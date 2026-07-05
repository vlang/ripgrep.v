module searcher

import io
import matcher
import os

struct ByteSliceReaderForSearch {
mut:
	bytes []u8
	pos   int
}

fn ByteSliceReaderForSearch.new(slice string) ByteSliceReaderForSearch {
	return ByteSliceReaderForSearch{
		bytes: slice.bytes()
	}
}

fn ByteSliceReaderForSearch.new_bytes(slice []u8) ByteSliceReaderForSearch {
	return ByteSliceReaderForSearch{
		bytes: slice.clone()
	}
}

fn (mut rdr ByteSliceReaderForSearch) read(mut buf []u8) !int {
	if rdr.pos >= rdr.bytes.len {
		return io.Eof{}
	}
	nread := copy(mut buf, rdr.bytes[rdr.pos..])
	rdr.pos += nread
	return nread
}

struct LiteralMatcher {
	needle    []u8
	line_term ?matcher.LineTerminator
}

fn LiteralMatcher.new(needle string) LiteralMatcher {
	return LiteralMatcher{
		needle: needle.bytes()
	}
}

fn (m LiteralMatcher) with_line_term(line_term ?matcher.LineTerminator) LiteralMatcher {
	return LiteralMatcher{
		needle:    m.needle.clone()
		line_term: line_term
	}
}

fn (m LiteralMatcher) find_at(haystack []u8, at usize) !matcher.FallibleMatch {
	if at > haystack.len {
		return matcher.FallibleMatch.absent()
	}
	if m.needle.len == 0 {
		return matcher.FallibleMatch.some(matcher.Match.zero(at))
	}
	mut i := at
	for i + m.needle.len <= haystack.len {
		mut matched := true
		for j in 0 .. m.needle.len {
			if haystack[i + j] != m.needle[j] {
				matched = false
				break
			}
		}
		if matched {
			return matcher.FallibleMatch.some(matcher.Match.new(i, i + m.needle.len))
		}
		i++
	}
	return matcher.FallibleMatch.absent()
}

fn (m LiteralMatcher) new_captures() !matcher.NoCaptures {
	_ = m
	return matcher.NoCaptures.new()
}

fn (m LiteralMatcher) capture_count() usize {
	_ = m
	return 0
}

fn (m LiteralMatcher) capture_index(name string) ?usize {
	_ = m
	_ = name
	return none
}

fn (m LiteralMatcher) captures_at(haystack []u8, at usize, mut caps matcher.NoCaptures) !bool {
	_ = m
	_ = haystack
	_ = at
	_ = caps
	return false
}

fn (m &^a LiteralMatcher) non_matching_bytes[^a]() ?&^a matcher.ByteSet {
	_ = m
	return none
}

fn (m LiteralMatcher) line_terminator() ?matcher.LineTerminator {
	return m.line_term
}

fn (m LiteralMatcher) find_candidate_line(haystack []u8) !matcher.FallibleLineMatchKind {
	maybe_match := m.find_at(haystack, 0)!
	mat := maybe_match.get() or {
		return matcher.FallibleLineMatchKind.absent()
	}
	return matcher.FallibleLineMatchKind.some(matcher.LineMatchKind.confirmed(mat.end()))
}

struct CollectSink {
mut:
	matches        []string
	contexts       []string
	breaks         int
	finished       bool
	byte_count     u64
	binary_offset  ?u64
	binary_reports []u64
}

fn (mut sink CollectSink) matched(searcher_ Searcher, mat SinkMatch) !bool {
	_ = searcher_
	line := mat.line_number() or { u64(0) }
	sink.matches << '${line}:${mat.absolute_byte_offset()}:${mat.bytes().bytestr()}'
	return true
}

fn (mut sink CollectSink) context(searcher_ Searcher, ctx SinkContext) !bool {
	_ = searcher_
	line := ctx.line_number() or { u64(0) }
	sink.contexts << '${ctx.kind()}:${line}:${ctx.absolute_byte_offset()}:${ctx.bytes().bytestr()}'
	return true
}

fn (mut sink CollectSink) context_break(searcher_ Searcher) !bool {
	_ = searcher_
	sink.breaks++
	return true
}

fn (mut sink CollectSink) binary_data(searcher_ Searcher, binary_byte_offset u64) !bool {
	_ = searcher_
	sink.binary_reports << binary_byte_offset
	return true
}

fn (mut sink CollectSink) begin(searcher_ Searcher) !bool {
	_ = searcher_
	return true
}

fn (mut sink CollectSink) finish(searcher_ Searcher, finish SinkFinish) ! {
	_ = searcher_
	sink.finished = true
	sink.byte_count = finish.byte_count()
	sink.binary_offset = finish.binary_byte_offset()
}

fn test_searcher_mod_config_error_heap_limit() {
	mut builder := SearcherBuilder.new()
	builder.heap_limit(usize(0))
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_slice(LiteralMatcher.new(''), []u8{}, &sink) or {
		assert true
		return
	}
	assert false
}

fn test_searcher_mod_config_error_line_terminator() {
	matcher_ := LiteralMatcher.new('').with_line_term(matcher.LineTerminator.byte(`z`))

	mut sink := CollectSink{}
	mut searcher_ := Searcher.new()
	searcher_.search_slice(matcher_, []u8{}, &sink) or {
		assert true
		return
	}
	assert false
}

fn test_searcher_mod_uft8_bom_sniffing() {
	// See: https://github.com/BurntSushi/ripgrep/issues/1638
	// ripgrep must sniff utf-8 BOM, just like it does with utf-16
	haystack := [u8(0xef), 0xbb, 0xbf, 0x66, 0x6f, 0x6f]
	mut sink := CollectSink{}
	mut searcher_ := SearcherBuilder.new().build()

	searcher_.search_slice(LiteralMatcher.new('foo'), haystack, &sink)!

	assert sink.matches == [
		'1:0:foo',
	]
	assert sink.finished
	assert sink.byte_count == 3
}

fn test_search_slice_reports_line_matches() {
	text := 'alpha\nSherlock\nbeta Sherlock\nomega\n'
	mut searcher_ := Searcher.new()
	mut sink := CollectSink{}
	searcher_.search_slice(LiteralMatcher.new('Sherlock'), text.bytes(), &sink)!

	assert sink.matches == [
		'2:6:Sherlock\n',
		'3:15:beta Sherlock\n',
	]
	assert sink.finished
	assert sink.byte_count == u64(text.len)
}

fn test_search_slice_invert_and_context() {
	text := 'one\ntwo\nthree\nfour\n'
	mut builder := SearcherBuilder.new()
	builder.invert_match(true)
	builder.before_context(1)
	builder.after_context(1)
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_slice(LiteralMatcher.new('three'), text.bytes(), &sink)!

	assert sink.contexts == [
		'after:3:8:three\n',
	]
	assert sink.matches == [
		'1:0:one\n',
		'2:4:two\n',
		'4:14:four\n',
	]
	assert sink.finished
}

fn test_search_slice_respects_max_matches() {
	mut builder := SearcherBuilder.new()
	builder.max_matches(u64(1))
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_slice(LiteralMatcher.new('a'), 'a\nb\na\n'.bytes(), &sink)!

	assert sink.matches == [
		'1:0:a\n',
	]
	assert sink.finished
}

fn test_search_slice_utf8_bom_sniffing() {
	// See: https://github.com/BurntSushi/ripgrep/issues/1638
	// ripgrep must sniff utf-8 BOM, just like it does with utf-16
	haystack := [u8(0xef), 0xbb, 0xbf, `f`, `o`, `o`, `\n`]
	mut searcher_ := Searcher.new()
	mut sink := CollectSink{}
	searcher_.search_slice(LiteralMatcher.new('foo'), haystack, &sink)!

	assert sink.matches == [
		'1:0:foo\n',
	]
	assert sink.finished
	assert sink.byte_count == 4
}

fn test_search_slice_utf16le_bom_sniffing() {
	haystack := [u8(0xff), 0xfe, `f`, 0, `o`, 0, `o`, 0, `\n`, 0]
	mut searcher_ := Searcher.new()
	mut sink := CollectSink{}
	searcher_.search_slice(LiteralMatcher.new('foo'), haystack, &sink)!

	assert sink.matches == [
		'1:0:foo\n',
	]
	assert sink.finished
	assert sink.byte_count == 4
}

fn test_search_slice_explicit_utf16be_encoding() {
	haystack := [u8(0), `f`, 0, `o`, 0, `o`, 0, `\n`]
	mut builder := SearcherBuilder.new()
	encoding := Encoding.new('utf-16be')!
	builder.encoding(encoding)
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_slice(LiteralMatcher.new('foo'), haystack, &sink)!

	assert sink.matches == [
		'1:0:foo\n',
	]
	assert sink.finished
	assert sink.byte_count == 4
}

fn test_search_slice_explicit_utf32le_encoding() {
	haystack := [u8(`f`), 0, 0, 0, `o`, 0, 0, 0, `o`, 0, 0, 0, `\n`, 0, 0, 0]
	mut builder := SearcherBuilder.new()
	encoding := Encoding.new('utf-32le')!
	builder.encoding(encoding)
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_slice(LiteralMatcher.new('foo'), haystack, &sink)!

	assert sink.matches == [
		'1:0:foo\n',
	]
	assert sink.finished
	assert sink.byte_count == 4
}

fn test_transcode_explicit_utf32be_encoding() {
	haystack := [u8(0), 0, 0, `f`, 0, 0, 0, `o`, 0, 0, 0, `o`, 0, 0, 0, `\n`]
	mut builder := SearcherBuilder.new()
	encoding := Encoding.new('utf32be')!
	builder.encoding(encoding)
	searcher_ := builder.build()

	got := transcode_slice_with_config(searcher_.config, haystack)!
	assert got == [u8(`f`), `o`, `o`, `\n`]
}

fn test_transcode_explicit_windows1252_encoding() {
	haystack := [u8(0x80), 0x81, `\n`]
	mut builder := SearcherBuilder.new()
	encoding := Encoding.new('latin1')!
	builder.encoding(encoding)
	searcher_ := builder.build()

	got := transcode_slice_with_config(searcher_.config, haystack)!
	assert got == [u8(0xe2), 0x82, 0xac, 0xef, 0xbf, 0xbd, `\n`]
}

fn test_search_reader_reports_line_matches() {
	text := 'alpha\nSherlock\nbeta Sherlock\nomega\n'
	mut source := ByteSliceReaderForSearch.new(text)
	mut searcher_ := Searcher.new()
	mut sink := CollectSink{}
	searcher_.search_reader(LiteralMatcher.new('Sherlock'), mut source, &sink)!

	assert sink.matches == [
		'2:6:Sherlock\n',
		'3:15:beta Sherlock\n',
	]
	assert sink.finished
	assert sink.byte_count == u64(text.len)
}

fn test_search_reader_multi_line_utf8_bom_sniffing() {
	haystack := [u8(0xef), 0xbb, 0xbf, `f`, `o`, `o`, `\n`, `b`, `a`, `r`, `\n`]
	mut source := ByteSliceReaderForSearch.new_bytes(haystack)
	mut builder := SearcherBuilder.new()
	builder.multi_line(true)
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_reader(LiteralMatcher.new('foo'), mut source, &sink)!

	assert sink.matches == [
		'1:0:foo\n',
	]
	assert sink.finished
	assert sink.byte_count == 8
}

fn test_search_reader_utf8_bom_sniffing() {
	haystack := [u8(0xef), 0xbb, 0xbf, `f`, `o`, `o`, `\n`, `b`, `a`, `r`, `\n`]
	mut source := ByteSliceReaderForSearch.new_bytes(haystack)
	mut searcher_ := Searcher.new()
	mut sink := CollectSink{}
	searcher_.search_reader(LiteralMatcher.new('foo'), mut source, &sink)!

	assert sink.matches == [
		'1:0:foo\n',
	]
	assert sink.finished
	assert sink.byte_count == 8
}

fn test_search_reader_explicit_utf16le_encoding() {
	haystack := [u8(`f`), 0, `o`, 0, `o`, 0, `\n`, 0, `b`, 0, `a`, 0, `r`, 0,
		`\n`, 0]
	mut source := ByteSliceReaderForSearch.new_bytes(haystack)
	mut builder := SearcherBuilder.new()
	encoding := Encoding.new('utf-16le')!
	builder.encoding(encoding)
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_reader(LiteralMatcher.new('foo'), mut source, &sink)!

	assert sink.matches == [
		'1:0:foo\n',
	]
	assert sink.finished
	assert sink.byte_count == 8
}

fn test_search_path_reports_line_matches() {
	text := 'alpha\nSherlock\nbeta Sherlock\nomega\n'
	path := os.join_path(os.temp_dir(), 'ripgrep_v_search_path_test.txt')
	os.write_file(path, text)!
	defer {
		os.rm(path) or {}
	}
	mut searcher_ := Searcher.new()
	mut sink := CollectSink{}
	searcher_.search_path(LiteralMatcher.new('Sherlock'), path, &sink)!

	assert sink.matches == [
		'2:6:Sherlock\n',
		'3:15:beta Sherlock\n',
	]
	assert sink.finished
	assert sink.byte_count == u64(text.len)
}

fn test_search_file_reports_line_matches() {
	text := 'alpha\nSherlock\nbeta Sherlock\nomega\n'
	path := os.join_path(os.temp_dir(), 'ripgrep_v_search_file_test.txt')
	os.write_file(path, text)!
	defer {
		os.rm(path) or {}
	}
	mut file := os.open(path)!
	defer {
		file.close()
	}
	mut searcher_ := Searcher.new()
	mut sink := CollectSink{}
	searcher_.search_file(LiteralMatcher.new('Sherlock'), mut file, &sink)!

	assert sink.matches == [
		'2:6:Sherlock\n',
		'3:15:beta Sherlock\n',
	]
	assert sink.finished
	assert sink.byte_count == u64(text.len)
}

fn test_search_file_utf8_bom_sniffing() {
	haystack := [u8(0xef), 0xbb, 0xbf, `f`, `o`, `o`, `\n`, `b`, `a`, `r`, `\n`]
	path := os.join_path(os.temp_dir(), 'ripgrep_v_search_file_utf8_bom_test.txt')
	os.write_file_array(path, haystack)!
	defer {
		os.rm(path) or {}
	}
	mut file := os.open(path)!
	defer {
		file.close()
	}
	mut searcher_ := Searcher.new()
	mut sink := CollectSink{}
	searcher_.search_file(LiteralMatcher.new('foo'), mut file, &sink)!

	assert sink.matches == [
		'1:0:foo\n',
	]
	assert sink.finished
	assert sink.byte_count == 8
}

fn test_search_file_explicit_utf16be_encoding() {
	haystack := [u8(0), `f`, 0, `o`, 0, `o`, 0, `\n`, 0, `b`, 0, `a`, 0, `r`, 0,
		`\n`]
	path := os.join_path(os.temp_dir(), 'ripgrep_v_search_file_utf16be_test.txt')
	os.write_file_array(path, haystack)!
	defer {
		os.rm(path) or {}
	}
	mut file := os.open(path)!
	defer {
		file.close()
	}
	mut builder := SearcherBuilder.new()
	encoding := Encoding.new('utf-16be')!
	builder.encoding(encoding)
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_file(LiteralMatcher.new('foo'), mut file, &sink)!

	assert sink.matches == [
		'1:0:foo\n',
	]
	assert sink.finished
	assert sink.byte_count == 8
}

fn test_search_path_utf16le_bom_sniffing() {
	haystack := [u8(0xff), 0xfe, `f`, 0, `o`, 0, `o`, 0, `\n`, 0, `b`, 0, `a`, 0,
		`r`, 0, `\n`, 0]
	path := os.join_path(os.temp_dir(), 'ripgrep_v_search_path_utf16le_bom_test.txt')
	os.write_file_array(path, haystack)!
	defer {
		os.rm(path) or {}
	}
	mut searcher_ := Searcher.new()
	mut sink := CollectSink{}
	searcher_.search_path(LiteralMatcher.new('foo'), path, &sink)!

	assert sink.matches == [
		'1:0:foo\n',
	]
	assert sink.finished
	assert sink.byte_count == 8
}

fn test_search_path_with_mmap_auto_reports_line_matches() {
	text := 'alpha\nSherlock\nbeta Sherlock\nomega\n'
	path := os.join_path(os.temp_dir(), 'ripgrep_v_search_path_mmap_test.txt')
	os.write_file(path, text)!
	defer {
		os.rm(path) or {}
	}
	mut builder := SearcherBuilder.new()
	builder.memory_map(MmapChoice.auto())
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_path(LiteralMatcher.new('Sherlock'), path, &sink)!

	assert sink.matches == [
		'2:6:Sherlock\n',
		'3:15:beta Sherlock\n',
	]
	assert sink.finished
	assert sink.byte_count == u64(text.len)
}

fn test_search_path_multi_line_reads_file() {
	text := 'alpha\nSherlock\nHolmes\nomega\n'
	path := os.join_path(os.temp_dir(), 'ripgrep_v_search_path_multiline_test.txt')
	os.write_file(path, text)!
	defer {
		os.rm(path) or {}
	}
	mut builder := SearcherBuilder.new()
	builder.multi_line(true)
	builder.memory_map(MmapChoice.auto())
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_path(LiteralMatcher.new('Sherlock\nHolmes'), path, &sink)!

	assert sink.matches == [
		'2:6:Sherlock\nHolmes\n',
	]
	assert sink.finished
	assert sink.byte_count == u64(text.len)
}

fn test_search_reader_multi_line_heap_limit_errors_at_limit() {
	text := 'Sherlock\n'
	mut source := ByteSliceReaderForSearch.new(text)
	mut builder := SearcherBuilder.new()
	builder.multi_line(true)
	builder.heap_limit(usize(text.len))
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_reader(LiteralMatcher.new('Sherlock'), mut source, &sink) or {
		assert err.msg().contains('configured allocation limit')
		return
	}
	assert false
}
