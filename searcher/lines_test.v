module searcher

import matcher

const sherlock_lines_test = 'For the Doctor Watsons of this world, as opposed to the Sherlock\nHolmeses, success in the province of detective work must always\nbe, to a very large extent, the result of luck. Sherlock Holmes\ncan extract a clew from a wisp of straw or a flake of cigar ash;\nbut Doctor Watson has to have it taken out for him and dusted,\nand exhibited clearly, with a label attached.'

fn line_ranges(text string) []matcher.Match {
	mut results := []matcher.Match{}
	mut it := LineStep.new(`\n`, 0, text.len)
	bytes := text.bytes()
	for {
		m := it.next_match(bytes) or { break }
		results << m
	}
	return results
}

fn line_texts(text string) []string {
	mut results := []string{}
	mut it := LineStep.new(`\n`, 0, text.len)
	bytes := text.bytes()
	for {
		m := it.next_match(bytes) or { break }
		results << text[m.start()..m.end()]
	}
	return results
}

fn loc(text string, start usize, end usize) matcher.Match {
	return locate(text.bytes(), `\n`, matcher.Match.new(start, end))
}

fn prev(text string, pos usize, count usize) usize {
	return preceding_by_pos(text.bytes(), pos, `\n`, count)
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
	assert line_texts('abc') == ['abc']

	assert line_texts('abc\n') == ['abc\n']
	assert line_texts('abc\nxyz') == ['abc\n', 'xyz']
	assert line_texts('abc\nxyz\n') == ['abc\n', 'xyz\n']

	assert line_texts('abc\n\n') == ['abc\n', '\n']
	assert line_texts('abc\n\n\n') == ['abc\n', '\n', '\n']
	assert line_texts('abc\n\nxyz') == ['abc\n', '\n', 'xyz']
	assert line_texts('abc\n\nxyz\n') == ['abc\n', '\n', 'xyz\n']
	assert line_texts('abc\nxyz\n\n') == ['abc\n', 'xyz\n', '\n']

	assert line_texts('\n') == ['\n']
	assert line_texts('') == []string{}
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
	assert loc('', 0, 0) == matcher.Match.new(0, 0)

	assert loc('\n', 0, 1) == matcher.Match.new(0, 1)
	assert loc('\n', 1, 1) == matcher.Match.new(1, 1)

	assert loc('\n\n', 0, 0) == matcher.Match.new(0, 1)
	assert loc('\n\n', 0, 1) == matcher.Match.new(0, 1)
	assert loc('\n\n', 1, 1) == matcher.Match.new(1, 2)
	assert loc('\n\n', 1, 2) == matcher.Match.new(1, 2)
	assert loc('\n\n', 2, 2) == matcher.Match.new(2, 2)

	assert loc('a\nb\nc', 0, 1) == matcher.Match.new(0, 2)
	assert loc('a\nb\nc', 1, 2) == matcher.Match.new(0, 2)
	assert loc('a\nb\nc', 2, 3) == matcher.Match.new(2, 4)
	assert loc('a\nb\nc', 3, 4) == matcher.Match.new(2, 4)
	assert loc('a\nb\nc', 4, 5) == matcher.Match.new(4, 5)
	assert loc('a\nb\nc', 5, 5) == matcher.Match.new(4, 5)
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
