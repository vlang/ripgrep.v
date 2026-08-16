module integration

// This tests that multiline matches that span multiple lines, but where
// multiple matches may begin and end on the same line work correctly.
fn test_multiline_overlap1() {
	dir, mut cmd := setup('multiline_overlap1')
	dir.create('test', 'xxx\nabc\ndefxxxabc\ndefxxx\nxxx')
	cmd.args(['-n', '-U', 'abc\ndef', 'test'])
	eqnice('2:abc\n3:defxxxabc\n4:defxxx\n', cmd.stdout())
}

// Like overlap1, but tests the case where one match ends at precisely the same
// location at which the next match begins.
fn test_multiline_overlap2() {
	dir, mut cmd := setup('multiline_overlap2')
	dir.create('test', 'xxx\nabc\ndefabc\ndefxxx\nxxx')
	cmd.args(['-n', '-U', 'abc\ndef', 'test'])
	eqnice('2:abc\n3:defabc\n4:defxxx\n', cmd.stdout())
}

// Tests that even in a multiline search, a '.' does not match a newline.
fn test_multiline_dot_no_newline() {
	dir, mut cmd := setup('multiline_dot_no_newline')
	dir.create('sherlock', sherlock)
	cmd.args(['-n', '-U', 'of this world.+detective work', 'sherlock'])
	cmd.assert_err()
}

// Tests that the --multiline-dotall flag causes '.' to match a newline.
fn test_multiline_dot_all() {
	dir, mut cmd := setup('multiline_dot_all')
	dir.create('sherlock', sherlock)
	cmd.args(['-n', '-U', '--multiline-dotall', 'of this world.+detective work', 'sherlock'])
	expected := '1:For the Doctor Watsons of this world, as opposed to the Sherlock\n2:Holmeses, success in the province of detective work must always\n'
	eqnice(expected, cmd.stdout())
}

// Tests that --only-matching works in multiline mode.
fn test_multiline_only_matching() {
	dir, mut cmd := setup('multiline_only_matching')
	dir.create('sherlock', sherlock)
	cmd.args(['-n', '-U', '--only-matching', r'Watson|Sherlock\p{Any}+?Holmes',
		'sherlock'])
	expected := '1:Watson\n1:Sherlock\n2:Holmes\n3:Sherlock Holmes\n5:Watson\n'
	eqnice(expected, cmd.stdout())
}

// Tests that --vimgrep works in multiline mode.
//
// In particular, we test that only the first line of each match is printed,
// even when a match spans multiple lines.
//
// See: https://github.com/BurntSushi/ripgrep/issues/1866
fn test_multiline_vimgrep() {
	dir, mut cmd := setup('multiline_vimgrep')
	dir.create('sherlock', sherlock)
	cmd.args(['-n', '-U', '--vimgrep', r'Watson|Sherlock\p{Any}+?Holmes', 'sherlock'])
	expected := 'sherlock:1:16:For the Doctor Watsons of this world, as opposed to the Sherlock\nsherlock:1:57:For the Doctor Watsons of this world, as opposed to the Sherlock\nsherlock:3:49:be, to a very large extent, the result of luck. Sherlock Holmes\nsherlock:5:12:but Doctor Watson has to have it taken out for him and dusted,\n'
	eqnice(expected, cmd.stdout())
}

// Tests that multiline search works when reading from stdin. This is an
// important test because multiline search must read the entire contents of
// what it is searching into memory before executing the search.
fn test_multiline_stdin() {
	_, mut cmd := setup('multiline_stdin')
	cmd.args(['-n', '-U', r'of this world\p{Any}+?detective work'])
	expected := '1:For the Doctor Watsons of this world, as opposed to the Sherlock\n2:Holmeses, success in the province of detective work must always\n'
	eqnice(expected, cmd.pipe(sherlock.bytes()))
}

// Test that multiline search and contextual matches work.
fn test_multiline_context() {
	dir, mut cmd := setup('multiline_context')
	dir.create('sherlock', sherlock)
	cmd.args(['-n', '-U', '-C1', r'detective work\p{Any}+?result of luck', 'sherlock'])
	expected := '1-For the Doctor Watsons of this world, as opposed to the Sherlock\n2:Holmeses, success in the province of detective work must always\n3:be, to a very large extent, the result of luck. Sherlock Holmes\n4-can extract a clew from a wisp of straw or a flake of cigar ash;\n'
	eqnice(expected, cmd.stdout())
}
