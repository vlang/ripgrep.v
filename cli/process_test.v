module cli

import io

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
