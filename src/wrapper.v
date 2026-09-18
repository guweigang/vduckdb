module vduckdb

import dl

struct Database {
pub:
	db voidptr
}

struct Connection {
pub:
	conn voidptr
}

struct Config {
pub mut:
	config voidptr
}

enum Type {
	duckdb_type_invalid         = 0
	duckdb_type_boolean
	duckdb_type_tinyint
	duckdb_type_smallint
	duckdb_type_integer
	duckdb_type_bigint
	duckdb_type_utinyint
	duckdb_type_usmallint
	duckdb_type_uinteger
	duckdb_type_ubigint
	duckdb_type_float
	duckdb_type_double
	duckdb_type_timestamp
	duckdb_type_date
	duckdb_type_time
	duckdb_type_interval
	duckdb_type_hugeint
	duckdb_type_varchar
	duckdb_type_blob
	duckdb_type_decimal
	duckdb_type_timestamp_s
	duckdb_type_timestamp_ms
	duckdb_type_timestamp_ns
	duckdb_type_enum
	duckdb_type_list
	duckdb_type_struct
	duckdb_type_map
	duckdb_type_uuid
	duckdb_type_union
	duckdb_type_bit
	duckdb_type_time_tz
	duckdb_type_timestamp_tz
	duckdb_type_uhugeint        = 32
	duckdb_type_array           = 33
	duckdb_type_any             = 34
	duckdb_type_bignum          = 35
	duckdb_type_sqlnull         = 36
	duckdb_type_string_literal  = 37
	duckdb_type_integer_literal = 38
	duckdb_type_time_ns         = 39
}

struct Column {
pub:
	deprecated_data     ?voidptr
	deprecated_nullmask ?bool
	deprecated_type     ?Type
	deprecated_name     ?&char
	internal_data       voidptr
}

struct Result {
pub:
	deprecated_column_count  u64
	deprecated_row_count     u64
	deprecated_rows_changed  u64
	deprecated_columns       voidptr
	deprecated_error_message voidptr
	internal_data            voidptr
}

pub enum State {
	duckdbsuccess = 0
	duckdberror   = 1
}

struct String {
pub:
	data &char
	size u64
}

struct HugeInt {
pub:
	lower u64
	upper i64
}

struct Decimal {
pub:
	width u8
	scale u8
	value HugeInt
}

struct Date {
pub:
	days i32
}

struct Time {
pub:
	micros i64
}

struct Interval {
pub:
	months i32
	days   i32
	micros i64
}

type FNOpen = fn (&char, &Database) State

type FNOpenExt = fn (&char, &Database, Config, char) State

type FNConnect = fn (&Database, &Connection) State

type FNDisconnect = fn (&Connection)

type FNClose = fn (&Database)

type FNQuery = fn (&Connection, &char, &Result) State

type FNCount = fn (&Result) u64

type FNColName = fn (&Result, u64) &char

type FNColType = fn (&Result, u64) Type

type FNDestroyRes = fn (&Result)

type FNValueBoolean = fn (&Result, u64, u64) bool

type FNValueInt8 = fn (&Result, u64, u64) i8

type FNValueInt16 = fn (&Result, u64, u64) i16

type FNValueInt32 = fn (&Result, u64, u64) i32

type FNValueInt64 = fn (&Result, u64, u64) i64

type FNValueFloat = fn (&Result, u64, u64) f32

type FNValueDouble = fn (&Result, u64, u64) f64

type FNValueVarchar = fn (&Result, u64, u64) &char

type FNValueHugeInt = fn (&Result, u64, u64) HugeInt

type FNValueDecimal = fn (&Result, u64, u64) Decimal

type FNValueHugeIntToDouble = fn (HugeInt) f64

type FNValueDate = fn (&Result, u64, u64) Date

type FNValueTime = fn (&Result, u64, u64) Time

type FNValueTimestamp = fn (&Result, u64, u64) Time

type FNValueInterval = fn (&Result, u64, u64) Interval

type FNValueString = fn (&Result, u64, u64) String

type FNResultError = fn (&Result) &char

type FNVoidPtr = fn (voidptr)

type FNVersion = fn () &char

const handle = dl.open_opt(library_file_path, dl.rtld_lazy) or { unsafe { nil } }

// Keep the handle in a local value: V 0.5.2 otherwise passes the address of
// this global voidptr to dlsym instead of the dynamic library handle.
fn load_duckdb_symbol(name string) voidptr {
	local_handle := handle
	return dl.sym_opt(local_handle, name) or { unsafe { nil } }
}
const duckdb_open = FNOpen(load_duckdb_symbol('duckdb_open'))
const duckdb_open_ext = FNOpenExt(load_duckdb_symbol('duckdb_open_ext'))
const duckdb_connect = FNConnect(load_duckdb_symbol('duckdb_connect'))
const duckdb_disconnect = FNDisconnect(load_duckdb_symbol('duckdb_disconnect'))
const duckdb_close = FNClose(load_duckdb_symbol('duckdb_close'))
const duckdb_query = FNQuery(load_duckdb_symbol('duckdb_query'))
const duckdb_row_count = FNCount(load_duckdb_symbol('duckdb_row_count'))
const duckdb_column_count = FNCount(load_duckdb_symbol('duckdb_column_count'))
const duckdb_column_chars = FNColName(load_duckdb_symbol('duckdb_column_name'))
const duckdb_column_type = FNColType(load_duckdb_symbol('duckdb_column_type'))
const duckdb_destroy_result = FNDestroyRes(load_duckdb_symbol('duckdb_destroy_result'))
// Returning values
const duckdb_value_boolean = FNValueBoolean(load_duckdb_symbol('duckdb_value_boolean'))
const duckdb_value_int8 = FNValueInt8(load_duckdb_symbol('duckdb_value_int8'))
const duckdb_value_int16 = FNValueInt16(load_duckdb_symbol('duckdb_value_int16'))
const duckdb_value_int32 = FNValueInt32(load_duckdb_symbol('duckdb_value_int32'))
const duckdb_value_int64 = FNValueInt64(load_duckdb_symbol('duckdb_value_int64'))
const duckdb_value_float = FNValueFloat(load_duckdb_symbol('duckdb_value_float'))
const duckdb_value_double = FNValueDouble(load_duckdb_symbol('duckdb_value_double'))
const duckdb_value_varchar = FNValueVarchar(load_duckdb_symbol('duckdb_value_varchar'))
const duckdb_value_str = FNValueString(load_duckdb_symbol('duckdb_value_string'))
const duckdb_value_hugeint = FNValueHugeInt(load_duckdb_symbol('duckdb_value_hugeint'))
const duckdb_hugeint_to_double = FNValueHugeIntToDouble(load_duckdb_symbol('duckdb_hugeint_to_double'))
const duckdb_value_decimal = FNValueDecimal(load_duckdb_symbol('duckdb_value_decimal'))
const duckdb_value_dt = FNValueDate(load_duckdb_symbol('duckdb_value_date'))
const duckdb_value_time = FNValueTime(load_duckdb_symbol('duckdb_value_time'))
const duckdb_value_timestamp = FNValueTimestamp(load_duckdb_symbol('duckdb_value_timestamp'))
const duckdb_value_interval = FNValueInterval(load_duckdb_symbol('duckdb_value_interval'))
const duckdb_result_error = FNResultError(load_duckdb_symbol('duckdb_result_error'))
const duckdb_free = FNVoidPtr(load_duckdb_symbol('duckdb_free'))
const duckdb_lib_version = FNVersion(load_duckdb_symbol('duckdb_library_version'))
const native_prepare = FNPrepare(load_duckdb_symbol('duckdb_prepare'))
const native_destroy_prepare = FNDestroyPrepare(load_duckdb_symbol('duckdb_destroy_prepare'))
const native_prepare_error = FNPrepareError(load_duckdb_symbol('duckdb_prepare_error'))
const native_nparams = FNNparams(load_duckdb_symbol('duckdb_nparams'))
const native_bind_parameter_index = FNBindParameterIndex(load_duckdb_symbol('duckdb_bind_parameter_index'))
const native_bind_boolean = FNBindBoolean(load_duckdb_symbol('duckdb_bind_boolean'))
const native_bind_int64 = FNBindI64(load_duckdb_symbol('duckdb_bind_int64'))
const native_bind_uint64 = FNBindU64(load_duckdb_symbol('duckdb_bind_uint64'))
const native_bind_double = FNBindF64(load_duckdb_symbol('duckdb_bind_double'))
const native_bind_varchar_length = FNBindVarcharLength(load_duckdb_symbol('duckdb_bind_varchar_length'))
const native_bind_blob = FNBindBlob(load_duckdb_symbol('duckdb_bind_blob'))
const native_bind_null = FNBindNull(load_duckdb_symbol('duckdb_bind_null'))
const native_execute_prepared = FNExecutePrepared(load_duckdb_symbol('duckdb_execute_prepared'))
const native_value_is_null = FNValueNull(load_duckdb_symbol('duckdb_value_is_null'))
const native_value_uint64 = FNValueU64(load_duckdb_symbol('duckdb_value_uint64'))
const native_value_blob = FNValueBlob(load_duckdb_symbol('duckdb_value_blob'))
const native_rows_changed = FNCount(load_duckdb_symbol('duckdb_rows_changed'))

// duckdb_value_string retrieves a VARCHAR value from a query result.
// Returns 'NULL' if the value is nil.
pub fn duckdb_value_string(result &Result, col u64, row u64) string {
	ret := unsafe { duckdb_value_varchar(result, col, row) }
	if ret == unsafe { nil } {
		return 'NULL'
	}
	s := unsafe { (*ret).vstring().clone() }
	duckdb_free(ret)
	return s
}

// duckdb_value_date retrieves a DATE value from a query result.
// Returns the date formatted as YYYY-MM-DD.
pub fn duckdb_value_date(result &Result, col u64, row u64) string {
	days := unsafe { duckdb_value_dt(result, col, row).days }
	cdate := start_date.add_days(days)
	return cdate.strftime('%Y-%m-%d')
}

// duckdb_query_error retrieves the error message from a failed query execution.
pub fn duckdb_query_error(result &Result) string {
	ret := duckdb_result_error(result)
	if ret == unsafe { nil } {
		return ''
	}
	return unsafe { ret.vstring() }.clone()
}

// duckdb_column_name retrieves the name of a column from a query result.
pub fn duckdb_column_name(result &Result, col_idx u64) string {
	ret := duckdb_column_chars(result, col_idx)
	if ret == unsafe { nil } {
		return ''
	}
	return unsafe { ret.vstring() }.clone()
}

// duckdb_library_version retrieves the version of the linked DuckDB library.
pub fn duckdb_library_version() string {
	ret := duckdb_lib_version()
	if ret == unsafe { nil } {
		return ''
	}
	return unsafe { ret.vstring() }.clone()
}
