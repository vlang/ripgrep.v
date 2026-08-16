module regex

import matcher

fn roundtrip_line_term(pattern string, line_term matcher.LineTerminator) !string {
	mut config := Config.default()
	config.line_terminator = line_term
	return strip_line_terminator_from_match(pattern, config)
}

fn roundtrip(pattern string, byte u8) string {
	result := roundtrip_line_term(pattern, matcher.LineTerminator.byte(byte)) or { panic(err) }
	return result
}

fn roundtrip_crlf(pattern string) string {
	result := roundtrip_line_term(pattern, matcher.LineTerminator.crlf()) or { panic(err) }
	return result
}

fn roundtrip_err(pattern string, byte u8) bool {
	roundtrip_line_term(pattern, matcher.LineTerminator.byte(byte)) or { return true }
	return false
}

fn test_strip_line_terminator_various() {
	assert roundtrip(r'[a\n]', `\n`) == '[a]'
	assert roundtrip(r'[a\n]', `a`) == r'[\x0a]'
	assert roundtrip(r'[a\x0A]', `\n`) == '[a]'
	assert roundtrip(r'[a\u{A}]', `\n`) == '[a]'
	assert roundtrip_crlf(r'[a\n]') == '[a]'
	assert roundtrip_crlf(r'[a\r]') == '[a]'
	assert roundtrip_crlf(r'[a\r\n]') == '[a]'

	assert roundtrip(r'(?-u)\s', `a`) == r'(?-u)\s'
	mut expected_space := '(?-u)['.bytes()
	expected_space << ` `
	expected_space << `\t`
	expected_space << `\r`
	expected_space << u8(0x0b)
	expected_space << u8(0x0c)
	expected_space << `]`
	assert roundtrip(r'(?-u)\s', `\n`).bytes() == expected_space

	assert roundtrip_err(r'\n', `\n`)
	assert roundtrip_err(r'abc\n', `\n`)
	assert roundtrip_err(r'\nabc', `\n`)
	assert roundtrip_err(r'abc\nxyz', `\n`)
	assert roundtrip_err(r'\x0A', `\n`)
	assert roundtrip_err(r'\u000A', `\n`)
	assert roundtrip_err(r'\U0000000A', `\n`)
	assert roundtrip_err(r'\u{A}', `\n`)
	assert roundtrip_err(r'[\u{A}]', `\n`)
	assert roundtrip_err('\n', `\n`)
}
