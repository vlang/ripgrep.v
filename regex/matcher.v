module regex

import matcher
import regex.pcre

$if !windows {
	#include <string.h>
	fn C.memmem(haystack voidptr, haystacklen usize, needle voidptr, needlelen usize) voidptr
	fn C.memchr(s voidptr, c int, n usize) voidptr
	fn C.memcmp(s1 voidptr, s2 voidptr, n usize) int
}

/// A builder for constructing a `Matcher` using regular expressions.
///
/// This builder re-exports many of the same options found on the regex crate's
/// builder, in addition to a few other options such as smart case, word
/// matching and the ability to set a line terminator which may enable certain
/// types of optimizations.
///
/// The syntax supported is documented as part of the regex crate:
/// <https://docs.rs/regex/#syntax>.
///
/// V-specific: matching is currently implemented with V's `regex.pcre`
/// backend plus translated HIR/literal analysis. This is not a full semantic
/// replacement for Rust ripgrep's `regex-automata::meta::Regex` backend.
pub struct RegexMatcherBuilder implements IClone {
mut:
	config Config
}

pub fn RegexMatcherBuilder.default() RegexMatcherBuilder {
	return RegexMatcherBuilder.new()
}

/// Create a new builder for configuring a regex matcher.
pub fn RegexMatcherBuilder.new() RegexMatcherBuilder {
	return RegexMatcherBuilder{
		config: Config.default()
	}
}

/// Build a new matcher using the current configuration for the provided
/// pattern.
///
/// The syntax supported is documented as part of the regex crate:
/// <https://docs.rs/regex/#syntax>.
pub fn (builder RegexMatcherBuilder) build(pattern string) !RegexMatcher {
	return builder.build_many([pattern.to_owned()])
}

/// Build a new matcher using the current configuration for the provided
/// patterns. The resulting matcher behaves as if all of the patterns
/// given are joined together into a single alternation. That is, it
/// reports matches where at least one of the given patterns matches.
pub fn (builder RegexMatcherBuilder) build_many(patterns []string) !RegexMatcher {
	if patterns.len == 0 {
		mut config := builder.config.clone()
		never := pcre.compile(r'\b\B') or { return Error.regex(err.msg()) }
		config.line_terminator = builder.config.line_terminator
		return RegexMatcher{
			config:               config
			regex:                never
			byte_literal:         none
			unicode_case_literal: none
			simple_ascii:         none
			fast_line_regex:      none
			non_matching_bytes:   matcher.ByteSet.full()
		}
	}
	byte_literal := byte_literal_from_patterns(patterns.clone(), builder.config)
	unicode_case_literal := unicode_case_literal_from_patterns(patterns.clone(), builder.config)
	simple_ascii := simple_ascii_from_patterns(patterns.clone(), builder.config)
	mut chir := builder.config.build_many(patterns)!
	// 'whole_line' is a strict subset of 'word', so when it is enabled,
	// we don't need to both with any specific to word matching.
	if chir.config().whole_line {
		chir = chir.into_whole_line()
	} else if chir.config().word {
		chir = chir.into_word()
	}
	regex := chir.to_regex()!
	non_matching_bytes := chir.non_matching_bytes()
	// If we can pick out some literals from the regex, then we might be
	// able to build a faster regex that quickly identifies candidate
	// matching lines. The regex engine will do what it can on its own, but
	// we can specifically do a little more when a line terminator is set.
	// For example, for a regex like `\w+foo\w+`, we can look for `foo`,
	// and when a match is found, look for the line containing `foo` and
	// then run the original regex on only that line. (In this case, the
	// regex engine is likely to handle this case for us since it's so
	// simple, but the idea applies.)
	//
	fast := InnerLiterals.new(&chir, &regex).one_regex()!
	mut fast_line_regex := ?pcre.Regex(none)
	if fast.has_value {
		fast_line_regex = ?pcre.Regex(fast.value)
	}
	// We override the line terminator in case the configured HIR doesn't
	// support it.
	mut config := builder.config.clone()
	config.line_terminator = chir.line_terminator()
	return RegexMatcher{
		config:               config
		regex:                regex
		byte_literal:         byte_literal
		unicode_case_literal: unicode_case_literal
		simple_ascii:         simple_ascii
		fast_line_regex:      fast_line_regex
		non_matching_bytes:   non_matching_bytes
	}
}

/// Build a new matcher from a plain alternation of literals.
///
/// Depending on the configuration set by the builder, this may be able to
/// build a matcher substantially faster than by joining the patterns with
/// a `|` and calling `build`.
pub fn (builder RegexMatcherBuilder) build_literals(literals []string) !RegexMatcher {
	return builder.build_many(literals)
}

/// Set the value for the case insensitive (`i`) flag.
///
/// When enabled, letters in the pattern will match both upper case and
/// lower case variants.
pub fn (mut builder RegexMatcherBuilder) case_insensitive(yes bool) &RegexMatcherBuilder {
	builder.config.case_insensitive = yes
	return builder
}

/// Whether to enable "smart case" or not.
///
/// When smart case is enabled, the builder will automatically enable
/// case insensitive matching based on how the pattern is written. Namely,
/// case insensitive mode is enabled when both of the following things
/// are true:
///
/// 1. The pattern contains at least one literal character. For example,
///    `a\w` contains a literal (`a`) but `\w` does not.
/// 2. Of the literals in the pattern, none of them are considered to be
///    uppercase according to Unicode. For example, `foo\pL` has no
///    uppercase literals but `Foo\pL` does.
pub fn (mut builder RegexMatcherBuilder) case_smart(yes bool) &RegexMatcherBuilder {
	builder.config.case_smart = yes
	return builder
}

/// Set the value for the multi-line matching (`m`) flag.
///
/// When enabled, `^` matches the beginning of lines and `$` matches the
/// end of lines.
///
/// By default, they match beginning/end of the input.
pub fn (mut builder RegexMatcherBuilder) multi_line(yes bool) &RegexMatcherBuilder {
	builder.config.multi_line = yes
	return builder
}

/// Set the value for the any character (`s`) flag, where in `.` matches
/// anything when `s` is set and matches anything except for new line when
/// it is not set (the default).
///
/// N.B. "matches anything" means "any byte" when Unicode is disabled and
/// means "any valid UTF-8 encoding of any Unicode scalar value" when
/// Unicode is enabled.
pub fn (mut builder RegexMatcherBuilder) dot_matches_new_line(yes bool) &RegexMatcherBuilder {
	builder.config.dot_matches_new_line = yes
	return builder
}

/// Set the value for the greedy swap (`U`) flag.
///
/// When enabled, a pattern like `a*` is lazy (tries to find shortest
/// match) and `a*?` is greedy (tries to find longest match).
///
/// By default, `a*` is greedy and `a*?` is lazy.
pub fn (mut builder RegexMatcherBuilder) swap_greed(yes bool) &RegexMatcherBuilder {
	builder.config.swap_greed = yes
	return builder
}

/// Set the value for the ignore whitespace (`x`) flag.
///
/// When enabled, whitespace such as new lines and spaces will be ignored
/// between expressions of the pattern, and `#` can be used to start a
/// comment until the next new line.
pub fn (mut builder RegexMatcherBuilder) ignore_whitespace(yes bool) &RegexMatcherBuilder {
	builder.config.ignore_whitespace = yes
	return builder
}

/// Set the value for the Unicode (`u`) flag.
///
/// Enabled by default. When disabled, character classes such as `\w` only
/// match ASCII word characters instead of all Unicode word characters.
pub fn (mut builder RegexMatcherBuilder) unicode(yes bool) &RegexMatcherBuilder {
	builder.config.unicode = yes
	return builder
}

/// Whether to support octal syntax or not.
///
/// Octal syntax is a little-known way of uttering Unicode codepoints in
/// a regular expression. For example, `a`, `\x61`, `\u0061` and
/// `\141` are all equivalent regular expressions, where the last example
/// shows octal syntax.
///
/// While supporting octal syntax isn't in and of itself a problem, it does
/// make good error messages harder. That is, in PCRE based regex engines,
/// syntax like `\0` invokes a backreference, which is explicitly
/// unsupported in Rust's regex engine. However, many users expect it to
/// be supported. Therefore, when octal support is disabled, the error
/// message will explicitly mention that backreferences aren't supported.
///
/// Octal syntax is disabled by default.
pub fn (mut builder RegexMatcherBuilder) octal(yes bool) &RegexMatcherBuilder {
	builder.config.octal = yes
	return builder
}

/// Set the approximate size limit of the compiled regular expression.
///
/// This roughly corresponds to the number of bytes occupied by a single
/// compiled program. If the program exceeds this number, then a
/// compilation error is returned.
pub fn (mut builder RegexMatcherBuilder) size_limit(bytes usize) &RegexMatcherBuilder {
	builder.config.size_limit = bytes
	return builder
}

/// Set the approximate size of the cache used by the DFA.
///
/// This roughly corresponds to the number of bytes that the DFA will
/// use while searching.
///
/// Note that this is a *per thread* limit. There is no way to set a global
/// limit. In particular, if a regex is used from multiple threads
/// simultaneously, then each thread may use up to the number of bytes
/// specified here.
pub fn (mut builder RegexMatcherBuilder) dfa_size_limit(bytes usize) &RegexMatcherBuilder {
	builder.config.dfa_size_limit = bytes
	return builder
}

/// Set the nesting limit for this parser.
///
/// The nesting limit controls how deep the abstract syntax tree is allowed
/// to be. If the AST exceeds the given limit (e.g., with too many nested
/// groups), then an error is returned by the parser.
///
/// The purpose of this limit is to act as a heuristic to prevent stack
/// overflow for consumers that do structural induction on an `Ast` using
/// explicit recursion. While this crate never does this (instead using
/// constant stack space and moving the call stack to the heap), other
/// crates may.
///
/// This limit is not checked until the entire Ast is parsed. Therefore,
/// if callers want to put a limit on the amount of heap space used, then
/// they should impose a limit on the length, in bytes, of the concrete
/// pattern string. In particular, this is viable since this parser
/// implementation will limit itself to heap space proportional to the
/// length of the pattern string.
///
/// Note that a nest limit of `0` will return a nest limit error for most
/// patterns but not all. For example, a nest limit of `0` permits `a` but
/// not `ab`, since `ab` requires a concatenation, which results in a nest
/// depth of `1`. In general, a nest limit is not something that manifests
/// in an obvious way in the concrete syntax, therefore, it should not be
/// used in a granular way.
pub fn (mut builder RegexMatcherBuilder) nest_limit(limit u32) &RegexMatcherBuilder {
	builder.config.nest_limit = limit
	return builder
}

/// Set an ASCII line terminator for the matcher.
///
/// The purpose of setting a line terminator is to enable a certain class
/// of optimizations that can make line oriented searching faster. Namely,
/// when a line terminator is enabled, then the builder will guarantee that
/// the resulting matcher will never be capable of producing a match that
/// contains the line terminator. Because of this guarantee, users of the
/// resulting matcher do not need to slowly execute a search line by line
/// for line oriented search.
///
/// If the aforementioned guarantee about not matching a line terminator
/// cannot be made because of how the pattern was written, then the builder
/// will return an error when attempting to construct the matcher. For
/// example, the pattern `a\sb` will be transformed such that it can never
/// match `a\nb` (when `\n` is the line terminator), but the pattern `a\nb`
/// will result in an error since the `\n` cannot be easily removed without
/// changing the fundamental intent of the pattern.
///
/// If the given line terminator isn't an ASCII byte (`<=127`), then the
/// builder will return an error when constructing the matcher.
pub fn (mut builder RegexMatcherBuilder) line_terminator(line_term ?u8) &RegexMatcherBuilder {
	if byte := line_term {
		builder.config.line_terminator = matcher.LineTerminator.byte(byte)
	} else {
		builder.config.line_terminator = none
	}
	return builder
}

/// Ban a byte from occurring in a regular expression pattern.
///
/// If this byte is found in the regex pattern, then an error will be
/// returned at construction time.
///
/// This is useful when binary detection is enabled. Callers will likely
/// want to ban the same byte that is used to detect binary data, i.e.,
/// the NUL byte. The reason for this is that when binary detection is
/// enabled, it's impossible to match a NUL byte because binary detection
/// will either quit when one is found, or will convert NUL bytes to line
/// terminators to avoid exorbitant heap usage.
pub fn (mut builder RegexMatcherBuilder) ban_byte(byte ?u8) &RegexMatcherBuilder {
	builder.config.ban = byte
	return builder
}

/// Set the line terminator to `\r\n` and enable CRLF matching for `$` in
/// regex patterns.
///
/// This method sets two distinct settings:
///
/// 1. It causes the line terminator for the matcher to be `\r\n`. Namely,
///    this prevents the matcher from ever producing a match that contains
///    a `\r` or `\n`.
/// 2. It enables CRLF mode for `^` and `$`. This means that line anchors
///    will treat both `\r` and `\n` as line terminators, but will never
///    match between a `\r` and `\n`.
///
/// Note that if you do not wish to set the line terminator but would
/// still like `$` to match `\r\n` line terminators, then it is valid to
/// call `crlf(true)` followed by `line_terminator(None)`. Ordering is
/// important, since `crlf` sets the line terminator, but `line_terminator`
/// does not touch the `crlf` setting.
pub fn (mut builder RegexMatcherBuilder) crlf(yes bool) &RegexMatcherBuilder {
	if yes {
		builder.config.line_terminator = matcher.LineTerminator.crlf()
	} else {
		builder.config.line_terminator = none
	}
	builder.config.crlf = yes
	return builder
}

/// Require that all matches occur on word boundaries.
///
/// Enabling this option is subtly different than putting `\b` assertions
/// on both sides of your pattern. In particular, a `\b` assertion requires
/// that one side of it match a word character while the other match a
/// non-word character. This option, in contrast, merely requires that
/// one side match a non-word character.
///
/// For example, `\b-2\b` will not match `foo -2 bar` since `-` is not a
/// word character. However, `-2` with this `word` option enabled will
/// match the `-2` in `foo -2 bar`.
pub fn (mut builder RegexMatcherBuilder) word(yes bool) &RegexMatcherBuilder {
	builder.config.word = yes
	return builder
}

/// Whether the patterns should be treated as literal strings or not. When
/// this is active, all characters, including ones that would normally be
/// special regex meta characters, are matched literally.
pub fn (mut builder RegexMatcherBuilder) fixed_strings(yes bool) &RegexMatcherBuilder {
	builder.config.fixed_strings = yes
	return builder
}

/// Whether each pattern should match the entire line or not. This is
/// equivalent to surrounding the pattern with `(?m:^)` and `(?m:$)`.
pub fn (mut builder RegexMatcherBuilder) whole_line(yes bool) &RegexMatcherBuilder {
	builder.config.whole_line = yes
	return builder
}

/// An implementation of the `Matcher` trait using Rust's standard regex
/// library.
pub struct RegexMatcher implements IClone {
	/// The configuration specified by the caller.
	config Config
	/// The regular expression compiled from the pattern provided by the
	/// caller.
	regex pcre.Regex
	/// A raw byte literal matcher used for simple non-Unicode byte patterns.
	byte_literal ?[]u8
	/// A Unicode literal matcher used when the backend cannot case fold
	/// non-ASCII literals.
	unicode_case_literal ?string
	/// A small ASCII-only regex matcher for one-byte character class suffixes.
	simple_ascii ?SimpleAsciiPattern
	/// A regex that never reports false negatives but may report false
	/// positives that is believed to be capable of being matched more quickly
	/// than `regex`. Typically, this is a single literal or an alternation
	/// of literals.
	fast_line_regex ?pcre.Regex
	/// A set of bytes that will never appear in a match.
	non_matching_bytes matcher.ByteSet
}

/// Create a new matcher from the given pattern using the default
/// configuration.
pub fn RegexMatcher.new(pattern string) !RegexMatcher {
	return RegexMatcherBuilder.new().build(pattern)
}

/// Create a new matcher from the given pattern using the default
/// configuration, but matches lines terminated by `\n`.
///
/// This is meant to be a convenience constructor for
/// using a `RegexMatcherBuilder` and setting its
/// [`line_terminator`](RegexMatcherBuilder::method.line_terminator) to
/// `\n`. The purpose of using this constructor is to permit special
/// optimizations that help speed up line oriented search. These types of
/// optimizations are only appropriate when matches span no more than one
/// line. For this reason, this constructor will return an error if the
/// given pattern contains a literal `\n`. Other uses of `\n` (such as in
/// `\s`) are removed transparently.
pub fn RegexMatcher.new_line_matcher(pattern string) !RegexMatcher {
	mut builder := RegexMatcherBuilder.new()
	builder.line_terminator(`\n`)
	return builder.build(pattern)
}

// This implementation just dispatches on the internal matcher impl except
// for the line terminator optimization, which is possibly executed via
// `fast_line_regex`.
pub fn (re RegexMatcher) find_at(haystack []u8, at usize) !matcher.FallibleMatch {
	found, _ := re.capture_groups_at(haystack, at)!
	return found
}

pub fn (re RegexMatcher) capture_groups_at(haystack []u8, at usize) !(matcher.FallibleMatch, []string) {
	if at > haystack.len {
		return matcher.FallibleMatch.absent(), []string{}
	}
	if literal := re.byte_literal {
		mut start := at
		for {
			found := find_byte_literal_at(haystack, literal, start)!
			mat := found.get() or { return matcher.FallibleMatch.absent(), []string{} }
			if re.accept_match(haystack, mat) {
				return matcher.FallibleMatch.some(mat), []string{}
			}
			start = mat.start() + 1
			if start > haystack.len {
				return matcher.FallibleMatch.absent(), []string{}
			}
		}
	}
	if literal := re.unicode_case_literal {
		return find_unicode_case_literal_at(haystack, literal, at)!, []string{}
	}
	if simple := re.simple_ascii {
		mut start := at
		for {
			found := find_simple_ascii_at(haystack, simple, start)!
			mat := found.get() or { return matcher.FallibleMatch.absent(), []string{} }
			if re.accept_match(haystack, mat) {
				return matcher.FallibleMatch.some(mat), []string{}
			}
			start = mat.start() + 1
			if start > haystack.len {
				return matcher.FallibleMatch.absent(), []string{}
			}
		}
	}
	text := haystack.bytestr()
	mut start := int(at)
	for start <= text.len {
		found := re.regex.find_from(text, start) or { return matcher.FallibleMatch.absent(), []string{} }
		mat := matcher.Match.new(usize(found.start), usize(found.end))
		if re.accept_match(haystack, mat) {
			return matcher.FallibleMatch.some(mat), found.groups.clone()
		}
		next := if found.end > found.start { found.start + 1 } else { found.end + 1 }
		if next <= start {
			start++
		} else {
			start = next
		}
	}
	return matcher.FallibleMatch.absent(), []string{}
}

pub fn (re RegexMatcher) new_captures() !matcher.NoCaptures {
	_ = re
	return matcher.NoCaptures.new()
}

pub fn (re RegexMatcher) capture_count() usize {
	return usize(re.regex.total_groups + 1)
}

pub fn (re RegexMatcher) capture_index(name string) ?usize {
	if index := re.regex.group_map[name] {
		return usize(index + 1)
	}
	return none
}

pub fn (re RegexMatcher) captures_at(haystack []u8, at usize, mut caps matcher.NoCaptures) !bool {
	_ = caps
	return re.find_at(haystack, at)!.is_some()
}

pub fn (re &^a RegexMatcher) non_matching_bytes[^a]() ?&^a matcher.ByteSet {
	return &re.non_matching_bytes
}

pub fn (re RegexMatcher) line_terminator() ?matcher.LineTerminator {
	return re.config.line_terminator
}

pub fn (re RegexMatcher) find_candidate_line(haystack []u8) !matcher.FallibleLineMatchKind {
	if literal := re.byte_literal {
		found := find_byte_literal_at(haystack, literal, 0)!
		if found.has_value {
			return matcher.FallibleLineMatchKind.some(matcher.LineMatchKind.confirmed(found.value.end()))
		}
		return matcher.FallibleLineMatchKind.absent()
	}
	if literal := re.unicode_case_literal {
		found := find_unicode_case_literal_at(haystack, literal, 0)!
		if found.has_value {
			return matcher.FallibleLineMatchKind.some(matcher.LineMatchKind.confirmed(found.value.end()))
		}
		return matcher.FallibleLineMatchKind.absent()
	}
	if simple := re.simple_ascii {
		found := find_simple_ascii_at(haystack, simple, 0)!
		if found.has_value {
			return matcher.FallibleLineMatchKind.some(matcher.LineMatchKind.confirmed(found.value.end()))
		}
		return matcher.FallibleLineMatchKind.absent()
	}
	if fast := re.fast_line_regex {
		text := haystack.bytestr()
		if mat := fast.find(text) {
			return matcher.FallibleLineMatchKind.some(matcher.LineMatchKind.candidate(usize(mat.end)))
		}
		return matcher.FallibleLineMatchKind.absent()
	}
	maybe_mat := re.find_at(haystack, 0)!
	if !maybe_mat.has_value {
		return matcher.FallibleLineMatchKind.absent()
	}
	end := maybe_mat.value.end()
	return matcher.FallibleLineMatchKind.some(matcher.LineMatchKind.confirmed(end))
}

fn (re RegexMatcher) accept_match(haystack []u8, mat matcher.Match) bool {
	if re.config.whole_line && !is_whole_line_match(re.config, haystack, mat) {
		return false
	}
	if re.config.word && !is_word_match(haystack, mat) {
		return false
	}
	return true
}

fn is_whole_line_match(config Config, haystack []u8, mat matcher.Match) bool {
	start := mat.start()
	end := mat.end()
	if start > 0 && haystack[start - 1] != config_line_byte(config) {
		return false
	}
	if end >= haystack.len {
		return true
	}
	if config.crlf && haystack[end] == `\r` && end + 1 < haystack.len && haystack[end + 1] == `\n` {
		return true
	}
	return haystack[end] == config_line_byte(config)
}

fn config_line_byte(config Config) u8 {
	if line_term := config.line_terminator {
		return line_term.as_byte()
	}
	return `\n`
}

fn is_word_match(haystack []u8, mat matcher.Match) bool {
	start := mat.start()
	end := mat.end()
	left_ok := start == 0 || !is_word_byte(haystack[start - 1])
	right_ok := end >= haystack.len || !is_word_byte(haystack[end])
	return left_ok && right_ok
}

fn is_word_byte(byte u8) bool {
	return (byte >= `A` && byte <= `Z`) || (byte >= `a` && byte <= `z`)
		|| (byte >= `0` && byte <= `9`) || byte == `_`
}

struct SimpleAsciiPattern implements IClone {
	prefix    []u8
	class     []bool
	match_len usize
}

fn byte_literal_from_patterns(patterns []string, config Config) ?[]u8 {
	if patterns.len != 1 {
		return none
	}
	return byte_literal_from_pattern(patterns[0].clone(), config)
}

fn unicode_case_literal_from_patterns(patterns []string, config Config) ?string {
	if !config.unicode || !config.case_insensitive || patterns.len != 1 {
		return none
	}
	pattern := patterns[0]
	if !pattern_has_non_ascii(pattern) {
		return none
	}
	for ch in pattern {
		if is_regex_meta_character(ch) {
			return none
		}
	}
	return pattern.to_owned()
}

fn pattern_has_non_ascii(pattern string) bool {
	for b in pattern.bytes() {
		if b >= 0x80 {
			return true
		}
	}
	return false
}

fn byte_literal_from_pattern(pattern string, config Config) ?[]u8 {
	if config.fixed_strings {
		if !can_use_ascii_byte_literal(pattern, config) {
			return none
		}
		return pattern.bytes()
	}
	if can_use_ascii_byte_literal(pattern, config) && !pattern_has_regex_meta(pattern) {
		return pattern.bytes()
	}
	if !pattern.starts_with('(?-u)') {
		return none
	}
	mut i := 5
	if i >= pattern.len {
		return none
	}
	mut bytes := []u8{}
	for i < pattern.len {
		if pattern[i] == `\\` {
			has_byte, byte, next := parse_escape_byte(pattern, i)
			if !has_byte {
				return none
			}
			bytes << byte
			i = next
			continue
		}
		if pattern[i] in [`.`, `+`, `*`, `?`, `(`, `)`, `|`, `[`, `]`, `{`, `}`, `^`, `$`] {
			return none
		}
		bytes << pattern[i]
		i++
	}
	return bytes
}

fn find_byte_literal_at(haystack []u8, literal []u8, at usize) !matcher.FallibleMatch {
	if literal.len == 0 || at > haystack.len || literal.len > haystack.len {
		return matcher.FallibleMatch.absent()
	}
	i := find_byte_literal_index(haystack, literal, at) or {
		return matcher.FallibleMatch.absent()
	}
	return matcher.FallibleMatch.some(matcher.Match.new(i, i + literal.len))
}

fn find_unicode_case_literal_at(haystack []u8, literal string, at usize) !matcher.FallibleMatch {
	if literal.len == 0 || at > haystack.len {
		return matcher.FallibleMatch.absent()
	}
	text := haystack.bytestr()
	lower_text := text.to_lower()
	lower_literal := literal.to_lower()
	index := lower_text.index_after(lower_literal, int(at)) or {
		return matcher.FallibleMatch.absent()
	}
	return matcher.FallibleMatch.some(matcher.Match.new(usize(index), usize(index + lower_literal.len)))
}

fn find_byte_literal_index(haystack []u8, literal []u8, at usize) ?usize {
	if literal.len == 0 || at > usize(haystack.len)
		|| usize(literal.len) > usize(haystack.len) - at {
		return none
	}
	if literal.len == 1 {
		mut i := at
		for i < usize(haystack.len) {
			if haystack[i] == literal[0] {
				return i
			}
			i++
		}
		return none
	}
	if literal.len >= 8 {
		return find_byte_literal_memmem(haystack, literal, at)
	}
	if literal.len >= 5 {
		return find_byte_literal_bmh(haystack, literal, at)
	}
	$if !windows {
		return find_byte_literal_memchr(haystack, literal, at)
	} $else {
		mut i := int(at)
		for i + literal.len <= haystack.len {
			mut matched := true
			for j in 0 .. literal.len {
				if haystack[i + j] != literal[j] {
					matched = false
					break
				}
			}
			if matched {
				return usize(i)
			}
			i++
		}
		return none
	}
}

fn find_byte_literal_memmem(haystack []u8, literal []u8, at usize) ?usize {
	$if windows {
		return find_byte_literal_bmh(haystack, literal, at)
	} $else {
		unsafe {
			base := voidptr(&haystack[at])
			found := C.memmem(base, usize(haystack.len) - at, voidptr(&literal[0]),
				usize(literal.len))
			if isnil(found) {
				return none
			}
			return at + (usize(found) - usize(base))
		}
	}
}

fn find_byte_literal_memchr(haystack []u8, literal []u8, at usize) ?usize {
	n := usize(haystack.len)
	m := usize(literal.len)
	if m == 0 {
		return at
	}
	if at > n || m > n - at {
		return none
	}
	$if windows {
		return find_byte_literal_bmh(haystack, literal, at)
	} $else {
		limit := n - m + 1
		mut pos := at
		first := int(literal[0])
		base := unsafe { usize(haystack.data) }
		for pos < limit {
			found := unsafe { C.memchr(&haystack[pos], first, limit - pos) }
			if found == C.NULL {
				return none
			}
			idx := unsafe { usize(found) - base }
			if unsafe { C.memcmp(found, literal.data, m) } == 0 {
				return idx
			}
			pos = idx + 1
		}
		return none
	}
}

fn find_byte_literal_bmh(haystack []u8, literal []u8, at usize) ?usize {
	n := usize(haystack.len)
	m := usize(literal.len)
	mut skip := []usize{len: 256, init: m}
	for i := 0; i + 1 < literal.len; i++ {
		skip[int(literal[i])] = m - 1 - usize(i)
	}
	last := literal[literal.len - 1]
	mut i := at + m - 1
	for i < n {
		got := haystack[i]
		if got == last {
			start := i + 1 - m
			mut j := usize(0)
			for j + 1 < m && haystack[start + j] == literal[j] {
				j++
			}
			if j + 1 == m {
				return start
			}
		}
		i += skip[int(got)]
	}
	return none
}

fn simple_ascii_from_patterns(patterns []string, config Config) ?SimpleAsciiPattern {
	if patterns.len != 1 || config.fixed_strings || config.case_insensitive || config.case_smart
		|| config.ignore_whitespace {
		return none
	}
	pattern := patterns[0]
	mut i := 0
	for i < pattern.len && pattern[i] != `[` {
		if pattern[i] >= 0x80 || pattern[i] == `\\` || is_regex_meta_character(rune(pattern[i])) {
			return none
		}
		i++
	}
	if i == 0 || i >= pattern.len || pattern[i] != `[` {
		return none
	}
	prefix := pattern[..i]
	class, ok, next_i := parse_class_set(pattern, i + 1)
	if !ok || next_i != pattern.len {
		return none
	}
	if line_term := config.line_terminator {
		if class[int(line_term.as_byte())] {
			return none
		}
	}
	return SimpleAsciiPattern{
		prefix:    prefix.bytes()
		class:     class
		match_len: usize(prefix.len + 1)
	}
}

fn find_simple_ascii_at(haystack []u8, simple SimpleAsciiPattern, at usize) !matcher.FallibleMatch {
	if simple.prefix.len == 0 || at > haystack.len || simple.match_len > usize(haystack.len) {
		return matcher.FallibleMatch.absent()
	}
	mut start := at
	for {
		i := find_byte_literal_index(haystack, simple.prefix, start) or {
			return matcher.FallibleMatch.absent()
		}
		class_index := i + simple.prefix.len
		if class_index < usize(haystack.len) && simple.class[int(haystack[class_index])] {
			return matcher.FallibleMatch.some(matcher.Match.new(i, i + simple.match_len))
		}
		start = i + 1
		if start > usize(haystack.len) {
			return matcher.FallibleMatch.absent()
		}
	}
	return matcher.FallibleMatch.absent()
}

fn can_use_ascii_byte_literal(pattern string, config Config) bool {
	if pattern.len == 0 || config.case_insensitive || config.case_smart || config.ignore_whitespace {
		return false
	}
	if line_term := config.line_terminator {
		if has_line_terminator(line_term, pattern) {
			return false
		}
	}
	for byte in pattern.bytes() {
		if byte >= 0x80 {
			return false
		}
	}
	return true
}

fn pattern_has_regex_meta(pattern string) bool {
	for ch in pattern {
		if is_regex_meta_character(ch) {
			return true
		}
	}
	return false
}
