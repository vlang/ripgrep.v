module cli

import io
import os

fn test_command_reader_streams_stdout() {
	$if windows {
		return
	}
	mut cmd := Command.new('sh')
	cmd.args(['-c', 'printf hello; sleep 0.05; printf world'])
	mut rdr := CommandReader.new(cmd) or { panic(err.msg()) }
	mut out := []u8{len: 16}
	nread := rdr.read(mut out) or { panic(err.msg()) }
	mut all := []u8{}
	all << out[..nread]
	for {
		mut buf := []u8{len: 16}
		n := rdr.read(mut buf) or {
			if err is io.Eof {
				break
			}
			panic(err.msg())
		}
		all << buf[..n]
	}
	assert all.bytestr() == 'helloworld'
}

fn test_command_reader_stdin_path_feeds_child() {
	$if windows {
		return
	}
	path := os.join_path(os.temp_dir(), 'ripgrep_v_command_reader_stdin_${os.getpid()}.txt')
	os.write_file(path, 'preprocessor stdin\n') or { panic(err.msg()) }
	defer {
		os.rm(path) or {}
	}
	mut cmd := Command.new('cat')
	cmd.stdin_path(path)
	mut rdr := CommandReader.new(cmd) or { panic(err.msg()) }
	mut all := []u8{}
	for {
		mut buf := []u8{len: 16}
		n := rdr.read(mut buf) or {
			if err is io.Eof {
				break
			}
			panic(err.msg())
		}
		all << buf[..n]
	}
	assert all.bytestr() == 'preprocessor stdin\n'
}

fn test_command_reader_error_includes_stderr() {
	$if windows {
		return
	}
	mut cmd := Command.new('sh')
	cmd.args(['-c', 'printf problem >&2; exit 7'])
	mut rdr := CommandReader.new(cmd) or { panic(err.msg()) }
	mut buf := []u8{len: 16}
	rdr.read(mut buf) or {
		assert err.msg().contains('problem')
		return
	}
	panic('expected command stderr error')
}

fn test_command_reader_close_drains_large_stderr() {
	$if windows {
		return
	}
	mut cmd := Command.new('sh')
	cmd.args(['-c', 'dd if=/dev/zero bs=1024 count=128 1>&2 2>/dev/null; exit 7'])
	mut rdr := CommandReader.new(cmd) or { panic(err.msg()) }
	rdr.close() or {
		assert err.msg().contains('---')
		return
	}
	panic('expected command stderr error')
}

fn test_command_reader_close_ignores_successful_stderr() {
	$if windows {
		return
	}
	mut cmd := Command.new('sh')
	cmd.args(['-c', 'dd if=/dev/zero bs=1024 count=128 1>&2 2>/dev/null; exit 0'])
	mut rdr := CommandReader.new(cmd) or { panic(err.msg()) }
	rdr.close() or { panic(err.msg()) }
}

fn test_command_reader_search_read_then_close_reports_stderr() {
	$if windows {
		return
	}
	os.find_abs_path_of_executable('gzip') or { return }
	path := os.join_path(os.temp_dir(), 'ripgrep_v_command_reader_bad_gzip_${os.getpid()}.gz')
	os.write_file(path, 'not gzip\n') or { panic(err.msg()) }
	defer {
		os.rm(path) or {}
	}
	mut cmd := Command.new('gzip')
	cmd.args(['-d', '-c', path])
	mut rdr := CommandReader.new(cmd) or { panic(err.msg()) }
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
	panic('expected gzip stderr error')
}

fn test_command_reader_search_read_pointer_then_close_reports_stderr() {
	$if windows {
		return
	}
	os.find_abs_path_of_executable('gzip') or { return }
	path := os.join_path(os.temp_dir(), 'ripgrep_v_command_reader_bad_gzip_ptr_${os.getpid()}.gz')
	os.write_file(path, 'not gzip\n') or { panic(err.msg()) }
	defer {
		os.rm(path) or {}
	}
	mut cmd := Command.new('gzip')
	cmd.args(['-d', '-c', path])
	mut rdr := CommandReader.new(cmd) or { panic(err.msg()) }
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
	panic('expected gzip stderr error')
}
