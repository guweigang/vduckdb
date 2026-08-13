module vduckdb

import os

fn test_native_database_shares_committed_state_across_connections() ! {
	path := os.join_path(os.temp_dir(), 'vduckdb-shared-${os.getpid()}.duckdb')
	os.rm(path) or {}
	defer { os.rm(path) or {} }

	mut database := open_native_database(path)!
	defer { database.close() }
	mut writer := database.connect()!
	defer { writer.disconnect() }
	mut reader := database.connect()!
	defer { reader.disconnect() }

	mut created := writer.run('CREATE TABLE items (id BIGINT PRIMARY KEY, name VARCHAR);', [],
		map[string]NativeValue{})!
	created.destroy()
	mut inserted := writer.run('INSERT INTO items VALUES (?, ?);', [
		NativeValue(i64(1)),
		NativeValue('手机数码'),
	], map[string]NativeValue{})!
	inserted.destroy()
	mut updated := writer.run('UPDATE items SET name = ? WHERE id = ? AND name = ?;', [
		NativeValue('手机数码1'),
		NativeValue(i64(1)),
		NativeValue('手机数码'),
	], map[string]NativeValue{})!
	assert updated.rows_changed() == 1
	updated.destroy()

	mut result := reader.run('SELECT name FROM items WHERE id = ?;', [
		NativeValue(i64(1)),
	], map[string]NativeValue{})!
	assert result.row_count() == 1
	assert result.text(0, 0) == '手机数码1'
	result.destroy()
}

fn test_native_prepared_binding_preserves_scalar_null_and_blob_values() ! {
	mut database := open_native_database(':memory:')!
	defer { database.close() }
	mut connection := database.connect()!
	defer { connection.disconnect() }

	mut result := connection.run('SELECT ?::BOOLEAN, ?::BIGINT, ?::UBIGINT, ?::DOUBLE, ?::VARCHAR, ?::BLOB, ?::VARCHAR;', [
		NativeValue(true),
		NativeValue(i64(-42)),
		NativeValue(u64(42)),
		NativeValue(1.5),
		NativeValue('bound'),
		NativeValue([u8(0), 255, 16]),
		NativeValue(NativeNull{}),
	], map[string]NativeValue{})!
	assert result.boolean(0, 0)
	assert result.int64(1, 0) == -42
	assert result.uint64(2, 0) == 42
	assert result.float64(3, 0) == 1.5
	assert result.text(4, 0) == 'bound'
	assert result.blob(5, 0) == [u8(0), 255, 16]
	assert result.is_null(6, 0)
	result.destroy()
}
