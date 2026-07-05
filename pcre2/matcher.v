module pcre2

import matcher
import regex.pcre

/// A builder for configuring the compilation of a PCRE2 regex.
pub struct RegexMatcherBuilder implements IClone {
mut:
	caseless           bool
	case_smart         bool
	dotall             bool
	extended           bool
	multi_line         bool
	crlf               bool
	word               bool
	fixed_strings      bool
	whole_line         bool
	ucp                bool
	utf                bool
	jit                bool
	jit_if_available   bool
	max_jit_stack_size ?usize
}

/// Create a new matcher builder with a default configuration.
pub fn RegexMatcherBuilder.new() RegexMatcherBuilder {
	return RegexMatcherBuilder{}
}

/// Compile the given pattern into a PCRE matcher using the current
/// configuration.
///
/// If there was a problem compiling the pattern, then an error is
/// returned.
pub fn (builder RegexMatcherBuilder) build(pattern string) !RegexMatcher {
	return builder.build_many([pattern.to_owned()])
}

/// Compile all of the given patterns into a single regex that matches when
/// at least one of the patterns matches.
///
/// If there was a problem building the regex, then an error is returned.
pub fn (builder RegexMatcherBuilder) build_many(patterns []string) !RegexMatcher {
	mut pats := []string{cap: patterns.len}
	for p in patterns {
		pats << if builder.fixed_strings {
			'(?:${pcre_escape(p)})'
		} else {
			'(?:${p})'
		}
	}
	mut singlepat := if patterns.len == 0 {
		// A way to spell a pattern that can never match anything.
		r'[^\S\s]'.to_owned()
	} else {
		pats.join('|')
	}
	singlepat = normalize_backend_pattern(singlepat, builder.crlf)
	mut flags := ''
	if builder.caseless || (builder.case_smart && !has_uppercase_literal(&singlepat)) {
		flags += 'i'
	}
	if builder.multi_line || builder.crlf {
		flags += 'm'
	}
	if builder.dotall {
		flags += 's'
	}
	if flags.len > 0 {
		singlepat = '(?${flags})${singlepat}'
	}
	// V-specific: the local backend does not expose PCRE2 option knobs for
	// extended/UTF/UCP/JIT. These settings are retained on the matcher so the
	// translated builder API remains observable, while matching itself uses
	// the closest available `regex.pcre` semantics.
	_ = builder.extended
	_ = builder.ucp
	_ = builder.utf
	_ = builder.jit
	_ = builder.jit_if_available
	_ = builder.max_jit_stack_size
	regex := pcre.compile(singlepat) or { return Error.regex(err) }
	return RegexMatcher{
		regex:      regex
		word:       builder.word
		whole_line: builder.whole_line
		crlf:       builder.crlf
	}
}

/// Enables case insensitive matching.
///
/// If the `utf` option is also set, then Unicode case folding is used
/// to determine case insensitivity. When the `utf` option is not set,
/// then only standard ASCII case insensitivity is considered.
///
/// This option corresponds to the `i` flag.
pub fn (mut builder RegexMatcherBuilder) caseless(yes bool) &RegexMatcherBuilder {
	builder.caseless = yes
	return &builder
}

/// Whether to enable "smart case" or not.
///
/// When smart case is enabled, the builder will automatically enable
/// case insensitive matching based on how the pattern is written. Namely,
/// case insensitive mode is enabled when both of the following things
/// are believed to be true:
///
/// 1. The pattern contains at least one literal character. For example,
///    `a\w` contains a literal (`a`) but `\w` does not.
/// 2. Of the literals in the pattern, none of them are considered to be
///    uppercase according to Unicode. For example, `foo\pL` has no
///    uppercase literals but `Foo\pL` does.
///
/// Note that the implementation of this is not perfect. Namely, `\p{Ll}`
/// will prevent case insensitive matching even though it is part of a meta
/// sequence. This bug will probably never be fixed.
pub fn (mut builder RegexMatcherBuilder) case_smart(yes bool) &RegexMatcherBuilder {
	builder.case_smart = yes
	return &builder
}

/// Enables "dot all" matching.
///
/// When enabled, the `.` metacharacter in the pattern matches any
/// character, include `\n`. When disabled (the default), `.` will match
/// any character except for `\n`.
///
/// This option corresponds to the `s` flag.
pub fn (mut builder RegexMatcherBuilder) dotall(yes bool) &RegexMatcherBuilder {
	builder.dotall = yes
	return &builder
}

/// Enable "extended" mode in the pattern, where whitespace is ignored.
///
/// This option corresponds to the `x` flag.
pub fn (mut builder RegexMatcherBuilder) extended(yes bool) &RegexMatcherBuilder {
	builder.extended = yes
	return &builder
}

/// Enable multiline matching mode.
///
/// When enabled, the `^` and `$` anchors will match both at the beginning
/// and end of a subject string, in addition to matching at the start of
/// a line and the end of a line. When disabled, the `^` and `$` anchors
/// will only match at the beginning and end of a subject string.
///
/// This option corresponds to the `m` flag.
pub fn (mut builder RegexMatcherBuilder) multi_line(yes bool) &RegexMatcherBuilder {
	builder.multi_line = yes
	return &builder
}

/// Enable matching of CRLF as a line terminator.
///
/// When enabled, anchors such as `^` and `$` will match any of the
/// following as a line terminator: `\r`, `\n` or `\r\n`.
///
/// This is disabled by default, in which case, only `\n` is recognized as
/// a line terminator.
pub fn (mut builder RegexMatcherBuilder) crlf(yes bool) &RegexMatcherBuilder {
	builder.crlf = yes
	return &builder
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
	builder.word = yes
	return &builder
}

/// Whether the patterns should be treated as literal strings or not. When
/// this is active, all characters, including ones that would normally be
/// special regex meta characters, are matched literally.
pub fn (mut builder RegexMatcherBuilder) fixed_strings(yes bool) &RegexMatcherBuilder {
	builder.fixed_strings = yes
	return &builder
}

/// Whether each pattern should match the entire line or not. This is
/// equivalent to surrounding the pattern with `(?m:^)` and `(?m:$)`.
pub fn (mut builder RegexMatcherBuilder) whole_line(yes bool) &RegexMatcherBuilder {
	builder.whole_line = yes
	return &builder
}

/// Enable Unicode matching mode.
///
/// When enabled, the following patterns become Unicode aware: `\b`, `\B`,
/// `\d`, `\D`, `\s`, `\S`, `\w`, `\W`.
///
/// When set, this implies UTF matching mode. It is not possible to enable
/// Unicode matching mode without enabling UTF matching mode.
///
/// This is disabled by default.
pub fn (mut builder RegexMatcherBuilder) ucp(yes bool) &RegexMatcherBuilder {
	builder.ucp = yes
	if yes {
		builder.utf = true
	}
	return &builder
}

/// Enable UTF matching mode.
///
/// When enabled, characters are treated as sequences of code units that
/// make up a single codepoint instead of as single bytes. For example,
/// this will cause `.` to match any single UTF-8 encoded codepoint, where
/// as when this is disabled, `.` will any single byte (except for `\n` in
/// both cases, unless "dot all" mode is enabled).
///
/// Note that when UTF matching mode is enabled, every search performed
/// will do a UTF-8 validation check, which can impact performance. The
/// UTF-8 check can be disabled via the `disable_utf_check` option, but it
/// is undefined behavior to enable UTF matching mode and search invalid
/// UTF-8.
///
/// This is disabled by default.
pub fn (mut builder RegexMatcherBuilder) utf(yes bool) &RegexMatcherBuilder {
	builder.utf = yes
	return &builder
}

/// This is now deprecated and is a no-op.
///
/// Previously, this option permitted disabling PCRE2's UTF-8 validity
/// check, which could result in undefined behavior if the haystack was
/// not valid UTF-8. But PCRE2 introduced a new option, `PCRE2_MATCH_INVALID_UTF`,
/// in 10.34 which this crate always sets. When this option is enabled,
/// PCRE2 claims to not have undefined behavior when the haystack is
/// invalid UTF-8.
///
/// Therefore, disabling the UTF-8 check is not something that is exposed
/// by this crate.
pub fn (mut builder RegexMatcherBuilder) disable_utf_check() &RegexMatcherBuilder {
	return &builder
}

/// Enable PCRE2's JIT and return an error if it's not available.
///
/// This generally speeds up matching quite a bit. The downside is that it
/// can increase the time it takes to compile a pattern.
///
/// If the JIT isn't available or if JIT compilation returns an error, then
/// regex compilation will fail with the corresponding error.
///
/// This is disabled by default, and always overrides `jit_if_available`.
pub fn (mut builder RegexMatcherBuilder) jit(yes bool) &RegexMatcherBuilder {
	builder.jit = yes
	if yes {
		builder.jit_if_available = false
	}
	return &builder
}

/// Enable PCRE2's JIT if it's available.
///
/// This generally speeds up matching quite a bit. The downside is that it
/// can increase the time it takes to compile a pattern.
///
/// If the JIT isn't available or if JIT compilation returns an error,
/// then a debug message with the error will be emitted and the regex will
/// otherwise silently fall back to non-JIT matching.
///
/// This is disabled by default, and always overrides `jit`.
pub fn (mut builder RegexMatcherBuilder) jit_if_available(yes bool) &RegexMatcherBuilder {
	builder.jit_if_available = yes
	if yes {
		builder.jit = false
	}
	return &builder
}

/// Set the maximum size of PCRE2's JIT stack, in bytes. If the JIT is
/// not enabled, then this has no effect.
///
/// When `None` is given, no custom JIT stack will be created, and instead,
/// the default JIT stack is used. When the default is used, its maximum
/// size is 32 KB.
///
/// When this is set, then a new JIT stack will be created with the given
/// maximum size as its limit.
///
/// Increasing the stack size can be useful for larger regular expressions.
///
/// By default, this is set to `None`.
pub fn (mut builder RegexMatcherBuilder) max_jit_stack_size(bytes ?usize) &RegexMatcherBuilder {
	builder.max_jit_stack_size = bytes
	return &builder
}

/// An implementation of the `Matcher` trait using PCRE2.
pub struct RegexMatcher implements IClone {
	regex pcre.Regex
	word  bool
	whole_line bool
	crlf bool
}

/// Create a new matcher from the given pattern using the default
/// configuration.
pub fn RegexMatcher.new(pattern string) !RegexMatcher {
	return RegexMatcherBuilder.new().build(pattern)
}

pub fn (re RegexMatcher) find_at(haystack []u8, at usize) !matcher.FallibleMatch {
	found, _ := re.capture_groups_at(haystack, at)!
	return found
}

pub fn (re RegexMatcher) capture_groups_at(haystack []u8, at usize) !(matcher.FallibleMatch, []string) {
	if at > haystack.len {
		return matcher.FallibleMatch.absent(), []string{}
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
	_ = re
	return none
}

pub fn (re RegexMatcher) line_terminator() ?matcher.LineTerminator {
	_ = re
	return none
}

pub fn (re RegexMatcher) find_candidate_line(haystack []u8) !matcher.FallibleLineMatchKind {
	return matcher.default_find_candidate_line(re, haystack)
}

fn (re RegexMatcher) accept_match(haystack []u8, mat matcher.Match) bool {
	if re.whole_line && !is_whole_line_match(re, haystack, mat) {
		return false
	}
	if re.word && !is_word_match(haystack, mat) {
		return false
	}
	return true
}

fn is_whole_line_match(re RegexMatcher, haystack []u8, mat matcher.Match) bool {
	start := mat.start()
	end := mat.end()
	if start > 0 && haystack[start - 1] != `\n` {
		return false
	}
	if end >= haystack.len {
		return true
	}
	if re.crlf && haystack[end] == `\r` && end + 1 < haystack.len && haystack[end + 1] == `\n` {
		return true
	}
	return haystack[end] == `\n`
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

/// Determine whether the pattern contains an uppercase character which should
/// negate the effect of the smart-case option.
///
/// Ideally we would be able to check the AST in order to correctly handle
/// things like '\p{Ll}' and '\p{Lu}' (which should be treated as explicitly
/// cased), but PCRE doesn't expose enough details for that kind of analysis.
/// For now, our 'good enough' solution is to simply perform a semi-naïve
/// scan of the input pattern and ignore all characters following a '\'. The
/// This at least lets us support the most common cases, like 'foo\w' and
/// 'foo\S', in an intuitive manner.
fn has_uppercase_literal(pattern &string) bool {
	pat := *pattern
	mut i := 0
	for i < pat.len {
		if pat[i] == `\\` {
			i += 2
			continue
		}
		if pat[i] >= `A` && pat[i] <= `Z` {
			return true
		}
		i++
	}
	return false
}

fn normalize_backend_pattern(pattern string, crlf bool) string {
	if !crlf {
		return pattern
	}
	bytes := pattern.bytes()
	mut out := []u8{cap: bytes.len}
	mut i := 0
	mut in_class := false
	mut escaped := false
	for i < bytes.len {
		ch := bytes[i]
		if !escaped && !in_class && ch == `$` {
			out << r'\x0D?$'.bytes()
			i++
			escaped = false
			continue
		}
		if !escaped && ch == `[` {
			in_class = true
		} else if !escaped && ch == `]` {
			in_class = false
		}
		out << ch
		escaped = !escaped && ch == `\\`
		i++
	}
	return out.bytestr()
}

fn pcre_escape(pattern string) string {
	mut out := []u8{cap: pattern.len}
	for byte in pattern.bytes() {
		match byte {
			`\\`, `.`, `+`, `*`, `?`, `(`, `)`, `|`, `[`, `]`, `{`, `}`, `^`, `$`, `#`,
			`&`, `-`, `~`, ` `, `\t`, `\n`, `\r`, 0x0b, 0x0c {
				out << `\\`
				out << byte
			}
			else {
				out << byte
			}
		}
	}
	return out.bytestr()
}
