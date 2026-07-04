module globset

struct TestOptions {
	casei      bool
	has_casei  bool
	litsep     bool
	has_litsep bool
	bsesc      bool
	has_bsesc  bool
	ealtre     bool
	has_ealtre bool
	unccls     bool
	has_unccls bool
}

fn make_test_glob(pattern string, options TestOptions) Glob {
	owned := pattern.to_owned()
	mut builder := GlobBuilder.new(&owned)
	if options.has_casei {
		builder.case_insensitive(options.casei)
	}
	if options.has_litsep {
		builder.literal_separator(options.litsep)
	}
	if options.has_bsesc {
		builder.backslash_escape(options.bsesc)
	}
	if options.has_ealtre {
		builder.empty_alternates(options.ealtre)
	}
	if options.has_unccls {
		builder.allow_unclosed_class(options.unccls)
	}
	return builder.build() or { panic(err) }
}

fn default_test_options() TestOptions {
	return TestOptions{}
}

fn slashlit_test_options() TestOptions {
	return TestOptions{
		litsep:     true
		has_litsep: true
	}
}

fn casei_test_options() TestOptions {
	return TestOptions{
		casei:     true
		has_casei: true
	}
}

fn ealtre_test_options() TestOptions {
	return TestOptions{
		bsesc:      true
		has_bsesc:  true
		ealtre:     true
		has_ealtre: true
	}
}

fn unccls_test_options() TestOptions {
	return TestOptions{
		unccls:     true
		has_unccls: true
	}
}

fn test_glob_parser_basic_tokens() {
	glob := Glob.new('a?b') or { panic(err) }
	assert glob.tokens.str() == '[Literal(a),Any,Literal(b)]'
}

fn test_glob_parser_recursive_tokens() {
	glob := Glob.new('a/**/b') or { panic(err) }
	assert glob.tokens.str() == '[Literal(a),RecursiveZeroOrMore,Literal(b)]'
}

fn test_glob_parser_class_and_alternates() {
	class_glob := Glob.new('[!a-z]') or { panic(err) }
	assert class_glob.tokens.str() == '[Class(true,[(a,z)])]'
	alt_glob := Glob.new('{a,b}') or { panic(err) }
	assert alt_glob.tokens.str() == '[Alternates([[Literal(a)],[Literal(b)]])]'
}

fn test_glob_parser_class_edge_cases() {
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
		glob := Glob.new(pattern) or { panic(err) }
		got := glob.tokens.str()
		assert got == expected, '${pattern}: expected ${expected}, got ${got}'
	}
}

fn test_glob_parser_errors() {
	for pattern in ['[', '[]', '[!', '[!]'] {
		Glob.new(pattern) or {
			assert err.msg().contains('unclosed character class')
			continue
		}
		assert false, 'expected unclosed class error for ${pattern}'
	}
	Glob.new('[z-a]') or {
		assert err.msg().contains("invalid range; 'z' > 'a'")
		return
	}
	assert false, 'expected invalid range error'
}

fn test_glob_regex_output_uses_non_unicode_bytes_mode() {
	assert *(Glob.new('a')!.regex()) == '(?-u)^a$'
	assert *(Glob.new('a?b')!.regex()) == '(?-u)^a.b$'
	assert *(Glob.new('**')!.regex()) == '(?-u)^.*$'
	assert *(Glob.new('**/foo')!.regex()) == '(?-u)^(?:/?|.*/)foo$'
}

fn test_glob_regex_output_escapes_literals() {
	assert *(Glob.new('a.b')!.regex()) == r'(?-u)^a\.b$'
	assert *(Glob.new('a+b')!.regex()) == r'(?-u)^a\+b$'
	assert *(Glob.new('a(b)')!.regex()) == r'(?-u)^a\(b\)$'
}

fn test_glob_regex_output_upstream_cases() {
	cases := {
		'':              '(?-u)^$'
		'?':             '(?-u)^.$'
		'*':             '(?-u)^.*$'
		'[*]':           r'(?-u)^[\*]$'
		'[+]':           r'(?-u)^[\+]$'
		'+':             r'(?-u)^\+$'
		'☃':             r'(?-u)^\xe2\x98\x83$'
		'**/':           '(?-u)^.*$'
		'**/*':          '(?-u)^(?:/?|.*/).*$'
		'**/**':         '(?-u)^.*$'
		'a/**':          '(?-u)^a/.*$'
		'a/**/b':        '(?-u)^a(?:/|/.*/)b$'
		'**/b':          '(?-u)^(?:/?|.*/)b$'
		'a**b':          '(?-u)^a.*.*b$'
		'***':           '(?-u)^.*.*.*$'
		'{a,b}':         '(?-u)^(?:a|b)$'
		'{a,{b,c}}':     '(?-u)^(?:a|(?:b|c))$'
		'{{a,b},{c,d}}': '(?-u)^(?:(?:a|b)|(?:c|d))$'
	}
	for pattern, expected in cases {
		assert *(Glob.new(pattern)!.regex()) == expected
	}
}

fn test_glob_regex_output_options() {
	assert *(make_test_glob('a', casei_test_options()).regex()) == '(?-u)(?i)^a$'
	assert *(make_test_glob('?', slashlit_test_options()).regex()) == '(?-u)^[^/]$'
	assert *(make_test_glob('*', slashlit_test_options()).regex()) == '(?-u)^[^/]*$'
	assert *(make_test_glob('[', unccls_test_options()).regex()) == r'(?-u)^\[$'
	assert *(make_test_glob('[abc', unccls_test_options()).regex()) == r'(?-u)^\[abc$'
	assert *(make_test_glob('{[abc,xyz}', unccls_test_options()).regex()) == r'(?-u)^(?:\[abc|xyz)$'
}

fn test_glob_matcher_matches() {
	glob := Glob.new('*.rs') or { panic(err) }
	matcher := glob.compile_matcher()
	assert matcher.is_match('foo.rs')
	assert matcher.is_match('foo/bar.rs')
	assert !matcher.is_match('Cargo.toml')
}

fn test_glob_matcher_literal_separator() {
	pattern := '*.rs'
	mut builder := GlobBuilder.new(&pattern)
	builder.literal_separator(true)
	glob := builder.build() or { panic(err) }
	matcher := glob.compile_matcher()
	assert matcher.is_match('foo.rs')
	assert !matcher.is_match('foo/bar.rs')
}

fn test_glob_matcher_recursive_prefix() {
	glob := Glob.new('**/foo') or { panic(err) }
	matcher := glob.compile_matcher()
	assert matcher.is_match('foo')
	assert matcher.is_match('bar/foo')
	assert !matcher.is_match('foo/bar')
}

fn test_glob_matcher_empty_alternates() {
	pattern := 'foo{,.txt}'
	mut builder := GlobBuilder.new(&pattern)
	builder.empty_alternates(true)
	glob := builder.build() or { panic(err) }
	matcher := glob.compile_matcher()
	assert matcher.is_match('foo')
	assert matcher.is_match('foo.txt')
}

fn test_glob_matcher_unclosed_class_allowed() {
	pattern := '[abc'
	mut builder := GlobBuilder.new(&pattern)
	builder.allow_unclosed_class(true)
	glob := builder.build() or { panic(err) }
	matcher := glob.compile_matcher()
	assert matcher.is_match('[abc')
}

fn test_glob_matcher_upstream_cases() {
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

fn test_glob_matcher_upstream_negative_cases() {
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

fn test_glob_matcher_option_cases() {
	assert make_test_glob('aBcDeFg', casei_test_options()).compile_matcher().is_match('ABCDEFG')
	assert !make_test_glob('abc?def', slashlit_test_options()).compile_matcher().is_match('abc/def')
	assert !make_test_glob('abc*def', slashlit_test_options()).compile_matcher().is_match('abc/def')
	assert make_test_glob('foo{,.txt}', ealtre_test_options()).compile_matcher().is_match('foo')
}

fn test_glob_extract_literal_and_basename() {
	assert Glob.new('foo')!.literal() or { '' } == 'foo'
	assert Glob.new('/foo/bar')!.literal() or { '' } == '/foo/bar'
	assert Glob.new('*.foo')!.literal() == none
	assert make_test_glob('foo', casei_test_options()).literal() == none
	assert Glob.new('**/foo')!.basename_literal() or { '' } == 'foo'
	assert Glob.new('foo')!.basename_literal() == none
	assert Glob.new('*foo')!.basename_literal() == none
	assert Glob.new('*/foo')!.basename_literal() == none
	assert Glob.new('**/fo*o')!.basename_tokens() == none
	basename_tokens := (make_test_glob('**/fo*o', slashlit_test_options()).basename_tokens() or {
		panic('missing basename tokens')
	}).str()
	assert basename_tokens == '[Literal(f), Literal(o), ZeroOrMore, Literal(o)]', basename_tokens
}

fn test_glob_extract_extensions() {
	assert Glob.new('**/*.rs')!.ext() or { '' } == '.rs'
	assert Glob.new('**/*.rs.bak')!.ext() == none
	assert Glob.new('*.rs')!.ext() or { '' } == '.rs'
	assert Glob.new('a*.rs')!.ext() == none
	assert Glob.new('/*.c')!.ext() == none
	assert make_test_glob('*.c', slashlit_test_options()).ext() == none
	assert Glob.new('*.c')!.required_ext() or { '' } == '.c'
	assert Glob.new('/foo/bar/*.rs')!.required_ext() or { '' } == '.rs'
	assert Glob.new('.rs')!.required_ext() or { '' } == '.rs'
	assert Glob.new('./rs')!.required_ext() == none
	assert Glob.new('foo')!.required_ext() == none
	assert Glob.new('.foo/')!.required_ext() == none
}

fn test_glob_extract_prefix_and_suffix() {
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
}
