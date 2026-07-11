module pcre2

import matcher
import sync.stdatomic

$if pcre2 ? {
	$if $pkgconfig('libpcre2-8') {
		#pkgconfig --cflags --libs libpcre2-8
	} $else $if macos {
		#flag -I/opt/homebrew/include
		#flag -L/opt/homebrew/lib
		#flag -lpcre2-8
	} $else {
		#flag -lpcre2-8
	}
	#flag -DRIPGREP_V_PCRE2_ENABLED=1
	#flag -DRIPGREP_V_C_EMBEDDED=1
	#include <stdio.h>
	#include <stdlib.h>
	#include "@VMODROOT/pcre2/pcre2_shim.h"
	fn C.rg_pcre2_enabled() int
	fn C.rg_pcre2_live_regex_count() usize
	fn C.rg_pcre2_opt_caseless() u32
	fn C.rg_pcre2_opt_dotall() u32
	fn C.rg_pcre2_opt_extended() u32
	fn C.rg_pcre2_opt_multiline() u32
	fn C.rg_pcre2_opt_ucp() u32
	fn C.rg_pcre2_opt_utf() u32
	fn C.rg_pcre2_opt_match_invalid_utf() u32
	fn C.rg_pcre2_error_nomatch() int
	fn C.rg_pcre2_unset() usize
	fn C.rg_pcre2_jit_available() int
	fn C.rg_pcre2_error_message(code int, buf &char, len usize) &char
	fn C.rg_pcre2_compile(pattern &u8, len usize, options u32, crlf int, errorcode &int, erroroffset &usize) voidptr
	fn C.rg_pcre2_jit_compile(code voidptr) int
	fn C.rg_pcre2_code_free(code voidptr)
	fn C.rg_pcre2_regex_new(code voidptr, use_match_context int, max_jit_stack_size usize) voidptr
	fn C.rg_pcre2_regex_clone(regex voidptr) voidptr
	fn C.rg_pcre2_regex_free(regex voidptr)
	fn C.rg_pcre2_regex_code(regex voidptr) voidptr
	fn C.rg_pcre2_regex_match_context(regex voidptr) voidptr
	fn C.rg_pcre2_match_data_create(code voidptr) voidptr
	fn C.rg_pcre2_match_data_free(match_data voidptr)
	fn C.rg_pcre2_match(code voidptr, subject &u8, len usize, start usize, options u32, match_data voidptr, match_context voidptr) int
	fn C.rg_pcre2_ovector(match_data voidptr) &usize
	fn C.rg_pcre2_capture_count(code voidptr) u32
	fn C.rg_pcre2_name_count(code voidptr) u32
	fn C.rg_pcre2_name_entry_size(code voidptr) u32
	fn C.rg_pcre2_name_table(code voidptr) &u8
	fn C.rg_pcre2_name_entry_group(table &u8, entry_size u32, index u32) u32
	fn C.rg_pcre2_name_entry_name(table &u8, entry_size u32, index u32) &u8
}

// Return the number of live PCRE2 regex owners allocated by the shim.
pub fn live_regex_count() usize {
	return C.rg_pcre2_live_regex_count()
}

fn pcre2_enabled() bool {
	$if pcre2 ? {
		return C.rg_pcre2_enabled() != 0
	} $else {
		return false
	}
}

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
	$if pcre2 ? {
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
		if builder.whole_line {
			singlepat = r'(?m:^)(?:' + singlepat + r')(?m:$)'
		} else if builder.word {
			// We make this option exclusive with whole_line because when
			// whole_line is enabled, all matches necessary fall on word
			// boundaries. So this extra goop is strictly redundant.
			singlepat = r'(?<!\w)(?:' + singlepat + r')(?!\w)'
		}
		mut options := u32(0)
		if builder.caseless || (builder.case_smart && !has_uppercase_literal(&singlepat)) {
			options |= C.rg_pcre2_opt_caseless()
		}
		if builder.multi_line || builder.crlf {
			options |= C.rg_pcre2_opt_multiline()
		}
		if builder.dotall {
			options |= C.rg_pcre2_opt_dotall()
		}
		if builder.extended {
			options |= C.rg_pcre2_opt_extended()
		}
		if builder.utf {
			// PCRE2 introduced `PCRE2_MATCH_INVALID_UTF` in 10.34, which is
			// always set when UTF matching mode is enabled so that searching
			// a haystack with invalid UTF-8 is not undefined behavior.
			options |= C.rg_pcre2_opt_utf()
			options |= C.rg_pcre2_opt_match_invalid_utf()
		}
		if builder.ucp {
			options |= C.rg_pcre2_opt_ucp()
		}
		mut errorcode := 0
		mut erroroffset := usize(0)
		code := C.rg_pcre2_compile(&u8(singlepat.str), usize(singlepat.len), options,
			if builder.crlf { 1 } else { 0 }, &errorcode, &erroroffset)
		if isnil(code) {
			message := pcre2_error_message(errorcode)
			return Error.regex_message('${message} at offset ${erroroffset}')
		}
		mut jit_enabled := false
		if builder.jit || builder.jit_if_available {
			if C.rg_pcre2_jit_available() == 0 {
				if builder.jit {
					C.rg_pcre2_code_free(code)
					return Error.regex_message('PCRE2 JIT is not available')
				}
			} else {
				jit_rc := C.rg_pcre2_jit_compile(code)
				if jit_rc != 0 {
					if builder.jit {
						C.rg_pcre2_code_free(code)
						return Error.regex_message(pcre2_error_message(jit_rc))
					}
				} else {
					jit_enabled = true
				}
			}
		}
		capture_count_value := usize(C.rg_pcre2_capture_count(code)) + 1
		capture_names := &CaptureNames{
			values: pcre2_capture_names(code)
		}
		mut use_match_context := false
		mut max_stack := usize(0)
		if stack_size := builder.max_jit_stack_size {
			if jit_enabled {
				use_match_context = true
				max_stack = stack_size
			}
		}
		inner := C.rg_pcre2_regex_new(code, if use_match_context { 1 } else { 0 }, max_stack)
		if isnil(inner) {
			unsafe {
				capture_names.values.free()
				free(capture_names)
			}
			return Error.regex_message('failed to allocate PCRE2 regex')
		}
		return RegexMatcher{
			inner:               inner
			refs:                stdatomic.new_atomic(1)
			capture_count_value: capture_count_value
			capture_names:       capture_names
		}
	}
	return Error.regex_message('PCRE2 is not available in this build of ripgrep')
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
pub struct RegexMatcher implements IClone, Drop {
	// V-specific: PCRE2 resources are owned by the shim object and shared by
	// by-value matcher clones through this reference count.
	inner               voidptr
	refs                &stdatomic.AtomicVal[int]
	capture_count_value usize
	capture_names       &CaptureNames = unsafe { nil }
}

@[heap]
struct CaptureNames {
mut:
	values map[string]usize
}

/// Create a new matcher from the given pattern using the default
/// configuration.
pub fn RegexMatcher.new(pattern string) !RegexMatcher {
	return RegexMatcherBuilder.new().build(pattern)
}

pub fn (re &RegexMatcher) clone() RegexMatcher {
	mut inner := re.inner
	mut refs := re.refs
	mut capture_names := &CaptureNames{
		values: map[string]usize{}
	}
	$if pcre2 ? {
		if !isnil(re.inner) {
			inner = C.rg_pcre2_regex_clone(re.inner)
			if isnil(inner) {
				panic('failed to clone PCRE2 matcher state')
			}
			refs = stdatomic.new_atomic(1)
		}
	}
	if !isnil(re.capture_names) {
		unsafe {
			capture_names.values.free()
			free(capture_names)
		}
		capture_names = &CaptureNames{
			values: re.capture_names.values.clone()
		}
	}
	return RegexMatcher{
		inner:               inner
		refs:                refs
		capture_count_value: re.capture_count_value
		capture_names:       capture_names
	}
}

pub fn (mut re RegexMatcher) drop() {
	$if pcre2 ? {
		if !isnil(re.inner) && !isnil(re.refs) {
			if re.refs.sub(1) == 1 {
				C.rg_pcre2_regex_free(re.inner)
				unsafe {
					free(re.refs)
				}
			}
			re.inner = voidptr(0)
			re.refs = unsafe { nil }
		}
	}
	if !isnil(re.capture_names) {
		unsafe {
			mut names := re.capture_names
			names.values.free()
			free(names)
		}
		re.capture_names = unsafe { nil }
	}
}

@[unsafe]
pub fn (mut re RegexMatcher) free() {
	re.drop()
}

fn (re &RegexMatcher) code() voidptr {
	$if pcre2 ? {
		return C.rg_pcre2_regex_code(re.inner)
	}
	_ = re
	return voidptr(0)
}

fn (re &RegexMatcher) match_context() voidptr {
	$if pcre2 ? {
		return C.rg_pcre2_regex_match_context(re.inner)
	}
	_ = re
	return voidptr(0)
}

pub fn (re &RegexMatcher) find_at(haystack []u8, at usize) !matcher.FallibleMatch {
	found, _ := re.capture_groups_at(haystack, at)!
	return found
}

pub fn (re &RegexMatcher) capture_groups_at(haystack []u8, at usize) !(matcher.FallibleMatch, []string) {
	$if pcre2 ? {
		if at > haystack.len {
			return matcher.FallibleMatch.absent(), []string{}
		}
		code := re.code()
		if isnil(code) {
			return Error.regex_message('PCRE2 regex is not initialized')
		}
		match_data := C.rg_pcre2_match_data_create(code)
		if isnil(match_data) {
			return Error.regex_message('failed to allocate PCRE2 match data')
		}
		mut empty_subject := [u8(0)]
		subject := if haystack.len == 0 { &empty_subject[0] } else { &haystack[0] }
		rc := C.rg_pcre2_match(code, subject, usize(haystack.len), at, u32(0), match_data,
			re.match_context())
		if rc == C.rg_pcre2_error_nomatch() {
			C.rg_pcre2_match_data_free(match_data)
			return matcher.FallibleMatch.absent(), []string{}
		}
		if rc < 0 {
			C.rg_pcre2_match_data_free(match_data)
			return Error.regex_message(pcre2_error_message(rc))
		}
		ovector := C.rg_pcre2_ovector(match_data)
		match_start := unsafe { ovector[0] }
		match_end := unsafe { ovector[1] }
		mat := matcher.Match.new(match_start, match_end)
		groups := re.capture_groups_from_ovector(haystack, ovector)
		C.rg_pcre2_match_data_free(match_data)
		return matcher.FallibleMatch.some(mat), groups
	}
	return Error.regex_message('PCRE2 is not available in this build of ripgrep')
}

pub fn (re &RegexMatcher) new_captures() !matcher.NoCaptures {
	_ = re
	return matcher.NoCaptures.new()
}

pub fn (re &RegexMatcher) capture_count() usize {
	return re.capture_count_value
}

pub fn (re &RegexMatcher) capture_index(name string) ?usize {
	if isnil(re.capture_names) {
		return none
	}
	if index := re.capture_names.values[name] {
		return index
	}
	return none
}

fn (re &RegexMatcher) capture_groups_from_ovector(haystack []u8, ovector &usize) []string {
	$if pcre2 ? {
		mut groups := []string{cap: int(re.capture_count_value)}
		unset := C.rg_pcre2_unset()
		for i := usize(1); i < re.capture_count_value; i++ {
			start := unsafe { ovector[i * 2] }
			end := unsafe { ovector[i * 2 + 1] }
			if start == unset || end == unset || start > haystack.len || end > haystack.len
				|| start > end {
				groups << ''
				continue
			}
			groups << haystack[start..end].bytestr()
		}
		return groups
	}
	_ = re
	_ = haystack
	_ = ovector
	return []string{}
}

fn pcre2_capture_names(code voidptr) map[string]usize {
	$if pcre2 ? {
		mut names := map[string]usize{}
		name_count := C.rg_pcre2_name_count(code)
		if name_count == 0 {
			return names
		}
		entry_size := C.rg_pcre2_name_entry_size(code)
		table := C.rg_pcre2_name_table(code)
		if isnil(table) {
			return names
		}
		for i := u32(0); i < name_count; i++ {
			group := usize(C.rg_pcre2_name_entry_group(table, entry_size, i))
			name_ptr := C.rg_pcre2_name_entry_name(table, entry_size, i)
			if !isnil(name_ptr) {
				name := unsafe { tos_clone(name_ptr) }
				names[name] = group
			}
		}
		return names
	}
	_ = code
	return map[string]usize{}
}

fn pcre2_error_message(code int) string {
	$if pcre2 ? {
		mut buf := []u8{len: 256}
		C.rg_pcre2_error_message(code, &char(buf.data), usize(buf.len))
		mut end := 0
		for end < buf.len && buf[end] != 0 {
			end++
		}
		return buf[..end].bytestr()
	}
	return 'PCRE2 error ${code}'
}

pub fn (re &RegexMatcher) captures_at(haystack []u8, at usize, mut caps matcher.NoCaptures) !bool {
	_ = caps
	return re.find_at(haystack, at)!.is_some()
}

pub fn (re &^a RegexMatcher) non_matching_bytes[^a]() ?&^a matcher.ByteSet {
	_ = re
	return none
}

pub fn (re &RegexMatcher) line_terminator() ?matcher.LineTerminator {
	_ = re
	return none
}

pub fn (re &RegexMatcher) find_candidate_line(haystack []u8) !matcher.FallibleLineMatchKind {
	return matcher.default_find_candidate_line(re, haystack)
}

/// A borrowed matcher adapter for APIs that currently use V interface values.
///
/// The interface contains this pointer-only adapter instead of copying the
/// owning `RegexMatcher` value.
pub struct RegexMatcherRef[^a] {
	re &^a RegexMatcher
}

pub fn RegexMatcherRef.new[^a](re &^a RegexMatcher) RegexMatcherRef[^a] {
	return RegexMatcherRef[^a]{
		re: re
	}
}

pub fn (re RegexMatcherRef[^a]) find_at[^a](haystack []u8, at usize) !matcher.FallibleMatch {
	return re.re.find_at(haystack, at)
}

pub fn (re RegexMatcherRef[^a]) new_captures[^a]() !matcher.NoCaptures {
	return re.re.new_captures()
}

pub fn (re RegexMatcherRef[^a]) capture_count[^a]() usize {
	return re.re.capture_count()
}

pub fn (re RegexMatcherRef[^a]) capture_index[^a](name string) ?usize {
	return re.re.capture_index(name)
}

pub fn (re RegexMatcherRef[^a]) captures_at[^a](haystack []u8, at usize, mut caps matcher.NoCaptures) !bool {
	return re.re.captures_at(haystack, at, mut caps)
}

pub fn (re RegexMatcherRef[^a]) non_matching_bytes[^b, ^a]() ?&^b matcher.ByteSet {
	_ = re
	return none
}

pub fn (re RegexMatcherRef[^a]) line_terminator[^a]() ?matcher.LineTerminator {
	return re.re.line_terminator()
}

pub fn (re RegexMatcherRef[^a]) find_candidate_line[^a](haystack []u8) !matcher.FallibleLineMatchKind {
	return re.re.find_candidate_line(haystack)
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

fn apply_extended_mode(pattern string) string {
	mut out := []u8{cap: pattern.len}
	mut escaped := false
	mut in_class := false
	mut in_comment := false
	for b in pattern.bytes() {
		if in_comment {
			if b == `\n` || b == `\r` {
				in_comment = false
			}
			continue
		}
		if escaped {
			out << b
			escaped = false
			continue
		}
		if b == `\\` {
			out << b
			escaped = true
			continue
		}
		if in_class {
			out << b
			if b == `]` {
				in_class = false
			}
			continue
		}
		if b == `[` {
			out << b
			in_class = true
			continue
		}
		if b == `#` {
			in_comment = true
			continue
		}
		if is_extended_whitespace(b) {
			continue
		}
		out << b
	}
	return out.bytestr()
}

fn is_extended_whitespace(b u8) bool {
	return b == ` ` || b == `\t` || b == `\n` || b == `\r` || b == `\f`
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
