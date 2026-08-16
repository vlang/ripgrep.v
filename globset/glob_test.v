module globset

import regex.meta

fn starts_with(needle string, haystack string) bool {
	return needle.len <= haystack.len && needle == haystack[..needle.len]
}

fn ends_with(needle string, haystack string) bool {
	if needle.len > haystack.len {
		return false
	}
	return needle == haystack[haystack.len - needle.len..]
}

/// A strategic matcher for a single pattern.
struct GlobStrategic {
	/// The match strategy to use.
	strategy MatchStrategy
	/// The pattern, as a compiled regex.
	re meta.Regex
}

/// Returns a strategic matcher.
///
/// This isn't exposed because it's not clear whether it's actually
/// faster than just running a regex for a *single* pattern. If it
/// is faster, then GlobMatcher should do it automatically.
fn (g &Glob) compile_strategic_matcher() GlobStrategic {
	strategy := match_strategy_new(g)
	re := new_regex(&g.re_) or { panic('regex compilation shouldn\'t fail') }
	return GlobStrategic{
		strategy: strategy
		re:       re
	}
}

/// Tests whether the given path matches this pattern or not.
fn (m &GlobStrategic) is_match(path string) bool {
	candidate := Candidate.new(&path)
	return m.is_match_candidate(&candidate)
}

/// Tests whether the given path matches this pattern or not.
fn (m &GlobStrategic) is_match_candidate[^a](candidate &Candidate[^a]) bool {
	return match m.strategy.kind {
		.literal { m.strategy.value == candidate.path_ }
		.basename_literal { m.strategy.value == candidate.basename_ }
		.extension { m.strategy.value == candidate.ext_ }
		.prefix { starts_with(m.strategy.value, candidate.path_) }
		.suffix {
			(m.strategy.component && candidate.path_ == m.strategy.value[1..])
				|| ends_with(m.strategy.value, candidate.path_)
		}
		.required_extension {
			candidate.ext_ == m.strategy.value && m.re.find(candidate.path_) != none
		}
		.regex { m.re.find(candidate.path_) != none }
	}
}

struct TestOptions implements IClone {
	casei  ?bool
	litsep ?bool
	bsesc  ?bool
	ealtre ?bool
	unccls ?bool
}

fn make_test_glob(pattern string, options TestOptions) Glob {
	owned := pattern.to_owned()
	mut builder := GlobBuilder.new(&owned)
	if casei := options.casei {
		builder.case_insensitive(casei)
	}
	if litsep := options.litsep {
		builder.literal_separator(litsep)
	}
	if bsesc := options.bsesc {
		builder.backslash_escape(bsesc)
	}
	if ealtre := options.ealtre {
		builder.empty_alternates(ealtre)
	}
	if unccls := options.unccls {
		builder.allow_unclosed_class(unccls)
	}
	return builder.build() or { panic(err) }
}

fn default_test_options() TestOptions {
	return TestOptions{}
}

fn slashlit_test_options() TestOptions {
	return TestOptions{
		litsep: true
	}
}

fn casei_test_options() TestOptions {
	return TestOptions{
		casei: true
	}
}

fn ealtre_test_options() TestOptions {
	return TestOptions{
		bsesc:  true
		ealtre: true
	}
}

fn bsesc_test_options() TestOptions {
	return TestOptions{
		bsesc: true
	}
}

fn no_bsesc_test_options() TestOptions {
	return TestOptions{
		bsesc: false
	}
}

fn unccls_test_options() TestOptions {
	return TestOptions{
		unccls: true
	}
}

fn assert_glob_case(pattern string, path string, options TestOptions, expected bool) {
	glob := make_test_glob(pattern, options)
	matcher := glob.compile_matcher()
	strategic := glob.compile_strategic_matcher()
	mut set_builder := GlobSetBuilder.new()
	set_builder.add(glob.clone())
	set := set_builder.build() or { panic(err) }
	assert matcher.is_match(path) == expected, 'matcher: ${pattern} versus ${path}'
	assert strategic.is_match(path) == expected, 'strategic matcher: ${pattern} versus ${path}'
	assert set.is_match(path) == expected, 'set matcher: ${pattern} versus ${path}'
}

fn test_glob_parser_basic_tokens() ! {
	cases := {
		'a':     '[Literal(a)]'
		'ab':    '[Literal(a),Literal(b)]'
		'?':     '[Any]'
		'a?b':   '[Literal(a),Any,Literal(b)]'
		'*':     '[ZeroOrMore]'
		'a*b':   '[Literal(a),ZeroOrMore,Literal(b)]'
		'*a*b*': '[ZeroOrMore,Literal(a),ZeroOrMore,Literal(b),ZeroOrMore]'
	}
	for pattern, expected in cases {
		glob := Glob.new(pattern.clone())!
		if pattern == 'a' {
			assert glob.tokens.tokens[0].ch == `a`
		}
		got := glob.tokens.str()
		assert got == expected
	}
}

fn test_glob_equality_uses_pattern_and_options() ! {
	one := Glob.new('a')!
	mut same := one.clone()
	same.re_ = 'different compiled representation'
	same.tokens = Tokens.default()
	assert one == same
	assert one != make_test_glob('a', casei_test_options())
}

fn test_glob_parser_recursive_tokens() ! {
	cases := {
		'**':     '[RecursivePrefix]'
		'**/':    '[RecursivePrefix]'
		'/**':    '[RecursiveSuffix]'
		'/**/':   '[RecursiveZeroOrMore]'
		'a/**/b': '[Literal(a),RecursiveZeroOrMore,Literal(b)]'
	}
	for pattern, expected in cases {
		assert Glob.new(pattern)!.tokens.str() == expected
	}
}

fn test_glob_parser_class_and_alternates() ! {
	class_glob := Glob.new('[!a-z]') or { panic(err) }
	assert class_glob.tokens.str() == '[Class(true,[(a,z)])]'
	alt_glob := Glob.new('{a,b}') or { panic(err) }
	assert alt_glob.tokens.str() == '[Alternates([[Literal(a)],[Literal(b)]])]'
}

fn test_glob_parser_class_edge_cases() ! {
	cases := {
		'[-]':       '[Class(false,[(-,-)])]'
		'[]]':       '[Class(false,[(],])])]'
		'[*]':       '[Class(false,[(*,*)])]'
		'[!!]':      '[Class(true,[(!,!)])]'
		'[a-]':      '[Class(false,[(a,a),(-,-)])]'
		'[-a-z]':    '[Class(false,[(-,-),(a,z)])]'
		'[a-z-]':    '[Class(false,[(a,z),(-,-)])]'
		'[-a-z-]':   '[Class(false,[(-,-),(a,z),(-,-)])]'
		'[]-z]':     '[Class(false,[(],z)])]'
		'[--z]':     '[Class(false,[(-,z)])]'
		'[ --]':     '[Class(false,[( ,-)])]'
		'[0-9a-z]':  '[Class(false,[(0,9),(a,z)])]'
		'[a-z0-9]':  '[Class(false,[(a,z),(0,9)])]'
		'[!0-9a-z]': '[Class(true,[(0,9),(a,z)])]'
		'[!a-z0-9]': '[Class(true,[(a,z),(0,9)])]'
		'[^a]':      '[Class(true,[(a,a)])]'
		'[^a-z]':    '[Class(true,[(a,z)])]'
	}
	for pattern, expected in cases {
		glob := Glob.new(pattern.clone()) or { panic(err) }
		got := glob.tokens.str()
		assert got == expected, '${pattern}: expected ${expected}, got ${got}'
	}
}

fn test_glob_parser_errors() ! {
	for pattern in ['[', '[]', '[!', '[!]'] {
		Glob.new(pattern.clone()) or {
			assert err.msg().contains('unclosed character class')
			continue
		}
		assert false, 'expected unclosed class error for ${pattern}'
	}
	mut got_range_error := false
	Glob.new('[z-a]') or {
		assert err.msg().contains("invalid range; 'z' > 'a'")
		got_range_error = true
	}
	assert got_range_error
	got_range_error = false
	Glob.new('[z--]') or {
		assert err.msg().contains("invalid range; 'z' > '-'")
		got_range_error = true
	}
	assert got_range_error
	for pattern in ['{a,b', '{a,{b,c}'] {
		Glob.new(pattern.clone()) or {
			assert err.msg().contains('unclosed alternate group')
			continue
		}
		assert false, 'expected unclosed alternate error for ${pattern}'
	}
	for pattern in ['a,b}', '{a,b}}'] {
		Glob.new(pattern.clone()) or {
			assert err.msg().contains('unopened alternate group')
			continue
		}
		assert false, 'expected unopened alternate error for ${pattern}'
	}
}

fn test_glob_parser_preserves_structured_error() ! {
	Glob.new('[') or {
		assert err is GlobError
		if err is GlobError {
			assert err.kind().tag == .unclosed_class
			original := err.glob() or { panic('missing original glob') }
			assert *original == '['
			return
		}
		panic('expected structured glob error')
	}
	assert false, 'expected unclosed class error'
}

fn test_glob_regex_output_uses_non_unicode_bytes_mode() ! {
	assert *(Glob.new('a')!.regex()) == '(?-u)^a$'
	assert *(Glob.new('a?b')!.regex()) == '(?-u)^a.b$'
	assert *(Glob.new('**')!.regex()) == '(?-u)^.*$'
	assert *(Glob.new('**/foo')!.regex()) == '(?-u)^(?:/?|.*/)foo$'
}

fn test_glob_regex_output_escapes_literals() ! {
	assert *(Glob.new('a.b')!.regex()) == r'(?-u)^a\.b$'
	assert *(Glob.new('a+b')!.regex()) == r'(?-u)^a\+b$'
	assert *(Glob.new('a(b)')!.regex()) == r'(?-u)^a\(b\)$'
	assert *(Glob.new('#&-~')!.regex()) == r'(?-u)^\#\&\-\~$'
	assert *(Glob.new('[-]')!.regex()) == r'(?-u)^[\-]$'
}

fn test_glob_regex_output_upstream_cases() ! {
	cases := {
		'':               '(?-u)^$'
		'?':              '(?-u)^.$'
		'*':              '(?-u)^.*$'
		'a?':             '(?-u)^a.$'
		'?a':             '(?-u)^.a$'
		'a*':             '(?-u)^a.*$'
		'*a':             '(?-u)^.*a$'
		'[*]':            r'(?-u)^[\*]$'
		'[+]':            r'(?-u)^[\+]$'
		'+':              r'(?-u)^\+$'
		'☃':              r'(?-u)^\xe2\x98\x83$'
		'**/':            '(?-u)^.*$'
		'**/*':           '(?-u)^(?:/?|.*/).*$'
		'**/**':          '(?-u)^.*$'
		'**/**/*':        '(?-u)^(?:/?|.*/).*$'
		'**/**/**':       '(?-u)^.*$'
		'**/**/**/*':     '(?-u)^(?:/?|.*/).*$'
		'a/**':           '(?-u)^a/.*$'
		'a/**/**':        '(?-u)^a/.*$'
		'a/**/**/**':     '(?-u)^a/.*$'
		'a/**/b':         '(?-u)^a(?:/|/.*/)b$'
		'a/**/**/b':      '(?-u)^a(?:/|/.*/)b$'
		'a/**/**/**/b':   '(?-u)^a(?:/|/.*/)b$'
		'**/b':           '(?-u)^(?:/?|.*/)b$'
		'**/**/b':        '(?-u)^(?:/?|.*/)b$'
		'**/**/**/b':     '(?-u)^(?:/?|.*/)b$'
		'a**':            '(?-u)^a.*.*$'
		'**a':            '(?-u)^.*.*a$'
		'a**b':           '(?-u)^a.*.*b$'
		'***':            '(?-u)^.*.*.*$'
		'/a**':           '(?-u)^/a.*.*$'
		'/**a':           '(?-u)^/.*.*a$'
		'/a**b':          '(?-u)^/a.*.*b$'
		'{a,b}':          '(?-u)^(?:a|b)$'
		'{a,{b,c}}':      '(?-u)^(?:a|(?:b|c))$'
		'{{a,b},{c,d}}':  '(?-u)^(?:(?:a|b)|(?:c|d))$'
	}
	for pattern, expected in cases {
		assert *(Glob.new(pattern)!.regex()) == expected
	}
}

fn test_glob_regex_output_options() ! {
	assert *(make_test_glob('a', casei_test_options()).regex()) == '(?-u)(?i)^a$'
	assert *(make_test_glob('ÄA', casei_test_options()).regex()) == r'(?-u)(?i)^\xc3\x84A$'
	assert *(make_test_glob('?', slashlit_test_options()).regex()) == '(?-u)^[^/]$'
	assert *(make_test_glob('*', slashlit_test_options()).regex()) == '(?-u)^[^/]*$'
	assert *(make_test_glob('[', unccls_test_options()).regex()) == r'(?-u)^\[$'
	assert *(make_test_glob('[abc', unccls_test_options()).regex()) == r'(?-u)^\[abc$'
	assert *(make_test_glob('[]', unccls_test_options()).regex()) == r'(?-u)^\[\]$'
	assert *(make_test_glob('[][', unccls_test_options()).regex()) == r'(?-u)^\[\]\[$'
	assert *(make_test_glob('[!', unccls_test_options()).regex()) == r'(?-u)^\[!$'
	assert *(make_test_glob('[!]', unccls_test_options()).regex()) == r'(?-u)^\[!\]$'
	assert *(make_test_glob('{[abc,xyz}', unccls_test_options()).regex()) == r'(?-u)^(?:\[abc|xyz)$'
	assert *(make_test_glob('{[abc,[xyz}', unccls_test_options()).regex()) == r'(?-u)^(?:\[abc|\[xyz)$'
	assert *(make_test_glob('{[abc],[xyz}', unccls_test_options()).regex()) == r'(?-u)^(?:[abc]|\[xyz)$'
}

fn test_glob_matcher_matches() ! {
	glob := Glob.new('*.rs') or { panic(err) }
	matcher := glob.compile_matcher()
	assert matcher.is_match('foo.rs')
	assert matcher.is_match('foo/bar.rs')
	assert !matcher.is_match('Cargo.toml')
}

fn test_glob_matcher_literal_separator() ! {
	pattern := '*.rs'
	mut builder := GlobBuilder.new(&pattern)
	builder.literal_separator(true)
	glob := builder.build() or { panic(err) }
	matcher := glob.compile_matcher()
	assert matcher.is_match('foo.rs')
	assert !matcher.is_match('foo/bar.rs')
}

fn test_glob_matcher_recursive_prefix() ! {
	glob := Glob.new('**/foo') or { panic(err) }
	matcher := glob.compile_matcher()
	assert matcher.is_match('foo')
	assert matcher.is_match('bar/foo')
	assert !matcher.is_match('foo/bar')
}

fn test_glob_matcher_empty_alternates() ! {
	pattern := 'foo{,.txt}'
	mut builder := GlobBuilder.new(&pattern)
	builder.empty_alternates(true)
	glob := builder.build() or { panic(err) }
	matcher := glob.compile_matcher()
	assert matcher.is_match('foo')
	assert matcher.is_match('foo.txt')
}

fn test_glob_matcher_unclosed_class_allowed() ! {
	pattern := '[abc'
	mut builder := GlobBuilder.new(&pattern)
	builder.allow_unclosed_class(true)
	glob := builder.build() or { panic(err) }
	matcher := glob.compile_matcher()
	assert matcher.is_match('[abc')
}

fn test_glob_matcher_upstream_cases() ! {
	for case in [
		['a*b*c', 'abc'],
		['a*b*c', 'a___b___c'],
		['*.rs', '.rs'],
		['some/**/needle.txt', 'some/needle.txt'],
		['some/**/needle.txt', 'some/one/two/needle.txt'],
		['**/test', 'test'],
		['**/foo/bar', 'foo/bar'],
		['a[0-9]b', 'a0b'],
		['a[!0-9]b', 'a_b'],
		['[-a-c]', 'b'],
		['{*.foo,*.bar,*.wat}', 'test.bar'],
		['{a,b{c,d}}', 'bd'],
	] {
		glob := Glob.new(case[0]) or { panic(err) }
		matcher := glob.compile_matcher()
		assert matcher.is_match(case[1]), '${case[0]} should match ${case[1]}'
	}
}

fn test_glob_matcher_upstream_negative_cases() ! {
	for case in [
		['a*b*c', 'abcd'],
		['some/**/needle.txt', 'some/other/notthis.txt'],
		['/**/test', 'test'],
		['**/.*', 'ab.c'],
		['a[0-9]b', 'a_b'],
		['a[!0-9]b', 'a0b'],
		['[!-]', '-'],
		['*hello.txt', 'hello.txt-and-then-some'],
		['**/foo', 'foofoo'],
		['**/foo/bar', 'foofoo/bar'],
	] {
		glob := Glob.new(case[0]) or { panic(err) }
		matcher := glob.compile_matcher()
		assert !matcher.is_match(case[1]), '${case[0]} should not match ${case[1]}'
	}
}

fn test_glob_matcher_all_upstream_default_cases() ! {
	matches := [
		['a', 'a'],
		['a*b', 'a_b'],
		['a*b*c', 'abc'],
		['a*b*c', 'a_b_c'],
		['a*b*c', 'a___b___c'],
		['abc*abc*abc', 'abcabcabcabcabcabcabc'],
		['a*a*a*a*a*a*a*a*a', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'],
		['a*b[xyz]c*d', 'abxcdbxcddd'],
		['*.rs', '.rs'],
		['☃', '☃'],
		['some/**/needle.txt', 'some/needle.txt'],
		['some/**/needle.txt', 'some/one/needle.txt'],
		['some/**/needle.txt', 'some/one/two/needle.txt'],
		['some/**/needle.txt', 'some/other/needle.txt'],
		['**', 'abcde'],
		['**', ''],
		['**', '.asdf'],
		['**', '/x/.asdf'],
		['some/**/**/needle.txt', 'some/needle.txt'],
		['some/**/**/needle.txt', 'some/one/needle.txt'],
		['some/**/**/needle.txt', 'some/one/two/needle.txt'],
		['some/**/**/needle.txt', 'some/other/needle.txt'],
		['**/test', 'one/two/test'],
		['**/test', 'one/test'],
		['**/test', 'test'],
		['/**/test', '/one/two/test'],
		['/**/test', '/one/test'],
		['/**/test', '/test'],
		['**/.*', '.abc'],
		['**/.*', 'abc/.abc'],
		['**/foo/bar', 'foo/bar'],
		['.*/**', '.abc/abc'],
		['test/**', 'test/'],
		['test/**', 'test/one'],
		['test/**', 'test/one/two'],
		['some/*/needle.txt', 'some/one/needle.txt'],
		['a[0-9]b', 'a0b'],
		['a[0-9]b', 'a9b'],
		['a[!0-9]b', 'a_b'],
		['[a-z123]', '1'],
		['[1a-z23]', '1'],
		['[123a-z]', '1'],
		['[abc-]', '-'],
		['[-abc]', '-'],
		['[-a-c]', 'b'],
		['[a-c-]', 'b'],
		['[-]', '-'],
		['a[^0-9]b', 'a_b'],
		['*hello.txt', 'hello.txt'],
		['*hello.txt', 'gareth_says_hello.txt'],
		['*hello.txt', 'some/path/to/hello.txt'],
		['*hello.txt', 'some\\path\\to\\hello.txt'],
		['*hello.txt', '/an/absolute/path/to/hello.txt'],
		['*some/path/to/hello.txt', 'some/path/to/hello.txt'],
		['*some/path/to/hello.txt', 'a/bigger/some/path/to/hello.txt'],
		['_[[]_[]]_[?]_[*]_!_', '_[_]_?_*_!_'],
		['a,b', 'a,b'],
		[',', ','],
		['{a,b}', 'a'],
		['{a,b}', 'b'],
		['{**/src/**,foo}', 'abc/src/bar'],
		['{**/src/**,foo}', 'foo'],
		['{[}],foo}', '}'],
		['{foo}', 'foo'],
		['{}', ''],
		['{,}', ''],
		['{*.foo,*.bar,*.wat}', 'test.foo'],
		['{*.foo,*.bar,*.wat}', 'test.bar'],
		['{*.foo,*.bar,*.wat}', 'test.wat'],
		['foo{,.txt}', 'foo.txt'],
		['{a,b{c,d}}', 'bc'],
		['{a,b{c,d}}', 'bd'],
		['{a,b{c,d}}', 'a'],
	]
	for case in matches {
		assert_glob_case(case[0], case[1], default_test_options(), true)
	}
	nmatches := [
		['a*b*c', 'abcd'],
		['abc*abc*abc', 'abcabcabcabcabcabcabca'],
		['some/**/needle.txt', 'some/other/notthis.txt'],
		['some/**/**/needle.txt', 'some/other/notthis.txt'],
		['/**/test', 'test'],
		['/**/test', '/one/notthis'],
		['/**/test', '/notthis'],
		['**/.*', 'ab.c'],
		['**/.*', 'abc/ab.c'],
		['.*/**', 'a.bc'],
		['.*/**', 'abc/a.bc'],
		['a[0-9]b', 'a_b'],
		['a[!0-9]b', 'a0b'],
		['a[!0-9]b', 'a9b'],
		['[!-]', '-'],
		['*hello.txt', 'hello.txt-and-then-some'],
		['*hello.txt', 'goodbye.txt'],
		['*some/path/to/hello.txt', 'some/path/to/hello.txt-and-then-some'],
		['*some/path/to/hello.txt', 'some/other/path/to/hello.txt'],
		['a', 'foo/a'],
		['./foo', 'foo'],
		['**/foo', 'foofoo'],
		['**/foo/bar', 'foofoo/bar'],
		['/*.c', 'mozilla-sha1/sha1.c'],
		['a[^0-9]b', 'a0b'],
		['a[^0-9]b', 'a9b'],
		['[^-]', '-'],
		['some/*/needle.txt', 'some/needle.txt'],
		['.*/**', '.abc'],
		['foo/**', 'foo'],
	]
	for case in nmatches {
		assert_glob_case(case[0], case[1], default_test_options(), false)
	}
}

fn test_glob_matcher_all_upstream_option_cases() ! {
	for path in ['aBcDeFg', 'abcdefg', 'ABCDEFG', 'AbCdEfG'] {
		assert_glob_case('aBcDeFg', path, casei_test_options(), true)
	}
	assert_glob_case('foo{,.txt}', 'foo', default_test_options(), false)
	assert_glob_case('foo{,.txt}', 'foo', ealtre_test_options(), true)
	assert_glob_case('abc/def', 'abc/def', slashlit_test_options(), true)
	assert_glob_case('abc?def', 'abc/def', slashlit_test_options(), false)
	assert_glob_case('abc*def', 'abc/def', slashlit_test_options(), false)
	assert_glob_case('abc[/]def', 'abc/def', slashlit_test_options(), true)
	assert_glob_case('*.c', 'mozilla-sha1/sha1.c', slashlit_test_options(), false)
	assert_glob_case('**/m4/ltoptions.m4', 'csharp/src/packages/repositories.config',
		slashlit_test_options(), false)
	assert_glob_case('some/*/needle.txt', 'some/one/two/needle.txt', slashlit_test_options(),
		false)
	assert_glob_case('some/*/needle.txt', 'some/one/two/three/needle.txt',
		slashlit_test_options(), false)
	assert_glob_case('\\[', '[', bsesc_test_options(), true)
	assert_glob_case('\\?', '?', bsesc_test_options(), true)
	assert_glob_case('\\*', '*', bsesc_test_options(), true)
	assert_glob_case('\\[a-z]', '\\a', no_bsesc_test_options(), true)
	assert_glob_case('\\?', '\\a', no_bsesc_test_options(), true)
	assert_glob_case('\\*', '\\\\', no_bsesc_test_options(), true)
	$if windows {
		assert_glob_case('abc\\def', 'abc/def', slashlit_test_options(), true)
		assert_glob_case('\\a', '/a', default_test_options(), true)
	} $else {
		assert_glob_case('abc\\def', 'abc/def', slashlit_test_options(), false)
		assert_glob_case('\\a', 'a', default_test_options(), true)
	}
}

fn test_glob_matcher_option_cases() ! {
	assert make_test_glob('aBcDeFg', casei_test_options()).compile_matcher().is_match('ABCDEFG')
	assert make_test_glob('ÄA', casei_test_options()).compile_matcher().is_match('Äa')
	assert !make_test_glob('ÄA', casei_test_options()).compile_matcher().is_match('äa')
	assert !make_test_glob('abc?def', slashlit_test_options()).compile_matcher().is_match('abc/def')
	assert !make_test_glob('abc*def', slashlit_test_options()).compile_matcher().is_match('abc/def')
	assert make_test_glob('foo{,.txt}', ealtre_test_options()).compile_matcher().is_match('foo')
}

fn test_glob_matcher_matches_arbitrary_bytes() ! {
	matcher := Glob.new('?')!.compile_matcher()
	path := [u8(0xff)]
	candidate := Candidate.from_bytes(&path)
	assert matcher.is_match_candidate(&candidate)
	assert matcher.is_match('\n')
	assert Glob.new('*')!.compile_matcher().is_match('a\nb')
}

fn test_glob_parser_does_not_treat_nul_as_end_of_pattern() ! {
	pattern := '**\x00'
	matcher := Glob.new(pattern)!.compile_matcher()
	assert matcher.is_match('\x00'), 'NUL candidate should match'
	assert !matcher.is_match('abc'), 'NUL literal must not be treated as end of regex'
}

fn test_glob_extract_literal_and_basename() ! {
	assert Glob.new('foo')!.literal() or { '' } == 'foo'
	assert Glob.new('/foo')!.literal() or { '' } == '/foo'
	assert Glob.new('/foo/')!.literal() or { '' } == '/foo/'
	assert Glob.new('/foo/bar')!.literal() or { '' } == '/foo/bar'
	assert Glob.new('foo/bar')!.literal() or { '' } == 'foo/bar'
	assert Glob.new('*.foo')!.literal() == none
	assert Glob.new('**/foo/bar')!.literal() == none
	assert make_test_glob('foo', casei_test_options()).literal() == none
	assert Glob.new('**/foo')!.basename_literal() or { '' } == 'foo'
	assert make_test_glob('**/foo', casei_test_options()).basename_tokens() == none
	assert make_test_glob('**/foo', slashlit_test_options()).basename_tokens() != none
	assert Glob.new('foo')!.basename_literal() == none
	assert Glob.new('*foo')!.basename_literal() == none
	assert Glob.new('*/foo')!.basename_literal() == none
	assert Glob.new('**/fo*o')!.basename_tokens() == none
	basename_tokens := (make_test_glob('**/fo*o', slashlit_test_options()).basename_tokens() or {
		panic('missing basename tokens')
	})
	basename_tokens_text := (*basename_tokens).str()
	assert basename_tokens_text == '[Literal(f), Literal(o), ZeroOrMore, Literal(o)]', basename_tokens_text
}

fn test_glob_extract_extensions() ! {
	assert Glob.new('**/*.rs')!.ext() or { '' } == '.rs'
	assert Glob.new('**/*.rs.bak')!.ext() == none
	assert Glob.new('*.rs')!.ext() or { '' } == '.rs'
	assert Glob.new('a*.rs')!.ext() == none
	assert Glob.new('/*.c')!.ext() == none
	assert make_test_glob('*.c', slashlit_test_options()).ext() == none
	assert Glob.new('*.c')!.required_ext() or { '' } == '.c'
	assert Glob.new('/foo/bar/*.rs')!.required_ext() or { '' } == '.rs'
	assert Glob.new('/foo/bar/.rs')!.required_ext() or { '' } == '.rs'
	assert Glob.new('.rs')!.required_ext() or { '' } == '.rs'
	assert Glob.new('./rs')!.required_ext() == none
	assert Glob.new('foo')!.required_ext() == none
	assert Glob.new('.foo/')!.required_ext() == none
	assert Glob.new('foo/')!.required_ext() == none
}

fn test_glob_extract_prefix_and_suffix() ! {
	assert Glob.new('/foo')!.prefix() or { '' } == '/foo'
	assert Glob.new('/foo/*')!.prefix() or { '' } == '/foo/'
	assert Glob.new('**/foo')!.prefix() == none
	assert Glob.new('foo/**')!.prefix() or { '' } == 'foo/'
	suffix1, component1 := Glob.new('**/foo/bar')!.suffix() or { panic('missing suffix') }
	assert suffix1 == '/foo/bar'
	assert component1
	suffix2, component2 := Glob.new('*/foo/bar')!.suffix() or { panic('missing suffix') }
	assert suffix2 == '/foo/bar'
	assert !component2
	assert make_test_glob('*/foo/bar', slashlit_test_options()).suffix() == none
	suffix3, component3 := Glob.new('foo/bar')!.suffix() or { panic('missing suffix') }
	assert suffix3 == 'foo/bar'
	assert !component3
	suffix4, component4 := Glob.new('**/*_test')!.suffix() or { panic('missing suffix') }
	assert suffix4 == '_test'
	assert !component4
	suffix5, component5 := Glob.new('*.foo')!.suffix() or { panic('missing suffix') }
	assert suffix5 == '.foo'
	assert !component5
	assert make_test_glob('*.foo', slashlit_test_options()).suffix() == none
}
