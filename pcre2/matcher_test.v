module pcre2

import matcher

fn pcre2_is_match(re &RegexMatcher, haystack &[]u8) !bool {
	return re.find_at(haystack, 0)!.has_value
}

fn has_pcre2_feature() bool {
	return pcre2_enabled()
}

// Test that enabling word matches does the right thing and demonstrate
// the difference between it and surrounding the regex in `\b`.
fn test_word() {
	if !has_pcre2_feature() {
		return
	}
	mut builder := RegexMatcherBuilder.new()
	builder.word(true)
	matcher_ := builder.build(r'-2') or { panic(err) }
	assert pcre2_is_match(&matcher_, 'abc -2 foo'.bytes())!

	mut boundary_builder := RegexMatcherBuilder.new()
	boundary_builder.word(false)
	boundary_matcher := boundary_builder.build(r'\b-2\b') or { panic(err) }
	assert !pcre2_is_match(&boundary_matcher, 'abc -2 foo'.bytes())!
}

fn test_word_rewrite_backtracks_at_same_start() {
	if !has_pcre2_feature() {
		return
	}
	mut builder := RegexMatcherBuilder.new()
	builder.word(true)
	matcher_ := builder.build_many(['foo', 'foobar']) or { panic(err) }
	mat := matcher_.find_at('foobar'.bytes(), 0)!.get() or { panic('missing match') }
	assert mat.start() == usize(0)
	assert mat.end() == usize(6)
}

fn test_whole_line_rewrite_backtracks_at_same_start() {
	if !has_pcre2_feature() {
		return
	}
	mut builder := RegexMatcherBuilder.new()
	builder.whole_line(true)
	matcher_ := builder.build_many(['foo', 'foo bar']) or { panic(err) }
	mat := matcher_.find_at('foo bar\n'.bytes(), 0)!.get() or { panic('missing match') }
	assert mat.start() == usize(0)
	assert mat.end() == usize(7)
}

fn test_clone_retain_free_keeps_other_clone_alive() {
	if !has_pcre2_feature() {
		return
	}
	mut matcher_ := RegexMatcherBuilder.new().build(r'abc') or { panic(err) }
	mut cloned := matcher_.clone()
	assert pcre2_is_match(&cloned, 'abc'.bytes())!
	unsafe {
		cloned.free()
	}
	assert pcre2_is_match(&matcher_, 'abc'.bytes())!
	unsafe {
		matcher_.free()
	}
}

fn test_automatic_drop_releases_cloned_matchers() {
	if !has_pcre2_feature() {
		return
	}
	baseline := live_regex_count()
	for _ in 0 .. 256 {
		exercise_automatic_matcher_drop()
	}
	assert live_regex_count() == baseline
}

fn exercise_automatic_matcher_drop() {
	matcher_ := RegexMatcherBuilder.new().build(r'(Sherlock)\s+(Holmes)') or { panic(err) }
	cloned1 := matcher_.clone()
	cloned2 := cloned1.clone()
	found := cloned2.find_at('Sherlock Holmes'.bytes(), 0) or { panic(err) }
	assert found.has_value
}

// Test that enabling CRLF permits `$` to match at the end of a line.
fn test_line_terminator_crlf() {
	if !has_pcre2_feature() {
		return
	}
	// Test normal use of `$` with a `\n` line terminator.
	mut lf_builder := RegexMatcherBuilder.new()
	lf_builder.multi_line(true)
	lf_matcher := lf_builder.build(r'abc$') or { panic(err) }
	assert pcre2_is_match(&lf_matcher, 'abc\n'.bytes())!

	// Test that `$` doesn't match at `\r\n` boundary normally.
	mut crlf_off_builder := RegexMatcherBuilder.new()
	crlf_off_builder.multi_line(true)
	crlf_off_matcher := crlf_off_builder.build(r'abc$') or { panic(err) }
	assert !pcre2_is_match(&crlf_off_matcher, 'abc\r\n'.bytes())!

	// Now check the CRLF handling.
	mut crlf_builder := RegexMatcherBuilder.new()
	crlf_builder.multi_line(true)
	crlf_builder.crlf(true)
	crlf_matcher := crlf_builder.build(r'abc$') or { panic(err) }
	assert pcre2_is_match(&crlf_matcher, 'abc\n'.bytes())!
	assert pcre2_is_match(&crlf_matcher, 'abc\r\n'.bytes())!
}

// Test that smart case works.
fn test_case_smart() {
	if !has_pcre2_feature() {
		return
	}
	mut builder := RegexMatcherBuilder.new()
	builder.case_smart(true)
	matcher_ := builder.build(r'abc') or { panic(err) }
	assert pcre2_is_match(&matcher_, 'ABC'.bytes())!

	mut upper_builder := RegexMatcherBuilder.new()
	upper_builder.case_smart(true)
	upper_matcher := upper_builder.build(r'aBc') or { panic(err) }
	assert !pcre2_is_match(&upper_matcher, 'ABC'.bytes())!
}

fn test_case_smart_recognizes_unicode_uppercase() {
	if !has_pcre2_feature() {
		return
	}
	mut builder := RegexMatcherBuilder.new()
	builder.case_smart(true)
	builder.ucp(true)
	matcher_ := builder.build('Δ') or { panic(err) }
	assert pcre2_is_match(&matcher_, 'Δ'.bytes())!
	assert !pcre2_is_match(&matcher_, 'δ'.bytes())!
}

fn test_extended() {
	if !has_pcre2_feature() {
		return
	}
	mut builder := RegexMatcherBuilder.new()
	builder.extended(true)
	matcher_ := builder.build(r'a b c') or { panic(err) }
	assert pcre2_is_match(&matcher_, 'abc'.bytes())!
}

fn test_look_around() {
	if !has_pcre2_feature() {
		return
	}
	matcher_ := RegexMatcherBuilder.new().build(r'(?<=the )Sherlock') or { panic(err) }
	assert pcre2_is_match(&matcher_, 'the Sherlock'.bytes())!
	assert !pcre2_is_match(&matcher_, 'not Sherlock'.bytes())!
}

fn test_utf_ucp_word_classes() {
	if !has_pcre2_feature() {
		return
	}
	mut ascii_builder := RegexMatcherBuilder.new()
	ascii_builder.utf(true)
	ascii_matcher := ascii_builder.build(r'\w+') or { panic(err) }
	assert !pcre2_is_match(&ascii_matcher, 'Δ'.bytes())!

	mut unicode_builder := RegexMatcherBuilder.new()
	unicode_builder.ucp(true)
	unicode_matcher := unicode_builder.build(r'\w+') or { panic(err) }
	assert pcre2_is_match(&unicode_matcher, 'Δ'.bytes())!
}

fn test_required_jit_errors_when_unavailable() {
	if !has_pcre2_feature() {
		return
	}
	mut builder := RegexMatcherBuilder.new()
	builder.jit(true)
	_ := builder.build(r'abc') or {
		assert err.msg().contains('PCRE2 JIT is not available')
		return
	}
}

// Test that finding candidate lines works as expected.
fn test_candidate_lines() {
	if !has_pcre2_feature() {
		return
	}
	matcher_ := RegexMatcherBuilder.new().build(r'\wfoo\s') or { panic(err) }
	m := matcher_.find_candidate_line('afoo '.bytes())!.get() or { panic('missing match') }
	assert m.is_confirmed()
}

fn test_fixed_strings_escape_meta_characters() {
	if !has_pcre2_feature() {
		return
	}
	mut builder := RegexMatcherBuilder.new()
	builder.fixed_strings(true)
	matcher_ := builder.build(r'a.c') or { panic(err) }
	assert pcre2_is_match(&matcher_, 'a.c'.bytes())!
	assert !pcre2_is_match(&matcher_, 'abc'.bytes())!
}

fn test_capture_metadata() {
	if !has_pcre2_feature() {
		return
	}
	matcher_ := RegexMatcherBuilder.new().build(r'(?P<name>ab)(c)') or { panic(err) }
	assert matcher_.capture_count() == 3
	assert matcher_.capture_index('name') or { usize(0) } == usize(1)
}

fn test_captures() {
	if !has_pcre2_feature() {
		return
	}
	matcher_ := RegexMatcherBuilder.new().build(r'(?P<foo>\w)|(?P<bar>\W)') or { panic(err) }
	mut caps := matcher_.new_captures()!
	assert caps.len() == 3
	assert matcher_.captures_at('a'.bytes(), 0, mut caps)!
	assert caps.get(0) or { panic('missing overall match') } == matcher.Match.new(0, 1)
	assert caps.get(1) or { panic('missing foo match') } == matcher.Match.new(0, 1)
	assert caps.get(2) == none
	cloned := caps.clone()
	assert cloned.get(0) or { panic('missing cloned overall match') } == matcher.Match.new(0, 1)
	assert cloned.get(1) or { panic('missing cloned foo match') } == matcher.Match.new(0, 1)
	assert cloned.get(2) == none

	assert matcher_.captures_at('!'.bytes(), 0, mut caps)!
	assert caps.get(0) or { panic('missing overall match') } == matcher.Match.new(0, 1)
	assert caps.get(1) == none
	assert caps.get(2) or { panic('missing bar match') } == matcher.Match.new(0, 1)
}
