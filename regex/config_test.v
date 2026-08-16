module regex

import matcher

fn test_config_fixed_literal_preserves_literal_hir_with_line_terminator() {
	mut config := Config.default()
	config.line_terminator = matcher.LineTerminator.byte(`\n`)
	patterns := ['foo'.to_owned()]
	chir := config.build_many(&patterns) or { panic(err.msg()) }
	assert chir.hir().is_alternation_literal()
	assert chir.hir().to_regex() == 'foo'
}

fn test_config_fixed_strings_skip_regex_only_ban_check() {
	mut config := Config.default()
	config.fixed_strings = true
	config.ban = u8(`x`)
	patterns := ['x'.to_owned()]
	chir := config.build_many(&patterns) or { panic(err.msg()) }
	assert chir.hir().is_alternation_literal()
	assert chir.hir().to_regex() == 'x'
}

fn test_config_uses_generated_clone() {
	mut config := Config.default()
	config.line_terminator = matcher.LineTerminator.crlf()
	config.ban = u8(0)
	cloned := config.clone()
	assert cloned.line_terminator == config.line_terminator
	assert cloned.ban == config.ban
	assert cloned.size_limit == config.size_limit
}

fn test_config_empty_patterns_never_match() {
	config := Config.default()
	patterns := []string{}
	chir := config.build_many(&patterns) or { panic(err.msg()) }
	compiled := chir.to_regex() or { panic(err.msg()) }
	if _ := compiled.find('') {
		assert false
	}
	if _ := compiled.find('abc') {
		assert false
	}
}
