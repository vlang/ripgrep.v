module ignore

import encoding.utf8.validate
import globset
import os
import regex.meta

/*
The gitignore module provides a way to match globs from a gitignore file
against file paths.

Note that this module implements the specification as described in the
`gitignore` man page from scratch. That is, this module does *not* shell out to
the `git` command line tool.
*/

/// Glob represents a single glob in a gitignore file.
///
/// This is used to report information about the highest precedent glob that
/// matched in one or more gitignore files.
pub struct Glob implements IClone {
mut:
	/// The file path that this glob was extracted from.
	source ?string
	/// The original glob string.
	original_ string
	/// The actual glob string used to convert to a regex.
	actual_ string
	/// Whether this is a whitelisted glob or not.
	is_whitelist_ bool
	/// Whether this glob should only match directories or not.
	is_only_dir_ bool
}

pub struct GitignoreGlobRef[^a] implements IClone {
	/// V-specific wrapper field for the borrowed glob carried by `Match`.
pub:
	glob &^a Glob
}

/// Returns the file path that defined this glob.
pub fn (g &^a Glob) from[^a]() ?&^a string {
	if g.source != none {
		return unsafe { &g.source? }
	}
	return none
}

/// The original glob as it was defined in a gitignore file.
pub fn (g &^a Glob) original[^a]() &^a string {
	return &g.original_
}

/// The actual glob that was compiled to respect gitignore
/// semantics.
pub fn (g &^a Glob) actual[^a]() &^a string {
	return &g.actual_
}

/// Whether this was a whitelisted glob or not.
pub fn (g &Glob) is_whitelist() bool {
	return g.is_whitelist_
}

/// Whether this glob must match a directory or not.
pub fn (g &Glob) is_only_dir() bool {
	return g.is_only_dir_
}

/// Returns true if and only if this glob has a `**/` prefix.
fn (g &Glob) has_doublestar_prefix() bool {
	return g.actual_.starts_with('**/') || g.actual_ == '**'
}

/// Gitignore is a matcher for the globs in one or more gitignore files
/// in the same directory.
pub struct Gitignore implements IClone {
mut:
	root string
	globs []Glob
	set globset.GlobSet
	num_ignores_ u64
	num_whitelists_ u64
}

/// Creates a new gitignore matcher from the gitignore file path given.
///
/// If it's desirable to include multiple gitignore files in a single
/// matcher, or read gitignore globs from a different source, then
/// use `GitignoreBuilder`.
///
/// This always returns a valid matcher, even if it's empty. In particular,
/// a Gitignore file can be partially valid, e.g., when one glob is invalid
/// but the rest aren't.
///
/// Note that I/O errors are ignored. For more granular control over
/// errors, use `GitignoreBuilder`.
pub fn Gitignore.new(gitignore_path string) (Gitignore, bool, IgnoreError) {
	parent := if gitignore_path == '' {
		'/'.to_owned()
	} else if gitignore_is_file_name(gitignore_path) {
		''.to_owned()
	} else {
		os.dir(gitignore_path)
	}
	mut builder := GitignoreBuilder.new(parent)
	mut errs := PartialErrorBuilder{}
	add_has_err, add_err := builder.add(gitignore_path)
	errs.maybe_push_ignore_io(add_has_err, add_err)
	gi, build_has_err, build_err := builder.build()
	if build_has_err {
		errs.push(build_err)
		_, final_err := errs.into_error_option()
		return Gitignore.empty(), true, final_err
	}
	final_has_err, final_err := errs.into_error_option()
	return gi, final_has_err, final_err
}

/// Creates a new gitignore matcher from the global ignore file, if one
/// exists.
///
/// The global config file path is specified by git's `core.excludesFile`
/// config option.
///
/// Git's config file location is `$HOME/.gitconfig`. If `$HOME/.gitconfig`
/// does not exist or does not specify `core.excludesFile`, then
/// `$XDG_CONFIG_HOME/git/ignore` is read. If `$XDG_CONFIG_HOME` is not
/// set or is empty, then `$HOME/.config/git/ignore` is used instead.
pub fn Gitignore.global() (Gitignore, bool, IgnoreError) {
	cwd := os.getwd()
	builder := GitignoreBuilder.new(cwd)
	return builder.build_global()
}

/// Creates a new empty gitignore matcher that never matches anything.
///
/// Its path is empty.
pub fn Gitignore.empty() Gitignore {
	return Gitignore{
		root:             ''.to_owned()
		globs:            []Glob{}
		set:              globset.GlobSet.empty()
		num_ignores_:     0
		num_whitelists_:  0
	}
}

/// Returns the directory containing this gitignore matcher.
///
/// All matches are done relative to this path.
pub fn (gi &^a Gitignore) path[^a]() &^a string {
	return &gi.root
}

/// Returns true if and only if this gitignore has zero globs, and
/// therefore never matches any file path.
pub fn (gi &Gitignore) is_empty() bool {
	return gi.set.is_empty()
}

// V-specific: empty matchers are created for every traversed directory and
// own their root/set storage even though they contain no rules.
fn (mut gi Gitignore) free_empty() {
	if !gi.is_empty() {
		return
	}
	unsafe {
		gi.root.free()
		gi.globs.free()
	}
	gi.set.free_empty()
	gi.root = ''
	gi.globs = []Glob{}
}

/// Returns the total number of globs, which should be equivalent to
/// `num_ignores + num_whitelists`.
pub fn (gi &Gitignore) len() usize {
	return gi.set.len()
}

/// Returns the total number of ignore globs.
pub fn (gi &Gitignore) num_ignores() u64 {
	return gi.num_ignores_
}

/// Returns the total number of whitelisted globs.
pub fn (gi &Gitignore) num_whitelists() u64 {
	return gi.num_whitelists_
}

/// Returns whether the given path (file or directory) matched a pattern in
/// this gitignore matcher.
///
/// `is_dir` should be true if the path refers to a directory and false
/// otherwise.
///
/// The given path is matched relative to the path given when building
/// the matcher. Specifically, before matching `path`, its prefix (as
/// determined by a common suffix of the directory containing this
/// gitignore) is stripped. If there is no common suffix/prefix overlap,
/// then `path` is assumed to be relative to this matcher.
pub fn (gi &^a Gitignore) matched[^a](path string, is_dir bool) Match[GitignoreGlobRef[^a]] {
	if gi.is_empty() {
		return Match[GitignoreGlobRef[^a]]{}
	}
	mut matches := []usize{}
	return gi.matched_with_scratch(&path, is_dir, mut matches)
}

fn (gi &^a Gitignore) matched_with_scratch[^a](path &string, is_dir bool, mut matches []usize) Match[GitignoreGlobRef[^a]] {
	if gi.is_empty() {
		return Match[GitignoreGlobRef[^a]]{}
	}
	return gi.matched_stripped_with_scratch(gi.strip(path), is_dir, mut matches)
}

/// Returns whether the given path (file or directory, and expected to be
/// under the root) or any of its parent directories (up to the root)
/// matched a pattern in this gitignore matcher.
///
/// NOTE: This method is more expensive than walking the directory hierarchy
/// top-to-bottom and matching the entries. But, is easier to use in cases
/// when a list of paths are available without a hierarchy.
///
/// `is_dir` should be true if the path refers to a directory and false
/// otherwise.
///
/// The given path is matched relative to the path given when building
/// the matcher. Specifically, before matching `path`, its prefix (as
/// determined by a common suffix of the directory containing this
/// gitignore) is stripped. If there is no common suffix/prefix overlap,
/// then `path` is assumed to be relative to this matcher.
///
/// # Panics
///
/// This method panics if the given file path is not under the root path
/// of this matcher.
pub fn (gi &^a Gitignore) matched_path_or_any_parents[^a](path string, is_dir bool) Match[GitignoreGlobRef[^a]] {
	if gi.is_empty() {
		return Match[GitignoreGlobRef[^a]]{}
	}
	mut stripped := gi.strip(&path)
	assert !stripped.starts_with('/'), 'path is expected to be under the root'
	matched := gi.matched_stripped(stripped.clone(), is_dir)
	if !matched.is_none() {
		return matched
	}
	// walk up
	for {
		parent := os.dir(stripped.clone())
		if parent == '' || parent == '.' || parent == stripped {
			break
		}
		matched := gi.matched_stripped(parent.clone(), true)
		if !matched.is_none() {
			return matched
		}
		stripped = parent
	}
	return Match[GitignoreGlobRef[^a]]{}
}

/// Like matched, but takes a path that has already been stripped.
fn (gi &^a Gitignore) matched_stripped[^a](path string, is_dir bool) Match[GitignoreGlobRef[^a]] {
	if gi.is_empty() {
		return Match[GitignoreGlobRef[^a]]{}
	}
	mut matches := []usize{}
	return gi.matched_stripped_with_scratch(path, is_dir, mut matches)
}

fn (gi &^a Gitignore) matched_stripped_with_scratch[^a](path string, is_dir bool, mut matches []usize) Match[GitignoreGlobRef[^a]] {
	if gi.is_empty() {
		return Match[GitignoreGlobRef[^a]]{}
	}
	candidate_path := gitignore_path_for_matching_if_needed(path)
	candidate := globset.Candidate.new(&candidate_path)
	gi.set.matches_candidate_into(&candidate, mut matches)
	for match_index := matches.len; match_index > 0; match_index-- {
		i := int(matches[match_index - 1])
		glob := &gi.globs[i]
		if glob.is_only_dir() && !is_dir {
			continue
		}
		return if glob.is_whitelist() {
			Match[GitignoreGlobRef[^a]]{
				kind:      .whitelist
				value:     GitignoreGlobRef[^a]{
					glob: glob
				}
				has_value: true
			}
		} else {
			Match[GitignoreGlobRef[^a]]{
				kind:      .ignore
				value:     GitignoreGlobRef[^a]{
					glob: glob
				}
				has_value: true
			}
		}
	}
	return Match[GitignoreGlobRef[^a]]{}
}

// V-specific: string substrings do not carry a distinct borrow lifetime, so
// this returns independent owned storage while borrowing `path`.
/// Strips the given path such that it's suitable for matching with this
/// gitignore matcher.
fn (gi &Gitignore) strip(path &string) string {
	mut stripped := (*path).to_owned()
	// A leading ./ is completely superfluous. We also strip it from
	// our gitignore root path, so we need to strip it from our candidate
	// path too.
	if stripped.starts_with('./') {
		stripped = stripped[2..].to_owned()
	}
	// Strip any common prefix between the candidate path and the root
	// of the gitignore, to make sure we get relative matching right.
	// BUT, a file name might not have any directory components to it,
	// in which case, we don't want to accidentally strip any part of the
	// file name.
	//
	// As an additional special case, if the root is just `.`, then we
	// shouldn't try to strip anything, e.g., when path begins with a `.`.
	if gi.root != '.' && !gitignore_is_file_name(stripped.clone()) {
		if relative := gitignore_strip_prefix_opt(gi.root.clone(), stripped.clone()) {
			stripped = relative
			// If we're left with a leading slash, get rid of it.
			if stripped.starts_with('/') {
				stripped = stripped[1..].to_owned()
			}
		}
	}
	$if !windows {
		return stripped
	}
	return gitignore_path_for_matching(stripped)
}

/// Builds a matcher for a single set of globs from a .gitignore file.
pub struct GitignoreBuilder implements IClone {
	builder globset.GlobSetBuilder
	root string
mut:
	globs                []Glob
	case_insensitive_    bool
	allow_unclosed_class_ bool
}

/// Create a new builder for a gitignore file.
///
/// The path given should be the path at which the globs for this gitignore
/// file should be matched. Note that paths are always matched relative
/// to the root path given here. Generally, the root path should correspond
/// to the *directory* containing a `.gitignore` file.
pub fn GitignoreBuilder.new(root string) GitignoreBuilder {
	mut path := gitignore_path_for_matching(root)
	if stripped := gitignore_strip_prefix_opt('./', path.clone()) {
		path = stripped
	}
	return GitignoreBuilder{
		builder:              globset.GlobSetBuilder.new()
		root:                 path.to_owned()
		globs:                []Glob{}
		case_insensitive_:    false
		allow_unclosed_class_: true
	}
}

/// Builds a new matcher from the globs added so far.
///
/// Once a matcher is built, no new globs can be added to it.
pub fn (builder &GitignoreBuilder) build() (Gitignore, bool, IgnoreError) {
	mut nignore := u64(0)
	mut nwhite := u64(0)
	for glob in builder.globs {
		if glob.is_whitelist() {
			nwhite++
		} else {
			nignore++
		}
	}
	set := builder.builder.build() or { return Gitignore.empty(), true, glob_error(none, err.msg()) }
	return Gitignore{
		root:             builder.root.clone()
		globs:            builder.globs.clone()
		set:              set
		num_ignores_:     nignore
		num_whitelists_:  nwhite
	}, false, IgnoreError{}
}

/// Build a global gitignore matcher using the configuration in this
/// builder.
///
/// This consumes ownership of the builder unlike `build` because it
/// must mutate the builder to add the global gitignore globs.
///
/// Note that this ignores the path given to this builder's constructor
/// and instead derives the path automatically from git's global
/// configuration.
pub fn (builder GitignoreBuilder) build_global() (Gitignore, bool, IgnoreError) {
	mut owned := builder
	path := gitconfig_excludes_path() or { return Gitignore.empty(), false, IgnoreError{} }
	if !os.is_file(path.clone()) {
		return Gitignore.empty(), false, IgnoreError{}
	}
	mut errs := PartialErrorBuilder{}
	add_has_err, add_err := owned.add(path)
	errs.maybe_push_ignore_io(add_has_err, add_err)
	gi, build_has_err, build_err := owned.build()
	if build_has_err {
		errs.push(build_err)
		_, final_err := errs.into_error_option()
		return Gitignore.empty(), true, final_err
	}
	final_has_err, final_err := errs.into_error_option()
	return gi, final_has_err, final_err
}

/// Add each glob from the file path given.
///
/// The file given should be formatted as a `gitignore` file.
///
/// Note that partial errors can be returned. For example, if there was
/// a problem adding one glob, an error for that will be returned, but
/// all other valid globs will still be added.
pub fn (mut builder GitignoreBuilder) add(path string) (bool, IgnoreError) {
	contents := os.read_file(path.clone()) or {
		return true, io_error(err).with_path(path.clone())
	}
	mut errs := PartialErrorBuilder{}
	lines := contents.split('\n')
	for i, raw_line in lines {
		lineno := u64(i + 1)
		mut line := raw_line.trim_right('\r')
		if i == 0 && line.len >= 3 {
			// Match Git's handling of .gitignore files that begin with the Unicode BOM
			bytes := line.bytes()
			if bytes[0] == u8(0xEF) && bytes[1] == u8(0xBB) && bytes[2] == u8(0xBF) {
				line = line[3..]
			}
		}
		add_has_err, add_err := builder.add_line(path.clone(), line)
		if add_has_err {
			errs.push(add_err.tagged(path.clone(), lineno))
		}
	}
	return errs.into_error_option()
}

/// Add each glob line from the string given.
///
/// If this string came from a particular `gitignore` file, then its path
/// should be provided here.
///
/// The string given should be formatted as a `gitignore` file.
//
// V-specific: this test helper remains in a normal module file because direct
// ownership-mode compilation of one `_test.v` file does not load helpers from
// sibling `_test.v` files, and both gitignore test files use it.
fn (mut builder GitignoreBuilder) add_str(from ?string, gitignore string) (bool, IgnoreError) {
	for raw_line in gitignore.split('\n') {
		line := raw_line.trim_right('\r')
		add_has_err, add_err := builder.add_line(clone_optional_string(from), line)
		if add_has_err {
			return true, add_err
		}
	}
	return false, IgnoreError{}
}

/// Add a line from a gitignore file to this builder.
///
/// If this line came from a particular `gitignore` file, then its path
/// should be provided here.
///
/// If the line could not be parsed as a glob, then an error is returned.
pub fn (mut builder GitignoreBuilder) add_line(from ?string, line string) (bool, IgnoreError) {
	mut current := line
	if current.starts_with('#') {
		return false, IgnoreError{}
	}
	if !current.ends_with('\\ ') {
		current = current.trim_space_right()
	}
	if current == '' {
		return false, IgnoreError{}
	}
	mut owned_from := ?string(none)
	if source := from {
		owned_from = source.to_owned()
	}
	mut glob := Glob{
		source:           owned_from
		original_:        current.to_owned()
		actual_:          ''.to_owned()
		is_whitelist_:    false
		is_only_dir_:     false
	}
	mut is_absolute := false
	if current.starts_with('\\!') || current.starts_with('\\#') {
		current = current[1..]
		is_absolute = current.len > 0 && current[0] == `/`
	} else {
		if current.starts_with('!') {
			glob.is_whitelist_ = true
			current = current[1..]
		}
		if current.starts_with('/') {
			// `man gitignore` says that if a glob starts with a slash,
			// then the glob can only match the beginning of a path
			// (relative to the location of gitignore). We achieve this by
			// simply banning wildcards from matching /.
			current = current[1..]
			is_absolute = true
		}
	}
	// If it ends with a slash, then this should only match directories,
	// but the slash should otherwise not be used while globbing.
	if current.len > 0 && current[current.len - 1] == `/` {
		glob.is_only_dir_ = true
		current = current[..current.len - 1]
		// If the slash was escaped, then remove the escape.
		// See: https://github.com/BurntSushi/ripgrep/issues/2236
		if current.len > 0 && current[current.len - 1] == `\\` {
			current = current[..current.len - 1]
		}
	}
	glob.actual_ = current.to_owned()
	// If there is a literal slash, then this is a glob that must match the
	// entire path name. Otherwise, we should let it match anywhere, so use
	// a **/ prefix.
	if !is_absolute && !current.contains('/') {
		// ... but only if we don't already have a **/ prefix.
		if !glob.has_doublestar_prefix() {
			glob.actual_ = '**/${glob.actual_}'
		}
	}
	// If the glob ends with `/**`, then we should only match everything
	// inside a directory, but not the directory itself. Standard globs
	// will match the directory. So we add `/*` to force the issue.
	if glob.actual_.ends_with('/**') {
		glob.actual_ += '/*'
	}
	parse_glob := glob.actual_.clone()
	mut glob_builder := globset.GlobBuilder.new(&parse_glob)
	glob_builder.literal_separator(true)
	glob_builder.case_insensitive(builder.case_insensitive_)
	glob_builder.backslash_escape(true)
	glob_builder.allow_unclosed_class(builder.allow_unclosed_class_)
	parsed := glob_builder.build() or {
		if err is globset.GlobError {
			return true, glob_error(glob.original_.clone(), (*err.kind()).str())
		}
		return true, glob_error(glob.original_.clone(), err.msg())
	}
	builder.builder.add(parsed.clone())
	builder.globs << glob
	return false, IgnoreError{}
}

/// Toggle whether the globs should be matched case insensitively or not.
///
/// When this option is changed, only globs added after the change will be
/// affected.
///
/// This is disabled by default.
pub fn (mut builder GitignoreBuilder) case_insensitive(yes bool) (bool, IgnoreError) {
	// TODO: This should not return a `Result`. Fix this in the next semver
	// release.
	builder.case_insensitive_ = yes
	return false, IgnoreError{}
}

/// Toggle whether unclosed character classes are allowed. When allowed,
/// a `[` without a matching `]` is treated literally instead of resulting
/// in a parse error.
///
/// For example, if this is set then the glob `[abc` will be treated as the
/// literal string `[abc` instead of returning an error.
///
/// By default, this is true in order to match established `gitignore`
/// semantics. Generally speaking, enabling this leads to worse failure
/// modes since the glob parser becomes more permissive. You might want to
/// enable this when compatibility (e.g., with POSIX glob implementations)
/// is more important than good error messages.
pub fn (mut builder GitignoreBuilder) allow_unclosed_class(yes bool) &GitignoreBuilder {
	builder.allow_unclosed_class_ = yes
	return builder
}

/// Return the file path of the current environment's global gitignore file.
///
/// Note that the file path returned may not exist.
pub fn gitconfig_excludes_path() ?string {
	// git supports $HOME/.gitconfig and $XDG_CONFIG_HOME/git/config. Notably,
	// both can be active at the same time, where $HOME/.gitconfig takes
	// precedent. So if $HOME/.gitconfig defines a `core.excludesFile`, then
	// we're done.
	if contents := gitconfig_home_contents() {
		if path := parse_excludes_file(contents) {
			return path
		}
	}
	if contents := gitconfig_xdg_contents() {
		if path := parse_excludes_file(contents) {
			return path
		}
	}
	return excludes_file_default()
}

/// Returns the file contents of git's global config file, if one exists, in
/// the user's home directory.
fn gitconfig_home_contents() ?[]u8 {
	home := home_dir() or { return none }
	path := os.join_path(home, '.gitconfig')
	if !os.is_file(path) {
		return none
	}
	return os.read_file(path) or { return none }.bytes()
}

/// Returns the file contents of git's global config file, if one exists, in
/// the user's XDG_CONFIG_HOME directory.
fn gitconfig_xdg_contents() ?[]u8 {
	mut base := os.getenv('XDG_CONFIG_HOME')
	if base == '' {
		base = os.join_path(home_dir() or { return none }, '.config')
	}
	path := os.join_path(base, 'git', 'config')
	if !os.is_file(path) {
		return none
	}
	return os.read_file(path) or { return none }.bytes()
}

/// Returns the default file path for a global .gitignore file.
///
/// Specifically, this respects XDG_CONFIG_HOME.
fn excludes_file_default() ?string {
	mut base := os.getenv('XDG_CONFIG_HOME')
	if base == '' {
		base = os.join_path(home_dir() or { return none }, '.config')
	}
	return os.join_path(base, 'git', 'ignore')
}

/// Extract git's `core.excludesfile` config setting from the raw file contents
/// given.
fn parse_excludes_file(data []u8) ?string {
	// N.B. This is the lazy approach, and isn't technically correct, but
	// probably works in more circumstances. I guess we would ideally have
	// a full INI parser. Yuck.
	re := meta.compile(r'(?im-u)^\s*excludesfile\s*=\s*"?\s*(\S+?)\s*"?\s*$') or {
		panic(err)
	}
	// We don't care about amortizing allocs here I think. This should only
	// be called ~once per traversal or so? (Although it's not guaranteed...)
	matched := re.find(data.bytestr()) or { return none }
	candidate := matched.get(1) or { return none }
	if !validate.utf8_string(candidate.clone()) {
		return none
	}
	return expand_tilde(candidate)
}

/// Expands ~ in file paths to the value of $HOME.
fn expand_tilde(path string) string {
	home := home_dir() or { return path.to_owned() }
	return path.replace('~', home)
}

/// Returns the location of the user's home directory.
fn home_dir() ?string {
	// We're fine with using os.home_dir for now. Its bugs are, IMO,
	// pretty minor corner cases.
	home := os.home_dir()
	if home == '' {
		return none
	}
	return home
}

fn gitignore_strip_prefix_opt(prefix string, path string) ?string {
	if prefix == '' {
		return path.to_owned()
	}
	if prefix.len > path.len || !path.starts_with(prefix) {
		return none
	}
	if prefix.len < path.len && !prefix.ends_with('/') && path[prefix.len] != `/` {
		return none
	}
	// V-specific: Rust returns a borrowed `&Path` here. V strings carry their
	// slice descriptor by value, so keep the returned descriptor alive with
	// owned storage after this helper's by-value `path` parameter is dropped.
	return path[prefix.len..].to_owned()
}

fn gitignore_is_file_name(path string) bool {
	return !gitignore_path_for_matching(path.clone()).contains('/')
}

fn gitignore_path_for_matching(path string) string {
	if path == '' {
		return ''
	}
	mut normalized := normalize_path(path)
	if os.path_separator.str() != '/' {
		normalized = normalized.replace(os.path_separator.str(), '/')
	}
	return normalized
}

fn gitignore_path_for_matching_if_needed(path string) string {
	$if !windows {
		if !gitignore_path_needs_normalization(path.clone()) {
			return path
		}
	}
	return gitignore_path_for_matching(path)
}

fn gitignore_path_needs_normalization(path string) bool {
	if path == '' {
		return false
	}
	mut component_start := 0
	for i := 0; i <= path.len; i++ {
		if i < path.len && path[i] != `/` {
			continue
		}
		if i == component_start {
			if i == 0 {
				component_start = i + 1
				continue
			}
			return true
		}
		component_len := i - component_start
		if component_len == 1 && path[component_start] == `.` {
			return true
		}
		if component_len == 2 && path[component_start] == `.` && path[component_start + 1] == `.` {
			return true
		}
		component_start = i + 1
	}
	return false
}

fn gitignore_glob_match_runes(pattern []rune, pi int, text []rune, ti int) bool {
	if pi >= pattern.len {
		return ti >= text.len
	}
	if pattern[pi] == `*` {
		if pi + 1 < pattern.len && pattern[pi + 1] == `*` {
			mut next_pi := pi + 2
			for next_pi < pattern.len && pattern[next_pi] == `*` {
				next_pi++
			}
			if next_pi < pattern.len && pattern[next_pi] == `/` {
				if gitignore_glob_match_runes(pattern, next_pi + 1, text, ti) {
					return true
				}
				for j := ti; j < text.len; j++ {
					if text[j] == `/` && gitignore_glob_match_runes(pattern, next_pi + 1, text, j + 1) {
						return true
					}
				}
				return false
			}
			for j := ti; j <= text.len; j++ {
				if gitignore_glob_match_runes(pattern, next_pi, text, j) {
					return true
				}
			}
			return false
		}
		for j := ti; j <= text.len; j++ {
			if gitignore_glob_match_runes(pattern, pi + 1, text, j) {
				return true
			}
			if j >= text.len || text[j] == `/` {
				break
			}
		}
		return false
	}
	if ti >= text.len {
		return false
	}
	if pattern[pi] == `?` {
		return text[ti] != `/` && gitignore_glob_match_runes(pattern, pi + 1, text, ti + 1)
	}
	if pattern[pi] == `[` {
		end := gitignore_find_class_end(pattern, pi)
		if end > pi {
			matches := gitignore_char_class_matches(pattern[pi + 1..end], text[ti])
			return matches && text[ti] != `/` && gitignore_glob_match_runes(pattern, end + 1, text,
				ti + 1)
		}
	}
	if pattern[pi] == `\\` && pi + 1 < pattern.len {
		return pattern[pi + 1] == text[ti] && gitignore_glob_match_runes(pattern, pi + 2, text,
			ti + 1)
	}
	return pattern[pi] == text[ti] && gitignore_glob_match_runes(pattern, pi + 1, text, ti + 1)
}

fn gitignore_find_class_end(pattern []rune, start int) int {
	mut i := start + 1
	mut escaped := false
	for i < pattern.len {
		if escaped {
			escaped = false
			i++
			continue
		}
		if pattern[i] == `\\` {
			escaped = true
			i++
			continue
		}
		if pattern[i] == `]` && i > start + 1 {
			return i
		}
		i++
	}
	return -1
}

fn gitignore_char_class_matches(class []rune, ch rune) bool {
	if class.len == 0 {
		return false
	}
	mut negate := false
	mut i := 0
	if class[0] == `!` || class[0] == `^` {
		negate = true
		i++
	}
	mut matched := false
	for i < class.len {
		mut current := class[i]
		if current == `\\` && i + 1 < class.len {
			i++
			current = class[i]
		}
		if i + 2 < class.len && class[i + 1] == `-` && class[i + 2] != `]` {
			mut end := class[i + 2]
			if end == `\\` && i + 3 < class.len {
				end = class[i + 3]
				i++
			}
			if current <= ch && ch <= end {
				matched = true
			}
			i += 3
			continue
		}
		if current == ch {
			matched = true
		}
		i++
	}
	return if negate { !matched } else { matched }
}
