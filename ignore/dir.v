module ignore

import os

const empty_ignore_string = ''

// This module provides a data structure, `Ignore`, that connects "directory
// traversal" with "ignore matchers." Specifically, it knows about gitignore
// semantics and precedence, and is organized based on directory hierarchy.
// Namely, every matcher logically corresponds to ignore rules from a single
// directory, and points to the matcher for its corresponding parent directory.
// In this sense, `Ignore` is a *persistent* data structure.
//
// This design was specifically chosen to make it possible to use this data
// structure in a parallel directory iterator.
//
// My initial intention was to expose this module as part of this crate's
// public API, but I think the data structure's public API is too complicated
// with non-obvious failure modes. Alas, such things haven't been documented
// well.

/// IgnoreMatch represents information about where a match came from when using
/// the `Ignore` matcher.
pub struct IgnoreMatch[^a] implements IClone {
	kind           IgnoreMatchInner
	override_glob  ?OverrideGlob[^a]
	gitignore_glob ?GitignoreGlobRef[^a]
	types_glob     ?TypesGlob[^a]
}

/// IgnoreMatchInner describes precisely where the match information came from.
/// This is private to allow expansion to more matchers in the future.
enum IgnoreMatchInner {
	override_
	gitignore
	types
	hidden
}

fn IgnoreMatch.overrides[^a](x OverrideGlob[^a]) IgnoreMatch[^a] {
	return IgnoreMatch[^a]{
		kind:          .override_
		override_glob: x
	}
}

fn IgnoreMatch.gitignore[^a](x GitignoreGlobRef[^a]) IgnoreMatch[^a] {
	return IgnoreMatch[^a]{
		kind:           .gitignore
		gitignore_glob: x
	}
}

fn IgnoreMatch.types[^a](x TypesGlob[^a]) IgnoreMatch[^a] {
	return IgnoreMatch[^a]{
		kind:       .types
		types_glob: x
	}
}

fn IgnoreMatch.hidden[^a]() IgnoreMatch[^a] {
	return IgnoreMatch[^a]{
		kind: .hidden
	}
}

fn ignore_match_none[^a]() Match[IgnoreMatch[^a]] {
	return Match[IgnoreMatch[^a]]{}
}

fn ignore_match_ignore_value[^a](value IgnoreMatch[^a]) Match[IgnoreMatch[^a]] {
	return Match[IgnoreMatch[^a]]{
		kind:      .ignore
		value:     value
		has_value: true
	}
}

fn ignore_match_whitelist_value[^a](value IgnoreMatch[^a]) Match[IgnoreMatch[^a]] {
	return Match[IgnoreMatch[^a]]{
		kind:      .whitelist
		value:     value
		has_value: true
	}
}

fn match_from_override[^a](m Match[OverrideGlob[^a]]) Match[IgnoreMatch[^a]] {
	if !m.has_value {
		return ignore_match_none[^a]()
	}
	if m.is_ignore() {
		return ignore_match_ignore_value[^a](IgnoreMatch.overrides[^a](m.value))
	} else if m.is_whitelist() {
		return ignore_match_whitelist_value[^a](IgnoreMatch.overrides[^a](m.value))
	}
	return ignore_match_none[^a]()
}

fn match_from_gitignore[^a](m Match[GitignoreGlobRef[^a]]) Match[IgnoreMatch[^a]] {
	if !m.has_value {
		return ignore_match_none[^a]()
	}
	if m.is_ignore() {
		return ignore_match_ignore_value[^a](IgnoreMatch.gitignore[^a](m.value))
	} else if m.is_whitelist() {
		return ignore_match_whitelist_value[^a](IgnoreMatch.gitignore[^a](m.value))
	}
	return ignore_match_none[^a]()
}

fn match_from_types[^a](m Match[TypesGlob[^a]]) Match[IgnoreMatch[^a]] {
	if !m.has_value {
		return ignore_match_none[^a]()
	}
	if m.is_ignore() {
		return ignore_match_ignore_value[^a](IgnoreMatch.types[^a](m.value))
	} else if m.is_whitelist() {
		return ignore_match_whitelist_value[^a](IgnoreMatch.types[^a](m.value))
	}
	return ignore_match_none[^a]()
}

/// Options for the ignore matcher, shared between the matcher itself and the
/// builder.
struct IgnoreOptions implements IClone {
	/// Whether to ignore hidden file paths or not.
	hidden bool = true
	/// Whether to read .ignore files.
	ignore bool = true
	/// Whether to respect any ignore files in parent directories.
	parents bool = true
	/// Whether to read git's global gitignore file.
	git_global bool = true
	/// Whether to read .gitignore files.
	git_ignore bool = true
	/// Whether to read .git/info/exclude files.
	git_exclude bool = true
	/// Whether to ignore files case insensitively
	ignore_case_insensitive bool
	/// Whether a git repository must be present in order to apply any
	/// git-related ignore rules.
	require_git bool = true
}

struct IgnoreNode implements IClone {
mut:
	/// The path to the directory that this matcher was built from.
	dir string
	/// The matcher for custom ignore files
	custom_ignore_matcher Gitignore
	/// The matcher for .ignore files.
	ignore_matcher Gitignore
	/// The matcher for .gitignore files.
	git_ignore_matcher Gitignore
	/// Special matcher for `.git/info/exclude` files.
	git_exclude_matcher Gitignore
	/// Whether this directory contains a .git sub-directory.
	has_git bool
	/// Whether this is an absolute parent matcher, as added by add_parent.
	is_absolute_parent bool
}

/// Ignore is a matcher useful for recursively walking one or more directories.
pub struct Ignore implements IClone {
mut:
	nodes []IgnoreNode
	/// An override matcher (default is empty).
	overrides Override
	/// A file type matcher.
	types Types
	/// The absolute base path of this matcher. Populated only if parent
	/// directories are added.
	absolute_base ?string
	/// The directory that gitignores should be interpreted relative to.
	///
	/// Usually this is the directory containing the gitignore file. But in
	/// some cases, like for global gitignores or for gitignores specified
	/// explicitly, this should generally be set to the current working
	/// directory. This is only used for global gitignores or "explicit"
	/// gitignores.
	///
	/// When `None`, this means the CWD could not be determined or is unknown.
	/// In this case, global gitignore files are ignored because they otherwise
	/// cannot be matched correctly.
	global_gitignores_relative_to ?string
	/// Explicit global ignore matchers specified by the caller.
	explicit_ignores []Gitignore
	/// Ignore files used in addition to `.ignore`
	custom_ignore_filenames []string
	/// A global gitignore matcher, usually from $XDG_CONFIG_HOME/git/ignore.
	git_global_matcher Gitignore
	/// Ignore config.
	opts IgnoreOptions
}

pub fn (ig &^a Ignore) path[^a]() &^a string {
	if ig.nodes.len == 0 {
		return &empty_ignore_string
	}
	return unsafe { &ig.nodes[ig.nodes.len - 1].dir }
}

pub fn (ig &Ignore) is_root() bool {
	return ig.nodes.len <= 1
}

pub fn (ig &Ignore) is_absolute_parent() bool {
	if ig.nodes.len == 0 {
		return false
	}
	return ig.nodes[ig.nodes.len - 1].is_absolute_parent
}

pub fn (ig Ignore) parent() ?Ignore {
	if ig.nodes.len <= 1 {
		return none
	}
	mut cloned := ig
	cloned.nodes = cloned.nodes[..cloned.nodes.len - 1].clone()
	return cloned
}

/// Create a new `Ignore` matcher with the parent directories of `dir`.
///
/// Note that this can only be called on an `Ignore` matcher with no
/// parents (i.e., `is_root` returns `true`). This will panic otherwise.
pub fn (ig Ignore) add_parents(path string) (Ignore, bool, IgnoreError) {
	if !ig.opts.parents && !ig.opts.git_ignore && !ig.opts.git_exclude && !ig.opts.git_global {
		return ig, false, IgnoreError{}
	}
	if !ig.is_root() {
		panic('Ignore.add_parents called on non-root matcher')
	}
	if !os.exists(path) {
		return ig, false, IgnoreError{}
	}
	absolute_base := os.real_path(path)
	if absolute_base == '' {
		return ig, false, IgnoreError{}
	}
	mut errs := PartialErrorBuilder{}
	mut built := ig
	for parent in ancestor_dirs(absolute_base) {
		node, has_err, err := built.add_child_path(parent)
		errs.maybe_push(has_err, err)
		mut next := built
		mut absolute_node := node
		absolute_node.is_absolute_parent = true
		absolute_node.has_git = if ig.opts.require_git && ig.opts.git_ignore {
			os.is_dir(os.join_path(parent, '.git')) || os.is_file(os.join_path(parent, '.git'))
				|| os.is_dir(os.join_path(parent, '.jj'))
		} else {
			false
		}
		next.absolute_base = ?string(absolute_base.to_owned())
		next.nodes << absolute_node
		built = next
	}
	final_has_err, final_err := errs.into_error_option()
	return built, final_has_err, final_err
}

/// Create a new `Ignore` matcher for the given child directory.
///
/// Since building the matcher may require reading from multiple
/// files, it's possible that this method partially succeeds. Therefore,
/// a matcher is always returned (which may match nothing) and an error is
/// returned if it exists.
///
/// Note that all I/O errors are completely ignored.
pub fn (ig Ignore) add_child(dir string) (Ignore, bool, IgnoreError) {
	node, has_err, err := ig.add_child_path(dir)
	mut next := ig
	next.nodes << node
	return next, has_err, err
}

/// Like add_child, but takes a full path and returns an IgnoreInner.
fn (ig Ignore) add_child_path(dir string) (IgnoreNode, bool, IgnoreError) {
	check_vcs_dir := ig.opts.require_git && (ig.opts.git_ignore || ig.opts.git_exclude)
	git_path := os.join_path(dir, '.git')
	git_is_file := check_vcs_dir && os.is_file(git_path)
	has_git := check_vcs_dir && ((os.is_dir(git_path) || git_is_file) || os.is_dir(os.join_path(dir,
		'.jj')))

	mut errs := PartialErrorBuilder{}
	custom_ig_matcher := if ig.custom_ignore_filenames.len == 0 {
		Gitignore.empty()
	} else {
		matcher, has_err, err := create_gitignore(dir, dir, ig.custom_ignore_filenames,
			ig.opts.ignore_case_insensitive)
		errs.maybe_push(has_err, err)
		matcher
	}
	ig_matcher := if !ig.opts.ignore {
		Gitignore.empty()
	} else {
		matcher, has_err, err := create_gitignore(dir, dir, ['.ignore'],
			ig.opts.ignore_case_insensitive)
		errs.maybe_push(has_err, err)
		matcher
	}
	gi_matcher := if !ig.opts.git_ignore {
		Gitignore.empty()
	} else {
		matcher, has_err, err := create_gitignore(dir, dir, ['.gitignore'],
			ig.opts.ignore_case_insensitive)
		errs.maybe_push(has_err, err)
		matcher
	}
	gi_exclude_matcher := if !ig.opts.git_exclude {
		Gitignore.empty()
	} else {
		git_dir, resolve_has_err, resolve_err := resolve_git_commondir(dir, git_is_file)
		if git_dir != '' {
			matcher, has_err, err := create_gitignore(dir, git_dir, ['info/exclude'],
				ig.opts.ignore_case_insensitive)
			errs.maybe_push(resolve_has_err, resolve_err)
			errs.maybe_push(has_err, err)
			matcher
		} else {
			errs.maybe_push(resolve_has_err, resolve_err)
			Gitignore.empty()
		}
	}
	final_has_err, final_err := errs.into_error_option()
	return IgnoreNode{
		dir:                   normalize_path(dir).to_owned()
		custom_ignore_matcher: custom_ig_matcher
		ignore_matcher:        ig_matcher
		git_ignore_matcher:    gi_matcher
		git_exclude_matcher:   gi_exclude_matcher
		has_git:               has_git
		is_absolute_parent:    false
	}, final_has_err, final_err
}

/// Returns true if at least one type of ignore rule should be matched.
fn (ig &Ignore) has_any_ignore_rules() bool {
	has_custom_ignore_files := ig.custom_ignore_filenames.len > 0
	has_explicit_ignores := ig.explicit_ignores.len > 0
	return ig.opts.ignore || ig.opts.git_global || ig.opts.git_ignore || ig.opts.git_exclude
		|| has_custom_ignore_files || has_explicit_ignores
}

/// Like `matched`, but works with a directory entry instead.
	pub fn (ig &^a Ignore) matched_dir_entry[^a](dent &DirEntry) Match[IgnoreMatch[^a]] {
	m := ig.matched[^a](dent.path(), dent.is_dir())
	if m.is_none() && ig.opts.hidden && is_hidden(dent.path()) {
		return ignore_match_ignore_value[^a](IgnoreMatch.hidden[^a]())
	}
	return m
}

/// Returns a match indicating whether the given file path should be
/// ignored or not.
///
/// The match contains information about its origin.
fn (ig &^a Ignore) matched[^a](path string, is_dir bool) Match[IgnoreMatch[^a]] {
	mut path_value := path
	stripped := strip_prefix(path_value, './')
	if stripped != path_value {
		path_value = stripped
	}
	if !ig.overrides.is_empty() {
		mat := match_from_override[^a](ig.overrides.matched[^a](path_value, is_dir))
		if !mat.is_none() {
			return mat
		}
	}
	mut whitelisted := ignore_match_none[^a]()
	if ig.has_any_ignore_rules() {
		mat := ig.matched_ignore[^a](path_value, is_dir)
		if mat.is_ignore() {
			return mat
		} else if mat.is_whitelist() {
			whitelisted = mat
		}
	}
	if !ig.types.is_empty() {
		mat := match_from_types[^a](ig.types.matched[^a](path_value, is_dir))
		if mat.is_ignore() {
			return mat
		} else if mat.is_whitelist() {
			whitelisted = mat
		}
	}
	return whitelisted
}

/// Performs matching only on the ignore files for this directory and
/// all parent directories.
fn (ig &^a Ignore) matched_ignore[^a](path string, is_dir bool) Match[IgnoreMatch[^a]] {
	mut m_custom_ignore := ignore_match_none[^a]()
	mut m_ignore := ignore_match_none[^a]()
	mut m_gi := ignore_match_none[^a]()
	mut m_gi_exclude := ignore_match_none[^a]()
	mut m_explicit := ignore_match_none[^a]()

	any_git := !ig.opts.require_git || ig.any_git_parent()
	mut saw_git := false
	for i := ig.nodes.len - 1; i >= 0; i-- {
		node := &ig.nodes[i]
		if node.is_absolute_parent {
			break
		}
		if m_custom_ignore.is_none() {
			m_custom_ignore = match_from_gitignore[^a](node.custom_ignore_matcher.matched[^a](path,
				is_dir))
		}
		if m_ignore.is_none() {
			m_ignore = match_from_gitignore[^a](node.ignore_matcher.matched[^a](path, is_dir))
		}
		if any_git && !saw_git && m_gi.is_none() {
			m_gi = match_from_gitignore[^a](node.git_ignore_matcher.matched[^a](path, is_dir))
		}
		if any_git && !saw_git && m_gi_exclude.is_none() {
			m_gi_exclude = match_from_gitignore[^a](node.git_exclude_matcher.matched[^a](path,
				is_dir))
		}
		saw_git = saw_git || node.has_git
	}
	if ig.opts.parents {
		if absolute_base := ig.absolute_base() {
			mut absolute_path := absolute_base.clone()
			mut path_to_join := path.to_owned()
			relative_base := ig.last_relative_dir_before_absolute_path()
			if relative_base != '' {
				if relative_base == '.' {
					path_to_join = path.to_owned()
				} else {
					without_dot_slash := strip_if_is_prefix[^a]('./', &relative_base)
					relative_path := strip_if_is_prefix[^a](without_dot_slash, &path)
					path_to_join = strip_if_is_prefix[^a]('/', &relative_path)
				}
			}
			if path_to_join != '' {
				absolute_path = os.join_path(absolute_path, path_to_join.clone())
			}
			for i := ig.nodes.len - 1; i >= 0; i-- {
				node := &ig.nodes[i]
				if !node.is_absolute_parent {
					continue
				}
				if m_custom_ignore.is_none() {
					m_custom_ignore = match_from_gitignore[^a](node.custom_ignore_matcher.matched[^a](absolute_path,
						is_dir))
				}
				if m_ignore.is_none() {
					m_ignore = match_from_gitignore[^a](node.ignore_matcher.matched[^a](absolute_path,
						is_dir))
				}
				if any_git && !saw_git && m_gi.is_none() {
					m_gi = match_from_gitignore[^a](node.git_ignore_matcher.matched[^a](absolute_path,
						is_dir))
				}
				if any_git && !saw_git && m_gi_exclude.is_none() {
					m_gi_exclude = match_from_gitignore[^a](node.git_exclude_matcher.matched[^a](absolute_path,
						is_dir))
				}
				saw_git = saw_git || node.has_git
			}
		}
	}
	for i := ig.explicit_ignores.len - 1; i >= 0; i-- {
		if !m_explicit.is_none() {
			break
		}
		explicit_ignore := &ig.explicit_ignores[i]
		m_explicit = match_from_gitignore[^a](explicit_ignore.matched[^a](path, is_dir))
	}
	m_global := if any_git {
		match_from_gitignore[^a](ig.git_global_matcher.matched[^a](path, is_dir))
	} else {
		ignore_match_none[^a]()
	}
	return m_custom_ignore.or(m_ignore).or(m_gi).or(m_gi_exclude).or(m_global).or(m_explicit)
}

/// Returns an iterator over parent ignore matchers, including this one.
pub fn (ig &^a Ignore) parents[^a]() Parents[^a] {
	mut items := []Ignore{}
	for i := ig.nodes.len - 1; i >= 0; i-- {
		mut item := ig
		item.nodes = ig.nodes[..i + 1].clone()
		items << item
	}
	return Parents[^a]{
		items: items
		index: 0
	}
}

/// Returns the first absolute path of the first absolute parent, if
/// one exists.
fn (ig &^a Ignore) absolute_base[^a]() ?&^a string {
	if ig.absolute_base != none {
		return unsafe { &ig.absolute_base? }
	}
	return none
}

/// An iterator over all parents of an ignore matcher, including itself.
///
/// The lifetime `'a` refers to the lifetime of the initial `Ignore` matcher.
pub struct Parents[^a] {
mut:
	items []Ignore
	index int
}

pub fn (mut p Parents[^a]) next[^a]() ?&^a Ignore {
	if p.index >= p.items.len {
		return none
	}
	item := unsafe { &p.items[p.index] }
	p.index++
	return item
}

/// A builder for creating an Ignore matcher.
pub struct IgnoreBuilder implements IClone {
mut:
	/// The root directory path for this ignore matcher.
	dir string
	/// An override matcher (default is empty).
	overrides Override
	/// A type matcher (default is empty).
	types Types
	/// Explicit global ignore matchers.
	explicit_ignores []Gitignore
	/// Ignore files in addition to .ignore.
	custom_ignore_filenames []string
	/// The directory that gitignores should be interpreted relative to.
	///
	/// Usually this is the directory containing the gitignore file. But in
	/// some cases, like for global gitignores or for gitignores specified
	/// explicitly, this should generally be set to the current working
	/// directory. This is only used for global gitignores or "explicit"
	/// gitignores.
	///
	/// When `None`, global gitignores are ignored.
	global_gitignores_relative_to ?string
	/// Ignore config.
	opts IgnoreOptions
}

/// Create a new builder for an `Ignore` matcher.
///
/// It is likely a bug to use this without also calling `current_dir()`
/// outside of tests. This isn't made mandatory because this is an internal
/// abstraction and it's annoying to update tests.
pub fn IgnoreBuilder.new() IgnoreBuilder {
	return IgnoreBuilder{
		dir:                         ''.to_owned()
		overrides:                   Override.empty()
		types:                       Types.empty()
		explicit_ignores:            []Gitignore{}
		custom_ignore_filenames:     []string{}
		global_gitignores_relative_to: none
		opts:                        IgnoreOptions{}
	}
}

/// Builds a new `Ignore` matcher.
///
/// The matcher returned won't match anything until ignore rules from
/// directories are added to it.
pub fn (builder IgnoreBuilder) build() Ignore {
	return builder.build_with_cwd('')
}

/// Builds a new `Ignore` matcher using the given CWD directory.
///
/// The matcher returned won't match anything until ignore rules from
/// directories are added to it.
pub fn (builder IgnoreBuilder) build_with_cwd(cwd string) Ignore {
	mut relative_to := ''
	if cwd != '' {
		relative_to = cwd.to_owned()
	} else if configured := builder.global_gitignores_relative_to {
		relative_to = configured.clone()
	}
	mut global_gitignores_relative_to := none_string()
	if relative_to != '' {
		global_gitignores_relative_to = ?string(relative_to.clone())
	}
	mut git_global_matcher := Gitignore.empty()
	if builder.opts.git_global {
		if relative_to != '' {
			mut gitignore_builder := GitignoreBuilder.new(relative_to.clone())
			_, _ = gitignore_builder.case_insensitive(builder.opts.ignore_case_insensitive)
			gi, _, _ := gitignore_builder.build_global()
			git_global_matcher = gi
		}
	}
	return Ignore{
		nodes: [IgnoreNode{
			dir:                   builder.dir.clone()
			custom_ignore_matcher: Gitignore.empty()
			ignore_matcher:        Gitignore.empty()
			git_ignore_matcher:    Gitignore.empty()
			git_exclude_matcher:   Gitignore.empty()
			has_git:               false
			is_absolute_parent:    true
		}]
		overrides:                 builder.overrides
		types:                     builder.types
		absolute_base:             none_string()
		global_gitignores_relative_to: global_gitignores_relative_to
		explicit_ignores:          builder.explicit_ignores.clone()
		custom_ignore_filenames:   builder.custom_ignore_filenames.clone()
		git_global_matcher:        git_global_matcher
		opts:                      builder.opts
	}
}

/// Set the current directory used for matching global gitignores.
pub fn (mut builder IgnoreBuilder) current_dir(cwd string) {
	builder.global_gitignores_relative_to = ?string(cwd.to_owned())
}

/// Add an override matcher.
///
/// By default, no override matcher is used.
///
/// This overrides any previous setting.
pub fn (mut builder IgnoreBuilder) overrides(overrides Override) {
	builder.overrides = overrides
}

/// Add a file type matcher.
///
/// By default, no file type matcher is used.
///
/// This overrides any previous setting.
pub fn (mut builder IgnoreBuilder) types(types Types) {
	builder.types = types
}

/// Adds a new global ignore matcher from the ignore file path given.
pub fn (mut builder IgnoreBuilder) add_ignore(ig Gitignore) {
	builder.explicit_ignores << ig
}

/// Add a custom ignore file name
///
/// These ignore files have higher precedence than all other ignore files.
///
/// When specifying multiple names, earlier names have lower precedence than
/// later names.
pub fn (mut builder IgnoreBuilder) add_custom_ignore_filename(file_name string) {
	builder.custom_ignore_filenames << file_name.to_owned()
}

/// Enables ignoring hidden files.
///
/// This is enabled by default.
pub fn (mut builder IgnoreBuilder) hidden(yes bool) {
	builder.opts.hidden = yes
}

/// Enables reading `.ignore` files.
///
/// `.ignore` files have the same semantics as `gitignore` files and are
/// supported by search tools such as ripgrep and The Silver Searcher.
///
/// This is enabled by default.
pub fn (mut builder IgnoreBuilder) ignore(yes bool) {
	builder.opts.ignore = yes
}

/// Enables reading ignore files from parent directories.
///
/// If this is enabled, then .gitignore files in parent directories of each
/// file path given are respected. Otherwise, they are ignored.
///
/// This is enabled by default.
pub fn (mut builder IgnoreBuilder) parents(yes bool) {
	builder.opts.parents = yes
}

/// Add a global gitignore matcher.
///
/// Its precedence is lower than both normal `.gitignore` files and
/// `.git/info/exclude` files.
///
/// This overwrites any previous global gitignore setting.
///
/// This is enabled by default.
pub fn (mut builder IgnoreBuilder) git_global(yes bool) {
	builder.opts.git_global = yes
}

/// Enables reading `.gitignore` files.
///
/// `.gitignore` files have match semantics as described in the `gitignore`
/// man page.
///
/// This is enabled by default.
pub fn (mut builder IgnoreBuilder) git_ignore(yes bool) {
	builder.opts.git_ignore = yes
}

/// Enables reading `.git/info/exclude` files.
///
/// `.git/info/exclude` files have match semantics as described in the
/// `gitignore` man page.
///
/// This is enabled by default.
pub fn (mut builder IgnoreBuilder) git_exclude(yes bool) {
	builder.opts.git_exclude = yes
}

/// Whether a git repository is required to apply git-related ignore
/// rules (global rules, .gitignore and local exclude rules).
///
/// When disabled, git-related ignore rules are applied even when searching
/// outside a git repository.
pub fn (mut builder IgnoreBuilder) require_git(yes bool) {
	builder.opts.require_git = yes
}

/// Process ignore files case insensitively
///
/// This is disabled by default.
pub fn (mut builder IgnoreBuilder) ignore_case_insensitive(yes bool) {
	builder.opts.ignore_case_insensitive = yes
}

/// Creates a new gitignore matcher for the directory given.
///
/// The matcher is meant to match files below `dir`.
/// Ignore globs are extracted from each of the file names relative to
/// `dir_for_ignorefile` in the order given (earlier names have lower
/// precedence than later names).
///
/// I/O errors are ignored.
pub fn create_gitignore(dir string, dir_for_ignorefile string, names []string, case_insensitive bool) (Gitignore, bool, IgnoreError) {
	mut builder := GitignoreBuilder.new(dir)
	mut errs := PartialErrorBuilder{}
	_, _ = builder.case_insensitive(case_insensitive)
	for name in names {
		gipath := os.join_path(dir_for_ignorefile, name)
		if os.user_os() == 'windows' || os.exists(gipath) {
			add_has_err, add_err := builder.add(gipath)
			errs.maybe_push_ignore_io(add_has_err, add_err)
		}
	}
	gi, build_has_err, build_err := builder.build()
	errs.maybe_push(build_has_err, build_err)
	final_has_err, final_err := errs.into_error_option()
	return gi, final_has_err, final_err
}

/// Find the GIT_COMMON_DIR for the given git worktree.
///
/// This is the directory that may contain a private ignore file
/// "info/exclude". Unlike git, this function does *not* read environment
/// variables GIT_DIR and GIT_COMMON_DIR, because it is not clear how to use
/// them when multiple repositories are searched.
///
/// Some I/O errors are ignored.
fn resolve_git_commondir(dir string, git_is_file bool) (string, bool, IgnoreError) {
	git_dir_path := os.join_path(dir, '.git')
	if !git_is_file {
		return git_dir_path, false, IgnoreError{}
	}
	dot_git_lines := os.read_lines(git_dir_path) or {
		return '', true, io_error(err).with_path(git_dir_path)
	}
	if dot_git_lines.len == 0 {
		return '', false, IgnoreError{}
	}
	dot_git_line := dot_git_lines[0]
	if !dot_git_line.starts_with('gitdir: ') {
		return '', false, IgnoreError{}
	}
	real_git_dir := dot_git_line['gitdir: '.len..]
	git_commondir_file := os.join_path(real_git_dir, 'commondir')
	commondir_lines := os.read_lines(git_commondir_file) or {
		return '', false, IgnoreError{}
	}
	if commondir_lines.len == 0 {
		return '', false, IgnoreError{}
	}
	commondir_line := commondir_lines[0]
	commondir_abs := if commondir_line.starts_with('.') {
		os.join_path(real_git_dir, commondir_line)
	} else {
		commondir_line
	}
	return commondir_abs, false, IgnoreError{}
}

/// Strips `prefix` from `path` if it's a prefix, otherwise returns `path`
/// unchanged.
fn strip_if_is_prefix[^a](prefix string, path &^a string) string {
	return strip_prefix(*path, prefix)
}

fn (ig Ignore) any_git_parent() bool {
	for i := ig.nodes.len - 1; i >= 0; i-- {
		if ig.nodes[i].has_git {
			return true
		}
	}
	return false
}

fn (ig Ignore) last_relative_dir_before_absolute_path() string {
	mut last := ''
	for i := ig.nodes.len - 1; i >= 0; i-- {
		node := ig.nodes[i]
		if node.is_absolute_parent {
			break
		}
		last = node.dir.clone()
	}
	return last
}

fn none_string() ?string {
	return none
}
