module pcre2

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

// Test that finding candidate lines works as expected.
fn test_candidate_lines() {
	matcher_ := RegexMatcherBuilder.new().build(r'\wfoo\s') or { panic(err) }
	m := matcher_.find_candidate_line('afoo '.bytes())!.get() or { panic('missing match') }
	assert m.is_confirmed()
}

fn test_fixed_strings_escape_meta_characters() {
	mut builder := RegexMatcherBuilder.new()
	builder.fixed_strings(true)
	matcher_ := builder.build(r'a.c') or { panic(err) }
	assert matcher.is_match(matcher_, 'a.c'.bytes())!
	assert !matcher.is_match(matcher_, 'abc'.bytes())!
}

fn test_capture_metadata() {
	matcher_ := RegexMatcherBuilder.new().build(r'(?P<name>ab)(c)') or { panic(err) }
	assert matcher_.capture_count() == 3
	assert matcher_.capture_index('name') or { usize(0) } == usize(1)
}
