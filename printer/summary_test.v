module printer

import cli
import io
import regex
import searcher

const summary_sherlock = 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
be, to a very large extent, the result of luck. Sherlock Holmes
can extract a clew from a wisp of straw or a flake of cigar ash;
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.
'

struct SummaryByteSliceReader {
mut:
	bytes []u8
	pos   int
}

fn SummaryByteSliceReader.new(slice string) SummaryByteSliceReader {
	return SummaryByteSliceReader{
		bytes: slice.bytes()
	}
}

fn (mut rdr SummaryByteSliceReader) read(mut buf []u8) !int {
	if rdr.pos >= rdr.bytes.len {
		return io.Eof{}
	}
	nread := copy(mut buf, rdr.bytes[rdr.pos..])
	rdr.pos += nread
	return nread
}

fn summary_no_color_buffer() cli.Buffer {
	return cli.BufferWriter.stdout(.never).buffer()
}

fn summary_printer_contents(mut printer Summary[cli.Buffer]) string {
	return printer.get_mut().as_slice().bytestr()
}

fn summary_assert_eq_printed(expected string, got string) {
	if got != expected {
		panic('expected:\n${expected}\n\ngot:\n${got}')
	}
}

fn test_summary_path_with_match_error() {
	matcher_ := regex.RegexMatcher.new(r'Watson') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.path_with_match)
	mut printer := builder.build(summary_no_color_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	mut sink := printer.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink) or { return }
	assert false
}

fn test_summary_path_without_match_error() {
	matcher_ := regex.RegexMatcher.new(r'Watson') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.path_without_match)
	mut printer := builder.build(summary_no_color_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	mut sink := printer.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink) or { return }
	assert false
}

fn test_summary_count_no_path() {
	matcher_ := regex.RegexMatcher.new(r'Watson') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.count)
	mut printer := builder.build(summary_no_color_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	mut sink := printer.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := summary_printer_contents(mut printer)
	summary_assert_eq_printed('2\n', got)
}

fn test_summary_builder_build_is_reusable() {
	builder := SummaryBuilder.new()
	first := builder.build(summary_no_color_buffer())
	second := builder.build(summary_no_color_buffer())
	assert !first.has_written()
	assert !second.has_written()
	first_writer := first.into_inner()
	second_writer := second.into_inner()
	assert first_writer.as_slice().len == 0
	assert second_writer.as_slice().len == 0
}

fn test_summary_count_no_path_even_with_path() {
	matcher_ := regex.RegexMatcher.new(r'Watson') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.count)
	builder.path(false)
	mut printer := builder.build(summary_no_color_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	path := 'sherlock'
	mut sink := printer.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := summary_printer_contents(mut printer)
	summary_assert_eq_printed('2\n', got)
}

fn test_summary_count_path() {
	matcher_ := regex.RegexMatcher.new(r'Watson') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.count)
	mut printer := builder.build(summary_no_color_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	path := 'sherlock'
	mut sink := printer.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := summary_printer_contents(mut printer)
	summary_assert_eq_printed('sherlock:2\n', got)
}

fn test_summary_count_path_with_zero() {
	matcher_ := regex.RegexMatcher.new(r'NO MATCH') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.count)
	builder.exclude_zero(false)
	mut printer := builder.build(summary_no_color_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	path := 'sherlock'
	mut sink := printer.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := summary_printer_contents(mut printer)
	summary_assert_eq_printed('sherlock:0\n', got)
}

fn test_summary_count_path_without_zero() {
	matcher_ := regex.RegexMatcher.new(r'NO MATCH') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.count)
	builder.exclude_zero(true)
	mut printer := builder.build(summary_no_color_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	path := 'sherlock'
	mut sink := printer.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := summary_printer_contents(mut printer)
	summary_assert_eq_printed('', got)
}

fn test_summary_count_path_field_separator() {
	matcher_ := regex.RegexMatcher.new(r'Watson') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.count)
	builder.separator_field('ZZ'.bytes())
	mut printer := builder.build(summary_no_color_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	path := 'sherlock'
	mut sink := printer.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := summary_printer_contents(mut printer)
	summary_assert_eq_printed('sherlockZZ2\n', got)
}

fn test_summary_count_path_terminator() {
	matcher_ := regex.RegexMatcher.new(r'Watson') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.count)
	builder.path_terminator(u8(0))
	mut printer := builder.build(summary_no_color_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	path := 'sherlock'
	mut sink := printer.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := summary_printer_contents(mut printer)
	summary_assert_eq_printed('sherlock\x002\n', got)
}

fn test_summary_count_path_separator() {
	matcher_ := regex.RegexMatcher.new(r'Watson') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.count)
	builder.separator_path(u8(`\\`))
	mut printer := builder.build(summary_no_color_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	path := '/home/andrew/sherlock'
	mut sink := printer.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := summary_printer_contents(mut printer)
	summary_assert_eq_printed('\\home\\andrew\\sherlock:2\n', got)
}

fn test_summary_count_max_matches() {
	matcher_ := regex.RegexMatcher.new(r'Watson') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.count)
	mut printer := builder.build(summary_no_color_buffer())
	mut searcher_builder := searcher.SearcherBuilder.new()
	searcher_builder.max_matches(u64(1))
	mut built := searcher_builder.build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	mut sink := printer.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!

	got := summary_printer_contents(mut printer)
	summary_assert_eq_printed('1\n', got)
}

fn test_summary_count_matches() {
	matcher_ := regex.RegexMatcher.new(r'Watson|Sherlock') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.count_matches)
	mut printer := builder.build(summary_no_color_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	path := 'sherlock'
	mut sink := printer.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := summary_printer_contents(mut printer)
	summary_assert_eq_printed('sherlock:4\n', got)
}

fn test_summary_path_with_match_found() {
	matcher_ := regex.RegexMatcher.new(r'Watson') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.path_with_match)
	mut printer := builder.build(summary_no_color_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	path := 'sherlock'
	mut sink := printer.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := summary_printer_contents(mut printer)
	summary_assert_eq_printed('sherlock\n', got)
}

fn test_summary_path_with_match_not_found() {
	matcher_ := regex.RegexMatcher.new(r'ZZZZZZZZ') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.path_with_match)
	mut printer := builder.build(summary_no_color_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	path := 'sherlock'
	mut sink := printer.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := summary_printer_contents(mut printer)
	summary_assert_eq_printed('', got)
}

fn test_summary_path_without_match_found() {
	matcher_ := regex.RegexMatcher.new(r'ZZZZZZZZZ') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.path_without_match)
	mut printer := builder.build(summary_no_color_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	path := 'sherlock'
	mut sink := printer.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := summary_printer_contents(mut printer)
	summary_assert_eq_printed('sherlock\n', got)
}

fn test_summary_path_without_match_not_found() {
	matcher_ := regex.RegexMatcher.new(r'Watson') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.path_without_match)
	mut printer := builder.build(summary_no_color_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	path := 'sherlock'
	mut sink := printer.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	built.search_reader(matcher_, mut rdr, &sink)!

	got := summary_printer_contents(mut printer)
	summary_assert_eq_printed('', got)
}

fn test_summary_quiet() {
	matcher_ := regex.RegexMatcher.new(r'Watson|Sherlock') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.quiet_with_match)
	mut printer := builder.build(summary_no_color_buffer())
	path := 'sherlock'
	mut sink := printer.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	built.search_reader(matcher_, mut rdr, &sink)!
	match_count := sink.match_count

	got := summary_printer_contents(mut printer)
	summary_assert_eq_printed('', got)
	// There is actually more than one match, but Quiet should quit after
	// finding the first one.
	assert match_count == u64(1)
}

fn test_summary_quiet_with_stats() {
	matcher_ := regex.RegexMatcher.new(r'Watson|Sherlock') or { panic(err) }
	mut builder := SummaryBuilder.new()
	builder.kind(.quiet_with_match)
	builder.stats(true)
	mut printer := builder.build(summary_no_color_buffer())
	path := 'sherlock'
	mut sink := printer.sink_with_path(PrinterMatcher.rust_regex(matcher_), &path)
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := SummaryByteSliceReader.new(summary_sherlock)
	built.search_reader(matcher_, mut rdr, &sink)!
	match_count := sink.match_count
	stats := sink.stats() or { panic('missing summary stats') }
	assert stats.matches() == u64(4)
	assert stats.matched_lines() == u64(3)

	got := summary_printer_contents(mut printer)
	summary_assert_eq_printed('', got)
	// There is actually more than one match, and Quiet will usually quit
	// after finding the first one, but since we request stats, it will
	// mush on to find all matches.
	assert match_count == u64(3)
}
