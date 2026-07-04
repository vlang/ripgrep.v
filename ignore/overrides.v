module ignore

/*
The overrides module provides a way to specify a set of override globs.

This provides functionality similar to `--include` or `--exclude` in command
line tools.
*/

/// Glob represents a single glob in an override matcher.
///
/// This is used to report information about the highest precedent glob
/// that matched.
///
/// Note that not all matches necessarily correspond to a specific glob. For
/// example, if there are one or more whitelist globs and a file path doesn't
/// match any glob in the set, then the file path is considered to be ignored.
///
/// The lifetime `^a` refers to the lifetime of the matcher that produced
/// this glob.
pub struct OverrideGlob[^a] implements IClone {
	kind OverrideGlobInner
	glob ?GitignoreGlobRef[^a]
}

enum OverrideGlobInner {
	unmatched_ignore
	matched
}

fn OverrideGlob.unmatched[^a]() OverrideGlob[^a] {
	return OverrideGlob[^a]{
		kind: .unmatched_ignore
	}
}

fn OverrideGlob.matched[^a](glob GitignoreGlobRef[^a]) OverrideGlob[^a] {
	return OverrideGlob[^a]{
		kind: .matched
		glob: glob
	}
}

/// Manages a set of overrides provided explicitly by the end user.
pub struct Override implements IClone {
	matcher Gitignore
}

/// Returns an empty matcher that never matches any file path.
pub fn Override.empty() Override {
	return Override{
		matcher: Gitignore.empty()
	}
}

/// Returns the directory of this override set.
///
/// All matches are done relative to this path.
pub fn (o &^a Override) path[^a]() &^a string {
	return o.matcher.path()
}

/// Returns true if and only if this matcher is empty.
///
/// When a matcher is empty, it will never match any file path.
pub fn (o Override) is_empty() bool {
	return o.matcher.is_empty()
}

/// Returns the total number of ignore globs.
pub fn (o Override) num_ignores() u64 {
	return o.matcher.num_whitelists()
}

/// Returns the total number of whitelisted globs.
pub fn (o Override) num_whitelists() u64 {
	return o.matcher.num_ignores()
}

/// Returns whether the given file path matched a pattern in this override
/// matcher.
///
/// `is_dir` should be true if the path refers to a directory and false
/// otherwise.
///
/// If there are no overrides, then this always returns `Match::None`.
///
/// If there is at least one whitelist override and `is_dir` is false, then
/// this never returns `Match::None`, since non-matches are interpreted as
/// ignored.
///
/// The given path is matched to the globs relative to the path given
/// when building the override matcher. Specifically, before matching
/// `path`, its prefix (as determined by a common suffix of the directory
/// given) is stripped. If there is no common suffix/prefix overlap, then
/// `path` is assumed to reside in the same directory as the root path for
/// this set of overrides.
pub fn (o &^a Override) matched[^a](path string, is_dir bool) Match[OverrideGlob[^a]] {
	if o.is_empty() {
		return Match[OverrideGlob[^a]]{}
	}
	mat := o.matcher.matched(path, is_dir)
	if mat.is_none() && o.num_whitelists() > 0 && !is_dir {
		return Match[OverrideGlob[^a]]{
			kind:      .ignore
			value:     OverrideGlob.unmatched()
			has_value: true
		}
	}
	if giglob := mat.inner() {
		if mat.is_ignore() {
			return Match[OverrideGlob[^a]]{
				kind:      .whitelist
				value:     OverrideGlob.matched(giglob)
				has_value: true
			}
		} else if mat.is_whitelist() {
			return Match[OverrideGlob[^a]]{
				kind:      .ignore
				value:     OverrideGlob.matched(giglob)
				has_value: true
			}
		}
	}
	return Match[OverrideGlob[^a]]{}
}

/// Builds a matcher for a set of glob overrides.
pub struct OverrideBuilder implements IClone {
mut:
	builder GitignoreBuilder
}

/// Create a new override builder.
///
/// Matching is done relative to the directory path provided.
pub fn OverrideBuilder.new(path string) OverrideBuilder {
	mut builder := GitignoreBuilder.new(path)
	builder.allow_unclosed_class(false)
	return OverrideBuilder{
		builder: builder
	}
}

/// Builds a new override matcher from the globs added so far.
///
/// Once a matcher is built, no new globs can be added to it.
pub fn (builder OverrideBuilder) build() (Override, bool, IgnoreError) {
	gi, has_err, err := builder.builder.build()
	if has_err {
		return Override.empty(), true, err
	}
	return Override{
		matcher: gi
	}, false, IgnoreError{}
}

/// Add a glob to the set of overrides.
///
/// Globs provided here have precisely the same semantics as a single
/// line in a `gitignore` file, where the meaning of `!` is inverted:
/// namely, `!` at the beginning of a glob will ignore a file. Without `!`,
/// all matches of the glob provided are treated as whitelist matches.
pub fn (mut builder OverrideBuilder) add(glob string) (bool, IgnoreError) {
	return gitignore_builder_add_line(mut builder.builder, none_string(), glob)
}

/// Toggle whether the globs should be matched case insensitively or not.
///
/// When this option is changed, only globs added after the change will be
/// affected.
///
/// This is disabled by default.
pub fn (mut builder OverrideBuilder) case_insensitive(yes bool) (bool, IgnoreError) {
	return builder.builder.case_insensitive(yes)
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
///
/// This default is different from the default for `Gitignore`. Namely,
/// `Gitignore` is intended to match git's behavior as-is. But this
/// abstraction for "override" globs does not necessarily conform to any
/// other known specification and instead prioritizes better error
/// messages.
pub fn (mut builder OverrideBuilder) allow_unclosed_class(yes bool) &OverrideBuilder {
	builder.builder.allow_unclosed_class(yes)
	return builder
}
