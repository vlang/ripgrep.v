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

fn test_word_uses_unicode_half_boundaries() {
	mut builder := RegexMatcherBuilder.new()
	builder.word(true)
	matcher_ := builder.build('Δ') or { panic(err) }
	assert matcher.is_match(matcher_, '-Δ-'.bytes())!
	assert !matcher.is_match(matcher_, 'Δβ'.bytes())!
	assert !matcher.is_match(matcher_, 'αΔ'.bytes())!

	lazy := builder.build('a+?') or { panic(err) }
	assert matcher.is_match(lazy, 'abc aaaa bc'.bytes())!
	non_word := builder.build(r'\W+') or { panic(err) }
	assert matcher.is_match(non_word, 'ABC !? spaced'.bytes())!
}

fn test_regex_matcher_ref_forwards_non_matching_bytes() {
	matcher_ := RegexMatcherBuilder.new().build('foo') or { panic(err) }
	ref_ := RegexMatcherRef.new(&matcher_)
	non_matching := ref_.non_matching_bytes() or { panic('expected non-matching byte set') }
	assert non_matching.contains(`\n`)
	assert !non_matching.contains(`f`)
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

fn test_non_unicode_dot_and_classes_match_invalid_utf8_bytes() {
	haystack := [u8(0xff)]
	unicode_dot := RegexMatcherBuilder.new().build('.') or { panic(err.msg()) }
	assert !matcher.is_match(unicode_dot, haystack)!

	mut bytes_builder := RegexMatcherBuilder.new()
	bytes_builder.unicode(false)
	byte_dot := bytes_builder.build('.') or { panic(err.msg()) }
	mat := byte_dot.find_at(haystack, 0)!.get() or { panic('expected byte dot match') }
	assert mat.start() == 0
	assert mat.end() == 1
	byte_class := bytes_builder.build(r'[\xFF]') or { panic(err.msg()) }
	assert matcher.is_match(byte_class, haystack)!
	negated := bytes_builder.build(r'[^\x00]') or { panic(err.msg()) }
	assert matcher.is_match(negated, haystack)!
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
		assert err.msg().contains('unrecognized flag')
	}
	if _ := RegexMatcherBuilder.new().build(r'a\Kb') {
		panic('expected unsupported escape error')
	} else {
		assert err.msg().contains('unrecognized escape sequence')
	}
	if _ := RegexMatcherBuilder.new().build(r'(*ACCEPT)') {
		panic('expected backtracking verb error')
	} else {
		assert err.msg().contains('repetition operator missing expression')
	}
	if _ := RegexMatcherBuilder.new().build(r'(?&name)') {
		panic('expected subroutine error')
	} else {
		assert err.msg().contains('unrecognized flag')
	}
	if _ := RegexMatcherBuilder.new().build(r'(?P=name)') {
		panic('expected named backreference error')
	} else {
		assert err.msg().contains('unrecognized flag')
	}
	if _ := RegexMatcherBuilder.new().build(r'\k<name>') {
		panic('expected named backreference escape error')
	} else {
		assert err.msg().contains('unrecognized escape sequence')
	}
}

fn test_fixed_strings_allow_pcre_syntax_as_literals() {
	mut builder := RegexMatcherBuilder.new()
	builder.fixed_strings(true)
	matcher_ := builder.build(r'(?=a)\1(?>a)\K') or { panic(err.msg()) }
	assert matcher.is_match(matcher_, r'xx(?=a)\1(?>a)\Kyy'.bytes())!
}

fn test_ascii_hex_class_matches_ascii_bytes() {
	matcher_ := RegexMatcherBuilder.new().build(r'[\x00-\x7F]+')!
	assert matcher.is_match(matcher_, 'abc'.bytes())!
	assert !matcher.is_match(matcher_, 'é'.bytes())!
	mut line_builder := RegexMatcherBuilder.new()
	line_builder.multi_line(true)
	line_builder.line_terminator(`\n`)
	line_matcher := line_builder.build(r'[\x00-\x7F]+')!
	assert matcher.is_match(line_matcher, 'abc'.bytes())!
	assert !matcher.is_match(line_matcher, 'é'.bytes())!
	cloned := line_matcher.clone()
	assert matcher.is_match(cloned, 'abc'.bytes())!
	assert !matcher.is_match(cloned, 'é'.bytes())!
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
	for pattern in [r'(?U)a+', r'(?i-m)a', r'(?x:a b)', r'(?-i:a)b', r'\Aabc', r'abc\z', r'\<abc',
		r'abc\>'] {
		matcher_ := RegexMatcherBuilder.new().build(pattern) or { panic(err.msg()) }
		assert matcher.is_match(matcher_, 'abc'.bytes())!
	}
}

fn test_rust_regex_greed_swap_global_scoped_and_builder() {
	for pattern in [r'(?U)a+', r'(?U:a+)'] {
		matcher_ := RegexMatcherBuilder.new().build(pattern)!
		mat := (matcher_.find_at('aaaa'.bytes(), 0)!).get() or { panic('missing match') }
		assert mat.end() == 1
	}
	mut builder := RegexMatcherBuilder.new()
	builder.swap_greed(true)
	matcher_ := builder.build(r'a+?')!
	mat := (matcher_.find_at('aaaa'.bytes(), 0)!).get() or { panic('missing match') }
	assert mat.end() == 4
}

fn test_rust_regex_ascii_class_compatibility() {
	for pattern in [r'\d+', r'\D+', r'\w+', r'\W+', r'\s+', r'\S+', r'[[:alpha:]]+', r'[^[:alpha:]]+',
		r'\pL+', r'\p{Letter}+', r'\p{gc=Lu}+', r'\p{ascii}+'] {
		matcher_ := RegexMatcherBuilder.new().build(pattern) or { panic(err.msg()) }
		assert matcher.is_match(matcher_, 'ABC 123'.bytes())!
	}
}

fn test_rust_regex_all_posix_ascii_classes() {
	cases := {
		'alnum':  'A1'
		'alpha':  'Az'
		'ascii':  '\u007f'
		'blank':  '\t '
		'cntrl':  '\u0001'
		'digit':  '19'
		'graph':  '!~'
		'lower':  'az'
		'print':  ' ~'
		'punct':  '!@'
		'space':  '\t\r '
		'upper':  'AZ'
		'word':   'A_9'
		'xdigit': 'aF9'
	}
	for name, text in cases {
		matcher_ := RegexMatcherBuilder.new().build('[[:${name}:]]+')!
		assert matcher.is_match(matcher_, text.bytes())!
	}
	not_digit := RegexMatcherBuilder.new().build(r'[^[:digit:]]+')!
	assert matcher.is_match(not_digit, 'abc'.bytes())!
	assert !matcher.is_match(not_digit, '123'.bytes())!
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

fn test_rust_regex_broad_unicode_properties() {
	cases := {
		r'\p{Emoji}+':                 '😀'
		r'\p{Script=Deseret}+':        '𐐀'
		r'\p{scx=Hiragana}+':          'ー'
		r'\p{Alphabetic}+':            'ᾀ'
		r'\p{Age=3.0}+':               '€'
		r'\p{Word_Break=Katakana}+':   'カ'
		r'\p{General_Category=Mark}+': '\u0301'
	}
	for pattern, text in cases {
		matcher_ := RegexMatcherBuilder.new().build(pattern) or {
			panic('${pattern}: ${err.msg()}')
		}
		assert matcher.is_match(matcher_, text.bytes())!
	}
	not_greek := RegexMatcherBuilder.new().build(r'[\P{Greek}]+') or { panic(err.msg()) }
	assert matcher.is_match(not_greek, 'Latin'.bytes())!
	assert !matcher.is_match(not_greek, 'Δ'.bytes())!
}

fn test_rust_regex_age_property_matches_codepoints_available_by_that_age() {
	mut builder := RegexMatcherBuilder.new()
	builder.multi_line(true)
	builder.line_terminator(`\n`)
	matcher_ := builder.build(r'\p{Age=6.0}+')!
	assert matcher.is_match(matcher_, 'abc'.bytes())!
	cloned := matcher_.clone()
	assert matcher.is_match(cloned, 'abc'.bytes())!
	candidate := cloned.find_candidate_line('abc\n'.bytes())!
	_ := candidate.get() or { panic('expected candidate') }
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

	greek_without_delta := RegexMatcherBuilder.new().build(r'[\p{Greek}--Δ]+') or {
		panic(err.msg())
	}
	assert matcher.is_match(greek_without_delta, 'δ'.bytes())!
	assert !matcher.is_match(greek_without_delta, 'Δ'.bytes())!
	assert !matcher.is_match(greek_without_delta, 'Latin'.bytes())!
	uppercase_greek := RegexMatcherBuilder.new().build(r'[\p{Greek}&&\p{Uppercase}]+') or {
		panic(err.msg())
	}
	assert matcher.is_match(uppercase_greek, 'Δ'.bytes())!
	assert !matcher.is_match(uppercase_greek, 'δ'.bytes())!
}

fn test_rust_regex_unicode_case_folding_scoped_flags_and_braced_hex() {
	class_matcher := RegexMatcherBuilder.new().build(r'(?i)[δkß]') or { panic(err.msg()) }
	for text in ['Δ', 'K', 'ẞ'] {
		assert matcher.is_match(class_matcher, text.bytes())!
	}
	scoped := RegexMatcherBuilder.new().build(r'(?i:δ(?-i:x))') or { panic(err.msg()) }
	assert matcher.is_match(scoped, 'Δx'.bytes())!
	assert !matcher.is_match(scoped, 'ΔX'.bytes())!
	hex := RegexMatcherBuilder.new().build(r'\x{394}') or { panic(err.msg()) }
	assert matcher.is_match(hex, 'Δ'.bytes())!
}

fn test_rust_regex_unicode_escape_forms() {
	for pattern in [r'\u{3B1}+', r'\u03B1+', r'\U000003B1+'] {
		matcher_ := RegexMatcherBuilder.new().build(pattern)!
		assert matcher.is_match(matcher_, 'α'.bytes())!
	}
	if _ := RegexMatcherBuilder.new().build(r'\Qabc\E') {
		panic('expected quote escape rejection')
	} else {
		assert err.msg().contains('unrecognized escape sequence')
	}
}

fn test_rust_regex_ascii_control_escapes() {
	patterns := [r'\a', r'\f', r'\v', r'[\a]', r'[\f]', r'[\v]']
	controls := [[u8(0x07)], [u8(0x0c)], [u8(0x0b)], [u8(0x07)],
		[u8(0x0c)], [u8(0x0b)]]
	for i, pattern in patterns {
		matcher_ := RegexMatcherBuilder.new().build(pattern)!
		assert matcher.is_match(matcher_, controls[i])!
		assert !matcher.is_match(matcher_, pattern[1..2].bytes())!
	}
}

fn test_rust_regex_character_class_escapes() {
	tests := {
		r'[\d]':        ['5']
		r'[^\d]':       ['a']
		r'[\w]':        ['_', 'α']
		r'[\W]':        [' ']
		r'[\s]':        [' ', '\t']
		r'[\S]':        ['a']
		r'[\p{Greek}]': ['α', 'Δ']
		r'[\P{Greek}]': ['a']
	}
	for pattern, haystacks in tests {
		matcher_ := RegexMatcherBuilder.new().build(pattern) or { panic(err.msg()) }
		for haystack in haystacks {
			assert matcher.is_match(matcher_, haystack.bytes())!
		}
	}
	for pattern in [r'[\b]', r'[\B]', r'[\A]', r'[\z]'] {
		if _ := RegexMatcherBuilder.new().build(pattern) {
			panic('expected character class escape rejection for ${pattern}')
		} else {
			assert err.msg().contains('invalid escape sequence found in character class')
		}
	}
	punctuation := {
		r'[]a]': [']', 'a']
		r'[-a]': ['-', 'a']
		r'[a-]': ['a', '-']
		r'[\-]': ['-']
	}
	for pattern, haystacks in punctuation {
		matcher_ := RegexMatcherBuilder.new().build(pattern) or { panic(err.msg()) }
		for haystack in haystacks {
			assert matcher.is_match(matcher_, haystack.bytes())!
		}
	}
}

fn test_default_regex_skips_malformed_utf8_in_unicode_mode() {
	haystack := [u8(`A`), 0x80, `B`, 0xc0, 0xaf, `C`, 0xe0, 0x80, 0x80, `D`, 0xed, 0xa0, 0x80,
		`E`, 0xf4, 0x90, 0x80, 0x80, `F`, 0xc2, 0xa2, `G`]
	unicode_dot := RegexMatcherBuilder.new().build('.') or { panic(err.msg()) }
	expected := [
		matcher.Match.new(usize(0), usize(1)),
		matcher.Match.new(usize(2), usize(3)),
		matcher.Match.new(usize(5), usize(6)),
		matcher.Match.new(usize(9), usize(10)),
		matcher.Match.new(usize(13), usize(14)),
		matcher.Match.new(usize(18), usize(19)),
		matcher.Match.new(usize(19), usize(21)),
		matcher.Match.new(usize(21), usize(22)),
	]
	mut at := usize(0)
	for expected_match in expected {
		actual := unicode_dot.find_at(haystack, at)!.get() or {
			panic('expected Unicode dot match')
		}
		assert actual == expected_match
		at = actual.end()
	}
	assert (unicode_dot.find_at(haystack, at)!).is_none()

	non_x := RegexMatcherBuilder.new().build('[^x]') or { panic(err.msg()) }
	for start in [usize(1), 3, 6, 10, 14] {
		actual := non_x.find_at(haystack, start)!.get() or {
			panic('expected valid match after malformed UTF-8')
		}
		assert actual.start() > start
	}

	byte_dot := RegexMatcherBuilder.new().build(r'(?-u:.)') or { panic(err.msg()) }
	invalid := byte_dot.find_at(haystack, 1)!.get() or { panic('expected byte-mode dot match') }
	assert invalid == matcher.Match.new(usize(1), usize(2))
}

fn test_regex_vm_grows_backtracking_workspace_without_false_negative() {
	pattern := '^' + 'a?'.repeat(1300) + 'b$'
	matcher_ := RegexMatcherBuilder.new().build(pattern)!
	assert matcher.is_match(matcher_, ('a'.repeat(1300) + 'b').bytes())!
}

fn test_regex_unicode_ranges_remain_compact_and_case_fold() {
	matcher_ := RegexMatcherBuilder.new().build(r'(?i)[Α-Ω]+') or { panic(err.msg()) }
	assert matcher.is_match(matcher_, 'δ'.bytes())!
	assert !matcher.is_match(matcher_, 'я'.bytes())!
	broad := RegexMatcherBuilder.new().build('[ -😀]') or { panic(err.msg()) }
	assert matcher.is_match(broad, '😀'.bytes())!
}

fn test_regex_compile_size_and_nest_limits_are_enforced() {
	mut size_builder := RegexMatcherBuilder.new()
	size_builder.size_limit(1024)
	if _ := size_builder.build('a{1000}') {
		panic('expected compiled regex size limit error')
	} else {
		assert err.msg().contains('compiled regex exceeds size limit of 1024')
	}
	mut nest_builder := RegexMatcherBuilder.new()
	nest_builder.nest_limit(2)
	if _ := nest_builder.build('(((a)))') {
		panic('expected regex nest limit error')
	} else {
		assert err.msg().contains('exceed the maximum number of nested parentheses/brackets (2)')
	}
}

fn test_regex_vm_memoizes_ambiguous_repetition_states() {
	mut builder := RegexMatcherBuilder.new()
	builder.dfa_size_limit(0)
	matcher_ := builder.build(r'^(a|aa)*b$')!
	assert !matcher.is_match(matcher_, 'a'.repeat(20_000).bytes())!
}

fn test_rust_regex_parse_errors_reject_invalid_captures_ranges_and_properties() {
	invalid := {
		r'(?<1>a)':            'invalid capture group character'
		r'(?P<x>a)(?P<x>b)':   'duplicate capture group name'
		r'[z-a]':              'invalid character class range'
		r'\p{NoSuchProperty}': 'Unicode property not found'
		r'[':                  'unclosed character class'
		r'a{4,2}':             'invalid repetition count range'
		r'*a':                 'repetition operator missing expression'
		r'(?q:a)':             'unrecognized flag'
	}
	for pattern, expected in invalid {
		if _ := RegexMatcherBuilder.new().build(pattern) {
			panic('expected parse error for ${pattern}')
		} else {
			assert err.msg().starts_with('regex parse error:\n    (?:${pattern})\n')
			assert err.msg().contains('error: ${expected}')
		}
	}
}

fn test_build_wrapper_parentheses_match_ripgrep_issue_2480() {
	matcher_ := RegexMatcherBuilder.new().build(')(') or { panic(err.msg()) }
	assert matcher.is_match(matcher_, ''.bytes())!
}

fn test_rust_regex_empty_alternatives_and_byte_offset_empty_matches() {
	for pattern in ['', r'a|', r'|a', r'()'] {
		empty := RegexMatcherBuilder.new().build(pattern) or { panic(err.msg()) }
		found := empty.find_at('Δ'.bytes(), 1)!
		mat := found.get() or { panic('expected empty match for ${pattern}') }
		assert mat.start() == 1
		assert mat.end() == 1
	}
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

fn test_rust_regex_word_boundary_variants_are_distinct_and_unicode_aware() {
	start := RegexMatcherBuilder.new().build(r'\b{start}Δ') or { panic(err.msg()) }
	assert matcher.is_match(start, 'Δ'.bytes())!
	start_nonword := RegexMatcherBuilder.new().build(r'\b{start}-') or { panic(err.msg()) }
	assert !matcher.is_match(start_nonword, '-'.bytes())!

	end := RegexMatcherBuilder.new().build(r'Δ\b{end}') or { panic(err.msg()) }
	assert matcher.is_match(end, 'Δ'.bytes())!
	end_nonword := RegexMatcherBuilder.new().build(r'-\b{end}') or { panic(err.msg()) }
	assert !matcher.is_match(end_nonword, '-'.bytes())!

	start_half := RegexMatcherBuilder.new().build(r'\b{start-half}-') or { panic(err.msg()) }
	assert matcher.is_match(start_half, '-'.bytes())!
	end_half := RegexMatcherBuilder.new().build(r'-\b{end-half}') or { panic(err.msg()) }
	assert matcher.is_match(end_half, '-'.bytes())!
	assert !matcher.is_match(RegexMatcherBuilder.new().build(r'\b{end-half}x') or {
		panic(err.msg())
	}, 'Δx'.bytes())!

	unicode_boundary := RegexMatcherBuilder.new().build(r'\bΔ') or { panic(err.msg()) }
	assert matcher.is_match(unicode_boundary, 'Δ'.bytes())!
	ascii_boundary := RegexMatcherBuilder.new().build(r'(?-u:\b)Δ') or { panic(err.msg()) }
	assert !matcher.is_match(ascii_boundary, 'Δ'.bytes())!
}

fn test_rust_regex_unicode_word_uses_the_regex_syntax_perl_word_table() {
	word := RegexMatcherBuilder.new().build(r'^\w$') or { panic(err.msg()) }
	for text in ['\u0301', '\u200c', '\u203f'] {
		assert matcher.is_match(word, text.bytes())!
	}
	boundary := RegexMatcherBuilder.new().build('^\\b\u0301\\b$') or { panic(err.msg()) }
	assert matcher.is_match(boundary, '\u0301'.bytes())!
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
