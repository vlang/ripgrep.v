module ignore

import os

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
pub:
	// The file path that this glob was extracted from.
	from_ ?string
	// The original glob string.
	original string
	// The actual glob string used to convert to a regex.
	actual string
	// Whether this is a whitelisted glob or not.
	is_whitelist_ bool
	// Whether this glob should only match directories or not.
	is_only_dir_ bool
	// V-specific helper field for the rooted `/foo` gitignore semantics.
	is_absolute bool
	// V-specific helper field because this port does not use `GlobSetBuilder`.
	case_insensitive bool
}

pub struct GitignoreGlobRef[^a] implements IClone {
	glob &^a Glob
}

/// Returns the file path that defined this glob.
pub fn (g Glob) from() ?string {
	return g.from_
}

/// Whether this was a whitelisted glob or not.
pub fn (g Glob) is_whitelist() bool {
	return g.is_whitelist_
}

/// Whether this glob must match a directory or not.
pub fn (g Glob) is_only_dir() bool {
	return g.is_only_dir_
}

/// Returns true if and only if this glob has a `**/` prefix.
fn (g Glob) has_doublestar_prefix() bool {
	return g.actual.starts_with('**/') || g.actual == '**'
}

/// Gitignore is a matcher for the globs in one or more gitignore files
/// in the same directory.
pub struct Gitignore implements IClone {
pub:
	// The directory containing this gitignore matcher.
	root string
	// The globs in this matcher.
	globs []Glob
	// The total number of ignore globs.
	num_ignores_ u64
	// The total number of whitelisted globs.
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
	parent := os.dir(gitignore_path)
	mut builder := GitignoreBuilder.new(if parent == '' { '/' } else { parent })
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
	mut builder := GitignoreBuilder.new(cwd)
	return builder.build_global()
}

/// Creates a new empty gitignore matcher that never matches anything.
///
/// Its path is empty.
pub fn Gitignore.empty() Gitignore {
	return Gitignore{
		root:             ''.to_owned()
		globs:            []Glob{}
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
pub fn (gi Gitignore) is_empty() bool {
	return gi.globs.len == 0
}

/// Returns the total number of globs, which should be equivalent to
/// `num_ignores + num_whitelists`.
pub fn (gi Gitignore) len() int {
	return gi.globs.len
}

/// Returns the total number of ignore globs.
pub fn (gi Gitignore) num_ignores() u64 {
	return gi.num_ignores_
}

/// Returns the total number of whitelisted globs.
pub fn (gi Gitignore) num_whitelists() u64 {
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
	return gi.matched_stripped(gi.strip(path), is_dir)
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
	mut stripped := gi.strip(path)
	assert !stripped.starts_with('/'), 'path is expected to be under the root'
	matched := gi.matched_stripped(stripped, is_dir)
	if !matched.is_none() {
		return matched
	}
	for {
		parent := os.dir(stripped)
		if parent == '' || parent == '.' || parent == stripped {
			break
		}
		matched := gi.matched_stripped(parent, true)
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
	candidate := gitignore_path_for_matching(path)
	for idx in 0 .. gi.globs.len {
		i := gi.globs.len - 1 - idx
		glob := &gi.globs[i]
		if gitignore_glob_matches(*glob, candidate, is_dir) {
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
	}
	return Match[GitignoreGlobRef[^a]]{}
}

/// Strips the given path such that it's suitable for matching with this
/// gitignore matcher.
fn (gi Gitignore) strip(path string) string {
	mut stripped := path
	if p := gitignore_strip_prefix_opt('./', stripped) {
		stripped = p
	}
	if gi.root != '.' && !gitignore_is_file_name(stripped) {
		if p := gitignore_strip_prefix_opt(gi.root, stripped) {
			stripped = p
			if p2 := gitignore_strip_prefix_opt('/', stripped) {
				stripped = p2
			}
		}
	}
	return gitignore_path_for_matching(stripped)
}

/// Builds a matcher for a single set of globs from a .gitignore file.
pub struct GitignoreBuilder implements IClone {
pub:
	root string
mut:
	globs                []Glob
	case_insensitive_    bool
	allow_unclosed_class bool
}

/// Create a new builder for a gitignore file.
///
/// The path given should be the path at which the globs for this gitignore
/// file should be matched. Note that paths are always matched relative
/// to the root path given here. Generally, the root path should correspond
/// to the *directory* containing a `.gitignore` file.
pub fn GitignoreBuilder.new(root string) GitignoreBuilder {
	mut path := gitignore_path_for_matching(root)
	if stripped := gitignore_strip_prefix_opt('./', path) {
		path = stripped
	}
	return GitignoreBuilder{
		root:                 path.to_owned()
		globs:                []Glob{}
		case_insensitive_:    false
		allow_unclosed_class: true
	}
}

/// Builds a new matcher from the globs added so far.
///
/// Once a matcher is built, no new globs can be added to it.
pub fn (builder GitignoreBuilder) build() (Gitignore, bool, IgnoreError) {
	mut nignore := u64(0)
	mut nwhite := u64(0)
	for glob in builder.globs {
		if glob.is_whitelist() {
			nwhite++
		} else {
			nignore++
		}
	}
	return Gitignore{
		root:             builder.root.clone()
		globs:            builder.globs.clone()
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
pub fn (mut builder GitignoreBuilder) build_global() (Gitignore, bool, IgnoreError) {
	path := gitconfig_excludes_path() or { return Gitignore.empty(), false, IgnoreError{} }
	if !os.is_file(path) {
		return Gitignore.empty(), false, IgnoreError{}
	}
	mut errs := PartialErrorBuilder{}
	add_has_err, add_err := builder.add(path)
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

/// Add each glob from the file path given.
///
/// The file given should be formatted as a `gitignore` file.
///
/// Note that partial errors can be returned. For example, if there was
/// a problem adding one glob, an error for that will be returned, but
/// all other valid globs will still be added.
pub fn (mut builder GitignoreBuilder) add(path string) (bool, IgnoreError) {
	contents := os.read_file(path) or {
		return true, io_error(err).with_path(path)
	}
	mut errs := PartialErrorBuilder{}
	lines := contents.split('\n')
	for i, raw_line in lines {
		lineno := u64(i + 1)
		mut line := raw_line.trim_right('\r')
		if i == 0 && line.len >= 3 {
			bytes := line.bytes()
			if bytes[0] == u8(0xEF) && bytes[1] == u8(0xBB) && bytes[2] == u8(0xBF) {
				line = line[3..]
			}
		}
		add_has_err, add_err := gitignore_builder_add_line(mut builder, path, line)
		if add_has_err {
			errs.push(add_err.with_path(path).with_line_number(lineno))
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
fn (mut builder GitignoreBuilder) add_str(from ?string, gitignore string) (bool, IgnoreError) {
	for raw_line in gitignore.split('\n') {
		line := raw_line.trim_right('\r')
		add_has_err, add_err := gitignore_builder_add_line(mut builder, from, line)
		if add_has_err {
			return true, add_err
		}
	}
	return false, IgnoreError{}
}

// This helper contains the translated `add_line` logic from the Rust
// `GitignoreBuilder` implementation. It is kept as a private helper instead of
// a public method because the current V2 C generator emits conflicting
// signatures for this specific method shape.
fn gitignore_builder_add_line(mut builder GitignoreBuilder, from ?string, line string) (bool, IgnoreError) {
	mut current := line
	if current.starts_with('#') {
		return false, IgnoreError{}
	}
	if !current.ends_with('\\ ') {
		current = current.trim_right(' \t')
	}
	if current == '' {
		return false, IgnoreError{}
	}
	mut glob := Glob{
		from_:            from
		original:         current.to_owned()
		actual:           ''
		is_whitelist_:    false
		is_only_dir_:     false
		is_absolute:      false
		case_insensitive: builder.case_insensitive_
	}
	if current.starts_with('\\!') || current.starts_with('\\#') {
		current = current[1..]
		glob.is_absolute = current.len > 0 && current[0] == `/`
	} else {
		if current.starts_with('!') {
			glob.is_whitelist_ = true
			current = current[1..]
		}
		if current.starts_with('/') {
			current = current[1..]
			glob.is_absolute = true
		}
	}
	if current.len > 0 && current[current.len - 1] == `/` {
		glob.is_only_dir_ = true
		current = current[..current.len - 1]
		if current.len > 0 && current[current.len - 1] == `\\` {
			current = current[..current.len - 1]
		}
	}
	glob.actual = current.to_owned()
	if !glob.is_absolute && !current.contains('/') {
		if !glob.has_doublestar_prefix() {
			glob.actual = '**/${glob.actual}'
		}
	}
	if glob.actual.ends_with('/**') {
		glob.actual += '/*'
	}
	if invalid_glob(glob.actual, builder.allow_unclosed_class) {
		return true, glob_error(glob.original, 'invalid glob')
	}
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
pub fn (mut builder GitignoreBuilder) allow_unclosed_class(yes bool) {
	builder.allow_unclosed_class = yes
}

/// Return the file path of the current environment's global gitignore file.
///
/// Note that the file path returned may not exist.
pub fn gitconfig_excludes_path() ?string {
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
		home := home_dir() or { return none }
		base = os.join_path(home, '.config')
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
		home := home_dir() or { return none }
		base = os.join_path(home, '.config')
	}
	return os.join_path(base, 'git', 'ignore')
}

/// Extract git's `core.excludesfile` config setting from the raw file contents
/// given.
fn parse_excludes_file(data []u8) ?string {
	for raw_line in data.bytestr().split('\n') {
		line := raw_line.trim_right('\r').trim_space()
		if line == '' {
			continue
		}
		lower := line.to_lower()
		if !lower.starts_with('excludesfile') {
			continue
		}
		mut rest := line['excludesfile'.len..].trim_space()
		if !rest.starts_with('=') {
			continue
		}
		rest = rest[1..].trim_space()
		if rest.starts_with('"') {
			if rest.len < 2 || !rest.ends_with('"') {
				continue
			}
			rest = rest[1..rest.len - 1].trim_space()
		}
		if rest == '' || rest.contains(' ') || rest.contains('\t') {
			continue
		}
		return expand_tilde(rest)
	}
	return none
}

/// Expands ~ in file paths to the value of $HOME.
fn expand_tilde(path string) string {
	home := home_dir() or { return path.to_owned() }
	return path.replace('~', home)
}

/// Returns the location of the user's home directory.
fn home_dir() ?string {
	home := os.home_dir()
	if home == '' {
		return none
	}
	return home
}

fn invalid_glob(glob string, allow_unclosed_class bool) bool {
	if glob.contains('{') || glob.contains('}') {
		return true
	}
	if !allow_unclosed_class && has_unclosed_class(glob) {
		return true
	}
	return false
}

fn has_unclosed_class(pattern string) bool {
	mut escaped := false
	mut in_class := false
	for ch in pattern {
		if escaped {
			escaped = false
			continue
		}
		if ch == `\\` {
			escaped = true
			continue
		}
		if ch == `[` && !in_class {
			in_class = true
			continue
		}
		if ch == `]` && in_class {
			in_class = false
		}
	}
	return in_class
}

fn gitignore_strip_prefix_opt(prefix string, path string) ?string {
	if prefix.len > path.len || !path.starts_with(prefix) {
		return none
	}
	return path[prefix.len..]
}

fn gitignore_is_file_name(path string) bool {
	return !gitignore_path_for_matching(path).contains('/')
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

fn gitignore_glob_matches(glob Glob, path string, is_dir bool) bool {
	if glob.is_only_dir() && !is_dir {
		return false
	}
	mut candidate := gitignore_path_for_matching(path)
	mut actual := glob.actual
	if glob.case_insensitive {
		candidate = candidate.to_lower()
		actual = actual.to_lower()
	}
	return gitignore_glob_match_runes(actual.runes(), 0, candidate.runes(), 0)
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
			return matches && text[ti] != `/` && gitignore_glob_match_runes(pattern, end + 1, text, ti + 1)
		}
	}
	if pattern[pi] == `\\` && pi + 1 < pattern.len {
		return pattern[pi + 1] == text[ti] && gitignore_glob_match_runes(pattern, pi + 2, text, ti + 1)
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
