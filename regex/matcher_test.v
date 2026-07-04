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
