module ignore

import os

fn gi_from_str(root string, s string) Gitignore {
	mut builder := GitignoreBuilder.new(root)
	add_has_err, add_err := builder.add_str(none_string(), s)
	assert !add_has_err, add_err.msg()
	gi, build_has_err, build_err := builder.build()
	assert !build_has_err, build_err.msg()
	return gi
}

fn assert_ignored(root string, gi_src string, path string, is_dir bool) {
	gi := gi_from_str(root, gi_src)
	m := gi.matched(path, is_dir)
	assert m.is_ignore()
}

fn assert_not_ignored(root string, gi_src string, path string, is_dir bool) {
	gi := gi_from_str(root, gi_src)
	m := gi.matched(path, is_dir)
	assert !m.is_ignore()
}

const root = '/home/foobar/rust/rg'

fn test_new_uses_the_source_path_parent() {
	gi, has_err, err := Gitignore.new('relative-ignore-file')
	assert !has_err, err.msg()
	assert *gi.path() == ''
	empty_path, empty_has_err, empty_err := Gitignore.new('')
	assert !empty_has_err, empty_err.msg()
	assert *empty_path.path() == '/'
}

fn test_create_gitignore_owns_glob_source_path() {
	dir := os.join_path(os.temp_dir(), 'ripgrep_v_gitignore_source_${os.getpid()}')
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	ignore_path := os.join_path(dir, '.ignore')
	os.write_file(ignore_path, 'hit\n')!
	gi, has_err, err := create_gitignore(dir, dir, ['.ignore'], false)
	assert !has_err, err.msg()
	matched := gi.matched(os.join_path(dir, 'hit'), false)
	glob_ref := matched.inner() or { panic('missing ignore match') }
	from := glob_ref.glob.from() or { panic('missing glob source') }
	assert from == ignore_path
}

fn test_ig1() {
	assert_ignored(root, 'months', 'months', false)
}

fn test_ig2() {
	assert_ignored(root, '*.lock', 'Cargo.lock', false)
}

fn test_ig3() {
	assert_ignored(root, '*.rs', 'src/main.rs', false)
}

fn test_ig4() {
	assert_ignored(root, 'src/*.rs', 'src/main.rs', false)
}

fn test_ig5() {
	assert_ignored(root, '/*.c', 'cat-file.c', false)
}

fn test_ig6() {
	assert_ignored(root, '/src/*.rs', 'src/main.rs', false)
}

fn test_ig7() {
	assert_ignored(root, '!src/main.rs\n*.rs', 'src/main.rs', false)
}

fn test_ig8() {
	assert_ignored(root, 'foo/', 'foo', true)
}

fn test_ig9() {
	assert_ignored(root, '**/foo', 'foo', false)
}

fn test_ig10() {
	assert_ignored(root, '**/foo', 'src/foo', false)
}

fn test_ig11() {
	assert_ignored(root, '**/foo/**', 'src/foo/bar', false)
}

fn test_ig12() {
	assert_ignored(root, '**/foo/**', 'wat/src/foo/bar/baz', false)
}

fn test_ig13() {
	assert_ignored(root, '**/foo/bar', 'foo/bar', false)
}

fn test_ig14() {
	assert_ignored(root, '**/foo/bar', 'src/foo/bar', false)
}

fn test_ig15() {
	assert_ignored(root, 'abc/**', 'abc/x', false)
}

fn test_ig16() {
	assert_ignored(root, 'abc/**', 'abc/x/y', false)
}

fn test_ig17() {
	assert_ignored(root, 'abc/**', 'abc/x/y/z', false)
}

fn test_ig18() {
	assert_ignored(root, 'a/**/b', 'a/b', false)
}

fn test_ig19() {
	assert_ignored(root, 'a/**/b', 'a/x/b', false)
}

fn test_ig20() {
	assert_ignored(root, 'a/**/b', 'a/x/y/b', false)
}

fn test_ig_brace_alternates() {
	gi := gi_from_str(root, '*.{js,json,py}')
	assert gi.len() == 1
	assert gi.num_ignores() == 1
	assert gi.matched('src/main.py', false).is_ignore()
	assert !gi.matched('src/main.rs', false).is_ignore()
	assert_ignored(root, '{.git,node_modules,plugged}/**', 'node_modules/pkg/index.js', false)
}

fn test_glob_accessors_preserve_source_and_compiled_pattern() {
	mut builder := GitignoreBuilder.new(root)
	has_err, err := builder.add_line('source/.gitignore', '*.rs')
	assert !has_err, err.msg()
	gi, build_has_err, build_err := builder.build()
	assert !build_has_err, build_err.msg()
	matched := gi.matched('src/main.rs', false)
	glob_ref := matched.inner() or { panic('missing ignore match') }
	from := glob_ref.glob.from() or { panic('missing glob source') }
	assert *from == 'source/.gitignore'
	assert *glob_ref.glob.original() == '*.rs'
	assert *glob_ref.glob.actual() == '**/*.rs'
}

fn test_builder_can_build_then_add_another_glob() {
	mut builder := GitignoreBuilder.new(root)
	has_err, err := builder.add_line(none_string(), '*.rs')
	assert !has_err, err.msg()
	first, first_has_err, first_err := builder.build()
	assert !first_has_err, first_err.msg()
	assert first.len() == 1
	has_err2, err2 := builder.add_line(none_string(), '*.c')
	assert !has_err2, err2.msg()
	second, second_has_err, second_err := builder.build()
	assert !second_has_err, second_err.msg()
	assert second.len() == 2
	assert second.matched('main.rs', false).is_ignore()
	assert second.matched('main.c', false).is_ignore()
}

fn test_strip_only_removes_complete_root_components() {
	component_boundary := gi_from_str('/foo/bar', '/ista/hit')
	assert !component_boundary.matched('/foo/barista/hit', false).is_ignore(), 'stripped a partial root component'
	file_name := gi_from_str('foo', '/bar')
	assert !file_name.matched('foobar', false).is_ignore(), 'stripped a prefix from a file name'
	file_system_root := gi_from_str('/', '/foo')
	assert file_system_root.matched('/foo', false).is_ignore(), 'did not strip the file system root'
}

fn test_add_line_reports_the_glob_error_kind() {
	mut builder := GitignoreBuilder.new(root)
	builder.allow_unclosed_class(false)
	has_err, err := builder.add_line(none_string(), '[abc')
	assert has_err
	assert err.path == '[abc'
	assert err.message == "unclosed character class; missing ']'"
}

fn test_ig21() {
	assert_ignored(root, '\\!xy', '!xy', false)
}

fn test_ig22() {
	assert_ignored(root, '\\#foo', '#foo', false)
}

fn test_ig23() {
	assert_ignored(root, 'foo', './foo', false)
}

fn test_ig24() {
	assert_ignored(root, 'target', 'grep/target', false)
}

fn test_ig25() {
	assert_ignored(root, 'Cargo.lock', './tabwriter-bin/Cargo.lock', false)
}

fn test_ig26() {
	assert_ignored(root, '/foo/bar/baz', './foo/bar/baz', false)
}

fn test_ig27() {
	assert_ignored(root, 'foo/', 'xyz/foo', true)
}

fn test_ig28() {
	assert_ignored('./src', '/llvm/', './src/llvm', true)
}

fn test_ig29() {
	assert_ignored(root, 'node_modules/ ', 'node_modules', true)
}

fn test_ig30() {
	assert_ignored(root, '**/', 'foo/bar', true)
}

fn test_ig31() {
	assert_ignored(root, 'path1/*', 'path1/foo', false)
}

fn test_ig32() {
	assert_ignored(root, '.a/b', '.a/b', false)
}

fn test_ig33() {
	assert_ignored('./', '.a/b', '.a/b', false)
}

fn test_ig34() {
	assert_ignored('.', '.a/b', '.a/b', false)
}

fn test_ig35() {
	assert_ignored('./.', '.a/b', '.a/b', false)
}

fn test_ig36() {
	assert_ignored('././', '.a/b', '.a/b', false)
}

fn test_ig37() {
	assert_ignored('././.', '.a/b', '.a/b', false)
}

fn test_ig38() {
	assert_ignored(root, '\\[', '[', false)
}

fn test_ig39() {
	assert_ignored(root, '\\?', '?', false)
}

fn test_ig40() {
	assert_ignored(root, '\\*', '*', false)
}

fn test_ig41() {
	assert_ignored(root, '\\a', 'a', false)
}

fn test_ig42() {
	assert_ignored(root, 's*.rs', 'sfoo.rs', false)
}

fn test_ig43() {
	assert_ignored(root, '**', 'foo.rs', false)
}

fn test_ig44() {
	assert_ignored(root, '**/**/*', 'a/foo.rs', false)
}

fn test_ignot1() {
	assert_not_ignored(root, 'amonths', 'months', false)
}

fn test_ignot2() {
	assert_not_ignored(root, 'monthsa', 'months', false)
}

fn test_ignot3() {
	assert_not_ignored(root, '/src/*.rs', 'src/grep/src/main.rs', false)
}

fn test_ignot4() {
	assert_not_ignored(root, '/*.c', 'mozilla-sha1/sha1.c', false)
}

fn test_ignot5() {
	assert_not_ignored(root, '/src/*.rs', 'src/grep/src/main.rs', false)
}

fn test_ignot6() {
	assert_not_ignored(root, '*.rs\n!src/main.rs', 'src/main.rs', false)
}

fn test_ignot7() {
	assert_not_ignored(root, 'foo/', 'foo', false)
}

fn test_ignot8() {
	assert_not_ignored(root, '**/foo/**', 'wat/src/afoo/bar/baz', false)
}

fn test_ignot9() {
	assert_not_ignored(root, '**/foo/**', 'wat/src/fooa/bar/baz', false)
}

fn test_ignot10() {
	assert_not_ignored(root, '**/foo/bar', 'foo/src/bar', false)
}

fn test_ignot11() {
	assert_not_ignored(root, '#foo', '#foo', false)
}

fn test_ignot12() {
	assert_not_ignored(root, '\n\n\n', 'foo', false)
}

fn test_ignot13() {
	assert_not_ignored(root, 'foo/**', 'foo', true)
}

fn test_ignot14() {
	assert_not_ignored('./third_party/protobuf', 'm4/ltoptions.m4',
		'./third_party/protobuf/csharp/src/packages/repositories.config', false)
}

fn test_ignot15() {
	assert_not_ignored(root, '!/bar', 'foo/bar', false)
}

fn test_ignot16() {
	assert_not_ignored(root, '*\n!**/', 'foo', true)
}

fn test_ignot17() {
	assert_not_ignored(root, 'src/*.rs', 'src/grep/src/main.rs', false)
}

fn test_ignot18() {
	assert_not_ignored(root, 'path1/*', 'path2/path1/foo', false)
}

fn test_ignot19() {
	assert_not_ignored(root, 's*.rs', 'src/foo.rs', false)
}

fn bytes(s string) []u8 {
	return s.bytes()
}

fn path_string(path ?string) string {
	return path or { '' }
}

fn test_parse_excludes_file1() {
	data := bytes('[core]\nexcludesFile = /foo/bar')
	got := parse_excludes_file(data) or { panic('expected path') }
	assert path_string(got) == '/foo/bar'
}

fn test_parse_excludes_file2() {
	data := bytes('[core]\nexcludesFile = ~/foo/bar')
	got := parse_excludes_file(data) or { panic('expected path') }
	assert path_string(got) == expand_tilde('~/foo/bar')
}

fn test_parse_excludes_file3() {
	data := bytes('[core]\nexcludeFile = /foo/bar')
	assert parse_excludes_file(data) == none
}

fn test_parse_excludes_file4() {
	data := bytes('[core]\nexcludesFile = "~/foo/bar"')
	got := parse_excludes_file(data) or { panic('expected path') }
	assert path_string(got) == expand_tilde('~/foo/bar')
}

fn test_parse_excludes_file5() {
	data := bytes('[core]\nexcludesFile = " "~/foo/bar " ""')
	assert parse_excludes_file(data) == none
}

fn test_parse_excludes_file_matches_ascii_case_and_optional_quotes() {
	data := bytes('[core]\n  ExClUdEsFiLe = "  ~/foo/bar')
	got := parse_excludes_file(data) or { panic('expected path') }
	assert path_string(got) == expand_tilde('~/foo/bar')
	data2 := bytes('[core]\nexcludesFile = ~/foo/bar"')
	got2 := parse_excludes_file(data2) or { panic('expected path') }
	assert path_string(got2) == expand_tilde('~/foo/bar')
}

// See: https://github.com/BurntSushi/ripgrep/issues/106
fn test_regression_106() {
	_ = gi_from_str('/', ' ')
}

fn test_case_insensitive() {
	mut builder := GitignoreBuilder.new(root)
	_, _ = builder.case_insensitive(true)
	add_has_err, add_err := builder.add_str(none_string(), '*.html')
	assert !add_has_err, add_err.msg()
	gi, build_has_err, build_err := builder.build()
	assert !build_has_err, build_err.msg()
	m1 := gi.matched('foo.html', false)
	m2 := gi.matched('foo.HTML', false)
	m3 := gi.matched('foo.htm', false)
	m4 := gi.matched('foo.HTM', false)
	assert m1.is_ignore()
	assert m2.is_ignore()
	assert !m3.is_ignore()
	assert !m4.is_ignore()
}

fn test_cs1() {
	assert_ignored(root, '*.html', 'foo.html', false)
}

fn test_cs2() {
	assert_not_ignored(root, '*.html', 'foo.HTML', false)
}

fn test_cs3() {
	assert_not_ignored(root, '*.html', 'foo.htm', false)
}

fn test_cs4() {
	assert_not_ignored(root, '*.html', 'foo.HTM', false)
}
