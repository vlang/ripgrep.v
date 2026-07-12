module ignore

import os

fn wfile(path string, contents string) {
	os.write_file(path, contents) or { panic(err.msg()) }
}

fn mkdirp(path string) {
	os.mkdir_all(path) or { panic(err.msg()) }
}

fn partial(err IgnoreError) []IgnoreError {
	match err.kind {
		.partial { return err.nested }
		else { panic('expected partial error') }
	}
}

fn test_explicit_ignore() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	wfile(os.join_path(td.path(), 'not-an-ignore'), 'foo\n!bar')

	gi, gi_has_err, _ := Gitignore.new(os.join_path(td.path(), 'not-an-ignore'))
	assert !gi_has_err
	mut builder := IgnoreBuilder.new()
	builder.add_ignore(gi)
	ig, add_has_err, _ := builder.build().add_child(td.path())
	assert !add_has_err
	assert ig.matched('foo', false).is_ignore()
	assert ig.matched('bar', false).is_whitelist()
	assert ig.matched('baz', false).is_none()
}

fn test_git_exclude() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), '.git/info'))
	wfile(os.join_path(td.path(), '.git/info/exclude'), 'foo\n!bar')

	ig, has_err, _ := IgnoreBuilder.new().build().add_child(td.path())
	assert !has_err
	assert ig.matched('foo', false).is_ignore()
	assert ig.matched('bar', false).is_whitelist()
	assert ig.matched('baz', false).is_none()
}

fn test_gitignore() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), '.git'))
	wfile(os.join_path(td.path(), '.gitignore'), 'foo\n!bar')

	ig, has_err, _ := IgnoreBuilder.new().build().add_child(td.path())
	assert !has_err
	assert ig.matched('foo', false).is_ignore()
	assert ig.matched('bar', false).is_whitelist()
	assert ig.matched('baz', false).is_none()
}

fn test_gitignore_with_jj() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), '.jj'))
	wfile(os.join_path(td.path(), '.gitignore'), 'foo\n!bar')

	ig, has_err, _ := IgnoreBuilder.new().build().add_child(td.path())
	assert !has_err
	assert ig.matched('foo', false).is_ignore()
	assert ig.matched('bar', false).is_whitelist()
	assert ig.matched('baz', false).is_none()
}

fn test_gitignore_no_git() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	wfile(os.join_path(td.path(), '.gitignore'), 'foo\n!bar')

	ig, has_err, _ := IgnoreBuilder.new().build().add_child(td.path())
	assert !has_err
	assert ig.matched('foo', false).is_none()
	assert ig.matched('bar', false).is_none()
	assert ig.matched('baz', false).is_none()
}

fn test_gitignore_allowed_no_git() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	wfile(os.join_path(td.path(), '.gitignore'), 'foo\n!bar')

	mut builder := IgnoreBuilder.new()
	builder.require_git(false)
	ig, has_err, _ := builder.build().add_child(td.path())
	assert !has_err
	assert ig.matched('foo', false).is_ignore()
	assert ig.matched('bar', false).is_whitelist()
	assert ig.matched('baz', false).is_none()
}

fn test_ignore() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	wfile(os.join_path(td.path(), '.ignore'), 'foo\n!bar')

	ig, has_err, _ := IgnoreBuilder.new().build().add_child(td.path())
	assert !has_err
	assert ig.matched('foo', false).is_ignore()
	assert ig.matched('bar', false).is_whitelist()
	assert ig.matched('baz', false).is_none()
}

fn test_custom_ignore() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	custom_ignore := '.customignore'
	wfile(os.join_path(td.path(), custom_ignore), 'foo\n!bar')

	mut builder := IgnoreBuilder.new()
	builder.add_custom_ignore_filename(custom_ignore)
	ig, has_err, _ := builder.build().add_child(td.path())
	assert !has_err
	assert ig.matched('foo', false).is_ignore()
	assert ig.matched('bar', false).is_whitelist()
	assert ig.matched('baz', false).is_none()
}

// Tests that a custom ignore file will override an .ignore.
fn test_custom_ignore_over_ignore() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	custom_ignore := '.customignore'
	wfile(os.join_path(td.path(), '.ignore'), 'foo')
	wfile(os.join_path(td.path(), custom_ignore), '!foo')

	mut builder := IgnoreBuilder.new()
	builder.add_custom_ignore_filename(custom_ignore)
	ig, has_err, _ := builder.build().add_child(td.path())
	assert !has_err
	assert ig.matched('foo', false).is_whitelist()
}

// Tests that earlier custom ignore files have lower precedence than later.
fn test_custom_ignore_precedence() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	custom_ignore1 := '.customignore1'
	custom_ignore2 := '.customignore2'
	wfile(os.join_path(td.path(), custom_ignore1), 'foo')
	wfile(os.join_path(td.path(), custom_ignore2), '!foo')

	mut builder := IgnoreBuilder.new()
	builder.add_custom_ignore_filename(custom_ignore1)
	builder.add_custom_ignore_filename(custom_ignore2)
	ig, has_err, _ := builder.build().add_child(td.path())
	assert !has_err
	assert ig.matched('foo', false).is_whitelist()
}

// Tests that an .ignore will override a .gitignore.
fn test_ignore_over_gitignore() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	wfile(os.join_path(td.path(), '.gitignore'), 'foo')
	wfile(os.join_path(td.path(), '.ignore'), '!foo')

	ig, has_err, _ := IgnoreBuilder.new().build().add_child(td.path())
	assert !has_err
	assert ig.matched('foo', false).is_whitelist()
}

// Tests that exclude has lower precedent than both .ignore and .gitignore.
fn test_exclude_lowest() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	wfile(os.join_path(td.path(), '.gitignore'), '!foo')
	wfile(os.join_path(td.path(), '.ignore'), '!bar')
	mkdirp(os.join_path(td.path(), '.git/info'))
	wfile(os.join_path(td.path(), '.git/info/exclude'), 'foo\nbar\nbaz')

	ig, has_err, _ := IgnoreBuilder.new().build().add_child(td.path())
	assert !has_err
	assert ig.matched('baz', false).is_ignore()
	assert ig.matched('foo', false).is_whitelist()
	assert ig.matched('bar', false).is_whitelist()
}

fn test_errored() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	wfile(os.join_path(td.path(), '.gitignore'), '{foo')

	_, has_err, _ := IgnoreBuilder.new().build().add_child(td.path())
	assert has_err
}

fn test_errored_both() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	wfile(os.join_path(td.path(), '.gitignore'), '{foo')
	wfile(os.join_path(td.path(), '.ignore'), '{bar')

	_, has_err, err := IgnoreBuilder.new().build().add_child(td.path())
	assert has_err
	assert partial(err).len == 2
}

fn test_errored_partial() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), '.git'))
	wfile(os.join_path(td.path(), '.gitignore'), '{foo\nbar')

	ig, has_err, _ := IgnoreBuilder.new().build().add_child(td.path())
	assert has_err
	assert ig.matched('bar', false).is_ignore()
}

fn test_errored_partial_and_ignore() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	wfile(os.join_path(td.path(), '.gitignore'), '{foo\nbar')
	wfile(os.join_path(td.path(), '.ignore'), '!bar')

	ig, has_err, _ := IgnoreBuilder.new().build().add_child(td.path())
	assert has_err
	assert ig.matched('bar', false).is_whitelist()
}

fn test_not_present_empty() {
	td := tmpdir()
	defer {
		td.cleanup()
	}

	_, has_err, _ := IgnoreBuilder.new().build().add_child(td.path())
	assert !has_err
}

fn test_stops_at_git_dir() {
	// This tests that .gitignore files beyond a .git barrier aren't
	// matched, but .ignore files are.
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), '.git'))
	mkdirp(os.join_path(td.path(), 'foo/.git'))
	wfile(os.join_path(td.path(), '.gitignore'), 'foo')
	wfile(os.join_path(td.path(), '.ignore'), 'bar')

	ig0 := IgnoreBuilder.new().build()
	ig1, has_err1, _ := ig0.add_child(td.path())
	assert !has_err1
	ig2, has_err2, _ := ig1.add_child(os.join_path(ig1.path(), 'foo'))
	assert !has_err2

	assert ig1.matched('foo', false).is_ignore()
	assert ig2.matched('foo', false).is_none()

	assert ig1.matched('bar', false).is_ignore()
	assert ig2.matched('bar', false).is_ignore()
}

fn test_absolute_parent() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), '.git'))
	mkdirp(os.join_path(td.path(), 'foo'))
	wfile(os.join_path(td.path(), '.gitignore'), 'bar')

	// First, check that the parent gitignore file isn't detected if the
	// parent isn't added. This establishes a baseline.
	ig0 := IgnoreBuilder.new().build()
	ig1, has_err1, _ := ig0.add_child(os.join_path(td.path(), 'foo'))
	assert !has_err1
	assert ig1.matched('bar', false).is_none()

	// Second, check that adding a parent directory actually works.
	ig0b := IgnoreBuilder.new().build()
	ig1b, has_err2, _ := ig0b.add_parents(os.join_path(td.path(), 'foo'))
	assert !has_err2
	ig2, has_err3, _ := ig1b.add_child(os.join_path(td.path(), 'foo'))
	assert !has_err3
	assert ig2.matched('bar', false).is_ignore()
}

fn test_absolute_parent_anchored() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), '.git'))
	mkdirp(os.join_path(td.path(), 'src/llvm'))
	wfile(os.join_path(td.path(), '.gitignore'), '/llvm/\nfoo')

	ig0 := IgnoreBuilder.new().build()
	ig1, has_err1, _ := ig0.add_parents(os.join_path(td.path(), 'src'))
	assert !has_err1
	ig2, has_err2, _ := ig1.add_child('src')
	assert !has_err2

	assert ig1.matched('llvm', true).is_none()
	assert ig2.matched('llvm', true).is_none()
	assert ig2.matched('src/llvm', true).is_none()
	assert ig2.matched('foo', false).is_ignore()
	assert ig2.matched('src/foo', false).is_ignore()
}

fn test_absolute_parent_anchored_descendant_keeps_root_base() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), 'a/src/f/b'))
	wfile(os.join_path(td.path(), '.ignore'), '/a/*/b')

	ig0 := IgnoreBuilder.new().build()
	ig1, has_err1, _ := ig0.add_parents(os.join_path(td.path(), 'a/src'))
	assert !has_err1
	ig2, has_err2, _ := ig1.add_child('a/src')
	assert !has_err2
	ig3, has_err3, _ := ig2.add_child('a/src/f')
	assert !has_err3

	assert ig2.matched('a/src/f', true).is_none()
	assert ig3.matched('a/src/f/b', true).is_none()
}

fn test_parents_iterator_yields_owned_matchers() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	mkdirp(os.join_path(td.path(), '.git'))
	mkdirp(os.join_path(td.path(), 'src'))
	wfile(os.join_path(td.path(), '.gitignore'), 'foo')

	ig0 := IgnoreBuilder.new().build()
	ig1, has_err1, _ := ig0.add_child(td.path())
	assert !has_err1
	ig2, has_err2, _ := ig1.add_child(os.join_path(td.path(), 'src'))
	assert !has_err2

	mut parents := ig2.parents()
	first := parents.next() or { panic('missing first parent') }
	second := parents.next() or { panic('missing second parent') }
	third := parents.next() or { panic('missing root parent') }
	if _ := parents.next() {
		panic('parents iterator should be exhausted')
	}

	if *first.path() != *ig2.path() {
		panic('first parent path should be self')
	}
	if *second.path() != *ig1.path() {
		panic('second parent path should be direct parent')
	}
	if *third.path() != *ig0.path() {
		panic('third parent path should be root')
	}
	if !first.matched('foo', false).is_ignore() {
		panic('first parent should retain child rules')
	}
	if !second.matched('foo', false).is_ignore() {
		panic('second parent should retain root rules')
	}
	if !third.matched('foo', false).is_none() {
		panic('root parent should not have loaded child rules')
	}
	mut owned_first := first
	mut owned_second := second
	mut owned_third := third
	owned_first.free_nodes()
	owned_second.free_nodes()
	owned_third.free_nodes()
}

fn test_parents_iterator_releases_unconsumed_matchers() {
	ig0 := IgnoreBuilder.new().build()
	ig1, has_err1, _ := ig0.add_child('one')
	assert !has_err1
	ig2, has_err2, _ := ig1.add_child('two')
	assert !has_err2
	root_refs := ig0.node.refs.load()
	first_refs := ig1.node.refs.load()
	mut parents := ig2.parents()
	assert ig0.node.refs.load() == root_refs + 1
	assert ig1.node.refs.load() == first_refs + 1
	mut first := parents.next() or { panic('missing first parent') }
	parents.drop()
	assert ig0.node.refs.load() == root_refs
	assert ig1.node.refs.load() == first_refs
	first.free_nodes()
}

fn test_git_info_exclude_in_linked_worktree() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	git_dir := os.join_path(td.path(), '.git')
	mkdirp(os.join_path(git_dir, 'info'))
	wfile(os.join_path(git_dir, 'info/exclude'), 'ignore_me')
	mkdirp(os.join_path(git_dir, 'worktrees/linked-worktree'))
	commondir_path := os.join_path(git_dir, 'worktrees/linked-worktree/commondir')
	mkdirp(os.join_path(td.path(), 'linked-worktree'))
	worktree_git_dir_abs := 'gitdir: ' + os.join_path(git_dir, 'worktrees/linked-worktree')
	wfile(os.join_path(td.path(), 'linked-worktree/.git'), worktree_git_dir_abs)

	// relative commondir
	wfile(commondir_path, '../..')
	ib := IgnoreBuilder.new().build()
	ignore1, has_err1, _ := ib.add_child(os.join_path(td.path(), 'linked-worktree'))
	assert !has_err1
	assert ignore1.matched('ignore_me', false).is_ignore()

	// absolute commondir
	wfile(commondir_path, git_dir)
	ignore2, has_err2, _ := ib.add_child(os.join_path(td.path(), 'linked-worktree'))
	assert !has_err2
	assert ignore2.matched('ignore_me', false).is_ignore()

	// missing commondir file
	os.rm(commondir_path) or { panic(err.msg()) }
	_, has_err3, _ := ib.add_child(os.join_path(td.path(), 'linked-worktree'))
	// We squash the error in this case, because it occurs in repositories
	// that are not linked worktrees but have submodules.
	assert !has_err3

	wfile(os.join_path(td.path(), 'linked-worktree/.git'), 'garbage')
	_, has_err4, _ := ib.add_child(os.join_path(td.path(), 'linked-worktree'))
	assert !has_err4

	wfile(os.join_path(td.path(), 'linked-worktree/.git'), 'gitdir: garbage')
	_, has_err5, _ := ib.add_child(os.join_path(td.path(), 'linked-worktree'))
	assert !has_err5
}
