module globset

import regex.meta

/*
The globset crate provides cross platform single glob and glob set matching.

Glob set matching is the process of matching one or more glob patterns against
a single candidate path simultaneously, and returning all of the globs that
matched. For example, given this set of globs:

* `*.rs`
* `src/lib.rs`
* `src/**/foo.rs`

and a path `src/bar/baz/foo.rs`, then the set would report the first and third
globs as matching.

# Example: one glob

This example shows how to match a single glob against a single file path.

```
glob := globset.Glob.new("*.rs")!
matcher := glob.compile_matcher()

assert matcher.is_match("foo.rs")
assert matcher.is_match("foo/bar.rs")
assert !matcher.is_match("Cargo.toml")
```

# Example: configuring a glob matcher

This example shows how to use a `GlobBuilder` to configure aspects of match
semantics. In this example, we prevent wildcards from matching path separators.

```
mut builder := globset.GlobBuilder.new("*.rs")
builder.literal_separator(true)
glob := builder.build()!
matcher := glob.compile_matcher()

assert matcher.is_match("foo.rs")
assert !matcher.is_match("foo/bar.rs")
assert !matcher.is_match("Cargo.toml")
```

# Example: match multiple globs at once

This example shows how to match multiple glob patterns at once.

```
mut builder := globset.GlobSetBuilder.new()
builder.add(globset.Glob.new("*.rs")!)
builder.add(globset.Glob.new("src/lib.rs")!)
builder.add(globset.Glob.new("src/**/foo.rs")!)
set := builder.build()!

assert set.matches("src/bar/baz/foo.rs") == [0, 2]
```

# Syntax

Standard Unix-style glob syntax is supported:

* `?` matches any single character. (If the `literal_separator` option is
  enabled, then `?` can never match a path separator.)
* `*` matches zero or more characters. (If the `literal_separator` option is
  enabled, then `*` can never match a path separator.)
* `**` recursively matches directories but are only legal in three situations.
  First, if the glob starts with <code>\*\*&#x2F;</code>, then it matches all
  directories. For example, <code>\*\*&#x2F;foo</code> matches `foo` and
  `bar/foo` but not `foo/bar`. Secondly, if the glob ends with
  <code>&#x2F;\*\*</code>, then it matches all sub-entries. For example,
  <code>foo&#x2F;\*\*</code> matches `foo/a` and `foo/a/b`, but not `foo`.
  Thirdly, if the glob contains <code>&#x2F;\*\*&#x2F;</code> anywhere within
  the pattern, then it matches zero or more
  directories. Using `**` anywhere else is illegal (N.B. the glob `**` is
  allowed and means "match everything").
* `{a,b}` matches `a` or `b` where `a` and `b` are arbitrary glob patterns.
  (N.B. Nesting `{...}` is not currently allowed.)
* `[ab]` matches `a` or `b` where `a` and `b` are characters. Use
  `[!ab]` to match any character except for `a` and `b`.
* Metacharacters such as `*` and `?` can be escaped with character class
  notation. e.g., `[*]` matches `*`.
* When backslash escapes are enabled, a backslash (`\`) will escape all meta
  characters in a glob. If it precedes a non-meta character, then the slash is
  ignored. A `\\` will match a literal `\\`. Note that this mode is only
  enabled on Unix platforms by default, but can be enabled on any platform
  via the `backslash_escape` setting on `Glob`.

A `GlobBuilder` can be used to prevent wildcards from matching path separators,
or to enable case insensitive matching.
*/

/// Represents an error that can occur when parsing a glob pattern.
///
/// V-specific type name: the Rust crate uses `Error`, but this port uses
/// `GlobError` because `Error` conflicts with V's builtin `Error` type during
/// ownership-mode direct compilation.
///
pub struct GlobError implements IClone {
	glob_ ?string
	kind_ ErrorKind
}

/// The kind of error that can occur when parsing a glob pattern.
pub struct ErrorKind implements IClone {
pub:
	/// V-specific discriminant for the translated Rust enum.
	tag ErrorKindTag
	/// V-specific starting character payload used by `invalid_range`.
	start rune
	/// V-specific ending character payload used by `invalid_range`.
	end rune
	/// V-specific payload field used by `regex`.
	details string
}

pub enum ErrorKindTag {
	/// **DEPRECATED**.
	///
	/// This error used to occur for consistency with git's glob specification,
	/// but the specification now accepts all uses of `**`. When `**` does not
	/// appear adjacent to a path separator or at the beginning/end of a glob,
	/// it is now treated as two consecutive `*` patterns. As such, this error
	/// is no longer used.
	invalid_recursive
	/// Occurs when a character class (e.g., `[abc]`) is not closed.
	unclosed_class
	/// Occurs when a range in a character (e.g., `[a-z]`) is invalid. For
	/// example, if the range starts with a lexicographically larger character
	/// than it ends with.
	invalid_range
	/// Occurs when a `}` is found without a matching `{`.
	unopened_alternates
	/// Occurs when a `{` is found without a matching `}`.
	unclosed_alternates
	/// **DEPRECATED**.
	///
	/// This error used to occur when an alternating group was nested inside
	/// another alternating group, e.g., `{{a,b},{c,d}}`. However, this is now
	/// supported and as such this error cannot occur.
	nested_alternates
	/// Occurs when an unescaped '\' is found at the end of a glob.
	dangling_escape
	/// An error associated with parsing or compiling a regex.
	regex
}

pub fn ErrorKind.invalid_recursive() ErrorKind {
	return ErrorKind{
		tag: .invalid_recursive
	}
}

pub fn ErrorKind.unclosed_class() ErrorKind {
	return ErrorKind{
		tag: .unclosed_class
	}
}

pub fn ErrorKind.invalid_range(start rune, end rune) ErrorKind {
	return ErrorKind{
		tag:   .invalid_range
		start: start
		end:   end
	}
}

pub fn ErrorKind.unopened_alternates() ErrorKind {
	return ErrorKind{
		tag: .unopened_alternates
	}
}

pub fn ErrorKind.unclosed_alternates() ErrorKind {
	return ErrorKind{
		tag: .unclosed_alternates
	}
}

pub fn ErrorKind.nested_alternates() ErrorKind {
	return ErrorKind{
		tag: .nested_alternates
	}
}

pub fn ErrorKind.dangling_escape() ErrorKind {
	return ErrorKind{
		tag: .dangling_escape
	}
}

pub fn ErrorKind.regex(details string) ErrorKind {
	return ErrorKind{
		tag:     .regex
		details: details
	}
}

pub fn (kind ErrorKind) description() string {
	return match kind.tag {
		.invalid_recursive { 'invalid use of **; must be one path component' }
		.unclosed_class { 'unclosed character class; missing \']\'' }
		.invalid_range { 'invalid character range' }
		.unopened_alternates { 'unopened alternate group; missing \'{\' (maybe escape \'}\' with \'[}]\'?)' }
		.unclosed_alternates { 'unclosed alternate group; missing \'}\' (maybe escape \'{\' with \'[{]\'?)' }
		.nested_alternates { 'nested alternate groups are not allowed' }
		.dangling_escape { 'dangling \'\\\\\'' }
		.regex { kind.details }
	}
}

pub fn (kind ErrorKind) str() string {
	return if kind.tag == .invalid_range {
		"invalid range; '${kind.start.str()}' > '${kind.end.str()}'"
	} else {
		kind.description()
	}
}

/// Return the glob that caused this error, if one exists.
pub fn (err &^a GlobError) glob[^a]() ?&^a string {
	if err.glob_ != none {
		return unsafe { &err.glob_? }
	}
	return none
}

/// Return the kind of this error.
pub fn (err &^a GlobError) kind[^a]() &^a ErrorKind {
	return &err.kind_
}

pub fn (err GlobError) msg() string {
	if glob := err.glob_ {
		return 'error parsing glob \'${glob}\': ${err.kind_}'
	}
	return err.kind_.str()
}

pub fn (err GlobError) code() int {
	_ = err
	return 1
}

fn new_regex(pat &string) !meta.Regex {
	return meta.compile_with_limits('(?s)' + *pat, usize(10 * (1 << 20)), usize(10 * (1 << 20))) or {
		glob_err := GlobError{
			glob_: (*pat).to_owned()
			kind_: ErrorKind.regex(err.msg())
		}
		return glob_err
	}
}

/// A candidate path for matching.
///
/// All glob matching in this crate operates on `Candidate` values.
/// Constructing candidates has a very small cost associated with it, so
/// callers may find it beneficial to amortize that cost when matching a single
/// path against multiple globs or sets of globs.
///
/// V-specific representation note: this keeps the Rust lifetime parameter but
/// stores normalized path views as V strings instead of `Cow<[u8]>`.
pub struct Candidate[^a] implements IClone {
	path_     string
	basename_ string
	ext_      string
}

/// Create a new candidate for matching from the given path.
pub fn Candidate.new[^a](path &^a string) Candidate[^a] {
	return candidate_from_string(path)
}

/// Create a new candidate for matching from the given path as a sequence
/// of bytes.
///
/// Generally speaking, this routine expects the bytes to be
/// _conventionally_ UTF-8. It is legal for the byte sequence to contain
/// invalid UTF-8. However, if the bytes are in some other encoding that
/// isn't ASCII compatible (for example, UTF-16), then the results of
/// matching are unspecified.
pub fn Candidate.from_bytes[^a](path &^a []u8) Candidate[^a] {
	text := path.bytestr()
	return candidate_from_string(&text)
}

fn candidate_from_string[^a](path &^a string) Candidate[^a] {
	npath := normalize_path(*path)
	basename := file_name(npath) or { '' }
	ext := file_name_ext(basename.clone()) or { '' }
	return Candidate[^a]{
		path_:     npath
		basename_: basename
		ext_:      ext
	}
}

fn (candidate &Candidate[^a]) path_prefix[^a](max usize) string {
	if candidate.path_.len <= int(max) {
		return candidate.path_
	}
	return unsafe { candidate.path_.substr_unsafe(0, int(max)) }
}

fn (candidate &Candidate[^a]) path_suffix[^a](max usize) string {
	if candidate.path_.len <= int(max) {
		return candidate.path_
	}
	start := candidate.path_.len - int(max)
	return unsafe { candidate.path_.substr_unsafe(start, candidate.path_.len) }
}

type GlobSetMatchStrategy = BasenameLiteralStrategy | ExtensionStrategy | LiteralStrategy | PrefixStrategy | RegexSetStrategy | RequiredExtensionStrategy | SuffixStrategy

struct LiteralStrategy implements IClone {
mut:
	entries map[string][]usize
}

fn LiteralStrategy.new() LiteralStrategy {
	return LiteralStrategy{
		entries: map[string][]usize{}
	}
}

fn (mut s LiteralStrategy) add(global_index usize, lit string) {
	mut hits := s.entries[lit] or { []usize{} }
	hits << global_index
	s.entries[lit] = hits
}

fn (s &LiteralStrategy) is_match[^a](candidate &Candidate[^a]) bool {
	return candidate.path_ in s.entries
}

fn (s &LiteralStrategy) matches_into[^a](candidate &Candidate[^a], mut matches []usize) {
	if hits := s.entries[candidate.path_] {
		matches << hits
	}
}

struct BasenameLiteralStrategy implements IClone {
mut:
	entries map[string][]usize
}

fn BasenameLiteralStrategy.new() BasenameLiteralStrategy {
	return BasenameLiteralStrategy{
		entries: map[string][]usize{}
	}
}

fn (mut s BasenameLiteralStrategy) add(global_index usize, lit string) {
	mut hits := s.entries[lit] or { []usize{} }
	hits << global_index
	s.entries[lit] = hits
}

fn (s &BasenameLiteralStrategy) is_match[^a](candidate &Candidate[^a]) bool {
	if candidate.basename_ == '' {
		return false
	}
	return candidate.basename_ in s.entries
}

fn (s &BasenameLiteralStrategy) matches_into[^a](candidate &Candidate[^a], mut matches []usize) {
	if candidate.basename_ == '' {
		return
	}
	if hits := s.entries[candidate.basename_] {
		matches << hits
	}
}

struct ExtensionStrategy implements IClone {
mut:
	entries map[string][]usize
}

fn ExtensionStrategy.new() ExtensionStrategy {
	return ExtensionStrategy{
		entries: map[string][]usize{}
	}
}

fn (mut s ExtensionStrategy) add(global_index usize, ext string) {
	mut hits := s.entries[ext] or { []usize{} }
	hits << global_index
	s.entries[ext] = hits
}

fn (s &ExtensionStrategy) is_match[^a](candidate &Candidate[^a]) bool {
	if candidate.ext_ == '' {
		return false
	}
	return candidate.ext_ in s.entries
}

fn (s &ExtensionStrategy) matches_into[^a](candidate &Candidate[^a], mut matches []usize) {
	if candidate.ext_ == '' {
		return
	}
	if hits := s.entries[candidate.ext_] {
		matches << hits
	}
}

struct PrefixStrategy implements IClone {
	// V-specific: Aho-Corasick is an external Cargo dependency, so this port
	// stores its literal patterns directly while preserving overlapping-prefix
	// match behavior.
	patterns []string
	map_     []usize
	longest  usize
}

fn (s &PrefixStrategy) is_match[^a](candidate &Candidate[^a]) bool {
	path := candidate.path_prefix(s.longest)
	for i, pattern in s.patterns {
		if path.starts_with(pattern) {
			_ = i
			return true
		}
	}
	return false
}

fn (s &PrefixStrategy) matches_into[^a](candidate &Candidate[^a], mut matches []usize) {
	path := candidate.path_prefix(s.longest)
	for i, pattern in s.patterns {
		if path.starts_with(pattern) {
			matches << s.map_[i]
		}
	}
}

struct SuffixStrategy implements IClone {
	// V-specific: Aho-Corasick is an external Cargo dependency, so this port
	// stores its literal patterns directly while preserving overlapping-suffix
	// match behavior.
	patterns []string
	map_     []usize
	longest  usize
}

fn (s &SuffixStrategy) is_match[^a](candidate &Candidate[^a]) bool {
	path := candidate.path_suffix(s.longest)
	for pattern in s.patterns {
		if path.ends_with(pattern) {
			return true
		}
	}
	return false
}

fn (s &SuffixStrategy) matches_into[^a](candidate &Candidate[^a], mut matches []usize) {
	path := candidate.path_suffix(s.longest)
	for i, pattern in s.patterns {
		if path.ends_with(pattern) {
			matches << s.map_[i]
		}
	}
}

struct RequiredExtensionEntry implements IClone {
	global_index usize
	matcher      meta.Regex
}

struct RequiredExtensionStrategy implements IClone {
	entries map[string][]RequiredExtensionEntry
}

fn (s &RequiredExtensionStrategy) is_match[^a](candidate &Candidate[^a]) bool {
	if candidate.ext_ == '' {
		return false
	}
	if entries := s.entries[candidate.ext_] {
		for entry in entries {
			if entry.matcher.find(candidate.path_) != none {
				return true
			}
		}
	}
	return false
}

fn (s &RequiredExtensionStrategy) matches_into[^a](candidate &Candidate[^a], mut matches []usize) {
	if candidate.ext_ == '' {
		return
	}
	if entries := s.entries[candidate.ext_] {
		for entry in entries {
			if entry.matcher.find(candidate.path_) != none {
				matches << entry.global_index
			}
		}
	}
}

struct RegexSetEntry implements IClone {
	global_index usize
	matcher      meta.Regex
}

struct RegexSetStrategy implements IClone {
	// V-specific: the local regex VM has no multi-pattern `PatternSet`, so
	// each compiled pattern retains its original global index here.
	entries []RegexSetEntry
}

fn (s &RegexSetStrategy) is_match[^a](candidate &Candidate[^a]) bool {
	for entry in s.entries {
		if entry.matcher.find(candidate.path_) != none {
			return true
		}
	}
	return false
}

fn (s &RegexSetStrategy) matches_into[^a](candidate &Candidate[^a], mut matches []usize) {
	for entry in s.entries {
		if entry.matcher.find(candidate.path_) != none {
			matches << entry.global_index
		}
	}
}

fn glob_set_strategy_is_match[^a](strat &GlobSetMatchStrategy, candidate &Candidate[^a]) bool {
	if *strat is LiteralStrategy {
		return ((*strat) as LiteralStrategy).is_match(candidate)
	}
	if *strat is BasenameLiteralStrategy {
		return ((*strat) as BasenameLiteralStrategy).is_match(candidate)
	}
	if *strat is ExtensionStrategy {
		return ((*strat) as ExtensionStrategy).is_match(candidate)
	}
	if *strat is PrefixStrategy {
		return ((*strat) as PrefixStrategy).is_match(candidate)
	}
	if *strat is SuffixStrategy {
		return ((*strat) as SuffixStrategy).is_match(candidate)
	}
	if *strat is RequiredExtensionStrategy {
		return ((*strat) as RequiredExtensionStrategy).is_match(candidate)
	}
	return ((*strat) as RegexSetStrategy).is_match(candidate)
}

fn glob_set_strategy_matches_into[^a](strat &GlobSetMatchStrategy, candidate &Candidate[^a], mut matches []usize) {
	if *strat is LiteralStrategy {
		((*strat) as LiteralStrategy).matches_into(candidate, mut matches)
		return
	}
	if *strat is BasenameLiteralStrategy {
		((*strat) as BasenameLiteralStrategy).matches_into(candidate, mut matches)
		return
	}
	if *strat is ExtensionStrategy {
		((*strat) as ExtensionStrategy).matches_into(candidate, mut matches)
		return
	}
	if *strat is PrefixStrategy {
		((*strat) as PrefixStrategy).matches_into(candidate, mut matches)
		return
	}
	if *strat is SuffixStrategy {
		((*strat) as SuffixStrategy).matches_into(candidate, mut matches)
		return
	}
	if *strat is RequiredExtensionStrategy {
		((*strat) as RequiredExtensionStrategy).matches_into(candidate, mut matches)
		return
	}
	((*strat) as RegexSetStrategy).matches_into(candidate, mut matches)
}

struct MultiStrategyBuilder implements IClone {
mut:
	literals []string
	map_     []usize
	longest  usize
}

fn MultiStrategyBuilder.new() MultiStrategyBuilder {
	return MultiStrategyBuilder{
		literals: []string{}
		map_:     []usize{}
		longest:  0
	}
}

fn (mut b MultiStrategyBuilder) add(global_index usize, literal string) {
	if usize(literal.len) > b.longest {
		b.longest = usize(literal.len)
	}
	b.map_ << global_index
	b.literals << literal
}

fn (b MultiStrategyBuilder) prefix() PrefixStrategy {
	return PrefixStrategy{
		patterns: b.literals
		map_:     b.map_
		longest:  b.longest
	}
}

fn (b MultiStrategyBuilder) suffix() SuffixStrategy {
	return SuffixStrategy{
		patterns: b.literals
		map_:     b.map_
		longest:  b.longest
	}
}

fn (b MultiStrategyBuilder) regex_set() !RegexSetStrategy {
	mut entries := []RegexSetEntry{}
	for i, literal in b.literals {
		entries << RegexSetEntry{
			global_index: b.map_[i]
			matcher:      new_regex(&literal)!
		}
	}
	return RegexSetStrategy{
		entries: entries
	}
}

fn (b &MultiStrategyBuilder) is_empty() bool {
	return b.literals.len == 0
}

struct RequiredExtensionBuilderEntry implements IClone {
	global_index usize
	regex        string
}

struct RequiredExtensionStrategyBuilder implements IClone {
mut:
	entries map[string][]RequiredExtensionBuilderEntry
}

fn RequiredExtensionStrategyBuilder.new() RequiredExtensionStrategyBuilder {
	return RequiredExtensionStrategyBuilder{
		entries: map[string][]RequiredExtensionBuilderEntry{}
	}
}

fn (mut b RequiredExtensionStrategyBuilder) add(global_index usize, ext string, regex string) {
	mut items := b.entries[ext] or { []RequiredExtensionBuilderEntry{} }
	items << RequiredExtensionBuilderEntry{
		global_index: global_index
		regex:        regex
	}
	b.entries[ext] = items
}

fn (b RequiredExtensionStrategyBuilder) build() !RequiredExtensionStrategy {
	mut entries := map[string][]RequiredExtensionEntry{}
	for ext, items in b.entries {
		mut compiled := []RequiredExtensionEntry{}
		for item in items {
			compiled << RequiredExtensionEntry{
				global_index: item.global_index
				matcher:      new_regex(&item.regex)!
			}
		}
		entries[ext] = compiled
	}
	return RequiredExtensionStrategy{
		entries: entries
	}
}

/// GlobSet represents a group of globs that can be matched together in a
/// single pass.
pub struct GlobSet implements IClone {
	mut:
	len_   usize
	strats []GlobSetMatchStrategy
}

// V-specific: V3 cannot yet synthesize cloning for a struct field whose
// element is a private sum type with owned payloads. This is the direct clone
// of each strategy variant used by Rust's derived `Clone` implementation.
pub fn (gs &GlobSet) clone() GlobSet {
	mut strats := []GlobSetMatchStrategy{cap: gs.strats.len}
	for i in 0 .. gs.strats.len {
		strats << clone_glob_set_match_strategy(&gs.strats[i])
	}
	return GlobSet{
		len_:   gs.len_
		strats: strats
	}
}

fn clone_glob_set_match_strategy(strat &GlobSetMatchStrategy) GlobSetMatchStrategy {
	if *strat is LiteralStrategy {
		return ((*strat) as LiteralStrategy).clone()
	}
	if *strat is BasenameLiteralStrategy {
		return ((*strat) as BasenameLiteralStrategy).clone()
	}
	if *strat is ExtensionStrategy {
		return ((*strat) as ExtensionStrategy).clone()
	}
	if *strat is PrefixStrategy {
		return ((*strat) as PrefixStrategy).clone()
	}
	if *strat is SuffixStrategy {
		return ((*strat) as SuffixStrategy).clone()
	}
	if *strat is RequiredExtensionStrategy {
		return ((*strat) as RequiredExtensionStrategy).clone()
	}
	return ((*strat) as RegexSetStrategy).clone()
}

/// Create a new `GlobSetBuilder`. A `GlobSetBuilder` can be used to add
/// new patterns. Once all patterns have been added, `build` should be
/// called to produce a `GlobSet`, which can then be used for matching.
pub fn GlobSet.builder() GlobSetBuilder {
	return GlobSetBuilder.new()
}

/// Create an empty `GlobSet`. An empty set matches nothing.
pub fn GlobSet.empty() GlobSet {
	return GlobSet{
		len_:   0
		strats: []GlobSetMatchStrategy{}
	}
}

/// Returns true if this set is empty, and therefore matches nothing.
pub fn (gs &GlobSet) is_empty() bool {
	return gs.len_ == 0
}

/// Returns the number of globs in this set.
pub fn (gs &GlobSet) len() usize {
	return gs.len_
}

// V-specific: release the allocation owned by an empty set without needing
// sum-type payload destruction. Non-empty sets are released with their owning
// ignore matcher once ownership-aware sum-type drops are available.
pub fn (mut gs GlobSet) free_empty() {
	if gs.len_ != 0 {
		return
	}
	unsafe { gs.strats.free() }
	gs.strats = []GlobSetMatchStrategy{}
}

/// Returns true if any glob in this set matches the path given.
pub fn (gs &GlobSet) is_match(path string) bool {
	candidate := Candidate.new(&path)
	return gs.is_match_candidate(&candidate)
}

/// Returns true if any glob in this set matches the path given.
///
/// This takes a Candidate as input, which can be used to amortize the
/// cost of preparing a path for matching.
pub fn (gs &GlobSet) is_match_candidate[^a](path &Candidate[^a]) bool {
	if gs.is_empty() {
		return false
	}
	for i in 0 .. gs.strats.len {
		if glob_set_strategy_is_match(&gs.strats[i], path) {
			return true
		}
	}
	return false
}

/// Returns true if all globs in this set match the path given.
///
/// This will return true if the set of globs is empty, as in that case all
/// `0` of the globs will match.
///
/// ```
/// mut builder := GlobSetBuilder.new()
/// builder.add(Glob.new('src/*')!)
/// builder.add(Glob.new('**/*.rs')!)
/// set := builder.build()!
///
/// assert set.matches_all('src/foo.rs')
/// assert !set.matches_all('src/bar.c')
/// assert !set.matches_all('test.rs')
/// ```
pub fn (gs &GlobSet) matches_all(path string) bool {
	candidate := Candidate.new(&path)
	return gs.matches_all_candidate(&candidate)
}

/// Returns ture if all globs in this set match the path given.
///
/// This takes a Candidate as input, which can be used to amortize the cost
/// of peparing a path for matching.
///
/// This will return true if the set of globs is empty, as in that case all
/// `0` of the globs will match.
pub fn (gs &GlobSet) matches_all_candidate[^a](path &Candidate[^a]) bool {
	for i in 0 .. gs.strats.len {
		if !glob_set_strategy_is_match(&gs.strats[i], path) {
			return false
		}
	}
	return true
}

/// Returns the sequence number of every glob pattern that matches the
/// given path.
pub fn (gs &GlobSet) matches(path string) []usize {
	candidate := Candidate.new(&path)
	return gs.matches_candidate(&candidate)
}

/// Returns the sequence number of every glob pattern that matches the
/// given path.
///
/// This takes a Candidate as input, which can be used to amortize the
/// cost of preparing a path for matching.
pub fn (gs &GlobSet) matches_candidate[^a](path &Candidate[^a]) []usize {
	mut into := []usize{}
	if gs.is_empty() {
		return into
	}
	gs.matches_candidate_into(path, mut into)
	return into
}

/// Adds the sequence number of every glob pattern that matches the given
/// path to the vec given.
///
/// `into` is cleared before matching begins, and contains the set of
/// sequence numbers (in ascending order) after matching ends. If no globs
/// were matched, then `into` will be empty.
pub fn (gs &GlobSet) matches_into(path string, mut into []usize) {
	candidate := Candidate.new(&path)
	gs.matches_candidate_into(&candidate, mut into)
}

/// Adds the sequence number of every glob pattern that matches the given
/// path to the vec given.
///
/// `into` is cleared before matching begins, and contains the set of
/// sequence numbers (in ascending order) after matching ends. If no globs
/// were matched, then `into` will be empty.
///
/// This takes a Candidate as input, which can be used to amortize the
/// cost of preparing a path for matching.
pub fn (gs &GlobSet) matches_candidate_into[^a](path &Candidate[^a], mut into []usize) {
	into.clear()
	if gs.is_empty() {
		return
	}
	for i in 0 .. gs.strats.len {
		glob_set_strategy_matches_into(&gs.strats[i], path, mut into)
	}
	into.sort()
	dedup_usize(mut into)
}

/// Builds a new matcher from a collection of Glob patterns.
///
/// Once a matcher is built, no new patterns can be added to it.
pub fn GlobSet.new(globs &[]Glob) !GlobSet {
	if globs.len == 0 {
		return GlobSet.empty()
	}
	mut lits := LiteralStrategy.new()
	mut base_lits := BasenameLiteralStrategy.new()
	mut exts := ExtensionStrategy.new()
	mut prefixes := MultiStrategyBuilder.new()
	mut suffixes := MultiStrategyBuilder.new()
	mut required_exts := RequiredExtensionStrategyBuilder.new()
	mut regexes := MultiStrategyBuilder.new()
	for i, glob in globs {
		strategy := match_strategy_new(glob)
		match strategy.kind {
			.literal {
				lits.add(usize(i), strategy.value)
			}
			.basename_literal {
				base_lits.add(usize(i), strategy.value)
			}
			.extension {
				exts.add(usize(i), strategy.value)
			}
			.prefix {
				prefixes.add(usize(i), strategy.value)
			}
			.suffix {
				if strategy.component {
					lits.add(usize(i), strategy.value[1..].to_owned())
				}
				suffixes.add(usize(i), strategy.value)
			}
			.required_extension {
				required_exts.add(usize(i), strategy.value, glob.regex().to_owned())
			}
			.regex {
				regexes.add(usize(i), glob.regex().to_owned())
			}
		}
	}
	mut strats := []GlobSetMatchStrategy{}
	if exts.entries.len > 0 {
		strats << exts
	}
	if base_lits.entries.len > 0 {
		strats << base_lits
	}
	if lits.entries.len > 0 {
		strats << lits
	}
	if !suffixes.is_empty() {
		strats << suffixes.suffix()
	}
	if !prefixes.is_empty() {
		strats << prefixes.prefix()
	}
	if required_exts.entries.len > 0 {
		strats << required_exts.build()!
	}
	if !regexes.is_empty() {
		strats << regexes.regex_set()!
	}
	return GlobSet{
		len_:   usize(globs.len)
		strats: strats
	}
}

/// GlobSetBuilder builds a group of patterns that can be used to
/// simultaneously match a file path.
pub struct GlobSetBuilder implements IClone {
mut:
	pats []Glob
}

/// Create a new `GlobSetBuilder`. A `GlobSetBuilder` can be used to add new
/// patterns. Once all patterns have been added, `build` should be called
/// to produce a `GlobSet`, which can then be used for matching.
pub fn GlobSetBuilder.new() GlobSetBuilder {
	return GlobSetBuilder{
		pats: []Glob{}
	}
}

pub fn (builder &GlobSetBuilder) str() string {
	mut pats := []string{cap: builder.pats.len}
	for pat in builder.pats {
		pats << 'Glob("${pat.str()}")'
	}
	return 'GlobSetBuilder { pats: [${pats.join(", ")}] }'
}

/// Builds a new matcher from all of the glob patterns added so far.
///
/// Once a matcher is built, no new patterns can be added to it.
pub fn (builder &GlobSetBuilder) build() !GlobSet {
	return GlobSet.new(&builder.pats)
}

/// Add a new pattern to this set.
pub fn (mut builder GlobSetBuilder) add(pat Glob) &GlobSetBuilder {
	builder.pats << pat
	return builder
}

/// Escape meta-characters within the given glob pattern.
///
/// The escaping works by surrounding meta-characters with brackets. For
/// example, `*` becomes `[*]`.
///
/// # Example
///
/// ```
/// assert escape('foo*bar') == 'foo[*]bar'
/// assert escape('foo?bar') == 'foo[?]bar'
/// assert escape('foo[bar') == 'foo[[]bar'
/// assert escape('foo]bar') == 'foo[]]bar'
/// assert escape('foo{bar') == 'foo[{]bar'
/// assert escape('foo}bar') == 'foo[}]bar'
/// ```
pub fn escape(s string) string {
	mut escaped := ''
	for ch in s.runes() {
		// note that ! does not need escaping because it is only special
		// inside brackets
		if ch in [`?`, `*`, `[`, `]`, `{`, `}`] {
			escaped += '['
			escaped += ch.str()
			escaped += ']'
		} else {
			escaped += ch.str()
		}
	}
	return escaped
}

fn dedup_usize(mut xs []usize) {
	if xs.len <= 1 {
		return
	}
	mut write := 1
	for read := 1; read < xs.len; read++ {
		if xs[read] != xs[write - 1] {
			xs[write] = xs[read]
			write++
		}
	}
	xs.trim(write)
}
