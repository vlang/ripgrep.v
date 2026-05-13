module ignore

import os
import rand

const temp_dir_tries = 100

// A simple wrapper for creating a temporary directory that is
// automatically deleted when it's dropped.
//
// We use this in lieu of tempfile because tempfile brings in too many
// dependencies.
//
// This helper is translated from the Rust `#[cfg(test)]` module in
// `lib.rs`. It lives in a normal `.v` file because the current ownership
// frontend does not include sibling `_test.v` helpers when compiling a
// single translated `_test.v` directly.
struct TempDir {
	dir string
}

// Create a new empty temporary directory under the system's configured
// temporary directory.
fn TempDir.new() !TempDir {
	root := os.join_path(os.temp_dir(), 'rust-ignore')
	for _ in 0 .. temp_dir_tries {
		path := os.join_path(root, rand.ulid())
		if os.is_dir(path) {
			continue
		}
		os.mkdir_all(path)!
		return TempDir{
			dir: path
		}
	}
	return error('failed to create temp dir after ${temp_dir_tries} tries')
}

// Return the underlying path to this temporary directory.
fn (td &^a TempDir) path[^a]() &^a string {
	return &td.dir
}

fn (td TempDir) cleanup() {
	if td.dir != '' {
		os.rmdir_all(td.dir) or {}
	}
}

fn tmpdir() TempDir {
	return TempDir.new() or { panic(err.msg()) }
}
