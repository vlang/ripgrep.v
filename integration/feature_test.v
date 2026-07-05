module integration

import time

// See: https://github.com/BurntSushi/ripgrep/issues/1
fn test_feature_f1_sjis() {
	dir, mut cmd := setup('feature_f1_sjis')
	dir.create_bytes('foo', [u8(0x84), 0x59, 0x84, 0x75, 0x84, 0x82, 0x84, 0x7c, 0x84,
		0x80, 0x84, 0x7b, 0x20, 0x84, 0x56, 0x84, 0x80, 0x84, 0x7c, 0x84, 0x7d,
		0x84, 0x83])
	cmd.args(['-Esjis', 'Шерлок Холмс'])
	eqnice('foo:Шерлок Холмс\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1
fn test_feature_f1_utf16_auto() {
	dir, mut cmd := setup('feature_f1_utf16_auto')
	dir.create_bytes('foo', [u8(0xff), 0xfe, 0x28, 0x04, 0x35, 0x04, 0x40, 0x04, 0x3b,
		0x04, 0x3e, 0x04, 0x3a, 0x04, 0x20, 0x00, 0x25, 0x04, 0x3e, 0x04, 0x3b, 0x04,
		0x3c, 0x04, 0x41, 0x04])
	cmd.arg('Шерлок Холмс')
	eqnice('foo:Шерлок Холмс\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1
fn test_feature_f1_utf16_explicit() {
	dir, mut cmd := setup('feature_f1_utf16_explicit')
	dir.create_bytes('foo', [u8(0xff), 0xfe, 0x28, 0x04, 0x35, 0x04, 0x40, 0x04, 0x3b,
		0x04, 0x3e, 0x04, 0x3a, 0x04, 0x20, 0x00, 0x25, 0x04, 0x3e, 0x04, 0x3b, 0x04,
		0x3c, 0x04, 0x41, 0x04])
	cmd.args(['-Eutf-16le', 'Шерлок Холмс'])
	eqnice('foo:Шерлок Холмс\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1
fn test_feature_f1_eucjp() {
	dir, mut cmd := setup('feature_f1_eucjp')
	dir.create_bytes('foo', [u8(0xa7), 0xba, 0xa7, 0xd6, 0xa7, 0xe2, 0xa7, 0xdd, 0xa7,
		0xe0, 0xa7, 0xdc, 0x20, 0xa7, 0xb7, 0xa7, 0xe0, 0xa7, 0xdd, 0xa7, 0xde, 0xa7,
		0xe3])
	cmd.args(['-Eeuc-jp', 'Шерлок Холмс'])
	eqnice('foo:Шерлок Холмс\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1
fn test_feature_f1_unknown_encoding() {
	_, mut cmd := setup('feature_f1_unknown_encoding')
	cmd.arg('-Efoobar')
	cmd.assert_non_empty_stderr()
}

// See: https://github.com/BurntSushi/ripgrep/issues/1
fn test_feature_f1_replacement_encoding() {
	_, mut cmd := setup('feature_f1_replacement_encoding')
	cmd.arg('-Ecsiso2022kr')
	cmd.assert_non_empty_stderr()
}

// See: https://github.com/BurntSushi/ripgrep/issues/7
fn test_feature_f7() {
	dir, mut cmd := setup('feature_f7')
	dir.create('sherlock', sherlock)
	dir.create('pat', 'Sherlock\nHolmes')
	cmd.args(['-fpat', 'sherlock'])
	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock\nHolmeses, success in the province of detective work must always\nbe, to a very large extent, the result of luck. Sherlock Holmes\n'
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/7
fn test_feature_f7_stdin() {
	dir, mut cmd := setup('feature_f7_stdin')
	dir.create('sherlock', sherlock)
	cmd.arg('-f-')
	expected := 'sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock\nsherlock:be, to a very large extent, the result of luck. Sherlock Holmes\n'
	eqnice(expected, cmd.pipe('Sherlock'.bytes()))
}

// See: https://github.com/BurntSushi/ripgrep/issues/20
fn test_feature_f20_no_filename() {
	dir, mut cmd := setup('feature_f20_no_filename')
	dir.create('sherlock', sherlock)
	cmd.args(['--no-filename', 'Sherlock'])
	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock\nbe, to a very large extent, the result of luck. Sherlock Holmes\n'
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/34
fn test_feature_f34_only_matching() {
	dir, mut cmd := setup('feature_f34_only_matching')
	dir.create('sherlock', sherlock)
	cmd.args(['-o', 'Sherlock'])
	eqnice('sherlock:Sherlock\nsherlock:Sherlock\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/34
fn test_feature_f34_only_matching_line_column() {
	dir, mut cmd := setup('feature_f34_only_matching_line_column')
	dir.create('sherlock', sherlock)
	cmd.args(['-o', '--column', '-n', 'Sherlock'])
	eqnice('sherlock:1:57:Sherlock\nsherlock:3:49:Sherlock\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/45
fn test_feature_f45_relative_cwd() {
	dir, mut cmd := setup('feature_f45_relative_cwd')
	dir.create('.not-an-ignore', 'foo\n/bar')
	dir.create_dir('bar')
	dir.create_dir('baz/bar')
	dir.create_dir('baz/baz/bar')
	dir.create('bar/test', 'test')
	dir.create('baz/bar/test', 'test')
	dir.create('baz/baz/bar/test', 'test')
	dir.create('baz/foo', 'test')
	dir.create('baz/test', 'test')
	dir.create('foo', 'test')
	dir.create('test', 'test')
	cmd.args(['-l', 'test'])
	expected1 := '\nbar/test\nbaz/bar/test\nbaz/baz/bar/test\nbaz/foo\nbaz/test\nfoo\ntest\n'
	eqnice(sort_lines(expected1), sort_lines(cmd.stdout()))

	cmd.args(['--ignore-file', '.not-an-ignore'])
	expected2 := '\nbaz/bar/test\nbaz/baz/bar/test\nbaz/test\ntest\n'
	eqnice(sort_lines(expected2), sort_lines(cmd.stdout()))

	mut cmd2 := dir.command()
	cmd2.args(['--ignore-file', '../.not-an-ignore', '-l', 'test'])
	cmd2.current_dir('baz')
	expected3 := '\nbaz/bar/test\ntest\n'
	eqnice(sort_lines(expected3), sort_lines(cmd2.stdout()))
}

// See: https://github.com/BurntSushi/ripgrep/issues/45
fn test_feature_f45_precedence_with_others() {
	dir, mut cmd := setup('feature_f45_precedence_with_others')
	dir.create('.not-an-ignore', '*.log')
	dir.create('.ignore', '!imp.log')
	dir.create('imp.log', 'test')
	dir.create('wat.log', 'test')
	cmd.args(['--ignore-file', '.not-an-ignore', 'test'])
	eqnice('imp.log:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/45
fn test_feature_f45_precedence_internal() {
	dir, mut cmd := setup('feature_f45_precedence_internal')
	dir.create('.not-an-ignore1', '*.log')
	dir.create('.not-an-ignore2', '!imp.log')
	dir.create('imp.log', 'test')
	dir.create('wat.log', 'test')
	cmd.args(['--ignore-file', '.not-an-ignore1', '--ignore-file', '.not-an-ignore2', 'test'])
	eqnice('imp.log:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/68
fn test_feature_f68_no_ignore_vcs() {
	dir, mut cmd := setup('feature_f68_no_ignore_vcs')
	dir.create_dir('.git')
	dir.create('.gitignore', 'foo')
	dir.create('.ignore', 'bar')
	dir.create('foo', 'test')
	dir.create('bar', 'test')
	cmd.args(['--no-ignore-vcs', 'test'])
	eqnice('foo:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/70
fn test_feature_f70_smart_case() {
	dir, mut cmd := setup('feature_f70_smart_case')
	dir.create('sherlock', sherlock)
	cmd.args(['-S', 'sherlock'])
	expected := 'sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock\nsherlock:be, to a very large extent, the result of luck. Sherlock Holmes\n'
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/89
fn test_feature_f89_files_with_matches() {
	dir, mut cmd := setup('feature_f89_files_with_matches')
	dir.create('sherlock', sherlock)
	cmd.args(['--null', '--files-with-matches', 'Sherlock'])
	eqnice('sherlock\x00', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/89
fn test_feature_f89_files_without_match() {
	dir, mut cmd := setup('feature_f89_files_without_match')
	dir.create('sherlock', sherlock)
	dir.create('file.py', 'foo')
	cmd.args(['--null', '--files-without-match', 'Sherlock'])
	eqnice('file.py\x00', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/89
fn test_feature_f89_count() {
	dir, mut cmd := setup('feature_f89_count')
	dir.create('sherlock', sherlock)
	cmd.args(['--null', '--count', 'Sherlock'])
	eqnice('sherlock\x002\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/89
fn test_feature_f89_files() {
	dir, mut cmd := setup('feature_f89_files')
	dir.create('sherlock', sherlock)
	cmd.args(['--null', '--files'])
	eqnice('sherlock\x00', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/89
fn test_feature_f89_match() {
	dir, mut cmd := setup('feature_f89_match')
	dir.create('sherlock', sherlock)
	cmd.args(['--null', '-C1', 'Sherlock'])
	expected := 'sherlock\x00For the Doctor Watsons of this world, as opposed to the Sherlock\nsherlock\x00Holmeses, success in the province of detective work must always\nsherlock\x00be, to a very large extent, the result of luck. Sherlock Holmes\nsherlock\x00can extract a clew from a wisp of straw or a flake of cigar ash;\n'
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/109
fn test_feature_f109_max_depth() {
	dir, mut cmd := setup('feature_f109_max_depth')
	dir.create_dir('one')
	dir.create('one/pass', 'far')
	dir.create_dir('one/too')
	dir.create('one/too/many', 'far')
	cmd.args(['--maxdepth', '2', 'far'])
	eqnice('one/pass:far\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/124
fn test_feature_f109_case_sensitive_part1() {
	dir, mut cmd := setup('feature_f109_case_sensitive_part1')
	dir.create('foo', 'tEsT')
	cmd.args(['--smart-case', '--case-sensitive', 'test'])
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/124
fn test_feature_f109_case_sensitive_part2() {
	dir, mut cmd := setup('feature_f109_case_sensitive_part2')
	dir.create('foo', 'tEsT')
	cmd.args(['--ignore-case', '--case-sensitive', 'test'])
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/129
fn test_feature_f129_matches() {
	dir, mut cmd := setup('feature_f129_matches')
	dir.create('foo', 'test\ntest abcdefghijklmnopqrstuvwxyz test')
	cmd.args(['-M26', 'test'])
	eqnice('foo:test\nfoo:[Omitted long matching line]\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/129
fn test_feature_f129_context() {
	dir, mut cmd := setup('feature_f129_context')
	dir.create('foo', 'test\nabcdefghijklmnopqrstuvwxyz')
	cmd.args(['-M20', '-C1', 'test'])
	eqnice('foo:test\nfoo-[Omitted long context line]\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/129
fn test_feature_f129_replace() {
	dir, mut cmd := setup('feature_f129_replace')
	dir.create('foo', 'test\ntest abcdefghijklmnopqrstuvwxyz test')
	cmd.args(['-M26', '-rfoo', 'test'])
	eqnice('foo:foo\nfoo:[Omitted long line with 2 matches]\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/159
fn test_feature_f159_max_count() {
	dir, mut cmd := setup('feature_f159_max_count')
	dir.create('foo', 'test\ntest')
	cmd.args(['-m1', 'test'])
	eqnice('foo:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/159
fn test_feature_f159_max_count_zero() {
	dir, mut cmd := setup('feature_f159_max_count_zero')
	dir.create('foo', 'test\ntest')
	cmd.args(['-m0', 'test'])
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/196
fn test_feature_f196_persistent_config() {
	dir, mut cmd := setup('feature_f196_persistent_config')
	dir.create('sherlock', sherlock)
	cmd.args(['sherlock', 'sherlock'])
	cmd.assert_err()
	dir.create('.ripgreprc', '--ignore-case')
	cmd.env('RIPGREP_CONFIG_PATH', '.ripgreprc')
	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock\nbe, to a very large extent, the result of luck. Sherlock Holmes\n'
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/243
fn test_feature_f243_column_line() {
	dir, mut cmd := setup('feature_f243_column_line')
	dir.create('foo', 'test')
	cmd.args(['--column', 'test'])
	eqnice('foo:1:1:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/263
fn test_feature_f263_sort_files() {
	dir, mut cmd := setup('feature_f263_sort_files')
	dir.create('foo', 'test')
	dir.create('abc', 'test')
	dir.create('zoo', 'test')
	dir.create('bar', 'test')
	cmd.args(['--sort-files', 'test'])
	eqnice('abc:test\nbar:test\nfoo:test\nzoo:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/263
fn test_feature_f263_sort_files_reverse() {
	dir, mut cmd := setup('feature_f263_sort_files_reverse')
	dir.create('foo', 'test')
	dir.create('abc', 'test')
	dir.create('zoo', 'test')
	dir.create('bar', 'test')
	cmd.args(['--sortr=path', 'test'])
	eqnice('zoo:test\nfoo:test\nbar:test\nabc:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/275
fn test_feature_f275_pathsep() {
	dir, mut cmd := setup('feature_f275_pathsep')
	dir.create_dir('foo')
	dir.create('foo/bar', 'test')
	cmd.args(['test', '--path-separator', 'Z'])
	eqnice('fooZbar:test\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/362
fn test_feature_f362_dfa_size_limit() {
	dir, mut cmd := setup('feature_f362_dfa_size_limit')
	dir.create('sherlock', sherlock)
	cmd.args(['--dfa-size-limit', '10', r'For\s', 'sherlock'])
	eqnice('For the Doctor Watsons of this world, as opposed to the Sherlock\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/362
fn test_feature_f362_exceeds_regex_size_limit() {
	dir, mut cmd := setup('feature_f362_exceeds_regex_size_limit')
	if dir.is_pcre2() {
		return
	}
	cmd.args(['--regex-size-limit', '10K', r'[0-9]\w+'])
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/362
fn test_feature_f362_u64_to_narrow_usize_overflow() {
	$if x64 {
		return
	}
	dir, mut cmd := setup('feature_f362_u64_to_narrow_usize_overflow')
	if dir.is_pcre2() {
		return
	}
	dir.create_size('foo', 1000000)

	// 2^35 * 2^20 is ok for u64, but not for usize
	cmd.args(['--dfa-size-limit', '34359738368M', '--files'])
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/411
fn test_feature_f411_single_threaded_search_stats() {
	dir, mut cmd := setup('feature_f411_single_threaded_search_stats')
	dir.create('sherlock', sherlock)
	cmd.args(['-j1', '--stats', 'Sherlock'])
	lines := cmd.stdout()
	assert lines.contains('Sherlock')
	assert lines.contains('2 matched lines')
	assert lines.contains('1 files contained matches')
	assert lines.contains('1 files searched')
	assert lines.contains('seconds')
}

fn test_feature_f411_parallel_search_stats() {
	dir, mut cmd := setup('feature_f411_parallel_search_stats')
	dir.create('sherlock_1', sherlock)
	dir.create('sherlock_2', sherlock)
	cmd.args(['-j2', '--stats', 'Sherlock'])
	lines := cmd.stdout()
	assert lines.contains('4 matched lines')
	assert lines.contains('2 files contained matches')
	assert lines.contains('2 files searched')
	assert lines.contains('seconds')
}

fn test_feature_f411_single_threaded_quiet_search_stats() {
	dir, mut cmd := setup('feature_f411_single_threaded_quiet_search_stats')
	dir.create('sherlock', sherlock)
	cmd.args(['--quiet', '-j1', '--stats', 'Sherlock'])
	lines := cmd.stdout()
	assert !lines.contains('Sherlock')
	assert lines.contains('2 matched lines')
	assert lines.contains('1 files contained matches')
	assert lines.contains('1 files searched')
	assert lines.contains('seconds')
}

fn test_feature_f411_parallel_quiet_search_stats() {
	dir, mut cmd := setup('feature_f411_parallel_quiet_search_stats')
	dir.create('sherlock_1', sherlock)
	dir.create('sherlock_2', sherlock)
	cmd.args(['-j2', '--quiet', '--stats', 'Sherlock'])
	lines := cmd.stdout()
	assert !lines.contains('Sherlock')
	assert lines.contains('4 matched lines')
	assert lines.contains('2 files contained matches')
	assert lines.contains('2 files searched')
	assert lines.contains('seconds')
}

// See: https://github.com/BurntSushi/ripgrep/issues/416
fn test_feature_f416_crlf() {
	dir, mut cmd := setup('feature_f416_crlf')
	dir.create('sherlock', sherlock_crlf)
	cmd.args(['--crlf', r'Sherlock$', 'sherlock'])
	eqnice('For the Doctor Watsons of this world, as opposed to the Sherlock\r\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/416
fn test_feature_f416_crlf_multiline() {
	dir, mut cmd := setup('feature_f416_crlf_multiline')
	dir.create('sherlock', sherlock_crlf)
	cmd.args(['--crlf', '-U', r'Sherlock$', 'sherlock'])
	eqnice('For the Doctor Watsons of this world, as opposed to the Sherlock\r\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/416
fn test_feature_f416_crlf_only_matching() {
	dir, mut cmd := setup('feature_f416_crlf_only_matching')
	dir.create('sherlock', sherlock_crlf)
	cmd.args(['--crlf', '-o', r'Sherlock$', 'sherlock'])
	eqnice('Sherlock\r\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/419
fn test_feature_f419_zero_as_shortcut_for_null() {
	dir, mut cmd := setup('feature_f419_zero_as_shortcut_for_null')
	dir.create('sherlock', sherlock)
	cmd.args(['-0', '--count', 'Sherlock'])
	eqnice('sherlock\x002\n', cmd.stdout())
}

fn test_feature_f740_passthru() {
	dir, mut cmd := setup('feature_f740_passthru')
	dir.create('file', '\nfoo\nbar\nfoobar\n\nbaz\n')
	dir.create('patterns', 'foo\nbar\n')

	common_args := ['-n', '--passthru']
	foo_expected := '1-\n2:foo\n3-bar\n4:foobar\n5-\n6-baz\n'
	cmd.args(common_args)
	cmd.args(['foo', 'file'])
	eqnice(foo_expected, cmd.stdout())

	foo_bar_expected := '1-\n2:foo\n3:bar\n4:foobar\n5-\n6-baz\n'
	mut cmd_patterns := dir.command()
	cmd_patterns.args(common_args)
	cmd_patterns.args(['-e', 'foo', '-e', 'bar', 'file'])
	eqnice(foo_bar_expected, cmd_patterns.stdout())

	mut cmd_file_patterns := dir.command()
	cmd_file_patterns.args(common_args)
	cmd_file_patterns.args(['-f', 'patterns', 'file'])
	eqnice(foo_bar_expected, cmd_file_patterns.stdout())

	mut cmd_count := dir.command()
	cmd_count.args(common_args)
	cmd_count.args(['-c', 'foo', 'file'])
	eqnice('2\n', cmd_count.stdout())

	only_foo_expected := '1-\n2:foo\n3-bar\n4:foo\n5-\n6-baz\n'
	mut cmd_only := dir.command()
	cmd_only.args(common_args)
	cmd_only.args(['-o', 'foo', 'file'])
	eqnice(only_foo_expected, cmd_only.stdout())

	replace_foo_expected := '1-\n2:wat\n3-bar\n4:watbar\n5-\n6-baz\n'
	mut cmd_replace := dir.command()
	cmd_replace.args(common_args)
	cmd_replace.args(['-r', 'wat', 'foo', 'file'])
	eqnice(replace_foo_expected, cmd_replace.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/948
fn test_feature_f948_exit_code_match() {
	dir, mut cmd := setup('feature_f948_exit_code_match')
	dir.create('sherlock', sherlock)
	cmd.arg('.')
	cmd.assert_exit_code(0)
}

// See: https://github.com/BurntSushi/ripgrep/issues/948
fn test_feature_f948_exit_code_no_match() {
	dir, mut cmd := setup('feature_f948_exit_code_no_match')
	dir.create('sherlock', sherlock)
	cmd.arg('NADA')
	cmd.assert_exit_code(1)
}

// See: https://github.com/BurntSushi/ripgrep/issues/948
fn test_feature_f948_exit_code_error() {
	dir, mut cmd := setup('feature_f948_exit_code_error')
	dir.create('sherlock', sherlock)
	cmd.arg('*')
	cmd.assert_exit_code(2)
}

// See: https://github.com/BurntSushi/ripgrep/issues/917
fn test_feature_f917_trim() {
	dir, mut cmd := setup('feature_f917_trim')
	text := 'zzz\n    For the Doctor Watsons of this world, as opposed to the Sherlock\n  Holmeses, success in the province of detective work must always\n\tbe, to a very large extent, the result of luck. Sherlock Holmes\n     can extract a clew from a wisp of straw or a flake of cigar ash;\nbut Doctor Watson has to have it taken out for him and dusted,\n and exhibited clearly, with a label attached.\n'
	dir.create('sherlock', text)
	cmd.args(['-n', '-B1', '-A2', '--trim', 'Holmeses', 'sherlock'])
	expected := '2-For the Doctor Watsons of this world, as opposed to the Sherlock\n3:Holmeses, success in the province of detective work must always\n4-be, to a very large extent, the result of luck. Sherlock Holmes\n5-can extract a clew from a wisp of straw or a flake of cigar ash;\n'
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/917
//
// This is like f917_trim, except this tests that trimming occurs even when the
// whitespace is part of a match.
fn test_feature_f917_trim_match() {
	dir, mut cmd := setup('feature_f917_trim_match')
	text := 'zzz\n    For the Doctor Watsons of this world, as opposed to the Sherlock\n  Holmeses, success in the province of detective work must always\n\tbe, to a very large extent, the result of luck. Sherlock Holmes\n     can extract a clew from a wisp of straw or a flake of cigar ash;\nbut Doctor Watson has to have it taken out for him and dusted,\n and exhibited clearly, with a label attached.\n'
	dir.create('sherlock', text)
	cmd.args(['-n', '-B1', '-A2', '--trim', r'\s+Holmeses', 'sherlock'])
	expected := '2-For the Doctor Watsons of this world, as opposed to the Sherlock\n3:Holmeses, success in the province of detective work must always\n4-be, to a very large extent, the result of luck. Sherlock Holmes\n5-can extract a clew from a wisp of straw or a flake of cigar ash;\n'
	eqnice(expected, cmd.stdout())
}

fn test_feature_f917_trim_multi_standard() {
	dir, mut cmd := setup('feature_f917_trim_multi_standard')
	dir.create('haystack', '     0123456789abcdefghijklmnopqrstuvwxyz')
	cmd.args(['--multiline', '--trim', '-r$0', '--no-filename', r'a\n?bc'])
	eqnice('0123456789abcdefghijklmnopqrstuvwxyz\n', cmd.stdout())
}

fn test_feature_f917_trim_max_columns_normal() {
	dir, mut cmd := setup('feature_f917_trim_max_columns_normal')
	dir.create('haystack', '     0123456789abcdefghijklmnopqrstuvwxyz')
	cmd.args(['--trim', '--max-columns-preview', '-M8', '--no-filename', 'abc'])
	eqnice('01234567 [... omitted end of long line]\n', cmd.stdout())
}

fn test_feature_f917_trim_max_columns_matches() {
	dir, mut cmd := setup('feature_f917_trim_max_columns_matches')
	dir.create('haystack', '     0123456789abcdefghijklmnopqrstuvwxyz')
	cmd.args(['--trim', '--max-columns-preview', '-M8', '--color=always', '--colors=path:none',
		'--no-filename', 'abc'])
	eqnice('01234567 [... 1 more match]\n', cmd.stdout())
}

fn test_feature_f917_trim_max_columns_multi_standard() {
	dir, mut cmd := setup('feature_f917_trim_max_columns_multi_standard')
	dir.create('haystack', '     0123456789abcdefghijklmnopqrstuvwxyz')
	cmd.args(['--multiline', '--trim', '--max-columns-preview', '-M8', '--color=always',
		'--colors=path:none', '--no-filename', r'a\n?bc'])
	eqnice('01234567 [... 1 more match]\n', cmd.stdout())
}

fn test_feature_f917_trim_max_columns_multi_only_matching() {
	dir, mut cmd := setup('feature_f917_trim_max_columns_multi_only_matching')
	dir.create('haystack', '     0123456789abcdefghijklmnopqrstuvwxyz')
	cmd.args(['--multiline', '--trim', '--max-columns-preview', '-M8', '--only-matching',
		'--no-filename', r'.*a\n?bc.*'])
	eqnice('01234567 [... 0 more matches]\n', cmd.stdout())
}

fn test_feature_f917_trim_max_columns_multi_per_match() {
	dir, mut cmd := setup('feature_f917_trim_max_columns_multi_per_match')
	dir.create('haystack', '     0123456789abcdefghijklmnopqrstuvwxyz')
	cmd.args(['--multiline', '--trim', '--max-columns-preview', '-M8', '--vimgrep',
		'--no-filename', r'.*a\n?bc.*'])
	eqnice('1:1:01234567 [... 0 more matches]\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/993
fn test_feature_f993_null_data() {
	dir, mut cmd := setup('feature_f993_null_data')
	dir.create('test', 'foo\x00bar\x00\x00\x00baz\x00')
	cmd.args(['--null-data', r'.+', 'test'])

	// If we just used -a instead of --null-data, then the result would include
	// all NUL bytes.
	eqnice('foo\x00bar\x00baz\x00', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1078
//
// N.B. There are many more tests in the grep-printer crate.
fn test_feature_f1078_max_columns_preview1() {
	dir, mut cmd := setup('feature_f1078_max_columns_preview1')
	dir.create('sherlock', sherlock)
	cmd.args(['-M46', '--max-columns-preview', 'exhibited|dusted|has to have it'])
	expected := 'sherlock:but Doctor Watson has to have it taken out for [... omitted end of long line]\nsherlock:and exhibited clearly, with a label attached.\n'
	eqnice(expected, cmd.stdout())
}

fn test_feature_f1078_max_columns_preview2() {
	dir, mut cmd := setup('feature_f1078_max_columns_preview2')
	dir.create('sherlock', sherlock)
	cmd.args(['-M43', '--max-columns-preview', '-rxxx', 'exhibited|dusted|has to have it'])
	expected := 'sherlock:but Doctor Watson xxx taken out for him and [... 1 more match]\nsherlock:and xxx clearly, with a label attached.\n'
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1138
fn test_feature_f1138_no_ignore_dot() {
	dir, mut cmd := setup('feature_f1138_no_ignore_dot')
	dir.create_dir('.git')
	dir.create('.gitignore', 'foo')
	dir.create('.ignore', 'bar')
	dir.create('.fzf-ignore', 'quux')
	dir.create('foo', '')
	dir.create('bar', '')
	dir.create('quux', '')

	cmd.args(['--sort', 'path', '--files'])
	eqnice('quux\n', cmd.stdout())
	cmd.arg('--no-ignore-dot')
	eqnice('bar\nquux\n', cmd.stdout())
	cmd.args(['--ignore-file', '.fzf-ignore'])
	eqnice('bar\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1155
fn test_feature_f1155_auto_hybrid_regex() {
	dir, mut cmd := setup('feature_f1155_auto_hybrid_regex')
	// No sense in testing a hybrid regex engine with only one engine!
	if !dir.is_pcre2() {
		return
	}

	dir.create('sherlock', sherlock)
	cmd.args(['--no-pcre2', '--auto-hybrid-regex', r'(?<=the )Sherlock'])
	expected := 'sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock\n'
	eqnice(expected, cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1207
//
// Tests if without encoding 'none' flag null bytes are consumed by automatic
// encoding detection.
fn test_feature_f1207_auto_encoding() {
	dir, mut cmd := setup('feature_f1207_auto_encoding')
	dir.create_bytes('foo', [u8(0xff), 0xfe, 0x00, 0x62])
	cmd.args(['-a', r'\x00', 'foo'])
	cmd.assert_exit_code(1)
}

// See: https://github.com/BurntSushi/ripgrep/issues/1207
//
// Tests if encoding 'none' flag does treat file as raw bytes
fn test_feature_f1207_ignore_encoding() {
	dir, mut cmd := setup('feature_f1207_ignore_encoding')
	// PCRE2 chokes on this test because it can't search invalid non-UTF-8
	// and the point of this test is to search raw UTF-16.
	if dir.is_pcre2() {
		return
	}

	dir.create_bytes('foo', [u8(0xff), 0xfe, 0x00, 0x62])
	cmd.args(['--encoding', 'none', '-a', r'\x00', 'foo'])
	eqnice('��\x00b\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1414
fn test_feature_f1414_no_require_git() {
	dir, mut cmd := setup('feature_f1414_no_require_git')
	dir.create('.gitignore', 'foo')
	dir.create('foo', '')
	dir.create('bar', '')

	cmd.args(['--sort', 'path', '--files'])
	eqnice('bar\nfoo\n', cmd.stdout())

	cmd.args(['--no-require-git'])
	eqnice('bar\n', cmd.stdout())

	cmd.args(['--require-git'])
	eqnice('bar\nfoo\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/pull/1420
fn test_feature_f1420_no_ignore_exclude() {
	dir, mut cmd := setup('feature_f1420_no_ignore_exclude')
	dir.create_dir('.git/info')
	dir.create('.git/info/exclude', 'foo')
	dir.create('bar', '')
	dir.create('foo', '')

	cmd.args(['--sort', 'path', '--files'])
	eqnice('bar\n', cmd.stdout())
	cmd.arg('--no-ignore-exclude')
	eqnice('bar\nfoo\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/pull/1466
fn test_feature_f1466_no_ignore_files() {
	dir, mut cmd := setup('feature_f1466_no_ignore_files')
	dir.create('.myignore', 'bar')
	dir.create('bar', '')
	dir.create('foo', '')

	// Test that --no-ignore-files disables --ignore-file.
	// And that --ignore-files overrides --no-ignore-files.
	cmd.args(['--sort', 'path', '--files'])
	eqnice('bar\nfoo\n', cmd.stdout())
	cmd.args(['--ignore-file', '.myignore'])
	eqnice('foo\n', cmd.stdout())
	cmd.arg('--no-ignore-files')
	eqnice('bar\nfoo\n', cmd.stdout())
	cmd.arg('--ignore-files')
	eqnice('foo\n', cmd.stdout())

	// Test that the -u flag does not disable --ignore-file.
	mut cmd2 := dir.command()
	cmd2.args(['--sort', 'path', '--files'])
	cmd2.args(['--ignore-file', '.myignore'])
	eqnice('foo\n', cmd2.stdout())
	cmd2.arg('-u')
	eqnice('foo\n', cmd2.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/pull/2361
fn test_feature_f2361_sort_nested_files() {
	dir, mut cmd := setup('feature_f2361_sort_nested_files')
	dir.create('foo', '1')
	time.sleep(200 * time.millisecond)
	dir.create_dir('dir')
	time.sleep(200 * time.millisecond)
	dir.create('dir/bar', '1')

	cmd.args(['--sort', 'accessed', '--files'])
	eqnice('foo\ndir/bar\n', cmd.stdout())

	dir.create('foo', '2')
	time.sleep(200 * time.millisecond)
	dir.create('dir/bar', '2')
	time.sleep(200 * time.millisecond)

	cmd.args(['--sort', 'accessed', '--files'])
	eqnice('foo\ndir/bar\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1404
fn test_feature_f1404_nothing_searched_warning() {
	dir, mut cmd := setup('feature_f1404_nothing_searched_warning')
	dir.create('.ignore', 'ignored-dir/**')
	dir.create_dir('ignored-dir')
	dir.create('ignored-dir/foo', 'needle')

	// Test that, if ripgrep searches only ignored folders/files, then there
	// is a non-zero exit code.
	cmd.arg('needle')
	cmd.assert_err()

	// Test that we actually get an error message that we expect.
	output := cmd.raw_output()
	expected := 'rg: No files were searched, which means ripgrep probably applied a filter you didn\'t expect.\nRunning with --debug will show why files are being skipped.\n'
	eqnice(expected, output.stderr)
}

// See: https://github.com/BurntSushi/ripgrep/issues/1404
fn test_feature_f1404_nothing_searched_ignored() {
	dir, mut cmd := setup('feature_f1404_nothing_searched_ignored')
	dir.create('.ignore', 'ignored-dir/**')
	dir.create_dir('ignored-dir')
	dir.create('ignored-dir/foo', 'needle')

	// Test that, if ripgrep searches only ignored folders/files, then there
	// is a non-zero exit code.
	cmd.args(['--no-messages', 'needle'])
	cmd.assert_err()

	// But since --no-messages is given, there should not be any error message
	// printed.
	output := cmd.raw_output()
	eqnice('', output.stderr)
}

// See: https://github.com/BurntSushi/ripgrep/issues/1842
fn test_feature_f1842_field_context_separator() {
	dir, _ := setup('feature_f1842_field_context_separator')
	dir.create('sherlock', sherlock)

	// Test the default.
	base := ['-n', '-A1', 'Doctor Watsons', 'sherlock']
	expected1 := '1:For the Doctor Watsons of this world, as opposed to the Sherlock\n2-Holmeses, success in the province of detective work must always\n'
	mut cmd1 := dir.command()
	cmd1.args(base)
	eqnice(expected1, cmd1.stdout())

	// Test that it can be overridden.
	mut cmd2 := dir.command()
	cmd2.args(['--field-context-separator', '!'])
	cmd2.args(base)
	expected2 := '1:For the Doctor Watsons of this world, as opposed to the Sherlock\n2!Holmeses, success in the province of detective work must always\n'
	eqnice(expected2, cmd2.stdout())

	// Test that it can use multiple bytes.
	mut cmd3 := dir.command()
	cmd3.args(['--field-context-separator', '!!'])
	cmd3.args(base)
	expected3 := '1:For the Doctor Watsons of this world, as opposed to the Sherlock\n2!!Holmeses, success in the province of detective work must always\n'
	eqnice(expected3, cmd3.stdout())

	// Test that unescaping works.
	mut cmd4 := dir.command()
	cmd4.args(['--field-context-separator', r'\x7F'])
	cmd4.args(base)
	expected4 := '1:For the Doctor Watsons of this world, as opposed to the Sherlock\n2\x7FHolmeses, success in the province of detective work must always\n'
	eqnice(expected4, cmd4.stdout())

	// Test that an empty separator is OK.
	mut cmd5 := dir.command()
	cmd5.args(['--field-context-separator', r''])
	cmd5.args(base)
	expected5 := '1:For the Doctor Watsons of this world, as opposed to the Sherlock\n2Holmeses, success in the province of detective work must always\n'
	eqnice(expected5, cmd5.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/1842
fn test_feature_f1842_field_match_separator() {
	dir, _ := setup('feature_f1842_field_match_separator')
	dir.create('sherlock', sherlock)

	// Test the default.
	base := ['-n', 'Doctor Watsons', 'sherlock']
	expected1 := '1:For the Doctor Watsons of this world, as opposed to the Sherlock\n'
	mut cmd1 := dir.command()
	cmd1.args(base)
	eqnice(expected1, cmd1.stdout())

	// Test that it can be overridden.
	mut cmd2 := dir.command()
	cmd2.args(['--field-match-separator', '!'])
	cmd2.args(base)
	expected2 := '1!For the Doctor Watsons of this world, as opposed to the Sherlock\n'
	eqnice(expected2, cmd2.stdout())

	// Test that it can use multiple bytes.
	mut cmd3 := dir.command()
	cmd3.args(['--field-match-separator', '!!'])
	cmd3.args(base)
	expected3 := '1!!For the Doctor Watsons of this world, as opposed to the Sherlock\n'
	eqnice(expected3, cmd3.stdout())

	// Test that unescaping works.
	mut cmd4 := dir.command()
	cmd4.args(['--field-match-separator', r'\x7F'])
	cmd4.args(base)
	expected4 := '1\x7FFor the Doctor Watsons of this world, as opposed to the Sherlock\n'
	eqnice(expected4, cmd4.stdout())

	// Test that an empty separator is OK.
	mut cmd5 := dir.command()
	cmd5.args(['--field-match-separator', r''])
	cmd5.args(base)
	expected5 := '1For the Doctor Watsons of this world, as opposed to the Sherlock\n'
	eqnice(expected5, cmd5.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/2288
fn test_feature_f2288_context_partial_override() {
	dir, mut cmd := setup('feature_f2288_context_partial_override')
	dir.create('test', '1\n2\n3\n4\n5\n6\n7\n8\n9\n')
	cmd.args(['-C1', '-A2', '5', 'test'])
	eqnice('4\n5\n6\n7\n', cmd.stdout())
}

// See: https://github.com/BurntSushi/ripgrep/issues/2288
fn test_feature_f2288_context_partial_override_rev() {
	dir, mut cmd := setup('feature_f2288_context_partial_override_rev')
	dir.create('test', '1\n2\n3\n4\n5\n6\n7\n8\n9\n')
	cmd.args(['-A2', '-C1', '5', 'test'])
	eqnice('4\n5\n6\n7\n', cmd.stdout())
}

fn test_feature_no_context_sep() {
	dir, mut cmd := setup('feature_no_context_sep')
	dir.create('test', 'foo\nctx\nbar\nctx\nfoo\nctx')
	cmd.args(['-A1', '--no-context-separator', 'foo', 'test'])
	eqnice('foo\nctx\nfoo\nctx\n', cmd.stdout())
}

fn test_feature_no_context_sep_overrides() {
	dir, mut cmd := setup('feature_no_context_sep_overrides')
	dir.create('test', 'foo\nctx\nbar\nctx\nfoo\nctx')
	cmd.args(['-A1', '--context-separator', 'AAA', '--no-context-separator', 'foo', 'test'])
	eqnice('foo\nctx\nfoo\nctx\n', cmd.stdout())
}

fn test_feature_no_context_sep_overridden() {
	dir, mut cmd := setup('feature_no_context_sep_overridden')
	dir.create('test', 'foo\nctx\nbar\nctx\nfoo\nctx')
	cmd.args(['-A1', '--no-context-separator', '--context-separator', 'AAA', 'foo', 'test'])
	eqnice('foo\nctx\nAAA\nfoo\nctx\n', cmd.stdout())
}

fn test_feature_context_sep() {
	dir, mut cmd := setup('feature_context_sep')
	dir.create('test', 'foo\nctx\nbar\nctx\nfoo\nctx')
	cmd.args(['-A1', '--context-separator', 'AAA', 'foo', 'test'])
	eqnice('foo\nctx\nAAA\nfoo\nctx\n', cmd.stdout())
}

fn test_feature_context_sep_default() {
	dir, mut cmd := setup('feature_context_sep_default')
	dir.create('test', 'foo\nctx\nbar\nctx\nfoo\nctx')
	cmd.args(['-A1', 'foo', 'test'])
	eqnice('foo\nctx\n--\nfoo\nctx\n', cmd.stdout())
}

fn test_feature_context_sep_empty() {
	dir, mut cmd := setup('feature_context_sep_empty')
	dir.create('test', 'foo\nctx\nbar\nctx\nfoo\nctx')
	cmd.args(['-A1', '--context-separator', '', 'foo', 'test'])
	eqnice('foo\nctx\n\nfoo\nctx\n', cmd.stdout())
}

fn test_feature_no_unicode() {
	dir, mut cmd := setup('feature_no_unicode')
	dir.create('test', 'δ')
	cmd.args(['-i', '--no-unicode', 'Δ'])
	cmd.assert_err()
}

// See: https://github.com/BurntSushi/ripgrep/issues/1790
fn test_feature_stop_on_nonmatch() {
	dir, mut cmd := setup('feature_stop_on_nonmatch')
	dir.create('test', 'line1\nline2\nline3\nline4\nline5')
	cmd.args(['--stop-on-nonmatch', '[235]'])
	eqnice('test:line2\ntest:line3\n', cmd.stdout())
}
