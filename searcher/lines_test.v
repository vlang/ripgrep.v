module searcher

import matcher

const sherlock_lines_test = 'For the Doctor Watsons of this world, as opposed to the Sherlock\nHolmeses, success in the province of detective work must always\nbe, to a very large extent, the result of luck. Sherlock Holmes\ncan extract a clew from a wisp of straw or a flake of cigar ash;\nbut Doctor Watson has to have it taken out for him and dusted,\nand exhibited clearly, with a label attached.'

fn line_ranges[^a](text &^a string) []matcher.Match {
	mut results := []matcher.Match{}
	mut it := LineStep.new(`\n`, 0, uint(text.len))
	bytes := text.bytes()
	for {
		m := it.next_match(bytes) or { break }
		results << m
	}
	return results
}

fn line_texts[^a](text &^a string) []&^a string {
	mut results := []&^a string{}
	mut it := LineStep.new(`\n`, 0, uint(text.len))
	bytes := text.bytes()
	for {
		m := it.next_match(bytes) or { break }
		results << &(*text)[m.start()..m.end()]
	}
	return results
}

fn loc[^a](text &^a string, start uint, end uint) matcher.Match {
	return locate(text.bytes(), `\n`, matcher.Match.new(start, end))
}

fn prev[^a](text &^a string, pos uint, count uint) uint {
	return preceding_by_pos(text.bytes(), pos, `\n`, count)
}

// Compare the borrowed strings returned by the translated Rust test helper.
fn assert_line_texts[^a](text &^a string, expected []string) {
	lines := line_texts(text)
	assert lines.len == expected.len
	for i, line in lines {
		assert *line == expected[i]
	}
}

fn test_line_count() {
	assert count(''.bytes(), `\n`) == 0
	assert count('\n'.bytes(), `\n`) == 1
	assert count('\n\n'.bytes(), `\n`) == 2
	assert count('a\nb\nc'.bytes(), `\n`) == 2
}

fn test_line_locate() {
	t := sherlock_lines_test
	lines := line_ranges(t)

	assert loc(t, lines[0].start(), lines[0].end()) == matcher.Match.new(lines[0].start(),
		lines[0].end())
	assert loc(t, lines[0].start() + 1, lines[0].end()) == matcher.Match.new(lines[0].start(),
		lines[0].end())
	assert loc(t, lines[0].end() - 1, lines[0].end()) == matcher.Match.new(lines[0].start(),
		lines[0].end())
	assert loc(t, lines[0].end(), lines[0].end()) == matcher.Match.new(lines[1].start(),
		lines[1].end())

	assert loc(t, lines[5].start(), lines[5].end()) == matcher.Match.new(lines[5].start(),
		lines[5].end())
	assert loc(t, lines[5].start() + 1, lines[5].end()) == matcher.Match.new(lines[5].start(),
		lines[5].end())
	assert loc(t, lines[5].end() - 1, lines[5].end()) == matcher.Match.new(lines[5].start(),
		lines[5].end())
	assert loc(t, lines[5].end(), lines[5].end()) == matcher.Match.new(lines[5].start(),
		lines[5].end())
}

fn test_line_iter() {
	abc := 'abc'
	abc_lf := 'abc\n'
	abc_xyz := 'abc\nxyz'
	abc_xyz_lf := 'abc\nxyz\n'
	abc_empty := 'abc\n\n'
	abc_empty_empty := 'abc\n\n\n'
	abc_empty_xyz := 'abc\n\nxyz'
	abc_empty_xyz_lf := 'abc\n\nxyz\n'
	abc_xyz_empty := 'abc\nxyz\n\n'
	lf := '\n'
	empty := ''
	assert_line_texts(abc, ['abc'])

	assert_line_texts(abc_lf, ['abc\n'])
	assert_line_texts(abc_xyz, ['abc\n', 'xyz'])
	assert_line_texts(abc_xyz_lf, ['abc\n', 'xyz\n'])

	assert_line_texts(abc_empty, ['abc\n', '\n'])
	assert_line_texts(abc_empty_empty, ['abc\n', '\n', '\n'])
	assert_line_texts(abc_empty_xyz, ['abc\n', '\n', 'xyz'])
	assert_line_texts(abc_empty_xyz_lf, ['abc\n', '\n', 'xyz\n'])
	assert_line_texts(abc_xyz_empty, ['abc\n', 'xyz\n', '\n'])

	assert_line_texts(lf, ['\n'])
	assert_line_texts(empty, []string{})
}

fn test_line_iter_empty() {
	mut it := LineStep.new(`\n`, 0, 0)
	assert it.next('abc'.bytes()) == none
}

fn test_without_terminator_returns_borrowed_view() {
	bytes := 'abc\r\n'.bytes()
	line := without_terminator(bytes, matcher.LineTerminator.crlf())
	assert line.bytestr() == 'abc'
	assert line.data == bytes.data

	unterminated := without_terminator(bytes[..3], matcher.LineTerminator.crlf())
	assert unterminated.bytestr() == 'abc'
	assert unterminated.data == bytes.data
}

fn test_line_locate_weird() {
	empty := ''
	lf := '\n'
	lfs := '\n\n'
	abc := 'a\nb\nc'
	assert loc(empty, 0, 0) == matcher.Match.new(0, 0)

	assert loc(lf, 0, 1) == matcher.Match.new(0, 1)
	assert loc(lf, 1, 1) == matcher.Match.new(1, 1)

	assert loc(lfs, 0, 0) == matcher.Match.new(0, 1)
	assert loc(lfs, 0, 1) == matcher.Match.new(0, 1)
	assert loc(lfs, 1, 1) == matcher.Match.new(1, 2)
	assert loc(lfs, 1, 2) == matcher.Match.new(1, 2)
	assert loc(lfs, 2, 2) == matcher.Match.new(2, 2)

	assert loc(abc, 0, 1) == matcher.Match.new(0, 2)
	assert loc(abc, 1, 2) == matcher.Match.new(0, 2)
	assert loc(abc, 2, 3) == matcher.Match.new(2, 4)
	assert loc(abc, 3, 4) == matcher.Match.new(2, 4)
	assert loc(abc, 4, 5) == matcher.Match.new(4, 5)
	assert loc(abc, 5, 5) == matcher.Match.new(4, 5)
}

fn test_preceding_lines_doc() {
	// These are the examples mentions in the documentation of `preceding`.
	bytes := 'abc\nxyz\n'
	assert preceding_by_pos(bytes.bytes(), 7, `\n`, 0) == 4
	assert preceding_by_pos(bytes.bytes(), 8, `\n`, 0) == 4
	assert preceding_by_pos(bytes.bytes(), 7, `\n`, 1) == 0
	assert preceding_by_pos(bytes.bytes(), 8, `\n`, 1) == 0
}

fn test_preceding_lines_sherlock() {
	t := sherlock_lines_test
	lines := line_ranges(t)

	// The following tests check the count == 0 case, i.e., finding the
	// beginning of the line containing the given position.
	assert prev(t, 0, 0) == 0
	assert prev(t, 1, 0) == 0
	// The line terminator is addressed by `end-1` and terminates the line
	// it is part of.
	assert prev(t, lines[0].end() - 1, 0) == 0
	assert prev(t, lines[0].end(), 0) == lines[0].start()
	// The end position of line addresses the byte immediately following a
	// line terminator, which puts it on the following line.
	assert prev(t, lines[0].end() + 1, 0) == lines[1].start()

	// Now tests for count > 0.
	assert prev(t, 0, 1) == 0
	assert prev(t, 0, 2) == 0
	assert prev(t, 1, 1) == 0
	assert prev(t, 1, 2) == 0
	assert prev(t, lines[0].end() - 1, 1) == 0
	assert prev(t, lines[0].end() - 1, 2) == 0
	assert prev(t, lines[0].end(), 1) == 0
	assert prev(t, lines[0].end(), 2) == 0
	assert prev(t, lines[4].end() - 1, 1) == lines[3].start()
	assert prev(t, lines[4].end(), 1) == lines[3].start()
	assert prev(t, lines[4].end() + 1, 1) == lines[4].start()

	// The last line has no line terminator.
	assert prev(t, lines[5].end(), 0) == lines[5].start()
	assert prev(t, lines[5].end() - 1, 0) == lines[5].start()
	assert prev(t, lines[5].end(), 1) == lines[4].start()
	assert prev(t, lines[5].end(), 5) == lines[0].start()
}

fn test_preceding_lines_short() {
	t := 'a\nb\nc\nd\ne\nf\n'
	lines := line_ranges(t)
	assert t.len == 12
	assert prev(t, lines[5].end(), 0) == lines[5].start()
	assert prev(t, lines[5].end(), 1) == lines[4].start()
	assert prev(t, lines[5].end(), 2) == lines[3].start()
	assert prev(t, lines[5].end(), 3) == lines[2].start()
	assert prev(t, lines[5].end(), 4) == lines[1].start()
	assert prev(t, lines[5].end(), 5) == lines[0].start()
	assert prev(t, lines[5].end(), 6) == lines[0].start()

	assert prev(t, lines[5].end() - 1, 0) == lines[5].start()
	assert prev(t, lines[5].end() - 1, 1) == lines[4].start()
	assert prev(t, lines[5].end() - 1, 2) == lines[3].start()
	assert prev(t, lines[5].end() - 1, 3) == lines[2].start()
	assert prev(t, lines[5].end() - 1, 4) == lines[1].start()
	assert prev(t, lines[5].end() - 1, 5) == lines[0].start()
	assert prev(t, lines[5].end() - 1, 6) == lines[0].start()

	assert prev(t, lines[5].start(), 0) == lines[4].start()
	assert prev(t, lines[5].start(), 1) == lines[3].start()
	assert prev(t, lines[5].start(), 2) == lines[2].start()
	assert prev(t, lines[5].start(), 3) == lines[1].start()
	assert prev(t, lines[5].start(), 4) == lines[0].start()
	assert prev(t, lines[5].start(), 5) == lines[0].start()

	assert prev(t, lines[4].end() - 1, 1) == lines[3].start()
	assert prev(t, lines[4].start(), 1) == lines[2].start()

	assert prev(t, lines[3].end() - 1, 1) == lines[2].start()
	assert prev(t, lines[3].start(), 1) == lines[1].start()

	assert prev(t, lines[2].end() - 1, 1) == lines[1].start()
	assert prev(t, lines[2].start(), 1) == lines[0].start()

	assert prev(t, lines[1].end() - 1, 1) == lines[0].start()
	assert prev(t, lines[1].start(), 1) == lines[0].start()

	assert prev(t, lines[0].end() - 1, 1) == lines[0].start()
	assert prev(t, lines[0].start(), 1) == lines[0].start()
}

fn test_preceding_lines_empty1() {
	t := '\n\n\nd\ne\nf\n'
	lines := line_ranges(t)
	assert t.len == 9

	assert prev(t, lines[0].end(), 0) == lines[0].start()
	assert prev(t, lines[0].end(), 1) == lines[0].start()
	assert prev(t, lines[1].end(), 0) == lines[1].start()
	assert prev(t, lines[1].end(), 1) == lines[0].start()

	assert prev(t, lines[5].end(), 0) == lines[5].start()
	assert prev(t, lines[5].end(), 1) == lines[4].start()
	assert prev(t, lines[5].end(), 2) == lines[3].start()
	assert prev(t, lines[5].end(), 3) == lines[2].start()
	assert prev(t, lines[5].end(), 4) == lines[1].start()
	assert prev(t, lines[5].end(), 5) == lines[0].start()
	assert prev(t, lines[5].end(), 6) == lines[0].start()
}

fn test_preceding_lines_empty2() {
	t := 'a\n\n\nd\ne\nf\n'
	lines := line_ranges(t)
	assert t.len == 10

	assert prev(t, lines[0].end(), 0) == lines[0].start()
	assert prev(t, lines[0].end(), 1) == lines[0].start()
	assert prev(t, lines[1].end(), 0) == lines[1].start()
	assert prev(t, lines[1].end(), 1) == lines[0].start()

	assert prev(t, lines[5].end(), 0) == lines[5].start()
	assert prev(t, lines[5].end(), 1) == lines[4].start()
	assert prev(t, lines[5].end(), 2) == lines[3].start()
	assert prev(t, lines[5].end(), 3) == lines[2].start()
	assert prev(t, lines[5].end(), 4) == lines[1].start()
	assert prev(t, lines[5].end(), 5) == lines[0].start()
	assert prev(t, lines[5].end(), 6) == lines[0].start()
}
