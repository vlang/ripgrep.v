module integration

import time

// This file contains "miscellaneous" tests that were either written before
// features were tracked more explicitly, or were simply written without
// linking them to a specific issue number. We should try to minimize the
// addition of more tests in this file and instead add them to either the
// regression test suite or the feature test suite (found in regression.rs and
// feature.rs, respectively).

fn test_misc_single_file() {
	dir, mut cmd := setup('misc_single_file')
	dir.create('sherlock', sherlock)

	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
be, to a very large extent, the result of luck. Sherlock Holmes
'
	cmd.args(['Sherlock', 'sherlock'])
	eqnice(expected, cmd.stdout())
}

fn test_misc_dir() {
	dir, mut cmd := setup('misc_dir')
	dir.create('sherlock', sherlock)

	expected := 'sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:be, to a very large extent, the result of luck. Sherlock Holmes
'
	cmd.arg('Sherlock')
	eqnice(expected, cmd.stdout())
}

fn test_misc_line_numbers() {
	dir, mut cmd := setup('misc_line_numbers')
	dir.create('sherlock', sherlock)

	expected := '1:For the Doctor Watsons of this world, as opposed to the Sherlock
3:be, to a very large extent, the result of luck. Sherlock Holmes
'
	cmd.args(['-n', 'Sherlock', 'sherlock'])
	eqnice(expected, cmd.stdout())
}

fn test_misc_columns() {
	dir, mut cmd := setup('misc_columns')
	dir.create('sherlock', sherlock)
	cmd.args(['--column', 'Sherlock', 'sherlock'])

	expected := '1:57:For the Doctor Watsons of this world, as opposed to the Sherlock
3:49:be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_with_filename() {
	dir, mut cmd := setup('misc_with_filename')
	dir.create('sherlock', sherlock)
	cmd.args(['-H', 'Sherlock', 'sherlock'])

	expected := 'sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_with_heading() {
	dir, mut cmd := setup('misc_with_heading')
	dir.create('sherlock', sherlock)
	cmd.args([
		// This forces the issue since --with-filename is disabled by default
		// when searching one file.
		'--with-filename',
		'--heading',
		'Sherlock',
		'sherlock',
	])

	expected := 'sherlock
For the Doctor Watsons of this world, as opposed to the Sherlock
be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_with_heading_default() {
	// Search two or more and get --with-filename enabled by default.
	// Use -j1 to get deterministic results.
	dir, mut cmd := setup('misc_with_heading_default')
	dir.create('sherlock', sherlock)
	dir.create('foo', 'Sherlock Holmes lives on Baker Street.')
	cmd.args(['-j1', '--heading', 'Sherlock'])

	expected := 'foo
Sherlock Holmes lives on Baker Street.

sherlock
For the Doctor Watsons of this world, as opposed to the Sherlock
be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(sort_lines(expected), sort_lines(cmd.stdout()))
}

fn test_misc_inverted() {
	dir, mut cmd := setup('misc_inverted')
	dir.create('sherlock', sherlock)
	cmd.args(['-v', 'Sherlock', 'sherlock'])

	expected := 'Holmeses, success in the province of detective work must always
can extract a clew from a wisp of straw or a flake of cigar ash;
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_inverted_line_numbers() {
	dir, mut cmd := setup('misc_inverted_line_numbers')
	dir.create('sherlock', sherlock)
	cmd.args(['-n', '-v', 'Sherlock', 'sherlock'])

	expected := '2:Holmeses, success in the province of detective work must always
4:can extract a clew from a wisp of straw or a flake of cigar ash;
5:but Doctor Watson has to have it taken out for him and dusted,
6:and exhibited clearly, with a label attached.
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_case_insensitive() {
	dir, mut cmd := setup('misc_case_insensitive')
	dir.create('sherlock', sherlock)
	cmd.args(['-i', 'sherlock', 'sherlock'])

	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_word() {
	dir, mut cmd := setup('misc_word')
	dir.create('sherlock', sherlock)
	cmd.args(['-w', 'as', 'sherlock'])

	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_word_period() {
	dir, mut cmd := setup('misc_word_period')
	dir.create('haystack', '...')
	cmd.args(['-ow', '.', 'haystack'])

	expected := '.
.
.
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_line() {
	dir, mut cmd := setup('misc_line')
	dir.create('sherlock', sherlock)
	cmd.args([
		'-x',
		'Watson|and exhibited clearly, with a label attached.',
		'sherlock',
	])

	expected := 'and exhibited clearly, with a label attached.
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_literal() {
	dir, mut cmd := setup('misc_literal')
	dir.create('sherlock', sherlock)
	dir.create('file', 'blib
()
blab
')
	cmd.args(['-F', '()', 'file'])

	eqnice('()\n', cmd.stdout())
}

fn test_misc_quiet() {
	dir, mut cmd := setup('misc_quiet')
	dir.create('sherlock', sherlock)
	cmd.args(['-q', 'Sherlock', 'sherlock'])

	assert cmd.stdout().len == 0
}

fn test_misc_replace() {
	dir, mut cmd := setup('misc_replace')
	dir.create('sherlock', sherlock)
	cmd.args(['-r', 'FooBar', 'Sherlock', 'sherlock'])

	expected := 'For the Doctor Watsons of this world, as opposed to the FooBar
be, to a very large extent, the result of luck. FooBar Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_replace_groups() {
	dir, mut cmd := setup('misc_replace_groups')
	dir.create('sherlock', sherlock)
	cmd.args(['-r', '$2, $1', '([A-Z][a-z]+) ([A-Z][a-z]+)', 'sherlock'])

	expected := 'For the Watsons, Doctor of this world, as opposed to the Sherlock
be, to a very large extent, the result of luck. Holmes, Sherlock
but Watson, Doctor has to have it taken out for him and dusted,
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_replace_named_groups() {
	dir, mut cmd := setup('misc_replace_named_groups')
	dir.create('sherlock', sherlock)
	cmd.args([
		'-r',
		'$last, $first',
		'(?P<first>[A-Z][a-z]+) (?P<last>[A-Z][a-z]+)',
		'sherlock',
	])

	expected := 'For the Watsons, Doctor of this world, as opposed to the Sherlock
be, to a very large extent, the result of luck. Holmes, Sherlock
but Watson, Doctor has to have it taken out for him and dusted,
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_replace_with_only_matching() {
	dir, mut cmd := setup('misc_replace_with_only_matching')
	dir.create('sherlock', sherlock)
	cmd.args(['-o', '-r', '$1', r'of (\w+)', 'sherlock'])

	expected := 'this
detective
luck
straw
cigar
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_file_types() {
	dir, mut cmd := setup('misc_file_types')
	dir.create('sherlock', sherlock)
	dir.create('file.py', 'Sherlock')
	dir.create('file.rs', 'Sherlock')
	cmd.args(['-t', 'rust', 'Sherlock'])

	eqnice('file.rs:Sherlock\n', cmd.stdout())
}

fn test_misc_file_types_all() {
	dir, mut cmd := setup('misc_file_types_all')
	dir.create('sherlock', sherlock)
	dir.create('file.py', 'Sherlock')
	cmd.args(['-t', 'all', 'Sherlock'])

	eqnice('file.py:Sherlock\n', cmd.stdout())
}

fn test_misc_file_types_negate() {
	dir, mut cmd := setup('misc_file_types_negate')
	dir.create('sherlock', sherlock)
	dir.remove('sherlock')
	dir.create('file.py', 'Sherlock')
	dir.create('file.rs', 'Sherlock')
	cmd.args(['-T', 'rust', 'Sherlock'])

	eqnice('file.py:Sherlock\n', cmd.stdout())
}

fn test_misc_file_types_negate_all() {
	dir, mut cmd := setup('misc_file_types_negate_all')
	dir.create('sherlock', sherlock)
	dir.create('file.py', 'Sherlock')
	cmd.args(['-T', 'all', 'Sherlock'])

	expected := 'sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_file_type_clear() {
	dir, mut cmd := setup('misc_file_type_clear')
	dir.create('sherlock', sherlock)
	dir.create('file.py', 'Sherlock')
	dir.create('file.rs', 'Sherlock')
	cmd.args(['--type-clear', 'rust', '-t', 'rust', 'Sherlock'])

	cmd.assert_non_empty_stderr()
}

fn test_misc_file_type_add() {
	dir, mut cmd := setup('misc_file_type_add')
	dir.create('sherlock', sherlock)
	dir.create('file.py', 'Sherlock')
	dir.create('file.rs', 'Sherlock')
	dir.create('file.wat', 'Sherlock')
	cmd.args(['--type-add', 'wat:*.wat', '-t', 'wat', 'Sherlock'])

	eqnice('file.wat:Sherlock\n', cmd.stdout())
}

fn test_misc_file_type_add_compose() {
	dir, mut cmd := setup('misc_file_type_add_compose')
	dir.create('sherlock', sherlock)
	dir.create('file.py', 'Sherlock')
	dir.create('file.rs', 'Sherlock')
	dir.create('file.wat', 'Sherlock')
	cmd.args([
		'--type-add',
		'wat:*.wat',
		'--type-add',
		'combo:include:wat,py',
		'-t',
		'combo',
		'Sherlock',
	])

	expected := 'file.py:Sherlock
file.wat:Sherlock
'
	eqnice(expected, sort_lines(cmd.stdout()))
}

fn test_misc_glob() {
	dir, mut cmd := setup('misc_glob')
	dir.create('sherlock', sherlock)
	dir.create('file.py', 'Sherlock')
	dir.create('file.rs', 'Sherlock')
	cmd.args(['-g', '*.rs', 'Sherlock'])

	eqnice('file.rs:Sherlock\n', cmd.stdout())
}

fn test_misc_glob_negate() {
	dir, mut cmd := setup('misc_glob_negate')
	dir.create('sherlock', sherlock)
	dir.remove('sherlock')
	dir.create('file.py', 'Sherlock')
	dir.create('file.rs', 'Sherlock')
	cmd.args(['-g', '!*.rs', 'Sherlock'])

	eqnice('file.py:Sherlock\n', cmd.stdout())
}

fn test_misc_glob_case_insensitive() {
	dir, mut cmd := setup('misc_glob_case_insensitive')
	dir.create('sherlock', sherlock)
	dir.create('file.HTML', 'Sherlock')
	cmd.args(['--iglob', '*.html', 'Sherlock'])

	eqnice('file.HTML:Sherlock\n', cmd.stdout())
}

fn test_misc_glob_case_sensitive() {
	dir, mut cmd := setup('misc_glob_case_sensitive')
	dir.create('sherlock', sherlock)
	dir.create('file1.HTML', 'Sherlock')
	dir.create('file2.html', 'Sherlock')
	cmd.args(['--glob', '*.html', 'Sherlock'])

	eqnice('file2.html:Sherlock\n', cmd.stdout())
}

fn test_misc_glob_always_case_insensitive() {
	dir, mut cmd := setup('misc_glob_always_case_insensitive')
	dir.create('sherlock', sherlock)
	dir.create('file.HTML', 'Sherlock')
	cmd.args(['--glob-case-insensitive', '--glob', '*.html', 'Sherlock'])

	eqnice('file.HTML:Sherlock\n', cmd.stdout())
}

fn test_misc_byte_offset_only_matching() {
	dir, mut cmd := setup('misc_byte_offset_only_matching')
	dir.create('sherlock', sherlock)
	cmd.args(['-b', '-o', 'Sherlock'])

	expected := 'sherlock:56:Sherlock
sherlock:177:Sherlock
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_count() {
	dir, mut cmd := setup('misc_count')
	dir.create('sherlock', sherlock)
	cmd.args(['--count', 'Sherlock'])

	expected := 'sherlock:2\n'
	eqnice(expected, cmd.stdout())
}

fn test_misc_count_matches() {
	dir, mut cmd := setup('misc_count_matches')
	dir.create('sherlock', sherlock)
	cmd.args(['--count-matches', 'the'])

	expected := 'sherlock:4\n'
	eqnice(expected, cmd.stdout())
}

fn test_misc_count_matches_inverted() {
	dir, mut cmd := setup('misc_count_matches_inverted')
	dir.create('sherlock', sherlock)
	cmd.args(['--count-matches', '--invert-match', 'Sherlock'])

	expected := 'sherlock:4\n'
	eqnice(expected, cmd.stdout())
}

fn test_misc_count_matches_via_only() {
	dir, mut cmd := setup('misc_count_matches_via_only')
	dir.create('sherlock', sherlock)
	cmd.args(['--count', '--only-matching', 'the'])

	expected := 'sherlock:4\n'
	eqnice(expected, cmd.stdout())
}

fn test_misc_include_zero() {
	dir, mut cmd := setup('misc_include_zero')
	dir.create('sherlock', sherlock)
	cmd.args(['--count', '--include-zero', 'nada'])
	cmd.assert_err()

	output := cmd.raw_output()
	expected := 'sherlock:0\n'

	eqnice(expected, output.stdout)
}

fn test_misc_include_zero_override() {
	dir, mut cmd := setup('misc_include_zero_override')
	dir.create('sherlock', sherlock)
	cmd.args(['--count', '--include-zero', '--no-include-zero', 'nada'])
	cmd.assert_err()

	output := cmd.raw_output()
	assert output.stdout.len == 0
}

fn test_misc_files_with_matches() {
	dir, mut cmd := setup('misc_files_with_matches')
	dir.create('sherlock', sherlock)
	cmd.args(['--files-with-matches', 'Sherlock'])

	expected := 'sherlock\n'
	eqnice(expected, cmd.stdout())
}

fn test_misc_files_without_match() {
	dir, mut cmd := setup('misc_files_without_match')
	dir.create('sherlock', sherlock)
	dir.create('file.py', 'foo')
	cmd.args(['--files-without-match', 'Sherlock'])

	expected := 'file.py\n'
	eqnice(expected, cmd.stdout())
}

fn test_misc_after_context() {
	dir, mut cmd := setup('misc_after_context')
	dir.create('sherlock', sherlock)
	cmd.args(['-A', '1', 'Sherlock', 'sherlock'])

	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
be, to a very large extent, the result of luck. Sherlock Holmes
can extract a clew from a wisp of straw or a flake of cigar ash;
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_after_context_line_numbers() {
	dir, mut cmd := setup('misc_after_context_line_numbers')
	dir.create('sherlock', sherlock)
	cmd.args(['-A', '1', '-n', 'Sherlock', 'sherlock'])

	expected := '1:For the Doctor Watsons of this world, as opposed to the Sherlock
2-Holmeses, success in the province of detective work must always
3:be, to a very large extent, the result of luck. Sherlock Holmes
4-can extract a clew from a wisp of straw or a flake of cigar ash;
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_before_context() {
	dir, mut cmd := setup('misc_before_context')
	dir.create('sherlock', sherlock)
	cmd.args(['-B', '1', 'Sherlock', 'sherlock'])

	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_before_context_line_numbers() {
	dir, mut cmd := setup('misc_before_context_line_numbers')
	dir.create('sherlock', sherlock)
	cmd.args(['-B', '1', '-n', 'Sherlock', 'sherlock'])

	expected := '1:For the Doctor Watsons of this world, as opposed to the Sherlock
2-Holmeses, success in the province of detective work must always
3:be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_context() {
	dir, mut cmd := setup('misc_context')
	dir.create('sherlock', sherlock)
	cmd.args(['-C', '1', 'world|attached', 'sherlock'])

	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
--
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_context_line_numbers() {
	dir, mut cmd := setup('misc_context_line_numbers')
	dir.create('sherlock', sherlock)
	cmd.args(['-C', '1', '-n', 'world|attached', 'sherlock'])

	expected := '1:For the Doctor Watsons of this world, as opposed to the Sherlock
2-Holmeses, success in the province of detective work must always
--
5-but Doctor Watson has to have it taken out for him and dusted,
6:and exhibited clearly, with a label attached.
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_max_filesize_parse_error_length() {
	_, mut cmd := setup('misc_max_filesize_parse_error_length')
	cmd.args(['--max-filesize', '44444444444444444444'])
	cmd.assert_non_empty_stderr()
}

fn test_misc_max_filesize_parse_error_suffix() {
	_, mut cmd := setup('misc_max_filesize_parse_error_suffix')
	cmd.args(['--max-filesize', '45k'])
	cmd.assert_non_empty_stderr()
}

fn test_misc_max_filesize_parse_no_suffix() {
	dir, mut cmd := setup('misc_max_filesize_parse_no_suffix')
	dir.create_size('foo', 40)
	dir.create_size('bar', 60)
	cmd.args(['--max-filesize', '50', '--files'])

	eqnice('foo\n', cmd.stdout())
}

fn test_misc_max_filesize_parse_k_suffix() {
	dir, mut cmd := setup('misc_max_filesize_parse_k_suffix')
	dir.create_size('foo', 3048)
	dir.create_size('bar', 4100)
	cmd.args(['--max-filesize', '4K', '--files'])

	eqnice('foo\n', cmd.stdout())
}

fn test_misc_max_filesize_parse_m_suffix() {
	dir, mut cmd := setup('misc_max_filesize_parse_m_suffix')
	dir.create_size('foo', 1000000)
	dir.create_size('bar', 1400000)
	cmd.args(['--max-filesize', '1M', '--files'])

	eqnice('foo\n', cmd.stdout())
}

fn test_misc_max_filesize_suffix_overflow() {
	dir, mut cmd := setup('misc_max_filesize_suffix_overflow')
	dir.create_size('foo', 1000000)

	// 2^35 * 2^30 would otherwise overflow
	cmd.args(['--max-filesize', '34359738368G', '--files'])
	cmd.assert_non_empty_stderr()
}

fn test_misc_ignore_hidden() {
	dir, mut cmd := setup('misc_ignore_hidden')
	dir.create('.sherlock', sherlock)
	cmd.arg('Sherlock')
	cmd.assert_err()
}

fn test_misc_no_ignore_hidden() {
	dir, mut cmd := setup('misc_no_ignore_hidden')
	dir.create('.sherlock', sherlock)
	cmd.args(['--hidden', 'Sherlock'])

	expected := '.sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
.sherlock:be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_ignore_git() {
	dir, mut cmd := setup('misc_ignore_git')
	dir.create('sherlock', sherlock)
	dir.create_dir('.git')
	dir.create('.gitignore', 'sherlock\n')
	cmd.arg('Sherlock')

	cmd.assert_err()
}

fn test_misc_ignore_generic() {
	dir, mut cmd := setup('misc_ignore_generic')
	dir.create('sherlock', sherlock)
	dir.create('.ignore', 'sherlock\n')
	cmd.arg('Sherlock')

	cmd.assert_err()
}

fn test_misc_ignore_ripgrep() {
	dir, mut cmd := setup('misc_ignore_ripgrep')
	dir.create('sherlock', sherlock)
	dir.create('.rgignore', 'sherlock\n')
	cmd.arg('Sherlock')

	cmd.assert_err()
}

fn test_misc_no_ignore() {
	dir, mut cmd := setup('misc_no_ignore')
	dir.create('sherlock', sherlock)
	dir.create('.gitignore', 'sherlock\n')
	cmd.args(['--no-ignore', 'Sherlock'])

	expected := 'sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_ignore_git_parent() {
	dir, mut cmd := setup('misc_ignore_git_parent')
	dir.create_dir('.git')
	dir.create('.gitignore', 'sherlock\n')
	dir.create_dir('foo')
	dir.create('foo/sherlock', sherlock)
	cmd.arg('Sherlock')

	// Even though we search in foo/, which has no .gitignore, ripgrep will
	// traverse parent directories and respect the gitignore files found.
	cmd.current_dir('foo')
	cmd.assert_err()
}

fn test_misc_ignore_git_parent_stop() {
	dir, mut cmd := setup('misc_ignore_git_parent_stop')
	// This tests that searching parent directories for .gitignore files stops
	// after it sees a .git directory. To test this, we create this directory
	// hierarchy:
	//
	// .gitignore (contains `sherlock`)
	// foo/
	//   .git/
	//   bar/
	//      sherlock
	//
	// And we perform the search inside `foo/bar/`. ripgrep will stop looking
	// for .gitignore files after it sees `foo/.git/`, and therefore not
	// respect the top-level `.gitignore` containing `sherlock`.
	dir.create('.gitignore', 'sherlock\n')
	dir.create_dir('foo')
	dir.create_dir('foo/.git')
	dir.create_dir('foo/bar')
	dir.create('foo/bar/sherlock', sherlock)
	cmd.arg('Sherlock')
	cmd.current_dir('foo/bar')

	expected := 'sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

// Like ignore_git_parent_stop, but with a .git file instead of a .git
// directory.
fn test_misc_ignore_git_parent_stop_file() {
	dir, mut cmd := setup('misc_ignore_git_parent_stop_file')
	// This tests that searching parent directories for .gitignore files stops
	// after it sees a .git *file*. A .git file is used for submodules. To test
	// this, we create this directory hierarchy:
	//
	// .gitignore (contains `sherlock`)
	// foo/
	//   .git
	//   bar/
	//      sherlock
	//
	// And we perform the search inside `foo/bar/`. ripgrep will stop looking
	// for .gitignore files after it sees `foo/.git`, and therefore not
	// respect the top-level `.gitignore` containing `sherlock`.
	dir.create('.gitignore', 'sherlock\n')
	dir.create_dir('foo')
	dir.create('foo/.git', '')
	dir.create_dir('foo/bar')
	dir.create('foo/bar/sherlock', sherlock)
	cmd.arg('Sherlock')
	cmd.current_dir('foo/bar')

	expected := 'sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_ignore_ripgrep_parent_no_stop() {
	dir, mut cmd := setup('misc_ignore_ripgrep_parent_no_stop')
	// This is like the `ignore_git_parent_stop` test, except it checks that
	// ripgrep *doesn't* stop checking for .rgignore files.
	dir.create('.rgignore', 'sherlock\n')
	dir.create_dir('foo')
	dir.create_dir('foo/.git')
	dir.create_dir('foo/bar')
	dir.create('foo/bar/sherlock', sherlock)
	cmd.arg('Sherlock')
	cmd.current_dir('foo/bar')

	// The top-level .rgignore applies.
	cmd.assert_err()
}

fn test_misc_no_parent_ignore_git() {
	dir, mut cmd := setup('misc_no_parent_ignore_git')
	// Set up a directory hierarchy like this:
	//
	// .git/
	// .gitignore
	// foo/
	//   .gitignore
	//   sherlock
	//   watson
	//
	// Where `.gitignore` contains `sherlock` and `foo/.gitignore` contains
	// `watson`.
	//
	// Now *do the search* from the foo directory. By default, ripgrep will
	// search parent directories for .gitignore files. The --no-ignore-parent
	// flag should prevent that. At the same time, the `foo/.gitignore` file
	// will still be respected (since the search is happening in `foo/`).
	//
	// In other words, we should only see results from `sherlock`, not from
	// `watson`.
	dir.create_dir('.git')
	dir.create('.gitignore', 'sherlock\n')
	dir.create_dir('foo')
	dir.create('foo/.gitignore', 'watson\n')
	dir.create('foo/sherlock', sherlock)
	dir.create('foo/watson', sherlock)
	cmd.args(['--no-ignore-parent', 'Sherlock'])
	cmd.current_dir('foo')

	expected := 'sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_symlink_nofollow() {
	dir, mut cmd := setup('misc_symlink_nofollow')
	dir.create_dir('foo')
	dir.create_dir('foo/bar')
	dir.link_dir('foo/baz', 'foo/bar/baz')
	dir.create_dir('foo/baz')
	dir.create('foo/baz/sherlock', sherlock)
	cmd.arg('Sherlock')
	cmd.current_dir('foo/bar')

	cmd.assert_err()
}

fn test_misc_symlink_follow() {
	$if windows {
		return
	}
	dir, mut cmd := setup('misc_symlink_follow')
	dir.create_dir('foo')
	dir.create_dir('foo/bar')
	dir.create_dir('foo/baz')
	dir.create('foo/baz/sherlock', sherlock)
	dir.link_dir('foo/baz', 'foo/bar/baz')
	cmd.args(['-L', 'Sherlock'])
	cmd.current_dir('foo/bar')

	expected := 'baz/sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
baz/sherlock:be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_unrestricted1() {
	dir, mut cmd := setup('misc_unrestricted1')
	dir.create('sherlock', sherlock)
	dir.create('.gitignore', 'sherlock\n')
	cmd.args(['-u', 'Sherlock'])

	expected := 'sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_unrestricted2() {
	dir, mut cmd := setup('misc_unrestricted2')
	dir.create('.sherlock', sherlock)
	cmd.args(['-uu', 'Sherlock'])

	expected := '.sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
.sherlock:be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_unrestricted3() {
	dir, mut cmd := setup('misc_unrestricted3')
	dir.create('sherlock', sherlock)
	dir.create('hay', 'foo\x00bar\nfoo\x00baz\n')
	cmd.args(['-uuu', 'foo'])

	expected := 'hay: binary file matches (found "\\0" byte around offset 3)
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_vimgrep() {
	dir, mut cmd := setup('misc_vimgrep')
	dir.create('sherlock', sherlock)
	cmd.args(['--vimgrep', 'Sherlock|Watson'])

	expected := 'sherlock:1:16:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:1:57:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:3:49:be, to a very large extent, the result of luck. Sherlock Holmes
sherlock:5:12:but Doctor Watson has to have it taken out for him and dusted,
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_vimgrep_no_line() {
	dir, mut cmd := setup('misc_vimgrep_no_line')
	dir.create('sherlock', sherlock)
	cmd.args(['--vimgrep', '-N', 'Sherlock|Watson'])

	expected := 'sherlock:16:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:57:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:49:be, to a very large extent, the result of luck. Sherlock Holmes
sherlock:12:but Doctor Watson has to have it taken out for him and dusted,
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_vimgrep_no_line_no_column() {
	dir, mut cmd := setup('misc_vimgrep_no_line_no_column')
	dir.create('sherlock', sherlock)
	cmd.args(['--vimgrep', '-N', '--no-column', 'Sherlock|Watson'])

	expected := 'sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:be, to a very large extent, the result of luck. Sherlock Holmes
sherlock:but Doctor Watson has to have it taken out for him and dusted,
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_preprocessing() {
	if !cmd_exists('xzcat') {
		return
	}

	dir, mut cmd := setup('misc_preprocessing')
	dir.create_bytes('sherlock.xz', test_data_bytes('sherlock.xz'))
	cmd.args(['--pre', 'xzcat', 'Sherlock', 'sherlock.xz'])

	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_preprocessing_glob() {
	if !cmd_exists('xzcat') {
		return
	}

	dir, mut cmd := setup('misc_preprocessing_glob')
	dir.create('sherlock', sherlock)
	dir.create_bytes('sherlock.xz', test_data_bytes('sherlock.xz'))
	cmd.args(['--pre', 'xzcat', '--pre-glob', '*.xz', 'Sherlock'])

	expected := 'sherlock.xz:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock.xz:be, to a very large extent, the result of luck. Sherlock Holmes
sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(sort_lines(expected), sort_lines(cmd.stdout()))
}

fn test_misc_compressed_gzip() {
	if !cmd_exists('gzip') {
		return
	}

	dir, mut cmd := setup('misc_compressed_gzip')
	dir.create_bytes('sherlock.gz', test_data_bytes('sherlock.gz'))
	cmd.args(['-z', 'Sherlock', 'sherlock.gz'])

	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_compressed_bzip2() {
	if !cmd_exists('bzip2') {
		return
	}

	dir, mut cmd := setup('misc_compressed_bzip2')
	dir.create_bytes('sherlock.bz2', test_data_bytes('sherlock.bz2'))
	cmd.args(['-z', 'Sherlock', 'sherlock.bz2'])

	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_compressed_xz() {
	if !cmd_exists('xz') {
		return
	}

	dir, mut cmd := setup('misc_compressed_xz')
	dir.create_bytes('sherlock.xz', test_data_bytes('sherlock.xz'))
	cmd.args(['-z', 'Sherlock', 'sherlock.xz'])

	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_compressed_lz4() {
	if !cmd_exists('lz4') {
		return
	}

	dir, mut cmd := setup('misc_compressed_lz4')
	dir.create_bytes('sherlock.lz4', test_data_bytes('sherlock.lz4'))
	cmd.args(['-z', 'Sherlock', 'sherlock.lz4'])

	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_compressed_lzma() {
	if !cmd_exists('xz') {
		return
	}

	dir, mut cmd := setup('misc_compressed_lzma')
	dir.create_bytes('sherlock.lzma', test_data_bytes('sherlock.lzma'))
	cmd.args(['-z', 'Sherlock', 'sherlock.lzma'])

	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_compressed_brotli() {
	if !cmd_exists('brotli') {
		return
	}

	dir, mut cmd := setup('misc_compressed_brotli')
	dir.create_bytes('sherlock.br', test_data_bytes('sherlock.br'))
	cmd.args(['-z', 'Sherlock', 'sherlock.br'])

	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_compressed_zstd() {
	if !cmd_exists('zstd') {
		return
	}

	dir, mut cmd := setup('misc_compressed_zstd')
	dir.create_bytes('sherlock.zst', test_data_bytes('sherlock.zst'))
	cmd.args(['-z', 'Sherlock', 'sherlock.zst'])

	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_compressed_uncompress() {
	if !cmd_exists('uncompress') {
		return
	}

	dir, mut cmd := setup('misc_compressed_uncompress')
	dir.create_bytes('sherlock.Z', test_data_bytes('sherlock.Z'))
	cmd.args(['-z', 'Sherlock', 'sherlock.Z'])

	expected := '    For the Doctor Watsons of this world, as opposed to the Sherlock
be, to a very large extent, the result of luck. Sherlock Holmes
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_compressed_failing_gzip() {
	if !cmd_exists('gzip') {
		return
	}

	dir, mut cmd := setup('misc_compressed_failing_gzip')
	dir.create('sherlock.gz', sherlock)
	cmd.args(['-z', 'Sherlock', 'sherlock.gz'])

	cmd.assert_non_empty_stderr()
}

fn test_misc_binary_convert() {
	dir, mut cmd := setup('misc_binary_convert')
	dir.create('file', 'foo\x00bar\nfoo\x00baz\n')
	cmd.args(['--no-mmap', 'foo', 'file'])

	expected := 'binary file matches (found "\\0" byte around offset 3)
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_binary_convert_mmap() {
	dir, mut cmd := setup('misc_binary_convert_mmap')
	dir.create('file', 'foo\x00bar\nfoo\x00baz\n')
	cmd.args(['--mmap', 'foo', 'file'])

	expected := 'binary file matches (found "\\0" byte around offset 3)
'
	eqnice(expected, cmd.stdout())
}

fn test_misc_binary_quit() {
	dir, mut cmd := setup('misc_binary_quit')
	dir.create('file', 'foo\x00bar\nfoo\x00baz\n')
	cmd.args(['--no-mmap', 'foo', '-gfile'])
	cmd.assert_err()
}

fn test_misc_binary_quit_mmap() {
	dir, mut cmd := setup('misc_binary_quit_mmap')
	dir.create('file', 'foo\x00bar\nfoo\x00baz\n')
	cmd.args(['--mmap', 'foo', '-gfile'])
	cmd.assert_err()
}

// The following two tests show a discrepancy in search results between
// searching with memory mapped files and stream searching. Stream searching
// uses a heuristic (that GNU grep also uses) where NUL bytes are replaced with
// the EOL terminator, which tends to avoid allocating large amounts of memory
// for really long "lines." The memory map searcher has no need to worry about
// such things, and more than that, it would be pretty hard for it to match the
// semantics of streaming search in this case.
//
// Binary files with lots of NULs aren't really part of the use case of ripgrep
// (or any other grep-like tool for that matter), so we shouldn't feel too bad
// about it.
fn test_misc_binary_search_mmap() {
	dir, mut cmd := setup('misc_binary_search_mmap')
	dir.create('file', 'foo\x00bar\nfoo\x00baz\n')
	cmd.args(['-a', '--mmap', 'foo', 'file'])
	eqnice('foo\x00bar\nfoo\x00baz\n', cmd.stdout())
}

fn test_misc_binary_search_no_mmap() {
	dir, mut cmd := setup('misc_binary_search_no_mmap')
	dir.create('file', 'foo\x00bar\nfoo\x00baz\n')
	cmd.args(['-a', '--no-mmap', 'foo', 'file'])
	eqnice('foo\x00bar\nfoo\x00baz\n', cmd.stdout())
}

fn test_misc_files() {
	dir, mut cmd := setup('misc_files')
	dir.create('file', '')
	dir.create_dir('dir')
	dir.create('dir/file', '')
	cmd.arg('--files')

	eqnice(sort_lines('file\ndir/file\n'), sort_lines(cmd.stdout()))
}

fn test_misc_type_list() {
	_, mut cmd := setup('misc_type_list')
	cmd.arg('--type-list')
	// This can change over time, so just make sure we print something.
	assert cmd.stdout().len != 0
}

// The following series of tests seeks to test all permutations of ripgrep's
// sorted queries.
//
// They all rely on this setup function, which sets up this particular file
// structure with a particular creation order:
//  ├── a             # 1
//  ├── b             # 4
//  └── dir           # 2
//     ├── c          # 3
//     └── d          # 5
//
// This order is important when sorting them by system time-stamps.
fn sort_setup(dir Dir) {
	// As reported in https://github.com/BurntSushi/ripgrep/issues/3071
	// this test fails if sufficient delay is not given on Windows/Aarch64.
	delay := 1100 * time.millisecond
	dir.create('a', 'test')
	time.sleep(delay)
	dir.create_dir('dir')
	time.sleep(delay)
	dir.create('dir/c', 'test')
	time.sleep(delay)
	dir.create('b', 'test')
	time.sleep(delay)
	dir.create('dir/d', 'test')
}

fn test_misc_sort_files() {
	dir, mut cmd := setup('misc_sort_files')
	sort_setup(dir)
	expected := 'a:test\nb:test\ndir/c:test\ndir/d:test\n'
	cmd.args(['--sort', 'path', 'test'])
	eqnice(expected, cmd.stdout())
}

fn test_misc_sort_accessed() {
	dir, mut cmd := setup('misc_sort_accessed')
	sort_setup(dir)
	expected := 'a:test\ndir/c:test\nb:test\ndir/d:test\n'
	cmd.args(['--sort', 'accessed', 'test'])
	eqnice(expected, cmd.stdout())
}

fn test_misc_sortr_accessed() {
	dir, mut cmd := setup('misc_sortr_accessed')
	sort_setup(dir)
	expected := 'dir/d:test\nb:test\ndir/c:test\na:test\n'
	cmd.args(['--sortr', 'accessed', 'test'])
	eqnice(expected, cmd.stdout())
}
