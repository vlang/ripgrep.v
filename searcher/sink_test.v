module searcher

import matcher

struct MinimalSink {
	SinkDefaults
mut:
	matched_count int
}

fn (mut sink MinimalSink) matched[^b](searcher_ &Searcher, mat &SinkMatch[^b]) !bool {
	_ = searcher_
	_ = mat
	sink.matched_count++
	return true
}

fn exercise_sink_defaults(mut sink Sink) ! {
	searcher_ := Searcher.new()
	bytes := 'x\n'.bytes()
	ctx := SinkContext.new(matcher.LineTerminator.byte(`\n`), bytes, .other, u64(0), none)
	finish := SinkFinish.new(u64(bytes.len))
	assert sink.context(&searcher_, &ctx)!
	assert sink.context_break(&searcher_)!
	assert sink.binary_data(&searcher_, u64(1))!
	assert sink.begin(&searcher_)!
	sink.finish(&searcher_, &finish)!
}

fn test_sink_defaults_supply_optional_behavior() {
	mut sink := MinimalSink{}
	exercise_sink_defaults(mut sink)!
}

fn test_sink_match_accessors_borrow_the_search_buffer() {
	mut input := [u8(`a`), `b`, `c`, `\n`]
	mat := SinkMatch.new(input, matcher.Match.new(1, 3))
	input[1] = `x`
	input[2] = `y`

	assert mat.buffer().bytestr() == 'axy\n'
	assert mat.bytes().bytestr() == 'xy'
}

fn test_sink_context_accessors_borrow_the_search_buffer() {
	mut input := [u8(`a`), `b`, `c`, `\n`]
	ctx := SinkContext.new(matcher.LineTerminator.byte(`\n`), input[1..], .before, u64(9),
		u64(2))
	input[1] = `x`

	assert ctx.bytes().bytestr() == 'xc\n'
	assert *ctx.kind() == .before
	assert ctx.absolute_byte_offset() == 9
	assert ctx.line_number() == ?u64(2)
	assert ctx.lines().count() == 1
}

fn test_utf8_sink_reports_utf8_match() {
	mut got_line := u64(0)
	mut got_text := ''
	mut sink := UTF8.new(fn [mut got_line, mut got_text] (line u64, text string) !bool {
		got_line = line
		got_text = text.to_owned()
		return true
	})
	mat := SinkMatch.new('abc\n'.bytes(), matcher.Match.new(0, 4)).with_line_number(u64(7))
	searcher_ := Searcher.new()

	assert sink.matched(&searcher_, &mat)!
	assert got_line == 7
	assert got_text == 'abc\n'
}

fn test_utf8_sink_rejects_invalid_utf8() {
	mut sink := UTF8.new(fn (line u64, text string) !bool {
		_ = line
		_ = text
		return true
	})
	bytes := [u8(`a`), 0xff, `b`]
	mat := SinkMatch.new(bytes, matcher.Match.new(0, bytes.len)).with_line_number(u64(1))
	searcher_ := Searcher.new()

	sink.matched(&searcher_, &mat) or {
		assert err.msg() == 'invalid utf-8 sequence of 1 bytes from index 1'
		return
	}
	assert false
}

fn test_utf8_sink_reports_incomplete_utf8() {
	mut sink := UTF8.new(fn (line u64, text string) !bool {
		_ = line
		_ = text
		return true
	})
	bytes := [u8(`a`), 0xe2, 0x82]
	mat := SinkMatch.new(bytes, matcher.Match.new(0, bytes.len)).with_line_number(u64(1))
	searcher_ := Searcher.new()

	sink.matched(&searcher_, &mat) or {
		assert err.msg() == 'incomplete utf-8 byte sequence from index 1'
		return
	}
	assert false
}

fn test_utf8_sink_requires_line_numbers() {
	mut sink := UTF8.new(fn (line u64, text string) !bool {
		_ = line
		_ = text
		return true
	})
	mat := SinkMatch.new('abc'.bytes(), matcher.Match.new(0, 3))
	searcher_ := Searcher.new()

	sink.matched(&searcher_, &mat) or {
		assert err.msg() == 'line numbers not enabled'
		return
	}
	assert false
}

fn test_lossy_sink_replaces_invalid_utf8() {
	mut got_line := u64(0)
	mut got_bytes := []u8{}
	mut sink := Lossy.new(fn [mut got_line, mut got_bytes] (line u64, text string) !bool {
		got_line = line
		got_bytes = text.bytes()
		return true
	})
	bytes := [u8(`a`), 0xff, `b`]
	mat := SinkMatch.new(bytes, matcher.Match.new(0, bytes.len)).with_line_number(u64(3))
	searcher_ := Searcher.new()

	assert sink.matched(&searcher_, &mat)!
	assert got_line == 3
	assert got_bytes == [u8(`a`), 0xef, 0xbf, 0xbd, `b`]
}

fn test_lossy_sink_replaces_incomplete_sequence_once() {
	mut got_bytes := []u8{}
	mut sink := Lossy.new(fn [mut got_bytes] (_line u64, text string) !bool {
		got_bytes = text.bytes()
		return true
	})
	bytes := [u8(`a`), 0xe2, 0x82]
	mat := SinkMatch.new(bytes, matcher.Match.new(0, bytes.len)).with_line_number(u64(3))
	searcher_ := Searcher.new()

	assert sink.matched(&searcher_, &mat)!
	assert got_bytes == [u8(`a`), 0xef, 0xbf, 0xbd]
}

fn test_bytes_sink_reports_raw_bytes() {
	mut got_line := u64(0)
	mut got_bytes := []u8{}
	mut sink := Bytes.new(fn [mut got_line, mut got_bytes] (line u64, bytes []u8) !bool {
		got_line = line
		got_bytes = bytes.clone()
		return true
	})
	bytes := [u8(`a`), 0xff, `b`]
	mat := SinkMatch.new(bytes, matcher.Match.new(0, bytes.len)).with_line_number(u64(9))
	searcher_ := Searcher.new()

	assert sink.matched(&searcher_, &mat)!
	assert got_line == 9
	assert got_bytes == bytes
}
