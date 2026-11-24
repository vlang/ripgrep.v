module meta

fn test_literal_nul_is_not_a_parser_terminator() {
	re := compile('^\x00$') or { panic(err) }
	assert re.find('\x00') != none
	assert re.find('') == none
	assert re.find('abc') == none
}

fn test_regex_worker_keeps_the_compiled_program_alive() {
	mut re := compile('(?P<name>hello)') or { panic(err) }
	worker := spawn find_with_regex_clone(re.clone())
	re.drop()
	assert worker.wait()
}

fn find_with_regex_clone(re Regex) bool {
	matched := re.find('say hello') or { return false }
	return re.group_by_name(matched, 'name') == 'hello'
}
