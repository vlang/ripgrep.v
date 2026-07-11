module integration

import os

// See: https://github.com/BurntSushi/ripgrep/issues/16
fn test_regression_r16() {
	dir, mut cmd := setup('regression_r16')
	dir.create_dir('.git')
	dir.create('.gitignore', 'ghi/')
	dir.create_dir('ghi')
	dir.create_dir('def/ghi')
	dir.create('ghi/toplevel.txt', 'xyz')
	dir.create('def/ghi/subdir.txt', 'xyz')

	cmd.arg('xyz')
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/25
fn test_regression_r25() {
	dir, mut cmd := setup('regression_r25')
	dir.create_dir('.git')
	dir.create('.gitignore', '/llvm/')
	dir.create_dir('src/llvm')
	dir.create('src/llvm/foo', 'test')

	cmd.arg('test')
	eqnice('src/llvm/foo:test\n', cmd.stdout())

	cmd.current_dir('src')
	eqnice('llvm/foo:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/30
fn test_regression_r30() {
	dir, mut cmd := setup('regression_r30')
	dir.create('.gitignore', 'vendor/**\n!vendor/manifest')
	dir.create_dir('vendor')
	dir.create('vendor/manifest', 'test')

	cmd.arg('test')
	eqnice('vendor/manifest:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/49
fn test_regression_r49() {
	dir, mut cmd := setup('regression_r49')
	dir.create('.gitignore', 'foo/bar')
	dir.create_dir('test/foo/bar')
	dir.create('test/foo/bar/baz', 'test')

	cmd.arg('xyz')
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/50
fn test_regression_r50() {
	dir, mut cmd := setup('regression_r50')
	dir.create('.gitignore', 'XXX/YYY/')
	dir.create_dir('abc/def/XXX/YYY')
	dir.create_dir('ghi/XXX/YYY')
	dir.create('abc/def/XXX/YYY/bar', 'test')
	dir.create('ghi/XXX/YYY/bar', 'test')

	cmd.arg('xyz')
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/64
fn test_regression_r64() {
	dir, mut cmd := setup('regression_r64')
	dir.create_dir('dir')
	dir.create_dir('foo')
	dir.create('dir/abc', '')
	dir.create('foo/abc', '')

	cmd.args(['--files', 'foo'])
	eqnice('foo/abc\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/65
fn test_regression_r65() {
	dir, mut cmd := setup('regression_r65')
	dir.create_dir('.git')
	dir.create('.gitignore', 'a/')
	dir.create_dir('a')
	dir.create('a/foo', 'xyz')
	dir.create('a/bar', 'xyz')

	cmd.arg('xyz')
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/67
fn test_regression_r67() {
	dir, mut cmd := setup('regression_r67')
	dir.create_dir('.git')
	dir.create('.gitignore', '/*\n!/dir')
	dir.create_dir('dir')
	dir.create_dir('foo')
	dir.create('foo/bar', 'test')
	dir.create('dir/bar', 'test')

	cmd.arg('test')
	eqnice('dir/bar:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/87
fn test_regression_r87() {
	dir, mut cmd := setup('regression_r87')
	dir.create_dir('.git')
	dir.create('.gitignore', 'foo\n**no-vcs**')
	dir.create('foo', 'test')

	cmd.arg('test')
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/90
fn test_regression_r90() {
	dir, mut cmd := setup('regression_r90')
	dir.create_dir('.git')
	dir.create('.gitignore', '!.foo')
	dir.create('.foo', 'test')

	cmd.arg('test')
	eqnice('.foo:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/93
fn test_regression_r93() {
	dir, mut cmd := setup('regression_r93')
	dir.create('foo', '192.168.1.1')

	cmd.arg(r'(\d{1,3}\.){3}\d{1,3}')
	eqnice('foo:192.168.1.1\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/99
fn test_regression_r99() {
	dir, mut cmd := setup('regression_r99')
	dir.create('foo1', 'test')
	dir.create('foo2', 'zzz')
	dir.create('bar', 'test')

	cmd.args(['-j1', '--heading', 'test'])
	eqnice(sort_lines('bar\ntest\n\nfoo1\ntest\n'), sort_lines(cmd.stdout()))
}

// See: https://github.com/BurntSushi/ripgrep/issues/105
fn test_regression_r105_part1() {
	dir, mut cmd := setup('regression_r105_part1')
	dir.create('foo', 'zztest')

	cmd.args(['--vimgrep', 'test'])
	eqnice('foo:1:3:zztest\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/105
fn test_regression_r105_part2() {
	dir, mut cmd := setup('regression_r105_part2')
	dir.create('foo', 'zztest')

	cmd.args(['--column', 'test'])
	eqnice('foo:1:3:zztest\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/127
fn test_regression_r127() {
	dir, mut cmd := setup('regression_r127')
	// Set up a directory hierarchy like this:
	//
	// .gitignore
	// foo/
	//   sherlock
	//   watson
	//
	// Where `.gitignore` contains `foo/sherlock`.
	//
	// ripgrep should ignore 'foo/sherlock' giving us results only from
	// 'foo/watson' but on Windows ripgrep will include both 'foo/sherlock' and
	// 'foo/watson' in the search results.
	dir.create_dir('.git')
	dir.create('.gitignore', 'foo/sherlock\n')
	dir.create_dir('foo')
	dir.create('foo/sherlock', sherlock)
	dir.create('foo/watson', sherlock)

	expected := 'foo/watson:For the Doctor Watsons of this world, as opposed to the Sherlock
foo/watson:be, to a very large extent, the result of luck. Sherlock Holmes
'
	cmd.arg('Sherlock')
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/128
fn test_regression_r128() {
	dir, mut cmd := setup('regression_r128')
	dir.create_bytes('foo', [u8(`0`), `1`, `2`, `3`, `4`, `5`, `6`, `7`, 0x0b, `\n`, 0x0b, `\n`,
		0x0b, `\n`, 0x0b, `\n`, `x`])

	cmd.args(['-n', 'x'])
	eqnice('foo:5:x\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/131
//
// TODO(burntsushi): Darwin doesn't like this test for some reason. Probably
// due to the weird file path.
fn test_regression_r131() {
	$if macos {
		return
	}
	dir, mut cmd := setup('regression_r131')
	dir.create_dir('.git')
	dir.create('.gitignore', 'TopÑapa')
	dir.create('TopÑapa', 'test')

	cmd.arg('test')
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/137
//
// TODO(burntsushi): Figure out how to make this test work on Windows. Right
// now it gives "access denied" errors when trying to create a file symlink.
// For now, disable test on Windows.
fn test_regression_r137() {
	$if windows {
		return
	}
	dir, mut cmd := setup('regression_r137')
	dir.create('sherlock', sherlock)
	dir.link_file('sherlock', 'sym1')
	dir.link_file('sherlock', 'sym2')

	expected := './sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
./sherlock:be, to a very large extent, the result of luck. Sherlock Holmes
sym1:For the Doctor Watsons of this world, as opposed to the Sherlock
sym1:be, to a very large extent, the result of luck. Sherlock Holmes
sym2:For the Doctor Watsons of this world, as opposed to the Sherlock
sym2:be, to a very large extent, the result of luck. Sherlock Holmes
'
	cmd.args(['-j1', 'Sherlock', './', 'sym1', 'sym2'])
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/156
fn test_regression_r156() {
	dir, mut cmd := setup('regression_r156')
	expected := '#parse(\'widgets/foo_bar_macros.vm\')
#parse ( \'widgets/mobile/foo_bar_macros.vm\' )
#parse ("widgets/foobarhiddenformfields.vm")
#parse ( "widgets/foo_bar_legal.vm" )
#include( \'widgets/foo_bar_tips.vm\' )
#include(\'widgets/mobile/foo_bar_macros.vm\')
#include ("widgets/mobile/foo_bar_resetpw.vm")
#parse(\'widgets/foo-bar-macros.vm\')
#parse ( \'widgets/mobile/foo-bar-macros.vm\' )
#parse ("widgets/foo-bar-hiddenformfields.vm")
#parse ( "widgets/foo-bar-legal.vm" )
#include( \'widgets/foo-bar-tips.vm\' )
#include(\'widgets/mobile/foo-bar-macros.vm\')
#include ("widgets/mobile/foo-bar-resetpw.vm")
'
	dir.create('testcase.txt', expected)

	cmd.arg('-N')
	cmd.arg(r'#(?:parse|include)\s*\(\s*(?:"|' + "'" + r')[./A-Za-z_-]+(?:"|' + "'" + r')')
	cmd.arg('testcase.txt')
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/184
fn test_regression_r184() {
	dir, mut cmd := setup('regression_r184')
	dir.create('.gitignore', '.*')
	dir.create_dir('foo/bar')
	dir.create('foo/bar/baz', 'test')

	cmd.arg('test')
	eqnice('foo/bar/baz:test\n', cmd.stdout())

	cmd.current_dir('./foo/bar')
	eqnice('baz:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/199
fn test_regression_r199() {
	dir, mut cmd := setup('regression_r199')
	dir.create('foo', 'tEsT')

	cmd.args(['--smart-case', r'\btest\b'])
	eqnice('foo:tEsT\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/206
fn test_regression_r206() {
	dir, mut cmd := setup('regression_r206')
	dir.create_dir('foo')
	dir.create('foo/bar.txt', 'test')

	cmd.args(['test', '-g', '*.txt'])
	eqnice('foo/bar.txt:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/210
fn test_regression_r210() {
	$if windows {
		return
	}
	$if macos {
		return
	}
	dir, mut cmd := setup('regression_r210')
	badutf8 := [u8(`f`), `o`, `o`, 0xff, `b`, `a`, `r`].bytestr()

	// APFS does not support creating files with invalid UTF-8 bytes.
	// https://github.com/BurntSushi/ripgrep/issues/559
	if dir.try_create_bytes(badutf8, 'test'.bytes()) {
		cmd.args(['-H', 'test', badutf8])
		expected := [u8(`f`), `o`, `o`, 0xff, `b`, `a`, `r`, `:`, `t`, `e`, `s`, `t`, `\n`]
		assert cmd.output().stdout_bytes == expected
	}
}

// See: https://github.com/BurntSushi/ripgrep/issues/228
fn test_regression_r228() {
	dir, mut cmd := setup('regression_r228')
	dir.create_dir('foo')

	cmd.args(['--ignore-file', 'foo', 'test'])
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/229
fn test_regression_r229() {
	dir, mut cmd := setup('regression_r229')
	dir.create('foo', 'economie')

	cmd.args(['-S', '[E]conomie'])
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/251
fn test_regression_r251() {
	dir, mut cmd := setup('regression_r251')
	dir.create('foo', 'привет\nПривет\nПрИвЕт')

	expected := 'foo:привет\nfoo:Привет\nfoo:ПрИвЕт\n'
	cmd.args(['-i', 'привет'])
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/256
fn test_regression_r256() {
	$if windows {
		return
	}
	dir, mut cmd := setup('regression_r256')
	dir.create_dir('bar')
	dir.create('bar/baz', 'test')
	dir.link_dir('bar', 'foo')

	cmd.args(['test', 'foo'])
	eqnice('foo/baz:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/256
fn test_regression_r256_j1() {
	$if windows {
		return
	}
	dir, mut cmd := setup('regression_r256_j1')
	dir.create_dir('bar')
	dir.create('bar/baz', 'test')
	dir.link_dir('bar', 'foo')

	cmd.args(['-j1', 'test', 'foo'])
	eqnice('foo/baz:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/270
fn test_regression_r270() {
	dir, mut cmd := setup('regression_r270')
	dir.create('foo', '-test')

	cmd.args(['-e', '-test'])
	eqnice('foo:-test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/279
fn test_regression_r279() {
	dir, mut cmd := setup('regression_r279')
	dir.create('foo', 'test')

	cmd.args(['-q', 'test'])
	eqnice('', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/391
fn test_regression_r391() {
	dir, mut cmd := setup('regression_r391')
	dir.create_dir('.git')
	dir.create('lock', '')
	dir.create('bar.py', '')
	dir.create('.git/packed-refs', '')
	dir.create('.git/description', '')

	cmd.args(['--no-ignore', '--hidden', '--follow', '--files', '--glob',
		'!{.git,node_modules,plugged}/**', '--glob',
		'*.{js,json,php,md,styl,scss,sass,pug,html,config,py,cpp,c,go,hs}'])
	eqnice('bar.py\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/405
fn test_regression_r405() {
	dir, mut cmd := setup('regression_r405')
	dir.create_dir('foo/bar')
	dir.create_dir('bar/foo')
	dir.create('foo/bar/file1.txt', 'test')
	dir.create('bar/foo/file2.txt', 'test')

	cmd.args(['-g', '!/foo/**', 'test'])
	eqnice('bar/foo/file2.txt:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/428
fn test_regression_r428_color_context_path() {
	$if windows {
		return
	}
	dir, mut cmd := setup('regression_r428_color_context_path')
	dir.create('sherlock', 'foo\nbar')
	cmd.args(['-A1', '-H', '--no-heading', '-N', '--colors=match:none', '--color=always',
		'--hyperlink-format=', 'foo'])

	colored_path := '\x1b\x5b\x30\x6d\x1b\x5b\x33\x35\x6dsherlock\x1b\x5b\x30\x6d'
	expected := '${colored_path}:foo\n${colored_path}-bar\n'
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/428
fn test_regression_r428_unrecognized_style() {
	dir, mut cmd := setup('regression_r428_unrecognized_style')
	dir.create('file.txt', 'Sherlock')

	cmd.args(['--colors=match:style:', 'Sherlock'])
	cmd.assert_err()

	output := cmd.raw_output()
	expected := "rg: error parsing flag --colors: unrecognized style attribute ''. Choose from: nobold, bold, nointense, intense, nounderline, underline, noitalic, italic.\n"
	eqnice(expected, output.stderr)
}

// See: https://github.com/BurntSushi/ripgrep/issues/451
fn test_regression_r451_only_matching_as_in_issue() {
	dir, mut cmd := setup('regression_r451_only_matching_as_in_issue')
	dir.create('digits.txt', '1 2 3\n')
	cmd.args(['--only-matching', r'[0-9]+', 'digits.txt'])

	expected := '1
2
3
'
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/451
fn test_regression_r451_only_matching() {
	dir, mut cmd := setup('regression_r451_only_matching')
	dir.create('digits.txt', '1 2 3\n123\n')
	cmd.args(['--only-matching', '--column', r'[0-9]', 'digits.txt'])

	expected := '1:1:1
1:3:2
1:5:3
2:1:1
2:2:2
2:3:3
'
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/483
fn test_regression_r483_matching_no_stdout() {
	dir, mut cmd := setup('regression_r483_matching_no_stdout')
	dir.create('file.py', '')
	cmd.args(['--quiet', '--files', '--glob', '*.py'])
	eqnice('', cmd.stdout())

	mut parallel_cmd := dir.command()
	parallel_cmd.args(['-j2', '--quiet', '--files', '--glob', '*.py'])
	eqnice('', parallel_cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/483
fn test_regression_r483_non_matching_exit_code() {
	dir, mut cmd := setup('regression_r483_non_matching_exit_code')
	dir.create('file.rs', '')
	cmd.args(['--quiet', '--files', '--glob', '*.py'])
	cmd.assert_err()

	mut parallel_cmd := dir.command()
	parallel_cmd.args(['-j2', '--quiet', '--files', '--glob', '*.py'])
	parallel_cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/493
fn test_regression_r493() {
	dir, mut cmd := setup('regression_r493')
	dir.create('input.txt', "peshwaship 're seminomata")

	cmd.args(['-o', r"\b 're \b", 'input.txt'])
	eqnice(" 're \n", cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/506
fn test_regression_r506_word_not_parenthesized() {
	dir, mut cmd := setup('regression_r506_word_not_parenthesized')
	dir.create('wb.txt', 'min minimum amin\nmax maximum amax')
	cmd.args(['-w', '-o', 'min|max', 'wb.txt'])
	eqnice('min\nmax\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/553
fn test_regression_r553_switch() {
	dir, mut cmd := setup('regression_r553_switch')
	dir.create('sherlock', sherlock)

	expected := 'sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:be, to a very large extent, the result of luck. Sherlock Holmes
'
	cmd.args(['-i', 'sherlock'])
	eqnice(expected, cmd.stdout())

	// Repeat the `i` flag to make sure everything still works.
	cmd.arg('-i')
	eqnice(expected, cmd.stdout())
}

fn test_regression_r553_flag() {
	dir, mut cmd := setup('regression_r553_flag')
	dir.create('sherlock', sherlock)

	expected1 := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
--
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.
'
	cmd.args(['-C', '1', r'world|attached', 'sherlock'])
	eqnice(expected1, cmd.stdout())

	expected2 := 'For the Doctor Watsons of this world, as opposed to the Sherlock
and exhibited clearly, with a label attached.
'
	cmd.args(['-C', '0'])
	eqnice(expected2, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/568
fn test_regression_r568_leading_hyphen_option_args() {
	dir, mut cmd := setup('regression_r568_leading_hyphen_option_args')
	dir.create('file', 'foo bar -baz\n')
	cmd.args(['-e-baz', '-e', '-baz', 'file'])
	eqnice('foo bar -baz\n', cmd.stdout())

	mut cmd2 := dir.command()
	cmd2.args(['-rni', 'bar', 'file'])
	eqnice('foo ni -baz\n', cmd2.stdout())

	mut cmd3 := dir.command()
	cmd3.args(['-r', '-n', '-i', 'bar', 'file'])
	eqnice('foo -n -baz\n', cmd3.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/599
//
// This test used to check that we emitted color escape sequences even for
// empty matches, but with the addition of the JSON output format, clients no
// longer need to rely on escape sequences to parse matches. Therefore, we no
// longer emit useless escape sequences.
fn test_regression_r599() {
	dir, mut cmd := setup('regression_r599')
	dir.create('input.txt', '\n\ntest\n')
	cmd.args(['--color', 'ansi', '--colors', 'path:none', '--colors', 'line:none', '--colors',
		'match:fg:red', '--colors', 'match:style:nobold', '--line-number', r'^$', 'input.txt'])

	expected := '\x1b[0m1\x1b[0m:\n\x1b[0m2\x1b[0m:\n'
	eqnice_repr(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/693
fn test_regression_r693_context_in_contextless_mode() {
	dir, mut cmd := setup('regression_r693_context_in_contextless_mode')
	dir.create('foo', 'xyz\n')
	dir.create('bar', 'xyz\n')

	cmd.args(['-C1', '-c', '--sort-files', 'xyz'])
	eqnice('bar:1\nfoo:1\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/807
fn test_regression_r807() {
	dir, mut cmd := setup('regression_r807')
	dir.create_dir('.git')
	dir.create('.gitignore', '.a/b')
	dir.create_dir('.a/b')
	dir.create_dir('.a/c')
	dir.create('.a/b/file', 'test')
	dir.create('.a/c/file', 'test')

	cmd.args(['--hidden', 'test'])
	eqnice('.a/c/file:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/pull/2711
//
// Note that this isn't a regression test. In particular, this didn't fail
// with ripgrep 14.1.1. I couldn't figure out how to turn what the OP gave me
// into a failing test.
fn test_regression_r2711() {
	dir, _ := setup('regression_r2711')
	dir.create_dir('a/b')
	dir.create('a/.ignore', '.foo')
	dir.create('a/b/.foo', '')

	mut cmd1 := dir.command()
	eqnice('a/.ignore\n', cmd1.args(['--hidden', '--files']).stdout())

	mut cmd2 := dir.command()
	eqnice('./a/.ignore\n', cmd2.args(['--hidden', '--files', './']).stdout())

	mut cmd3 := dir.command()
	eqnice('a/.ignore\n', cmd3.args(['--hidden', '--files', 'a']).stdout())

	mut cmd4 := dir.command()
	cmd4.args(['--hidden', '--files', 'a/b'])
	cmd4.assert_err()

	mut cmd5 := dir.command()
	eqnice('./a/.ignore\n', cmd5.args(['--hidden', '--files', './a']).stdout())

	mut cmd6 := dir.command()
	cmd6.current_dir('a')
	eqnice('.ignore\n', cmd6.args(['--hidden', '--files']).stdout())

	mut cmd7 := dir.command()
	cmd7.current_dir('a/b')
	cmd7.args(['--hidden', '--files'])
	cmd7.assert_err()

	mut cmd8 := dir.command()
	cmd8.current_dir('./a')
	eqnice('.ignore\n', cmd8.args(['--hidden', '--files']).stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/829
fn test_regression_r829_original() {
	dir, _ := setup('regression_r829_original')
	dir.create_dir('a/b')
	dir.create('.ignore', '/a/b')
	dir.create('a/b/test.txt', 'Sample text')

	mut cmd1 := dir.command()
	cmd1.args(['Sample'])
	cmd1.assert_err()

	mut cmd2 := dir.command()
	cmd2.args(['Sample', 'a'])
	cmd2.assert_err()

	mut cmd3 := dir.command()
	cmd3.current_dir('a')
	cmd3.args(['Sample'])
	cmd3.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/2731
fn test_regression_r829_2731() {
	dir, _ := setup('regression_r829_2731')
	dir.create_dir('some_dir/build')
	dir.create('some_dir/build/foo', 'string')
	dir.create('.ignore', 'build/\n!/some_dir/build/')

	mut cmd1 := dir.command()
	eqnice('some_dir/build/foo\n', cmd1.args(['-l', 'string']).stdout())

	mut cmd2 := dir.command()
	eqnice('some_dir/build/foo\n', cmd2.args(['-l', 'string', 'some_dir']).stdout())

	mut cmd3 := dir.command()
	eqnice('./some_dir/build/foo\n', cmd3.args(['-l', 'string', './some_dir']).stdout())

	mut cmd4 := dir.command()
	eqnice('some_dir/build/foo\n', cmd4.args(['-l', 'string', 'some_dir/build']).stdout())

	mut cmd5 := dir.command()
	eqnice('./some_dir/build/foo\n', cmd5.args(['-l', 'string', './some_dir/build']).stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/2747
fn test_regression_r829_2747() {
	dir, _ := setup('regression_r829_2747')
	dir.create_dir('a/c/b')
	dir.create_dir('a/src/f/b')
	dir.create('a/c/b/foo', '')
	dir.create('a/src/f/b/foo', '')
	dir.create('.ignore', '/a/*/b')

	mut cmd1 := dir.command()
	eqnice('a/src/f/b/foo\n', cmd1.arg('--files').stdout())

	mut cmd2 := dir.command()
	eqnice('a/src/f/b/foo\n', cmd2.args(['--files', 'a/src']).stdout())

	mut cmd3 := dir.command()
	cmd3.current_dir('a/src')
	eqnice('f/b/foo\n', cmd3.arg('--files').stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/2778
fn test_regression_r829_2778() {
	dir, _ := setup('regression_r829_2778')
	dir.create_dir('parent/subdir')
	dir.create('.ignore', '/parent/*.txt')
	dir.create('parent/ignore-me.txt', '')
	dir.create('parent/subdir/dont-ignore-me.txt', '')

	mut cmd1 := dir.command()
	eqnice('parent/subdir/dont-ignore-me.txt\n', cmd1.arg('--files').stdout())

	mut cmd2 := dir.command()
	cmd2.current_dir('parent')
	eqnice('subdir/dont-ignore-me.txt\n', cmd2.arg('--files').stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/2836
fn test_regression_r829_2836() {
	dir, _ := setup('regression_r829_2836')
	dir.create_dir('testdir/sub/sub2')
	dir.create('.ignore', '/testdir/sub/sub2/\n')
	dir.create('testdir/sub/sub2/foo', '')

	mut cmd1 := dir.command()
	cmd1.arg('--files')
	cmd1.assert_err()

	mut cmd2 := dir.command()
	cmd2.current_dir('testdir')
	cmd2.arg('--files')
	cmd2.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/pull/2933
fn test_regression_r829_2933() {
	dir, mut cmd := setup('regression_r829_2933')
	dir.create_dir('testdir/sub/sub2')
	dir.create('.ignore', '/testdir/sub/sub2/')
	dir.create('testdir/sub/sub2/testfile', 'needle')

	cmd.current_dir('testdir')
	cmd.args(['--files-with-matches', 'needle'])
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/900
fn test_regression_r900() {
	dir, mut cmd := setup('regression_r900')
	dir.create('sherlock', sherlock)
	dir.create('pat', '')

	cmd.arg('-fpat').arg('sherlock')
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/1064
fn test_regression_r1064() {
	dir, mut cmd := setup('regression_r1064')
	dir.create('input', 'abc')
	eqnice('input:abc\n', cmd.arg(r'a(.*c)').stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1174
fn test_regression_r1098() {
	dir, mut cmd := setup('regression_r1098')
	dir.create_dir('.git')
	dir.create('.gitignore', 'a**b')
	dir.create('afoob', 'test')
	cmd.arg('test')
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/1130
fn test_regression_r1130() {
	dir, mut cmd := setup('regression_r1130')
	dir.create('foo', 'test')
	eqnice('foo\n', cmd.args(['--files-with-matches', 'test', 'foo']).stdout())

	mut cmd2 := dir.command()
	eqnice('foo\n', cmd2.args(['--files-without-match', 'nada', 'foo']).stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1159
fn test_regression_r1159_invalid_flag() {
	_, mut cmd := setup('regression_r1159_invalid_flag')
	cmd.arg('--wat')
	cmd.assert_exit_code(2)
}

// See: https://github.com/BurntSushi/ripgrep/issues/1159
fn test_regression_r1159_exit_status() {
	dir, _ := setup('regression_r1159_exit_status')
	dir.create('foo', 'test')

	mut cmd1 := dir.command()
	cmd1.arg('test')
	cmd1.assert_exit_code(0)

	mut cmd2 := dir.command()
	cmd2.args(['-q', 'test'])
	cmd2.assert_exit_code(0)

	mut cmd3 := dir.command()
	cmd3.args(['test', 'no-file'])
	cmd3.assert_exit_code(2)

	mut cmd4 := dir.command()
	cmd4.args(['-q', 'test', 'foo', 'no-file'])
	cmd4.assert_exit_code(0)

	mut cmd5 := dir.command()
	cmd5.arg('nada')
	cmd5.assert_exit_code(1)

	mut cmd6 := dir.command()
	cmd6.args(['-q', 'nada'])
	cmd6.assert_exit_code(1)

	mut cmd7 := dir.command()
	cmd7.args(['nada', 'no-file'])
	cmd7.assert_exit_code(2)

	mut cmd8 := dir.command()
	cmd8.args(['-q', 'nada', 'foo', 'no-file'])
	cmd8.assert_exit_code(2)
}

// See: https://github.com/BurntSushi/ripgrep/issues/1163
fn test_regression_r1163() {
	dir, mut cmd := setup('regression_r1163')
	dir.create('bom.txt', '\ufefftest123\ntest123')
	eqnice('bom.txt:test123\nbom.txt:test123\n', cmd.arg('^test123').stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1164
fn test_regression_r1164() {
	dir, mut cmd := setup('regression_r1164')
	dir.create_dir('.git')
	dir.create('.gitignore', 'myfile')
	dir.create('MYFILE', 'test')

	cmd.args(['--ignore-file-case-insensitive', 'test'])
	cmd.assert_err()
	eqnice('MYFILE:test\n', cmd.arg('--no-ignore-file-case-insensitive').stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1173
fn test_regression_r1173() {
	dir, mut cmd := setup('regression_r1173')
	dir.create_dir('.git')
	dir.create('.gitignore', '**')
	dir.create('foo', 'test')
	cmd.arg('test')
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/1174
fn test_regression_r1174() {
	dir, mut cmd := setup('regression_r1174')
	dir.create_dir('.git')
	dir.create('.gitignore', '**/**/*')
	dir.create_dir('a')
	dir.create('a/foo', 'test')
	cmd.arg('test')
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/1176
fn test_regression_r1176_literal_file() {
	dir, mut cmd := setup('regression_r1176_literal_file')
	dir.create('patterns', 'foo(bar\n')
	dir.create('test', 'foo(bar')

	eqnice('foo(bar\n', cmd.args(['-F', '-f', 'patterns', 'test']).stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1176
fn test_regression_r1176_line_regex() {
	dir, mut cmd := setup('regression_r1176_line_regex')
	dir.create('patterns', 'foo\n')
	dir.create('test', 'foobar\nfoo\nbarfoo\n')

	eqnice('foo\n', cmd.args(['-x', '-f', 'patterns', 'test']).stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1203
fn test_regression_r1203_reverse_suffix_literal() {
	dir, _ := setup('regression_r1203_reverse_suffix_literal')
	dir.create('test', '153.230000\n')

	mut cmd1 := dir.command()
	eqnice('153.230000\n', cmd1.args([r'\d\d\d00', 'test']).stdout())

	mut cmd2 := dir.command()
	eqnice('153.230000\n', cmd2.args([r'\d\d\d000', 'test']).stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1223
fn test_regression_r1223_no_dir_check_for_default_path() {
	dir, mut cmd := setup('regression_r1223_no_dir_check_for_default_path')
	dir.create_dir('-')
	dir.create('a.json', '{}')
	dir.create('a.txt', 'some text')

	eqnice('a.json\na.txt\n', sort_lines(cmd.arg('a').pipe('a.json\na.txt'.bytes())))
}

// See: https://github.com/BurntSushi/ripgrep/issues/1259
fn test_regression_r1259_drop_last_byte_nonl() {
	dir, mut cmd := setup('regression_r1259_drop_last_byte_nonl')
	dir.create('patterns-nonl', '[foo]')
	dir.create('patterns-nl', '[foo]\n')
	dir.create('test', 'fz')

	eqnice('fz\n', cmd.args(['-f', 'patterns-nonl', 'test']).stdout())
	mut cmd2 := dir.command()
	eqnice('fz\n', cmd2.args(['-f', 'patterns-nl', 'test']).stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1311
fn test_regression_r1311_multi_line_term_replace() {
	dir, mut cmd := setup('regression_r1311_multi_line_term_replace')
	dir.create('input', 'hello\nworld\n')
	eqnice('1:hello?world?\n', cmd.args(['-U', '-r?', '-n', '\n', 'input']).stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1319
fn test_regression_r1319() {
	dir, mut cmd := setup('regression_r1319')
	dir.create('input', 'CCAGCTACTCGGGAGGCTGAGGCTGGAGGATCGCTTGAGTCCAGGAGTTC')
	eqnice('input:CCAGCTACTCGGGAGGCTGAGGCTGGAGGATCGCTTGAGTCCAGGAGTTC\n',
		cmd.arg('TTGAGTCCAGGAG[ATCG]{2}C').stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1332
fn test_regression_r1334_invert_empty_patterns() {
	dir, _ := setup('regression_r1334_invert_empty_patterns')
	dir.create('zero-patterns', '')
	dir.create('one-pattern', '\n')
	dir.create('haystack', 'one\ntwo\nthree\n')

	mut cmd1 := dir.command()
	cmd1.args(['-f', 'zero-patterns', 'haystack'])
	cmd1.assert_err()

	mut cmd2 := dir.command()
	eqnice('one\ntwo\nthree\n', cmd2.args(['-f', 'one-pattern', 'haystack']).stdout())

	mut cmd3 := dir.command()
	eqnice('one\ntwo\nthree\n', cmd3.args(['-vf', 'zero-patterns', 'haystack']).stdout())

	mut cmd4 := dir.command()
	cmd4.args(['-vf', 'one-pattern', 'haystack'])
	cmd4.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/1334
fn test_regression_r1334_crazy_literals() {
	dir, mut cmd := setup('regression_r1334_crazy_literals')
	dir.create('patterns', '1.208.0.0/12\n'.repeat(40))
	dir.create('corpus', '1.208.0.0/12\n')
	eqnice('1.208.0.0/12\n', cmd.args(['-Ff', 'patterns', 'corpus']).stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1380
fn test_regression_r1380() {
	dir, mut cmd := setup('regression_r1380')
	dir.create('foo', 'a\nb\nc\nd\ne\nd\ne\nd\ne\nd\ne\n')

	eqnice('d\ne\nd\n', cmd.args(['-A2', '-m1', 'd', 'foo']).stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1389
fn test_regression_r1389_bad_symlinks_no_biscuit() {
	dir, mut cmd := setup('regression_r1389_bad_symlinks_no_biscuit')
	dir.create_dir('mydir')
	dir.create('mydir/file.txt', 'test')
	dir.link_dir('mydir', 'mylink')

	stdout := cmd.args(['test', '--no-ignore', '--sort', 'path', 'mylink']).stdout()
	eqnice('mylink/file.txt:test\n', stdout)
}

// See: https://github.com/BurntSushi/ripgrep/issues/1401
fn test_regression_r1401_look_ahead_only_matching_1() {
	dir, mut cmd := setup('regression_r1401_look_ahead_only_matching_1')
	if !dir.is_pcre2() {
		return
	}
	dir.create('ip.txt', 'foo 42\nxoyz\ncat\tdog\n')
	cmd.args(['-No', r'.*o(?!.*\s)', 'ip.txt'])
	eqnice('xo\ncat\tdo\n', cmd.stdout())

	mut cmd2 := dir.command()
	cmd2.args(['-No', r'.*o(?!.*[ \t])', 'ip.txt'])
	eqnice('xo\ncat\tdo\n', cmd2.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1401
fn test_regression_r1401_look_ahead_only_matching_2() {
	dir, mut cmd := setup('regression_r1401_look_ahead_only_matching_2')
	if !dir.is_pcre2() {
		return
	}
	dir.create('ip.txt', 'foo 42\nxoyz\ncat\tdog\nfoo')
	cmd.args(['-No', r'.*o(?!.*\s)', 'ip.txt'])
	eqnice('xo\ncat\tdo\nfoo\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1412
fn test_regression_r1412_look_behind_no_replacement() {
	dir, mut cmd := setup('regression_r1412_look_behind_no_replacement')
	if !dir.is_pcre2() {
		return
	}

	dir.create('test', 'foo\nbar\n')
	cmd.args(['-nU', '-rquux', r'(?<=foo\n)bar', 'test'])
	eqnice('2:quux\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/pull/1446
fn test_regression_r1446_respect_excludes_in_worktree() {
	dir, mut cmd := setup('regression_r1446_respect_excludes_in_worktree')
	dir.create_dir('repo/.git/info')
	dir.create('repo/.git/info/exclude', 'ignored')
	dir.create_dir('repo/.git/worktrees/repotree')
	dir.create('repo/.git/worktrees/repotree/commondir', '../..')

	dir.create_dir('repotree')
	dir.create('repotree/.git', 'gitdir: repo/.git/worktrees/repotree')
	dir.create('repotree/ignored', '')
	dir.create('repotree/not-ignored', '')

	cmd.args(['--sort', 'path', '--files', 'repotree'])
	eqnice('repotree/not-ignored\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1537
fn test_regression_r1537() {
	dir, mut cmd := setup('regression_r1537')
	dir.create('foo', 'abc;de,fg')

	expected := 'foo:abc;de,fg\n'
	eqnice(expected, cmd.arg(';(.*,){1}').stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1559
fn test_regression_r1559() {
	dir, mut cmd := setup('regression_r1559')
	dir.create('foo', 'type A struct {
	TaskID int `json:"taskID"`
}

type B struct {
	ObjectID string `json:"objectID"`
	TaskID   int    `json:"taskID"`
}
')

	expected := 'foo:	TaskID int `json:"taskID"`
foo:	TaskID   int    `json:"taskID"`
'
	eqnice(expected, cmd.arg('TaskID +int').stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1573
//
// Tests that if look-ahead is used, then --count-matches is correct.
fn test_regression_r1573() {
	dir, mut cmd := setup('regression_r1573')
	if !dir.is_pcre2() {
		return
	}

	dir.create_bytes('foo', [u8(0xff), 0xfe, 0x00, 0x62])
	dir.create('foo', 'def A;
def B;
use A;
use B;
')

	cmd.args(['--pcre2', '--multiline', '--count', r'(?s)def (\w+);(?=.*use \w+)', 'foo'])
	eqnice('2\n', cmd.stdout())

	mut cmd2 := dir.command()
	cmd2.args(['--pcre2', '--multiline', '--count-matches', r'(?s)def (\w+);(?=.*use \w+)', 'foo'])
	eqnice('2\n', cmd2.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1638
//
// Tests if UTF-8 BOM is sniffed, then the column index is correct.
fn test_regression_r1638() {
	dir, mut cmd := setup('regression_r1638')
	dir.create_bytes('foo', [u8(0xef), 0xbb, 0xbf, 0x78])

	eqnice('foo:1:1:x\n', cmd.args(['--column', 'x']).stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1739
fn test_regression_r1739_replacement_lineterm_match() {
	dir, mut cmd := setup('regression_r1739_replacement_lineterm_match')
	dir.create('test', 'a\n')
	cmd.args([r'-r${0}f', r'.*', 'test'])
	eqnice('af\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1757
fn test_regression_f1757() {
	dir, _ := setup('regression_f1757')
	dir.create_dir('rust/target')
	dir.create('.ignore', 'rust/target')
	dir.create('rust/source.rs', 'needle')
	dir.create('rust/target/rustdoc-output.html', 'needle')

	args := ['--files-with-matches', 'needle', 'rust']
	mut cmd1 := dir.command()
	eqnice('rust/source.rs\n', cmd1.args(args).stdout())
	mut cmd2 := dir.command()
	eqnice('./rust/source.rs\n', cmd2.args(['--files-with-matches', 'needle', './rust']).stdout())

	dir.create_dir('rust1/target/onemore')
	dir.create('.ignore', 'rust1/target/onemore')
	dir.create('rust1/source.rs', 'needle')
	dir.create('rust1/target/onemore/rustdoc-output.html', 'needle')
	mut cmd3 := dir.command()
	eqnice('rust1/source.rs\n', cmd3.args(['--files-with-matches', 'needle', 'rust1']).stdout())
	mut cmd4 := dir.command()
	eqnice('./rust1/source.rs\n', cmd4.args(['--files-with-matches', 'needle', './rust1']).stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1765
fn test_regression_r1765() {
	dir, mut cmd := setup('regression_r1765')
	dir.create('test', '\n')
	// We need to add --color=always here to force the failure, since the bad
	// code path is only triggered when colors are enabled.
	cmd.args([r'x?', '--crlf', '--color', 'always'])

	assert cmd.stdout().len > 0
}

// See: https://github.com/BurntSushi/ripgrep/issues/1838
fn test_regression_r1838_nul_error_with_binary_detection() {
	dir, _ := setup('regression_r1838_nul_error_with_binary_detection')
	if dir.is_pcre2() {
		return
	}
	dir.create('test', 'foo\n')

	mut cmd1 := dir.command()
	cmd1.args([r'foo\x00?'])
	cmd1.assert_err()
	mut cmd2 := dir.command()
	eqnice('test:foo\n', cmd2.args(['-a', r'foo\x00?']).stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1866
fn test_regression_r1866() {
	dir, mut cmd := setup('regression_r1866')
	dir.create('test', 'foobar\nfoobar\nfoo quux')
	cmd.args(['--multiline', '--vimgrep', r'foobar\nfoobar\nfoo|quux', 'test'])

	// vimgrep only wants the first line of each match, even when a match
	// spans multiple lines.
	//
	// See: https://github.com/BurntSushi/ripgrep/issues/1866
	expected := 'test:1:1:foobar
test:3:5:foo quux
'
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1868
fn test_regression_r1868_context_passthru_override() {
	dir, _ := setup('regression_r1868_context_passthru_override')
	dir.create('test', 'foo\nbar\nbaz\nquux\n')

	mut cmd1 := dir.command()
	eqnice('foo\nbar\nbaz\n', cmd1.args(['-C1', 'bar', 'test']).stdout())
	mut cmd2 := dir.command()
	eqnice('foo\nbar\nbaz\nquux\n', cmd2.args(['--passthru', 'bar', 'test']).stdout())

	mut cmd3 := dir.command()
	eqnice('foo\nbar\nbaz\n', cmd3.args(['--passthru', '-C1', 'bar', 'test']).stdout())
	mut cmd4 := dir.command()
	eqnice('foo\nbar\nbaz\nquux\n', cmd4.args(['-C1', '--passthru', 'bar', 'test']).stdout())

	mut cmd5 := dir.command()
	eqnice('foo\nbar\n', cmd5.args(['--passthru', '-B1', 'bar', 'test']).stdout())
	mut cmd6 := dir.command()
	eqnice('foo\nbar\nbaz\nquux\n', cmd6.args(['-B1', '--passthru', 'bar', 'test']).stdout())

	mut cmd7 := dir.command()
	eqnice('bar\nbaz\n', cmd7.args(['--passthru', '-A1', 'bar', 'test']).stdout())
	mut cmd8 := dir.command()
	eqnice('foo\nbar\nbaz\nquux\n', cmd8.args(['-A1', '--passthru', 'bar', 'test']).stdout())
}

fn test_regression_r1878() {
	dir, _ := setup('regression_r1878')
	dir.create('test', 'a\nbaz\nabc\n')

	mut cmd1 := dir.command()
	eqnice('baz\n', cmd1.args(['-U', '--no-mmap', r'^baz', 'test']).stdout())
	$if !macos {
		mut cmd2 := dir.command()
		eqnice('baz\n', cmd2.args(['-U', '--mmap', r'^baz', 'test']).stdout())
	}

	mut cmd3 := dir.command()
	cmd3.args(['-U', '--no-mmap', r'(?-m)^baz', 'test'])
	cmd3.assert_err()
	$if !macos {
		mut cmd4 := dir.command()
		cmd4.args(['-U', '--mmap', r'(?-m)^baz', 'test'])
		cmd4.assert_err()
	}

	mut cmd5 := dir.command()
	cmd5.args(['-U', '--no-mmap', r'\Abaz', 'test'])
	cmd5.assert_err()
	$if !macos {
		mut cmd6 := dir.command()
		cmd6.args(['-U', '--mmap', r'\Abaz', 'test'])
		cmd6.assert_err()
	}
}

// See: https://github.com/BurntSushi/ripgrep/issues/1891
fn test_regression_r1891() {
	dir, mut cmd := setup('regression_r1891')
	dir.create('test', '\n##\n')
	// N.B. We use -o here to force the issue to occur, which seems to only
	// happen when each match needs to be detected.
	eqnice('1:\n2:\n2:\n2:\n', cmd.args(['-won', '', 'test']).stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/2094
fn test_regression_r2094() {
	dir, mut cmd := setup('regression_r2094')
	dir.create('haystack', 'a\nb\nc\na\nb\nc')
	cmd.args(['--no-line-number', '--no-filename', '--multiline', '--max-count=1', '--passthru',
		'--replace=B', 'b', 'haystack'])
	expected := 'a
B
c
a
b
c
'
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/2095
fn test_regression_r2095() {
	dir, mut cmd := setup('regression_r2095')
	dir.create('test', '#!/usr/bin/env bash

zero=one

a=one

if true; then
	a=(
		a
		b
		c
	)
	true
fi

a=two

b=one
});
')
	cmd.args(['--line-number', '--multiline', '--only-matching', '--replace', r'${value}',
		r'^(?P<indent>\s*)a=(?P<value>(?ms:[(].*?[)])|.*?)$', 'test'])
	expected := '4:one
8:(
9:		a
10:		b
11:		c
12:	)
15:two
'
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/2198
fn test_regression_r2198() {
	dir, mut cmd := setup('regression_r2198')
	dir.create('.ignore', 'a')
	dir.create('.rgignore', 'b')
	dir.create('a', '')
	dir.create('b', '')
	dir.create('c', '')

	cmd.args(['--files', '--sort', 'path'])
	eqnice('c\n', cmd.stdout())
	eqnice('a\nb\nc\n', cmd.arg('--no-ignore-dot').stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/2208
fn test_regression_r2208() {
	dir, mut cmd := setup('regression_r2208')
	dir.create('test', '# Compile requirements.txt files from all found or specified requirements.in files (compile).
# Use -h to include hashes, -u dep1,dep2... to upgrade specific dependencies, and -U to upgrade all.
pipc () {  # [-h] [-U|-u <pkgspec>[,<pkgspec>...]] [<reqs-in>...] [-- <pip-compile-arg>...]
    emulate -L zsh
    unset REPLY
    if [[ $1 == --help ]] { zpy $0; return }
    [[ $ZPY_PROCS ]] || return

    local gen_hashes upgrade upgrade_csv
    while [[ $1 == -[hUu] ]] {
        if [[ $1 == -h ]] { gen_hashes=--generate-hashes; shift   }
        if [[ $1 == -U ]] { upgrade=1;                    shift   }
        if [[ $1 == -u ]] { upgrade=1; upgrade_csv=$2;    shift 2 }
    }
}
')
	cmd.args(['-N', '-U', '-r', r'$usage',
		r'^(?P<predoc>\n?(# .*\n)*)(alias (?P<aname>pipc)="[^"]+"|(?P<fname>pipc) \(\) \{)(  #(?P<usage> .+))?',
		'test'])
	expected := ' [-h] [-U|-u <pkgspec>[,<pkgspec>...]] [<reqs-in>...] [-- <pip-compile-arg>...]\n'
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/2236
fn test_regression_r2236() {
	dir, mut cmd := setup('regression_r2236')
	dir.create('.ignore', r'foo\/')
	dir.create_dir('foo')
	dir.create('foo/bar', 'test\n')
	cmd.args(['test'])
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/2480
fn test_regression_r2480() {
	dir, mut cmd := setup('regression_r2480')
	dir.create('file', 'FooBar\n')

	cmd.args(['-e', '', 'file'])
	eqnice('FooBar\n', cmd.stdout())

	mut cmd2 := dir.command()
	cmd2.args(['-e', ')(', 'file'])
	eqnice('FooBar\n', cmd2.stdout())

	mut cmd3 := dir.command()
	cmd3.args(['--only-matching', '-e', 'Foo', '-e', 'Bar', 'file'])
	eqnice('Foo\nBar\n', cmd3.stdout())

	mut cmd4 := dir.command()
	cmd4.args(['-e', 'Fo(oB)a(r)', '--replace', r'${0}_${1}_${2}${3}', 'file'])
	eqnice('FooBar_oB_r\n', cmd4.stdout())

	mut cmd5 := dir.command()
	cmd5.args(['--only-matching', '-e', '(?i)foo', '-e', 'bar', 'file'])
	eqnice('Foo\n', cmd5.stdout())

	mut cmd6 := dir.command()
	cmd6.args(['--only-matching', '-e', '(?i)notfoo', '-e', 'bar', 'file'])
	cmd6.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/2574
fn test_regression_r2574() {
	dir, mut cmd := setup('regression_r2574')
	dir.create('haystack', 'some.domain.com\nsome.domain.com/x\n')
	got :=
		cmd.args(['--no-filename', '--no-unicode', '-w', '-o', r'(\w+\.)*domain\.(\w+)']).stdout()
	eqnice('some.domain.com\nsome.domain.com\n', got)
}

// See: https://github.com/BurntSushi/ripgrep/issues/2658
fn test_regression_r2658_null_data_line_regexp() {
	dir, mut cmd := setup('regression_r2658_null_data_line_regexp')
	dir.create('haystack', 'foo\0bar\0quux\0')
	got := cmd.args(['--null-data', '--line-regexp', r'bar']).stdout()
	eqnice('haystack:bar\0', got)
}

// See: https://github.com/BurntSushi/ripgrep/issues/2770
fn test_regression_r2770_gitignore_error() {
	dir, _ := setup('regression_r2770_gitignore_error')
	dir.create('.git', '')
	dir.create('.gitignore', '**/bar/*')
	dir.create_dir('foo/bar')
	dir.create('foo/bar/baz', 'quux')

	mut cmd1 := dir.command()
	cmd1.args(['-l', 'quux'])
	cmd1.assert_err()
	mut cmd2 := dir.command()
	cmd2.current_dir('foo')
	cmd2.args(['-l', 'quux'])
	cmd2.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/pull/2944
fn test_regression_r2944_incorrect_bytes_searched() {
	dir, mut cmd := setup('regression_r2944_incorrect_bytes_searched')
	dir.create('haystack', 'foo1\nfoo2\nfoo3\nfoo4\nfoo5\n')
	got := cmd.args(['--stats', '-m2', 'foo', '.']).stdout()
	assert got.contains('10 bytes searched\n')
}

// See: https://github.com/BurntSushi/ripgrep/issues/2990
fn test_regression_r2990_trip_over_trailing_dot() {
	$if windows {
		return
	}
	dir, _ := setup('regression_r2990_trip_over_trailing_dot')
	dir.create_dir('asdf')
	dir.create_dir('asdf.')
	dir.create('asdf/foo', '')
	dir.create('asdf./foo', '')

	mut cmd1 := dir.command()
	eqnice('asdf./foo\n', cmd1.args(['--files', '-g', '!asdf/']).stdout())

	mut cmd2 := dir.command()
	eqnice('asdf/foo\n', cmd2.args(['--files', '-g', '!asdf./']).stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/3067
fn test_regression_r3067_gitignore_error() {
	dir, mut cmd := setup('regression_r3067_gitignore_error')
	dir.create('.git', '')
	dir.create('.gitignore', 'foobar/debug')
	dir.create_dir('foobar/some/debug')
	dir.create_dir('foobar/debug')
	dir.create('foobar/some/debug/flag', 'baz')
	dir.create('foobar/debug/flag2', 'baz')

	got := cmd.arg('baz').stdout()
	eqnice('foobar/some/debug/flag:baz\n', got)
}

// See: https://github.com/BurntSushi/ripgrep/issues/3108
fn test_regression_r3108_files_without_match_quiet_exit() {
	dir, _ := setup('regression_r3108_files_without_match_quiet_exit')
	dir.create('yes-match', 'abc')
	dir.create('non-match', 'xyz')

	mut cmd1 := dir.command()
	cmd1.args(['-q', 'abc', 'non-match'])
	cmd1.assert_exit_code(1)
	mut cmd2 := dir.command()
	cmd2.args(['-q', 'abc', 'yes-match'])
	cmd2.assert_exit_code(0)
	mut cmd3 := dir.command()
	cmd3.args(['--files-with-matches', '-q', 'abc', 'non-match'])
	cmd3.assert_exit_code(1)
	mut cmd4 := dir.command()
	cmd4.args(['--files-with-matches', '-q', 'abc', 'yes-match'])
	cmd4.assert_exit_code(0)

	mut cmd5 := dir.command()
	cmd5.args(['--files-without-match', 'abc', 'non-match'])
	cmd5.assert_exit_code(0)
	mut cmd6 := dir.command()
	cmd6.args(['--files-without-match', 'abc', 'yes-match'])
	cmd6.assert_exit_code(1)

	mut cmd7 := dir.command()
	got := cmd7.args(['--files-without-match', 'abc', 'non-match']).stdout()
	eqnice('non-match\n', got)

	mut cmd8 := dir.command()
	cmd8.args(['--files-without-match', '-q', 'abc', 'non-match'])
	cmd8.assert_exit_code(0)
	mut cmd9 := dir.command()
	cmd9.args(['--files-without-match', '-q', 'abc', 'yes-match'])
	cmd9.assert_exit_code(1)

	mut cmd10 := dir.command()
	got2 := cmd10.args(['--files-without-match', '-q', 'abc', 'non-match']).stdout()
	eqnice('', got2)
}

// See: https://github.com/BurntSushi/ripgrep/issues/3127
fn test_regression_r3127_gitignore_allow_unclosed_class() {
	dir, mut cmd := setup('regression_r3127_gitignore_allow_unclosed_class')
	dir.create_dir('.git')
	dir.create('.gitignore', '[abc')
	dir.create('[abc', '')
	dir.create('test', '')

	got := cmd.args(['--files']).stdout()
	eqnice('test\n', got)
}

// See: https://github.com/BurntSushi/ripgrep/issues/3127
fn test_regression_r3127_glob_flag_not_allow_unclosed_class() {
	dir, mut cmd := setup('regression_r3127_glob_flag_not_allow_unclosed_class')
	dir.create('[abc', '')
	dir.create('test', '')

	cmd.args(['--files', '-g', '[abc'])
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/3139
fn test_regression_r3139_multiline_lookahead_files_with_matches() {
	dir, _ := setup('regression_r3139_multiline_lookahead_files_with_matches')
	if !dir.is_pcre2() {
		return
	}
	dir.create('test',
		'Start \n   \n\n   XXXXXXXXXXXXXXXXXXXXXXXXXX\n   YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY\n   \n      thing2 \n\n')

	mut cmd1 := dir.command()
	got := cmd1.args(['--multiline', '--pcre2', r'(?s)Start(?=.*thing2)', 'test']).stdout()
	eqnice('Start \n', got)

	mut cmd2 := dir.command()
	got2 := cmd2.args(['--multiline', '--pcre2', '--files-with-matches', r'(?s)Start(?=.*thing2)',
		'test']).stdout()
	eqnice('test\n', got2)
}

// See: https://github.com/BurntSushi/ripgrep/issues/3173
fn test_regression_r3173_hidden_whitelist_only_dot() {
	dir, _ := setup('regression_r3173_hidden_whitelist_only_dot')
	dir.create_dir('subdir')
	dir.create('subdir/.foo.txt', 'text')
	dir.create('.ignore', '!.foo.txt')

	mut cmd1 := dir.command()
	eqnice('subdir/.foo.txt\n', cmd1.args(['--files']).stdout())
	mut cmd2 := dir.command()
	eqnice('./subdir/.foo.txt\n', cmd2.args(['--files', '.']).stdout())
	mut cmd3 := dir.command()
	eqnice('./subdir/.foo.txt\n', cmd3.args(['--files', './']).stdout())

	mut cmd4 := dir.command()
	cmd4.current_dir('subdir')
	eqnice('.foo.txt\n', cmd4.args(['--files']).stdout())
	mut cmd5 := dir.command()
	cmd5.current_dir('subdir')
	eqnice('./.foo.txt\n', cmd5.args(['--files', '.']).stdout())
	mut cmd6 := dir.command()
	cmd6.current_dir('subdir')
	eqnice('./.foo.txt\n', cmd6.args(['--files', './']).stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/3179
fn test_regression_r3179_global_gitignore_cwd() {
	dir, mut cmd := setup('regression_r3179_global_gitignore_cwd')
	dir.create_dir('a/b/c')
	dir.create('a/b/c/haystack', '')
	dir.create('.test.gitignore', '/haystack')

	dir_path := os.real_path(dir.path())
	ignore_file_path := os.join_path(dir_path, '.test.gitignore')
	cmd.current_dir('a/b/c')
	cmd.args(['--files', '--ignore-file', ignore_file_path, dir_path])
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/3180
fn test_regression_r3180_look_around_panic() {
	dir, mut cmd := setup('regression_r3180_look_around_panic')
	dir.create('haystack', ' b b b b b b b b\nc\n')

	got :=
		cmd.arg(r'(^|[^a-z])((([a-z]+)?)\s)?b(\s([a-z]+)?)($|[^a-z])').arg('haystack').arg('-U').arg('-rx').stdout()
	eqnice('xbxbx\n', got)
}

fn test_parallel_search_discards_buffer_after_search_error() {
	$if windows {
		return
	}
	dir, mut cmd := setup('parallel_search_discards_buffer_after_search_error')
	dir.create('haystack1', 'ignored\n')
	dir.create('haystack2', 'ignored\n')
	dir.create('fail-pre', "#!/bin/sh\nprintf 'needle\\n'\nexit 1\n")
	pre_path := os.join_path(dir.path(), 'fail-pre')
	os.chmod(pre_path, 0o755) or { panic(err.msg()) }

	cmd.args(['-j2', '--pre', pre_path, 'needle', 'haystack1', 'haystack2'])
	output := cmd.raw_output()
	if output.code != 2 {
		panic(command_failure_message(cmd, output, 'expected a search error'))
	}
	eqnice('', output.stdout)
	if !output.stderr.contains('haystack1:') || !output.stderr.contains('haystack2:') {
		panic(command_failure_message(cmd, output, 'search error omitted the haystack path'))
	}
}

fn test_parallel_search_output_error_includes_path() {
	$if windows {
		return
	}
	dir, _ := setup('parallel_search_output_error_includes_path')
	dir.create('haystack1', 'needle\n')
	dir.create('haystack2', 'needle\n')
	stderr_path := os.join_path(dir.path(), 'stderr')
	command := 'cd ${sh_quote(dir.path())} && ${sh_quote(rg_binary())} --path-separator / -j2 needle haystack1 haystack2 1>&- 2> ${sh_quote(stderr_path)}'
	result := os.execute(command)
	stderr := os.read_file(stderr_path) or { panic(err.msg()) }
	os.rm(stderr_path) or {}
	if result.exit_code != 2 {
		panic('expected exit code 2, got ${result.exit_code}: ${stderr}')
	}
	if !stderr.contains('rg: haystack1:') || !stderr.contains('rg: haystack2:') {
		panic('parallel output error omitted the haystack path: ${stderr}')
	}
}
