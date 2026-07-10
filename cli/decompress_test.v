module cli

import io
import os

fn test_decompression_try_associate_keeps_relative_program_on_non_windows() {
	$if !windows {
		mut builder := DecompressionMatcherBuilder.new()
		builder.defaults(false)
		builder.try_associate('*.foo', 'definitely-not-a-real-ripgrep-v-command', ['-d'])!
		matcher := builder.build()!
		cmd := matcher.command('sample.foo') or { panic('missing decompression command') }

		assert cmd.program == 'definitely-not-a-real-ripgrep-v-command'
		assert cmd.args == ['-d']
	}
}

fn test_decompression_command_prefers_last_matching_glob() {
	$if !windows {
		mut builder := DecompressionMatcherBuilder.new()
		builder.defaults(false)
		builder.try_associate('*.foo', 'first-command', ['first'])!
		builder.try_associate('*.foo', 'second-command', ['second'])!
		matcher := builder.build()!
		cmd := matcher.command('sample.foo') or { panic('missing decompression command') }

		assert cmd.program == 'second-command'
		assert cmd.args == ['second']
	}
}

fn test_decompression_reader_builder_has_default_matcher() {
	$if !windows {
		builder := DecompressionReaderBuilder.new()
		assert builder.get_matcher().has_command('sample.gz')
	}
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
