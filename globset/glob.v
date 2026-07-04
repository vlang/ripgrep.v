module globset

enum MatchStrategyKind {
	literal
	basename_literal
	extension
	prefix
	suffix
	required_extension
	regex
}

struct MatchStrategy {
	kind      MatchStrategyKind
	value     string
	component bool
}

/// Describes a matching strategy for a particular pattern.
///
/// This provides a way to more quickly determine whether a pattern matches
/// a particular file path in a way that scales with a large number of
/// patterns. For example, if many patterns are of the form `*.ext`, then it's
/// possible to test whether any of those patterns matches by looking up a
/// file path's extension in a hash table.
fn match_strategy_new(pat Glob) MatchStrategy {
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
	} else if suffix_pair := pat.suffix() {
		suffix, component := suffix_pair
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

fn (tok Token) clone() Token {
	return Token{
		kind:     tok.kind
		ch:       tok.ch
		negated:  tok.negated
		ranges:   tok.ranges.clone()
		patterns: tok.patterns.clone()
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

fn Tokens.default() Tokens {
	return Tokens{
		tokens: []Token{}
	}
}

fn (mut t Tokens) push(tok Token) {
	t.tokens << tok
}

fn (mut t Tokens) pop() ?Token {
	if t.tokens.len == 0 {
		return none
	}
	last := t.tokens[t.tokens.len - 1]
	t.tokens = t.tokens[..t.tokens.len - 1]
	return last
}

fn (t Tokens) len() int {
	return t.tokens.len
}

fn (t Tokens) is_empty() bool {
	return t.tokens.len == 0
}

fn (t Tokens) clone_slice(start int, end int) []Token {
	mut cloned := []Token{}
	for i := start; i < end; i++ {
		tok := t.tokens[i]
		cloned << tok.clone()
	}
	return cloned
}

fn (t Tokens) str() string {
	mut pieces := []string{}
	for tok in t.tokens {
		pieces << tok.str()
	}
	return '[' + pieces.join(',') + ']'
}

struct GlobOptions implements IClone {
	case_insensitive    bool
	literal_separator   bool
	backslash_escape    bool
	empty_alternates    bool
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
	glob_  string
	re_    string
	opts   GlobOptions
	tokens Tokens
}

pub fn Glob.new(glob string) !Glob {
	mut builder := GlobBuilder.new(&glob)
	return builder.build()
}

/// Returns a matcher for this pattern.
pub fn (g Glob) compile_matcher() GlobMatcher {
	return GlobMatcher{
		pat: g.clone()
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

fn (g Glob) literal() ?string {
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

fn (g Glob) ext() ?string {
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
	if start == 0 && g.opts.literal_separator {
		return none
	}
	if start + 1 >= g.tokens.tokens.len || g.tokens.tokens[start + 1].kind != .literal
		|| g.tokens.tokens[start + 1].ch != `.` {
		return none
	}
	mut lit := '.'
	for i := start + 2; i < g.tokens.tokens.len; i++ {
		tok := g.tokens.tokens[i]
		if tok.kind != .literal || tok.ch == `.` || tok.ch == `/` {
			return none
		}
		lit += tok.ch.str()
	}
	return lit
}

fn (g Glob) required_ext() ?string {
	if g.opts.case_insensitive {
		return none
	}
	mut chars := []rune{}
	for i := g.tokens.tokens.len - 1; i >= 0; i-- {
		tok := g.tokens.tokens[i]
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

fn (g Glob) prefix() ?string {
	if g.opts.case_insensitive || g.tokens.tokens.len == 0 {
		return none
	}
	mut end := g.tokens.tokens.len
	mut need_sep := false
	last := g.tokens.tokens[g.tokens.tokens.len - 1]
	if last.kind == .zero_or_more {
		if g.opts.literal_separator {
			return none
		}
		end--
	} else if last.kind == .recursive_suffix {
		end--
		need_sep = true
	}
	mut lit := ''
	for i := 0; i < end; i++ {
		tok := g.tokens.tokens[i]
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

fn (g Glob) suffix() ?(string, bool) {
	if g.opts.case_insensitive || g.tokens.tokens.len == 0 {
		return none
	}
	mut lit := ''
	mut start := 0
	mut entire := false
	if g.tokens.tokens[0].kind == .recursive_prefix {
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
		if g.opts.literal_separator {
			return none
		}
		start++
	}
	for i := start; i < g.tokens.tokens.len; i++ {
		tok := g.tokens.tokens[i]
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

fn (g Glob) basename_tokens() ?[]Token {
	if g.opts.case_insensitive || g.tokens.tokens.len == 0 {
		return none
	}
	if g.tokens.tokens[0].kind != .recursive_prefix {
		return none
	}
	if g.tokens.tokens.len == 1 {
		return none
	}
	for i := 1; i < g.tokens.tokens.len; i++ {
		tok := g.tokens.tokens[i]
		match tok.kind {
			.literal {
				if tok.ch == `/` {
					return none
				}
			}
			.any, .zero_or_more {
				if !g.opts.literal_separator {
					return none
				}
			}
			.recursive_prefix, .recursive_suffix, .recursive_zero_or_more, .class, .alternates {
				return none
			}
		}
	}
	mut tokens := []Token{}
	for i := 1; i < g.tokens.tokens.len; i++ {
		tok := g.tokens.tokens[i]
		tokens << tok.clone()
	}
	return tokens
}

fn (g Glob) basename_literal() ?string {
	tokens := g.basename_tokens() or { return none }
	mut lit := ''
	for tok in tokens {
		if tok.kind != .literal {
			return none
		}
		lit += tok.ch.str()
	}
	return lit
}

pub fn (g Glob) str() string {
	return g.glob_
}

/// A matcher for a single pattern.
pub struct GlobMatcher implements IClone {
	pat Glob
}

/// Tests whether the given path matches this pattern or not.
pub fn (gm GlobMatcher) is_match(path string) bool {
	candidate := Candidate.new(&path)
	return gm.is_match_candidate(candidate)
}

/// Tests whether the given path matches this pattern or not.
pub fn (gm GlobMatcher) is_match_candidate[^a](path Candidate[^a]) bool {
	return glob_matches_candidate(gm.pat, path)
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
	glob &^a string
mut:
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
pub fn (builder GlobBuilder[^a]) build[^a]() !Glob {
	parse_glob := if builder.opts.case_insensitive {
		(*builder.glob).to_lower()
	} else {
		(*builder.glob).to_owned()
	}
	mut parser := Parser{
		glob:                   &parse_glob
		alternates_stack:       []int{}
		branches:               [Tokens.default()]
		chars:                  parse_glob.runes()
		index:                  0
		prev:                   none
		cur:                    none
		found_unclosed_class:   false
		opts:                   &builder.opts
	}
	parser.parse()!
	if parser.branches.len == 0 {
		panic('glob parser invariant violated')
	}
	if parser.branches.len > 1 {
		glob_err := GlobError{
			glob_: *builder.glob
			kind_: ErrorKind.unclosed_alternates()
		}
		return error(glob_err.msg())
	}
	tokens := parser.branches[0].clone()
	return Glob{
		glob_:  (*builder.glob).to_owned()
		re_:    tokens.to_regex_with(builder.opts)
		opts:   builder.opts
		tokens: tokens
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

fn (tokens Tokens) to_regex_with(options GlobOptions) string {
	mut re := '(?-u)'
	if options.case_insensitive {
		re += '(?i)'
	}
	re += '^'
	if tokens.tokens.len == 1 && tokens.tokens[0].kind == .recursive_prefix {
		re += '.*'
		re += r'$'
		return re
	}
	tokens.tokens_to_regex(options, tokens.tokens, mut re)
	re += r'$'
	return re
}

fn (tokens Tokens) tokens_to_regex(options GlobOptions, src []Token, mut re string) {
	for tok in src {
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
					mut alt := ''
					pat.tokens_to_regex(options, pat.tokens, mut alt)
					if alt != '' || options.empty_alternates {
						parts << alt
					}
				}
				if parts.len > 0 {
					re += '(?:' + parts.join('|') + ')'
				}
			}
		}
	}
}

fn char_to_escaped_literal(ch rune) string {
	return bytes_to_escaped_literal(ch.str().bytes())
}

fn bytes_to_escaped_literal(bytes []u8) string {
	mut s := ''
	for b in bytes {
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
	return b in [`\\`, `.`, `+`, `*`, `?`, `(`, `)`, `|`, `[`, `]`, `{`, `}`, `^`, `$`]
}

struct Parser {
	glob &string
mut:
	alternates_stack     []int
	branches             []Tokens
	chars                []rune
	index                int
	prev                 ?rune
	cur                  ?rune
	found_unclosed_class bool
	opts                 &GlobOptions
}

fn (p Parser) mk_error(kind ErrorKind) GlobError {
	return GlobError{
		glob_: *p.glob
		kind_: kind
	}
}

fn (mut p Parser) parse() ! {
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

fn (mut p Parser) push_alternate() ! {
	p.alternates_stack << p.branches.len
	p.branches << Tokens.default()
}

fn (mut p Parser) pop_alternate() ! {
	if p.alternates_stack.len == 0 {
		return error(p.mk_error(ErrorKind.unopened_alternates()).msg())
	}
	start := p.alternates_stack[p.alternates_stack.len - 1]
	p.alternates_stack = p.alternates_stack[..p.alternates_stack.len - 1]
	mut patterns := []Tokens{}
	for i := start; i < p.branches.len; i++ {
		branch := p.branches[i]
		patterns << branch.clone()
	}
	p.branches = p.branches[..start]
	p.push_token(token_alternates(patterns))!
}

fn (mut p Parser) push_token(tok Token) ! {
	if p.branches.len == 0 {
		return error(p.mk_error(ErrorKind.unopened_alternates()).msg())
	}
	mut last := p.branches[p.branches.len - 1]
	last.push(tok)
	p.branches[p.branches.len - 1] = last
}

fn (mut p Parser) pop_token() !Token {
	if p.branches.len == 0 {
		return error(p.mk_error(ErrorKind.unopened_alternates()).msg())
	}
	mut last := p.branches[p.branches.len - 1]
	tok := last.pop() or { panic('missing token in parser') }
	p.branches[p.branches.len - 1] = last
	return tok
}

fn (p Parser) have_tokens() !bool {
	if p.branches.len == 0 {
		return error(p.mk_error(ErrorKind.unopened_alternates()).msg())
	}
	return !p.branches[p.branches.len - 1].is_empty()
}

fn (mut p Parser) parse_comma() ! {
	if p.alternates_stack.len == 0 {
		p.push_token(token_literal(`,`))!
		return
	}
	p.branches << Tokens.default()
}

fn (mut p Parser) parse_backslash() ! {
	if p.opts.backslash_escape {
		next := p.bump() or { return error(p.mk_error(ErrorKind.dangling_escape()).msg()) }
		p.push_token(token_literal(next))!
		return
	}
	$if windows {
		p.push_token(token_literal(`/`))!
	} $else {
		p.push_token(token_literal(`\\`))!
	}
}

fn (mut p Parser) parse_star() ! {
	prev := p.prev
	if p.peek() != `*` {
		p.push_token(token_zero_or_more())!
		return
	}
	assert p.bump() or { `\0` } == `*`
	if !p.have_tokens()! {
		next := p.peek()
		if next != `\0` && !is_separator(next) {
			p.push_token(token_zero_or_more())!
			p.push_token(token_zero_or_more())!
		} else {
			p.push_token(token_recursive_prefix())!
			if next != `\0` && is_separator(next) {
				_ := p.bump()
			}
		}
		return
	}
	if prev == none || !is_separator(prev or { `\0` }) {
		if p.branches.len <= 1 || ((prev or { `\0` }) != `,` && (prev or { `\0` }) != `{`) {
			p.push_token(token_zero_or_more())!
			p.push_token(token_zero_or_more())!
			return
		}
	}
	mut is_suffix := false
	next := p.peek()
	if next == `\0` {
		_ := p.bump()
		is_suffix = true
	} else if (next == `,` || next == `}`) && p.branches.len >= 2 {
		is_suffix = true
	} else if is_separator(next) {
		_ := p.bump()
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

fn (mut p Parser) parse_class() ! {
	saved_index := p.index
	saved_prev := p.prev
	saved_cur := p.cur
	mut ranges := []TokenRange{}
	mut negated := false
	peek := p.peek()
	if peek == `!` || peek == `^` {
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
			return error(p.mk_error(ErrorKind.unclosed_class()).msg())
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
					mut last := ranges[ranges.len - 1]
					last.end = `-`
					if last.end < last.start {
						return error(p.mk_error(ErrorKind.invalid_range(last.start, last.end)).msg())
					}
					ranges[ranges.len - 1] = last
					in_range = false
				} else {
					in_range = true
				}
			}
			else {
				if in_range {
					mut last := ranges[ranges.len - 1]
					last.end = ch
					if last.end < last.start {
						return error(p.mk_error(ErrorKind.invalid_range(last.start, last.end)).msg())
					}
					ranges[ranges.len - 1] = last
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
		ranges << TokenRange{
			start: `-`
			end:   `-`
		}
	}
	p.push_token(token_class(negated, ranges))!
}

fn (mut p Parser) bump() ?rune {
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

fn (p Parser) peek() rune {
	if p.index >= p.chars.len {
		return `\0`
	}
	return p.chars[p.index]
}

fn is_separator(ch rune) bool {
	return ch == `/` || $if windows { ch == `\\` } $else { false }
}

fn glob_matches_candidate[^a](glob Glob, candidate Candidate[^a]) bool {
	path := if glob.opts.case_insensitive {
		candidate.path_.to_lower()
	} else {
		candidate.path_
	}
	return glob_match_tokens(glob.tokens.tokens, glob.opts, path.runes())
}

fn glob_match_tokens(tokens []Token, opts GlobOptions, text []rune) bool {
	return glob_match_tokens_from(tokens, opts, text, 0, 0)
}

fn glob_match_tokens_from(tokens []Token, opts GlobOptions, text []rune, pi int, ti int) bool {
	if pi >= tokens.len {
		return ti >= text.len
	}
	tok := tokens[pi]
	match tok.kind {
		.literal {
			return ti < text.len && tok.ch == text[ti] && glob_match_tokens_from(tokens, opts, text,
				pi + 1, ti + 1)
		}
		.any {
			if ti >= text.len {
				return false
			}
			if opts.literal_separator && text[ti] == `/` {
				return false
			}
			return glob_match_tokens_from(tokens, opts, text, pi + 1, ti + 1)
		}
		.zero_or_more {
			if opts.literal_separator {
				mut j := ti
				for {
					if glob_match_tokens_from(tokens, opts, text, pi + 1, j) {
						return true
					}
					if j >= text.len || text[j] == `/` {
						break
					}
					j++
				}
				return false
			}
			for j := ti; j <= text.len; j++ {
				if glob_match_tokens_from(tokens, opts, text, pi + 1, j) {
					return true
				}
			}
			return false
		}
		.recursive_prefix {
			if pi == tokens.len - 1 {
				return true
			}
			if glob_match_tokens_from(tokens, opts, text, pi + 1, ti) {
				return true
			}
			for j := ti; j < text.len; j++ {
				if text[j] == `/` && glob_match_tokens_from(tokens, opts, text, pi + 1, j + 1) {
					return true
				}
			}
			return false
		}
		.recursive_suffix {
			if ti >= text.len || text[ti] != `/` {
				return false
			}
			if pi == tokens.len - 1 {
				return true
			}
			for j := ti + 1; j <= text.len; j++ {
				if glob_match_tokens_from(tokens, opts, text, pi + 1, j) {
					return true
				}
			}
			return false
		}
		.recursive_zero_or_more {
			if ti >= text.len || text[ti] != `/` {
				return false
			}
			if glob_match_tokens_from(tokens, opts, text, pi + 1, ti + 1) {
				return true
			}
			for j := ti + 1; j < text.len; j++ {
				if text[j] == `/` && glob_match_tokens_from(tokens, opts, text, pi + 1, j + 1) {
					return true
				}
			}
			return false
		}
		.class {
			return ti < text.len && glob_class_matches(tok, text[ti]) && glob_match_tokens_from(tokens,
				opts, text, pi + 1, ti + 1)
		}
		.alternates {
			for branch in tok.patterns {
				mut combined := []Token{}
				for item in branch.tokens {
					combined << item.clone()
				}
				for i := pi + 1; i < tokens.len; i++ {
					item := tokens[i]
					combined << item.clone()
				}
				if glob_match_tokens_from(combined, opts, text, 0, ti) {
					return true
				}
			}
			return false
		}
	}
}

fn glob_class_matches(tok Token, ch rune) bool {
	mut matched := false
	for rng in tok.ranges {
		if rng.start <= ch && ch <= rng.end {
			matched = true
			break
		}
	}
	return if tok.negated { !matched } else { matched }
}
