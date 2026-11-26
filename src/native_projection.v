module vduckdb

@[heap]
struct ProjectionInput {
	source &Result
mut:
	chunk voidptr
	read  bool
}

type ProjectCreate = fn () voidptr
type ProjectDestroy = fn (&voidptr)
type ProjectName = fn (voidptr, &char)
type ProjectExtra = fn (voidptr, voidptr, voidptr)
type ProjectUnary = fn (voidptr)
type ProjectScan = fn (voidptr, voidptr)
type ProjectRegister = fn (voidptr, voidptr) State
type ProjectSetUnary = fn (voidptr, ProjectUnary)
type ProjectSetScan = fn (voidptr, ProjectScan)
type ProjectHandle = fn (voidptr) voidptr
type ProjectLogical = fn (&Result, u64) voidptr
type ProjectBindCol = fn (voidptr, &char, voidptr)
type ProjectChunkCount = fn (Result) u64
type ProjectChunk = fn (Result, u64) voidptr
type ProjectSetCount = fn (voidptr, u64)
type ProjectCount = fn (voidptr) u64
type ProjectVector = fn (voidptr, u64) voidptr
type ProjectReference = fn (voidptr, voidptr)

const projection_create = ProjectCreate(load_duckdb_symbol('duckdb_create_table_function'))
const projection_destroy = ProjectDestroy(load_duckdb_symbol('duckdb_destroy_table_function'))
const projection_set_name = ProjectName(load_duckdb_symbol('duckdb_table_function_set_name'))
const projection_set_extra = ProjectExtra(load_duckdb_symbol('duckdb_table_function_set_extra_info'))
const projection_set_bind = ProjectSetUnary(load_duckdb_symbol('duckdb_table_function_set_bind'))
const projection_set_init = ProjectSetUnary(load_duckdb_symbol('duckdb_table_function_set_init'))
const projection_set_scan = ProjectSetScan(load_duckdb_symbol('duckdb_table_function_set_function'))
const projection_register = ProjectRegister(load_duckdb_symbol('duckdb_register_table_function'))
const projection_bind_input = ProjectHandle(load_duckdb_symbol('duckdb_bind_get_extra_info'))
const projection_scan_input = ProjectHandle(load_duckdb_symbol('duckdb_function_get_extra_info'))
const projection_logical = ProjectLogical(load_duckdb_symbol('duckdb_column_logical_type'))
const projection_destroy_logical = ProjectDestroy(load_duckdb_symbol('duckdb_destroy_logical_type'))
const projection_bind_col = ProjectBindCol(load_duckdb_symbol('duckdb_bind_add_result_column'))
const projection_threads = ProjectSetCount(load_duckdb_symbol('duckdb_init_set_max_threads'))
const projection_chunk_count = ProjectChunkCount(load_duckdb_symbol('duckdb_result_chunk_count'))
const projection_get_chunk = ProjectChunk(load_duckdb_symbol('duckdb_result_get_chunk'))
const projection_cols = ProjectCount(load_duckdb_symbol('duckdb_data_chunk_get_column_count'))
const projection_size = ProjectCount(load_duckdb_symbol('duckdb_data_chunk_get_size'))
const projection_set_size = ProjectSetCount(load_duckdb_symbol('duckdb_data_chunk_set_size'))
const projection_destroy_chunk = ProjectDestroy(load_duckdb_symbol('duckdb_destroy_data_chunk'))
const projection_vector = ProjectVector(load_duckdb_symbol('duckdb_data_chunk_get_vector'))
const projection_reference = ProjectReference(load_duckdb_symbol('duckdb_vector_reference_vector'))

fn bind_projection(info voidptr) {
	input := unsafe { &ProjectionInput(projection_bind_input(info)) }
	for column in u64(0) .. duckdb_column_count(input.source) {
		name := 'c${column}'
		mut logical := projection_logical(input.source, column)
		projection_bind_col(info, name.str, logical)
		projection_destroy_logical(&logical)
	}
}

fn init_projection(info voidptr) {
	projection_threads(info, 1)
}

fn scan_projection(info voidptr, output voidptr) {
	mut input := unsafe { &ProjectionInput(projection_scan_input(info)) }
	if input.read {
		projection_set_size(output, 0)
		return
	}
	input.read = true
	for column in u64(0) .. projection_cols(input.chunk) {
		projection_reference(projection_vector(output, column), projection_vector(input.chunk, column))
	}
	projection_set_size(output, projection_size(input.chunk))
}

@[heap]
pub struct NativeProjection {
mut:
	source     &NativeResult
	database   &NativeDatabase
	connection &NativeConnection
	state      &ProjectionInput
	sql        string
	next       u64
	count      u64
	closed     bool
}

// open_projection borrows the materialized result, before any legacy cell
// access. It converts selected columns to length-preserving UTF-8 blobs.
pub fn (result &NativeResult) open_projection(text_columns []int) !&NativeProjection {
	if result.destroyed {
		return error('DuckDB result is closed.')
	}
	if unsafe { voidptr(projection_reference) == nil || voidptr(projection_get_chunk) == nil } {
		return error('DuckDB runtime does not support materialized result projection.')
	}
	count := projection_chunk_count(*result.raw)
	if count == 0 && result.row_count() > 0 {
		return error('DuckDB projection must open before reading legacy result cells.')
	}
	column_count := int(result.column_count())
	for column in text_columns {
		if column < 0 || column >= column_count {
			return error('DuckDB projection column is out of bounds.')
		}
	}
	mut database := open_native_database(':memory:')!
	mut connection := database.connect() or {
		database.close()
		return err
	}
	state := &ProjectionInput{ source: result.raw }
	mut table_fn := projection_create()
	defer { projection_destroy(&table_fn) }
	projection_set_name(table_fn, c'vduckdb_materialized_chunk')
	projection_set_extra(table_fn, state, unsafe { nil })
	projection_set_bind(table_fn, bind_projection)
	projection_set_init(table_fn, init_projection)
	projection_set_scan(table_fn, scan_projection)
	if projection_register(connection.raw.conn, table_fn) != .duckdbsuccess {
		connection.disconnect()
		database.close()
		return error('Could not register the DuckDB materialized result reader.')
	}
	mut columns := []string{cap: column_count}
	for i in 0 .. column_count {
		columns << if i in text_columns { 'encode(CAST(c${i} AS VARCHAR))' } else { 'c${i}' }
	}
	return &NativeProjection{
		source:     result
		database:   database
		connection: connection
		state:      state
		count:      count
		sql:        'SELECT ${columns.join(', ')} FROM vduckdb_materialized_chunk()'
	}
}

// next_chunk returns one converted chunk or nil at EOF. The caller owns the
// converted result and must destroy it after use.
pub fn (mut projection NativeProjection) next_chunk() !&NativeResult {
	if projection.closed || projection.source.destroyed {
		return error('DuckDB result projection is closed.')
	}
	if projection.next >= projection.count { return unsafe { nil } }
	mut chunk := projection_get_chunk(*projection.source.raw, projection.next)
	if chunk == unsafe { nil } {
		return error('Could not read a materialized DuckDB result chunk.')
	}
	defer {
		projection.state.chunk = unsafe { nil }
		projection_destroy_chunk(&chunk)
	}
	projection.state.chunk = chunk
	projection.state.read = false
	result := projection.connection.run(projection.sql, [], {})!
	projection.next++
	return result
}

pub fn (mut projection NativeProjection) close() {
	if projection.closed { return }
	projection.connection.disconnect()
	projection.database.close()
	projection.closed = true
}
