module regex

fn test_hir_fixed_literals_render_as_escaped_alternation() {
	hir := Hir.from_fixed_literals(['a.c', 'x'])
	assert hir.to_regex() == r'a\.c|x'
	assert hir.is_alternation_literal()
}

fn test_hir_non_matching_bytes_literal_and_class() {
	config := Config.default()

	literal := Hir.from_pattern('a', config)
	assert sparse(literal.non_matching_bytes()) == sparse_except([u8(`a`)])

	class := Hir.from_pattern(r'[ab]', config)
	assert sparse(class.non_matching_bytes()) == sparse_except([u8(`a`), `b`])
}

fn test_hir_non_matching_bytes_dot() {
	config := Config.default()
	hir := Hir.from_pattern('.', config)
	assert sparse(hir.non_matching_bytes()) == sparse_unicode_dot(false)

	mut dotall := Config.default()
	dotall.dot_matches_new_line = true
	dotall_hir := Hir.from_pattern('.', dotall)
	assert sparse(dotall_hir.non_matching_bytes()) == sparse_unicode_dot(true)
}

fn test_configured_hir_line_terminator_suppressed_for_haystack_anchor() {
	mut config := Config.default()
	config.line_terminator = matcher.LineTerminator.byte(`\n`)
	chir := config.build_many([r'\Afoo']) or { panic(err) }
	if _ := chir.line_terminator() {
		assert false
	} else {
		assert true
	}
}

fn test_configured_hir_whole_line_wraps_hir() {
	config := Config.default()
	chir := config.build_many(['foo']) or { panic(err) }
	wrapped := chir.into_whole_line()
	assert wrapped.hir().to_regex() == r'(?m:^)(?:foo)(?m:$)'
}
