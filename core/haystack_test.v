module core

import ignore
import os
import rand

fn haystack_tmpdir() string {
	root := os.join_path(os.temp_dir(), 'ripgrep-v-haystack')
	path := os.join_path(root, rand.ulid())
	os.mkdir_all(path) or { panic(err.msg()) }
	return path
}

fn test_haystack_builds_explicit_file() {
	td := haystack_tmpdir()
	defer {
		os.rmdir_all(td) or {}
	}
	file := os.join_path(td, 'file.txt')
	os.write_file(file, 'abc') or { panic(err.msg()) }
	mut walk := ignore.WalkBuilder.new(file).build()
	result := walk.next() or { panic('expected a walk result') }
	builder := HaystackBuilder.new()
	hay := builder.build_from_result(result) or { panic('expected haystack') }
	assert *hay.path() == file
	assert hay.is_explicit()
	assert !hay.is_stdin()
}

fn test_haystack_omits_directory() {
	td := haystack_tmpdir()
	defer {
		os.rmdir_all(td) or {}
	}
	mut walk := ignore.WalkBuilder.new(td).build()
	result := walk.next() or { panic('expected a walk result') }
	builder := HaystackBuilder.new()
	if _ := builder.build_from_result(result) {
		assert false
	}
}

fn test_haystack_strip_dot_prefix() {
	td := haystack_tmpdir()
	defer {
		os.rmdir_all(td) or {}
	}
	cwd := os.getwd()
	os.chdir(td) or { panic(err.msg()) }
	defer {
		os.chdir(cwd) or {}
	}
	os.write_file('file.txt', 'abc') or { panic(err.msg()) }
	mut walk := ignore.WalkBuilder.new('./file.txt').build()
	result := walk.next() or { panic('expected a walk result') }
	mut builder := HaystackBuilder.new()
	builder.strip_dot_prefix(true)
	hay := builder.build_from_result(result) or { panic('expected haystack') }
	assert *hay.path() == 'file.txt'
}
