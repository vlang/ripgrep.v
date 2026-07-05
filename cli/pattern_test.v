module cli

import os

fn test_pattern_from_bytes_reports_valid_prefix() {
	pat := [u8(`a`), `b`, `c`, 0xff, `x`, `y`, `z`]
	pattern_from_bytes(pat) or {
		perr := err as InvalidPatternError
		assert perr.valid_up_to() == usize(3)
		assert perr.msg().contains(r'abc\xFFxyz')
		return
	}
	assert false, 'expected invalid UTF-8 pattern'
}

fn test_pattern_from_os_reports_valid_prefix() {
	pat := [u8(`a`), `b`, `c`, 0xff, `x`, `y`, `z`].bytestr()
	pattern_from_os(pat) or {
		perr := err as InvalidPatternError
		assert perr.valid_up_to() == usize(3)
		return
	}
	assert false, 'expected invalid UTF-8 pattern'
}

fn test_pattern_from_bytes_accepts_utf8() {
	assert pattern_from_bytes('abcxyz'.bytes())! == 'abcxyz'
}

fn test_patterns_from_path_reads_lines() {
	path := os.join_path(os.temp_dir(), 'ripgrep_v_patterns_from_path_${os.getpid()}.txt')
	os.write_file(path, 'Sherlock\nHolmes') or { panic(err.msg()) }
	defer {
		os.rm(path) or {}
	}
	assert patterns_from_path(path)! == ['Sherlock', 'Holmes']
}
