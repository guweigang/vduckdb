module vduckdb

fn test_native_projection_converts_materialized_batches_once() ! {
	mut database := open_native_database(':memory:')!
	defer { database.close() }
	mut conn := database.connect()!
	defer { conn.disconnect() }
	mut created := conn.run('CREATE SEQUENCE calls', [], {})!
	created.destroy()

	number := '12345678901234567890123456789012345678901234567890'
	mut src := conn.run("SELECT nextval('calls') AS duplicate,
		CASE WHEN i % 3 = 0 THEN NULL WHEN i % 3 = 1 THEN '${number}'::BIGNUM ELSE '-${number}'::BIGNUM END AS duplicate,
		'a'||chr(0)||'b' AS nul_text, [1,2] AS items FROM range(5003) t(i)", [], {})!
	defer { src.destroy() }
	assert src.row_count() == 5003
	assert src.column_name(0) == 'duplicate'
	assert src.column_name(1) == 'duplicate'
	mut projection := src.open_projection([1, 2, 3])!
	defer { projection.close() }

	mut row := i64(0)
	mut chunks := 0
	for {
		mut chunk := projection.next_chunk()!
		if chunk == unsafe { nil } { break }
		chunks++
		for i in u64(0) .. chunk.row_count() {
			assert chunk.int64(0, i) == row + 1
			if row % 3 == 0 {
				assert chunk.is_null(1, i)
			} else {
				assert chunk.blob(1, i).bytestr() == if row % 3 == 1 {
					number
				} else {
					'-${number}'
				}
			}
			assert chunk.blob(2, i) == [u8(97), 0, 98]
			assert chunk.blob(3, i).bytestr() == '[1, 2]'
			row++
		}
		chunk.destroy()
	}
	assert row == 5003
	assert chunks > 1
	mut check := conn.run("SELECT currval('calls')", [], {})!
	defer { check.destroy() }
	assert check.int64(0, 0) == 5003
}

fn test_native_projection_distinguishes_an_empty_result_from_legacy_access() ! {
	mut database := open_native_database(':memory:')!
	defer { database.close() }
	mut conn := database.connect()!
	defer { conn.disconnect() }

	mut empty := conn.run('SELECT 1::BIGNUM WHERE FALSE', [], {})!
	defer { empty.destroy() }
	mut projection := empty.open_projection([0])!
	defer { projection.close() }
	assert projection.next_chunk()! == unsafe { nil }

	mut legacy := conn.run("SELECT 42, 'value'", [], {})!
	defer { legacy.destroy() }
	assert legacy.int64(0, 0) == 42
	if mut invalid := legacy.open_projection([1]) {
		invalid.close()
		return error('expected legacy-access mismatch')
	} else {
		assert err.msg() == 'DuckDB projection must open before reading legacy result cells.'
	}

	mut source := conn.run('SELECT 1::BIGNUM', [], {})!
	defer { source.destroy() }
	if mut invalid := source.open_projection([1]) {
		invalid.close()
		return error('expected out-of-bounds column rejection')
	} else {
		assert err.msg() == 'DuckDB projection column is out of bounds.'
	}
}
