module globset

import regex.meta

/// Describes a matching strategy for a particular pattern.
///
/// This provides a way to more quickly determine whether a pattern matches
/// a particular file path in a way that scales with a large number of
/// patterns. For example, if many patterns are of the form `*.ext`, then it's
/// possible to test whether any of those patterns matches by looking up a
/// file path's extension in a hash table.
enum MatchStrategyKind {
	/// A pattern matches if and only if the entire file path matches this
	/// literal string.
	literal
	/// A pattern matches if and only if the file path's basename matches this
	/// literal string.
	basename_literal
	/// A pattern matches if and only if the file path's extension matches this
	/// literal string.
	extension
	/// A pattern matches if and only if this prefix literal is a prefix of the
	/// candidate file path.
	prefix
	/// A pattern matches if and only if this prefix literal is a prefix of the
	/// candidate file path.
	///
	/// An exception: if `component` is true, then `suffix` must appear at the
	/// beginning of a file path or immediately following a `/`.
	suffix
	/// A pattern matches only if the given extension matches the file path's
	/// extension. Note that this is a necessary but NOT sufficient criterion.
	/// Namely, if the extension matches, then a full regex search is still
	/// required.
	required_extension
	/// A regex needs to be used for matching.
	regex
}

struct MatchStrategy {
	kind      MatchStrategyKind
	/// The literal value for strategies that carry one.
	value     string
	/// Whether a suffix must start at the beginning of a path component.
	component bool
}

fn match_strategy_new(pat &Glob) MatchStrategy {
	if lit := pat.basename_literal() {
		return MatchStrategy{
			kind:  .basename_literal
			value: lit
		}
	} else if lit := pat.literal() {
		return MatchStrategy{
			kind:  .literal
			value: lit
		}
	} else if ext := pat.ext() {
		return MatchStrategy{
			kind:  .extension
			value: ext
		}
	} else if prefix := pat.prefix() {
		return MatchStrategy{
			kind:  .prefix
			value: prefix
		}
	} else if suffix, component := pat.suffix() {
		return MatchStrategy{
			kind:      .suffix
			value:     suffix
			component: component
		}
	} else if ext := pat.required_ext() {
		return MatchStrategy{
			kind:  .required_extension
			value: ext
		}
	}
	return MatchStrategy{
		kind: .regex
	}
}

struct TokenRange implements IClone {
	mut:
	start rune
	end   rune
}

enum TokenKind {
	literal
	any
	zero_or_more
	recursive_prefix
	recursive_suffix
	recursive_zero_or_more
	class
	alternates
}

struct Token implements IClone {
	kind     TokenKind
	ch       rune
	negated  bool
	ranges   []TokenRange
	patterns []Tokens
}

fn token_literal(ch rune) Token {
	return Token{
		kind: .literal
		ch:   ch
	}
}

fn token_any() Token {
	return Token{
		kind: .any
	}
}

fn token_zero_or_more() Token {
	return Token{
		kind: .zero_or_more
	}
}

fn token_recursive_prefix() Token {
	return Token{
		kind: .recursive_prefix
	}
}

fn token_recursive_suffix() Token {
	return Token{
		kind: .recursive_suffix
	}
}

fn token_recursive_zero_or_more() Token {
	return Token{
		kind: .recursive_zero_or_more
	}
}

fn token_class(negated bool, ranges []TokenRange) Token {
	return Token{
		kind:    .class
		negated: negated
		ranges:  ranges
	}
}

fn token_alternates(patterns []Tokens) Token {
	return Token{
		kind:     .alternates
		patterns: patterns
	}
}

fn (tok Token) str() string {
	return match tok.kind {
		.literal { 'Literal(${tok.ch.str()})' }
		.any { 'Any' }
		.zero_or_more { 'ZeroOrMore' }
		.recursive_prefix { 'RecursivePrefix' }
		.recursive_suffix { 'RecursiveSuffix' }
		.recursive_zero_or_more { 'RecursiveZeroOrMore' }
		.class {
			mut pieces := []string{}
			for r in tok.ranges {
				pieces << '(${r.start.str()},${r.end.str()})'
			}
			'Class(${tok.negated},[${pieces.join(",")}])'
		}
		.alternates {
			mut pieces := []string{}
			for pat in tok.patterns {
				pieces << pat.str()
			}
			'Alternates([${pieces.join(",")}])'
		}
	}
}

struct Tokens implements IClone {
mut:
	tokens []Token
}

// V-specific: the current compiler-generated `IClone` lowering expands
// mutually recursive aggregate fields at compile time. `Token` and `Tokens`
// are recursive through their arrays, so spell out Rust's derived deep clone
// and let the recursion occur only for values present at runtime.
fn (tok &Token) clone() Token {
	mut patterns := []Tokens{cap: tok.patterns.len}
	for pattern in tok.patterns {
		patterns << pattern.clone()
	}
	return Token{
		kind: tok.kind
		ch: tok.ch
		negated: tok.negated
		ranges: tok.ranges.clone()
		patterns: patterns
	}
}

fn (tokens &Tokens) clone() Tokens {
	mut cloned := []Token{cap: tokens.tokens.len}
	for token in tokens.tokens {
		cloned << token.clone()
	}
	return Tokens{
		tokens: cloned
	}
}

fn Tokens.default() Tokens {
	return Tokens{
		tokens: []Token{}
	}
}

fn (mut t Tokens) push(tok Token) {
	t.tokens << tok
}

fn (mut t Tokens) pop() ?Token {
	return t.tokens.pop()
}

fn (t Tokens) len() int {
	return t.tokens.len
}

fn (t Tokens) is_empty() bool {
	return t.tokens.len == 0
}

fn (t Tokens) str() string {
	mut pieces := []string{}
	for tok in t.tokens {
		pieces << tok.str()
	}
	return '[' + pieces.join(',') + ']'
}

struct GlobOptions implements IClone {
	mut:
	/// Whether to match case insensitively.
	case_insensitive    bool
	/// Whether to require a literal separator to match a separator in a file
	/// path. e.g., when enabled, `*` won't match `/`.
	literal_separator   bool
	/// Whether or not to use `\` to escape special characters.
	/// e.g., when enabled, `\*` will match a literal `*`.
	backslash_escape    bool
	/// Whether or not an empty case in an alternate will be removed.
	/// e.g., when enabled, `{,a}` will match "" and "a".
	empty_alternates    bool
	/// Whether or not an unclosed character class is allowed. When an unclosed
	/// character class is found, the opening `[` is treated as a literal `[`.
	/// When this isn't enabled, an opening `[` without a corresponding `]` is
	/// treated as an error.
	allow_unclosed_class bool
}

fn glob_options_default() GlobOptions {
	return GlobOptions{
		case_insensitive:     false
		literal_separator:    false
		backslash_escape:     !is_separator(`\\`)
		empty_alternates:     false
		allow_unclosed_class: false
	}
}

/// Glob represents a successfully parsed shell glob pattern.
///
/// It cannot be used directly to match file paths, but it can be converted
/// to a regular expression string or a matcher.
pub struct Glob implements IClone {
	mut:
	glob_  string
	re_    string
	opts   GlobOptions
	tokens Tokens
	// V-specific: V represents `&[]Token` as a pointer to an array descriptor.
	// Keep the basename slice descriptor in the `Glob` so the translated
	// lifetime-bearing return never takes the address of a temporary slice.
	basename_tokens_view []Token
}

pub fn (g Glob) == (other Glob) bool {
	return g.glob_ == other.glob_ && g.opts == other.opts
}

/// Builds a new pattern with default options.
pub fn Glob.new(glob string) !Glob {
	mut builder := GlobBuilder.new(&glob)
	return builder.build()
}

/// Builds a new pattern with default options from its string representation.
///
/// This is the V-exposed equivalent of Rust's `FromStr` implementation.
pub fn Glob.from_str(glob string) !Glob {
	return Glob.new(glob)
}

/// Returns a matcher for this pattern.
pub fn (g &Glob) compile_matcher() GlobMatcher {
	re := new_regex(&g.re_) or { panic('regex compilation shouldn\'t fail') }
	return GlobMatcher{
		pat: g.clone()
		re:  re
	}
}

/// Returns the original glob pattern used to build this pattern.
pub fn (g &^a Glob) glob[^a]() &^a string {
	return &g.glob_
}

/// Returns the regular expression string for this glob.
///
/// Note that regular expressions for globs are intended to be matched on
/// arbitrary bytes (`&[u8]`) instead of Unicode strings (`&str`). In
/// particular, globs are frequently used on file paths, where there is no
/// general guarantee that file paths are themselves valid UTF-8. As a
/// result, callers will need to ensure that they are using a regex API
/// that can match on arbitrary bytes. For example, the
/// [`regex`](https://crates.io/regex)
/// crate's
/// [`Regex`](https://docs.rs/regex/*/regex/struct.Regex.html)
/// API is not suitable for this since it matches on `&str`, but its
/// [`bytes::Regex`](https://docs.rs/regex/*/regex/bytes/struct.Regex.html)
/// API is suitable for this.
pub fn (g &^a Glob) regex[^a]() &^a string {
	return &g.re_
}

/// Returns the pattern as a literal if and only if the pattern must match
/// an entire path exactly.
///
/// The basic format of these patterns is `{literal}`.
fn (g &Glob) literal() ?string {
	if g.opts.case_insensitive {
		return none
	}
	mut lit := ''
	for tok in g.tokens.tokens {
		if tok.kind != .literal {
			return none
		}
		lit += tok.ch.str()
	}
	if lit == '' {
		return none
	}
	return lit
}

/// Returns an extension if this pattern matches a file path if and only
/// if the file path has the extension returned.
///
/// Note that this extension returned differs from the extension that
/// std::path::Path::extension returns. Namely, this extension includes
/// the '.'. Also, paths like `.rs` are considered to have an extension
/// of `.rs`.
fn (g &Glob) ext() ?string {
	if g.opts.case_insensitive {
		return none
	}
	if g.tokens.tokens.len == 0 {
		return none
	}
	mut start := 0
	if g.tokens.tokens[0].kind == .recursive_prefix {
		start = 1
	}
	if start >= g.tokens.tokens.len || g.tokens.tokens[start].kind != .zero_or_more {
		return none
	}
	// If there was no recursive prefix, then we only permit
	// `*` if `*` can match a `/`. For example, if `*` can't
	// match `/`, then `*.c` doesn't match `foo/bar.c`.
	if start == 0 && g.opts.literal_separator {
		return none
	}
	if start + 1 >= g.tokens.tokens.len || g.tokens.tokens[start + 1].kind != .literal
		|| g.tokens.tokens[start + 1].ch != `.` {
		return none
	}
	mut lit := '.'
	for i := start + 2; i < g.tokens.tokens.len; i++ {
		tok := &g.tokens.tokens[i]
		if tok.kind != .literal || tok.ch == `.` || tok.ch == `/` {
			return none
		}
		lit += tok.ch.str()
	}
	return lit
}

/// This is like `ext`, but returns an extension even if it isn't sufficient
/// to imply a match. Namely, if an extension is returned, then it is
/// necessary but not sufficient for a match.
fn (g &Glob) required_ext() ?string {
	if g.opts.case_insensitive {
		return none
	}
	// We don't care at all about the beginning of this pattern. All we
	// need to check for is if it ends with a literal of the form `.ext`.
	mut chars := []rune{}
	for i := g.tokens.tokens.len - 1; i >= 0; i-- {
		tok := &g.tokens.tokens[i]
		if tok.kind != .literal {
			return none
		}
		if tok.ch == `/` {
			return none
		}
		chars << tok.ch
		if tok.ch == `.` {
			break
		}
	}
	if chars.len == 0 || chars[chars.len - 1] != `.` {
		return none
	}
	mut lit := ''
	for i := chars.len - 1; i >= 0; i-- {
		lit += chars[i].str()
	}
	return lit
}

/// Returns a literal prefix of this pattern if the entire pattern matches
/// if the literal prefix matches.
fn (g &Glob) prefix() ?string {
	if g.opts.case_insensitive || g.tokens.tokens.len == 0 {
		return none
	}
	mut end := g.tokens.tokens.len
	mut need_sep := false
	last := &g.tokens.tokens[g.tokens.tokens.len - 1]
	if last.kind == .zero_or_more {
		if g.opts.literal_separator {
			// If a trailing `*` can't match a `/`, then we can't
			// assume a match of the prefix corresponds to a match
			// of the overall pattern. e.g., `foo/*` with
			// `literal_separator` enabled matches `foo/bar` but not
			// `foo/bar/baz`, even though `foo/bar/baz` has a `foo/`
			// literal prefix.
			return none
		}
		end--
	} else if last.kind == .recursive_suffix {
		end--
		need_sep = true
	}
	mut lit := ''
	for i := 0; i < end; i++ {
		tok := &g.tokens.tokens[i]
		if tok.kind != .literal {
			return none
		}
		lit += tok.ch.str()
	}
	if need_sep {
		lit += '/'
	}
	if lit == '' {
		return none
	}
	return lit
}

/// Returns a literal suffix of this pattern if the entire pattern matches
/// if the literal suffix matches.
///
/// If a literal suffix is returned and it must match either the entire
/// file path or be preceded by a `/`, then also return true. This happens
/// with a pattern like `**/foo/bar`. Namely, this pattern matches
/// `foo/bar` and `baz/foo/bar`, but not `foofoo/bar`. In this case, the
/// suffix returned is `/foo/bar` (but should match the entire path
/// `foo/bar`).
///
/// When this returns true, the suffix literal is guaranteed to start with
/// a `/`.
fn (g &Glob) suffix() ?(string, bool) {
	if g.opts.case_insensitive || g.tokens.tokens.len == 0 {
		return none
	}
	mut lit := ''
	mut start := 0
	mut entire := false
	if g.tokens.tokens[0].kind == .recursive_prefix {
		// We only care if this follows a path component if the next
		// token is a literal.
		if g.tokens.tokens.len > 1 && g.tokens.tokens[1].kind == .literal {
			lit += '/'
			entire = true
		}
		start = 1
	}
	if start >= g.tokens.tokens.len {
		return none
	}
	if g.tokens.tokens[start].kind == .zero_or_more {
		// If literal_separator is enabled, then a `*` can't
		// necessarily match everything, so reporting a suffix match
		// as a match of the pattern would be a false positive.
		if g.opts.literal_separator {
			return none
		}
		start++
	}
	for i := start; i < g.tokens.tokens.len; i++ {
		tok := &g.tokens.tokens[i]
		if tok.kind != .literal {
			return none
		}
		lit += tok.ch.str()
	}
	if lit == '' || lit == '/' {
		return none
	}
	return lit, entire
}

/// If this pattern only needs to inspect the basename of a file path,
/// then the tokens corresponding to only the basename match are returned.
///
/// For example, given a pattern of `**/*.foo`, only the tokens
/// corresponding to `*.foo` are returned.
///
/// Note that this will return None if any match of the basename tokens
/// doesn't correspond to a match of the entire pattern. For example, the
/// glob `foo` only matches when a file path has a basename of `foo`, but
/// doesn't *always* match when a file path has a basename of `foo`. e.g.,
/// `foo` doesn't match `abc/foo`.
fn (g &^a Glob) basename_tokens[^a]() ?&^a []Token {
	if g.opts.case_insensitive || g.tokens.tokens.len == 0 {
		return none
	}
	if g.tokens.tokens[0].kind != .recursive_prefix {
		// With nothing to gobble up the parent portion of a path,
		// we can't assume that matching on only the basename is
		// correct.
		return none
	}
	if g.tokens.tokens.len == 1 {
		return none
	}
	for i := 1; i < g.tokens.tokens.len; i++ {
		tok := &g.tokens.tokens[i]
		match tok.kind {
			.literal {
				if tok.ch == `/` {
					return none
				}
				// OK
			}
			.any, .zero_or_more {
				if !g.opts.literal_separator {
					// In this case, `*` and `?` can match a path
					// separator, which means this could reach outside
					// the basename.
					return none
				}
			}
			.recursive_prefix, .recursive_suffix, .recursive_zero_or_more, .class, .alternates {
				// We *could* be a little smarter here, but either one
				// of these is going to prevent our literal optimizations
				// anyway, so give up.
				return none
			}
		}
	}
	return &g.basename_tokens_view
}

/// Returns the pattern as a literal if and only if the pattern exclusively
/// matches the basename of a file path *and* is a literal.
///
/// The basic format of these patterns is `**/{literal}`, where `{literal}`
/// does not contain a path separator.
fn (g &Glob) basename_literal() ?string {
	tokens := g.basename_tokens() or { return none }
	mut lit := ''
	for tok in *tokens {
		if tok.kind != .literal {
			return none
		}
		lit += tok.ch.str()
	}
	return lit
}

pub fn (g &Glob) str() string {
	return g.glob_.clone()
}

/// A matcher for a single pattern.
pub struct GlobMatcher implements IClone {
	/// The underlying pattern.
	pat Glob
	/// The pattern, as a compiled regex.
	re  meta.Regex
}

/// Tests whether the given path matches this pattern or not.
pub fn (gm &GlobMatcher) is_match(path string) bool {
	candidate := Candidate.new(&path)
	return gm.is_match_candidate(&candidate)
}

/// Tests whether the given path matches this pattern or not.
pub fn (gm &GlobMatcher) is_match_candidate[^a](path &Candidate[^a]) bool {
	return gm.re.find(path.path_) != none
}

/// Returns the `Glob` used to compile this matcher.
pub fn (gm &^a GlobMatcher) glob[^a]() &^a Glob {
	return &gm.pat
}

/// A builder for a pattern.
///
/// This builder enables configuring the match semantics of a pattern. For
/// example, one can make matching case insensitive.
///
/// The lifetime `^a` refers to the lifetime of the pattern string.
pub struct GlobBuilder[^a] implements IClone {
	/// The glob pattern to compile.
	glob &^a string
mut:
	/// Options for the pattern.
	opts GlobOptions
}

/// Create a new builder for the pattern given.
///
/// The pattern is not compiled until `build` is called.
pub fn GlobBuilder.new[^a](glob &^a string) GlobBuilder[^a] {
	return GlobBuilder[^a]{
		glob: glob
		opts: glob_options_default()
	}
}

/// Parses and builds the pattern.
pub fn (builder &GlobBuilder[^a]) build() !Glob {
	mut parser := Parser{
		glob:                   builder.glob
		alternates_stack:       []int{}
		branches:               [Tokens.default()]
		chars:                  (*builder.glob).runes()
		index:                  0
		prev:                   none
		cur:                    none
		found_unclosed_class:   false
		opts:                   &builder.opts
	}
	parser.parse()!
	if parser.branches.len == 0 {
		// OK because of how the the branches/alternate_stack are managed.
		// If we end up here, then there *must* be a bug in the parser
		// somewhere.
		panic('glob parser invariant violated')
	}
	if parser.branches.len > 1 {
		glob_err := GlobError{
			glob_: (*builder.glob).to_owned()
			kind_: ErrorKind.unclosed_alternates()
		}
		return glob_err
	}
	tokens := parser.branches.pop()
	basename_tokens_view := if tokens.tokens.len > 1 {
		tokens.tokens[1..].clone()
	} else {
		[]Token{}
	}
	return Glob{
		glob_:                (*builder.glob).to_owned()
		re_:                  tokens.to_regex_with(&builder.opts)
		opts:                 builder.opts.clone()
		tokens:               tokens
		basename_tokens_view: basename_tokens_view
	}
}

/// Toggle whether the pattern matches case insensitively or not.
///
/// This is disabled by default.
pub fn (mut builder GlobBuilder[^a]) case_insensitive[^a](yes bool) &GlobBuilder[^a] {
	builder.opts.case_insensitive = yes
	return builder
}

/// Toggle whether a literal `/` is required to match a path separator.
///
/// By default this is false: `*` and `?` will match `/`.
pub fn (mut builder GlobBuilder[^a]) literal_separator[^a](yes bool) &GlobBuilder[^a] {
	builder.opts.literal_separator = yes
	return builder
}

/// When enabled, a back slash (`\`) may be used to escape
/// special characters in a glob pattern. Additionally, this will
/// prevent `\` from being interpreted as a path separator on all
/// platforms.
///
/// This is enabled by default on platforms where `\` is not a
/// path separator and disabled by default on platforms where `\`
/// is a path separator.
pub fn (mut builder GlobBuilder[^a]) backslash_escape[^a](yes bool) &GlobBuilder[^a] {
	builder.opts.backslash_escape = yes
	return builder
}

/// Toggle whether an empty pattern in a list of alternates is accepted.
///
/// For example, if this is set then the glob `foo{,.txt}` will match both
/// `foo` and `foo.txt`.
///
/// By default this is false.
pub fn (mut builder GlobBuilder[^a]) empty_alternates[^a](yes bool) &GlobBuilder[^a] {
	builder.opts.empty_alternates = yes
	return builder
}

/// Toggle whether unclosed character classes are allowed. When allowed,
/// a `[` without a matching `]` is treated literally instead of resulting
/// in a parse error.
///
/// For example, if this is set then the glob `[abc` will be treated as the
/// literal string `[abc` instead of returning an error.
///
/// By default, this is false. Generally speaking, enabling this leads to
/// worse failure modes since the glob parser becomes more permissive. You
/// might want to enable this when compatibility (e.g., with POSIX glob
/// implementations) is more important than good error messages.
pub fn (mut builder GlobBuilder[^a]) allow_unclosed_class[^a](yes bool) &GlobBuilder[^a] {
	builder.opts.allow_unclosed_class = yes
	return builder
}

/// Convert this pattern to a string that is guaranteed to be a valid
/// regular expression and will represent the matching semantics of this
/// glob pattern and the options given.
fn (tokens &Tokens) to_regex_with(options &GlobOptions) string {
	mut re := '(?-u)'
	if options.case_insensitive {
		re += '(?i)'
	}
	re += '^'
	// Special case. If the entire glob is just `**`, then it should match
	// everything.
	if tokens.tokens.len == 1 && tokens.tokens[0].kind == .recursive_prefix {
		re += '.*'
		re += r'$'
		return re
	}
	re += tokens.tokens_to_regex(options, &tokens.tokens)
	re += r'$'
	return re
}

fn (tokens &Tokens) tokens_to_regex(options &GlobOptions, src &[]Token) string {
	mut re := ''
	for tok in *src {
		match tok.kind {
			.literal {
				re += char_to_escaped_literal(tok.ch)
			}
			.any {
				re += if options.literal_separator { '[^/]' } else { '.' }
			}
			.zero_or_more {
				re += if options.literal_separator { '[^/]*' } else { '.*' }
			}
			.recursive_prefix {
				re += '(?:/?|.*/)'
			}
			.recursive_suffix {
				re += '/.*'
			}
			.recursive_zero_or_more {
				re += '(?:/|/.*/)'
			}
			.class {
				re += '['
				if tok.negated {
					re += '^'
				}
				for rng in tok.ranges {
					if rng.start == rng.end {
						// Not strictly necessary, but nicer to look at.
						re += char_to_escaped_literal(rng.start)
					} else {
						re += char_to_escaped_literal(rng.start)
						re += '-'
						re += char_to_escaped_literal(rng.end)
					}
				}
				re += ']'
			}
			.alternates {
				mut parts := []string{}
				for pat in tok.patterns {
					alt := pat.tokens_to_regex(options, &pat.tokens)
					if alt != '' || options.empty_alternates {
						parts << alt
					}
				}
				// It is possible to have an empty set in which case the
				// resulting alternation '()' would be an error.
				if parts.len > 0 {
					re += '(?:' + parts.join('|') + ')'
				}
			}
		}
	}
	return re
}

/// Convert a Unicode scalar value to an escaped string suitable for use as
/// a literal in a non-Unicode regex.
fn char_to_escaped_literal(ch rune) string {
	bytes := ch.str().bytes()
	return bytes_to_escaped_literal(&bytes)
}

/// Converts an arbitrary sequence of bytes to a UTF-8 string. All non-ASCII
/// code units are converted to their escaped form.
fn bytes_to_escaped_literal(bytes &[]u8) string {
	mut s := ''
	for b in *bytes {
		if b <= 0x7F {
			if ascii_needs_regex_escape(b) {
				s += '\\'
			}
			s += rune(b).str()
		} else {
			s += '\\x' + b.hex()
		}
	}
	return s
}

fn ascii_needs_regex_escape(b u8) bool {
	return b in [`\\`, `.`, `+`, `*`, `?`, `(`, `)`, `|`, `[`, `]`, `{`, `}`, `^`, `$`,
		`#`, `&`, `-`, `~`]
}

struct Parser[^a] {
	/// The glob to parse.
	glob &^a string
mut:
	/// Marks the index in `stack` where the alternation started.
	alternates_stack     []int
	/// The set of active alternation branches being parsed.
	/// Tokens are added to the end of the last one.
	branches             []Tokens
	/// The characters in the glob pattern to parse.
	chars                []rune
	/// The next character index.
	index                int
	/// The previous character seen.
	prev                 ?rune
	/// The current character.
	cur                  ?rune
	/// Whether we failed to find a closing `]` for a character
	/// class. This can only be true when `GlobOptions::allow_unclosed_class`
	/// is enabled. When enabled, it is impossible to ever parse another
	/// character class with this glob. That's because classes cannot be
	/// nested *and* the only way this happens is when there is never a `]`.
	///
	/// We track this state so that we don't end up spending quadratic time
	/// trying to parse something like `[[[[[[[[[[[[[[[[[[[[[[[...`.
	found_unclosed_class bool
	/// Glob options, which may influence parsing.
	opts                 &^a GlobOptions
}

fn (p &Parser[^a]) mk_error(kind ErrorKind) GlobError {
	return GlobError{
		glob_: (*p.glob).to_owned()
		kind_: kind
	}
}

fn (mut p Parser[^a]) parse() ! {
	for {
		ch := p.bump() or { break }
		match ch {
			`?` {
				p.push_token(token_any())!
			}
			`*` {
				p.parse_star()!
			}
			`[` {
				if !p.found_unclosed_class {
					p.parse_class()!
				} else {
					p.push_token(token_literal(ch))!
				}
			}
			`{` {
				p.push_alternate()!
			}
			`}` {
				p.pop_alternate()!
			}
			`,` {
				p.parse_comma()!
			}
			`\\` {
				p.parse_backslash()!
			}
			else {
				p.push_token(token_literal(ch))!
			}
		}
	}
}

fn (mut p Parser[^a]) push_alternate() ! {
	p.alternates_stack << p.branches.len
	p.branches << Tokens.default()
}

fn (mut p Parser[^a]) pop_alternate() ! {
	if p.alternates_stack.len == 0 {
		return p.mk_error(ErrorKind.unopened_alternates())
	}
	start := p.alternates_stack[p.alternates_stack.len - 1]
	p.alternates_stack = p.alternates_stack[..p.alternates_stack.len - 1]
	assert start <= p.branches.len
	mut patterns := []Tokens{}
	for p.branches.len > start {
		patterns << p.branches.pop()
	}
	patterns.reverse_in_place()
	p.push_token(token_alternates(patterns))!
}

fn (mut p Parser[^a]) push_token(tok Token) ! {
	if p.branches.len == 0 {
		return p.mk_error(ErrorKind.unopened_alternates())
	}
	p.branches[p.branches.len - 1].push(tok)
}

fn (mut p Parser[^a]) pop_token() !Token {
	if p.branches.len == 0 {
		return p.mk_error(ErrorKind.unopened_alternates())
	}
	return p.branches[p.branches.len - 1].pop() or { panic('missing token in parser') }
}

fn (p &Parser[^a]) have_tokens() !bool {
	if p.branches.len == 0 {
		return p.mk_error(ErrorKind.unopened_alternates())
	}
	return !p.branches[p.branches.len - 1].is_empty()
}

fn (mut p Parser[^a]) parse_comma() ! {
	// If we aren't inside a group alternation, then don't
	// treat commas specially. Otherwise, we need to start
	// a new alternate branch.
	if p.alternates_stack.len == 0 {
		p.push_token(token_literal(`,`))!
		return
	}
	p.branches << Tokens.default()
}

fn (mut p Parser[^a]) parse_backslash() ! {
	if p.opts.backslash_escape {
		next := p.bump() or { return p.mk_error(ErrorKind.dangling_escape()) }
		p.push_token(token_literal(next))!
		return
	}
	$if windows {
		p.push_token(token_literal(`/`))!
	} $else {
		p.push_token(token_literal(`\\`))!
	}
}

fn (mut p Parser[^a]) parse_star() ! {
	prev := p.prev
	next_star := p.peek() or {
		p.push_token(token_zero_or_more())!
		return
	}
	if next_star != `*` {
		p.push_token(token_zero_or_more())!
		return
	}
	assert p.bump() or { `\0` } == `*`
	if !p.have_tokens()! {
		if next := p.peek() {
			if !is_separator(next) {
				p.push_token(token_zero_or_more())!
				p.push_token(token_zero_or_more())!
				return
			}
			p.push_token(token_recursive_prefix())!
			assert is_separator(p.bump() or { panic('missing separator') })
		} else {
			p.push_token(token_recursive_prefix())!
		}
		return
	}
	prev_is_separator := if previous := prev { is_separator(previous) } else { false }
	if !prev_is_separator {
		prev_is_alternate := if previous := prev { previous == `,` || previous == `{` } else { false }
		if p.branches.len <= 1 || !prev_is_alternate {
			p.push_token(token_zero_or_more())!
			p.push_token(token_zero_or_more())!
			return
		}
	}
	mut is_suffix := false
	next := p.peek()
	if next == none {
		assert p.bump() == none
		is_suffix = true
	} else if (next == `,` || next == `}`) && p.branches.len >= 2 {
		is_suffix = true
	} else if is_separator(next) {
		assert is_separator(p.bump() or { panic('missing separator') })
		is_suffix = false
	} else {
		p.push_token(token_zero_or_more())!
		p.push_token(token_zero_or_more())!
		return
	}
	last := p.pop_token()!
	if last.kind == .recursive_prefix {
		p.push_token(token_recursive_prefix())!
	} else if last.kind == .recursive_suffix {
		p.push_token(token_recursive_suffix())!
	} else if is_suffix {
		p.push_token(token_recursive_suffix())!
	} else {
		p.push_token(token_recursive_zero_or_more())!
	}
}

fn (p &Parser[^a]) add_to_last_range[^a](range TokenRange, add rune) !TokenRange {
	if add < range.start {
		glob_err := GlobError{
			glob_: (*p.glob).to_owned()
			kind_: ErrorKind.invalid_range(range.start, add)
		}
		return glob_err
	}
	return TokenRange{
		start: range.start
		end:   add
	}
}

fn (mut p Parser[^a]) parse_class() ! {
	// Save parser state for potential rollback to literal '[' parsing.
	saved_index := p.index
	saved_prev := p.prev
	saved_cur := p.cur
	mut ranges := []TokenRange{}
	mut negated := false
	peek := p.peek()
	if peek != none && (peek == `!` || peek == `^`) {
		_ := p.bump()
		negated = true
	}
	mut first := true
	mut in_range := false
	for {
		ch := p.bump() or {
			if p.opts.allow_unclosed_class {
				p.index = saved_index
				p.prev = saved_prev
				p.cur = saved_cur
				p.found_unclosed_class = true
				p.push_token(token_literal(`[`))!
				return
			}
			return p.mk_error(ErrorKind.unclosed_class())
		}
		match ch {
			`]` {
				if first {
					ranges << TokenRange{
						start: `]`
						end:   `]`
					}
				} else {
					break
				}
			}
			`-` {
				if first {
					ranges << TokenRange{
						start: `-`
						end:   `-`
					}
				} else if in_range {
					// invariant: in_range is only set when there is
					// already at least one character seen.
				ranges[ranges.len - 1] = p.add_to_last_range(ranges[ranges.len - 1], `-`)!
					in_range = false
				} else {
					assert ranges.len > 0
					in_range = true
				}
			}
			else {
				if in_range {
					// invariant: in_range is only set when there is
					// already at least one character seen.
				ranges[ranges.len - 1] = p.add_to_last_range(ranges[ranges.len - 1], ch)!
				} else {
					ranges << TokenRange{
						start: ch
						end:   ch
					}
				}
				in_range = false
			}
		}
		first = false
	}
	if in_range {
		// Means that the last character in the class was a '-', so add
		// it as a literal.
		ranges << TokenRange{
			start: `-`
			end:   `-`
		}
	}
	p.push_token(token_class(negated, ranges))!
}

fn (mut p Parser[^a]) bump() ?rune {
	p.prev = p.cur
	if p.index >= p.chars.len {
		p.cur = none
		return none
	}
	ch := p.chars[p.index]
	p.index++
	p.cur = ch
	return ch
}

fn (p &Parser[^a]) peek() ?rune {
	if p.index >= p.chars.len {
		return none
	}
	return p.chars[p.index]
}

fn is_separator(ch rune) bool {
	return ch == `/` || $if windows { ch == `\\` } $else { false }
}
