module cli

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

fn test_pattern_from_bytes_accepts_utf8() {
	assert pattern_from_bytes('abcxyz'.bytes())! == 'abcxyz'
}
