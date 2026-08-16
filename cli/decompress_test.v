module cli

import io
import os

fn restore_decompression_path(previous ?string) {
	if path := previous {
		os.setenv('PATH', path, true)
	} else {
		os.unsetenv('PATH')
	}
}

fn test_decompression_resolve_binary_keeps_relative_program_on_non_windows() {
	$if !windows {
		resolved := resolve_binary('definitely-not-a-real-ripgrep-v-command')!
		assert resolved == 'definitely-not-a-real-ripgrep-v-command'
	}
}

fn test_decompression_try_associate_resolves_program_from_path() {
	previous := os.getenv_opt('PATH')
	td := os.join_path(os.temp_dir(), 'ripgrep_v_decompress_path_${os.getpid()}')
	os.mkdir_all(td) or { panic(err.msg()) }
	program := os.join_path(td, 'decompress-test-bin')
	os.write_file(program, '') or { panic(err.msg()) }
	defer {
		os.rmdir_all(td) or {}
		restore_decompression_path(previous)
	}
	os.setenv('PATH', td, true)

	mut builder := DecompressionMatcherBuilder.new()
	builder.defaults(false)
	builder.try_associate('*.foo', 'decompress-test-bin', ['-d'])!
	matcher := builder.build()!
	cmd := matcher.command('sample.foo') or { panic('missing decompression command') }
	assert cmd.program == program
	assert cmd.args == ['-d']
}

fn test_decompression_try_associate_reports_missing_program() {
	previous := os.getenv_opt('PATH')
	td := os.join_path(os.temp_dir(), 'ripgrep_v_decompress_missing_${os.getpid()}')
	os.mkdir_all(td) or { panic(err.msg()) }
	defer {
		os.rmdir_all(td) or {}
		restore_decompression_path(previous)
	}
	os.setenv('PATH', td, true)

	mut builder := DecompressionMatcherBuilder.new()
	builder.try_associate('*.foo', 'missing-decompressor', []string{}) or {
		assert err.msg() == 'missing-decompressor: could not find executable in PATH'
		return
	}
	assert false
}

fn test_decompression_try_resolve_binary_checks_exe_extension() {
	previous := os.getenv_opt('PATH')
	td := os.join_path(os.temp_dir(), 'ripgrep_v_decompress_extension_${os.getpid()}')
	os.mkdir_all(td) or { panic(err.msg()) }
	program := os.join_path(td, 'decompress-test-bin.exe')
	os.write_file(program, '') or { panic(err.msg()) }
	defer {
		os.rmdir_all(td) or {}
		restore_decompression_path(previous)
	}
	os.setenv('PATH', td, true)

	resolved := try_resolve_binary('decompress-test-bin') or { panic(err.msg()) }
	assert resolved == program
}

fn test_decompression_try_resolve_binary_reports_missing_path() {
	previous := os.getenv_opt('PATH')
	defer {
		restore_decompression_path(previous)
	}
	os.unsetenv('PATH')

	try_resolve_binary('decompress-test-bin') or {
		assert err.msg() == 'system PATH environment variable not found'
		return
	}
	assert false
}

fn test_decompression_command_prefers_last_matching_glob() {
	$if !windows {
		mut builder := DecompressionMatcherBuilder.new()
		builder.defaults(false)
		first_program := os.join_path(os.temp_dir(), 'first-command')
		second_program := os.join_path(os.temp_dir(), 'second-command')
		builder.try_associate('*.foo', first_program, ['first'])!
		builder.try_associate('*.foo', second_program, ['second'])!
		matcher := builder.build()!
		cmd := matcher.command('sample.foo') or { panic('missing decompression command') }

		assert cmd.program == second_program
		assert cmd.args == ['second']
	}
}

fn test_decompression_reader_builder_has_default_matcher() {
	$if !windows {
		builder := DecompressionReaderBuilder.new()
		assert builder.get_matcher().has_command('sample.gz')
	}
}

fn test_decompression_passthru_close_is_noop() {
	path := os.join_path(os.temp_dir(), 'ripgrep_v_decompress_passthru_${os.getpid()}.plain')
	os.write_file(path, 'abc') or { panic(err.msg()) }
	defer {
		os.rm(path) or {}
	}
	mut rdr := DecompressionReader.new(path) or { panic(err.msg()) }
	rdr.close() or { panic(err.msg()) }
	mut buf := []u8{len: 3}
	nread := rdr.read(mut buf) or { panic(err.msg()) }
	assert nread == 3
	assert buf.bytestr() == 'abc'
}

fn test_decompression_reader_reports_command_stderr() {
	$if windows {
		return
	}
	path := bad_gzip_path() or { return }
	defer {
		os.rm(path) or {}
	}
	mut rdr := DecompressionReader.new(path) or { panic(err.msg()) }
	mut buf := []u8{len: 128}
	for {
		rdr.read(mut buf) or {
			if err is io.Eof {
				break
			}
			if !err.msg().contains('not in gzip format') {
				panic('unexpected gzip read error: ${err.msg()}')
			}
			return
		}
	}
	rdr.close() or {
		if !err.msg().contains('not in gzip format') {
			panic('unexpected gzip close error: ${err.msg()}')
		}
		rdr.close() or { panic('second close should be a no-op: ${err.msg()}') }
		return
	}
	panic('expected decompression stderr error')
}

fn test_decompression_reader_search_read_then_close_reports_stderr() {
	$if windows {
		return
	}
	path := bad_gzip_path() or { return }
	defer {
		os.rm(path) or {}
	}
	mut rdr := DecompressionReader.new(path) or { panic(err.msg()) }
	mut buf := []u8{len: 128}
	for {
		rdr.read_for_search(mut buf) or {
			if err is io.Eof {
				break
			}
			panic(err.msg())
		}
	}
	rdr.close() or {
		if !err.msg().contains('not in gzip format') {
			panic('unexpected gzip close error: ${err.msg()}')
		}
		rdr.close() or { panic('second close should be a no-op: ${err.msg()}') }
		return
	}
	panic('expected decompression stderr error')
}

fn test_decompression_reader_search_read_pointer_then_close_reports_stderr() {
	$if windows {
		return
	}
	path := bad_gzip_path() or { return }
	defer {
		os.rm(path) or {}
	}
	mut rdr := DecompressionReader.new(path) or { panic(err.msg()) }
	mut rdr_ptr := &rdr
	mut buf := []u8{len: 128}
	for {
		rdr_ptr.read_for_search(mut buf) or {
			if err is io.Eof {
				break
			}
			panic(err.msg())
		}
	}
	rdr_ptr.close() or {
		if !err.msg().contains('not in gzip format') {
			panic('unexpected gzip close error: ${err.msg()}')
		}
		return
	}
	panic('expected decompression stderr error')
}

fn bad_gzip_path() ?string {
	os.find_abs_path_of_executable('gzip') or { return none }
	path := os.join_path(os.temp_dir(), 'ripgrep_v_bad_gzip_${os.getpid()}.gz')
	os.write_file(path, 'not gzip\n') or { panic(err.msg()) }
	return path
}
