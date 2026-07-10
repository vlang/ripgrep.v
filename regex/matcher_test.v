module regex

import matcher

// Test that enabling word matches does the right thing and demonstrate
// the difference between it and surrounding the regex in `\b`.
fn test_word() {
	mut builder := RegexMatcherBuilder.new()
	builder.word(true)
	matcher_ := builder.build(r'-2') or { panic(err) }
	assert matcher.is_match(matcher_, 'abc -2 foo'.bytes())!

	mut boundary_builder := RegexMatcherBuilder.new()
	boundary_builder.word(false)
	boundary_matcher := boundary_builder.build(r'\b-2\b') or { panic(err) }
	assert !matcher.is_match(boundary_matcher, 'abc -2 foo'.bytes())!
}

// Test that enabling a line terminator prevents it from matching through
// said line terminator.
fn test_line_terminator() {
	// This works, because there's no line terminator specified.
	matcher_ := RegexMatcherBuilder.new().build(r'abc\sxyz') or { panic(err) }
	assert matcher.is_match(matcher_, 'abc\nxyz'.bytes())!

	// This doesn't.
	mut builder := RegexMatcherBuilder.new()
	builder.line_terminator(`\n`)
	line_matcher := builder.build(r'abc\sxyz') or { panic(err) }
	assert !matcher.is_match(line_matcher, 'abc\nxyz'.bytes())!
}

// Ensure that the builder returns an error if a line terminator is set
// and the regex could not be modified to remove a line terminator.
fn test_line_terminator_error() {
	mut builder := RegexMatcherBuilder.new()
	builder.line_terminator(`\n`)
	if _ := builder.build(r'a\nz') {
		assert false
	}
}

// Test that enabling CRLF permits `$` to match at the end of a line.
fn test_line_terminator_crlf() {
	mut lf_builder := RegexMatcherBuilder.new()
	lf_builder.multi_line(true)
	lf_matcher := lf_builder.build(r'abc$') or { panic(err) }
	assert matcher.is_match(lf_matcher, 'abc\n'.bytes())!

	mut crlf_off_builder := RegexMatcherBuilder.new()
	crlf_off_builder.multi_line(true)
	crlf_off_matcher := crlf_off_builder.build(r'abc$') or { panic(err) }
	assert !matcher.is_match(crlf_off_matcher, 'abc\r\n'.bytes())!

	mut crlf_builder := RegexMatcherBuilder.new()
	crlf_builder.multi_line(true)
	crlf_builder.crlf(true)
	crlf_matcher := crlf_builder.build(r'abc$') or { panic(err) }
	assert matcher.is_match(crlf_matcher, 'abc\r\n'.bytes())!
	assert !matcher.is_match(crlf_matcher, 'abc xyz\r\n'.bytes())!
}

// Test that smart case works.
fn test_case_smart() {
	mut builder := RegexMatcherBuilder.new()
	builder.case_smart(true)
	matcher_ := builder.build(r'abc') or { panic(err) }
	assert matcher.is_match(matcher_, 'ABC'.bytes())!

	mut upper_builder := RegexMatcherBuilder.new()
	upper_builder.case_smart(true)
	upper_matcher := upper_builder.build(r'aBc') or { panic(err) }
	assert !matcher.is_match(upper_matcher, 'ABC'.bytes())!
}

fn test_case_insensitive_unicode_literal() {
	mut builder := RegexMatcherBuilder.new()
	builder.case_insensitive(true)
	matcher_ := builder.build('привет') or { panic(err) }
	assert matcher.is_match(matcher_, 'привет'.bytes())!
	assert matcher.is_match(matcher_, 'Привет'.bytes())!
	assert matcher.is_match(matcher_, 'ПрИвЕт'.bytes())!
}

fn test_case_insensitive_unicode_literal_disabled_without_unicode() {
	mut builder := RegexMatcherBuilder.new()
	builder.case_insensitive(true)
	builder.unicode(false)
	matcher_ := builder.build('Δ') or { panic(err) }
	assert !matcher.is_match(matcher_, 'δ'.bytes())!
}

fn test_build_many_and_literals() {
	matcher_ := RegexMatcherBuilder.new().build_many(['abc', 'xyz']) or { panic(err) }
	assert matcher.is_match(matcher_, '---xyz---'.bytes())!
	assert !matcher.is_match(matcher_, '---def---'.bytes())!

	mut builder := RegexMatcherBuilder.new()
	builder.fixed_strings(true)
	literal_matcher := builder.build_literals(['a.c']) or { panic(err) }
	assert matcher.is_match(literal_matcher, 'a.c'.bytes())!
	assert !matcher.is_match(literal_matcher, 'abc'.bytes())!
}

fn test_build_many_zero_patterns_never_matches() {
	matcher_ := RegexMatcherBuilder.new().build_many([]string{}) or { panic(err) }
	assert !matcher.is_match(matcher_, ''.bytes())!
	assert !matcher.is_match(matcher_, 'abc'.bytes())!
	candidate := matcher_.find_candidate_line('abc'.bytes()) or { panic(err) }
	if _ := candidate.get() {
		assert false
	}
}

fn test_candidate_lines() {
	base_matcher := RegexMatcherBuilder.new().build(r'\wfoo\s') or { panic(err) }
	base := base_matcher.find_candidate_line('afoo '.bytes()) or { panic(err) }
	base_kind := base.get() or { panic('expected match') }
	assert base_kind.is_confirmed()

	mut builder := RegexMatcherBuilder.new()
	builder.line_terminator(`\n`)
	line_matcher := builder.build(r'\wfoo\s') or { panic(err) }
	candidate := line_matcher.find_candidate_line('afoo '.bytes()) or { panic(err) }
	candidate_kind := candidate.get() or { panic('expected match') }
	assert candidate_kind.is_candidate()
}

fn test_candidate_lines_regression_1064() {
	mut builder := RegexMatcherBuilder.new()
	builder.multi_line(true)
	builder.line_terminator(`\n`)
	line_matcher := builder.build(r'a(.*c)') or { panic(err) }
	assert matcher.is_match(line_matcher, 'abc'.bytes())!
	candidate := line_matcher.find_candidate_line('abc'.bytes()) or { panic(err) }
	_ := candidate.get() or { panic('expected match') }
}

fn test_multiline_haystack_anchor_does_not_become_line_anchor() {
	mut builder := RegexMatcherBuilder.new()
	builder.multi_line(true)
	matcher_ := builder.build(r'\Abaz') or { panic(err) }
	assert matcher.is_match(matcher_, 'baz'.bytes())!
	assert !matcher.is_match(matcher_, 'a\nbaz'.bytes())!

	line_anchor := builder.build(r'^baz') or { panic(err) }
	assert matcher.is_match(line_anchor, 'a\nbaz'.bytes())!
}

fn test_candidate_lines_whole_line_literal_needs_confirmation() {
	mut builder := RegexMatcherBuilder.new()
	builder.line_terminator(`\n`)
	builder.whole_line(true)
	line_matcher := builder.build('foo') or { panic(err) }
	assert !matcher.is_match(line_matcher, 'foobar'.bytes())!
	candidate := line_matcher.find_candidate_line('foobar\n'.bytes()) or { panic(err) }
	candidate_kind := candidate.get() or { panic('expected literal candidate') }
	assert candidate_kind.is_candidate()
}

fn test_unicode_any_property() {
	matcher_ := RegexMatcherBuilder.new().build(r'Sherlock\p{Any}+?Holmes') or { panic(err) }
	assert matcher.is_match(matcher_, 'Sherlock\nHolmes'.bytes())!
	assert matcher.is_match(matcher_, 'Sherlock Watson Holmes'.bytes())!
	lowercase := RegexMatcherBuilder.new().build(r'Sherlock\p{any}+?Holmes') or { panic(err) }
	assert matcher.is_match(lowercase, 'Sherlock\nHolmes'.bytes())!
	not_any := RegexMatcherBuilder.new().build(r'\P{Any}') or { panic(err) }
	assert !matcher.is_match(not_any, 'Sherlock!'.bytes())!
	not_any_one_or_more := RegexMatcherBuilder.new().build(r'\P{Any}+') or { panic(err) }
	assert !matcher.is_match(not_any_one_or_more, 'Sherlock!'.bytes())!
}

fn test_capture_groups() {
	matcher_ := RegexMatcherBuilder.new().build(r'(?P<first>[A-Z][a-z]+) (?P<last>[A-Z][a-z]+)') or {
		panic(err)
	}
	found, groups := matcher_.capture_groups_at('Doctor Watson'.bytes(), 0)!
	mat := found.get() or { panic('expected match') }
	assert mat.start() == 0
	assert mat.end() == 13
	assert groups == ['Doctor', 'Watson']
	assert matcher_.capture_count() == 3
	assert matcher_.capture_index('first') == ?usize(1)
	assert matcher_.capture_index('last') == ?usize(2)
}

fn test_non_unicode_hex_byte_literal() {
	matcher_ := RegexMatcherBuilder.new().build(r'(?-u)\xFF') or { panic(err) }
	literal := matcher_.byte_literal or { panic('expected byte literal') }
	assert literal == [u8(0xff)]
	haystack := [u8(`q`), `u`, `u`, `x`, u8(0xff), `b`, `a`, `z`]
	found := matcher_.find_at(haystack, 0)!
	mat := found.get() or { panic('expected match') }
	assert mat.start() == 4
	assert mat.end() == 5
	assert matcher.is_match(matcher_, haystack)!
}

fn test_rejects_pcre_only_syntax() {
	if _ := RegexMatcherBuilder.new().build(r'(?=a)a') {
		panic('expected look-around error')
	} else {
		assert err.msg().contains('look-around')
	}
	if _ := RegexMatcherBuilder.new().build(r'(a)\1') {
		panic('expected backreference error')
	} else {
		assert err.msg().contains('backreferences')
	}
	if _ := RegexMatcherBuilder.new().build(r'(?>a)') {
		panic('expected atomic group error')
	} else {
		assert err.msg().contains('unsupported regex group syntax')
	}
	if _ := RegexMatcherBuilder.new().build(r'a\Kb') {
		panic('expected unsupported escape error')
	} else {
		assert err.msg().contains('unsupported escape sequence')
	}
	if _ := RegexMatcherBuilder.new().build(r'(*ACCEPT)') {
		panic('expected backtracking verb error')
	} else {
		assert err.msg().contains('unsupported regex group syntax')
	}
	if _ := RegexMatcherBuilder.new().build(r'(?&name)') {
		panic('expected subroutine error')
	} else {
		assert err.msg().contains('unsupported regex group syntax')
	}
	if _ := RegexMatcherBuilder.new().build(r'(?P=name)') {
		panic('expected named backreference error')
	} else {
		assert err.msg().contains('backreferences')
	}
	if _ := RegexMatcherBuilder.new().build(r'\k<name>') {
		panic('expected named backreference escape error')
	} else {
		assert err.msg().contains('unsupported escape sequence')
	}
}

fn test_fixed_strings_allow_pcre_syntax_as_literals() {
	mut builder := RegexMatcherBuilder.new()
	builder.fixed_strings(true)
	matcher_ := builder.build(r'(?=a)\1(?>a)\K') or { panic(err.msg()) }
	assert matcher.is_match(matcher_, r'xx(?=a)\1(?>a)\Kyy'.bytes())!
}

fn test_possessive_quantifier_syntax_matches_rust_regex() {
	for pattern in [r'a++a', r'a*+a', r'a?+a', r'a{1,3}+a'] {
		matcher_ := RegexMatcherBuilder.new().build(pattern) or { panic(err.msg()) }
		assert matcher.is_match(matcher_, 'aaaa'.bytes())!
	}
}

fn test_rust_regex_inline_flag_compatibility() {
	for pattern in [r'(?-i)a', r'(?x)a b', r'(?R)'] {
		matcher_ := RegexMatcherBuilder.new().build(pattern) or { panic(err.msg()) }
		assert matcher.is_match(matcher_, 'abc'.bytes())!
	}
}

fn test_rust_regex_crlf_flag_compatibility() {
	matcher_ := RegexMatcherBuilder.new().build(r'(?R)a$') or { panic(err.msg()) }
	assert matcher.is_match(matcher_, 'a\r'.bytes())!
	disabled := RegexMatcherBuilder.new().build(r'(?-R)$') or { panic(err.msg()) }
	assert matcher.is_match(disabled, 'a'.bytes())!
	grouped := RegexMatcherBuilder.new().build(r'(?R:a$)') or { panic(err.msg()) }
	assert matcher.is_match(grouped, 'a\r'.bytes())!
}

fn test_rust_regex_more_inline_and_anchor_compatibility() {
	for pattern in [r'(?U)a+', r'(?i-m)a', r'(?x:a b)', r'(?-i:a)b', r'\Aabc',
		r'abc\z', r'\<abc', r'abc\>'] {
		matcher_ := RegexMatcherBuilder.new().build(pattern) or { panic(err.msg()) }
		assert matcher.is_match(matcher_, 'abc'.bytes())!
	}
}

fn test_rust_regex_ascii_class_compatibility() {
	for pattern in [r'\d+', r'\D+', r'\w+', r'\W+', r'\s+', r'\S+', r'[[:alpha:]]+',
		r'[^[:alpha:]]+', r'\pL+', r'\p{Letter}+', r'\p{gc=Lu}+', r'\p{ascii}+'] {
		matcher_ := RegexMatcherBuilder.new().build(pattern) or { panic(err.msg()) }
		assert matcher.is_match(matcher_, 'ABC 123'.bytes())!
	}
}

fn test_rust_regex_common_unicode_class_compatibility() {
	for pattern in [r'\w+', r'\pL+', r'\p{Letter}+'] {
		matcher_ := RegexMatcherBuilder.new().build(pattern) or { panic(err.msg()) }
		assert matcher.is_match(matcher_, 'mañana'.bytes())!
		assert matcher.is_match(matcher_, 'κόσμος'.bytes())!
		assert matcher.is_match(matcher_, 'кириллица'.bytes())!
		assert matcher.is_match(matcher_, '漢字'.bytes())!
	}
	not_word := RegexMatcherBuilder.new().build(r'\W+') or { panic(err.msg()) }
	assert !matcher.is_match(not_word, 'mañana'.bytes())!
	assert !matcher.is_match(not_word, 'κόσμος'.bytes())!
	ascii := RegexMatcherBuilder.new().build(r'\p{ascii}+') or { panic(err.msg()) }
	assert matcher.is_match(ascii, 'foo bar'.bytes())!
	assert matcher.is_match(ascii, [u8(0)])!
	assert !matcher.is_match(ascii, 'κόσμος'.bytes())!
	not_ascii := RegexMatcherBuilder.new().build(r'\P{ascii}+') or { panic(err.msg()) }
	assert matcher.is_match(not_ascii, 'mañana'.bytes())!
	assert matcher.is_match(not_ascii, 'κόσμος'.bytes())!
	digit := RegexMatcherBuilder.new().build(r'\d+') or { panic(err.msg()) }
	assert matcher.is_match(digit, '१२३'.bytes())!
	space := RegexMatcherBuilder.new().build(r'\s+') or { panic(err.msg()) }
	assert matcher.is_match(space, rune(0x2003).str().bytes())!
}

fn test_negated_unicode_classes_do_not_match_invalid_utf8_empty() {
	haystack := [u8(`x`), `y`, `z`, 0xff]
	for pattern in [r'\W+', r'[^[:alpha:]]+'] {
		matcher_ := RegexMatcherBuilder.new().build(pattern) or { panic(err.msg()) }
		assert !matcher.is_match(matcher_, haystack)!
	}
}

fn test_rust_regex_greek_property_compatibility() {
	for pattern in [r'\p{Greek}+', r'\p{Script=Greek}+', r'[\p{Greek}]+'] {
		matcher_ := RegexMatcherBuilder.new().build(pattern) or { panic(err.msg()) }
		assert matcher.is_match(matcher_, 'Delta Δ'.bytes())!
		assert !matcher.is_match(matcher_, 'Delta'.bytes())!
	}
}

fn test_rust_regex_additional_script_property_compatibility() {
	cases := {
		r'\p{Han}+':      '漢字'
		r'\p{Cyrillic}+': 'кириллица'
		r'\p{Hiragana}+': 'ひらがな'
		r'\p{Katakana}+': 'カタカナ'
		r'\p{Hebrew}+':   'שלום'
		r'\p{Arabic}+':   'سلام'
	}
	for pattern, text in cases {
		matcher_ := RegexMatcherBuilder.new().build(pattern) or { panic(err.msg()) }
		assert matcher.is_match(matcher_, text.bytes())!
		assert !matcher.is_match(matcher_, 'abc'.bytes())!
	}
}

fn test_rust_regex_rejects_unsupported_unicode_properties() {
	for pattern in [r'\p{Emoji}', r'\p{Script=Deseret}', r'[\P{Greek}]'] {
		if _ := RegexMatcherBuilder.new().build(pattern) {
			panic('expected unsupported Unicode property error for ${pattern}')
		} else {
			assert err.msg().contains('Unicode property')
		}
	}
}

fn test_non_unicode_group_byte_literal() {
	matcher_ := RegexMatcherBuilder.new().build(r'(?-u:\xFF)') or { panic(err.msg()) }
	assert matcher.is_match(matcher_, [u8(0xff)])!
}

fn test_rust_regex_class_set_operations() {
	empty := RegexMatcherBuilder.new().build(r'[a&&b]') or { panic(err.msg()) }
	assert !matcher.is_match(empty, 'a'.bytes())!
	assert !matcher.is_match(empty, 'b'.bytes())!
	assert !matcher.is_match(empty, '!'.bytes())!

	diff := RegexMatcherBuilder.new().build(r'[a--b]') or { panic(err.msg()) }
	assert matcher.is_match(diff, 'a'.bytes())!
	assert !matcher.is_match(diff, 'b'.bytes())!

	symmetric := RegexMatcherBuilder.new().build(r'[a~~b]') or { panic(err.msg()) }
	assert matcher.is_match(symmetric, 'a'.bytes())!
	assert matcher.is_match(symmetric, 'b'.bytes())!

	consonants := RegexMatcherBuilder.new().build(r'[a-z&&[^aeiou]]+') or { panic(err.msg()) }
	assert matcher.is_match(consonants, 'bcdf'.bytes())!
	assert !matcher.is_match(consonants, 'aeiou'.bytes())!

	ascii_word := RegexMatcherBuilder.new().build(r'[\w&&\p{ascii}]+') or { panic(err.msg()) }
	assert matcher.is_match(ascii_word, 'abc_123'.bytes())!
	assert !matcher.is_match(ascii_word, 'Δ'.bytes())!
}

fn test_rust_regex_named_capture_angle_syntax() {
	matcher_ := RegexMatcherBuilder.new().build(r'(?<name>a)') or { panic(err.msg()) }
	assert matcher.is_match(matcher_, 'abc'.bytes())!
	assert matcher_.capture_index('name') == ?usize(1)
}

fn test_rust_regex_word_boundary_variants() {
	for pattern in [r'\b{start}abc', r'abc\b{end}', r'\b{start-half}abc', r'abc\b{end-half}'] {
		matcher_ := RegexMatcherBuilder.new().build(pattern) or { panic(err.msg()) }
		assert matcher.is_match(matcher_, 'abc'.bytes())!
	}
}

fn test_backend_normalized_patterns_with_line_terminator() {
	for pattern in [r'(?x)a b', r'\b{start}abc', r'abc\b{end}', r'\b{start-half}abc',
		r'abc\b{end-half}'] {
		mut builder := RegexMatcherBuilder.new()
		builder.line_terminator(`\n`)
		matcher_ := builder.build(pattern) or { panic(err.msg()) }
		candidate := matcher_.find_candidate_line('abc\n'.bytes())!
		kind := candidate.get() or { panic('expected candidate line') }
		assert kind.is_confirmed()
		assert matcher.is_match(matcher_, 'abc'.bytes())!
	}
}
