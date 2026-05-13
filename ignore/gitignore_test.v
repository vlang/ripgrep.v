module ignore

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
