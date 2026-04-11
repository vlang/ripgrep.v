module ignore

import os

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

struct StdinEntry {}

struct DirEntryRaw {
	path              string
	ty                EntryFileType
	follow_link       bool
	depth             int
	source_is_symlink bool
	metadata          Metadata
}

pub struct Metadata {
pub:
	size      u64
	file_type EntryFileType
}

pub type DirEntryInner = DirEntryRaw | StdinEntry

pub struct DirEntry {
pub mut:
	dent    DirEntryInner
	err     IgnoreError
	has_err bool
}

pub fn (d DirEntry) path() string {
	if d.dent is StdinEntry {
		return '<stdin>'
	}
	raw := d.dent as DirEntryRaw
	return raw.path
}

pub fn (d DirEntry) into_path() string {
	return d.path().clone()
}

pub fn (d DirEntry) path_is_symlink() bool {
	if d.dent is StdinEntry {
		return false
	}
	raw := d.dent as DirEntryRaw
	return raw.path_is_symlink()
}

pub fn (d DirEntry) is_stdin() bool {
	return d.dent is StdinEntry
}

pub fn (d DirEntry) metadata() !Metadata {
	if d.dent is StdinEntry {
		return error('<stdin> has no metadata')
	}
	raw := d.dent as DirEntryRaw
	return raw.metadata()
}

pub fn (d DirEntry) file_type() EntryFileType {
	if d.dent is StdinEntry {
		return .unknown
	}
	raw := d.dent as DirEntryRaw
	return raw.file_type()
}

pub fn (d DirEntry) file_name() string {
	if d.dent is StdinEntry {
		return '<stdin>'
	}
	raw := d.dent as DirEntryRaw
	return raw.file_name()
}

pub fn (d DirEntry) depth() int {
	if d.dent is StdinEntry {
		return 0
	}
	raw := d.dent as DirEntryRaw
	return raw.depth
}

pub fn (d DirEntry) ino() (bool, u64) {
	return false, u64(0)
}

pub fn (d DirEntry) error() (bool, IgnoreError) {
	if d.has_err {
		return true, d.err
	}
	return false, IgnoreError{}
}

pub fn (d DirEntry) is_dir() bool {
	return d.file_type().is_dir()
}

fn DirEntry.new_stdin() DirEntry {
	return DirEntry{
		dent:    StdinEntry{}
		has_err: false
	}
}

fn DirEntry.new_raw(dent DirEntryRaw, has_err bool, err IgnoreError) DirEntry {
	return DirEntry{
		dent:    dent
		err:     err
		has_err: has_err
	}
}

fn (raw DirEntryRaw) path_is_symlink() bool {
	return raw.source_is_symlink || raw.follow_link
}

fn (raw DirEntryRaw) metadata() !Metadata {
	return raw.metadata
}

fn (raw DirEntryRaw) file_type() EntryFileType {
	return raw.ty
}

fn (raw DirEntryRaw) file_name() string {
	base := os.file_name(raw.path)
	if base != '' {
		return base
	}
	return raw.path
}

fn DirEntryRaw.from_path(depth int, path string, link bool) !DirEntryRaw {
	source_is_symlink := os.is_link(path)
	ty := if link {
		detect_followed_type(path)
	} else {
		detect_unfollowed_type(path, source_is_symlink)
	}
	return DirEntryRaw{
		path:              path.to_owned()
		ty:                ty
		follow_link:       link
		depth:             depth
		source_is_symlink: source_is_symlink
		metadata:          Metadata{
			size:      if ty == .directory { u64(0) } else { os.file_size(path) }
			file_type: ty
		}
	}
}

fn DirEntryRaw.from_child(depth int, parent_path string, name string) !DirEntryRaw {
	return DirEntryRaw.from_path(depth, os.join_path(parent_path, name), false)
}

pub struct WalkResult {
pub:
	is_error bool
	entry    DirEntry
	err      IgnoreError
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
		entry:    DirEntry{}
		err:      err
	}
}

pub enum WalkState {
	continue_
	skip
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

pub interface ParallelVisitor {
mut:
	visit(entry WalkResult) WalkState
}

struct NoopParallelVisitor {}

fn (mut visitor NoopParallelVisitor) visit(entry WalkResult) WalkState {
	_ = entry
	return .continue_
}

pub struct Handle {
pub:
	path      string
	is_stdout bool
}

fn Handle.from_path(path string) !Handle {
	return Handle{
		path:      os.real_path(path).to_owned()
		is_stdout: false
	}
}

fn stdout_handle() (bool, Handle) {
	return false, Handle{}
}

pub struct WalkBuilder {
mut:
	paths           []string
	ig_builder      IgnoreBuilder
	max_depth       int = -1
	min_depth       int = -1
	max_filesize    u64
	has_max_filesize bool
	follow_links    bool
	same_file_system bool
	threads         int
	skip            Handle
	has_skip        bool
	filter          FilterFn = unsafe { nil }
	has_filter      bool
	sort_by_name    NameComparator = unsafe { nil }
	has_sort_by_name bool
	sort_by_path    PathComparator = unsafe { nil }
	has_sort_by_path bool
	cwd_initialized bool
	cwd_value       string
}

pub fn WalkBuilder.new(path string) WalkBuilder {
	return WalkBuilder{
		paths:            [path.to_owned()]
		ig_builder:       IgnoreBuilder.new()
		cwd_initialized:  false
		cwd_value:        ''.to_owned()
	}
}

pub fn (builder WalkBuilder) build() Walk {
	cwd := builder.get_or_set_current_dir()
	ig_root := if cwd != '' { builder.ig_builder.build_with_cwd(cwd) } else { builder.ig_builder.build() }
	mut walk := Walk{
		ig_root:          ig_root
		ig:               ig_root
		max_filesize:     builder.max_filesize
		has_max_filesize: builder.has_max_filesize
		skip:             builder.skip
		has_skip:         builder.has_skip
		filter:           builder.filter
		has_filter:       builder.has_filter
		min_depth:        builder.min_depth
		max_depth:        builder.max_depth
		has_max_depth:    builder.max_depth >= 0
		follow_links:     builder.follow_links
		same_file_system: builder.same_file_system
		has_sort_by_name: builder.has_sort_by_name
		sort_by_name:     builder.sort_by_name
		has_sort_by_path: builder.has_sort_by_path
		sort_by_path:     builder.sort_by_path
	}
	for path in builder.paths {
		walk.add_root_path(path)
	}
	return walk
}

pub fn (builder WalkBuilder) build_parallel() WalkParallel {
	cwd := builder.get_or_set_current_dir()
	ig_root := if cwd != '' { builder.ig_builder.build_with_cwd(cwd) } else { builder.ig_builder.build() }
	return WalkParallel{
		paths:            builder.paths.clone()
		ig_root:          ig_root
		max_filesize:     builder.max_filesize
		has_max_filesize: builder.has_max_filesize
		max_depth:        builder.max_depth
		min_depth:        builder.min_depth
		follow_links:     builder.follow_links
		same_file_system: builder.same_file_system
		threads:          builder.threads
		skip:             builder.skip
		has_skip:         builder.has_skip
		filter:           builder.filter
		has_filter:       builder.has_filter
	}
}

pub fn (mut builder WalkBuilder) add(path string) &WalkBuilder {
	builder.paths << path.to_owned()
	return builder
}

pub fn (mut builder WalkBuilder) max_depth(depth int) &WalkBuilder {
	builder.max_depth = depth
	if builder.min_depth >= 0 && builder.max_depth >= 0 && builder.max_depth < builder.min_depth {
		builder.max_depth = builder.min_depth
	}
	return builder
}

pub fn (mut builder WalkBuilder) min_depth(depth int) &WalkBuilder {
	builder.min_depth = depth
	if builder.max_depth >= 0 && builder.min_depth >= 0 && builder.min_depth > builder.max_depth {
		builder.min_depth = builder.max_depth
	}
	return builder
}

pub fn (mut builder WalkBuilder) follow_links(yes bool) &WalkBuilder {
	builder.follow_links = yes
	return builder
}

pub fn (mut builder WalkBuilder) max_filesize(filesize u64) &WalkBuilder {
	builder.max_filesize = filesize
	builder.has_max_filesize = true
	return builder
}

pub fn (mut builder WalkBuilder) clear_max_filesize() &WalkBuilder {
	builder.max_filesize = 0
	builder.has_max_filesize = false
	return builder
}

pub fn (mut builder WalkBuilder) threads(n int) &WalkBuilder {
	builder.threads = n
	return builder
}

pub fn (mut builder WalkBuilder) add_ignore(path string) (bool, IgnoreError) {
	cwd := builder.get_or_set_current_dir()
	if cwd == '' {
		return true, other_error('CWD is not known, ignoring global gitignore ${path}')
	}
	mut gitignore_builder := GitignoreBuilder.new(cwd)
	mut errs := PartialErrorBuilder{}
	has_err, err := gitignore_builder.add(path)
	errs.maybe_push(has_err, err)
	_, gi, build_err := gitignore_builder.build()
	_ = build_err
	builder.ig_builder.add_ignore(gi)
	return errs.into_error_option()
}

pub fn (mut builder WalkBuilder) add_custom_ignore_filename(file_name string) &WalkBuilder {
	builder.ig_builder.add_custom_ignore_filename(file_name)
	return builder
}

pub fn (mut builder WalkBuilder) overrides(overrides Override) &WalkBuilder {
	builder.ig_builder.overrides(overrides)
	return builder
}

pub fn (mut builder WalkBuilder) types(types Types) &WalkBuilder {
	builder.ig_builder.types(types)
	return builder
}

pub fn (mut builder WalkBuilder) standard_filters(yes bool) &WalkBuilder {
	builder.hidden(yes)
	builder.parents(yes)
	builder.ignore(yes)
	builder.git_ignore(yes)
	builder.git_global(yes)
	builder.git_exclude(yes)
	return builder
}

pub fn (mut builder WalkBuilder) hidden(yes bool) &WalkBuilder {
	builder.ig_builder.hidden(yes)
	return builder
}

pub fn (mut builder WalkBuilder) parents(yes bool) &WalkBuilder {
	builder.ig_builder.parents(yes)
	return builder
}

pub fn (mut builder WalkBuilder) ignore(yes bool) &WalkBuilder {
	builder.ig_builder.ignore(yes)
	return builder
}

pub fn (mut builder WalkBuilder) git_global(yes bool) &WalkBuilder {
	builder.ig_builder.git_global(yes)
	return builder
}

pub fn (mut builder WalkBuilder) git_ignore(yes bool) &WalkBuilder {
	builder.ig_builder.git_ignore(yes)
	return builder
}

pub fn (mut builder WalkBuilder) git_exclude(yes bool) &WalkBuilder {
	builder.ig_builder.git_exclude(yes)
	return builder
}

pub fn (mut builder WalkBuilder) require_git(yes bool) &WalkBuilder {
	builder.ig_builder.require_git(yes)
	return builder
}

pub fn (mut builder WalkBuilder) ignore_case_insensitive(yes bool) &WalkBuilder {
	builder.ig_builder.ignore_case_insensitive(yes)
	return builder
}

pub fn (mut builder WalkBuilder) sort_by_file_path(cmp PathComparator) &WalkBuilder {
	builder.sort_by_path = cmp
	builder.has_sort_by_path = true
	builder.has_sort_by_name = false
	return builder
}

pub fn (mut builder WalkBuilder) sort_by_file_name(cmp NameComparator) &WalkBuilder {
	builder.sort_by_name = cmp
	builder.has_sort_by_name = true
	builder.has_sort_by_path = false
	return builder
}

pub fn (mut builder WalkBuilder) same_file_system(yes bool) &WalkBuilder {
	builder.same_file_system = yes
	return builder
}

pub fn (mut builder WalkBuilder) skip_stdout(yes bool) &WalkBuilder {
	if yes {
		has_handle, handle := stdout_handle()
		builder.has_skip = has_handle
		builder.skip = handle
	} else {
		builder.has_skip = false
	}
	return builder
}

pub fn (mut builder WalkBuilder) filter_entry(filter FilterFn) &WalkBuilder {
	builder.filter = filter
	builder.has_filter = true
	return builder
}

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

pub struct Walk {
mut:
	entries          []WalkResult
	index            int
	ig_root          Ignore
	ig               Ignore
	max_filesize     u64
	has_max_filesize bool
	skip             Handle
	has_skip         bool
	filter           FilterFn = unsafe { nil }
	has_filter       bool
	min_depth        int
	max_depth        int
	has_max_depth    bool
	follow_links     bool
	same_file_system bool
	sort_by_name     NameComparator = unsafe { nil }
	has_sort_by_name bool
	sort_by_path     PathComparator = unsafe { nil }
	has_sort_by_path bool
}

pub fn Walk.new(path string) Walk {
	return WalkBuilder.new(path).build()
}

pub fn (mut walk Walk) next() ?WalkResult {
	if walk.index >= walk.entries.len {
		return none
	}
	result := walk.entries[walk.index]
	walk.index++
	return result
}

pub fn (walk Walk) items() []WalkResult {
	return walk.entries.clone()
}

fn (mut walk Walk) push_result(result WalkResult) {
	walk.entries << result
}

fn (mut walk Walk) add_root_path(path string) {
	if path == '-' {
		if walk.min_depth <= 0 || walk.min_depth < 0 {
			walk.push_result(walk_result_from_entry(DirEntry.new_stdin()))
		}
		return
	}
	root, err := prepare_root_entry(path, walk.follow_links)
	if err.kind != .other || err.msg != '' {
		walk.push_result(walk_result_from_error(err))
		return
	}
	mut dent := root
	mut ig := walk.ig_root
	if dent.is_dir() {
		ig2, has_err, add_err := walk.ig_root.add_parents(dent.path())
		ig = ig2
		if has_err {
			walk.push_result(walk_result_from_error(add_err))
		}
	}
	root_device := if walk.same_file_system { device_num(dent.path()) or { u64(0) } } else { u64(0) }
	has_root_device := walk.same_file_system
	walk.traverse_entry(mut dent, ig, true, root_device, has_root_device)
}

fn (mut walk Walk) traverse_entry(mut dent DirEntry, ig Ignore, is_root bool, root_device u64, has_root_device bool) {
	should_visit := walk.min_depth < 0 || dent.depth() >= walk.min_depth
	if dent.path_is_symlink() || !dent.is_dir() {
		if !is_root {
			if walk.skip_entry(ig, dent) {
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
	dent.has_err = has_child_err
	dent.err = child_err
	if !is_root {
		if walk.skip_entry(ig, dent) {
			return
		}
	}
	if should_visit {
		walk.push_result(walk_result_from_entry(dent))
	}
	if walk.has_max_depth && dent.depth() >= walk.max_depth {
		return
	}
	names := walk.read_dir_names(dent.path()) or {
		walk.push_result(walk_result_from_error(io_error(err).with_path(dent.path()).with_depth(dent.depth())))
		return
	}
	for name in names {
		child_depth := dent.depth() + 1
		mut child_raw := DirEntryRaw.from_child(child_depth, dent.path(), name) or {
			walk.push_result(walk_result_from_error(io_error(err).with_path(os.join_path(dent.path(), name)).with_depth(child_depth)))
			continue
		}
		if walk.follow_links && child_raw.path_is_symlink() {
			child_raw = DirEntryRaw.from_path(child_depth, child_raw.path, true) or {
				walk.push_result(walk_result_from_error(io_error(err).with_path(os.join_path(dent.path(), name)).with_depth(child_depth)))
				continue
			}
			if child_raw.ty.is_dir() {
				if err := check_symlink_loop(child_ignore, child_raw.path, child_depth) {
					walk.push_result(walk_result_from_error(err))
					continue
				}
			}
		}
		mut child := DirEntry.new_raw(child_raw, false, IgnoreError{})
		walk.traverse_entry(mut child, child_ignore, false, root_device, has_root_device)
	}
}

fn (walk Walk) read_dir_names(path string) ![]string {
	mut names := os.ls(path)!
	sort_names(mut names, path, walk.has_sort_by_name, walk.sort_by_name, walk.has_sort_by_path, walk.sort_by_path)
	return names
}

fn (walk Walk) skip_entry(ig Ignore, ent DirEntry) bool {
	if ent.depth() == 0 {
		return false
	}
	if should_skip_entry(ig, ent) {
		return true
	}
	if walk.has_skip {
		is_stdout := path_equals(ent, walk.skip) or { false }
		if is_stdout {
			return true
		}
	}
	if walk.has_max_filesize && !ent.is_dir() {
		if skip_filesize(walk.max_filesize, ent.path(), ent.metadata() or { return false }) {
			return true
		}
	}
	if walk.has_filter && !walk.filter(ent) {
		return true
	}
	return false
}

pub struct WalkParallel {
	paths            []string
	ig_root          Ignore
	max_filesize     u64
	has_max_filesize bool
	max_depth        int
	min_depth        int
	follow_links     bool
	same_file_system bool
	threads          int
	skip             Handle
	has_skip         bool
	filter           FilterFn = unsafe { nil }
	has_filter       bool
}

pub fn (wp WalkParallel) run(mut visitor ParallelVisitor) {
	wp.visit(visitor)
}

pub fn (wp WalkParallel) visit(mut visitor ParallelVisitor) {
	mut walk := Walk{
		ig_root:          wp.ig_root
		ig:               wp.ig_root
		max_filesize:     wp.max_filesize
		has_max_filesize: wp.has_max_filesize
		skip:             wp.skip
		has_skip:         wp.has_skip
		filter:           wp.filter
		has_filter:       wp.has_filter
		min_depth:        wp.min_depth
		max_depth:        wp.max_depth
		has_max_depth:    wp.max_depth >= 0
		follow_links:     wp.follow_links
		same_file_system: wp.same_file_system
	}
	for path in wp.paths {
		walk.add_root_path(path)
	}
	for item in walk.items() {
		state := visitor.visit(item)
		if state.is_quit() {
			break
		}
	}
}

fn prepare_root_entry(path string, follow_links bool) (DirEntry, IgnoreError) {
	link_root := follow_links || os.is_file(path)
	mut raw := DirEntryRaw.from_path(0, path, link_root) or {
		return DirEntry{}, io_error(err).with_path(path)
	}
	if !follow_links && raw.ty == .symbolic_link {
		if target_is_dir(path) {
			raw = DirEntryRaw.from_path(0, path, true) or {
				return DirEntry{}, io_error(err).with_path(path)
			}
		}
	}
	return DirEntry.new_raw(raw, false, IgnoreError{}), IgnoreError{}
}

fn target_is_dir(path string) bool {
	return os.is_dir(path)
}

fn sort_names(mut names []string, parent_path string, has_name_cmp bool, name_cmp NameComparator, has_path_cmp bool, path_cmp PathComparator) {
	for i := 0; i < names.len; i++ {
		for j := i + 1; j < names.len; j++ {
			mut cmp := 0
			if has_name_cmp {
				cmp = name_cmp(names[i], names[j])
			} else if has_path_cmp {
				cmp = path_cmp(os.join_path(parent_path, names[i]), os.join_path(parent_path, names[j]))
			}
			if cmp > 0 {
				names[i], names[j] = names[j], names[i]
			}
		}
	}
}

fn check_symlink_loop(ig_parent Ignore, child_path string, child_depth int) ?IgnoreError {
	hchild := Handle.from_path(child_path) or {
		return io_error(err).with_path(child_path).with_depth(child_depth)
	}
	for i := ig_parent.layers.len - 1; i >= 0; i-- {
		layer := ig_parent.layers[i]
		if layer.absolute_parent {
			break
		}
		h := Handle.from_path(layer.path) or {
			return io_error(err).with_path(child_path).with_depth(child_depth)
		}
		if h.path == hchild.path {
			return loop_error(layer.path, child_path).with_depth(child_depth)
		}
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

fn should_skip_entry(ig Ignore, dent DirEntry) bool {
	matched := ig.matched_dir_entry(dent)
	if matched.is_ignore() {
		return true
	}
	return false
}

fn path_equals(dent DirEntry, handle Handle) !bool {
	if dent.is_stdin() {
		return false
	}
	other := Handle.from_path(dent.path())!
	return other.path == handle.path
}

fn is_same_file_system(root_device u64, path string) !bool {
	return root_device == device_num(path)!
}

fn device_num(path string) !u64 {
	_ = path
	return u64(0)
}

fn detect_followed_type(path string) EntryFileType {
	if os.is_dir(path) {
		return .directory
	}
	if os.is_file(path) {
		return .file
	}
	return .other
}

fn detect_unfollowed_type(path string, source_is_symlink bool) EntryFileType {
	if source_is_symlink {
		return .symbolic_link
	}
	if os.is_dir(path) {
		return .directory
	}
	if os.is_file(path) {
		return .file
	}
	return .other
}
