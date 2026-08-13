module vduckdb

// NativeNull represents SQL NULL in a prepared statement binding.
pub struct NativeNull {}

// NativeValue is the dependency-free value contract accepted by DuckDB's
// prepared-statement API. Higher-level drivers map their own value types here.
pub type NativeValue = NativeNull | []u8 | bool | f64 | i64 | string | u64

pub struct NativeDatabase {
mut:
	raw    &Database = unsafe { nil }
	closed bool
}

pub struct NativeConnection {
mut:
	raw          &Connection = unsafe { nil }
	disconnected bool
}

pub struct NativeResult {
mut:
	raw       &Result = unsafe { nil }
	destroyed bool
}

struct NativePrepared {
mut:
	handle voidptr
}

struct NativeBlob {
	data voidptr
	size u64
}

type FNPrepare = fn (voidptr, &char, &NativePrepared) State

type FNDestroyPrepare = fn (&NativePrepared)

type FNPrepareError = fn (voidptr) &char

type FNNparams = fn (voidptr) u64

type FNBindParameterIndex = fn (voidptr, &u64, &char) State

type FNBindBoolean = fn (voidptr, u64, bool) State

type FNBindI64 = fn (voidptr, u64, i64) State

type FNBindU64 = fn (voidptr, u64, u64) State

type FNBindF64 = fn (voidptr, u64, f64) State

type FNBindVarcharLength = fn (voidptr, u64, &char, u64) State

type FNBindBlob = fn (voidptr, u64, voidptr, u64) State

type FNBindNull = fn (voidptr, u64) State

type FNExecutePrepared = fn (voidptr, &Result) State

type FNValueNull = fn (&Result, u64, u64) bool

type FNValueU64 = fn (&Result, u64, u64) u64

type FNValueBlob = fn (&Result, u64, u64) NativeBlob

fn require_native_library() ! {
	if handle == unsafe { nil } {
		return error('DuckDB runtime library not found at `${library_file_path}`.')
	}
}

// open_native_database opens one DuckDB database instance. Create multiple
// connections from this value when concurrent sessions must share one catalog
// and buffer manager.
pub fn open_native_database(path string) !&NativeDatabase {
	require_native_library()!
	raw := &Database{}
	if duckdb_open(path.str, raw) != .duckdbsuccess {
		return error('Could not open "${path}". Is it locked?')
	}
	return &NativeDatabase{
		raw: raw
	}
}

pub fn (database &NativeDatabase) connect() !&NativeConnection {
	if database.closed || database.raw == unsafe { nil } {
		return error('DuckDB database is closed.')
	}
	raw := &Connection{}
	if duckdb_connect(database.raw.db, raw) != .duckdbsuccess {
		return error('Could not create a DuckDB connection.')
	}
	return &NativeConnection{
		raw: raw
	}
}

pub fn (mut database NativeDatabase) close() {
	if !database.closed && database.raw != unsafe { nil } {
		duckdb_close(database.raw)
		database.raw = unsafe { nil }
	}
	database.closed = true
}

pub fn (mut connection NativeConnection) disconnect() {
	if !connection.disconnected && connection.raw != unsafe { nil } {
		duckdb_disconnect(connection.raw)
		connection.raw = unsafe { nil }
	}
	connection.disconnected = true
}

fn native_result_error(result &Result, fallback string) string {
	message := duckdb_query_error(result)
	return if message == '' { fallback } else { message }
}

fn prepared_error(prepared &NativePrepared, fallback string) string {
	message_ptr := native_prepare_error(prepared.handle)
	if message_ptr == unsafe { nil } {
		return fallback
	}
	return unsafe { message_ptr.vstring() }.clone()
}

fn bind_native_value(prepared &NativePrepared, index u64, value NativeValue, label string) ! {
	state := match value {
		NativeNull {
			native_bind_null(prepared.handle, index)
		}
		bool {
			native_bind_boolean(prepared.handle, index, value)
		}
		i64 {
			native_bind_int64(prepared.handle, index, value)
		}
		u64 {
			native_bind_uint64(prepared.handle, index, value)
		}
		f64 {
			native_bind_double(prepared.handle, index, value)
		}
		[]u8 {
			native_bind_blob(prepared.handle, index, unsafe { voidptr(value.data) }, u64(value.len))
		}
		string {
			native_bind_varchar_length(prepared.handle, index, value.str, u64(value.len))
		}
	}
	if state != .duckdbsuccess {
		return error(prepared_error(prepared, 'Failed to bind DuckDB parameter ${label}.'))
	}
}

fn (connection &NativeConnection) run_prepared(statement string, parameters []NativeValue, named_params map[string]NativeValue) !&NativeResult {
	if parameters.len > 0 && named_params.len > 0 {
		return error('DuckDB positional and named parameters cannot be mixed in one statement.')
	}
	prepared := &NativePrepared{}
	if native_prepare(connection.raw.conn, statement.str, prepared) != .duckdbsuccess {
		message := prepared_error(prepared, 'DuckDB prepare failed.')
		native_destroy_prepare(prepared)
		return error(message)
	}
	defer { native_destroy_prepare(prepared) }

	expected := native_nparams(prepared.handle)
	provided := if named_params.len > 0 { named_params.len } else { parameters.len }
	if expected != u64(provided) {
		return error('DuckDB statement expects ${expected} parameter(s), but ${provided} were provided.')
	}

	if named_params.len > 0 {
		mut bound_indexes := map[u64]bool{}
		for name, value in named_params {
			mut index := u64(0)
			if native_bind_parameter_index(prepared.handle, &index, name.str) != .duckdbsuccess
				|| index == 0 {
				return error(prepared_error(prepared, 'Unknown DuckDB named parameter `${name}`.'))
			}
			if index in bound_indexes {
				return error('DuckDB named parameter `${name}` resolves to an already bound parameter.')
			}
			bind_native_value(prepared, index, value, '`${name}`')!
			bound_indexes[index] = true
		}
	} else {
		for offset, value in parameters {
			index := u64(offset + 1)
			bind_native_value(prepared, index, value, '#${index}')!
		}
	}

	raw := &Result{}
	if native_execute_prepared(prepared.handle, raw) != .duckdbsuccess {
		message := native_result_error(raw, prepared_error(prepared,
			'DuckDB prepared statement execution failed.'))
		duckdb_destroy_result(raw)
		return error(message)
	}
	return &NativeResult{
		raw: raw
	}
}

pub fn (connection &NativeConnection) run(statement string, parameters []NativeValue, named_params map[string]NativeValue) !&NativeResult {
	if connection.disconnected || connection.raw == unsafe { nil } {
		return error('DuckDB connection is closed.')
	}
	if parameters.len > 0 || named_params.len > 0 {
		return connection.run_prepared(statement, parameters, named_params)
	}
	raw := &Result{}
	if duckdb_query(connection.raw.conn, statement.str, raw) != .duckdbsuccess {
		message := native_result_error(raw, 'DuckDB query failed.')
		duckdb_destroy_result(raw)
		return error(message)
	}
	return &NativeResult{
		raw: raw
	}
}

pub fn (result &NativeResult) row_count() u64 {
	return duckdb_row_count(result.raw)
}

pub fn (result &NativeResult) rows_changed() u64 {
	return native_rows_changed(result.raw)
}

pub fn (result &NativeResult) column_count() u64 {
	return duckdb_column_count(result.raw)
}

pub fn (result &NativeResult) column_name(index u64) string {
	return duckdb_column_name(result.raw, index)
}

pub fn (result &NativeResult) column_type(index u64) int {
	return int(duckdb_column_type(result.raw, index))
}

pub fn (result &NativeResult) is_null(column u64, row u64) bool {
	return native_value_is_null(result.raw, column, row)
}

pub fn (result &NativeResult) boolean(column u64, row u64) bool {
	return duckdb_value_boolean(result.raw, column, row)
}

pub fn (result &NativeResult) int64(column u64, row u64) i64 {
	return duckdb_value_int64(result.raw, column, row)
}

pub fn (result &NativeResult) uint64(column u64, row u64) u64 {
	return native_value_uint64(result.raw, column, row)
}

pub fn (result &NativeResult) float64(column u64, row u64) f64 {
	return duckdb_value_double(result.raw, column, row)
}

pub fn (result &NativeResult) text(column u64, row u64) string {
	return duckdb_value_string(result.raw, column, row)
}

pub fn (result &NativeResult) blob(column u64, row u64) []u8 {
	value := native_value_blob(result.raw, column, row)
	mut bytes := []u8{}
	if value.data != unsafe { nil } && value.size > 0 {
		bytes = unsafe { (&u8(value.data)).vbytes(int(value.size)).clone() }
	}
	if value.data != unsafe { nil } { duckdb_free(value.data) }
	return bytes
}

pub fn (mut result NativeResult) destroy() {
	if !result.destroyed && result.raw != unsafe { nil } {
		duckdb_destroy_result(result.raw)
		result.raw = unsafe { nil }
	}
	result.destroyed = true
}
