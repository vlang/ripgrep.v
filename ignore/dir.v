module ignore

import encoding.utf8
import os
import sync.arc

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

fn match_from_override[^a](m Match[OverrideGlob[^a]]) Match[IgnoreMatch[^a]] {
	return m.map(IgnoreMatch.overrides)
}

fn match_from_gitignore[^a](m Match[GitignoreGlobRef[^a]]) Match[IgnoreMatch[^a]] {
	return m.map(IgnoreMatch.gitignore)
}

fn match_from_types[^a](m Match[TypesGlob[^a]]) Match[IgnoreMatch[^a]] {
	return m.map(IgnoreMatch.types)
}

// V-specific: this constructs only the empty match, so it carries no borrowed
// payload at runtime. It avoids a V2 local inference fallback for
// `Match[IgnoreMatch[^a]]{}` while preserving the translated control flow.
fn ignore_match_none() Match[IgnoreMatch] {
	return Match[IgnoreMatch]{}
}

/// Options for the ignore matcher, shared between the matcher itself and the
/// builder.
struct IgnoreOptions implements IClone {
mut:
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

// IgnoreNode holds the immutable per-directory matcher data. Rust nests this in
// `IgnoreInner` behind `Arc<IgnoreInner>`; here it is shared via
// `arc.Arc[IgnoreNode]`, and each node owns a shared reference to its parent.
// Cleanup (freeing `dir` and the matchers, and cascading into the parent Arc)
// happens automatically when the last owning Arc is dropped.
struct IgnoreNode {
mut:
	// V-specific: V3 cannot clone an `Option<Arc<T>>` field directly. This
	// zero-or-one array preserves the Rust optional Arc and owns its handle.
	parent []arc.Arc[IgnoreNode]
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

// parent_node returns a shared borrow of the parent node, or none at the root.
// The borrow is tied to the caller's lifetime because the whole node chain is
// kept alive by the originating `Ignore`.
fn (node &^a IgnoreNode) parent_node[^a]() ?&^a IgnoreNode {
	if node.parent.len > 0 {
		return node.parent[0].get()
	}
	return none
}

/// Ignore is a matcher useful for recursively walking one or more directories.
pub struct Ignore implements IClone {
mut:
	// V-specific: Rust models this as `Ignore(Arc<IgnoreInner>)`; the shared,
	// immutable per-directory matcher data lives in `arc.Arc[IgnoreNode]`.
	node arc.Arc[IgnoreNode]
	/// An override matcher (default is empty). Rust: `Arc<Override>`.
	overrides arc.Arc[Override]
	/// A file type matcher. Rust: `Arc<Types>`.
	types arc.Arc[Types]
	/// The absolute base path of this matcher. Populated only if parent
	/// directories are added. Rust: `Option<Arc<PathBuf>>`.
	//
	// V-specific: stored as a non-optional `Arc[string]` with an empty-string
	// sentinel meaning "none" (an absent absolute base already resolves to the
	// empty path — see `Ignore` construction). This lets every `Ignore.clone()`
	// share it via the ordinary `Arc.clone()` (strong-count++) path used by the
	// other `Arc` fields. Cloning it through an `?Arc` helper instead tripped a
	// v3 ownership bug: unwrapping the optional to clone the inner produced a
	// shallow alias that the generated code then dropped, so each clone was a net
	// -1 to the shared strong count and prematurely freed the path (UAF).
	absolute_base_value arc.Arc[string]
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
	/// Rust: `Arc<Vec<Gitignore>>`.
	explicit_ignores arc.Arc[[]Gitignore]
	/// Ignore files used in addition to `.ignore`. Rust: `Arc<Vec<OsString>>`.
	custom_ignore_filenames arc.Arc[[]string]
	/// A global gitignore matcher, usually from $XDG_CONFIG_HOME/git/ignore.
	/// Rust: `Arc<Gitignore>`.
	git_global_matcher arc.Arc[Gitignore]
	/// Ignore config.
	opts IgnoreOptions
}

pub fn (ig &Ignore) clone() Ignore {
	return Ignore{
		node:                          ig.node.clone()
		overrides:                     ig.overrides.clone()
		types:                         ig.types.clone()
		absolute_base_value:           ig.absolute_base_value.clone()
		global_gitignores_relative_to: clone_optional_string(ig.global_gitignores_relative_to)
		explicit_ignores:              ig.explicit_ignores.clone()
		custom_ignore_filenames:       ig.custom_ignore_filenames.clone()
		git_global_matcher:            ig.git_global_matcher.clone()
		opts:                          ig.opts
	}
}

pub fn (ig &^a Ignore) path[^a]() &^a string {
	node := ig.node.get()
	return &node.dir
}

pub fn (ig &Ignore) is_root() bool {
	return ig.node.get().parent.len == 0
}

pub fn (ig &Ignore) is_absolute_parent() bool {
	return ig.node.get().is_absolute_parent
}

pub fn (ig &Ignore) parent() ?Ignore {
	if ig.node.get().parent.len > 0 {
		return ig.with_node(ig.node.get().parent[0].clone())
	}
	return none
}

fn (ig &Ignore) with_node(node arc.Arc[IgnoreNode]) Ignore {
	return Ignore{
		node:                          node
		overrides:                     ig.overrides.clone()
		types:                         ig.types.clone()
		absolute_base_value:           ig.absolute_base_value.clone()
		global_gitignores_relative_to: clone_optional_string(ig.global_gitignores_relative_to)
		explicit_ignores:              ig.explicit_ignores.clone()
		custom_ignore_filenames:       ig.custom_ignore_filenames.clone()
		git_global_matcher:            ig.git_global_matcher.clone()
		opts:                          ig.opts
	}
}

/// Create a new `Ignore` matcher with the parent directories of `dir`.
///
/// Note that this can only be called on an `Ignore` matcher with no
/// parents (i.e., `is_root` returns `true`). This will panic otherwise.
pub fn (ig &Ignore) add_parents(path string) (Ignore, bool, IgnoreError) {
	if !ig.opts.parents && !ig.opts.git_ignore && !ig.opts.git_exclude && !ig.opts.git_global {
		return ig.clone(), false, IgnoreError{}
	}
	if !ig.is_root() {
		panic('Ignore.add_parents called on non-root matcher')
	}
	if !os.exists(path) {
		return ig.clone(), false, IgnoreError{}
	}
	absolute_base := os.real_path(path)
	if absolute_base == '' {
		return ig.clone(), false, IgnoreError{}
	}
	absolute_base_arc := arc.new(absolute_base.to_owned())
	mut errs := PartialErrorBuilder{}
	mut built := ig.clone()
	for parent in ancestor_dirs(absolute_base) {
		mut node, has_err, err := built.add_child_path(parent.clone())
		errs.maybe_push(has_err, err)
		// Mutate the freshly-built, still-owned node before sharing it, exactly
		// like Rust mutates the owned `IgnoreInner` prior to `Arc::new`.
		node.is_absolute_parent = true
		node.has_git = if ig.opts.require_git && ig.opts.git_ignore {
			os.exists(os.join_path(parent.clone(), '.git'))
				|| os.exists(os.join_path(parent.clone(), '.jj'))
		} else {
			false
		}
		node_arc := arc.new(node)
		mut next := built.with_node(node_arc)
		next.absolute_base_value = absolute_base_arc.clone()
		built = next.clone()
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
pub fn (ig &Ignore) add_child(dir string) (Ignore, bool, IgnoreError) {
	node, has_err, err := ig.add_child_path(dir)
	node_arc := arc.new(node)
	return ig.with_node(node_arc), has_err, err
}

// free_nodes eagerly releases this matcher's shared node chain.
//
// With `arc.Arc` this is optional: dropping an `Ignore` already releases one
// strong reference to the tail node and cascades up the parent chain, freeing
// each node once its last owner is gone. Callers that finish with a matcher
// early may still invoke this to release the chain sooner. `arc.drop` is
// idempotent (it nils the handle), so the later automatic drop is a safe no-op.
fn (mut ig Ignore) free_nodes() {
	ig.node.drop()
}

/// Like add_child, but takes a full path and returns an owned IgnoreNode.
///
/// The node is returned by value (not yet shared) so the caller can finish
/// initializing it before wrapping it in an `arc.Arc`, mirroring how Rust
/// builds an owned `IgnoreInner` and then calls `Arc::new`.
fn (ig &Ignore) add_child_path(dir string) (IgnoreNode, bool, IgnoreError) {
	check_vcs_dir := ig.opts.require_git && (ig.opts.git_ignore || ig.opts.git_exclude)
	git_path := os.join_path(dir.clone(), '.git')
	git_is_file := check_vcs_dir && os.is_file(git_path)
	has_git := check_vcs_dir
		&& (os.exists(git_path.clone()) || os.exists(os.join_path(dir.clone(), '.jj')))

	mut errs := PartialErrorBuilder{}
	custom_ig_matcher := if ig.custom_ignore_filenames.get().len == 0 {
		Gitignore.empty()
	} else {
		matcher, has_err, err := create_gitignore(dir.clone(), dir.clone(),
			ig.custom_ignore_filenames.get().clone(),
			ig.opts.ignore_case_insensitive)
		errs.maybe_push(has_err, err)
		matcher
	}
	ig_matcher := if !ig.opts.ignore {
		Gitignore.empty()
	} else {
		matcher, has_err, err := create_gitignore(dir.clone(), dir.clone(), ['.ignore'],
			ig.opts.ignore_case_insensitive)
		errs.maybe_push(has_err, err)
		matcher
	}
	gi_matcher := if !ig.opts.git_ignore {
		Gitignore.empty()
	} else {
		matcher, has_err, err := create_gitignore(dir.clone(), dir.clone(), ['.gitignore'],
			ig.opts.ignore_case_insensitive)
		errs.maybe_push(has_err, err)
		matcher
	}
	gi_exclude_matcher := if !ig.opts.git_exclude || (check_vcs_dir && !has_git) {
		Gitignore.empty()
	} else {
		git_dir, resolve_has_err, resolve_err := resolve_git_commondir(dir.clone(), git_is_file)
		if git_dir != '' {
			matcher, has_err, err := create_gitignore(dir.clone(), git_dir, ['info/exclude'],
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
		parent:                [ig.node.clone()]
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
	has_custom_ignore_files := ig.custom_ignore_filenames.get().len > 0
	has_explicit_ignores := ig.explicit_ignores.get().len > 0
	return ig.opts.ignore || ig.opts.git_global || ig.opts.git_ignore || ig.opts.git_exclude
		|| has_custom_ignore_files || has_explicit_ignores
}

/// Like `matched`, but works with a directory entry instead.
pub fn (ig &^a Ignore) matched_dir_entry[^a](dent &DirEntry) Match[IgnoreMatch[^a]] {
	m := ig.matched(dent.path().clone(), dent.is_dir())
	if m.is_none() && ig.opts.hidden && is_hidden_file_name(dent.file_name().clone()) {
		return Match[IgnoreMatch[^a]]{
			kind:      .ignore
			value:     IgnoreMatch.hidden()
			has_value: true
		}
	}
	return m
}

fn (ig &^a Ignore) matched_dir_entry_with_scratch[^a](dent &DirEntry, mut gitignore_matches []usize) Match[IgnoreMatch[^a]] {
	m := ig.matched_with_scratch(dent.path().clone(), dent.is_dir(), mut gitignore_matches)
	if m.is_none() && ig.opts.hidden && is_hidden_file_name(dent.file_name().clone()) {
		return Match[IgnoreMatch[^a]]{
			kind:      .ignore
			value:     IgnoreMatch.hidden()
			has_value: true
		}
	}
	return m
}

/// Returns a match indicating whether the given file path should be
/// ignored or not.
///
/// The match contains information about its origin.
fn (ig &^a Ignore) matched[^a](path string, is_dir bool) Match[IgnoreMatch[^a]] {
	mut gitignore_matches := []usize{}
	return ig.matched_with_scratch(path, is_dir, mut gitignore_matches)
}

fn (ig &^a Ignore) matched_with_scratch[^a](path string, is_dir bool, mut gitignore_matches []usize) Match[IgnoreMatch[^a]] {
	mut path_value := path
	if path_value.starts_with('./') {
		path_value = unsafe { path_value.substr_unsafe(2, path_value.len) }
	}
	if !ig.overrides.get().is_empty() {
		mat := match_from_override(ig.overrides.get().matched(path_value, is_dir))
		if !mat.is_none() {
			return mat
		}
	}
	mut whitelisted := ignore_match_none()
	if ig.has_any_ignore_rules() {
		mat := ig.matched_ignore_with_scratch(&path_value, is_dir, mut gitignore_matches)
		if mat.is_ignore() {
			return mat
		} else if mat.is_whitelist() {
			whitelisted = mat
		}
	}
	if !ig.types.get().is_empty() {
		mat := match_from_types(ig.types.get().matched(path_value, is_dir))
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
	mut gitignore_matches := []usize{}
	return ig.matched_ignore_with_scratch(&path, is_dir, mut gitignore_matches)
}

fn (ig &^a Ignore) matched_ignore_with_scratch[^a](path &string, is_dir bool, mut gitignore_matches []usize) Match[IgnoreMatch[^a]] {
	mut m_custom_ignore := ignore_match_none()
	mut m_ignore := ignore_match_none()
	mut m_gi := ignore_match_none()
	mut m_gi_exclude := ignore_match_none()
	mut m_explicit := ignore_match_none()

	any_git := !ig.opts.require_git || ig.any_git_parent()
	mut saw_git := false
	mut node := ig.node.get()
	for {
		if node.is_absolute_parent {
			break
		}
			if m_custom_ignore.is_none() && !node.custom_ignore_matcher.is_empty() {
				m_custom_ignore = match_from_gitignore(node.custom_ignore_matcher.matched_with_scratch(path,
					is_dir, mut gitignore_matches))
			}
			if m_ignore.is_none() && !node.ignore_matcher.is_empty() {
				m_ignore = match_from_gitignore(node.ignore_matcher.matched_with_scratch(path, is_dir,
					mut gitignore_matches))
			}
			if any_git && !saw_git && m_gi.is_none() && !node.git_ignore_matcher.is_empty() {
				m_gi = match_from_gitignore(node.git_ignore_matcher.matched_with_scratch(path, is_dir,
					mut gitignore_matches))
			}
			if any_git && !saw_git && m_gi_exclude.is_none() && !node.git_exclude_matcher.is_empty() {
				m_gi_exclude = match_from_gitignore(node.git_exclude_matcher.matched_with_scratch(path,
					is_dir, mut gitignore_matches))
			}
		saw_git = saw_git || node.has_git
		node = node.parent_node() or { break }
	}
	if ig.opts.parents {
		if absolute_base := ig.absolute_base() {
			mut absolute_path := parent_absolute_match_path(*absolute_base,
				ig.first_relative_dir_after_absolute_path(), (*path).clone())
			node = ig.node.get()
			for {
				if !node.is_absolute_parent {
					node = node.parent_node() or { break }
					continue
				}
					if m_custom_ignore.is_none() && !node.custom_ignore_matcher.is_empty() {
						m_custom_ignore = match_from_gitignore(node.custom_ignore_matcher.matched_with_scratch(&absolute_path,
							is_dir, mut gitignore_matches))
					}
					if m_ignore.is_none() && !node.ignore_matcher.is_empty() {
						m_ignore = match_from_gitignore(node.ignore_matcher.matched_with_scratch(&absolute_path,
							is_dir, mut gitignore_matches))
					}
					if any_git && !saw_git && m_gi.is_none() && !node.git_ignore_matcher.is_empty() {
						m_gi = match_from_gitignore(node.git_ignore_matcher.matched_with_scratch(&absolute_path,
							is_dir, mut gitignore_matches))
					}
					if any_git && !saw_git && m_gi_exclude.is_none() && !node.git_exclude_matcher.is_empty() {
						m_gi_exclude = match_from_gitignore(node.git_exclude_matcher.matched_with_scratch(&absolute_path,
							is_dir, mut gitignore_matches))
					}
				saw_git = saw_git || node.has_git
				node = node.parent_node() or { break }
			}
		}
	}
	for i := ig.explicit_ignores.get().len - 1; i >= 0; i-- {
		if !m_explicit.is_none() {
			break
		}
			explicit_ignores := ig.explicit_ignores.get()
			explicit_ignore := unsafe { &(*explicit_ignores)[i] }
			if !explicit_ignore.is_empty() {
				m_explicit = match_from_gitignore(explicit_ignore.matched_with_scratch(path, is_dir,
					mut gitignore_matches))
			}
		}
		m_global := if any_git && !ig.git_global_matcher.get().is_empty() {
			match_from_gitignore(ig.git_global_matcher.get().matched_with_scratch(path, is_dir,
				mut gitignore_matches))
		} else {
			Match[IgnoreMatch[^a]]{}
		}
	if !m_custom_ignore.is_none() {
		return m_custom_ignore
	}
	if !m_ignore.is_none() {
		return m_ignore
	}
	if !m_gi.is_none() {
		return m_gi
	}
	if !m_gi_exclude.is_none() {
		return m_gi_exclude
	}
	if !m_global.is_none() {
		return m_global
	}
	if !m_explicit.is_none() {
		return m_explicit
	}
	return Match[IgnoreMatch[^a]]{}
}

/// Returns an iterator over parent ignore matchers, including this one.
pub fn (ig &Ignore) parents() Parents {
	mut items := [ig.clone()]
	mut node := ig.node.get()
	for node.parent.len > 0 {
		items << ig.with_node(node.parent[0].clone())
		node = node.parent[0].get()
	}
	return Parents{
		items: items
		index: 0
	}
}

/// Returns the first absolute path of the first absolute parent, if
/// one exists.
fn (ig &^a Ignore) absolute_base[^a]() ?&^a string {
	// The empty-string sentinel means "no absolute base".
	if ig.absolute_base_value.get().len == 0 {
		return none
	}
	return ig.absolute_base_value.get()
}

/// An iterator over all parents of an ignore matcher, including itself.
///
/// V-specific: this iterator holds owned `Ignore` handles that each share the
/// underlying matcher nodes via `arc.Arc`; they are released automatically when
/// the iterator (and each yielded handle) goes out of scope.
pub struct Parents {
mut:
	items []Ignore
	index int
}

pub fn (mut p Parents) next() ?Ignore {
	if p.index >= p.items.len {
		return none
	}
	item := p.items[p.index].clone()
	p.index++
	return item
}

/// A builder for creating an Ignore matcher.
pub struct IgnoreBuilder implements IClone {
mut:
	/// The root directory path for this ignore matcher.
	dir string
	/// An override matcher (default is empty). Rust: `Arc<Override>`.
	overrides_value arc.Arc[Override]
	/// A type matcher (default is empty). Rust: `Arc<Types>`.
	types_value arc.Arc[Types]
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
		overrides_value:             arc.new(Override.empty())
		types_value:                 arc.new(Types.empty())
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
pub fn (builder &IgnoreBuilder) build() Ignore {
	return builder.build_with_cwd(none_string())
}

/// Builds a new `Ignore` matcher using the given CWD directory.
///
/// The matcher returned won't match anything until ignore rules from
/// directories are added to it.
pub fn (builder &IgnoreBuilder) build_with_cwd(cwd ?string) Ignore {
	mut global_gitignores_relative_to := none_string()
	mut matcher_gitignores_relative_to := none_string()
	if cwd_value := cwd {
		global_gitignores_relative_to = ?string(cwd_value.clone())
		matcher_gitignores_relative_to = ?string(cwd_value.clone())
	} else if configured := builder.global_gitignores_relative_to {
		global_gitignores_relative_to = ?string(configured.clone())
		matcher_gitignores_relative_to = ?string(configured.clone())
	}
	mut git_global_matcher_arc := arc.new(Gitignore.empty())
	if builder.opts.git_global {
		if relative_to := matcher_gitignores_relative_to {
			mut gitignore_builder := GitignoreBuilder.new(relative_to)
			_, _ = gitignore_builder.case_insensitive(builder.opts.ignore_case_insensitive)
			gi, _, _ := gitignore_builder.build_global()
			git_global_matcher_arc = arc.new(gi)
		}
	}
	return Ignore{
		node: arc.new(IgnoreNode{
			dir:                   builder.dir.clone()
			custom_ignore_matcher: Gitignore.empty()
			ignore_matcher:        Gitignore.empty()
			git_ignore_matcher:    Gitignore.empty()
			git_exclude_matcher:   Gitignore.empty()
			has_git:               false
			is_absolute_parent:    true
		})
		overrides:                     builder.overrides_value.clone()
		types:                         builder.types_value.clone()
		absolute_base_value:           none_absolute_base()
		global_gitignores_relative_to: global_gitignores_relative_to
		explicit_ignores:              arc.new(clone_gitignores(builder.explicit_ignores))
		custom_ignore_filenames:       arc.new(builder.custom_ignore_filenames.clone())
		git_global_matcher:            git_global_matcher_arc
		opts:                          builder.opts
	}
}

/// Set the current directory used for matching global gitignores.
pub fn (mut builder IgnoreBuilder) current_dir(cwd string) &IgnoreBuilder {
	builder.global_gitignores_relative_to = ?string(cwd.to_owned())
	return builder
}

/// Add an override matcher.
///
/// By default, no override matcher is used.
///
/// This overrides any previous setting.
pub fn (mut builder IgnoreBuilder) overrides(overrides Override) &IgnoreBuilder {
	builder.overrides_value = arc.new(overrides)
	return builder
}

/// Add a file type matcher.
///
/// By default, no file type matcher is used.
///
/// This overrides any previous setting.
pub fn (mut builder IgnoreBuilder) types(types Types) &IgnoreBuilder {
	builder.types_value = arc.new(types)
	return builder
}

/// Adds a new global ignore matcher from the ignore file path given.
pub fn (mut builder IgnoreBuilder) add_ignore(ig Gitignore) &IgnoreBuilder {
	builder.explicit_ignores << ig
	return builder
}

/// Add a custom ignore file name
///
/// These ignore files have higher precedence than all other ignore files.
///
/// When specifying multiple names, earlier names have lower precedence than
/// later names.
pub fn (mut builder IgnoreBuilder) add_custom_ignore_filename(file_name string) &IgnoreBuilder {
	builder.custom_ignore_filenames << file_name.to_owned()
	return builder
}

/// Enables ignoring hidden files.
///
/// This is enabled by default.
pub fn (mut builder IgnoreBuilder) hidden(yes bool) &IgnoreBuilder {
	builder.opts.hidden = yes
	return builder
}

/// Enables reading `.ignore` files.
///
/// `.ignore` files have the same semantics as `gitignore` files and are
/// supported by search tools such as ripgrep and The Silver Searcher.
///
/// This is enabled by default.
pub fn (mut builder IgnoreBuilder) ignore(yes bool) &IgnoreBuilder {
	builder.opts.ignore = yes
	return builder
}

/// Enables reading ignore files from parent directories.
///
/// If this is enabled, then .gitignore files in parent directories of each
/// file path given are respected. Otherwise, they are ignored.
///
/// This is enabled by default.
pub fn (mut builder IgnoreBuilder) parents(yes bool) &IgnoreBuilder {
	builder.opts.parents = yes
	return builder
}

/// Add a global gitignore matcher.
///
/// Its precedence is lower than both normal `.gitignore` files and
/// `.git/info/exclude` files.
///
/// This overwrites any previous global gitignore setting.
///
/// This is enabled by default.
pub fn (mut builder IgnoreBuilder) git_global(yes bool) &IgnoreBuilder {
	builder.opts.git_global = yes
	return builder
}

/// Enables reading `.gitignore` files.
///
/// `.gitignore` files have match semantics as described in the `gitignore`
/// man page.
///
/// This is enabled by default.
pub fn (mut builder IgnoreBuilder) git_ignore(yes bool) &IgnoreBuilder {
	builder.opts.git_ignore = yes
	return builder
}

/// Enables reading `.git/info/exclude` files.
///
/// `.git/info/exclude` files have match semantics as described in the
/// `gitignore` man page.
///
/// This is enabled by default.
pub fn (mut builder IgnoreBuilder) git_exclude(yes bool) &IgnoreBuilder {
	builder.opts.git_exclude = yes
	return builder
}

/// Whether a git repository is required to apply git-related ignore
/// rules (global rules, .gitignore and local exclude rules).
///
/// When disabled, git-related ignore rules are applied even when searching
/// outside a git repository.
pub fn (mut builder IgnoreBuilder) require_git(yes bool) &IgnoreBuilder {
	builder.opts.require_git = yes
	return builder
}

/// Process ignore files case insensitively
///
/// This is disabled by default.
pub fn (mut builder IgnoreBuilder) ignore_case_insensitive(yes bool) &IgnoreBuilder {
	builder.opts.ignore_case_insensitive = yes
	return builder
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
	mut paths := []string{}
	defer {
		unsafe { paths.free() }
	}
	for name in names {
		gipath := join_ignore_path(dir_for_ignorefile, name)
		if os.user_os() == 'windows' || os.exists(gipath) {
			paths << gipath
		} else {
			unsafe { gipath.free() }
		}
	}
	if paths.len == 0 {
		return Gitignore.empty(), false, IgnoreError{}
	}
	mut builder := GitignoreBuilder.new(dir)
	mut errs := PartialErrorBuilder{}
	_, _ = builder.case_insensitive(case_insensitive)
	for gipath in paths {
		add_has_err, add_err := builder.add(gipath)
		errs.maybe_push_ignore_io(add_has_err, add_err)
	}
	gi, build_has_err, build_err := builder.build()
	errs.maybe_push(build_has_err, build_err)
	final_has_err, final_err := errs.into_error_option()
	return gi, final_has_err, final_err
}

fn join_ignore_path(dir string, name string) string {
	$if windows {
		return os.join_path(dir, name)
	}
	if dir == '' {
		return name.to_owned()
	}
	if dir[dir.len - 1] == `/` {
		return dir + name
	}
	return dir + '/' + name
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
	dot_git_line, dot_git_has_err, dot_git_err := read_first_line(git_dir_path)
	if dot_git_has_err {
		return '', true, dot_git_err
	}
	if !dot_git_line.starts_with('gitdir: ') {
		return '', false, IgnoreError{}
	}
	real_git_dir := dot_git_line['gitdir: '.len..]
	git_commondir_file := os.join_path(real_git_dir, 'commondir')
	commondir_line, commondir_has_err, commondir_err := read_first_line(git_commondir_file)
	if commondir_has_err {
		_ = commondir_err
		return '', false, IgnoreError{}
	}
	if commondir_line == '' {
		return '', false, IgnoreError{}
	}
	commondir_abs := if commondir_line.starts_with('.') {
		os.join_path(real_git_dir, commondir_line)
	} else {
		commondir_line
	}
	return commondir_abs, false, IgnoreError{}
}

// Reads the first line with Rust `BufRead::lines().next()` semantics.
fn read_first_line(path string) (string, bool, IgnoreError) {
	contents := os.read_file(path) or { return '', true, io_error(err).with_path(path) }
	if contents == '' {
		return '', false, IgnoreError{}
	}
	line_end := contents.index('\n') or { contents.len }
	mut line := contents[..line_end]
	if line.ends_with('\r') {
		line = line[..line.len - 1]
	}
	if !utf8.validate_str(line) {
		return '', true, io_error(error('stream did not contain valid UTF-8')).with_path(path)
	}
	return line.to_owned(), false, IgnoreError{}
}

// V-specific: return independent owned storage because V string slices do not
// carry the borrow lifetime of `path` in their type.
/// Strips `prefix` from `path` if it's a prefix, otherwise returns `path`
/// unchanged.
fn strip_if_is_prefix[^a](prefix string, path &^a string) string {
	value := *path
	$if unix {
		prefix_len := prefix.len
		if value.starts_with(prefix) {
			return value[prefix_len..].to_owned()
		}
		return value.to_owned()
	} $else {
		return strip_prefix(value, prefix)
	}
}

fn parent_absolute_match_path(absolute_base string, relative_base string, path string) string {
	mut path_to_join := path.to_owned()
	if relative_base != '' && relative_base != '.' {
		mut without_dot_slash := relative_base.clone()
		if relative_base.starts_with('./') {
			without_dot_slash = relative_base[2..].to_owned()
		}
		if path == without_dot_slash.clone() {
			path_to_join = ''
		} else if path.len > without_dot_slash.len && path.starts_with(without_dot_slash.clone())
			&& path[without_dot_slash.len] == os.path_separator[0] {
			path_to_join = path[without_dot_slash.len + 1..].to_owned()
		} else {
			relative_path := strip_if_is_prefix(without_dot_slash.clone(), &path)
			path_to_join = strip_if_is_prefix('/', &relative_path)
		}
	} else if relative_base == '' {
		path_to_join = path
	}
	if path_to_join == '' {
		return absolute_base.to_owned()
	}
	return join_ignore_path(absolute_base, path_to_join)
}

fn (ig &Ignore) any_git_parent() bool {
	mut node := ig.node.get()
	for {
		if node.has_git {
			return true
		}
		node = node.parent_node() or { break }
	}
	return false
}

fn (ig &Ignore) first_relative_dir_after_absolute_path() string {
	mut node := ig.node.get()
	for {
		if !node.is_absolute_parent {
			if node.parent.len > 0 {
				if node.parent[0].get().is_absolute_parent {
					return node.dir
				}
			}
		}
		node = node.parent_node() or { break }
	}
	return ''
}

fn none_string() ?string {
	return none
}

// clone_optional_absolute_base shares the absolute-base path Arc, if present.
// Rust: `Option<Arc<PathBuf>>::clone`.
// none_absolute_base returns the empty-string sentinel `Arc` used when an
// `Ignore` has no absolute base (no parent directories were added).
fn none_absolute_base() arc.Arc[string] {
	return arc.new('')
}

// V-specific: V3 cannot yet synthesize cloning for the private glob-set sum
// type nested inside `Gitignore`, so clone each matcher through its public
// `IClone` implementation until generated nested sum-type cloning is available.
fn clone_gitignores(values []Gitignore) []Gitignore {
	mut cloned := []Gitignore{cap: values.len}
	for value in values {
		cloned << value.clone()
	}
	return cloned
}

fn clone_optional_string(value ?string) ?string {
	if text := value {
		return text.clone()
	}
	return none
}
