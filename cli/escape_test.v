module cli

fn b(bytes []u8) []u8 {
	return bytes.clone()
}

fn test_escape_empty() {
	assert b([]u8{}) == unescape(r'')
	assert r'' == escape([]u8{})
}

fn test_escape_backslash() {
	assert b([`\\`]) == unescape(r'\\')
	assert r'\\' == escape([u8(`\\`)])
}

fn test_escape_nul() {
	assert b([u8(0)]) == unescape(r'\x00')
	assert b([u8(0)]) == unescape(r'\0')
	assert r'\0' == escape([u8(0)])
}

fn test_escape_newline() {
	assert b([u8(`\n`)]) == unescape(r'\n')
	assert r'\n' == escape([u8(`\n`)])
}

fn test_escape_tab() {
	assert b([u8(`\t`)]) == unescape(r'\t')
	assert r'\t' == escape([u8(`\t`)])
}

fn test_escape_carriage() {
	assert b([u8(`\r`)]) == unescape(r'\r')
	assert r'\r' == escape([u8(`\r`)])
}

fn test_escape_nothing_simple() {
	assert b([u8(`\\`), `a`]) == unescape(r'\a')
	assert b([u8(`\\`), `a`]) == unescape(r'\\a')
	assert r'\\a' == escape([u8(`\\`), `a`])
}

fn test_escape_nothing_hex0() {
	assert b([u8(`\\`), `x`]) == unescape(r'\x')
	assert b([u8(`\\`), `x`]) == unescape(r'\\x')
	assert r'\\x' == escape([u8(`\\`), `x`])
}

fn test_escape_nothing_hex1() {
	assert b([u8(`\\`), `x`, `z`]) == unescape(r'\xz')
	assert b([u8(`\\`), `x`, `z`]) == unescape(r'\\xz')
	assert r'\\xz' == escape([u8(`\\`), `x`, `z`])
}

fn test_escape_nothing_hex2() {
	assert b([u8(`\\`), `x`, `z`, `z`]) == unescape(r'\xzz')
	assert b([u8(`\\`), `x`, `z`, `z`]) == unescape(r'\\xzz')
	assert r'\\xzz' == escape([u8(`\\`), `x`, `z`, `z`])
}

fn test_escape_invalid_utf8() {
	assert r'\xFF' == escape([u8(0xff)])
	assert r'a\xFFb' == escape([u8(`a`), 0xff, `b`])
}
