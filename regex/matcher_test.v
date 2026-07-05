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

fn test_unicode_any_property() {
	matcher_ := RegexMatcherBuilder.new().build(r'Sherlock\p{Any}+?Holmes') or { panic(err) }
	assert matcher.is_match(matcher_, 'Sherlock\nHolmes'.bytes())!
	assert matcher.is_match(matcher_, 'Sherlock Watson Holmes'.bytes())!
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
