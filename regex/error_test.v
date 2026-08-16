module regex

fn test_error_messages() {
	assert Error.regex('bad regex').msg() == 'bad regex'
	assert Error.new(ErrorKind.not_allowed('\n')).msg() == 'the literal "\\n" is not allowed in a regex'
	assert Error.new(ErrorKind.invalid_line_terminator(0xff)).msg() == 'line terminators must be ASCII, but "\\xFF" is not'
	assert Error.new(ErrorKind.banned(0)).msg() == 'pattern contains "\\0" but it is impossible to match'
}
