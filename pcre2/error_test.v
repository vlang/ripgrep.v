module pcre2

fn test_error_messages() {
	err := Error.regex_message('bad pcre2 regex')
	assert err.msg() == 'bad pcre2 regex'
	assert err.kind().is_regex()
	assert err.kind().text() == 'bad pcre2 regex'
}
