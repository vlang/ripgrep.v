module searcher

import io
import matcher
import os
import regex

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

struct LimitedChunkReaderForSearch {
mut:
	bytes      []u8
	pos        int
	chunk      int
	fail_after int
}

fn LimitedChunkReaderForSearch.new(bytes &[]u8, chunk int, fail_after int) LimitedChunkReaderForSearch {
	return LimitedChunkReaderForSearch{
		bytes:      bytes.clone()
		chunk:      chunk
		fail_after: fail_after
	}
}

fn (mut rdr LimitedChunkReaderForSearch) read(mut buf []u8) !int {
	if rdr.pos >= rdr.bytes.len {
		return io.Eof{}
	}
	if rdr.pos >= rdr.fail_after {
		return error('reader consumed too much input')
	}
	remaining_before_fail := rdr.fail_after - rdr.pos
	max_chunk := if rdr.chunk < remaining_before_fail { rdr.chunk } else { remaining_before_fail }
	nread := copy(mut buf, rdr.bytes[rdr.pos..rdr.pos + max_chunk])
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

fn (m LiteralMatcher) find_at(haystack &[]u8, at usize) !matcher.FallibleMatch {
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

fn (m LiteralMatcher) shortest_match_at(haystack &[]u8, at usize) !matcher.FallibleUsize {
	return matcher.shortest_match_at(m, haystack, at)
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

fn (m LiteralMatcher) captures_at(haystack &[]u8, at usize, mut caps matcher.NoCaptures) !bool {
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

fn (m LiteralMatcher) find_candidate_line(haystack &[]u8) !matcher.FallibleLineMatchKind {
	maybe_match := m.find_at(haystack, 0)!
	mat := maybe_match.get() or {
		return matcher.FallibleLineMatchKind.absent()
	}
	return matcher.FallibleLineMatchKind.some(matcher.LineMatchKind.confirmed(mat.end()))
}

struct ShortestMatchOnlyMatcher {}

fn (m ShortestMatchOnlyMatcher) find_at(haystack &[]u8, at usize) !matcher.FallibleMatch {
	_ = m
	_ = haystack
	_ = at
	return error('search core called find_at instead of shortest_match_at')
}

fn (m ShortestMatchOnlyMatcher) shortest_match_at(haystack &[]u8, at usize) !matcher.FallibleUsize {
	_ = m
	for i := at; i < haystack.len; i++ {
		if haystack[i] == `x` {
			return matcher.FallibleUsize.some(i + 1)
		}
	}
	return matcher.FallibleUsize.absent()
}

fn (m ShortestMatchOnlyMatcher) new_captures() !matcher.NoCaptures {
	_ = m
	return matcher.NoCaptures.new()
}

fn (m ShortestMatchOnlyMatcher) capture_count() usize {
	_ = m
	return matcher.default_capture_count()
}

fn (m ShortestMatchOnlyMatcher) capture_index(name string) ?usize {
	_ = m
	return matcher.default_capture_index(name)
}

fn (m ShortestMatchOnlyMatcher) captures_at(haystack &[]u8, at usize, mut caps matcher.NoCaptures) !bool {
	_ = m
	return matcher.default_captures_at(haystack, at, mut caps)
}

fn (m &^a ShortestMatchOnlyMatcher) non_matching_bytes[^a]() ?&^a matcher.ByteSet {
	_ = m
	return none
}

fn (m ShortestMatchOnlyMatcher) line_terminator() ?matcher.LineTerminator {
	_ = m
	return none
}

fn (m ShortestMatchOnlyMatcher) find_candidate_line(haystack &[]u8) !matcher.FallibleLineMatchKind {
	_ = m
	_ = haystack
	return error('slow line search should not request a candidate line')
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

fn (mut sink CollectSink) matched[^b](searcher_ &Searcher, mat &SinkMatch[^b]) !bool {
	_ = searcher_
	line := mat.line_number() or { u64(0) }
	sink.matches << '${line}:${mat.absolute_byte_offset()}:${mat.bytes().bytestr()}'
	return true
}

fn (mut sink CollectSink) context[^b](searcher_ &Searcher, ctx &SinkContext[^b]) !bool {
	_ = searcher_
	line := ctx.line_number() or { u64(0) }
	sink.contexts << '${*ctx.kind()}:${line}:${ctx.absolute_byte_offset()}:${ctx.bytes().bytestr()}'
	return true
}

fn (mut sink CollectSink) context_break(searcher_ &Searcher) !bool {
	_ = searcher_
	sink.breaks++
	return true
}

fn (mut sink CollectSink) binary_data(searcher_ &Searcher, binary_byte_offset u64) !bool {
	_ = searcher_
	sink.binary_reports << binary_byte_offset
	return true
}

fn (mut sink CollectSink) begin(searcher_ &Searcher) !bool {
	_ = searcher_
	return true
}

fn (mut sink CollectSink) finish(searcher_ &Searcher, finish &SinkFinish) ! {
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

fn test_search_slice_slow_path_uses_shortest_match() {
	mut searcher_ := Searcher.new()
	mut sink := CollectSink{}
	searcher_.search_slice(ShortestMatchOnlyMatcher{}, 'x\n'.bytes(), &sink)!

	assert sink.matches == [
		'1:0:x\n',
	]
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

fn test_transcode_explicit_windows1252_encoding() {
	haystack := [u8(0x80), 0x81, `\n`]
	mut builder := SearcherBuilder.new()
	encoding := Encoding.new('latin1')!
	builder.encoding(encoding)
	searcher_ := builder.build()

	got := transcode_slice_with_config(&searcher_.config, haystack)!
	assert got == [u8(0xe2), 0x82, 0xac, 0xc2, 0x81, `\n`]
}

fn test_encoding_rs_single_byte_tables_replace_unmapped_bytes() {
	assert decode_iconv([u8(0xa5)], 'ISO-8859-3')! == [u8(0xef), 0xbf, 0xbd]
	assert decode_iconv([u8(0xc0), 0xe0], 'WINDOWS-1251')! == 'Аа'.bytes()
	assert decode_iconv([u8(0x81)], 'WINDOWS-1250')! == [u8(0xc2), 0x81]
}

fn test_transcode_explicit_utf8_replaces_malformed_sequences() {
	mut builder := SearcherBuilder.new()
	builder.encoding(Encoding.new('utf-8')!)
	searcher_ := builder.build()
	got := transcode_slice_with_config(&searcher_.config, [u8(`a`), 0xc2, `b`, 0xe2, 0x82])!
	assert got == [u8(`a`), 0xef, 0xbf, 0xbd, `b`, 0xef, 0xbf, 0xbd]
}

fn test_bom_sniffed_utf8_replaces_malformed_sequences() {
	config := SearcherBuilder.new().build().config
	got := transcode_slice_with_config(&config, [u8(0xef), 0xbb, 0xbf, `a`, 0xff, `b`])!
	assert got == [u8(`a`), 0xef, 0xbf, 0xbd, `b`]
}

fn test_utf8_stream_decoder_preserves_split_sequence() {
	first := decode_utf8_lossy([u8(`a`), 0xe2], false)
	assert first.bytes == [u8(`a`)]
	assert first.tail == [u8(0xe2)]
	mut second_input := first.tail.clone()
	second_input << [u8(0x82), 0xac, `b`]
	second := decode_utf8_lossy(second_input, true)
	assert second.bytes == [u8(0xe2), 0x82, 0xac, `b`]
	assert second.tail.len == 0
}

fn test_iconv_stream_boundaries_preserve_split_multibyte_sequences() {
	assert multibyte_stream_boundary([u8(`a`), 0x82], 'SHIFT_JIS') == 1
	assert multibyte_stream_boundary([u8(`a`), 0x82, 0xa0], 'SHIFT_JIS') == 3
	assert multibyte_stream_boundary([u8(0x81), 0x30, 0x81], 'GB18030') == 0
	assert multibyte_stream_boundary([u8(0x81), 0x30, 0x81, 0x30], 'GB18030') == 4
}

fn test_iso2022jp_stream_boundary_preserves_mode_and_split_pair() {
	first_end, first_mode := iso2022jp_stream_boundary([u8(0x1b), `$`, `B`, 0x24], 0)
	assert first_end == 3
	assert first_mode == 3
	second_end, second_mode := iso2022jp_stream_boundary([u8(0x24), 0x22, 0x1b, `(`,
		`B`], first_mode)
	assert second_end == 5
	assert second_mode == 0
	assert iso2022jp_mode_prefix(3) == [u8(0x1b), `$`, `B`]
}

fn test_transcode_explicit_x_user_defined_encoding() {
	haystack := [u8(`A`), 0x80, `B`]
	mut builder := SearcherBuilder.new()
	encoding := Encoding.new('x-user-defined')!
	builder.encoding(encoding)
	searcher_ := builder.build()

	got := transcode_slice_with_config(&searcher_.config, haystack)!
	assert got == [u8(`A`), 0xef, 0x9e, 0x80, `B`]
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

fn test_search_reader_with_default_regex_complex_classes() {
	for pattern in [r'[\x00-\x7F]+', r'[^[:digit:]]+', r'\p{Age=6.0}+'] {
		mut regex_builder := regex.RegexMatcherBuilder.new()
		regex_builder.multi_line(true)
		regex_builder.line_terminator(`\n`)
		matcher_ := regex_builder.build(pattern)!
		matcher_ref := regex.RegexMatcherRef.new(&matcher_)
		candidate := matcher_ref.find_candidate_line('abc\n'.bytes())!
		assert candidate.has_value
		mut source := ByteSliceReaderForSearch.new('abc\n')
		mut searcher_ := Searcher.new()
		mut sink := CollectSink{}
		searcher_.search_reader(matcher_ref, mut source, &sink)!
		assert sink.matches == ['1:0:abc\n']
	}
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

fn test_search_reader_utf16le_preserves_surrogate_pair_across_stream_chunk() {
	mut haystack := []u8{cap: 8200}
	for _ in 0 .. 4096 {
		haystack << [u8(`x`), 0]
	}
	// U+1F600 encoded as a UTF-16LE surrogate pair. The first internal read ends
	// after the high surrogate (and one byte of the low surrogate).
	haystack << [u8(0x3d), 0xd8, 0x00, 0xde, `\n`, 0]
	mut source := ByteSliceReaderForSearch.new_bytes(haystack)
	mut builder := SearcherBuilder.new()
	encoding := Encoding.new('utf-16le')!
	builder.encoding(encoding)
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_reader(LiteralMatcher.new('😀'), mut source, &sink)!

	assert sink.matches.len == 1
	assert sink.matches[0].contains('😀')
}

fn test_search_reader_explicit_utf16le_streams_until_quit() {
	mut haystack := [u8(`f`), 0, `o`, 0, `o`, 0, `\n`, 0]
	for _ in 0 .. 256 {
		haystack << [u8(`x`), 0, `\n`, 0]
	}
	mut source := LimitedChunkReaderForSearch.new(&haystack, 5, 16)
	mut builder := SearcherBuilder.new()
	encoding := Encoding.new('utf-16le')!
	builder.encoding(encoding)
	builder.max_matches(u64(1))
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_reader(LiteralMatcher.new('foo'), mut source, &sink)!

	assert sink.matches == [
		'1:0:foo\n',
	]
	assert source.pos < 16
}

fn test_search_reader_bom_sniffed_utf16le_streams_until_quit() {
	mut haystack := [u8(0xff), 0xfe, `f`, 0, `o`, 0, `o`, 0, `\n`, 0]
	for _ in 0 .. 256 {
		haystack << [u8(`x`), 0, `\n`, 0]
	}
	mut source := LimitedChunkReaderForSearch.new(&haystack, 5, 20)
	mut builder := SearcherBuilder.new()
	builder.max_matches(u64(1))
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_reader(LiteralMatcher.new('foo'), mut source, &sink)!

	assert sink.matches == [
		'1:0:foo\n',
	]
	assert source.pos < 20
}

fn test_search_reader_iconv_encoding_streams_until_quit() {
	mut haystack := 'foo\n'.bytes()
	for _ in 0 .. 256 {
		haystack << 'x\n'.bytes()
	}
	mut source := LimitedChunkReaderForSearch.new(&haystack, 5, 16)
	mut builder := SearcherBuilder.new()
	encoding := Encoding.new('cp1251')!
	builder.encoding(encoding)
	builder.max_matches(u64(1))
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_reader(LiteralMatcher.new('foo'), mut source, &sink)!

	assert sink.matches == [
		'1:0:foo\n',
	]
	assert source.pos < 16
}

fn test_search_reader_shift_jis_preserves_one_byte_chunk_boundaries() {
	haystack := [u8(0x93), 0xfa, 0x96, 0x7b, `\n`]
	mut source := LimitedChunkReaderForSearch.new(&haystack, 1, haystack.len)
	mut builder := SearcherBuilder.new()
	builder.encoding(Encoding.new('shift_jis')!)
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_reader(LiteralMatcher.new('日本'), mut source, &sink)!
	assert sink.matches == ['1:0:日本\n']
}

fn test_search_reader_iso2022jp_preserves_state_across_one_byte_chunks() {
	haystack := [u8(0x1b), `$`, `B`, 0x24, 0x22, 0x1b, `(`, `B`, `\n`]
	mut source := LimitedChunkReaderForSearch.new(&haystack, 1, haystack.len)
	mut builder := SearcherBuilder.new()
	builder.encoding(Encoding.new('iso-2022-jp')!)
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_reader(LiteralMatcher.new('あ'), mut source, &sink)!
	assert sink.matches == ['1:0:あ\n']
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

fn test_search_slice_multi_line_heap_limit_applies_to_transcoded_bytes() {
	mut builder := SearcherBuilder.new()
	builder.multi_line(true)
	builder.heap_limit(usize(2))
	builder.encoding(Encoding.new('windows-1252')!)
	mut searcher_ := builder.build()
	mut sink := CollectSink{}
	searcher_.search_slice(LiteralMatcher.new('€'), [u8(0x80)], &sink) or {
		assert err.msg().contains('configured allocation limit')
		return
	}
	assert false
}
