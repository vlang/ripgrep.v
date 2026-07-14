module regex

import matcher

fn e(pattern string) Seq {
	hir := Hir.from_pattern(pattern, Config.default())
	return Extractor.new().extract_untagged(&hir)
}

fn e_with_config(pattern string, config Config) Seq {
	hir := Hir.from_pattern(pattern, config)
	return Extractor.new().extract_untagged(&hir)
}

fn lit_e(x string) Literal {
	return Literal.exact(x.bytes())
}

fn lit_i(x string) Literal {
	return Literal.inexact(x.bytes())
}

fn seq(it []Literal) Seq {
	return Seq.new(it)
}

fn inexact(it []Literal) Seq {
	return Seq.new(it)
}

fn exact(it []string) Seq {
	mut lits := []Literal{cap: it.len}
	for x in it {
		lits << lit_e(x)
	}
	return Seq.new(lits)
}

fn exact_bytes(it [][]u8) Seq {
	mut lits := []Literal{cap: it.len}
	for x in it {
		lits << Literal.exact(x)
	}
	return Seq.new(lits)
}

fn test_various() {
	assert e(r'foo') == seq([lit_e('foo')])
	assert e(r'[a-z]foo[a-z]') == seq([lit_i('foo')])
	assert e(r'[a-z](foo)(bar)[a-z]') == seq([lit_i('foobar')])
	assert e(r'[a-z]([a-z]foo)(bar[a-z])[a-z]') == seq([lit_i('foo')])
	assert e(r'[a-z]([a-z]foo)([a-z]foo)[a-z]') == seq([lit_i('foo')])
	assert e(r'(\d{1,3}\.){3}\d{1,3}') == seq([lit_i('.')])
	assert e(r'[a-z]([a-z]foo){3}[a-z]') == seq([lit_i('foo')])
	assert e(r'[a-z](foo[a-z]){3}[a-z]') == seq([lit_i('foo')])
	assert e(r'[a-z]([a-z]foo[a-z]){3}[a-z]') == seq([lit_i('foo')])
	assert e(r'[a-z]([a-z]foo){3}(bar[a-z]){3}[a-z]') == seq([lit_i('foo')])
}

// These test that some of our suspicious heuristics try to "pick better
// literals."
fn test_heuristics() {
	// Here, the first literals we stumble across are {ab, cd, ef}. But we
	// keep going and our heuristics decide that {hiya} is better. (And it
	// should be, since it's just one literal and it's longer.)
	assert e(r'[a-z]+(ab|cd|ef)[a-z]+hiya[a-z]+') == seq([lit_i('hiya')])
	// But here, the first alternation becomes "good enough" that literal
	// extraction short circuits early. {hiya} is probably still a better
	// choice here, but {abc, def, ghi} is not bad.
	assert e(r'[a-z]+(abc|def|ghi)[a-z]+hiya[a-z]+') == seq([lit_i('abc'), lit_i('def'),
		lit_i('ghi')])
}

fn test_literal() {
	assert exact(['a']) == e('a')
	assert exact(['aaaaa']) == e('aaaaa')
	assert exact(['A', 'a']) == e('(?i-u)a')
	assert exact(['AB', 'Ab', 'aB', 'ab']) == e('(?i-u)ab')
	assert exact(['abC', 'abc']) == e('ab(?i-u)c')

	assert Seq.infinite() == e(r'(?-u:\xFF)')
	assert exact_bytes(['Z'.bytes()]) == e(r'Z')

	assert exact(['☃']) == e('☃')
	assert exact(['☃']) == e('(?i)☃')
	assert exact(['☃☃☃☃☃']) == e('☃☃☃☃☃')

	assert exact(['Δ']) == e('Δ')
	assert exact(['δ']) == e('δ')
	assert exact(['Δ', 'δ']) == e('(?i)Δ')
	assert exact(['Δ', 'δ']) == e('(?i)δ')

	assert exact(['S', 's', 'ſ']) == e('(?i)S')
	assert exact(['S', 's', 'ſ']) == e('(?i)s')
	assert exact(['S', 's', 'ſ']) == e('(?i)ſ')

	letters := 'ͱͳͷΐάέήίΰαβγδεζηθικλμνξοπρςστυφχψωϊϋ'
	assert exact([letters]) == e(letters)
}

fn test_literal_initial_unicode_mode() {
	mut config := Config.default()
	config.unicode = false
	assert exact(['ſ']) == e_with_config('(?i)ſ', config)
	assert exact(['S', 's', 'ſ']) == e_with_config('(?u:(?i)ſ)', config)
	assert exact(['ſ']) == e('(?i-u)ſ')
}

fn test_inner_literals_respect_backend_acceleration() {
	mut config := Config.default()
	config.line_terminator = matcher.LineTerminator.default()

	accelerated := ConfiguredHIR.new(config.clone(), ['foo[a-z]+'])!
	accelerated_re := accelerated.to_regex()!
	assert accelerated_re.is_accelerated()
	assert !InnerLiterals.new(&accelerated, &accelerated_re).seq.is_finite()

	unicode_word := ConfiguredHIR.new(config.clone(), [r'foo\b[a-z]+'])!
	unicode_word_re := unicode_word.to_regex()!
	assert unicode_word_re.is_accelerated()
	assert unicode_word_re.contains_word_unicode()
	assert InnerLiterals.new(&unicode_word, &unicode_word_re).seq == seq([lit_i('foo')])

	ascii_word := ConfiguredHIR.new(config.clone(), [r'foo(?-u:\b)[a-z]+'])!
	ascii_word_re := ascii_word.to_regex()!
	assert ascii_word_re.is_accelerated()
	assert !ascii_word_re.contains_word_unicode()
	assert !InnerLiterals.new(&ascii_word, &ascii_word_re).seq.is_finite()

	case_folded := ConfiguredHIR.new(config, [r'(?i:e.x|ex)'])!
	case_folded_re := case_folded.to_regex()!
	assert !case_folded_re.is_accelerated()
	assert InnerLiterals.new(&case_folded, &case_folded_re).seq == seq([lit_i('X'),
		lit_i('x')])
}

fn test_literal_seq_dedup_preserves_preference_order() {
	mut non_adjacent := exact(['foo', 'bar', 'foo'])
	non_adjacent.dedup()
	assert non_adjacent == exact(['foo', 'bar', 'foo'])

	mut adjacent := seq([lit_e('foo'), lit_i('foo')])
	adjacent.dedup()
	assert adjacent == seq([lit_i('foo')])
}

fn test_class() {
	assert exact(['a', 'b', 'c']) == e('[abc]')
	assert exact(['a1b', 'a2b', 'a3b']) == e('a[123]b')
	assert exact(['δ', 'ε']) == e('[εδ]')
	assert exact(['Δ', 'Ε', 'δ', 'ε', 'ϵ']) == e(r'(?i)[εδ]')
}

fn test_look() {
	assert exact(['ab']) == e(r'a\Ab')
	assert exact(['ab']) == e(r'a\zb')
	assert exact(['ab']) == e(r'a(?m:^)b')
	assert exact(['ab']) == e(r'a(?m:$)b')
	assert exact(['ab']) == e(r'a\bb')
	assert exact(['ab']) == e(r'a\Bb')
	assert exact(['ab']) == e(r'a(?-u:\b)b')
	assert exact(['ab']) == e(r'a(?-u:\B)b')

	assert exact(['ab']) == e(r'^ab')
	assert exact(['ab']) == e(r'$ab')
	assert exact(['ab']) == e(r'(?m:^)ab')
	assert exact(['ab']) == e(r'(?m:$)ab')
	assert exact(['ab']) == e(r'\bab')
	assert exact(['ab']) == e(r'\Bab')
	assert exact(['ab']) == e(r'(?-u:\b)ab')
	assert exact(['ab']) == e(r'(?-u:\B)ab')

	assert exact(['ab']) == e(r'ab^')
	assert exact(['ab']) == e(r'ab$')
	assert exact(['ab']) == e(r'ab(?m:^)')
	assert exact(['ab']) == e(r'ab(?m:$)')
	assert exact(['ab']) == e(r'ab\b')
	assert exact(['ab']) == e(r'ab\B')
	assert exact(['ab']) == e(r'ab(?-u:\b)')
	assert exact(['ab']) == e(r'ab(?-u:\B)')

	assert seq([lit_i('aZ'), lit_e('ab')]) == e(r'^aZ*b')
}

fn test_repetition() {
	assert Seq.infinite() == e(r'a?')
	assert Seq.infinite() == e(r'a??')
	assert Seq.infinite() == e(r'a*')
	assert Seq.infinite() == e(r'a*?')
	assert inexact([lit_i('a')]) == e(r'a+')
	assert inexact([lit_i('a')]) == e(r'(a+)+')

	assert exact(['ab']) == e(r'aZ{0}b')
	assert exact(['aZb', 'ab']) == e(r'aZ?b')
	assert exact(['ab', 'aZb']) == e(r'aZ??b')
	assert inexact([lit_i('aZ'), lit_e('ab')]) == e(r'aZ*b')
	assert inexact([lit_e('ab'), lit_i('aZ')]) == e(r'aZ*?b')
	assert inexact([lit_i('aZ')]) == e(r'aZ+b')
	assert inexact([lit_i('aZ')]) == e(r'aZ+?b')

	assert exact(['aZZb']) == e(r'aZ{2}b')
	assert inexact([lit_i('aZZ')]) == e(r'aZ{2,3}b')

	assert Seq.infinite() == e(r'(abc)?')
	assert Seq.infinite() == e(r'(abc)??')

	assert inexact([lit_i('a'), lit_e('b')]) == e(r'a*b')
	assert inexact([lit_e('b'), lit_i('a')]) == e(r'a*?b')
	assert inexact([lit_i('ab')]) == e(r'ab+')
	assert inexact([lit_i('a'), lit_i('b')]) == e(r'a*b+')

	assert inexact([lit_i('a'), lit_i('b'), lit_e('c')]) == e(r'a*b*c')
	assert inexact([lit_i('a'), lit_i('b'), lit_e('c')]) == e(r'(a+)?(b+)?c')
	assert inexact([lit_i('a'), lit_i('b'), lit_e('c')]) == e(r'(a+|)(b+|)c')
	// A few more similarish but not identical regexes. These may have a
	// similar problem as above.
	assert Seq.infinite() == e(r'a*b*c*')
	assert inexact([lit_i('a'), lit_i('b'), lit_i('c')]) == e(r'a*b*c+')
	assert inexact([lit_i('a'), lit_i('b')]) == e(r'a*b+c')
	assert inexact([lit_i('a'), lit_i('b')]) == e(r'a*b+c*')
	assert inexact([lit_i('ab'), lit_e('a')]) == e(r'ab*')
	assert inexact([lit_i('ab'), lit_e('ac')]) == e(r'ab*c')
	assert inexact([lit_i('ab')]) == e(r'ab+')
	assert inexact([lit_i('ab')]) == e(r'ab+c')

	assert inexact([lit_i('z'), lit_e('azb')]) == e(r'z*azb')

	mut expected := exact(['aaa', 'aab', 'aba', 'abb', 'baa', 'bab', 'bba', 'bbb'])
	assert expected == e(r'[ab]{3}')
	expected = inexact([
		lit_i('aaa'),
		lit_i('aab'),
		lit_i('aba'),
		lit_i('abb'),
		lit_i('baa'),
		lit_i('bab'),
		lit_i('bba'),
		lit_i('bbb'),
	])
	assert expected == e(r'[ab]{3,4}')
}

fn test_concat() {
	assert exact(['abcxyz']) == e(r'abc()xyz')
	assert exact(['abcxyz']) == e(r'(abc)(xyz)')
	assert exact(['abcmnoxyz']) == e(r'abc()mno()xyz')
	assert Seq.infinite() == e(r'abc[a&&b]xyz')
	assert exact(['abcxyz']) == e(r'abc[a&&b]*xyz')
}

fn test_alternation() {
	assert exact(['abc', 'mno', 'xyz']) == e(r'abc|mno|xyz')
	assert inexact([lit_e('abc'), lit_i('mZ'), lit_e('mo'), lit_e('xyz')]) == e(r'abc|mZ*o|xyz')
	assert exact(['abc', 'xyz']) == e(r'abc|M[a&&b]N|xyz')
	assert exact(['abc', 'MN', 'xyz']) == e(r'abc|M[a&&b]*N|xyz')

	assert exact(['aaa']) == e(r'(?:|aa)aaa')
	assert Seq.infinite() == e(r'(?:|aa)(?:aaa)*')
	assert Seq.infinite() == e(r'(?:|aa)(?:aaa)*?')

	assert Seq.infinite() == e(r'a|b*')
	assert inexact([lit_e('a'), lit_i('b')]) == e(r'a|b+')

	assert inexact([lit_i('a'), lit_e('b'), lit_e('c')]) == e(r'a*b|c')

	assert Seq.infinite() == e(r'a|(?:b|c*)')

	assert inexact([lit_i('a'), lit_i('b'), lit_e('c')]) == e(r'(a|b)*c|(a|ab)*c')

	assert exact(['abef', 'abgh', 'cdef', 'cdgh']) == e(r'(ab|cd)(ef|gh)')
	assert exact(['abefij', 'abefkl', 'abghij', 'abghkl', 'cdefij', 'cdefkl', 'cdghij',
		'cdghkl']) == e(r'(ab|cd)(ef|gh)(ij|kl)')
}

fn test_impossible() {
	// N.B. The extractor in this module "optimizes" the sequence and makes
	// it infinite if it isn't "good." An empty sequence (generated by a
	// concatenantion containing an expression that can never match) is
	// considered "not good." Since infinite sequences are not actionably
	// and disable optimizations, this winds up being okay.
	//
	// The literal extractor in regex-syntax doesn't combine these two
	// steps and makes the caller choose to optimize. That is, it returns
	// the sequences as they are. Which in this case, for some of the tests
	// below, would be an empty Seq and not an infinite Seq.
	assert Seq.infinite() == e(r'[a&&b]')
	assert Seq.infinite() == e(r'a[a&&b]')
	assert Seq.infinite() == e(r'[a&&b]b')
	assert Seq.infinite() == e(r'a[a&&b]b')
	assert exact(['a', 'b']) == e(r'a|[a&&b]|b')
	assert exact(['a', 'b']) == e(r'a|c[a&&b]|b')
	assert exact(['a', 'b']) == e(r'a|[a&&b]d|b')
	assert exact(['a', 'b']) == e(r'a|c[a&&b]d|b')
	assert Seq.infinite() == e(r'[a&&b]*')
	assert exact(['MN']) == e(r'M[a&&b]*N')
}

// This tests patterns that contain something that defeats literal
// detection, usually because it would blow some limit on the total number
// of literals that can be returned.
//
// The main idea is that when literal extraction sees something that
// it knows will blow a limit, it replaces it with a marker that says
// "any literal will match here." While not necessarily true, the
// over-estimation is just fine for the purposes of literal extraction,
// because the imprecision doesn't matter: too big is too big.
//
// This is one of the trickier parts of literal extraction, since we need
// to make sure all of our literal extraction operations correctly compose
// with the markers.
//
// Note that unlike in regex-syntax, some of these have "inner" literals
// extracted where a prefix or suffix would otherwise not be found.
fn test_anything() {
	assert Seq.infinite() == e(r'.')
	assert Seq.infinite() == e(r'(?s).')
	assert Seq.infinite() == e(r'[A-Za-z]')
	assert Seq.infinite() == e(r'[A-Z]')
	assert Seq.infinite() == e(r'[A-Z]{0}')
	assert Seq.infinite() == e(r'[A-Z]?')
	assert Seq.infinite() == e(r'[A-Z]*')
	assert Seq.infinite() == e(r'[A-Z]+')
	assert seq([lit_i('1')]) == e(r'1[A-Z]')
	assert seq([lit_i('1')]) == e(r'1[A-Z]2')
	assert seq([lit_i('123')]) == e(r'[A-Z]+123')
	assert seq([lit_i('123')]) == e(r'[A-Z]+123[A-Z]+')
	assert Seq.infinite() == e(r'1|[A-Z]|3')
	assert seq([lit_e('1'), lit_i('2'), lit_e('3')]) == e(r'1|2[A-Z]|3')
	assert seq([lit_e('1'), lit_i('2'), lit_e('3')]) == e(r'1|[A-Z]2[A-Z]|3')
	assert seq([lit_e('1'), lit_i('2'), lit_e('3')]) == e(r'1|[A-Z]2|3')
	assert seq([lit_e('1'), lit_i('2'), lit_e('4')]) == e(r'1|2[A-Z]3|4')
	assert seq([lit_i('2')]) == e(r'(?:|1)[A-Z]2')
	assert inexact([lit_i('a')]) == e(r'a.z')
}

fn test_empty() {
	assert Seq.infinite() == e(r'')
	assert Seq.infinite() == e(r'^')
	assert Seq.infinite() == e(r'$')
	assert Seq.infinite() == e(r'(?m:^)')
	assert Seq.infinite() == e(r'(?m:$)')
	assert Seq.infinite() == e(r'\b')
	assert Seq.infinite() == e(r'\B')
	assert Seq.infinite() == e(r'(?-u:\b)')
	assert Seq.infinite() == e(r'(?-u:\B)')
}

fn test_crazy_repeats() {
	assert Seq.infinite() == e(r'(?:){4294967295}')
	assert Seq.infinite() == e(r'(?:){64}{64}{64}{64}{64}{64}')
	assert Seq.infinite() == e(r'x{0}{4294967295}')
	assert Seq.infinite() == e(r'(?:|){4294967295}')

	assert Seq.infinite() == e(r'(?:){8}{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}')
	repa := 'a'.repeat(100)
	assert inexact([lit_i(repa)]) == e(r'a{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}{8}')
}

fn test_optimize() {
	// This gets a common prefix that isn't too short.
	mut s := e(r'foobarfoobar|foobar|foobarzfoobar|foobarfoobar')
	assert seq([lit_i('foobar')]) == s

	// This also finds a common prefix, but since it's only one byte, it
	// prefers the multiple literals.
	s = e(r'abba|akka|abccba')
	assert exact(['abba', 'akka', 'abccba']) == s

	s = e(r'sam|samwise')
	assert seq([lit_e('sam')]) == s

	// The empty string is poisonous, so our seq becomes infinite, even
	// though all literals are exact.
	s = e(r'foobarfoo|foo||foozfoo|foofoo')
	assert Seq.infinite() == s

	// A space is also poisonous, so our seq becomes infinite. But this
	// only gets triggered when we don't have a completely exact sequence.
	// When the sequence is exact, spaces are okay, since we presume that
	// any prefilter will match a space more quickly than the regex engine.
	// (When the sequence is exact, there's a chance of the prefilter being
	// used without needing the regex engine at all.)
	s = e(r'foobarfoo|foo| |foofoo')
	assert Seq.infinite() == s
}

// Regression test for: https://github.com/BurntSushi/ripgrep/issues/2884
fn test_case_insensitive_alternation() {
	s := e(r'(?i:e.x|ex)')
	assert s == seq([lit_i('X'), lit_i('x')])
}
