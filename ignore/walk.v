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

pub enum EntryFileType {
	unknown
	file
	directory
	symbolic_link
	other
}

fn (ft EntryFileType) is_dir() bool {
	return ft == .directory
}

fn (ft EntryFileType) is_symlink() bool {
	return ft == .symbolic_link
}

fn entry_file_type_from_os(ft os.FileType) EntryFileType {
	return match ft {
		.directory { .directory }
		.regular { .file }
		.symbolic_link { .symbolic_link }
		else { .other }
	}
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
	ty                EntryFileType
	follow_link       bool
	depth             int
	source_is_symlink bool
	metadata          Metadata
	ino_value         u64
}

fn (raw &DirEntryRaw) clone() DirEntryRaw {
	return DirEntryRaw{
		path:              raw.path.clone()
		file_name_value:   raw.file_name_value.clone()
		ty:                raw.ty
		follow_link:       raw.follow_link
		depth:             raw.depth
		source_is_symlink: raw.source_is_symlink
		metadata:          raw.metadata
		ino_value:         raw.ino_value
	}
}

struct DirChild {
	name     string
	ty       EntryFileType
	has_type bool
}

// File metadata attached to a directory entry.
pub struct Metadata {
pub:
	size      u64
	file_type EntryFileType
}

// A directory entry with a possible error attached.
//
// The error typically refers to a problem parsing ignore files in a
// particular directory.
pub struct DirEntry implements IClone {
pub mut:
	err_value IgnoreError
	has_err   bool
mut:
	// V-specific explicit representation of Rust's private DirEntryInner enum.
	// Keeping the raw entry inline avoids a heap-allocated sum-type payload and
	// lets path/file_name return borrows without duplicate cache strings.
	raw         DirEntryRaw
	stdin_value bool
}

pub fn (d &DirEntry) clone() DirEntry {
	return DirEntry{
		raw:         if d.stdin_value { DirEntryRaw{} } else { d.raw.clone() }
		stdin_value: d.stdin_value
		err_value:   d.err_value.clone()
		has_err:     d.has_err
	}
}

fn none_ignore_error() ?IgnoreError {
	return none
}

// The full path that this entry represents.
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
	d.err_value.free()
	d.raw.path = ''
	d.raw.file_name_value = ''
}

// The full path that this entry represents.
//
// Analogous to `DirEntry.path`, but moves ownership of the path.
pub fn (d &DirEntry) into_path() string {
	return (*d.path()).clone()
}

// Whether this entry corresponds to a symbolic link or not.
pub fn (d &DirEntry) path_is_symlink() bool {
	if d.stdin_value {
		return false
	}
	return d.raw.path_is_symlink()
}

// Returns true if and only if this entry corresponds to stdin.
pub fn (d &DirEntry) is_stdin() bool {
	return d.stdin_value
}

// Returns metadata for the file represented by this entry.
pub fn (d &DirEntry) metadata() !Metadata {
	if d.stdin_value {
		return error('<stdin> has no metadata')
	}
	return d.raw.metadata()
}

// Return the file type for the file that this entry points to.
//
// This entry doesn't have a file type if it corresponds to stdin.
pub fn (d &DirEntry) file_type() ?EntryFileType {
	if d.stdin_value {
		return none
	}
	return d.raw.file_type()
}

// Returns the file name for this entry.
//
// If the entry has no base name, then the full path is returned.
pub fn (d &^a DirEntry) file_name[^a]() &^a string {
	if d.stdin_value {
		return &stdin_entry_name
	}
	return &d.raw.file_name_value
}

// Returns the depth of this entry relative to the walk root.
pub fn (d &DirEntry) depth() int {
	if d.stdin_value {
		return 0
	}
	return d.raw.depth
}

// Returns the underlying inode number if one exists.
//
// If this entry doesn't have an inode number, then `none` is returned.
pub fn (d &DirEntry) ino() ?u64 {
	if d.stdin_value {
		return none
	}
	return d.raw.ino()
}

// Returns an error associated with this entry, if one exists.
pub fn (d &^a DirEntry) error[^a]() ?&^a IgnoreError {
	if d.has_err {
		return &d.err_value
	}
	return none
}

// Returns true if and only if this entry points to a directory.
pub fn (d &DirEntry) is_dir() bool {
	if file_type := d.file_type() {
		return file_type.is_dir()
	}
	return false
}

fn DirEntry.new_stdin() DirEntry {
	return DirEntry{
		raw:         DirEntryRaw{}
		stdin_value: true
		err_value:   IgnoreError{}
		has_err:     false
	}
}

fn DirEntry.new_raw(dent DirEntryRaw, err ?IgnoreError) DirEntry {
	mut entry := DirEntry{
		raw:         dent
		stdin_value: false
		err_value:   IgnoreError{}
		has_err:     false
	}
	if value := err {
		entry.err_value = value
		entry.has_err = true
	}
	return entry
}

fn (raw &DirEntryRaw) path_is_symlink() bool {
	return raw.source_is_symlink
}

fn (raw &DirEntryRaw) metadata() !Metadata {
	return raw.metadata
}

fn (raw &DirEntryRaw) file_type() EntryFileType {
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

fn DirEntryRaw.from_path(depth int, path string, link bool) !DirEntryRaw {
	link_info := os.lstat(path) or { return err }
	source_is_symlink := link_info.get_filetype() == .symbolic_link
	info := if link { followed_path_info(path) or { return err } } else { link_info }
	ty := entry_file_type_from_os(info.get_filetype())
	return DirEntryRaw{
		path:              path.to_owned()
		file_name_value:   file_name(path).to_owned()
		ty:                ty
		follow_link:       link
		depth:             depth
		source_is_symlink: source_is_symlink
		metadata:          Metadata{
			size:      if ty == .directory { u64(0) } else { info.size }
			file_type: ty
		}
		ino_value:         info.inode
	}
}

fn DirEntryRaw.from_child(depth int, parent_path string, name string) !DirEntryRaw {
	return DirEntryRaw.from_path(depth, join_child_path(parent_path, name), false)
}

fn DirEntryRaw.from_child_known(depth int, parent_path string, name string, ty EntryFileType) DirEntryRaw {
	path := join_child_path(parent_path, name)
	return DirEntryRaw{
		path:              path
		file_name_value:   name.to_owned()
		ty:                ty
		follow_link:       false
		depth:             depth
		source_is_symlink: ty == .symbolic_link
		metadata:          Metadata{
			size:      u64(0)
			file_type: ty
		}
		ino_value:         u64(0)
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

pub enum WalkState {
	// Continue walking as normal.
	continue_
	// If the current entry is a directory, do not descend into it.
	skip
	// Stop the walk as soon as possible.
	quit
}

fn (ws WalkState) is_continue() bool {
	return ws == .continue_
}

fn (ws WalkState) is_quit() bool {
	return ws == .quit
}

pub type NameComparator = fn (string, string) int
pub type PathComparator = fn (string, string) int
pub type FilterFn = fn (DirEntry) bool

// Receives walk results during parallel traversal.
pub interface ParallelVisitor {
mut:
	visit(entry WalkResult) WalkState
	// V-specific ownership hook for visitor boxes returned by a factory.
	free()
}

// Creates one independent visitor for each parallel traversal worker.
pub interface ParallelVisitorFactory {
mut:
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

// Builds a recursive directory iterator.
//
// The builder controls ignore handling, recursion depth, symlink behavior,
// path sorting, size filtering, and other traversal options.
pub struct WalkBuilder implements IClone {
mut:
	paths            []string
	ig_builder       IgnoreBuilder
	max_depth        ?usize
	min_depth        ?usize
	max_filesize     ?u64
	follow_links     bool
	same_file_system bool
	threads          int
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
	cwd_initialized  bool
	cwd_value        string
}

// Creates a new builder for recursive traversal rooted at `path`.
//
// If multiple roots are needed, prefer calling `add` instead of creating
// multiple builders.
pub fn WalkBuilder.new(path string) WalkBuilder {
	return WalkBuilder{
		paths:            [path.to_owned()]
		ig_builder:       IgnoreBuilder.new()
		cwd_initialized:  false
		cwd_value:        ''.to_owned()
	}
}

// Builds a sequential `Walk` iterator.
pub fn (builder WalkBuilder) build() Walk {
	cwd := builder.get_or_set_current_dir()
	ig_root := if cwd != '' { builder.ig_builder.build_with_cwd(cwd) } else { builder.ig_builder.build() }
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

// Builds a `WalkParallel` traversal.
//
// Unlike `build`, this does not return an iterator. It returns a traversal
// value that must be executed with `run` or `visit`.
pub fn (builder WalkBuilder) build_parallel() WalkParallel {
	cwd := builder.get_or_set_current_dir()
	ig_root := if cwd != '' { builder.ig_builder.build_with_cwd(cwd) } else { builder.ig_builder.build() }
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
		sort_by_name:     builder.sort_by_name
		has_sort_by_name: builder.has_sort_by_name
		sort_by_path:     builder.sort_by_path
		has_sort_by_path: builder.has_sort_by_path
	}
}

// Adds another root path to the iterator.
pub fn (mut builder WalkBuilder) add(path string) &WalkBuilder {
	builder.paths << path.to_owned()
	return builder
}

// The maximum depth to recurse.
//
// The default, `none`, imposes no depth restriction.
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

// The minimum depth to recurse.
//
// The default, `none`, imposes no minimum depth restriction.
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

// Enables or disables following symbolic links.
pub fn (mut builder WalkBuilder) follow_links(yes bool) &WalkBuilder {
	builder.follow_links = yes
	return builder
}

// Whether to ignore files above the specified limit.
pub fn (mut builder WalkBuilder) max_filesize(filesize ?u64) &WalkBuilder {
	builder.max_filesize = filesize
	return builder
}

// Sets the number of worker threads used by `build_parallel`.
pub fn (mut builder WalkBuilder) threads(n int) &WalkBuilder {
	builder.threads = n
	return builder
}

// Adds an explicit ignore file.
//
// Explicitly added ignore files have lower precedence than the normal ignore
// files discovered during traversal.
pub fn (mut builder WalkBuilder) add_ignore(path string) (bool, IgnoreError) {
	cwd := builder.get_or_set_current_dir()
	if cwd == '' {
		return true, other_error('CWD is not known, ignoring global gitignore ${path}')
	}
	mut gitignore_builder := GitignoreBuilder.new(cwd)
	mut errs := PartialErrorBuilder{}
	add_has_err, add_err := gitignore_builder.add(path)
	errs.maybe_push(add_has_err, add_err)
	gi, build_has_err, build_err := gitignore_builder.build()
	errs.maybe_push(build_has_err, build_err)
	builder.ig_builder.add_ignore(gi)
	return errs.into_error_option()
}

// Adds a custom ignore file name.
//
// These custom names have higher precedence than the default ignore files.
pub fn (mut builder WalkBuilder) add_custom_ignore_filename(file_name string) &WalkBuilder {
	builder.ig_builder.add_custom_ignore_filename(file_name)
	return builder
}

// Sets an override matcher.
pub fn (mut builder WalkBuilder) overrides(overrides Override) &WalkBuilder {
	builder.ig_builder.overrides(overrides)
	return builder
}

// Sets a file type matcher.
pub fn (mut builder WalkBuilder) types(types Types) &WalkBuilder {
	builder.ig_builder.types(types)
	return builder
}

// Toggles the standard ignore-related filters as a group.
pub fn (mut builder WalkBuilder) standard_filters(yes bool) &WalkBuilder {
	builder.hidden(yes)
	builder.parents(yes)
	builder.ignore(yes)
	builder.git_ignore(yes)
	builder.git_global(yes)
	builder.git_exclude(yes)
	return builder
}

// Enables or disables hidden-file filtering.
pub fn (mut builder WalkBuilder) hidden(yes bool) &WalkBuilder {
	builder.ig_builder.hidden(yes)
	return builder
}

// Enables or disables loading ignore files from parent directories.
pub fn (mut builder WalkBuilder) parents(yes bool) &WalkBuilder {
	builder.ig_builder.parents(yes)
	return builder
}

// Enables or disables `.ignore` files.
pub fn (mut builder WalkBuilder) ignore(yes bool) &WalkBuilder {
	builder.ig_builder.ignore(yes)
	return builder
}

// Enables or disables the global gitignore file.
pub fn (mut builder WalkBuilder) git_global(yes bool) &WalkBuilder {
	builder.ig_builder.git_global(yes)
	return builder
}

// Enables or disables `.gitignore` files.
pub fn (mut builder WalkBuilder) git_ignore(yes bool) &WalkBuilder {
	builder.ig_builder.git_ignore(yes)
	return builder
}

// Enables or disables `.git/info/exclude` files.
pub fn (mut builder WalkBuilder) git_exclude(yes bool) &WalkBuilder {
	builder.ig_builder.git_exclude(yes)
	return builder
}

// Controls whether git-related rules require being inside a git repository.
pub fn (mut builder WalkBuilder) require_git(yes bool) &WalkBuilder {
	builder.ig_builder.require_git(yes)
	return builder
}

// Processes ignore files case-insensitively.
pub fn (mut builder WalkBuilder) ignore_case_insensitive(yes bool) &WalkBuilder {
	builder.ig_builder.ignore_case_insensitive(yes)
	return builder
}

// Sorts directory entries by full path.
//
// This is used by the sequential iterator and visitor traversal.
pub fn (mut builder WalkBuilder) sort_by_file_path(cmp PathComparator) &WalkBuilder {
	builder.sort_by_path = cmp
	builder.has_sort_by_path = true
	builder.has_sort_by_name = false
	return builder
}

// Sorts directory entries by base file name.
//
// This is used by the sequential iterator and visitor traversal.
pub fn (mut builder WalkBuilder) sort_by_file_name(cmp NameComparator) &WalkBuilder {
	builder.sort_by_name = cmp
	builder.has_sort_by_name = true
	builder.has_sort_by_path = false
	return builder
}

// Prevents traversal from crossing filesystem boundaries.
pub fn (mut builder WalkBuilder) same_file_system(yes bool) &WalkBuilder {
	builder.same_file_system = yes
	return builder
}

// Skips directory entries believed to correspond to stdout.
pub fn (mut builder WalkBuilder) skip_stdout(yes bool) &WalkBuilder {
	if yes {
		has_handle, handle := stdout_handle()
		builder.skip = if has_handle { handle } else { none }
	} else {
		builder.skip = none
	}
	return builder
}

// Filters yielded entries and prevents descending into directories that do
// not satisfy the predicate.
pub fn (mut builder WalkBuilder) filter_entry(filter FilterFn) &WalkBuilder {
	builder.filter = filter
	builder.has_filter = true
	return builder
}

// Sets the current working directory used for global gitignore resolution.
pub fn (mut builder WalkBuilder) current_dir(cwd string) &WalkBuilder {
	builder.ig_builder.current_dir(cwd)
	builder.cwd_initialized = true
	builder.cwd_value = cwd.to_owned()
	return builder
}

fn (builder WalkBuilder) get_or_set_current_dir() string {
	if builder.cwd_initialized {
		return builder.cwd_value
	}
	return os.getwd()
}

// Recursive directory iterator over one or more roots.
//
// By default, ignore files such as `.gitignore` are respected.
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
	parent_depth    int
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

// Creates a new recursive directory iterator using default settings.
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
		if min_depth := walk.min_depth {
			if min_depth == 0 {
				walk.push_result(walk_result_from_entry(DirEntry.new_stdin()))
			}
		} else {
			walk.push_result(walk_result_from_entry(DirEntry.new_stdin()))
		}
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
		DirEntryRaw.from_child_known(child_depth, frame.parent_path, child_entry.name, child_entry.ty)
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
		if child_raw.ty.is_dir() {
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
		usize(dent.depth()) >= min_depth
	} else {
		true
	}
	if !dent.is_dir() {
		if !is_root {
			if walk.skip_entry(&ig, &dent) {
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

	if has_root_device {
		same_fs := is_same_file_system(root_device, dent.path()) or {
			walk.push_result(walk_result_from_error(io_error(err).with_path(dent.path()).with_depth(dent.depth())))
			return
		}
		if !same_fs {
			return
		}
	}

	mut child_ignore, has_child_err, child_err := ig.add_child(dent.path())
	defer {
		child_ignore.free_nodes()
	}
	if has_child_err {
		dent.err_value = child_err
		dent.has_err = true
	} else {
		dent.err_value = IgnoreError{}
		dent.has_err = false
	}
	if !is_root {
		if walk.skip_entry(&ig, &dent) {
			return
		}
	}
	if should_visit {
		walk.push_result(walk_result_from_entry(dent.clone()))
	}
	if max_depth := walk.max_depth {
		if usize(dent.depth()) >= max_depth {
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
		usize(dent.depth()) >= min_depth
	} else {
		true
	}
	if !dent.is_dir() {
		if !is_root {
			if walk.skip_entry(&ig, &dent) {
				return
			}
		}
		if should_visit {
			walk.push_result(walk_result_from_entry(dent))
		}
		return
	}

	if has_root_device {
		same_fs := is_same_file_system(root_device, dent.path()) or {
			walk.push_result(walk_result_from_error(io_error(err).with_path(dent.path()).with_depth(dent.depth())))
			return
		}
		if !same_fs {
			return
		}
	}

	mut child_ignore, has_child_err, child_err := ig.add_child(dent.path())
	defer {
		child_ignore.free_nodes()
	}
	if has_child_err {
		dent.err_value = child_err
		dent.has_err = true
	} else {
		dent.err_value = IgnoreError{}
		dent.has_err = false
	}
	if !is_root {
		if walk.skip_entry(&ig, &dent) {
			return
		}
	}
	if should_visit {
		walk.push_result(walk_result_from_entry(dent))
	}
	if max_depth := walk.max_depth {
		if usize(dent.depth()) >= max_depth {
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
			DirEntryRaw.from_child_known(child_depth, dent.path(), child_entry.name, child_entry.ty)
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
			if child_raw.ty.is_dir() {
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
		usize(dent.depth()) >= min_depth
	} else {
		true
	}
	if !dent.is_dir() {
		if !is_root {
			if walk.skip_entry(&ig, &dent) {
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

	if has_root_device {
		same_fs := is_same_file_system(root_device, dent.path()) or {
			state := visitor.visit(walk_result_from_error(io_error(err).with_path(dent.path()).with_depth(dent.depth())))
			if state.is_quit() {
				return .quit
			}
			return .continue_
		}
		if !same_fs {
			return .continue_
		}
	}

	mut child_ignore, has_child_err, child_err := ig.add_child(dent.path())
	defer {
		child_ignore.free_nodes()
	}
	if has_child_err {
		dent.err_value = child_err
		dent.has_err = true
	} else {
		dent.err_value = IgnoreError{}
		dent.has_err = false
	}
	if !is_root {
		if walk.skip_entry(&ig, &dent) {
			return .continue_
		}
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
	if max_depth := walk.max_depth {
		if usize(dent.depth()) >= max_depth {
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
			DirEntryRaw.from_child_known(child_depth, dent.path(), child_entry.name, child_entry.ty)
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
			if child_raw.ty.is_dir() {
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
			}
		}
	}
	C.closedir(dir_ptr)
	return children
}

fn entry_file_type_from_dirent(d_type int) (EntryFileType, bool) {
	return match d_type {
		dirent_dt_reg { EntryFileType.file, true }
		dirent_dt_dir { EntryFileType.directory, true }
		dirent_dt_lnk { EntryFileType.symbolic_link, true }
		else { EntryFileType.unknown, false }
	}
}

fn (mut walk Walk) skip_entry(ig &Ignore, ent &DirEntry) bool {
	if ent.depth() == 0 {
		return false
	}
	if should_skip_entry_with_scratch(ig, ent, mut walk.gitignore_matches) {
		return true
	}
	if skip := walk.skip {
		is_stdout := path_equals(ent, skip) or { false }
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

// Visitor-based recursive directory traversal over one or more roots.
pub struct WalkParallel {
	paths            []string
	ig_root          Ignore
	max_filesize     ?u64
	max_depth        ?usize
	min_depth        ?usize
	follow_links     bool
	same_file_system bool
	threads          int
	skip             ?Handle
	// V-specific: see `WalkBuilder.filter`.
	filter           FilterFn = unsafe { nil }
	has_filter       bool
	sort_by_name     NameComparator = unsafe { nil }
	has_sort_by_name bool
	sort_by_path     PathComparator = unsafe { nil }
	has_sort_by_path bool
}

// Executes the traversal with one visitor created for each worker.
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
		sort_by_name:     wp.sort_by_name
		has_sort_by_name: wp.has_sort_by_name
		sort_by_path:     wp.sort_by_path
		has_sort_by_path: wp.has_sort_by_path
	}
}

fn (wp WalkParallel) worker_count() int {
	mut count := wp.threads
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
		usize(dent.depth()) >= min_depth
	} else {
		true
	}
	if !dent.is_dir() {
		if !work.is_root && walk.skip_entry(&work.ig, &dent) {
			dent.free()
			return .continue_
		}
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
		dent.err_value = child_err
		dent.has_err = true
	} else {
		dent.err_value = IgnoreError{}
		dent.has_err = false
	}
	if !work.is_root && walk.skip_entry(&work.ig, &dent) {
		return .continue_
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
		if usize(dent.depth()) >= max_depth {
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
			DirEntryRaw.from_child_known(child_depth, dent.path(), child_entry.name, child_entry.ty)
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
			if child_raw.ty.is_dir() {
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
		if walk.skip_entry(&child_ignore, &child) {
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
	link_root := follow_links || os.is_file(path)
	mut raw := DirEntryRaw.from_path(0, path, link_root) or {
		return DirEntry.new_stdin(), io_error(err).with_path(path)
	}
	if !follow_links && raw.ty == .symbolic_link {
		if target_is_dir(path) {
			raw = DirEntryRaw.from_path(0, path, true) or {
				return DirEntry.new_stdin(), io_error(err).with_path(path)
			}
		}
	}
	return DirEntry.new_raw(raw, none_ignore_error()), IgnoreError{}
}

fn target_is_dir(path string) bool {
	return os.is_dir(path)
}

fn sort_children(mut children []DirChild, parent_path string, has_name_cmp bool, name_cmp NameComparator, has_path_cmp bool, path_cmp PathComparator) {
	if !has_name_cmp && !has_path_cmp {
		return
	}
	for i := 0; i < children.len; i++ {
		for j := i + 1; j < children.len; j++ {
			mut cmp := 0
			if has_name_cmp {
				cmp = name_cmp(children[i].name, children[j].name)
			} else if has_path_cmp {
				cmp = path_cmp(os.join_path(parent_path, children[i].name), os.join_path(parent_path,
					children[j].name))
			}
			if cmp > 0 {
				children[i], children[j] = children[j], children[i]
			}
		}
	}
}

fn check_symlink_loop(ig_parent Ignore, child_path string, child_depth int) ?IgnoreError {
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

fn skip_filesize(max_filesize u64, path string, stat Metadata) bool {
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
	other := Handle.from_path(dent.path())!
	return other.same_file(handle)
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
