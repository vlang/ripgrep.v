module regex

import matcher

fn extracted(pattern string) Seq {
	hir := Hir.from_pattern(pattern, Config.default())
	return Extractor.new().extract_untagged(&hir)
}

fn literal_strings(seq Seq) []string {
	lits := seq.literals() or { return []string{} }
	mut strings := []string{cap: lits.len}
	for lit in lits {
		strings << lit.bytes.bytestr()
	}
	return strings
}

fn test_inner_literal_extracts_required_literal_after_classes() {
	assert literal_strings(extracted(r'\wfoo\s')) == ['foo']
	assert literal_strings(extracted(r'[a-z](foo)(bar)[a-z]')) == ['foobar']
}

fn test_inner_literal_extracts_alternation_literals() {
	assert literal_strings(extracted(r'(?:abc|xyz)')) == ['abc', 'xyz']
	assert literal_strings(extracted(r'(?:|abc)')) == []string{}
}

fn test_inner_literal_prefers_longer_required_literal() {
	assert literal_strings(extracted(r'[a-z]+(ab|cd|ef)[a-z]+hiya[a-z]+')) == ['hiya']
}

fn test_inner_literal_declines_case_insensitive_patterns() {
	mut config := Config.default()
	config.line_terminator = matcher.LineTerminator.byte(`\n`)
	config.case_insensitive = true
	chir := ConfiguredHIR.new(config, [r'foo\w']) or { panic(err) }
	re := chir.to_regex() or { panic(err) }
	assert !(InnerLiterals.new(&chir, &re).one_regex() or { panic(err) }).has_value

	mut inline_config := Config.default()
	inline_config.line_terminator = matcher.LineTerminator.byte(`\n`)
	inline_chir := ConfiguredHIR.new(inline_config, [r'(?i:foo)\w']) or { panic(err) }
	inline_re := inline_chir.to_regex() or { panic(err) }
	assert !(InnerLiterals.new(&inline_chir, &inline_re).one_regex() or { panic(err) }).has_value
}
