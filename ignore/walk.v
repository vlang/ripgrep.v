module ignore

import os
import runtime
import sync
import sync.stdatomic

import time

$if !windows {
	#include <dirent.h>
	fn C.opendir(name &char) voidptr
	fn C.readdir(dirp voidptr) &C.dirent
	fn C.closedir(dirp voidptr) int
}

const stdin_entry_name = '<stdin>'

const dirent_dt_unknown = 0
const dirent_dt_dir = 4
const dirent_dt_reg = 8
const dirent_dt_lnk = 10

fn entry_file_type_from_os(ft os.FileType) os.FileType {
	return ft
}

fn followed_path_info(path string) !os.Stat {
	resolved := os.real_path(path)
	return os.lstat(resolved)
}

struct StdinEntry {}

struct DirEntryRaw implements IClone {
	// V strings are length-delimited byte strings. On Unix this preserves the
	// same arbitrary non-NUL path bytes represented by Rust's `OsStr`.
	path              string
	file_name_value   string
	ty                os.FileType
	follow_link       bool
	depth             usize
	metadata          os.Stat
	ino_value         u64
}

fn (raw &DirEntryRaw) clone() DirEntryRaw {
	return DirEntryRaw{
		path:              raw.path.clone()
		file_name_value:   raw.file_name_value.clone()
		ty:                raw.ty
		follow_link:       raw.follow_link
		depth:             raw.depth
		metadata:          raw.metadata
		ino_value:         raw.ino_value
	}
}

struct DirChild {
	name     string
	ty       os.FileType
	has_type bool
	ino      u64
}

/// A directory entry with a possible error attached.
///
/// The error typically refers to a problem parsing ignore files in a
/// particular directory.
pub struct DirEntry implements IClone {
mut:
	// V-specific explicit representation of Rust's private DirEntryInner enum.
	// Keeping the raw entry inline avoids a heap-allocated sum-type payload and
	// lets path/file_name return borrows without duplicate cache strings.
	raw         DirEntryRaw
	stdin_value bool
	err         ?IgnoreError
}

pub fn (d &DirEntry) clone() DirEntry {
	mut cloned_err := ?IgnoreError(none)
	if err := d.err {
		cloned_err = err.clone()
	}
	return DirEntry{
		raw:         if d.stdin_value { DirEntryRaw{} } else { d.raw.clone() }
		stdin_value: d.stdin_value
		err:         cloned_err
	}
}

fn none_ignore_error() ?IgnoreError {
	return none
}

/// The full path that this entry represents.
pub fn (d &^a DirEntry) path[^a]() &^a string {
	if d.stdin_value {
		return &stdin_entry_name
	}
	return &d.raw.path
}

// V-specific: releases storage owned by a completed walk result.
pub fn (mut d DirEntry) free() {
	if !d.stdin_value {
		unsafe {
			d.raw.path.free()
			d.raw.file_name_value.free()
		}
	}
	if mut err := d.err {
		err.free()
		d.err = ?IgnoreError(none)
	}
	d.raw.path = ''
	d.raw.file_name_value = ''
}

/// The full path that this entry represents.
/// Analogous to [`DirEntry::path`], but moves ownership of the path.
pub fn (mut d DirEntry) into_path() string {
	if d.stdin_value {
		return stdin_entry_name.to_owned()
	}
	path := d.raw.path
	d.raw.path = ''
	unsafe { d.raw.file_name_value.free() }
	d.raw.file_name_value = ''
	if mut err := d.err {
		err.free()
		d.err = ?IgnoreError(none)
	}
	return path
}

/// Whether this entry corresponds to a symbolic link or not.
pub fn (d &DirEntry) path_is_symlink() bool {
	if d.stdin_value {
		return false
	}
	return d.raw.path_is_symlink()
}

/// Returns true if and only if this entry corresponds to stdin.
///
/// i.e., The entry has depth 0 and its file name is `-`.
pub fn (d &DirEntry) is_stdin() bool {
	return d.stdin_value
}

/// Return the metadata for the file that this entry points to.
pub fn (d &DirEntry) metadata() !os.Stat {
	if d.stdin_value {
		return io_error(error('<stdin> has no metadata')).with_path(stdin_entry_name)
	}
	return d.raw.metadata()
}

/// Return the file type for the file that this entry points to.
///
/// This entry doesn't have a file type if it corresponds to stdin.
pub fn (d &DirEntry) file_type() ?os.FileType {
	if d.stdin_value {
		return none
	}
	return d.raw.file_type()
}

/// Return the file name of this entry.
///
/// If this entry has no file name (e.g., `/`), then the full path is
/// returned.
pub fn (d &^a DirEntry) file_name[^a]() &^a string {
	if d.stdin_value {
		return &stdin_entry_name
	}
	return &d.raw.file_name_value
}

/// Returns the depth at which this entry was created relative to the root.
pub fn (d &DirEntry) depth() usize {
	if d.stdin_value {
		return 0
	}
	return d.raw.depth
}

/// Returns the underlying inode number if one exists.
///
/// If this entry doesn't have an inode number, then `None` is returned.
pub fn (d &DirEntry) ino() ?u64 {
	if d.stdin_value {
		return none
	}
	return d.raw.ino()
}

/// Returns an error, if one exists, associated with processing this entry.
///
/// An example of an error is one that occurred while parsing an ignore
/// file. Errors related to traversing a directory tree itself are reported
/// as part of yielding the directory entry, and not with this method.
pub fn (d &^a DirEntry) error[^a]() ?&^a IgnoreError {
	if d.err != none {
		return unsafe { &d.err? }
	}
	return none
}

/// Returns true if and only if this entry points to a directory.
pub fn (d &DirEntry) is_dir() bool {
	if file_type := d.file_type() {
		return file_type == .directory
	}
	return false
}

fn DirEntry.new_stdin() DirEntry {
	return DirEntry{
		raw:         DirEntryRaw{}
		stdin_value: true
		err:         none
	}
}

fn DirEntry.new_raw(dent DirEntryRaw, err ?IgnoreError) DirEntry {
	mut entry := DirEntry{
		raw:         dent
		stdin_value: false
		err:         none
	}
	if value := err {
		entry.err = value
	}
	return entry
}

fn (raw &DirEntryRaw) path_is_symlink() bool {
	return raw.ty == .symbolic_link || raw.follow_link
}

fn (raw &DirEntryRaw) metadata() !os.Stat {
	$if windows {
		if !raw.follow_link {
			return raw.metadata
		}
	}
	return if raw.follow_link {
		followed_path_info(raw.path) or { return io_error(err).with_path(raw.path) }
	} else {
		os.lstat(raw.path) or { return io_error(err).with_path(raw.path) }
	}
}

fn (raw &DirEntryRaw) file_type() os.FileType {
	return raw.ty
}

fn (raw &DirEntryRaw) ino() ?u64 {
	$if linux || macos || freebsd || openbsd || netbsd || dragonfly || solaris {
		return raw.ino_value
	} $else {
		return none
	}
}

fn (raw &^a DirEntryRaw) file_name[^a]() &^a string {
	return &raw.file_name_value
}

fn DirEntryRaw.from_path(depth usize, path string, link bool) !DirEntryRaw {
	info := followed_path_info(path) or { return err }
	ty := entry_file_type_from_os(info.get_filetype())
	name := file_name(path)
	return DirEntryRaw{
		path:              path.to_owned()
		file_name_value:   if name == '' { path.to_owned() } else { name.to_owned() }
		ty:                ty
		follow_link:       link
		depth:             depth
		metadata:          info
		ino_value:         info.inode
	}
}

fn DirEntryRaw.from_child(depth usize, parent_path string, name string) !DirEntryRaw {
	path := join_child_path(parent_path, name)
	info := os.lstat(path) or { return err }
	ty := entry_file_type_from_os(info.get_filetype())
	return DirEntryRaw{
		path:            path
		file_name_value: name.to_owned()
		ty:              ty
		follow_link:     false
		depth:           depth
		metadata:        info
		ino_value:       info.inode
	}
}

fn DirEntryRaw.from_child_known(depth usize, parent_path string, name string, ty os.FileType, ino u64) DirEntryRaw {
	path := join_child_path(parent_path, name)
	return DirEntryRaw{
		path:              path
		file_name_value:   name.to_owned()
		ty:                ty
		follow_link:       false
		depth:             depth
		metadata:          os.Stat{}
		ino_value:         ino
	}
}

fn join_child_path(parent_path string, name string) string {
	$if windows {
		return os.join_path(parent_path, name)
	}
	if parent_path == '' {
		return name.to_owned()
	}
	if parent_path[parent_path.len - 1] == `/` {
		return parent_path + name
	}
	return parent_path + '/' + name
}

// Result item produced by the V walk APIs.
//
// The original Rust iterator yields `Result<DirEntry, Error>`. This port keeps
// the same shape explicitly in a struct so it can be used from both the
// sequential and visitor-style APIs.
pub struct WalkResult {
pub:
	is_error bool
	entry    DirEntry
	err      IgnoreError
}

// V-specific: releases a result after its visitor has returned.
pub fn (mut result WalkResult) free() {
	result.entry.free()
	result.err.free()
}

fn walk_result_from_entry(entry DirEntry) WalkResult {
	return WalkResult{
		is_error: false
		entry:    entry
		err:      IgnoreError{}
	}
}

fn walk_result_from_error(err IgnoreError) WalkResult {
	return WalkResult{
		is_error: true
		entry:    DirEntry.new_stdin()
		err:      err
	}
}

/// WalkState is used in the parallel recursive directory iterator to indicate
/// whether walking should continue as normal, skip descending into a
/// particular directory or quit the walk entirely.
pub enum WalkState {
	/// Continue walking as normal.
	continue_
	/// If the directory entry given is a directory, don't descend into it.
	/// In all other cases, this has no effect.
	skip
	/// Quit the entire iterator as soon as possible.
	///
	/// Note that this is an inherently asynchronous action. It is possible
	/// for more entries to be yielded even after instructing the iterator
	/// to quit.
	quit
}

fn (ws WalkState) is_continue() bool {
	return ws == .continue_
}

fn (ws WalkState) is_quit() bool {
	return ws == .quit
}

pub type NameComparator = fn (&string, &string) int
pub type PathComparator = fn (&string, &string) int
pub type FilterFn = fn (&DirEntry) bool

/// Receives files and directories for the current thread.
///
/// Setup for the traversal can be implemented as part of
/// [`ParallelVisitorFactory::create`]. Teardown when traversal finishes is
/// implemented by the V-specific `free` ownership hook.
pub interface ParallelVisitor {
mut:
	/// Receives files and directories for the current thread. This is called
	/// once for every directory entry visited by traversal.
	visit(entry WalkResult) WalkState
	// V-specific ownership hook for visitor boxes returned by a factory.
	free()
}

/// A builder for constructing a visitor when using [`WalkParallel::visit`].
/// The builder will be called for each thread started by `WalkParallel`. The
/// visitor returned from each builder is then called for every directory
/// entry.
pub interface ParallelVisitorFactory {
mut:
	/// Create per-thread `ParallelVisitor`s for `WalkParallel`.
	create() ParallelVisitor
}

fn free_parallel_visitor(visitor ParallelVisitor) {
	mut owned := visitor
	owned.free()
}

struct NoopParallelVisitor {}

fn (mut visitor NoopParallelVisitor) visit(entry WalkResult) WalkState {
	_ = entry
	return .continue_
}

fn (mut visitor NoopParallelVisitor) free() {
	unsafe { free(&visitor) }
}

// Handle used for path equality checks, for example when skipping stdout.
struct Handle {
pub:
	path      string
	dev       u64
	ino       u64
	is_stdout bool
}

fn Handle.from_path(path string) !Handle {
	info := followed_path_info(path) or { return err }
	return Handle{
		path:      os.real_path(path).to_owned()
		dev:       info.dev
		ino:       info.inode
		is_stdout: false
	}
}

fn (left Handle) same_file(right Handle) bool {
	return left.dev == right.dev && left.ino == right.ino
}

// Returns a handle to stdout for filtering search.
//
// A handle is returned if and only if stdout is being redirected to a file.
// The handle returned corresponds to that file.
//
// This can be used to ensure that we do not attempt to search a file that we
// may also be writing to.
fn stdout_handle() (bool, Handle) {
	$if windows {
		return false, Handle{}
	} $else {
		info := followed_path_info('/dev/fd/1') or {
			return false, Handle{}
		}
		if info.get_filetype() != .regular {
			return false, Handle{}
		}
		return true, Handle{
			path:      os.real_path('/dev/fd/1').to_owned()
			dev:       info.dev
			ino:       info.inode
			is_stdout: true
		}
	}
}

/// WalkBuilder builds a recursive directory iterator.
///
/// The builder supports a large number of configurable options. This includes
/// specific glob overrides, file type matching, toggling whether hidden
/// files are ignored or not, and of course, support for respecting gitignore
/// files.
///
/// By default, all ignore files found are respected. This includes `.ignore`,
/// `.gitignore`, `.git/info/exclude` and even your global gitignore
/// globs, usually found in `$XDG_CONFIG_HOME/git/ignore`.
///
/// Some standard recursive directory options are also supported, such as
/// limiting the recursive depth or whether to follow symbolic links (disabled
/// by default).
///
/// # Ignore rules
///
/// There are many rules that influence whether a particular file or directory
/// is skipped by this iterator. Those rules are documented here. Note that
/// the rules assume a default configuration.
///
/// * First, glob overrides are checked. If a path matches a glob override,
/// then matching stops. The path is then only skipped if the glob that matched
/// the path is an ignore glob. (An override glob is a whitelist glob unless it
/// starts with a `!`, in which case it is an ignore glob.)
/// * Second, ignore files are checked. Ignore files currently only come from
/// git ignore files (`.gitignore`, `.git/info/exclude` and the configured
/// global gitignore file), plain `.ignore` files, which have the same format
/// as gitignore files, or explicitly added ignore files. The precedence order
/// is: `.ignore`, `.gitignore`, `.git/info/exclude`, global gitignore and
/// finally explicitly added ignore files. Note that precedence between
/// different types of ignore files is not impacted by the directory hierarchy;
/// any `.ignore` file overrides all `.gitignore` files. Within each precedence
/// level, more nested ignore files have a higher precedence than less nested
/// ignore files.
/// * Third, if the previous step yields an ignore match, then all matching
/// is stopped and the path is skipped. If it yields a whitelist match, then
/// matching continues. A whitelist match can be overridden by a later matcher.
/// * Fourth, unless the path is a directory, the file type matcher is run on
/// the path. As above, if it yields an ignore match, then all matching is
/// stopped and the path is skipped. If it yields a whitelist match, then
/// matching continues.
/// * Fifth, if the path hasn't been whitelisted and it is hidden, then the
/// path is skipped.
/// * Sixth, unless the path is a directory, the size of the file is compared
/// against the max filesize limit. If it exceeds the limit, it is skipped.
/// * Seventh, if the path has made it this far then it is yielded in the
/// iterator.
pub struct WalkBuilder implements IClone {
mut:
	paths            []string
	ig_builder       IgnoreBuilder
	max_depth        ?usize
	min_depth        ?usize
	max_filesize     ?u64
	follow_links     bool
	same_file_system bool
	threads          usize
	skip             ?Handle
	// V-specific: Rust stores callback slots as `Option<Fn>`. The port keeps
	// function pointers with explicit presence bits because optional function
	// fields are not reliable in the current ownership frontend.
	filter           FilterFn = unsafe { nil }
	has_filter       bool
	sort_by_name     NameComparator = unsafe { nil }
	has_sort_by_name bool
	sort_by_path     PathComparator = unsafe { nil }
	has_sort_by_path bool
	/// The directory that gitignores should be interpreted relative to.
	///
	/// Usually this is the directory containing the gitignore file. But in
	/// some cases, like for global gitignores or for gitignores specified
	/// explicitly, this should generally be set to the current working
	/// directory. This is only used for global gitignores or "explicit"
	/// gitignores.
	///
	/// When `None`, the CWD is fetched from `std::env::current_dir()`. If
	/// that fails, then global gitignores are ignored (an error is logged).
	cwd_mutex        &sync.Mutex
	cwd_initialized  bool
	cwd_value        string
}

/// Create a new builder for a recursive directory iterator for the
/// directory given.
///
/// Note that if you want to traverse multiple different directories, it
/// is better to call `add` on this builder than to create multiple
/// `Walk` values.
pub fn WalkBuilder.new(path string) WalkBuilder {
	return WalkBuilder{
		paths:            [path.to_owned()]
		ig_builder:       IgnoreBuilder.new()
		cwd_mutex:        sync.new_mutex()
		cwd_initialized:  false
		cwd_value:        ''.to_owned()
	}
}

/// Build a new `Walk` iterator.
pub fn (builder &WalkBuilder) build() Walk {
	cwd := builder.get_or_set_current_dir()
	ig_root := if *cwd != '' {
		builder.ig_builder.build_with_cwd(?string((*cwd).clone()))
	} else {
		builder.ig_builder.build()
	}
	return Walk{
		paths:            builder.paths.clone()
		ig_root:          ig_root
		ig:               ig_root
		max_filesize:     builder.max_filesize
		skip:             builder.skip
		filter:           builder.filter
		has_filter:       builder.has_filter
		min_depth:        builder.min_depth
		max_depth:        builder.max_depth
		follow_links:     builder.follow_links
		same_file_system: builder.same_file_system
		has_sort_by_name: builder.has_sort_by_name
		sort_by_name:     builder.sort_by_name
		has_sort_by_path: builder.has_sort_by_path
		sort_by_path:     builder.sort_by_path
	}
}

/// Build a new `WalkParallel` iterator.
///
/// Note that this *doesn't* return something that implements `Iterator`.
/// Instead, the returned value must be run with a `ParallelVisitorFactory`.
pub fn (builder &WalkBuilder) build_parallel() WalkParallel {
	cwd := builder.get_or_set_current_dir()
	ig_root := if *cwd != '' {
		builder.ig_builder.build_with_cwd(?string((*cwd).clone()))
	} else {
		builder.ig_builder.build()
	}
	return WalkParallel{
		paths:            builder.paths.clone()
		ig_root:          ig_root
		max_filesize:     builder.max_filesize
		max_depth:        builder.max_depth
		min_depth:        builder.min_depth
		follow_links:     builder.follow_links
		same_file_system: builder.same_file_system
		threads:          builder.threads
		skip:             builder.skip
		filter:           builder.filter
		has_filter:       builder.has_filter
	}
}

/// Add a file path to the iterator.
///
/// Each additional file path added is traversed recursively. This should
/// be preferred over building multiple `Walk` iterators since this
/// enables reusing resources across iteration.
pub fn (mut builder WalkBuilder) add(path string) &WalkBuilder {
	builder.paths << path.to_owned()
	return builder
}

/// The maximum depth to recurse.
///
/// The default, `None`, imposes no depth restriction.
pub fn (mut builder WalkBuilder) max_depth(depth ?usize) &WalkBuilder {
	builder.max_depth = depth
	if min_depth := builder.min_depth {
		if max_depth := builder.max_depth {
			if max_depth < min_depth {
				builder.max_depth = min_depth
			}
		}
	}
	return builder
}

/// The minimum depth to recurse.
///
/// The default, `None`, imposes no minimum depth restriction.
pub fn (mut builder WalkBuilder) min_depth(depth ?usize) &WalkBuilder {
	builder.min_depth = depth
	if max_depth := builder.max_depth {
		if min_depth := builder.min_depth {
			if min_depth > max_depth {
				builder.min_depth = max_depth
			}
		}
	}
	return builder
}

/// Whether to follow symbolic links or not.
pub fn (mut builder WalkBuilder) follow_links(yes bool) &WalkBuilder {
	builder.follow_links = yes
	return builder
}

/// Whether to ignore files above the specified limit.
pub fn (mut builder WalkBuilder) max_filesize(filesize ?u64) &WalkBuilder {
	builder.max_filesize = filesize
	return builder
}

/// The number of threads to use for traversal.
///
/// Note that this only has an effect when using `build_parallel`.
///
/// The default setting is `0`, which chooses the number of threads
/// automatically using heuristics.
pub fn (mut builder WalkBuilder) threads(n usize) &WalkBuilder {
	builder.threads = n
	return builder
}

/// Add a global ignore file to the matcher.
///
/// This has lower precedence than all other sources of ignore rules.
///
/// # Errors
///
/// If there was a problem adding the ignore file, then an error is
/// returned. Note that the error may indicate *partial* failure. For
/// example, if an ignore file contains an invalid glob, all other globs
/// are still applied.
///
/// An error will also occur if this walker could not get the current
/// working directory (and `WalkBuilder::current_dir` isn't set).
pub fn (mut builder WalkBuilder) add_ignore(path string) (bool, IgnoreError) {
	cwd := builder.get_or_set_current_dir()
	if *cwd == '' {
		return true, other_error('CWD is not known, ignoring global gitignore ${path}')
	}
	mut gitignore_builder := GitignoreBuilder.new((*cwd).clone())
	mut errs := PartialErrorBuilder{}
	add_has_err, add_err := gitignore_builder.add(path)
	errs.maybe_push(add_has_err, add_err)
	gi, build_has_err, build_err := gitignore_builder.build()
	errs.maybe_push(build_has_err, build_err)
	if !build_has_err {
		builder.ig_builder.add_ignore(gi)
	}
	return errs.into_error_option()
}

/// Add a custom ignore file name
///
/// These ignore files have higher precedence than all other ignore files.
///
/// When specifying multiple names, earlier names have lower precedence than
/// later names.
pub fn (mut builder WalkBuilder) add_custom_ignore_filename(file_name string) &WalkBuilder {
	builder.ig_builder.add_custom_ignore_filename(file_name)
	return builder
}

/// Add an override matcher.
///
/// By default, no override matcher is used.
///
/// This overrides any previous setting.
pub fn (mut builder WalkBuilder) overrides(overrides Override) &WalkBuilder {
	builder.ig_builder.overrides(overrides)
	return builder
}

/// Add a file type matcher.
///
/// By default, no file type matcher is used.
///
/// This overrides any previous setting.
pub fn (mut builder WalkBuilder) types(types Types) &WalkBuilder {
	builder.ig_builder.types(types)
	return builder
}

/// Enables all the standard ignore filters.
///
/// This toggles, as a group, all the filters that are enabled by default:
///
/// - [hidden()](#method.hidden)
/// - [parents()](#method.parents)
/// - [ignore()](#method.ignore)
/// - [git_ignore()](#method.git_ignore)
/// - [git_global()](#method.git_global)
/// - [git_exclude()](#method.git_exclude)
///
/// They may still be toggled individually after calling this function.
///
/// This is (by definition) enabled by default.
pub fn (mut builder WalkBuilder) standard_filters(yes bool) &WalkBuilder {
	builder.hidden(yes)
	builder.parents(yes)
	builder.ignore(yes)
	builder.git_ignore(yes)
	builder.git_global(yes)
	builder.git_exclude(yes)
	return builder
}

/// Enables ignoring hidden files.
///
/// This is enabled by default.
pub fn (mut builder WalkBuilder) hidden(yes bool) &WalkBuilder {
	builder.ig_builder.hidden(yes)
	return builder
}

/// Enables reading ignore files from parent directories.
///
/// If this is enabled, then .gitignore files in parent directories of each
/// file path given are respected. Otherwise, they are ignored.
///
/// This is enabled by default.
pub fn (mut builder WalkBuilder) parents(yes bool) &WalkBuilder {
	builder.ig_builder.parents(yes)
	return builder
}

/// Enables reading `.ignore` files.
///
/// `.ignore` files have the same semantics as `gitignore` files and are
/// supported by search tools such as ripgrep and The Silver Searcher.
///
/// This is enabled by default.
pub fn (mut builder WalkBuilder) ignore(yes bool) &WalkBuilder {
	builder.ig_builder.ignore(yes)
	return builder
}

/// Enables reading a global gitignore file, whose path is specified in
/// git's `core.excludesFile` config option.
///
/// Git's config file location is `$HOME/.gitconfig`. If `$HOME/.gitconfig`
/// does not exist or does not specify `core.excludesFile`, then
/// `$XDG_CONFIG_HOME/git/ignore` is read. If `$XDG_CONFIG_HOME` is not
/// set or is empty, then `$HOME/.config/git/ignore` is used instead.
///
/// This is enabled by default.
pub fn (mut builder WalkBuilder) git_global(yes bool) &WalkBuilder {
	builder.ig_builder.git_global(yes)
	return builder
}

/// Enables reading `.gitignore` files.
///
/// `.gitignore` files have match semantics as described in the `gitignore`
/// man page.
///
/// This is enabled by default.
pub fn (mut builder WalkBuilder) git_ignore(yes bool) &WalkBuilder {
	builder.ig_builder.git_ignore(yes)
	return builder
}

/// Enables reading `.git/info/exclude` files.
///
/// `.git/info/exclude` files have match semantics as described in the
/// `gitignore` man page.
///
/// This is enabled by default.
pub fn (mut builder WalkBuilder) git_exclude(yes bool) &WalkBuilder {
	builder.ig_builder.git_exclude(yes)
	return builder
}

/// Whether a git repository is required to apply git-related ignore
/// rules (global rules, .gitignore and local exclude rules).
///
/// When disabled, git-related ignore rules are applied even when searching
/// outside a git repository.
///
/// In particular, if this is `false` then `.gitignore` files will be read
/// from parent directories above the git root directory containing `.git`,
/// which is different from the git behavior.
pub fn (mut builder WalkBuilder) require_git(yes bool) &WalkBuilder {
	builder.ig_builder.require_git(yes)
	return builder
}

/// Process ignore files case insensitively
///
/// This is disabled by default.
pub fn (mut builder WalkBuilder) ignore_case_insensitive(yes bool) &WalkBuilder {
	builder.ig_builder.ignore_case_insensitive(yes)
	return builder
}

/// Set a function for sorting directory entries by their path.
///
/// If a compare function is set, the resulting iterator will return all
/// paths in sorted order. The compare function will be called to compare
/// entries from the same directory.
///
/// This is like `sort_by_file_name`, except the comparator accepts
/// a `&string` path instead of the base file name, which permits it to sort by
/// more criteria.
///
/// This method will override any previous sorter set by this method or
/// by `sort_by_file_name`.
///
/// Note that this is not used in the parallel iterator.
pub fn (mut builder WalkBuilder) sort_by_file_path(cmp PathComparator) &WalkBuilder {
	builder.sort_by_path = cmp
	builder.has_sort_by_path = true
	builder.has_sort_by_name = false
	return builder
}

/// Set a function for sorting directory entries by file name.
///
/// If a compare function is set, the resulting iterator will return all
/// paths in sorted order. The compare function will be called to compare
/// names from entries from the same directory using only the name of the
/// entry.
///
/// This method will override any previous sorter set by this method or
/// by `sort_by_file_path`.
///
/// Note that this is not used in the parallel iterator.
pub fn (mut builder WalkBuilder) sort_by_file_name(cmp NameComparator) &WalkBuilder {
	builder.sort_by_name = cmp
	builder.has_sort_by_name = true
	builder.has_sort_by_path = false
	return builder
}

/// Do not cross file system boundaries.
///
/// When this option is enabled, directory traversal will not descend into
/// directories that are on a different file system from the root path.
///
/// Currently, this option is only supported on Unix and Windows. If this
/// option is used on an unsupported platform, then directory traversal
/// will immediately return an error and will not yield any entries.
pub fn (mut builder WalkBuilder) same_file_system(yes bool) &WalkBuilder {
	builder.same_file_system = yes
	return builder
}

/// Do not yield directory entries that are believed to correspond to
/// stdout.
///
/// This is useful when a command is invoked via shell redirection to a
/// file that is also being read. For example, `grep -r foo ./ > results`
/// might end up trying to search `results` even though it is also writing
/// to it, which could cause an unbounded feedback loop. Setting this
/// option prevents this from happening by skipping over the `results`
/// file.
///
/// This is disabled by default.
pub fn (mut builder WalkBuilder) skip_stdout(yes bool) &WalkBuilder {
	if yes {
		has_handle, handle := stdout_handle()
		builder.skip = if has_handle { handle } else { none }
	} else {
		builder.skip = none
	}
	return builder
}

/// Yields only entries which satisfy the given predicate and skips
/// descending into directories that do not satisfy the given predicate.
///
/// The predicate is applied to all entries. If the predicate is
/// true, iteration carries on as normal. If the predicate is false, the
/// entry is ignored and if it is a directory, it is not descended into.
///
/// Note that the errors for reading entries that may not satisfy the
/// predicate will still be yielded.
///
/// Note also that only one filter predicate can be applied to a
/// `WalkBuilder`. Calling this subsequent times overrides previous filter
/// predicates.
pub fn (mut builder WalkBuilder) filter_entry(filter FilterFn) &WalkBuilder {
	builder.filter = filter
	builder.has_filter = true
	return builder
}

/// Set the current working directory used for matching global gitignores.
///
/// If this is not set, then this walker will attempt to discover the
/// correct path from the environment's current working directory. If
/// that fails, then global gitignore files will be ignored.
///
/// Global gitignore files come from things like a user's git configuration
/// or from gitignore files added via [`WalkBuilder::add_ignore`].
pub fn (mut builder WalkBuilder) current_dir(cwd string) &WalkBuilder {
	builder.ig_builder.current_dir(cwd)
	builder.cwd_initialized = true
	builder.cwd_value = cwd.to_owned()
	return builder
}

/// Gets the currently configured CWD on this walk builder.
///
/// This is "lazy." That is, we only ask for the CWD from the environment
/// if `WalkBuilder::current_dir` hasn't been called yet. And we ensure
/// that we only do it once.
fn (builder &^a WalkBuilder) get_or_set_current_dir[^a]() &^a string {
	builder.cwd_mutex.lock()
	if !builder.cwd_initialized {
		cwd := os.getwd()
		unsafe {
			mut builder_mut := &WalkBuilder(builder)
			builder_mut.cwd_value = cwd.to_owned()
			builder_mut.cwd_initialized = true
		}
	}
	builder.cwd_mutex.unlock()
	return &builder.cwd_value
}

/// Walk is a recursive directory iterator over file paths in one or more
/// directories.
///
/// Only file and directory paths matching the rules are returned. By default,
/// ignore files like `.gitignore` are respected. The precise matching rules
/// and precedence is explained in the documentation for `WalkBuilder`.
pub struct Walk {
mut:
	paths            []string
	root_index       int
	pending          []WalkResult
	pending_index    int
	stack            []WalkFrame
	ig_root          Ignore
	ig               Ignore
	max_filesize     ?u64
	skip             ?Handle
	// V-specific: see `WalkBuilder.filter`.
	filter           FilterFn = unsafe { nil }
	has_filter       bool
	min_depth        ?usize
	max_depth        ?usize
	follow_links     bool
	same_file_system bool
	sort_by_name     NameComparator = unsafe { nil }
	has_sort_by_name bool
	sort_by_path     PathComparator = unsafe { nil }
	has_sort_by_path bool
	gitignore_matches []usize
}

struct WalkFrame {
	parent_path     string
	parent_depth    usize
	ig              Ignore
	children        []DirChild
	next_index      int
	root_device     u64
	has_root_device bool
}

fn (mut frame WalkFrame) free() {
	for child in frame.children {
		unsafe { child.name.free() }
	}
	unsafe {
		frame.parent_path.free()
		frame.children.free()
	}
	frame.ig.free_nodes()
	frame.parent_path = ''
	frame.children = []DirChild{}
}

/// Creates a new recursive directory iterator for the file path given.
///
/// Note that this uses default settings, which include respecting
/// `.gitignore` files. To configure the iterator, use `WalkBuilder`
/// instead.
pub fn Walk.new(path string) Walk {
	return WalkBuilder.new(path).build()
}

// Returns the next walk result, or `none` when iteration is finished.
pub fn (mut walk Walk) next() ?WalkResult {
	for {
		if result := walk.pop_pending() {
			return result
		}
		if walk.advance_stack() {
			continue
		}
		if walk.root_index >= walk.paths.len {
			return none
		}
		path := walk.paths[walk.root_index]
		walk.root_index++
		walk.enqueue_root_path(path)
	}
}

// Returns all currently buffered walk results.
pub fn (walk Walk) items() []WalkResult {
	if walk.pending_index >= walk.pending.len {
		return []WalkResult{}
	}
	return walk.pending[walk.pending_index..].clone()
}

fn (mut walk Walk) push_result(result WalkResult) {
	walk.pending << result
}

fn (mut walk Walk) add_root_path(path string) {
	walk.paths << path.to_owned()
}

fn (mut walk Walk) pop_pending() ?WalkResult {
	if walk.pending_index >= walk.pending.len {
		unsafe { walk.pending.free() }
		walk.pending = []WalkResult{}
		walk.pending_index = 0
		return none
	}
	result := walk.pending[walk.pending_index]
	walk.pending_index++
	return result
}

fn (mut walk Walk) enqueue_root_path(path string) {
	if path == '-' {
		walk.push_result(walk_result_from_entry(DirEntry.new_stdin()))
		return
	}
	root, err := prepare_root_entry(path, walk.follow_links)
	if err.kind != .other || err.message != '' {
		walk.push_result(walk_result_from_error(err))
		return
	}
	mut dent := root
	mut ig := walk.ig_root.clone()
	if dent.is_dir() {
		ig2, has_err, add_err := walk.ig_root.add_parents(dent.path())
		ig.free_nodes()
		ig = ig2
		if has_err {
			walk.push_result(walk_result_from_error(add_err))
		}
	}
	mut root_device := u64(0)
	if walk.same_file_system {
		root_device = device_num(dent.path()) or {
			walk.push_result(walk_result_from_error(io_error(err).with_path(dent.path())))
			return
		}
	}
	has_root_device := walk.same_file_system
	walk.enqueue_entry(mut dent, ig, true, root_device, has_root_device)
}

fn (mut walk Walk) advance_stack() bool {
	for walk.stack.len > 0 {
		last := walk.stack.len - 1
		mut frame := walk.stack[last]
		if frame.next_index >= frame.children.len {
			walk.stack.delete(last)
			frame.free()
			continue
		}
		child_entry := frame.children[frame.next_index]
		frame.next_index++
		walk.stack[last] = frame
		walk.enqueue_child(frame, child_entry)
		return true
	}
	return false
}

fn (mut walk Walk) enqueue_child(frame WalkFrame, child_entry DirChild) {
	child_depth := frame.parent_depth + 1
	mut child_raw := if child_entry.has_type && walk.can_trust_dirent_type() {
		DirEntryRaw.from_child_known(child_depth, frame.parent_path, child_entry.name, child_entry.ty,
			child_entry.ino)
	} else {
		DirEntryRaw.from_child(child_depth, frame.parent_path, child_entry.name) or {
			walk.push_result(walk_result_from_error(io_error(err).with_path(os.join_path(frame.parent_path,
				child_entry.name)).with_depth(child_depth)))
			return
		}
	}
	if walk.follow_links && child_raw.path_is_symlink() {
		child_path := child_raw.path.clone()
		child_raw = DirEntryRaw.from_path(child_depth, child_path, true) or {
			walk.push_result(walk_result_from_error(io_error(err).with_path(os.join_path(frame.parent_path,
				child_entry.name)).with_depth(child_depth)))
			return
		}
		if child_raw.ty == .directory {
			if err := check_symlink_loop(frame.ig, child_raw.path.clone(), child_depth) {
				walk.push_result(walk_result_from_error(err))
				return
			}
		}
	}
	mut child := DirEntry.new_raw(child_raw, none_ignore_error())
	walk.enqueue_entry(mut child, frame.ig.clone(), false, frame.root_device, frame.has_root_device)
}

fn (mut walk Walk) enqueue_entry(mut dent DirEntry, mut ig Ignore, is_root bool, root_device u64, has_root_device bool) {
	defer {
		ig.free_nodes()
	}
	should_visit := if min_depth := walk.min_depth {
		dent.depth() >= min_depth
	} else {
		true
	}
	if !dent.is_dir() {
		if !is_root {
			should_skip := walk.skip_entry(&ig, &dent) or {
				walk.push_result(walk_result_from_error(ignore_error_from_ierror(err)))
				dent.free()
				return
			}
			if should_skip {
				dent.free()
				return
			}
		}
		if should_visit {
			walk.push_result(walk_result_from_entry(dent))
		} else {
			dent.free()
		}
		return
	}
	defer {
		dent.free()
	}
	if !is_root {
		should_skip := walk.skip_entry(&ig, &dent) or {
			walk.push_result(walk_result_from_error(ignore_error_from_ierror(err)))
			return
		}
		if should_skip {
			return
		}
	}

	mut descend := true
	if has_root_device {
		descend = is_same_file_system(root_device, dent.path()) or {
			walk.push_result(walk_result_from_error(io_error(err).with_path(dent.path()).with_depth(dent.depth())))
			false
		}
	}

	mut child_ignore, has_child_err, child_err := ig.add_child(dent.path())
	defer {
		child_ignore.free_nodes()
	}
	if has_child_err {
		dent.err = child_err
	} else {
		dent.err = none
	}
	if should_visit {
		walk.push_result(walk_result_from_entry(dent.clone()))
	}
	if !descend {
		return
	}
	if max_depth := walk.max_depth {
		if dent.depth() >= max_depth {
			return
		}
	}
	children := walk.read_dir_children(dent.path()) or {
		walk.push_result(walk_result_from_error(io_error(err).with_path(dent.path()).with_depth(dent.depth())))
		return
	}
	walk.stack << WalkFrame{
		parent_path:     (*dent.path()).to_owned()
		parent_depth:    dent.depth()
		ig:              child_ignore.clone()
		children:        children
		root_device:     root_device
		has_root_device: has_root_device
	}
}

fn (mut walk Walk) visit_root_path(mut visitor ParallelVisitor, path string) WalkState {
	if path == '-' {
		if min_depth := walk.min_depth {
			if min_depth == 0 {
				return visitor.visit(walk_result_from_entry(DirEntry.new_stdin()))
			}
		} else {
			return visitor.visit(walk_result_from_entry(DirEntry.new_stdin()))
		}
		return .continue_
	}
	root, err := prepare_root_entry(path, walk.follow_links)
	if err.kind != .other || err.message != '' {
		return visitor.visit(walk_result_from_error(err))
	}
	mut dent := root
	mut ig := walk.ig_root.clone()
	if dent.is_dir() {
		ig2, has_err, add_err := walk.ig_root.add_parents(dent.path())
		ig.free_nodes()
		ig = ig2
		if has_err {
			state := visitor.visit(walk_result_from_error(add_err))
			if state.is_quit() {
				ig.free_nodes()
				return .quit
			}
		}
	}
	mut root_device := u64(0)
	if walk.same_file_system {
		root_device = device_num(dent.path()) or {
			state := visitor.visit(walk_result_from_error(io_error(err).with_path(dent.path())))
			if state.is_quit() {
				ig.free_nodes()
				return .quit
			}
			ig.free_nodes()
			return .continue_
		}
	}
	has_root_device := walk.same_file_system
	return walk.visit_traverse_entry(mut visitor, mut dent, ig, true, root_device, has_root_device)
}

fn (mut walk Walk) traverse_entry(mut dent DirEntry, mut ig Ignore, is_root bool, root_device u64, has_root_device bool) {
	defer {
		ig.free_nodes()
	}
	should_visit := if min_depth := walk.min_depth {
		dent.depth() >= min_depth
	} else {
		true
	}
	if !dent.is_dir() {
		if !is_root {
			should_skip := walk.skip_entry(&ig, &dent) or {
				walk.push_result(walk_result_from_error(ignore_error_from_ierror(err)))
				return
			}
			if should_skip {
				return
			}
		}
		if should_visit {
			walk.push_result(walk_result_from_entry(dent))
		}
		return
	}
	if !is_root {
		should_skip := walk.skip_entry(&ig, &dent) or {
			walk.push_result(walk_result_from_error(ignore_error_from_ierror(err)))
			return
		}
		if should_skip {
			return
		}
	}

	mut descend := true
	if has_root_device {
		descend = is_same_file_system(root_device, dent.path()) or {
			walk.push_result(walk_result_from_error(io_error(err).with_path(dent.path()).with_depth(dent.depth())))
			false
		}
	}

	mut child_ignore, has_child_err, child_err := ig.add_child(dent.path())
	defer {
		child_ignore.free_nodes()
	}
	if has_child_err {
		dent.err = child_err
	} else {
		dent.err = none
	}
	if should_visit {
		walk.push_result(walk_result_from_entry(dent))
	}
	if !descend {
		return
	}
	if max_depth := walk.max_depth {
		if dent.depth() >= max_depth {
			return
		}
	}
	children := walk.read_dir_children(dent.path()) or {
		walk.push_result(walk_result_from_error(io_error(err).with_path(dent.path()).with_depth(dent.depth())))
		return
	}
	for child_entry in children {
		child_depth := dent.depth() + 1
		mut child_raw := if child_entry.has_type && walk.can_trust_dirent_type() {
			DirEntryRaw.from_child_known(child_depth, dent.path(), child_entry.name, child_entry.ty,
				child_entry.ino)
		} else {
			DirEntryRaw.from_child(child_depth, dent.path(), child_entry.name) or {
				walk.push_result(walk_result_from_error(io_error(err).with_path(os.join_path(dent.path(),
					child_entry.name)).with_depth(child_depth)))
				continue
			}
		}
		if walk.follow_links && child_raw.path_is_symlink() {
			child_path := child_raw.path.clone()
			child_raw = DirEntryRaw.from_path(child_depth, child_path, true) or {
				walk.push_result(walk_result_from_error(io_error(err).with_path(os.join_path(dent.path(),
					child_entry.name)).with_depth(child_depth)))
				continue
			}
			if child_raw.ty == .directory {
				if err := check_symlink_loop(child_ignore, child_raw.path.clone(), child_depth) {
					walk.push_result(walk_result_from_error(err))
					continue
				}
			}
		}
		mut child := DirEntry.new_raw(child_raw, none_ignore_error())
		walk.traverse_entry(mut child, child_ignore.clone(), false, root_device, has_root_device)
	}
}

fn (mut walk Walk) visit_traverse_entry(mut visitor ParallelVisitor, mut dent DirEntry, mut ig Ignore, is_root bool, root_device u64, has_root_device bool) WalkState {
	defer {
		ig.free_nodes()
	}
	should_visit := if min_depth := walk.min_depth {
		dent.depth() >= min_depth
	} else {
		true
	}
	if !dent.is_dir() {
		if !is_root {
			should_skip := walk.skip_entry(&ig, &dent) or {
				state := visitor.visit(walk_result_from_error(ignore_error_from_ierror(err)))
				return if state.is_quit() { .quit } else { .continue_ }
			}
			if should_skip {
				return .continue_
			}
		}
		if should_visit {
			state := visitor.visit(walk_result_from_entry(dent))
			if state.is_quit() {
				return .quit
			}
		}
		return .continue_
	}
	if !is_root {
		should_skip := walk.skip_entry(&ig, &dent) or {
			state := visitor.visit(walk_result_from_error(ignore_error_from_ierror(err)))
			return if state.is_quit() { .quit } else { .continue_ }
		}
		if should_skip {
			return .continue_
		}
	}

	mut descend := true
	if has_root_device {
		descend = is_same_file_system(root_device, dent.path()) or {
			state := visitor.visit(walk_result_from_error(io_error(err).with_path(dent.path()).with_depth(dent.depth())))
			if state.is_quit() {
				return .quit
			}
			false
		}
	}

	mut child_ignore, has_child_err, child_err := ig.add_child(dent.path())
	defer {
		child_ignore.free_nodes()
	}
	if has_child_err {
		dent.err = child_err
	} else {
		dent.err = none
	}
	if should_visit {
		state := visitor.visit(walk_result_from_entry(dent))
		if state.is_quit() {
			return .quit
		}
		if state == .skip {
			return .continue_
		}
	}
	if !descend {
		return .continue_
	}
	if max_depth := walk.max_depth {
		if dent.depth() >= max_depth {
			return .continue_
		}
	}
	children := walk.read_dir_children(dent.path()) or {
		state := visitor.visit(walk_result_from_error(io_error(err).with_path(dent.path()).with_depth(dent.depth())))
		if state.is_quit() {
			return .quit
		}
		return .continue_
	}
	for child_entry in children {
		child_depth := dent.depth() + 1
		mut child_raw := if child_entry.has_type && walk.can_trust_dirent_type() {
			DirEntryRaw.from_child_known(child_depth, dent.path(), child_entry.name, child_entry.ty,
				child_entry.ino)
		} else {
			DirEntryRaw.from_child(child_depth, dent.path(), child_entry.name) or {
				state := visitor.visit(walk_result_from_error(io_error(err).with_path(os.join_path(dent.path(),
					child_entry.name)).with_depth(child_depth)))
				if state.is_quit() {
					return .quit
				}
				continue
			}
		}
		if walk.follow_links && child_raw.path_is_symlink() {
			child_path := child_raw.path.clone()
			child_raw = DirEntryRaw.from_path(child_depth, child_path, true) or {
				state := visitor.visit(walk_result_from_error(io_error(err).with_path(os.join_path(dent.path(),
					child_entry.name)).with_depth(child_depth)))
				if state.is_quit() {
					return .quit
				}
				continue
			}
			if child_raw.ty == .directory {
				if err := check_symlink_loop(child_ignore, child_raw.path.clone(), child_depth) {
					state := visitor.visit(walk_result_from_error(err))
					if state.is_quit() {
						return .quit
					}
					continue
				}
			}
		}
		mut child := DirEntry.new_raw(child_raw, none_ignore_error())
		state := walk.visit_traverse_entry(mut visitor, mut child, child_ignore.clone(), false,
			root_device, has_root_device)
		if state.is_quit() {
			return .quit
		}
	}
	return .continue_
}

fn (walk &Walk) can_trust_dirent_type() bool {
	return !walk.follow_links && walk.max_filesize == none && walk.skip == none && !walk.same_file_system
}

fn (walk &Walk) read_dir_children(path string) ![]DirChild {
	mut children := read_dir_children(path)!
	sort_children(mut children, path, walk.has_sort_by_name, walk.sort_by_name, walk.has_sort_by_path,
		walk.sort_by_path)
	return children
}

fn read_dir_children(path string) ![]DirChild {
	$if windows {
		names := os.ls(path)!
		mut children := []DirChild{cap: names.len}
		for name in names {
			children << DirChild{
				name: name
			}
		}
		return children
	} $else {
		return read_dir_children_nix(path)
	}
}

fn read_dir_children_nix(path string) ![]DirChild {
	if path == '' {
		return error('ls() expects a folder, not an empty string')
	}
	mut children := []DirChild{cap: 50}
	dir_ptr := unsafe { C.opendir(&char(path.str)) }
	if isnil(dir_ptr) {
		return error('ls() couldnt open dir "${path}"')
	}
	mut ent := &C.dirent(unsafe { nil })
	for {
		ent = C.readdir(dir_ptr)
		if isnil(ent) {
			break
		}
		unsafe {
			bptr := &u8(&ent.d_name[0])
			if bptr[0] == 0 || (bptr[0] == `.` && bptr[1] == 0)
				|| (bptr[0] == `.` && bptr[1] == `.` && bptr[2] == 0) {
				continue
			}
			ty, has_type := entry_file_type_from_dirent(int(ent.d_type))
			children << DirChild{
				name:     tos_clone(bptr)
				ty:       ty
				has_type: has_type
				ino:      u64(ent.d_ino)
			}
		}
	}
	C.closedir(dir_ptr)
	return children
}

fn entry_file_type_from_dirent(d_type int) (os.FileType, bool) {
	return match d_type {
		dirent_dt_reg { os.FileType.regular, true }
		dirent_dt_dir { os.FileType.directory, true }
		dirent_dt_lnk { os.FileType.symbolic_link, true }
		else { os.FileType.unknown, false }
	}
}

fn (mut walk Walk) skip_entry(ig &Ignore, ent &DirEntry) !bool {
	if ent.depth() == 0 {
		return false
	}
	if should_skip_entry_with_scratch(ig, ent, mut walk.gitignore_matches) {
		return true
	}
	if skip := walk.skip {
		is_stdout := path_equals(ent, skip)!
		if is_stdout {
			return true
		}
	}
	if max_filesize := walk.max_filesize {
		if !ent.is_dir() && skip_filesize(max_filesize, ent.path(), ent.metadata() or { return false }) {
			return true
		}
	}
	if walk.has_filter && !walk.filter(ent) {
		return true
	}
	return false
}

/// WalkParallel is a parallel recursive directory iterator over files paths
/// in one or more directories.
///
/// Only file and directory paths matching the rules are returned. By default,
/// ignore files like `.gitignore` are respected. The precise matching rules
/// and precedence is explained in the documentation for `WalkBuilder`.
///
/// Unlike `Walk`, this uses multiple threads for traversing a directory.
pub struct WalkParallel {
	paths            []string
	ig_root          Ignore
	max_filesize     ?u64
	max_depth        ?usize
	min_depth        ?usize
	follow_links     bool
	same_file_system bool
	threads          usize
	skip             ?Handle
	// V-specific: see `WalkBuilder.filter`.
	filter           FilterFn = unsafe { nil }
	has_filter       bool
}

/// Execute the parallel recursive directory iterator using a custom
/// visitor.
///
/// The factory is used to construct a visitor for every thread used by this
/// traversal. The visitor returned from each factory call is then called for
/// every directory entry seen by that thread.
///
/// Typically, creating a custom visitor is useful if you need to perform
/// some kind of cleanup once traversal is finished. This can be achieved
/// through the V-specific `ParallelVisitor.free` ownership hook.
pub fn (wp WalkParallel) run(mut factory ParallelVisitorFactory) {
	worker_count := wp.worker_count()
	if worker_count <= 1 {
		mut visitor := factory.create()
		wp.visit_serial(mut visitor)
		free_parallel_visitor(visitor)
		return
	}
	mut first_visitor := factory.create()
	mut initial := wp.initial_work(mut first_visitor)
	if initial.len == 0 {
		free_parallel_visitor(first_visitor)
		return
	}
	stacks := WorkStealingStacks.new(worker_count, mut initial)
	quit_now := stdatomic.new_atomic(false)
	active_workers := stdatomic.new_atomic(worker_count)
	mut threads := []thread bool{}
	threads << spawn walk_stealing_visit_worker(wp, stacks, first_visitor, quit_now,
		active_workers, 0)
	for worker_index in 1 .. worker_count {
		visitor := factory.create()
		threads << spawn walk_stealing_visit_worker(wp, stacks, visitor, quit_now, active_workers,
			worker_index)
	}
	for thread in threads {
		thread.wait()
	}
	unsafe { threads.free() }
	stacks.free()
	unsafe {
		free(quit_now)
		free(active_workers)
	}
}

// A result emitted by unordered parallel traversal.
pub struct WalkParallelStreamResult {
pub:
	done   bool
	result WalkResult
}

// Streams walk results from worker threads without waiting for a central
// visitor decision for each entry.
//
// This is intended for callers that always continue traversal unless a shared
// stop flag is set. It does not support `WalkState.skip`; callers needing
// per-directory skip decisions should use `run`/`visit`.
pub fn (wp WalkParallel) stream(results chan WalkParallelStreamResult, stop &stdatomic.AtomicVal[bool]) {
	worker_count := wp.worker_count()
	if worker_count <= 1 {
		wp.stream_serial(results, stop)
		return
	}
	mut initial_visitor := WalkParallelStreamVisitor{
		results: results
		stop:    stop
	}
	mut initial_visitor_box := ParallelVisitor(&initial_visitor)
	mut initial := wp.initial_work(mut initial_visitor_box)
	if initial.len == 0 {
		results <- WalkParallelStreamResult{
			done: true
		}
		return
	}
	stacks := WorkStealingStacks.new(worker_count, mut initial)
	active_workers := stdatomic.new_atomic(worker_count)
	mut threads := []thread bool{}
	for worker_index in 0 .. worker_count {
		threads << spawn walk_stealing_stream_worker(wp, stacks, results, stop, active_workers,
			worker_index)
	}
	for thread in threads {
		thread.wait()
	}
	unsafe { threads.free() }
	stacks.free()
	unsafe { free(active_workers) }
	results <- WalkParallelStreamResult{
		done: true
	}
}

fn (wp WalkParallel) stream_serial(results chan WalkParallelStreamResult, stop &stdatomic.AtomicVal[bool]) {
	mut walk := wp.new_walk()
	mut visitor := WalkParallelStreamVisitor{
		results: results
		stop:    stop
	}
	mut visitor_box := ParallelVisitor(&visitor)
	for path in wp.paths {
		if stop.load() {
			break
		}
		state := walk.visit_root_path(mut visitor_box, path)
		if state.is_quit() {
			break
		}
	}
	results <- WalkParallelStreamResult{
		done: true
	}
}

fn (wp WalkParallel) visit_serial(mut visitor ParallelVisitor) {
	mut walk := wp.new_walk()
	for path in wp.paths {
		state := walk.visit_root_path(mut visitor, path)
		if state.is_quit() {
			break
		}
	}
}

fn (wp WalkParallel) initial_work(mut visitor ParallelVisitor) []WalkStealingWork {
	mut initial := []WalkStealingWork{cap: wp.paths.len}
	for path in wp.paths {
		if path == '-' {
			initial << WalkStealingWork{
				entry:   DirEntry.new_stdin()
				ig:      wp.ig_root.clone()
				is_root: true
			}
			continue
		}
		root, root_err := prepare_root_entry(path, wp.follow_links)
		if root_err.kind != .other || root_err.message != '' {
			if visitor.visit(walk_result_from_error(root_err)).is_quit() {
				return initial
			}
			continue
		}
		mut ig := wp.ig_root.clone()
		if root.is_dir() {
			parent_ig, has_parent_err, parent_err := wp.ig_root.add_parents(root.path())
			ig.free_nodes()
			ig = parent_ig
			if has_parent_err && visitor.visit(walk_result_from_error(parent_err)).is_quit() {
				return initial
			}
		}
		mut root_device := u64(0)
		if wp.same_file_system {
			root_device = device_num(root.path()) or {
				if visitor.visit(walk_result_from_error(io_error(err).with_path(root.path()))).is_quit() {
					return initial
				}
				continue
			}
		}
		initial << WalkStealingWork{
			entry:           root
			ig:              ig
			is_root:         true
			root_device:     root_device
			has_root_device: wp.same_file_system
		}
	}
	return initial
}

fn (wp WalkParallel) new_walk() Walk {
	return Walk{
		ig_root:          wp.ig_root
		ig:               wp.ig_root
		max_filesize:     wp.max_filesize
		skip:             wp.skip
		filter:           wp.filter
		has_filter:       wp.has_filter
		min_depth:        wp.min_depth
		max_depth:        wp.max_depth
		follow_links:     wp.follow_links
		same_file_system: wp.same_file_system
	}
}

fn (wp WalkParallel) worker_count() int {
	mut count := int(wp.threads)
	if count <= 0 {
		count = runtime.nr_cpus()
		if count <= 0 {
			count = 1
		}
		if count > 12 {
			count = 12
		}
	}
	if count < 1 {
		return 1
	}
	return count
}

struct WalkParallelStreamVisitor {
	results chan WalkParallelStreamResult
	stop    &stdatomic.AtomicVal[bool]
}

struct WalkStealingWork {
	entry           DirEntry
	ig              Ignore
	is_root         bool
	root_device     u64
	has_root_device bool
}

@[heap]
struct WorkStealingStacks {
	queues []&WorkStealingQueue
}

@[heap]
struct WorkStealingQueue {
	mutex &sync.Mutex
mut:
	items []WalkStealingWork
	head  int
}

fn WorkStealingQueue.new() &WorkStealingQueue {
	mut items := []WalkStealingWork{}
	unsafe { items.flags |= .noslices }
	return &WorkStealingQueue{
		mutex: sync.new_mutex()
		items: items
	}
}

fn (queue &WorkStealingQueue) len_unlocked() int {
	return queue.items.len - queue.head
}

fn (mut queue WorkStealingQueue) push_unlocked(work WalkStealingWork) {
	queue.items << work
}

fn (mut queue WorkStealingQueue) pop_back_unlocked() ?WalkStealingWork {
	if queue.len_unlocked() == 0 {
		return none
	}
	work := queue.items.pop()
	if queue.items.len == queue.head {
		queue.items.clear()
		queue.head = 0
	}
	return work
}

fn (mut queue WorkStealingQueue) pop_front_unlocked() ?WalkStealingWork {
	if queue.len_unlocked() == 0 {
		return none
	}
	work := queue.items[queue.head]
	queue.head++
	if queue.items.len == queue.head {
		queue.items.clear()
		queue.head = 0
	}
	return work
}

fn (queue &WorkStealingQueue) push(work WalkStealingWork) {
	queue.mutex.lock()
	unsafe { (&WorkStealingQueue(queue)).push_unlocked(work) }
	queue.mutex.unlock()
}

fn (queue &WorkStealingQueue) pop_back() ?WalkStealingWork {
	queue.mutex.lock()
	defer {
		queue.mutex.unlock()
	}
	unsafe {
		return (&WorkStealingQueue(queue)).pop_back_unlocked()
	}
}

fn (queue &WorkStealingQueue) free() {
	unsafe {
		mut owned := &WorkStealingQueue(queue)
		owned.items.free()
		owned.items = []WalkStealingWork{}
		owned.head = 0
		owned.mutex.destroy()
		free(owned.mutex)
		free(owned)
	}
}

fn WorkStealingStacks.new(worker_count int, mut initial []WalkStealingWork) &WorkStealingStacks {
	mut queues := []&WorkStealingQueue{len: worker_count}
	for i in 0 .. queues.len {
		queues[i] = WorkStealingQueue.new()
	}
	mut worker_index := 0
	for initial.len > 0 {
		unsafe { (&WorkStealingQueue(queues[worker_index])).push_unlocked(initial.pop()) }
		worker_index = (worker_index + 1) % worker_count
	}
	unsafe { initial.free() }
	return &WorkStealingStacks{
		queues: queues
	}
}

fn (stacks &WorkStealingStacks) free() {
	unsafe {
		mut owned := &WorkStealingStacks(stacks)
		for i in 0 .. owned.queues.len {
			owned.queues[i].free()
		}
		owned.queues.free()
		free(owned)
	}
}

fn (stacks &WorkStealingStacks) push(worker_index int, work WalkStealingWork) {
	stacks.queues[worker_index].push(work)
}

fn (stacks &WorkStealingStacks) take(worker_index int) ?WalkStealingWork {
	owner := stacks.queues[worker_index]
	if work := owner.pop_back() {
		return work
	}
	for offset in 1 .. stacks.queues.len {
		victim_index := (worker_index + offset) % stacks.queues.len
		victim := stacks.queues[victim_index]
		// Lock queue pairs in index order so simultaneous thieves cannot deadlock.
		first := if worker_index < victim_index { owner } else { victim }
		second := if worker_index < victim_index { victim } else { owner }
		first.mutex.lock()
		second.mutex.lock()
		mut found := ?WalkStealingWork(none)
		unsafe {
			mut mutable_owner := &WorkStealingQueue(owner)
			mut mutable_victim := &WorkStealingQueue(victim)
			victim_len := mutable_victim.len_unlocked()
			if victim_len > 0 {
				steal_count := if victim_len == 1 { 1 } else { victim_len / 2 }
				found = mutable_victim.pop_front_unlocked()
				for _ in 1 .. steal_count {
					stolen := mutable_victim.pop_front_unlocked() or { break }
					mutable_owner.push_unlocked(stolen)
				}
			}
		}
		second.mutex.unlock()
		first.mutex.unlock()
		if work := found {
			return work
		}
	}
	return none
}

fn take_work(stacks &WorkStealingStacks, active_workers &stdatomic.AtomicVal[int], stop &stdatomic.AtomicVal[bool], worker_index int) ?WalkStealingWork {
	if work := stacks.take(worker_index) {
		return work
	}
	if active_workers.sub(1) == 1 {
		return none
	}
	for active_workers.load() > 0 {
		if stop.load() {
			return none
		}
		if work := stacks.take(worker_index) {
			active_workers.add(1)
			return work
		}
		time.sleep(100 * time.microsecond)
	}
	return none
}

fn walk_stealing_visit_worker(wp WalkParallel, stacks &WorkStealingStacks, visitor_in ParallelVisitor, stop &stdatomic.AtomicVal[bool], active_workers &stdatomic.AtomicVal[int], worker_index int) bool {
	mut walk := wp.new_walk()
	mut visitor := visitor_in
	defer {
		free_parallel_visitor(visitor)
	}
	for !stop.load() {
		work := take_work(stacks, active_workers, stop, worker_index) or { break }
		state := walk_stealing_run_one(mut walk, stacks, worker_index, mut visitor, work)
		if state.is_quit() {
			stop.store(true)
			break
		}
	}
	return true
}

fn walk_stealing_stream_worker(wp WalkParallel, stacks &WorkStealingStacks, results chan WalkParallelStreamResult, stop &stdatomic.AtomicVal[bool], active_workers &stdatomic.AtomicVal[int], worker_index int) bool {
	mut walk := wp.new_walk()
	mut sender := WalkParallelStreamVisitor{
		results: results
		stop:    stop
	}
	mut sender_box := ParallelVisitor(&sender)
	for !stop.load() {
		work := take_work(stacks, active_workers, stop, worker_index) or { break }
		state := walk_stealing_run_one(mut walk, stacks, worker_index, mut sender_box, work)
		if state.is_quit() {
			stop.store(true)
			break
		}
	}
	return true
}

fn walk_stealing_run_one(mut walk Walk, stacks &WorkStealingStacks, worker_index int, mut visitor ParallelVisitor, work_in WalkStealingWork) WalkState {
	mut work := work_in
	defer {
		work.ig.free_nodes()
	}
	mut dent := work.entry
	should_visit := if min_depth := walk.min_depth {
		dent.depth() >= min_depth
	} else {
		true
	}
	if !dent.is_dir() {
		if should_visit {
			return visitor.visit(walk_result_from_entry(dent))
		}
		dent.free()
		return .continue_
	}
	defer {
		dent.free()
	}
	mut descend := true
	if work.has_root_device {
		descend = is_same_file_system(work.root_device, dent.path()) or {
			state := visitor.visit(walk_result_from_error(io_error(err).with_path(dent.path()).with_depth(dent.depth())))
			if state.is_quit() {
				return state
			}
			false
		}
	}
	mut child_ignore, has_child_err, child_err := work.ig.add_child(dent.path())
	defer {
		child_ignore.free_nodes()
	}
	if has_child_err {
		dent.err = child_err
	} else {
		dent.err = none
	}
	if should_visit {
		state := visitor.visit(walk_result_from_entry(dent.clone()))
		if state.is_quit() || state == .skip {
			return state
		}
	}
	if !descend {
		return .skip
	}
	if max_depth := walk.max_depth {
		if dent.depth() >= max_depth {
			return .continue_
		}
	}
	mut children := walk.read_dir_children(dent.path()) or {
		return visitor.visit(walk_result_from_error(io_error(err).with_path(dent.path()).with_depth(dent.depth())))
	}
	defer {
		for child_entry in children {
			unsafe { child_entry.name.free() }
		}
		unsafe { children.free() }
	}
	for child_entry in children {
		child_depth := dent.depth() + 1
		mut child_raw := if child_entry.has_type && walk.can_trust_dirent_type() {
			DirEntryRaw.from_child_known(child_depth, dent.path(), child_entry.name, child_entry.ty,
				child_entry.ino)
		} else {
			DirEntryRaw.from_child(child_depth, dent.path(), child_entry.name) or {
				state := visitor.visit(walk_result_from_error(io_error(err).with_path(os.join_path(dent.path(),
					child_entry.name)).with_depth(child_depth)))
				if state.is_quit() {
					return .quit
				}
				continue
			}
		}
		if walk.follow_links && child_raw.path_is_symlink() {
			child_path := child_raw.path.clone()
			child_raw = DirEntryRaw.from_path(child_depth, child_path, true) or {
				state := visitor.visit(walk_result_from_error(io_error(err).with_path(os.join_path(dent.path(),
					child_entry.name)).with_depth(child_depth)))
				if state.is_quit() {
					return .quit
				}
				continue
			}
			if child_raw.ty == .directory {
				if loop_err := check_symlink_loop(child_ignore, child_raw.path.clone(), child_depth) {
					state := visitor.visit(walk_result_from_error(loop_err))
					if state.is_quit() {
						return .quit
					}
					continue
				}
			}
		}
		mut child := DirEntry.new_raw(child_raw, none_ignore_error())
		should_skip := walk.skip_entry(&child_ignore, &child) or {
			state := visitor.visit(walk_result_from_error(ignore_error_from_ierror(err)))
			if state.is_quit() {
				return .quit
			}
			child.free()
			continue
		}
		if should_skip {
			child.free()
			continue
		}
		stacks.push(worker_index, WalkStealingWork{
			entry:           child
			ig:              child_ignore.clone()
			root_device:     work.root_device
			has_root_device: work.has_root_device
		})
	}
	return .continue_
}

fn (mut visitor WalkParallelStreamVisitor) visit(result WalkResult) WalkState {
	if visitor.stop.load() {
		return .quit
	}
	visitor.results <- WalkParallelStreamResult{
		result: result
	}
	if visitor.stop.load() {
		return .quit
	}
	return .continue_
}

fn (mut visitor WalkParallelStreamVisitor) free() {
	_ = visitor
}

fn prepare_root_entry(path string, follow_links bool) (DirEntry, IgnoreError) {
	_ = follow_links
	raw := DirEntryRaw.from_path(0, path, false) or {
		return DirEntry.new_stdin(), io_error(err).with_path(path)
	}
	return DirEntry.new_raw(raw, none_ignore_error()), IgnoreError{}
}

fn sort_children(mut children []DirChild, parent_path string, has_name_cmp bool, name_cmp NameComparator, has_path_cmp bool, path_cmp PathComparator) {
	if !has_name_cmp && !has_path_cmp {
		return
	}
	for i := 0; i < children.len; i++ {
		for j := i + 1; j < children.len; j++ {
			mut cmp := 0
			if has_name_cmp {
				cmp = name_cmp(&children[i].name, &children[j].name)
			} else if has_path_cmp {
				left := os.join_path(parent_path, children[i].name)
				right := os.join_path(parent_path, children[j].name)
				cmp = path_cmp(&left, &right)
			}
			if cmp > 0 {
				children[i], children[j] = children[j], children[i]
			}
		}
	}
}

fn check_symlink_loop(ig_parent Ignore, child_path string, child_depth usize) ?IgnoreError {
	hchild := Handle.from_path(child_path) or {
		return io_error(err).with_path(child_path).with_depth(child_depth)
	}
	mut node := ig_parent.node
	for !isnil(node) {
		if node.is_absolute_parent {
			break
		}
		h := Handle.from_path(node.dir) or {
			return io_error(err).with_path(child_path).with_depth(child_depth)
		}
		if h.same_file(hchild) {
			return loop_error(node.dir, child_path).with_depth(child_depth)
		}
		node = node.parent
	}
	return none
}

fn skip_filesize(max_filesize u64, path string, stat os.Stat) bool {
	if stat.size > max_filesize {
		_ = path
		return true
	}
	return false
}

fn should_skip_entry_with_scratch(ig &Ignore, dent &DirEntry, mut gitignore_matches []usize) bool {
	matched := ig.matched_dir_entry_with_scratch(dent, mut gitignore_matches)
	if matched.is_ignore() {
		return true
	}
	return false
}

fn never_equal(dent &DirEntry, handle Handle) bool {
	$if linux || macos || freebsd || openbsd || netbsd || dragonfly || solaris {
		if ino := dent.ino() {
			return ino != handle.ino
		}
		return false
	} $else {
		_ = dent
		_ = handle
		return false
	}
}

// Returns true if and only if the given directory entry is believed to be
// equivalent to the given handle. If there was a problem querying the path
// for information to determine equality, then that error is returned.
fn path_equals(dent &DirEntry, handle Handle) !bool {
	if dent.is_stdin() || never_equal(dent, handle) {
		return false
	}
	other := Handle.from_path(dent.path()) or {
		return io_error(err).with_path(dent.path())
	}
	return other.same_file(handle)
}

fn ignore_error_from_ierror(err IError) IgnoreError {
	if err is IgnoreError {
		return err.clone()
	}
	return io_error(err)
}

// Returns true if and only if the given path is on the same device as the
// given root device.
fn is_same_file_system(root_device u64, path string) !bool {
	return root_device == device_num(path)!
}

fn device_num(path string) !u64 {
	$if linux || macos || freebsd || openbsd || netbsd || dragonfly || solaris || windows {
		info := followed_path_info(path) or { return err }
		return info.dev
	} $else {
		return error('walkdir: same_file_system option not supported on this platform')
	}
}
