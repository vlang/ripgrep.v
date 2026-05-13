import matcher
import printer
import searcher

struct DummyWriter {
mut:
	data []u8
}

pub fn (mut w DummyWriter) write(buf []u8) !int {
	w.data << buf
	return buf.len
}

struct DummyMatcher {}

pub fn (m DummyMatcher) find_at(haystack []u8, at usize) !matcher.FallibleOption[matcher.Match] {
	for i := at; i + 4 <= haystack.len; i++ {
		if haystack[i..i + 4].bytestr() == 'test' {
			return matcher.FallibleOption.some(matcher.Match.new(i, i + 4))
		}
	}
	return matcher.FallibleOption.absent[matcher.Match]()
}

pub fn (m DummyMatcher) new_captures() !matcher.NoCaptures {
	return matcher.NoCaptures.new()
}

pub fn (m DummyMatcher) capture_count() usize {
	return matcher.default_capture_count()
}

pub fn (m DummyMatcher) capture_index(name string) ?usize {
	return matcher.default_capture_index(name)
}

pub fn (m DummyMatcher) captures_at(haystack []u8, at usize, mut caps matcher.NoCaptures) !bool {
	return matcher.default_captures_at(haystack, at, mut caps)
}

pub fn (m DummyMatcher) non_matching_bytes() ?&matcher.ByteSet {
	return matcher.default_non_matching_bytes()
}

pub fn (m DummyMatcher) line_terminator() ?matcher.LineTerminator {
	return matcher.default_line_terminator()
}

pub fn (m DummyMatcher) find_candidate_line(haystack []u8) !matcher.FallibleOption[matcher.LineMatchKind] {
	return matcher.default_find_candidate_line(m, haystack)
}

fn main() {
	mut summary := printer.SummaryBuilder.new().build_no_color(DummyWriter{})
	mut sink := summary.sink(DummyMatcher{})
	search := searcher.Searcher.new()
	_ := sink.begin(search)!
	_ := sink.matched(search, searcher.SinkMatch.new('test\n'.bytes(), matcher.Match.new(0, 4)))!
	sink.finish(search, searcher.SinkFinish.new(5))!
}
