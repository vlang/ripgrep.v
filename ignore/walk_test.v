module ignore

import os
import sync.stdatomic

fn wfile(path string, contents string) {
	os.write_file(path, contents) or { panic(err.msg()) }
}

fn wfile_size(path string, size u64) {
	os.write_file(path, '') or { panic(err.msg()) }
	os.truncate(path, size) or { panic(err.msg()) }
}

fn symlink(src string, dst string) {
	os.symlink(src, dst) or { panic(err.msg()) }
}

fn mkdirp(path string) {
	os.mkdir_all(path) or { panic(err.msg()) }
}

fn normal_path(unix string) string {
	if os.user_os() == 'windows' {
		return unix.replace('\\', '/')
	}
	return unix.to_owned()
}

fn walk_collect(prefix string, builder WalkBuilder) []string {
	mut paths := []string{}
	mut walk := builder.build()
	for {
		result := walk.next() or { break }
		if result.is_error {
			continue
		}
		path := strip_prefix(result.entry.path(), prefix)
		if path == '' {
			continue
		}
		paths << normal_path(path)
	}
	paths.sort()
	return paths
}

struct ParallelCollector {
mut:
	dents []DirEntry
}

fn (mut collector ParallelCollector) visit(result WalkResult) WalkState {
	if !result.is_error {
		collector.dents << result.entry
	}
	return .continue_
}

fn walk_collect_entries_parallel(builder WalkBuilder) []DirEntry {
	mut collector := ParallelCollector{}
	builder.build_parallel().run(mut collector)
	return collector.dents
}

struct ParallelSkipCollector {
mut:
	paths []string
}

fn (mut collector ParallelSkipCollector) visit(result WalkResult) WalkState {
	if result.is_error {
		return .continue_
	}
	collector.paths << (*result.entry.path()).to_owned()
	if *result.entry.file_name() == 'skip' {
		return .skip
	}
	return .continue_
}

fn walk_collect_parallel(prefix string, builder WalkBuilder) []string {
	mut paths := []string{}
	for dent in walk_collect_entries_parallel(builder) {
		path := strip_prefix(dent.path(), prefix)
		if path == '' {
			continue
		}
		paths << normal_path(path)
	}
	paths.sort()
	return paths
}

fn walk_parallel_stream_test_runner(walk WalkParallel, events chan WalkParallelStreamResult, stop &stdatomic.AtomicVal[bool]) bool {
	walk.stream(events, stop)
	return true
}

fn walk_collect_stream(prefix string, builder WalkBuilder) []string {
	stop := stdatomic.new_atomic(false)
	events := chan WalkParallelStreamResult{cap: 32}
	stream := spawn walk_parallel_stream_test_runner(builder.build_parallel(), events, stop)
	mut paths := []string{}
	for {
		event := <-events
		if event.done {
			break
		}
		if event.result.is_error {
			continue
		}
		path := strip_prefix(event.result.entry.path(), prefix)
		if path == '' {
			continue
		}
		paths << normal_path(path)
	}
	stream.wait()
	paths.sort()
	return paths
}

fn mkpaths(paths []string) []string {
	mut got := paths.clone()
	got.sort()
	return got
}

fn assert_paths(prefix string, builder WalkBuilder, expected []string) {
	want := mkpaths(expected)
	got := walk_collect(prefix, builder)
	if got != want {
		panic('single threaded got ${got}, want ${want}')
	}
	got_parallel := walk_collect_parallel(prefix, builder)
	if got_parallel != want {
		panic('parallel got ${got_parallel}, want ${want}')
	}
}

fn walk_collect_entries(builder WalkBuilder) []DirEntry {
	mut dents := []DirEntry{}
	mut walk := builder.build()
	for {
		result := walk.next() or { break }
		if !result.is_error {
			dents << result.entry
		}
	}
	return dents
}

fn test_walk_build_is_lazy() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mut walk := WalkBuilder.new(td.path()).build()
	wfile(os.join_path(td.path(), 'late.txt'), '')
	mut got := []string{}
	for {
		result := walk.next() or { break }
		if result.is_error {
			continue
		}
		path := strip_prefix(result.entry.path(), td.path())
		if path != '' {
			got << normal_path(path)
		}
	}
	if 'late.txt' !in got {
		panic('late file missing from ${got}')
	}
}

fn test_no_ignores() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), 'a/b/c'))
	mkdirp(os.join_path(td.path(), 'x/y'))
	wfile(os.join_path(td.path(), 'a/b/foo'), '')
	wfile(os.join_path(td.path(), 'x/y/foo'), '')

	assert_paths(td.path(), WalkBuilder.new(td.path()), ['x', 'x/y', 'x/y/foo', 'a', 'a/b', 'a/b/foo',
		'a/b/c'])
}

fn test_custom_ignore() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	custom_ignore := '.customignore'
	mkdirp(os.join_path(td.path(), 'a'))
	wfile(os.join_path(td.path(), custom_ignore), 'foo')
	wfile(os.join_path(td.path(), 'foo'), '')
	wfile(os.join_path(td.path(), 'a/foo'), '')
	wfile(os.join_path(td.path(), 'bar'), '')
	wfile(os.join_path(td.path(), 'a/bar'), '')

	mut builder := WalkBuilder.new(td.path())
	builder.add_custom_ignore_filename(custom_ignore)
	assert_paths(td.path(), builder, ['bar', 'a', 'a/bar'])
}

fn test_custom_ignore_exclusive_use() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	custom_ignore := '.customignore'
	mkdirp(os.join_path(td.path(), 'a'))
	wfile(os.join_path(td.path(), custom_ignore), 'foo')
	wfile(os.join_path(td.path(), 'foo'), '')
	wfile(os.join_path(td.path(), 'a/foo'), '')
	wfile(os.join_path(td.path(), 'bar'), '')
	wfile(os.join_path(td.path(), 'a/bar'), '')

	mut builder := WalkBuilder.new(td.path())
	builder.ignore(false)
	builder.git_ignore(false)
	builder.git_global(false)
	builder.git_exclude(false)
	builder.add_custom_ignore_filename(custom_ignore)
	assert_paths(td.path(), builder, ['bar', 'a', 'a/bar'])
}

fn test_gitignore() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), '.git'))
	mkdirp(os.join_path(td.path(), 'a'))
	wfile(os.join_path(td.path(), '.gitignore'), 'foo')
	wfile(os.join_path(td.path(), 'foo'), '')
	wfile(os.join_path(td.path(), 'a/foo'), '')
	wfile(os.join_path(td.path(), 'bar'), '')
	wfile(os.join_path(td.path(), 'a/bar'), '')

	assert_paths(td.path(), WalkBuilder.new(td.path()), ['bar', 'a', 'a/bar'])
}

fn test_explicit_ignore() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	igpath := os.join_path(td.path(), '.not-an-ignore')
	mkdirp(os.join_path(td.path(), 'a'))
	wfile(igpath, 'foo')
	wfile(os.join_path(td.path(), 'foo'), '')
	wfile(os.join_path(td.path(), 'a/foo'), '')
	wfile(os.join_path(td.path(), 'bar'), '')
	wfile(os.join_path(td.path(), 'a/bar'), '')

	mut builder := WalkBuilder.new(td.path())
	has_err, _ := builder.add_ignore(igpath)
	if has_err {
		panic('explicit ignore should parse without error')
	}
	assert_paths(td.path(), builder, ['bar', 'a', 'a/bar'])
}

fn test_explicit_ignore_exclusive_use() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	igpath := os.join_path(td.path(), '.not-an-ignore')
	mkdirp(os.join_path(td.path(), 'a'))
	wfile(igpath, 'foo')
	wfile(os.join_path(td.path(), 'foo'), '')
	wfile(os.join_path(td.path(), 'a/foo'), '')
	wfile(os.join_path(td.path(), 'bar'), '')
	wfile(os.join_path(td.path(), 'a/bar'), '')

	mut builder := WalkBuilder.new(td.path())
	builder.standard_filters(false)
	has_err, _ := builder.add_ignore(igpath)
	if has_err {
		panic('explicit ignore should parse without error')
	}
	assert_paths(td.path(), builder, ['.not-an-ignore', 'bar', 'a', 'a/bar'])
}

fn test_gitignore_parent() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), '.git'))
	mkdirp(os.join_path(td.path(), 'a'))
	wfile(os.join_path(td.path(), '.gitignore'), 'foo')
	wfile(os.join_path(td.path(), 'a/foo'), '')
	wfile(os.join_path(td.path(), 'a/bar'), '')

	root := os.join_path(td.path(), 'a')
	assert_paths(root, WalkBuilder.new(root), ['bar'])
}

fn test_max_depth() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), 'a/b/c'))
	wfile(os.join_path(td.path(), 'foo'), '')
	wfile(os.join_path(td.path(), 'a/foo'), '')
	wfile(os.join_path(td.path(), 'a/b/foo'), '')
	wfile(os.join_path(td.path(), 'a/b/c/foo'), '')

	assert_paths(td.path(), WalkBuilder.new(td.path()), ['a', 'a/b', 'a/b/c', 'foo', 'a/foo',
		'a/b/foo', 'a/b/c/foo'])

	mut builder0 := WalkBuilder.new(td.path())
	builder0.max_depth(usize(0))
	assert_paths(td.path(), builder0, []string{})

	mut builder1 := WalkBuilder.new(td.path())
	builder1.max_depth(usize(1))
	assert_paths(td.path(), builder1, ['a', 'foo'])

	mut builder2 := WalkBuilder.new(td.path())
	builder2.max_depth(usize(2))
	assert_paths(td.path(), builder2, ['a', 'a/b', 'foo', 'a/foo'])
}

fn test_min_depth() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), 'a/b/c'))
	wfile(os.join_path(td.path(), 'foo'), '')
	wfile(os.join_path(td.path(), 'a/foo'), '')
	wfile(os.join_path(td.path(), 'a/b/foo'), '')
	wfile(os.join_path(td.path(), 'a/b/c/foo'), '')

	assert_paths(td.path(), WalkBuilder.new(td.path()), ['a', 'a/b', 'a/b/c', 'foo', 'a/foo',
		'a/b/foo', 'a/b/c/foo'])

	mut builder0 := WalkBuilder.new(td.path())
	builder0.min_depth(usize(0))
	assert_paths(td.path(), builder0, ['a', 'a/b', 'a/b/c', 'foo', 'a/foo', 'a/b/foo', 'a/b/c/foo'])

	mut builder1 := WalkBuilder.new(td.path())
	builder1.min_depth(usize(1))
	assert_paths(td.path(), builder1, ['a', 'a/b', 'a/b/c', 'foo', 'a/foo', 'a/b/foo', 'a/b/c/foo'])

	mut builder2 := WalkBuilder.new(td.path())
	builder2.min_depth(usize(2))
	assert_paths(td.path(), builder2, ['a/b', 'a/b/c', 'a/b/c/foo', 'a/b/foo', 'a/foo'])

	mut builder3 := WalkBuilder.new(td.path())
	builder3.min_depth(usize(3))
	assert_paths(td.path(), builder3, ['a/b/c', 'a/b/c/foo', 'a/b/foo'])

	mut builder10 := WalkBuilder.new(td.path())
	builder10.min_depth(usize(10))
	assert_paths(td.path(), builder10, []string{})

	mut builder21 := WalkBuilder.new(td.path())
	builder21.min_depth(usize(2))
	builder21.max_depth(usize(1))
	assert_paths(td.path(), builder21, ['a/b', 'a/foo'])
}

fn test_max_filesize() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), 'a/b'))
	wfile_size(os.join_path(td.path(), 'foo'), 0)
	wfile_size(os.join_path(td.path(), 'bar'), 400)
	wfile_size(os.join_path(td.path(), 'baz'), 600)
	wfile_size(os.join_path(td.path(), 'a/foo'), 600)
	wfile_size(os.join_path(td.path(), 'a/bar'), 500)
	wfile_size(os.join_path(td.path(), 'a/baz'), 200)

	assert_paths(td.path(), WalkBuilder.new(td.path()), ['a', 'a/b', 'foo', 'bar', 'baz', 'a/foo',
		'a/bar', 'a/baz'])

	mut builder0 := WalkBuilder.new(td.path())
	builder0.max_filesize(u64(0))
	assert_paths(td.path(), builder0, ['a', 'a/b', 'foo'])

	mut builder500 := WalkBuilder.new(td.path())
	builder500.max_filesize(u64(500))
	assert_paths(td.path(), builder500, ['a', 'a/b', 'foo', 'bar', 'a/bar', 'a/baz'])

	mut builder50000 := WalkBuilder.new(td.path())
	builder50000.max_filesize(u64(50000))
	assert_paths(td.path(), builder50000,
		['a', 'a/b', 'foo', 'bar', 'baz', 'a/foo', 'a/bar', 'a/baz'])
}

// because symlinks on windows are weird
fn test_symlinks() {
	$if windows {
		return
	}
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), 'a/b'))
	symlink(os.join_path(td.path(), 'a/b'), os.join_path(td.path(), 'z'))
	wfile(os.join_path(td.path(), 'a/b/foo'), '')

	mut builder := WalkBuilder.new(td.path())
	assert_paths(td.path(), builder, ['a', 'a/b', 'a/b/foo', 'z'])

	mut follow_builder := WalkBuilder.new(td.path())
	follow_builder.follow_links(true)
	assert_paths(td.path(), follow_builder, ['a', 'a/b', 'a/b/foo', 'z', 'z/foo'])
}

// because symlinks on windows are weird
fn test_first_path_not_symlink() {
	$if windows {
		return
	}
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), 'foo'))

	dents := walk_collect_entries(WalkBuilder.new(os.join_path(td.path(), 'foo')))
	if dents.len != 1 {
		panic('single root entry count: ${dents.len}')
	}
	if dents[0].path_is_symlink() {
		panic('single root should not be marked symlink')
	}

	parallel_dents := walk_collect_entries_parallel(WalkBuilder.new(os.join_path(td.path(), 'foo')))
	if parallel_dents.len != 1 {
		panic('parallel root entry count: ${parallel_dents.len}')
	}
	if parallel_dents[0].path_is_symlink() {
		panic('parallel root should not be marked symlink')
	}
}

// because symlinks on windows are weird
fn test_symlink_loop() {
	$if windows {
		return
	}
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), 'a/b'))
	symlink(os.join_path(td.path(), 'a'), os.join_path(td.path(), 'a/b/c'))

	mut builder := WalkBuilder.new(td.path())
	assert_paths(td.path(), builder, ['a', 'a/b', 'a/b/c'])

	mut follow_builder := WalkBuilder.new(td.path())
	follow_builder.follow_links(true)
	assert_paths(td.path(), follow_builder, ['a', 'a/b'])
}

// It's a little tricky to test the 'same_file_system' option since
// we need an environment with more than one file system. We adopt a
// heuristic where /sys is typically a distinct volume on Linux and roll
// with that.
fn test_same_file_system() {
	$if linux {
		// If for some reason /sys doesn't exist or isn't a directory, just
		// skip this test.
		if !os.is_dir('/sys') {
			return
		}

		// If our test directory actually isn't a different volume from /sys,
		// then this test is meaningless and we shouldn't run it.
		td := tmpdir()
		defer {
			td.cleanup()
		}
		if device_num(td.path()) or { u64(0) } == device_num('/sys') or { u64(0) } {
			return
		}

		mkdirp(os.join_path(td.path(), 'same_file'))
		symlink('/sys', os.join_path(td.path(), 'same_file/alink'))

		// Create a symlink to sys and enable following symlinks. If the
		// same_file_system option doesn't work, then this probably will hit a
		// permission error. Otherwise, it should just skip over the symlink
		// completely.
		mut builder := WalkBuilder.new(td.path())
		builder.follow_links(true)
		builder.same_file_system(true)
		assert_paths(td.path(), builder, ['same_file', 'same_file/alink'])
	}
}

fn test_no_read_permissions() {
	$if linux {
		dir_path := '/root'

		// There's no /etc/sudoers.d, skip the test.
		if !os.is_dir(dir_path) {
			return
		}
		// We're the root, so the test won't check what we want it to.
		if os.is_readable(dir_path) {
			return
		}

		// Check that we can't descend but get an entry for the parent dir.
		parent := os.dir(dir_path)
		assert_paths(parent, WalkBuilder.new(dir_path), ['root'])
	}
}

fn filter_not_a(entry DirEntry) bool {
	return *entry.file_name() != 'a'
}

fn test_filter() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), 'a/b/c'))
	mkdirp(os.join_path(td.path(), 'x/y'))
	wfile(os.join_path(td.path(), 'a/b/foo'), '')
	wfile(os.join_path(td.path(), 'x/y/foo'), '')

	assert_paths(td.path(), WalkBuilder.new(td.path()), ['x', 'x/y', 'x/y/foo', 'a', 'a/b', 'a/b/foo',
		'a/b/c'])

	mut builder := WalkBuilder.new(td.path())
	builder.filter_entry(filter_not_a)
	assert_paths(td.path(), builder, ['x', 'x/y', 'x/y/foo'])
}

fn test_parallel_skip_prevents_descent() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	root1 := os.join_path(td.path(), 'one')
	root2 := os.join_path(td.path(), 'two')
	mkdirp(os.join_path(root1, 'skip/child'))
	mkdirp(os.join_path(root2, 'keep/child'))
	wfile(os.join_path(root1, 'skip/child/file'), '')
	wfile(os.join_path(root2, 'keep/child/file'), '')

	mut builder := WalkBuilder.new(root1)
	builder.add(root2)
	builder.threads(2)
	mut collector := ParallelSkipCollector{}
	builder.build_parallel().run(mut collector)

	mut paths := []string{}
	for path in collector.paths {
		paths << normal_path(strip_prefix(path, td.path()))
	}
	paths.sort()
	if 'one/skip' !in paths {
		panic('missing one/skip from ${paths}')
	}
	if 'one/skip/child' in paths {
		panic('skip descended into child: ${paths}')
	}
	if 'one/skip/child/file' in paths {
		panic('skip descended into file: ${paths}')
	}
	if 'two/keep/child/file' !in paths {
		panic('missing keep file from ${paths}')
	}
}

fn test_parallel_single_root_uses_requested_workers() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mut builder := WalkBuilder.new(td.path())
	builder.threads(4)
	if builder.build_parallel().worker_count() != 4 {
		panic('explicit worker count was not preserved')
	}
}

fn test_parallel_stream_collects_single_root_children() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), 'a/b'))
	mkdirp(os.join_path(td.path(), 'x/y'))
	wfile(os.join_path(td.path(), 'a/b/foo'), '')
	wfile(os.join_path(td.path(), 'x/y/bar'), '')

	mut builder := WalkBuilder.new(td.path())
	builder.threads(4)
	got := walk_collect_stream(td.path(), builder)
	want := mkpaths(['a', 'a/b', 'a/b/foo', 'x', 'x/y', 'x/y/bar'])
	if got != want {
		panic('stream got ${got}, want ${want}')
	}
}

fn test_parallel_single_root_child_gitignore() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), '.git'))
	mkdirp(os.join_path(td.path(), 'cmd/v2'))
	mkdirp(os.join_path(td.path(), 'vlib/db/sqlite'))
	wfile(os.join_path(td.path(), 'cmd/v2/.gitignore'), '*.c')
	wfile(os.join_path(td.path(), 'cmd/v2/keep.v'), '')
	wfile(os.join_path(td.path(), 'cmd/v2/drop.c'), '')
	wfile(os.join_path(td.path(), 'vlib/db/sqlite/README.md'), '')

	mut builder := WalkBuilder.new(td.path())
	builder.threads(4)
	expected := ['cmd', 'cmd/v2', 'cmd/v2/keep.v', 'vlib', 'vlib/db', 'vlib/db/sqlite',
		'vlib/db/sqlite/README.md']
	want := mkpaths(expected)
	got_single := walk_collect(td.path(), builder.clone())
	if got_single != want {
		panic('single threaded got ${got_single}, want ${want}')
	}
	got_parallel := walk_collect_parallel(td.path(), builder.clone())
	if got_parallel != want {
		panic('parallel got ${got_parallel}, want ${want}')
	}
	got_stream := walk_collect_stream(td.path(), builder)
	if got_stream != want {
		panic('stream got ${got_stream}, want ${want}')
	}
}

fn test_parallel_single_root_skip_prevents_descent() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), 'skip/child'))
	mkdirp(os.join_path(td.path(), 'keep/child'))
	wfile(os.join_path(td.path(), 'skip/child/file'), '')
	wfile(os.join_path(td.path(), 'keep/child/file'), '')

	mut builder := WalkBuilder.new(td.path())
	builder.threads(4)
	mut collector := ParallelSkipCollector{}
	builder.build_parallel().run(mut collector)

	mut paths := []string{}
	for path in collector.paths {
		paths << normal_path(strip_prefix(path, td.path()))
	}
	paths.sort()
	if 'skip' !in paths {
		panic('missing skip from ${paths}')
	}
	if 'skip/child' in paths {
		panic('skip descended into child: ${paths}')
	}
	if 'skip/child/file' in paths {
		panic('skip descended into file: ${paths}')
	}
	if 'keep/child/file' !in paths {
		panic('missing keep file from ${paths}')
	}
}
