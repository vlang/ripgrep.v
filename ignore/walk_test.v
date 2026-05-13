module ignore

import os

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

fn mkpaths(paths []string) []string {
	mut got := paths.clone()
	got.sort()
	return got
}

fn assert_paths(prefix string, builder WalkBuilder, expected []string) {
	got := walk_collect(prefix, builder)
	assert got == mkpaths(expected), 'single threaded'
	got_parallel := walk_collect_parallel(prefix, builder)
	assert got_parallel == mkpaths(expected), 'parallel'
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

fn test_no_ignores() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), 'a/b/c'))
	mkdirp(os.join_path(td.path(), 'x/y'))
	wfile(os.join_path(td.path(), 'a/b/foo'), '')
	wfile(os.join_path(td.path(), 'x/y/foo'), '')

	assert_paths(td.path(), WalkBuilder.new(td.path()), ['x', 'x/y', 'x/y/foo', 'a', 'a/b', 'a/b/foo', 'a/b/c'])
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
	assert !has_err
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
	assert !has_err
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

	assert_paths(td.path(), WalkBuilder.new(td.path()), ['a', 'a/b', 'a/b/c', 'foo', 'a/foo', 'a/b/foo', 'a/b/c/foo'])

	mut builder0 := WalkBuilder.new(td.path())
	builder0.max_depth(0)
	assert_paths(td.path(), builder0, []string{})

	mut builder1 := WalkBuilder.new(td.path())
	builder1.max_depth(1)
	assert_paths(td.path(), builder1, ['a', 'foo'])

	mut builder2 := WalkBuilder.new(td.path())
	builder2.max_depth(2)
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

	assert_paths(td.path(), WalkBuilder.new(td.path()), ['a', 'a/b', 'a/b/c', 'foo', 'a/foo', 'a/b/foo', 'a/b/c/foo'])

	mut builder0 := WalkBuilder.new(td.path())
	builder0.min_depth(0)
	assert_paths(td.path(), builder0, ['a', 'a/b', 'a/b/c', 'foo', 'a/foo', 'a/b/foo', 'a/b/c/foo'])

	mut builder1 := WalkBuilder.new(td.path())
	builder1.min_depth(1)
	assert_paths(td.path(), builder1, ['a', 'a/b', 'a/b/c', 'foo', 'a/foo', 'a/b/foo', 'a/b/c/foo'])

	mut builder2 := WalkBuilder.new(td.path())
	builder2.min_depth(2)
	assert_paths(td.path(), builder2, ['a/b', 'a/b/c', 'a/b/c/foo', 'a/b/foo', 'a/foo'])

	mut builder3 := WalkBuilder.new(td.path())
	builder3.min_depth(3)
	assert_paths(td.path(), builder3, ['a/b/c', 'a/b/c/foo', 'a/b/foo'])

	mut builder10 := WalkBuilder.new(td.path())
	builder10.min_depth(10)
	assert_paths(td.path(), builder10, []string{})

	mut builder21 := WalkBuilder.new(td.path())
	builder21.min_depth(2)
	builder21.max_depth(1)
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

	assert_paths(td.path(), WalkBuilder.new(td.path()), ['a', 'a/b', 'foo', 'bar', 'baz', 'a/foo', 'a/bar', 'a/baz'])

	mut builder0 := WalkBuilder.new(td.path())
	builder0.max_filesize(0)
	assert_paths(td.path(), builder0, ['a', 'a/b', 'foo'])

	mut builder500 := WalkBuilder.new(td.path())
	builder500.max_filesize(500)
	assert_paths(td.path(), builder500, ['a', 'a/b', 'foo', 'bar', 'a/bar', 'a/baz'])

	mut builder50000 := WalkBuilder.new(td.path())
	builder50000.max_filesize(50000)
	assert_paths(td.path(), builder50000, ['a', 'a/b', 'foo', 'bar', 'baz', 'a/foo', 'a/bar', 'a/baz'])
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
	assert dents.len == 1
	assert !dents[0].path_is_symlink()

	parallel_dents := walk_collect_entries_parallel(WalkBuilder.new(os.join_path(td.path(), 'foo')))
	assert parallel_dents.len == 1
	assert !parallel_dents[0].path_is_symlink()
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
	return entry.file_name() != 'a'
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

	assert_paths(td.path(), WalkBuilder.new(td.path()), ['x', 'x/y', 'x/y/foo', 'a', 'a/b', 'a/b/foo', 'a/b/c'])

	mut builder := WalkBuilder.new(td.path())
	builder.filter_entry(filter_not_a)
	assert_paths(td.path(), builder, ['x', 'x/y', 'x/y/foo'])
}
