module meta

fn test_literal_nul_is_not_a_parser_terminator() {
	re := compile('^\x00$') or { panic(err) }
	assert re.find('\x00') != none
	assert re.find('') == none
	assert re.find('abc') == none
}
