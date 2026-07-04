module searcher

import matcher

fn test_utf8_sink_reports_utf8_match() {
	mut got_line := u64(0)
	mut got_text := ''
	mut sink := UTF8.new(fn [mut got_line, mut got_text] (line u64, text string) !bool {
		got_line = line
		got_text = text.to_owned()
		return true
	})
	mat := SinkMatch.new('abc\n'.bytes(), matcher.Match.new(0, 4)).with_line_number(u64(7))

	assert sink.matched(Searcher.new(), mat)!
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

	sink.matched(Searcher.new(), mat) or {
		assert err.msg() == 'invalid UTF-8 in search match'
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

	sink.matched(Searcher.new(), mat) or {
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

	assert sink.matched(Searcher.new(), mat)!
	assert got_line == 3
	assert got_bytes == [u8(`a`), 0xef, 0xbf, 0xbd, `b`]
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

	assert sink.matched(Searcher.new(), mat)!
	assert got_line == 9
	assert got_bytes == bytes
}
