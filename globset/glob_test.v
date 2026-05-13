module globset

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
