module vduckdb

import dl
import time
import os

fn get_libname() string {
	// Check current directory first
	if os.is_file(dl.get_libname('./libduckdb')) {
		return dl.get_libname('./libduckdb')
	}
	// Check environment variable
	if os.is_file(dl.get_libname('${os.getenv('LIBDUCKDB_DIR')}/libduckdb')) {
		return dl.get_libname('${os.getenv('LIBDUCKDB_DIR')}/libduckdb')
	}
	// Check Homebrew macOS standard locations
	if os.is_file('/opt/homebrew/opt/duckdb/lib/libduckdb.dylib') {
		return '/opt/homebrew/opt/duckdb/lib/libduckdb.dylib'
	}
	if os.is_file('/opt/homebrew/lib/libduckdb.dylib') {
		return '/opt/homebrew/lib/libduckdb.dylib'
	}
	if os.is_file('/usr/local/lib/libduckdb.dylib') {
		return '/usr/local/lib/libduckdb.dylib'
	}
	// Check system default search
	return dl.get_libname('libduckdb')
}

const library_file_path = get_libname()
const start_date = time.Time{
	year:  1970
	month: 1
	day:   1
}
