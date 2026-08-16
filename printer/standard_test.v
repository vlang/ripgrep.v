module printer

import cli
import io
import matcher
import regex
import searcher
import time

const sherlock = 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
be, to a very large extent, the result of luck. Sherlock Holmes
can extract a clew from a wisp of straw or a flake of cigar ash;
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.'

const sherlock_crlf = 'For the Doctor Watsons of this world, as opposed to the Sherlock\r
Holmeses, success in the province of detective work must always\r
be, to a very large extent, the result of luck. Sherlock Holmes\r
can extract a clew from a wisp of straw or a flake of cigar ash;\r
but Doctor Watson has to have it taken out for him and dusted,\r
and exhibited clearly, with a label attached.'

fn no_color_buffer() cli.Buffer {
	return cli.BufferWriter.stdout(.never).buffer()
}

fn ansi_buffer() cli.Buffer {
	return cli.BufferWriter.stdout(.always).buffer()
}

struct StandardByteSliceReader {
mut:
	bytes []u8
	pos   int
}

fn StandardByteSliceReader.new(slice string) StandardByteSliceReader {
	return StandardByteSliceReader{
		bytes: slice.bytes()
	}
}

fn StandardByteSliceReader.new_bytes(slice []u8) StandardByteSliceReader {
	return StandardByteSliceReader{
		bytes: slice.clone()
	}
}

fn (mut rdr StandardByteSliceReader) read(mut buf []u8) !int {
	if rdr.pos >= rdr.bytes.len {
		return io.Eof{}
	}
	nread := copy(mut buf, rdr.bytes[rdr.pos..])
	rdr.pos += nread
	return nread
}

fn printer_contents(mut printer_ Standard[cli.Buffer]) string {
	return printer_.get_mut().as_slice().bytestr()
}

fn printer_contents_ansi(mut printer_ Standard[cli.Buffer]) string {
	return printer_.get_mut().as_slice().bytestr()
}

fn assert_eq_printed(expected string, got string) {
	if got != expected {
		panic('expected:\n${expected}\n\ngot:\n${got}')
	}
}

fn test_standard_reports_match() {
	matcher_ := regex.RegexMatcher.new('Sherlock') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	built.search_reader(matcher_, mut rdr, &sink)!
	assert sink.has_match()

	no_matcher := regex.RegexMatcher.new('zzzzz') or { panic(err) }
	mut no_printer := StandardBuilder.new().build(no_color_buffer())
	mut no_sink := no_printer.sink(PrinterMatcher.rust_regex(no_matcher))
	mut no_searcher := searcher.SearcherBuilder.new()
	no_searcher.line_number(false)
	mut no_built := no_searcher.build()
	mut no_rdr := StandardByteSliceReader.new(sherlock)
	no_built.search_reader(no_matcher, mut no_rdr, &no_sink)!
	assert !no_sink.has_match()
}

fn test_standard_reports_binary() {
	matcher_ := regex.RegexMatcher.new('Sherlock') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	built.search_reader(matcher_, mut rdr, &sink)!
	assert sink.binary_byte_offset() == none

	binary_matcher := regex.RegexMatcher.new('.+') or { panic(err) }
	mut binary_printer := StandardBuilder.new().build(no_color_buffer())
	mut binary_sink := binary_printer.sink(PrinterMatcher.rust_regex(binary_matcher))
	mut binary_searcher := searcher.SearcherBuilder.new()
	binary_searcher.line_number(false)
	binary_searcher.binary_detection(searcher.BinaryDetection.quit(u8(0)))
	mut binary_built := binary_searcher.build()
	mut binary_rdr := StandardByteSliceReader.new_bytes([u8(`a`), `b`, `c`, 0])
	binary_built.search_reader(binary_matcher, mut binary_rdr, &binary_sink)!
	binary_offset := binary_sink.binary_byte_offset() or { panic('missing binary byte offset') }
	assert binary_offset == u64(3)
}

fn test_standard_reports_stats() {
	matcher_ := regex.RegexMatcher.new('Sherlock|opposed') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.stats(true)
	mut printer_ := builder.build(no_color_buffer())
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	built.search_reader(matcher_, mut rdr, &sink)!
	stats := sink.stats() or { panic('missing stats') }
	buf := printer_contents(mut printer_)

	assert stats.elapsed() > time.Duration(0)
	assert stats.searches() == u64(1)
	assert stats.searches_with_match() == u64(1)
	assert stats.bytes_searched() == u64(sherlock.len)
	assert stats.bytes_printed() == u64(buf.len)
	assert stats.matched_lines() == u64(2)
	assert stats.matches() == u64(3)
}

fn test_standard_reports_stats_multiple() {
	matcher_ := regex.RegexMatcher.new('Sherlock|opposed') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.stats(true)
	mut printer_ := builder.build(no_color_buffer())
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	mut searcher1 := searcher.SearcherBuilder.new()
	searcher1.line_number(false)
	mut built1 := searcher1.build()
	mut rdr1 := StandardByteSliceReader.new(sherlock)
	built1.search_reader(matcher_, mut rdr1, &sink)!
	mut searcher2 := searcher.SearcherBuilder.new()
	searcher2.line_number(false)
	mut built2 := searcher2.build()
	mut rdr2 := StandardByteSliceReader.new_bytes('zzzzzzzzzz'.bytes())
	built2.search_reader(matcher_, mut rdr2, &sink)!
	mut searcher3 := searcher.SearcherBuilder.new()
	searcher3.line_number(false)
	mut built3 := searcher3.build()
	mut rdr3 := StandardByteSliceReader.new(sherlock)
	built3.search_reader(matcher_, mut rdr3, &sink)!
	stats := sink.stats() or { panic('missing stats') }
	buf := printer_contents(mut printer_)

	assert stats.elapsed() > time.Duration(0)
	assert stats.searches() == u64(3)
	assert stats.searches_with_match() == u64(2)
	assert stats.bytes_searched() == u64(10 + 2 * sherlock.len)
	assert stats.bytes_printed() == u64(buf.len)
	assert stats.matched_lines() == u64(4)
	assert stats.matches() == u64(6)
}

fn test_standard_context_break() {
	matcher_ := regex.RegexMatcher.new('Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.separator_context('--abc--'.bytes())
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	searcher_.before_context(1)
	searcher_.after_context(1)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
--abc--
can extract a clew from a wisp of straw or a flake of cigar ash;
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_context_break_multiple_no_heading() {
	matcher_ := regex.RegexMatcher.new('Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.separator_search('--xyz--'.bytes())
	builder.separator_context('--abc--'.bytes())
	mut printer_ := builder.build(no_color_buffer())

	mut searcher1 := searcher.SearcherBuilder.new()
	searcher1.line_number(false)
	searcher1.before_context(1)
	searcher1.after_context(1)
	mut built1 := searcher1.build()
	mut rdr1 := StandardByteSliceReader.new(sherlock)
	mut sink1 := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built1.search_reader(matcher_, mut rdr1, &sink1)!
	mut searcher2 := searcher.SearcherBuilder.new()
	searcher2.line_number(false)
	searcher2.before_context(1)
	searcher2.after_context(1)
	mut built2 := searcher2.build()
	mut rdr2 := StandardByteSliceReader.new(sherlock)
	mut sink2 := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built2.search_reader(matcher_, mut rdr2, &sink2)!

	got := printer_contents(mut printer_)
	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
--abc--
can extract a clew from a wisp of straw or a flake of cigar ash;
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.
--xyz--
For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
--abc--
can extract a clew from a wisp of straw or a flake of cigar ash;
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_context_break_multiple_heading() {
	matcher_ := regex.RegexMatcher.new('Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.heading(true)
	builder.separator_search('--xyz--'.bytes())
	builder.separator_context('--abc--'.bytes())
	mut printer_ := builder.build(no_color_buffer())

	mut searcher1 := searcher.SearcherBuilder.new()
	searcher1.line_number(false)
	searcher1.before_context(1)
	searcher1.after_context(1)
	mut built1 := searcher1.build()
	mut rdr1 := StandardByteSliceReader.new(sherlock)
	mut sink1 := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built1.search_reader(matcher_, mut rdr1, &sink1)!
	mut searcher2 := searcher.SearcherBuilder.new()
	searcher2.line_number(false)
	searcher2.before_context(1)
	searcher2.after_context(1)
	mut built2 := searcher2.build()
	mut rdr2 := StandardByteSliceReader.new(sherlock)
	mut sink2 := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built2.search_reader(matcher_, mut rdr2, &sink2)!

	got := printer_contents(mut printer_)
	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
--abc--
can extract a clew from a wisp of straw or a flake of cigar ash;
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.
--xyz--
For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
--abc--
can extract a clew from a wisp of straw or a flake of cigar ash;
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_path() {
	matcher_ := regex.RegexMatcher.new('Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.path(false)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	path := 'sherlock'
	mut sink := printer_.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:For the Doctor Watsons of this world, as opposed to the Sherlock
5:but Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_separator_field() {
	matcher_ := regex.RegexMatcher.new('Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.separator_field_match('!!'.bytes())
	builder.separator_field_context('^^'.bytes())
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	searcher_.before_context(1)
	searcher_.after_context(1)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	path := 'sherlock'
	mut sink := printer_.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'sherlock!!For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock^^Holmeses, success in the province of detective work must always
--
sherlock^^can extract a clew from a wisp of straw or a flake of cigar ash;
sherlock!!but Doctor Watson has to have it taken out for him and dusted,
sherlock^^and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_separator_path() {
	matcher_ := regex.RegexMatcher.new('Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.separator_path(u8(`Z`))
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	path := 'books/sherlock'
	mut sink := printer_.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'booksZsherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
booksZsherlock:but Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_path_terminator() {
	matcher_ := regex.RegexMatcher.new('Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.path_terminator(u8(`Z`))
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	path := 'books/sherlock'
	mut sink := printer_.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'books/sherlockZFor the Doctor Watsons of this world, as opposed to the Sherlock
books/sherlockZbut Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_heading() {
	matcher_ := regex.RegexMatcher.new('Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.heading(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	path := 'sherlock'
	mut sink := printer_.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'sherlock
For the Doctor Watsons of this world, as opposed to the Sherlock
but Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_no_heading() {
	matcher_ := regex.RegexMatcher.new('Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.heading(false)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	path := 'sherlock'
	mut sink := printer_.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:but Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_no_heading_multiple() {
	matcher_ := regex.RegexMatcher.new('Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.heading(false)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher1 := searcher.SearcherBuilder.new()
	searcher1.line_number(false)
	mut built1 := searcher1.build()
	mut rdr1 := StandardByteSliceReader.new(sherlock)
	path := 'sherlock'
	mut sink1 := printer_.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built1.search_reader(matcher_, mut rdr1, &sink1)!

	matcher2 := regex.RegexMatcher.new('Sherlock') or { panic(err) }
	mut searcher2 := searcher.SearcherBuilder.new()
	searcher2.line_number(false)
	mut built2 := searcher2.build()
	mut rdr2 := StandardByteSliceReader.new(sherlock)
	mut sink2 := printer_.sink_with_path(PrinterMatcher.rust_regex(matcher2), &path)
	built2.search_reader(matcher2, mut rdr2, &sink2)!

	got := printer_contents(mut printer_)
	expected := 'sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:but Doctor Watson has to have it taken out for him and dusted,
sherlock:For the Doctor Watsons of this world, as opposed to the Sherlock
sherlock:be, to a very large extent, the result of luck. Sherlock Holmes
'
	assert_eq_printed(expected, got)
}

fn test_standard_heading_multiple() {
	matcher_ := regex.RegexMatcher.new('Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.heading(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher1 := searcher.SearcherBuilder.new()
	searcher1.line_number(false)
	mut built1 := searcher1.build()
	mut rdr1 := StandardByteSliceReader.new(sherlock)
	path := 'sherlock'
	mut sink1 := printer_.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built1.search_reader(matcher_, mut rdr1, &sink1)!

	matcher2 := regex.RegexMatcher.new('Sherlock') or { panic(err) }
	mut searcher2 := searcher.SearcherBuilder.new()
	searcher2.line_number(false)
	mut built2 := searcher2.build()
	mut rdr2 := StandardByteSliceReader.new(sherlock)
	mut sink2 := printer_.sink_with_path(PrinterMatcher.rust_regex(matcher2), &path)
	built2.search_reader(matcher2, mut rdr2, &sink2)!

	got := printer_contents(mut printer_)
	expected := 'sherlock
For the Doctor Watsons of this world, as opposed to the Sherlock
but Doctor Watson has to have it taken out for him and dusted,
sherlock
For the Doctor Watsons of this world, as opposed to the Sherlock
be, to a very large extent, the result of luck. Sherlock Holmes
'
	assert_eq_printed(expected, got)
}

fn test_standard_trim_ascii() {
	matcher_ := regex.RegexMatcher.new('Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.trim_ascii(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new('   Watson')
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'Watson
'
	assert_eq_printed(expected, got)
}

fn test_standard_trim_ascii_multi_line() {
	matcher_ := regex.RegexMatcher.new('(?s:.{0})Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.trim_ascii(true)
	builder.stats(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	searcher_.multi_line(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new('   Watson')
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'Watson
'
	assert_eq_printed(expected, got)
}

fn test_standard_trim_ascii_with_line_term() {
	matcher_ := regex.RegexMatcher.new('Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.trim_ascii(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	searcher_.before_context(1)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new('\n   Watson')
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1-
2:Watson
'
	assert_eq_printed(expected, got)
}

fn test_standard_line_number() {
	matcher_ := regex.RegexMatcher.new('Watson') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:For the Doctor Watsons of this world, as opposed to the Sherlock
5:but Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_line_number_multi_line() {
	matcher_ := regex.RegexMatcher.new('(?s)Watson.+Watson') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	searcher_.multi_line(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:For the Doctor Watsons of this world, as opposed to the Sherlock
2:Holmeses, success in the province of detective work must always
3:be, to a very large extent, the result of luck. Sherlock Holmes
4:can extract a clew from a wisp of straw or a flake of cigar ash;
5:but Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_column_number() {
	matcher_ := regex.RegexMatcher.new('Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '16:For the Doctor Watsons of this world, as opposed to the Sherlock
12:but Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_column_number_multi_line() {
	matcher_ := regex.RegexMatcher.new('(?s)Watson.+Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	searcher_.multi_line(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '16:For the Doctor Watsons of this world, as opposed to the Sherlock
16:Holmeses, success in the province of detective work must always
16:be, to a very large extent, the result of luck. Sherlock Holmes
16:can extract a clew from a wisp of straw or a flake of cigar ash;
16:but Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_byte_offset() {
	matcher_ := regex.RegexMatcher.new('Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.byte_offset(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '0:For the Doctor Watsons of this world, as opposed to the Sherlock
258:but Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_byte_offset_multi_line() {
	matcher_ := regex.RegexMatcher.new('(?s)Watson.+Watson') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.byte_offset(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	searcher_.multi_line(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '0:For the Doctor Watsons of this world, as opposed to the Sherlock
65:Holmeses, success in the province of detective work must always
129:be, to a very large extent, the result of luck. Sherlock Holmes
193:can extract a clew from a wisp of straw or a flake of cigar ash;
258:but Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_max_columns() {
	matcher_ := regex.RegexMatcher.new('ash|dusted') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.max_columns(u64(63))
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '[Omitted long matching line]
but Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_max_columns_preview() {
	matcher_ := regex.RegexMatcher.new('exhibited|dusted') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.max_columns(u64(46))
	builder.max_columns_preview(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'but Doctor Watson has to have it taken out for [... omitted end of long line]
and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_max_columns_preview_uses_grapheme_clusters() {
	matcher_ := regex.RegexMatcher.new('x') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.stats(true)
	builder.max_columns(u64(1))
	builder.max_columns_preview(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new('e\u0301x\n')
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'e\u0301 [... 1 more match]\n'
	assert_eq_printed(expected, got)
}

fn test_standard_max_columns_preview_preserves_invalid_utf8_widths() {
	bytes := [u8(0xe2), 0x98, `x`, `\n`]
	matcher_ := regex.RegexMatcher.new('x') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.stats(true)
	builder.max_columns(u64(1))
	builder.max_columns_preview(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new_bytes(bytes)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_).bytes()
	mut expected := [u8(0xe2), 0x98]
	expected << ' [... 1 more match]\n'.bytes()
	assert got == expected
}

fn test_standard_max_columns_with_count() {
	matcher_ := regex.RegexMatcher.new('cigar|ash|dusted') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.stats(true)
	builder.max_columns(u64(63))
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '[Omitted long line with 2 matches]
but Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_max_columns_with_count_preview_no_match() {
	matcher_ := regex.RegexMatcher.new('exhibited|has to have it') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.stats(true)
	builder.max_columns(u64(46))
	builder.max_columns_preview(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'but Doctor Watson has to have it taken out for [... 0 more matches]
and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_max_columns_with_count_preview_one_match() {
	matcher_ := regex.RegexMatcher.new('exhibited|dusted') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.stats(true)
	builder.max_columns(u64(46))
	builder.max_columns_preview(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'but Doctor Watson has to have it taken out for [... 1 more match]
and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_max_columns_with_count_preview_two_matches() {
	matcher_ := regex.RegexMatcher.new('exhibited|dusted|has to have it') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.stats(true)
	builder.max_columns(u64(46))
	builder.max_columns_preview(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'but Doctor Watson has to have it taken out for [... 1 more match]
and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_max_columns_multi_line() {
	matcher_ := regex.RegexMatcher.new('(?s)ash.+dusted') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.max_columns(u64(63))
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	searcher_.multi_line(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '[Omitted long matching line]
but Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_max_columns_multi_line_preview() {
	matcher_ := regex.RegexMatcher.new('(?s)clew|cigar ash.+have it|exhibited') or {
		panic(err)
	}
	mut builder := StandardBuilder.new()
	builder.stats(true)
	builder.max_columns(u64(46))
	builder.max_columns_preview(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	searcher_.multi_line(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'can extract a clew from a wisp of straw or a f [... 1 more match]
but Doctor Watson has to have it taken out for [... 0 more matches]
and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_max_matches() {
	matcher_ := regex.RegexMatcher.new('Sherlock') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	searcher_.max_matches(u64(1))
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
'
	assert_eq_printed(expected, got)
}

fn test_standard_max_matches_context() {
	// after context: 1
	matcher_ := regex.RegexMatcher.new('Doctor Watsons') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut searcher1 := searcher.SearcherBuilder.new()
	searcher1.max_matches(u64(1))
	searcher1.line_number(false)
	searcher1.after_context(1)
	mut built1 := searcher1.build()
	mut rdr1 := StandardByteSliceReader.new(sherlock)
	mut sink1 := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built1.search_reader(matcher_, mut rdr1, &sink1)!

	got1 := printer_contents(mut printer_)
	expected1 := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
'
	assert_eq_printed(expected1, got1)

	// after context: 4
	mut printer2 := StandardBuilder.new().build(no_color_buffer())
	mut searcher2 := searcher.SearcherBuilder.new()
	searcher2.max_matches(u64(1))
	searcher2.line_number(false)
	searcher2.after_context(4)
	mut built2 := searcher2.build()
	mut rdr2 := StandardByteSliceReader.new(sherlock)
	mut sink2 := printer2.sink(PrinterMatcher.rust_regex(matcher_))
	built2.search_reader(matcher_, mut rdr2, &sink2)!

	got2 := printer_contents(mut printer2)
	expected2 := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
be, to a very large extent, the result of luck. Sherlock Holmes
can extract a clew from a wisp of straw or a flake of cigar ash;
but Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected2, got2)

	// after context: 1, max matches: 2
	matcher2 := regex.RegexMatcher.new('Doctor Watsons|but Doctor') or { panic(err) }
	mut printer3 := StandardBuilder.new().build(no_color_buffer())
	mut searcher3 := searcher.SearcherBuilder.new()
	searcher3.max_matches(u64(2))
	searcher3.line_number(false)
	searcher3.after_context(1)
	mut built3 := searcher3.build()
	mut rdr3 := StandardByteSliceReader.new(sherlock)
	mut sink3 := printer3.sink(PrinterMatcher.rust_regex(matcher2))
	built3.search_reader(matcher2, mut rdr3, &sink3)!

	got3 := printer_contents(mut printer3)
	expected3 := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
--
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected3, got3)

	// after context: 4, max matches: 2
	mut printer4 := StandardBuilder.new().build(no_color_buffer())
	mut searcher4 := searcher.SearcherBuilder.new()
	searcher4.max_matches(u64(2))
	searcher4.line_number(false)
	searcher4.after_context(4)
	mut built4 := searcher4.build()
	mut rdr4 := StandardByteSliceReader.new(sherlock)
	mut sink4 := printer4.sink(PrinterMatcher.rust_regex(matcher2))
	built4.search_reader(matcher2, mut rdr4, &sink4)!

	got4 := printer_contents(mut printer4)
	expected4 := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
be, to a very large extent, the result of luck. Sherlock Holmes
can extract a clew from a wisp of straw or a flake of cigar ash;
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected4, got4)
}

fn test_standard_max_matches_context_invert() {
	// after context: 1
	matcher_ := regex.RegexMatcher.new('success|extent|clew|dusted|exhibited') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut searcher1 := searcher.SearcherBuilder.new()
	searcher1.invert_match(true)
	searcher1.max_matches(u64(1))
	searcher1.line_number(false)
	searcher1.after_context(1)
	mut built1 := searcher1.build()
	mut rdr1 := StandardByteSliceReader.new(sherlock)
	mut sink1 := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built1.search_reader(matcher_, mut rdr1, &sink1)!

	got1 := printer_contents(mut printer_)
	expected1 := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
'
	assert_eq_printed(expected1, got1)

	// after context: 4
	mut printer2 := StandardBuilder.new().build(no_color_buffer())
	mut searcher2 := searcher.SearcherBuilder.new()
	searcher2.invert_match(true)
	searcher2.max_matches(u64(1))
	searcher2.line_number(false)
	searcher2.after_context(4)
	mut built2 := searcher2.build()
	mut rdr2 := StandardByteSliceReader.new(sherlock)
	mut sink2 := printer2.sink(PrinterMatcher.rust_regex(matcher_))
	built2.search_reader(matcher_, mut rdr2, &sink2)!

	got2 := printer_contents(mut printer2)
	expected2 := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
be, to a very large extent, the result of luck. Sherlock Holmes
can extract a clew from a wisp of straw or a flake of cigar ash;
but Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected2, got2)

	// after context: 1, max matches: 2
	matcher2 := regex.RegexMatcher.new('success|extent|clew|exhibited') or { panic(err) }
	mut printer3 := StandardBuilder.new().build(no_color_buffer())
	mut searcher3 := searcher.SearcherBuilder.new()
	searcher3.invert_match(true)
	searcher3.max_matches(u64(2))
	searcher3.line_number(false)
	searcher3.after_context(1)
	mut built3 := searcher3.build()
	mut rdr3 := StandardByteSliceReader.new(sherlock)
	mut sink3 := printer3.sink(PrinterMatcher.rust_regex(matcher2))
	built3.search_reader(matcher2, mut rdr3, &sink3)!

	got3 := printer_contents(mut printer3)
	expected3 := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
--
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected3, got3)

	// after context: 4, max matches: 2
	mut printer4 := StandardBuilder.new().build(no_color_buffer())
	mut searcher4 := searcher.SearcherBuilder.new()
	searcher4.invert_match(true)
	searcher4.max_matches(u64(2))
	searcher4.line_number(false)
	searcher4.after_context(4)
	mut built4 := searcher4.build()
	mut rdr4 := StandardByteSliceReader.new(sherlock)
	mut sink4 := printer4.sink(PrinterMatcher.rust_regex(matcher2))
	built4.search_reader(matcher2, mut rdr4, &sink4)!

	got4 := printer_contents(mut printer4)
	expected4 := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
be, to a very large extent, the result of luck. Sherlock Holmes
can extract a clew from a wisp of straw or a flake of cigar ash;
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected4, got4)
}

fn test_standard_max_matches_multi_line1() {
	matcher_ := regex.RegexMatcher.new('(?s:.{0})Sherlock') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	searcher_.multi_line(true)
	searcher_.max_matches(u64(1))
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
'
	assert_eq_printed(expected, got)
}

fn test_standard_max_matches_multi_line2() {
	matcher_ := regex.RegexMatcher.new(r'(?s)Watson.+?(Holmeses|clearly)') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	searcher_.multi_line(true)
	searcher_.max_matches(u64(1))
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
'
	assert_eq_printed(expected, got)
}

fn test_standard_max_matches_multi_line3() {
	matcher_ := regex.RegexMatcher.new(r'line 2\nline 3') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	searcher_.multi_line(true)
	searcher_.max_matches(u64(1))
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new('line 2\nline 3 x\nline 2\nline 3\n')
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'line 2
line 3 x
'
	assert_eq_printed(expected, got)
}

fn test_standard_max_matches_multi_line4() {
	matcher_ := regex.RegexMatcher.new(r'line 2\nline 3|x\nline 2\n') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	searcher_.multi_line(true)
	searcher_.max_matches(u64(1))
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new('line 2\nline 3 x\nline 2\nline 3 x\n')
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'line 2
line 3 x
'
	assert_eq_printed(expected, got)
}

fn test_standard_only_matching() {
	matcher_ := regex.RegexMatcher.new('Doctor Watsons|Sherlock') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.only_matching(true)
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:9:Doctor Watsons
1:57:Sherlock
3:49:Sherlock
'
	assert_eq_printed(expected, got)
}

fn test_standard_only_matching_multi_line1() {
	matcher_ := regex.RegexMatcher.new(r'(?s:.{0})(Doctor Watsons|Sherlock)') or {
		panic(err)
	}
	mut builder := StandardBuilder.new()
	builder.only_matching(true)
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.multi_line(true)
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:9:Doctor Watsons
1:57:Sherlock
3:49:Sherlock
'
	assert_eq_printed(expected, got)
}

fn test_standard_only_matching_multi_line2() {
	matcher_ := regex.RegexMatcher.new(r'(?s)Watson.+?(Holmeses|clearly)') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.only_matching(true)
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.multi_line(true)
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:16:Watsons of this world, as opposed to the Sherlock
2:16:Holmeses
5:12:Watson has to have it taken out for him and dusted,
6:12:and exhibited clearly
'
	assert_eq_printed(expected, got)
}

fn test_standard_only_matching_max_columns() {
	matcher_ := regex.RegexMatcher.new('Doctor Watsons|Sherlock') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.only_matching(true)
	builder.max_columns(u64(10))
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:9:[Omitted long matching line]
1:57:Sherlock
3:49:Sherlock
'
	assert_eq_printed(expected, got)
}

fn test_standard_only_matching_max_columns_preview() {
	matcher_ := regex.RegexMatcher.new('Doctor Watsons|Sherlock') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.only_matching(true)
	builder.max_columns(u64(10))
	builder.max_columns_preview(true)
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:9:Doctor Wat [... 0 more matches]
1:57:Sherlock
3:49:Sherlock
'
	assert_eq_printed(expected, got)
}

fn test_standard_only_matching_max_columns_multi_line1() {
	// The `(?s:.{0})` trick fools the matcher into thinking that it
	// can match across multiple lines without actually doing so. This is
	// so we can test multi-line handling in the case of a match on only
	// one line.
	matcher_ := regex.RegexMatcher.new(r'(?s:.{0})(Doctor Watsons|Sherlock)') or {
		panic(err)
	}
	mut builder := StandardBuilder.new()
	builder.only_matching(true)
	builder.max_columns(u64(10))
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.multi_line(true)
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:9:[Omitted long matching line]
1:57:Sherlock
3:49:Sherlock
'
	assert_eq_printed(expected, got)
}

fn test_standard_only_matching_max_columns_preview_multi_line1() {
	// The `(?s:.{0})` trick fools the matcher into thinking that it
	// can match across multiple lines without actually doing so. This is
	// so we can test multi-line handling in the case of a match on only
	// one line.
	matcher_ := regex.RegexMatcher.new(r'(?s:.{0})(Doctor Watsons|Sherlock)') or {
		panic(err)
	}
	mut builder := StandardBuilder.new()
	builder.only_matching(true)
	builder.max_columns(u64(10))
	builder.max_columns_preview(true)
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.multi_line(true)
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:9:Doctor Wat [... 0 more matches]
1:57:Sherlock
3:49:Sherlock
'
	assert_eq_printed(expected, got)
}

fn test_standard_only_matching_max_columns_multi_line2() {
	matcher_ := regex.RegexMatcher.new(r'(?s)Watson.+?(Holmeses|clearly)') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.only_matching(true)
	builder.max_columns(u64(50))
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.multi_line(true)
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:16:Watsons of this world, as opposed to the Sherlock
2:16:Holmeses
5:12:[Omitted long matching line]
6:12:and exhibited clearly
'
	assert_eq_printed(expected, got)
}

fn test_standard_only_matching_max_columns_preview_multi_line2() {
	matcher_ := regex.RegexMatcher.new(r'(?s)Watson.+?(Holmeses|clearly)') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.only_matching(true)
	builder.max_columns(u64(50))
	builder.max_columns_preview(true)
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.multi_line(true)
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:16:Watsons of this world, as opposed to the Sherlock
2:16:Holmeses
5:12:Watson has to have it taken out for him and dusted [... 0 more matches]
6:12:and exhibited clearly
'
	assert_eq_printed(expected, got)
}

fn test_standard_per_match() {
	matcher_ := regex.RegexMatcher.new('Doctor Watsons|Sherlock') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.per_match(true)
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:9:For the Doctor Watsons of this world, as opposed to the Sherlock
1:57:For the Doctor Watsons of this world, as opposed to the Sherlock
3:49:be, to a very large extent, the result of luck. Sherlock Holmes
'
	assert_eq_printed(expected, got)
}

fn test_standard_per_match_multi_line1() {
	matcher_ := regex.RegexMatcher.new(r'(?s:.{0})(Doctor Watsons|Sherlock)') or {
		panic(err)
	}
	mut builder := StandardBuilder.new()
	builder.per_match(true)
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.multi_line(true)
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:9:For the Doctor Watsons of this world, as opposed to the Sherlock
1:57:For the Doctor Watsons of this world, as opposed to the Sherlock
3:49:be, to a very large extent, the result of luck. Sherlock Holmes
'
	assert_eq_printed(expected, got)
}

fn test_standard_per_match_multi_line2() {
	matcher_ := regex.RegexMatcher.new(r'(?s)Watson.+?(Holmeses|clearly)') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.per_match(true)
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.multi_line(true)
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:16:For the Doctor Watsons of this world, as opposed to the Sherlock
2:1:Holmeses, success in the province of detective work must always
5:12:but Doctor Watson has to have it taken out for him and dusted,
6:1:and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_per_match_multi_line3() {
	matcher_ := regex.RegexMatcher.new(r'(?s)Watson.+?Holmeses|always.+?be') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.per_match(true)
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.multi_line(true)
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:16:For the Doctor Watsons of this world, as opposed to the Sherlock
2:1:Holmeses, success in the province of detective work must always
2:58:Holmeses, success in the province of detective work must always
3:1:be, to a very large extent, the result of luck. Sherlock Holmes
'
	assert_eq_printed(expected, got)
}

fn test_standard_per_match_multi_line1_only_first_line() {
	matcher_ := regex.RegexMatcher.new(r'(?s:.{0})(Doctor Watsons|Sherlock)') or {
		panic(err)
	}
	mut builder := StandardBuilder.new()
	builder.per_match(true)
	builder.per_match_one_line(true)
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.multi_line(true)
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:9:For the Doctor Watsons of this world, as opposed to the Sherlock
1:57:For the Doctor Watsons of this world, as opposed to the Sherlock
3:49:be, to a very large extent, the result of luck. Sherlock Holmes
'
	assert_eq_printed(expected, got)
}

fn test_standard_per_match_multi_line2_only_first_line() {
	matcher_ := regex.RegexMatcher.new(r'(?s)Watson.+?(Holmeses|clearly)') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.per_match(true)
	builder.per_match_one_line(true)
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.multi_line(true)
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:16:For the Doctor Watsons of this world, as opposed to the Sherlock
5:12:but Doctor Watson has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_per_match_multi_line3_only_first_line() {
	matcher_ := regex.RegexMatcher.new(r'(?s)Watson.+?Holmeses|always.+?be') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.per_match(true)
	builder.per_match_one_line(true)
	builder.column(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.multi_line(true)
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:16:For the Doctor Watsons of this world, as opposed to the Sherlock
2:58:Holmeses, success in the province of detective work must always
'
	assert_eq_printed(expected, got)
}

fn test_standard_replacement_passthru() {
	matcher_ := regex.RegexMatcher.new(r'Sherlock|Doctor (\w+)') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.replacement(r'doctah $1 MD'.bytes())
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	searcher_.passthru(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:For the doctah Watsons MD of this world, as opposed to the doctah  MD
2-Holmeses, success in the province of detective work must always
3:be, to a very large extent, the result of luck. doctah  MD Holmes
4-can extract a clew from a wisp of straw or a flake of cigar ash;
5:but doctah Watson MD has to have it taken out for him and dusted,
6-and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_replacement() {
	matcher_ := regex.RegexMatcher.new(r'Sherlock|Doctor (\w+)') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.replacement(r'doctah $1 MD'.bytes())
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:For the doctah Watsons MD of this world, as opposed to the doctah  MD
3:be, to a very large extent, the result of luck. doctah  MD Holmes
5:but doctah Watson MD has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

// This is a somewhat weird test that checks the behavior of attempting
// to replace a line terminator with something else.
//
// See: https://github.com/BurntSushi/ripgrep/issues/1311
fn test_standard_replacement_multi_line() {
	matcher_ := regex.RegexMatcher.new(r'\n') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.replacement('?'.bytes())
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	searcher_.multi_line(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new('hello\nworld\n')
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:hello?world?\n'
	assert_eq_printed(expected, got)
}

fn test_standard_replacement_multi_line_diff_line_term() {
	mut matcher_builder := regex.RegexMatcherBuilder.new()
	matcher_builder.line_terminator(u8(0))
	matcher_ := matcher_builder.build(r'\n') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.replacement('?'.bytes())
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_terminator(matcher.LineTerminator.byte(u8(0)))
	searcher_.line_number(true)
	searcher_.multi_line(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new('hello\nworld\n')
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:hello?world?\x00'
	assert_eq_printed(expected, got)
}

fn test_standard_replacement_multi_line_combine_lines() {
	matcher_ := regex.RegexMatcher.new(r'\n(.)?') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.replacement(r'?$1'.bytes())
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	searcher_.multi_line(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new('hello\nworld\n')
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:hello?world?\n'
	assert_eq_printed(expected, got)
}

fn test_standard_replacement_max_columns() {
	matcher_ := regex.RegexMatcher.new(r'Sherlock|Doctor (\w+)') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.max_columns(u64(67))
	builder.replacement(r'doctah $1 MD'.bytes())
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:[Omitted long line with 2 matches]
3:be, to a very large extent, the result of luck. doctah  MD Holmes
5:but doctah Watson MD has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_replacement_max_columns_preview1() {
	matcher_ := regex.RegexMatcher.new(r'Sherlock|Doctor (\w+)') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.max_columns(u64(67))
	builder.max_columns_preview(true)
	builder.replacement(r'doctah $1 MD'.bytes())
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:For the doctah Watsons MD of this world, as opposed to the doctah   [... 0 more matches]
3:be, to a very large extent, the result of luck. doctah  MD Holmes
5:but doctah Watson MD has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_replacement_max_columns_preview2() {
	matcher_ := regex.RegexMatcher.new('exhibited|dusted|has to have it') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.max_columns(u64(43))
	builder.max_columns_preview(true)
	builder.replacement('xxx'.bytes())
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(false)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := 'but Doctor Watson xxx taken out for him and [... 1 more match]
and xxx clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_replacement_only_matching() {
	matcher_ := regex.RegexMatcher.new(r'Sherlock|Doctor (\w+)') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.only_matching(true)
	builder.replacement(r'doctah $1 MD'.bytes())
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:doctah Watsons MD
1:doctah  MD
3:doctah  MD
5:doctah Watson MD
'
	assert_eq_printed(expected, got)
}

fn test_standard_replacement_per_match() {
	matcher_ := regex.RegexMatcher.new(r'Sherlock|Doctor (\w+)') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.per_match(true)
	builder.replacement(r'doctah $1 MD'.bytes())
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1:For the doctah Watsons MD of this world, as opposed to the doctah  MD
1:For the doctah Watsons MD of this world, as opposed to the doctah  MD
3:be, to a very large extent, the result of luck. doctah  MD Holmes
5:but doctah Watson MD has to have it taken out for him and dusted,
'
	assert_eq_printed(expected, got)
}

fn test_standard_invert() {
	matcher_ := regex.RegexMatcher.new(r'Sherlock') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	searcher_.invert_match(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '2:Holmeses, success in the province of detective work must always
4:can extract a clew from a wisp of straw or a flake of cigar ash;
5:but Doctor Watson has to have it taken out for him and dusted,
6:and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_invert_multi_line() {
	matcher_ := regex.RegexMatcher.new(r'(?s:.{0})Sherlock') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.multi_line(true)
	searcher_.line_number(true)
	searcher_.invert_match(true)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '2:Holmeses, success in the province of detective work must always
4:can extract a clew from a wisp of straw or a flake of cigar ash;
5:but Doctor Watson has to have it taken out for him and dusted,
6:and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_invert_context() {
	matcher_ := regex.RegexMatcher.new(r'Sherlock') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	searcher_.invert_match(true)
	searcher_.before_context(1)
	searcher_.after_context(1)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1-For the Doctor Watsons of this world, as opposed to the Sherlock
2:Holmeses, success in the province of detective work must always
3-be, to a very large extent, the result of luck. Sherlock Holmes
4:can extract a clew from a wisp of straw or a flake of cigar ash;
5:but Doctor Watson has to have it taken out for him and dusted,
6:and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_invert_context_multi_line() {
	matcher_ := regex.RegexMatcher.new(r'(?s:.{0})Sherlock') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.multi_line(true)
	searcher_.line_number(true)
	searcher_.invert_match(true)
	searcher_.before_context(1)
	searcher_.after_context(1)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1-For the Doctor Watsons of this world, as opposed to the Sherlock
2:Holmeses, success in the province of detective work must always
3-be, to a very large extent, the result of luck. Sherlock Holmes
4:can extract a clew from a wisp of straw or a flake of cigar ash;
5:but Doctor Watson has to have it taken out for him and dusted,
6:and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_invert_context_only_matching() {
	matcher_ := regex.RegexMatcher.new(r'Sherlock') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.only_matching(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_number(true)
	searcher_.invert_match(true)
	searcher_.before_context(1)
	searcher_.after_context(1)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1-Sherlock
2:Holmeses, success in the province of detective work must always
3-Sherlock
4:can extract a clew from a wisp of straw or a flake of cigar ash;
5:but Doctor Watson has to have it taken out for him and dusted,
6:and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_invert_context_only_matching_multi_line() {
	matcher_ := regex.RegexMatcher.new(r'(?s:.{0})Sherlock') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.only_matching(true)
	mut printer_ := builder.build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.multi_line(true)
	searcher_.line_number(true)
	searcher_.invert_match(true)
	searcher_.before_context(1)
	searcher_.after_context(1)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(sherlock)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '1-Sherlock
2:Holmeses, success in the province of detective work must always
3-Sherlock
4:can extract a clew from a wisp of straw or a flake of cigar ash;
5:but Doctor Watson has to have it taken out for him and dusted,
6:and exhibited clearly, with a label attached.
'
	assert_eq_printed(expected, got)
}

fn test_standard_regression_search_empty_with_crlf() {
	mut matcher_builder := regex.RegexMatcherBuilder.new()
	matcher_builder.crlf(true)
	matcher_ := matcher_builder.build(r'x?') or { panic(err) }
	mut builder := StandardBuilder.new()
	builder.color_specs(ColorSpecs.default_with_color())
	mut printer_ := builder.build(ansi_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.line_terminator(matcher.LineTerminator.crlf())
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new_bytes([u8(`\n`)])
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents_ansi(mut printer_)
	assert got.len > 0
}

fn test_standard_regression_after_context_with_match() {
	haystack := 'a
b
c
d
e
d
e
d
e
d
e
'

	matcher_ := regex.RegexMatcherBuilder.new().build(r'd') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut searcher_ := searcher.SearcherBuilder.new()
	searcher_.max_matches(u64(1))
	searcher_.line_number(true)
	searcher_.after_context(2)
	mut built := searcher_.build()
	mut rdr := StandardByteSliceReader.new(haystack)
	mut sink := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := printer_contents(mut printer_)
	expected := '4:d\n5-e\n6:d\n'
	assert_eq_printed(expected, got)
}

fn test_standard_regression_crlf_preserve() {
	haystack := 'hello\nworld\r\n'
	mut matcher_builder := regex.RegexMatcherBuilder.new()
	matcher_builder.crlf(true)
	matcher_ := matcher_builder.build(r'.') or { panic(err) }
	mut printer_ := StandardBuilder.new().build(no_color_buffer())
	mut searcher_builder := searcher.SearcherBuilder.new()
	searcher_builder.line_number(false)
	searcher_builder.line_terminator(matcher.LineTerminator.crlf())
	mut searcher_ := searcher_builder.build()

	mut rdr1 := StandardByteSliceReader.new(haystack)
	mut sink1 := printer_.sink(PrinterMatcher.rust_regex(matcher_))
	searcher_.search_reader(matcher_, mut rdr1, &sink1)!
	got1 := printer_contents(mut printer_)
	expected1 := 'hello\nworld\r\n'
	assert_eq_printed(expected1, got1)

	mut builder := StandardBuilder.new()
	builder.replacement(r'$0'.bytes())
	mut printer2 := builder.build(no_color_buffer())
	mut rdr2 := StandardByteSliceReader.new(haystack)
	mut sink2 := printer2.sink(PrinterMatcher.rust_regex(matcher_))
	searcher_.search_reader(matcher_, mut rdr2, &sink2)!
	got2 := printer_contents(mut printer2)
	expected2 := 'hello\nworld\r\n'
	assert_eq_printed(expected2, got2)
}
