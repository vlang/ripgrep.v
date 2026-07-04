module matcher

enum TestPattern {
	word_pair
	a_plus
}

struct TestMatcher {
	pattern TestPattern
	named   bool
}

struct TestMatcherNoCaps {
	inner TestMatcher
}

struct TestCaptures {
mut:
	matches []Match
	present []bool
}

struct WordPairMatch {
	overall Match
	first   Match
	second  Match
}

fn make_test_matcher(pattern string) TestMatcher {
	return match pattern {
		r'(\w+)\s+(\w+)' {
			TestMatcher{
				pattern: .word_pair
			}
		}
		r'(?P<a>\w+)\s+(?P<b>\w+)' {
			TestMatcher{
				pattern: .word_pair
				named:   true
			}
		}
		r'a+' {
			TestMatcher{
				pattern: .a_plus
			}
		}
		else { unsupported_test_matcher(pattern) }
	}
}

fn unsupported_test_matcher(pattern string) TestMatcher {
	panic('unsupported test pattern: ${pattern}')
}

fn make_test_matcher_no_caps(pattern string) TestMatcherNoCaps {
	return TestMatcherNoCaps{
		inner: make_test_matcher(pattern)
	}
}

fn tm(start usize, end usize) Match {
	return Match.new(start, end)
}

fn assert_match_eq(actual Match, expected Match) {
	assert actual.start() == expected.start()
	assert actual.end() == expected.end()
}

fn assert_matches_eq(actual []Match, expected []Match) {
	assert actual.len == expected.len
	for i, mat in actual {
		assert_match_eq(mat, expected[i])
	}
}

fn is_word_byte(byte u8) bool {
	return (byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`) || (byte >= `0`
		&& byte <= `9`) || byte == `_`
}

fn is_space_byte(byte u8) bool {
	return byte == `\t` || byte == `\n` || byte == 0x0b || byte == 0x0c || byte == `\r`
		|| byte == ` `
}

fn word_pair_at(haystack []u8, start usize) ?WordPairMatch {
	mut i := start
	if i >= usize(haystack.len) || !is_word_byte(haystack[i]) {
		return none
	}
	first_start := i
	for i < usize(haystack.len) && is_word_byte(haystack[i]) {
		i++
	}
	first_end := i
	space_start := i
	for i < usize(haystack.len) && is_space_byte(haystack[i]) {
		i++
	}
	if i == space_start {
		return none
	}
	second_start := i
	if i >= usize(haystack.len) || !is_word_byte(haystack[i]) {
		return none
	}
	for i < usize(haystack.len) && is_word_byte(haystack[i]) {
		i++
	}
	return WordPairMatch{
		overall: tm(first_start, i)
		first:   tm(first_start, first_end)
		second:  tm(second_start, i)
	}
}

fn find_word_pair(haystack []u8, at usize) ?WordPairMatch {
	mut start := at
	for start < usize(haystack.len) {
		if mat := word_pair_at(haystack, start) {
			return mat
		}
		start++
	}
	return none
}

fn find_a_plus(haystack []u8, at usize) ?Match {
	mut start := at
	for start < usize(haystack.len) && haystack[start] != `a` {
		start++
	}
	if start >= usize(haystack.len) {
		return none
	}
	mut end := start
	for end < usize(haystack.len) && haystack[end] == `a` {
		end++
	}
	return tm(start, end)
}

fn (m TestMatcher) find_at(haystack []u8, at usize) !FallibleMatch {
	match m.pattern {
		.word_pair {
			mat := find_word_pair(haystack, at) or { return FallibleMatch.absent() }
			return FallibleMatch.some(mat.overall)
		}
		.a_plus {
			mat := find_a_plus(haystack, at) or { return FallibleMatch.absent() }
			return FallibleMatch.some(mat)
		}
	}
}

fn (m TestMatcher) new_captures() !TestCaptures {
	_ = m
	return TestCaptures{
		matches: []Match{len: 3}
		present: []bool{len: 3}
	}
}

fn (m TestMatcher) captures_at(haystack []u8, at usize, mut caps TestCaptures) !bool {
	_ = m
	mat := find_word_pair(haystack, at) or { return false }
	caps.matches[0] = mat.overall
	caps.matches[1] = mat.first
	caps.matches[2] = mat.second
	caps.present[0] = true
	caps.present[1] = true
	caps.present[2] = true
	return true
}

fn (m TestMatcher) capture_count() usize {
	return match m.pattern {
		.word_pair { usize(3) }
		.a_plus { usize(0) }
	}
}

fn (m TestMatcher) capture_index(name string) ?usize {
	if !m.named {
		return none
	}
	return match name {
		'a' { usize(1) }
		'b' { usize(2) }
		else { none }
	}
}

fn (m TestMatcherNoCaps) find_at(haystack []u8, at usize) !FallibleMatch {
	return m.inner.find_at(haystack, at)
}

fn (m TestMatcherNoCaps) new_captures() !NoCaptures {
	_ = m
	return NoCaptures.new()
}

fn (m TestMatcherNoCaps) captures_at(haystack []u8, at usize, mut caps NoCaptures) !bool {
	_ = m
	return default_captures_at(haystack, at, mut caps)
}

fn (m TestMatcherNoCaps) capture_count() usize {
	_ = m
	return default_capture_count()
}

fn (m TestMatcherNoCaps) capture_index(name string) ?usize {
	_ = m
	return default_capture_index(name)
}

fn (caps TestCaptures) len() usize {
	return usize(caps.matches.len)
}

fn (caps TestCaptures) get(i usize) ?Match {
	if i >= usize(caps.matches.len) || !caps.present[i] {
		return none
	}
	return caps.matches[i]
}

fn test_find() {
	matcher_ := make_test_matcher(r'(\w+)\s+(\w+)')
	found := find(matcher_, ' homer simpson '.bytes())!
	mat := found.get() or { panic_missing_test_capture('find') }
	assert_match_eq(mat, tm(1, 14))
}

fn test_find_iter() {
	matcher_ := make_test_matcher(r'(\w+)\s+(\w+)')
	mut matches := []Match{}
	find_iter(matcher_, 'aa bb cc dd'.bytes(), fn [mut matches] (mat Match) bool {
		matches << mat
		return true
	})!
	assert_matches_eq(matches, [tm(0, 5), tm(6, 11)])

	// Test that find_iter respects short circuiting.
	matches.clear()
	find_iter(matcher_, 'aa bb cc dd'.bytes(), fn [mut matches] (mat Match) bool {
		matches << mat
		return false
	})!
	assert_matches_eq(matches, [tm(0, 5)])
}

fn test_try_find_iter() {
	matcher_ := make_test_matcher(r'(\w+)\s+(\w+)')
	mut matches := []Match{}
	mut saw_error := false
	try_find_iter(matcher_, 'aa bb cc dd'.bytes(), fn [mut matches] (mat Match) !bool {
		if matches.len == 0 {
			matches << mat
			return true
		}
		return error('my error')
	}) or {
		saw_error = true
		assert err.msg() == 'my error'
	}
	assert saw_error
	assert_matches_eq(matches, [tm(0, 5)])
}

fn test_shortest_match() {
	matcher_ := make_test_matcher(r'a+')
	// This tests that the default impl isn't doing anything smart, and simply
	// defers to `find`.
	found := shortest_match(matcher_, 'aaa'.bytes())!
	end := found.get() or { panic('missing shortest match') }
	assert end == usize(3)
}

fn test_captures() {
	matcher_ := make_test_matcher(r'(?P<a>\w+)\s+(?P<b>\w+)')
	assert matcher_.capture_count() == 3
	assert matcher_.capture_index('a') == ?usize(1)
	assert matcher_.capture_index('b') == ?usize(2)
	assert matcher_.capture_index('nada') == none

	mut caps := matcher_.new_captures()!
	assert captures(matcher_, ' homer simpson '.bytes(), mut caps)!
	overall := caps.get(0) or { panic_missing_test_capture('overall') }
	first := caps.get(1) or { panic_missing_test_capture('first') }
	second := caps.get(2) or { panic_missing_test_capture('second') }
	assert_match_eq(overall, tm(1, 14))
	assert_match_eq(first, tm(1, 6))
	assert_match_eq(second, tm(7, 14))
}

fn test_captures_iter() {
	matcher_ := make_test_matcher(r'(?P<a>\w+)\s+(?P<b>\w+)')
	mut caps := matcher_.new_captures()!
	mut matches := []Match{}
	captures_iter(matcher_, 'aa bb cc dd'.bytes(), mut caps, fn [mut matches] (caps &TestCaptures) bool {
		overall := caps.get(0) or { panic_missing_test_capture('overall') }
		first := caps.get(1) or { panic_missing_test_capture('first') }
		second := caps.get(2) or { panic_missing_test_capture('second') }
		matches << overall
		matches << first
		matches << second
		return true
	})!
	assert_matches_eq(matches, [tm(0, 5), tm(0, 2), tm(3, 5), tm(6, 11), tm(6, 8), tm(9, 11)])

	// Test that captures_iter respects short circuiting.
	matches.clear()
	captures_iter(matcher_, 'aa bb cc dd'.bytes(), mut caps, fn [mut matches] (caps &TestCaptures) bool {
		overall := caps.get(0) or { panic_missing_test_capture('overall') }
		first := caps.get(1) or { panic_missing_test_capture('first') }
		second := caps.get(2) or { panic_missing_test_capture('second') }
		matches << overall
		matches << first
		matches << second
		return false
	})!
	assert_matches_eq(matches, [tm(0, 5), tm(0, 2), tm(3, 5)])
}

fn test_try_captures_iter() {
	matcher_ := make_test_matcher(r'(?P<a>\w+)\s+(?P<b>\w+)')
	mut caps := matcher_.new_captures()!
	mut matches := []Match{}
	mut saw_error := false
	try_captures_iter(matcher_, 'aa bb cc dd'.bytes(), mut caps, fn [mut matches] (caps &TestCaptures) !bool {
		if matches.len == 0 {
			overall := caps.get(0) or { panic_missing_test_capture('overall') }
			first := caps.get(1) or { panic_missing_test_capture('first') }
			second := caps.get(2) or { panic_missing_test_capture('second') }
			matches << overall
			matches << first
			matches << second
			return true
		}
		return error('my error')
	}) or {
		saw_error = true
		assert err.msg() == 'my error'
	}
	assert saw_error
	assert_matches_eq(matches, [tm(0, 5), tm(0, 2), tm(3, 5)])
}

// Test that our default impls for capturing are correct. Namely, when
// capturing isn't supported by the underlying matcher, then all of the
// various capturing related APIs fail fast.
fn test_no_captures() {
	matcher_ := make_test_matcher_no_caps(r'(?P<a>\w+)\s+(?P<b>\w+)')
	assert matcher_.capture_count() == 0
	assert matcher_.capture_index('a') == none
	assert matcher_.capture_index('b') == none
	assert matcher_.capture_index('nada') == none

	mut caps := matcher_.new_captures()!
	assert !captures(matcher_, 'homer simpson'.bytes(), mut caps)!

	mut called := false
	captures_iter(matcher_, 'homer simpson'.bytes(), mut caps, fn [mut called] (_caps &NoCaptures) bool {
		called = true
		return true
	})!
	assert !called
}

fn test_replace() {
	matcher_ := make_test_matcher(r'(\w+)\s+(\w+)')
	mut dst := []u8{}
	replace(matcher_, 'aa bb cc dd'.bytes(), mut dst, fn (_mat Match, mut dst []u8) bool {
		dst << `z`
		return true
	})!
	assert dst == 'z z'.bytes()

	// Test that replacements respect short circuiting.
	dst.clear()
	replace(matcher_, 'aa bb cc dd'.bytes(), mut dst, fn (_mat Match, mut dst []u8) bool {
		dst << `z`
		return false
	})!
	assert dst == 'z cc dd'.bytes()
}

fn test_replace_with_captures() {
	matcher_ := make_test_matcher(r'(\w+)\s+(\w+)')
	haystack := 'aa bb cc dd'.bytes()
	mut caps := matcher_.new_captures()!
	mut dst := []u8{}
	replace_with_captures(matcher_, haystack, mut caps, mut dst, fn [matcher_, haystack] (caps &TestCaptures, mut dst []u8) bool {
		interpolate('$2 $1'.bytes(), fn [caps, haystack] (i usize, mut dst []u8) {
			cap_match := caps.get(i) or { return }
			append_slice(mut dst, haystack[cap_match.start()..cap_match.end()])
		}, fn [matcher_] (name string) ?usize {
			return matcher_.capture_index(name)
		}, mut dst)
		return true
	})!
	assert dst == 'bb aa dd cc'.bytes()

	// Test that replacements respect short circuiting.
	dst.clear()
	replace_with_captures(matcher_, haystack, mut caps, mut dst, fn [matcher_, haystack] (caps &TestCaptures, mut dst []u8) bool {
		interpolate('$2 $1'.bytes(), fn [caps, haystack] (i usize, mut dst []u8) {
			cap_match := caps.get(i) or { return }
			append_slice(mut dst, haystack[cap_match.start()..cap_match.end()])
		}, fn [matcher_] (name string) ?usize {
			return matcher_.capture_index(name)
		}, mut dst)
		return false
	})!
	assert dst == 'bb aa cc dd'.bytes()
}

fn panic_missing_test_capture(name string) Match {
	panic('missing ${name} capture')
}
