module vduckdb

// DuckDB's public duckdb_string_t is a 16 byte union. The value is passed
// through DuckDB's own string accessors, including for BLOB vectors.
struct ChunkString {
	length  u32
	prefix  u32
	payload voidptr
}

type ChunkStringLength = fn (ChunkString) u32
type ChunkStringData = fn (&ChunkString) &u8
type ChunkValid = fn (voidptr, u64) bool

const chunk_data = ProjectHandle(load_duckdb_symbol('duckdb_vector_get_data'))
const chunk_validity = ProjectHandle(load_duckdb_symbol('duckdb_vector_get_validity'))
const chunk_valid = ChunkValid(load_duckdb_symbol('duckdb_validity_row_is_valid'))
const chunk_string_length = ChunkStringLength(load_duckdb_symbol('duckdb_string_t_length'))
const chunk_string_data = ChunkStringData(load_duckdb_symbol('duckdb_string_t_data'))

struct NativeChunkColumn {
	kind     int
	data     voidptr
	validity voidptr
}

@[heap]
pub struct NativeChunk {
pub:
	rows u64
mut:
	raw     voidptr
	columns []NativeChunkColumn
}

// read_chunk opens a vector result chunk. Do not mix vector reads with
// legacy cell access for the same result.
pub fn (result &NativeResult) read_chunk(index u64) !&NativeChunk {
	if result.destroyed {
		return error('DuckDB result is closed.')
	}
	chunk := projection_get_chunk(*result.raw, index)
	if chunk == unsafe { nil } {
		return error('Could not read a materialized DuckDB result chunk.')
	}
	mut columns := []NativeChunkColumn{cap: int(result.column_count())}
	for col in u64(0) .. result.column_count() {
		vector := projection_vector(chunk, col)
		columns << NativeChunkColumn{
			kind:     result.column_type(col)
			data:     chunk_data(vector)
			validity: chunk_validity(vector)
		}
	}
	return &NativeChunk{
		rows:    projection_size(chunk)
		raw:     chunk
		columns: columns
	}
}

fn read_chunk_bytes(data voidptr, row u64) []u8 {
	item := unsafe { &(&ChunkString(data))[row] }
	size := chunk_string_length(*item)
	if size == 0 {
		return []u8{}
	}
	return unsafe { chunk_string_data(item).vbytes(int(size)).clone() }
}

pub fn (chunk &NativeChunk) value(column int, row u64) !NativeValue {
	if chunk.raw == unsafe { nil } || row >= chunk.rows || column < 0 || column >= chunk.columns.len {
		return error('DuckDB chunk cell is out of bounds.')
	}
	cell := chunk.columns[column]
	if cell.kind == 36 || (cell.validity != unsafe { nil } && !chunk_valid(cell.validity, row)) {
		return NativeValue(NativeNull{})
	}
	data := cell.data
	return match cell.kind {
		1 { NativeValue(unsafe { (&u8(data))[row] != 0 }) }
		2 { NativeValue(i64(unsafe { (&i8(data))[row] })) }
		3 { NativeValue(i64(unsafe { (&i16(data))[row] })) }
		4 { NativeValue(i64(unsafe { (&i32(data))[row] })) }
		5 { NativeValue(unsafe { (&i64(data))[row] }) }
		6 { NativeValue(u64(unsafe { (&u8(data))[row] })) }
		7 { NativeValue(u64(unsafe { (&u16(data))[row] })) }
		8 { NativeValue(u64(unsafe { (&u32(data))[row] })) }
		9 { NativeValue(unsafe { (&u64(data))[row] }) }
		10 { NativeValue(f64(unsafe { (&f32(data))[row] })) }
		11 { NativeValue(unsafe { (&f64(data))[row] }) }
		17 { NativeValue(read_chunk_bytes(data, row).bytestr()) }
		18 { NativeValue(read_chunk_bytes(data, row)) }
		else { return error('DuckDB vector type ${cell.kind} must be projected before reading.') }
	}
}

pub fn (mut chunk NativeChunk) close() {
	if chunk.raw != unsafe { nil } {
		projection_destroy_chunk(&chunk.raw)
		chunk.raw = unsafe { nil }
	}
}
