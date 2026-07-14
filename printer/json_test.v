module printer

import cli
import io
import matcher
import regex
import searcher

const json_sherlock = 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
be, to a very large extent, the result of luck. Sherlock Holmes
can extract a clew from a wisp of straw or a flake of cigar ash;
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.
'

struct JsonByteSliceReader {
mut:
	bytes []u8
	pos   int
}

fn JsonByteSliceReader.new(bytes []u8) JsonByteSliceReader {
	return JsonByteSliceReader{
		bytes: bytes.clone()
	}
}

fn JsonByteSliceReader.from_string(slice string) JsonByteSliceReader {
	return JsonByteSliceReader.new(slice.bytes())
}

fn (mut rdr JsonByteSliceReader) read(mut buf []u8) !int {
	if rdr.pos >= rdr.bytes.len {
		return io.Eof{}
	}
	nread := copy(mut buf, rdr.bytes[rdr.pos..])
	rdr.pos += nread
	return nread
}

fn json_buffer() cli.Buffer {
	return cli.BufferWriter.stdout(.never).buffer()
}

fn json_printer_contents(mut printer JSON[cli.Buffer]) string {
	return printer.get_mut().as_slice().bytestr()
}

fn json_line_count(text string) int {
	if text.len == 0 {
		return 0
	}
	mut count := 0
	for line in text.split('\n') {
		if line.len > 0 {
			count++
		}
	}
	return count
}

fn json_last_line(text string) string {
	mut last := ''
	for line in text.split('\n') {
		if line.len > 0 {
			last = line
		}
	}
	return last
}

fn json_nth_line(text string, n int) string {
	mut seen := 0
	for line in text.split('\n') {
		if line.len == 0 {
			continue
		}
		if seen == n {
			return line
		}
		seen++
	}
	return ''
}

fn test_json_builder_build_is_reusable() {
	builder := JSONBuilder.new()
	first := builder.build(json_buffer())
	second := builder.build(json_buffer())
	assert !first.has_written()
	assert !second.has_written()
	first_writer := first.into_inner()
	second_writer := second.into_inner()
	assert first_writer.as_slice().len == 0
	assert second_writer.as_slice().len == 0
}

fn test_json_sink_stats_accumulate_across_searches() {
	matcher_ := regex.RegexMatcher.new(r'Watson') or { panic(err) }
	mut printer := JSONBuilder.new().build(json_buffer())
	mut sink := printer.sink(PrinterMatcher.rust_regex(matcher_))
	built := searcher.SearcherBuilder.new().build()
	assert sink.begin(built)!
	sink.finish(built, searcher.SinkFinish.new(3))!
	assert sink.begin(built)!
	sink.finish(built, searcher.SinkFinish.new(5))!
	assert sink.stats().searches() == u64(2)
	assert sink.stats().bytes_searched() == u64(8)
}

fn test_json_binary_callback_does_not_publish_offset_before_finish() {
	matcher_ := regex.RegexMatcher.new(r'Watson') or { panic(err) }
	mut printer := JSONBuilder.new().build(json_buffer())
	mut sink := printer.sink(PrinterMatcher.rust_regex(matcher_))
	mut builder := searcher.SearcherBuilder.new()
	builder.binary_detection(searcher.BinaryDetection.quit(`\x00`))
	built := builder.build()
	assert sink.binary_data(built, 17)!
	assert sink.binary_byte_offset() == none
}

fn test_json_binary_detection() {
	binary := 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
be, to a very large extent, the result of luck. Sherlock Holmes
can extract a clew \x00 from a wisp of straw or a flake of cigar ash;
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.'

	matcher_ := regex.RegexMatcher.new(r'Watson') or { panic(err) }
	mut printer := JSONBuilder.new().build(json_buffer())
	mut builder := searcher.SearcherBuilder.new()
	builder.binary_detection(searcher.BinaryDetection.quit(`\x00`))
	builder.heap_limit(usize(80))
	mut built := builder.build()
	mut rdr := JsonByteSliceReader.from_string(binary)
	mut sink := printer.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!
	got := json_printer_contents(mut printer)

	assert json_line_count(got) == 3
	last := json_last_line(got)
	assert last.contains(r'"binary_offset":212,')
}

fn test_json_max_matches() {
	matcher_ := regex.RegexMatcher.new(r'Watson') or { panic(err) }
	mut printer := JSONBuilder.new().build(json_buffer())
	mut builder := searcher.SearcherBuilder.new()
	builder.max_matches(u64(1))
	mut built := builder.build()
	mut rdr := JsonByteSliceReader.from_string(json_sherlock)
	mut sink := printer.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!
	got := json_printer_contents(mut printer)

	assert json_line_count(got) == 3
}

fn test_json_max_matches_after_context() {
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
	matcher_ := regex.RegexMatcher.new(r'd') or { panic(err) }
	mut printer := JSONBuilder.new().build(json_buffer())
	mut builder := searcher.SearcherBuilder.new()
	builder.after_context(2)
	builder.max_matches(u64(1))
	mut built := builder.build()
	mut rdr := JsonByteSliceReader.from_string(haystack)
	mut sink := printer.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!
	got := json_printer_contents(mut printer)

	assert json_line_count(got) == 5
}

fn test_json_no_match() {
	matcher_ := regex.RegexMatcher.new(r'DOES NOT MATCH') or { panic(err) }
	mut printer := JSONBuilder.new().build(json_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := JsonByteSliceReader.from_string(json_sherlock)
	mut sink := printer.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!
	got := json_printer_contents(mut printer)

	assert got.len == 0
}

fn test_json_always_begin_end_no_match() {
	matcher_ := regex.RegexMatcher.new(r'DOES NOT MATCH') or { panic(err) }
	mut builder := JSONBuilder.new()
	builder.always_begin_end(true)
	mut printer := builder.build(json_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := JsonByteSliceReader.from_string(json_sherlock)
	mut sink := printer.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!
	got := json_printer_contents(mut printer)

	assert json_line_count(got) == 2
	assert got.contains('begin') && got.contains('end')
}

fn test_json_pretty() {
	matcher_ := regex.RegexMatcher.new(r'DOES NOT MATCH') or { panic(err) }
	mut builder := JSONBuilder.new()
	builder.pretty(true)
	builder.always_begin_end(true)
	mut printer := builder.build(json_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := JsonByteSliceReader.from_string(json_sherlock)
	mut sink := printer.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!
	got := json_printer_contents(mut printer)

	assert got.starts_with('{\n  "type": "begin",\n')
	assert json_line_count(got) > 2
}

fn test_json_missing_crlf() {
	haystack := 'test\r\n'.bytes()

	mut matcher_builder := regex.RegexMatcherBuilder.new()
	matcher_ := matcher_builder.build('test') or { panic(err) }
	mut printer := JSONBuilder.new().build(json_buffer())
	mut built := searcher.SearcherBuilder.new().build()
	mut rdr := JsonByteSliceReader.new(haystack)
	mut sink := printer.sink(PrinterMatcher.rust_regex(matcher_))
	built.search_reader(matcher_, mut rdr, &sink)!
	mut got := json_printer_contents(mut printer)
	assert json_line_count(got) == 3
	assert json_nth_line(got, 1).contains(r'test\r\n'), 'missing \'test\\r\\n\' in \'${json_nth_line(got,
		1)}\''

	mut crlf_matcher_builder := regex.RegexMatcherBuilder.new()
	crlf_matcher_builder.crlf(true)
	crlf_matcher := crlf_matcher_builder.build('test') or { panic(err) }
	mut crlf_printer := JSONBuilder.new().build(json_buffer())
	mut search_builder := searcher.SearcherBuilder.new()
	search_builder.line_terminator(matcher.LineTerminator.crlf())
	mut crlf_searcher := search_builder.build()
	mut crlf_rdr := JsonByteSliceReader.new(haystack)
	mut crlf_sink := crlf_printer.sink(PrinterMatcher.rust_regex(crlf_matcher))
	crlf_searcher.search_reader(crlf_matcher, mut crlf_rdr, &crlf_sink)!
	got = json_printer_contents(mut crlf_printer)
	assert json_line_count(got) == 3
	assert json_nth_line(got, 1).contains(r'test\r\n'), 'missing \'test\\r\\n\' in \'${json_nth_line(got,
		1)}\''
}
