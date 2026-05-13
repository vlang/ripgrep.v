module searcher

import matcher

interface IClone {}

/// A minimal translated surface for `grep-searcher` needed by `printer`
/// until the rest of the searcher crate is translated.

pub struct BinaryDetection implements IClone {
	quit_byte_ ?u8
}

pub fn BinaryDetection.none() BinaryDetection {
	return BinaryDetection{}
}

pub fn BinaryDetection.quit(byte u8) BinaryDetection {
	return BinaryDetection{
		quit_byte_: byte
	}
}

pub fn (d BinaryDetection) quit_byte() ?u8 {
	return d.quit_byte_
}

pub struct Searcher implements IClone {
mut:
	multi_line_       bool
	line_terminator_  matcher.LineTerminator
	binary_detection_ BinaryDetection
}

pub fn Searcher.new() Searcher {
	return Searcher{
		line_terminator_: matcher.LineTerminator.default()
	}
}

pub fn (s Searcher) multi_line_with_matcher[M](matcher_ M) bool {
	_ = matcher_
	return s.multi_line_
}

pub fn (s Searcher) line_terminator() matcher.LineTerminator {
	return s.line_terminator_
}

pub fn (s Searcher) binary_detection() BinaryDetection {
	return s.binary_detection_
}

pub fn (mut s Searcher) set_multi_line(yes bool) {
	s.multi_line_ = yes
}

pub fn (mut s Searcher) set_line_terminator(line_terminator matcher.LineTerminator) {
	s.line_terminator_ = line_terminator
}

pub fn (mut s Searcher) set_binary_detection(binary_detection BinaryDetection) {
	s.binary_detection_ = binary_detection
}

pub struct SinkFinish implements IClone {
	byte_count_         u64
	binary_byte_offset_ ?u64
}

pub fn SinkFinish.new(byte_count u64) SinkFinish {
	return SinkFinish{
		byte_count_: byte_count
	}
}

pub fn (finish SinkFinish) byte_count() u64 {
	return finish.byte_count_
}

pub fn (finish SinkFinish) binary_byte_offset() ?u64 {
	return finish.binary_byte_offset_
}

pub fn (finish SinkFinish) with_binary_byte_offset(binary_byte_offset ?u64) SinkFinish {
	return SinkFinish{
		byte_count_:         finish.byte_count_
		binary_byte_offset_: binary_byte_offset
	}
}

pub struct LineIter implements IClone {
	bytes_     []u8
	line_term_ u8
}

pub fn LineIter.new(bytes []u8, line_term u8) LineIter {
	return LineIter{
		bytes_:     bytes.clone()
		line_term_: line_term
	}
}

pub fn (iter LineIter) count() u64 {
	if iter.bytes_.len == 0 {
		return 0
	}
	mut count := u64(0)
	for byte in iter.bytes_ {
		if byte == iter.line_term_ {
			count++
		}
	}
	if iter.bytes_[iter.bytes_.len - 1] != iter.line_term_ {
		count++
	}
	return count
}

pub struct SinkMatch implements IClone {
	buffer_                []u8
	bytes_range_in_buffer_ matcher.Match
	absolute_byte_offset_  u64
	line_number_           ?u64
	line_term_             u8 = `\n`
}

pub fn SinkMatch.new(buffer []u8, bytes_range_in_buffer matcher.Match) SinkMatch {
	return SinkMatch{
		buffer_:                buffer.clone()
		bytes_range_in_buffer_: bytes_range_in_buffer
	}
}

pub fn (mat SinkMatch) with_absolute_byte_offset(absolute_byte_offset u64) SinkMatch {
	return SinkMatch{
		buffer_:                mat.buffer_.clone()
		bytes_range_in_buffer_: mat.bytes_range_in_buffer_
		absolute_byte_offset_:  absolute_byte_offset
		line_number_:           mat.line_number_
		line_term_:             mat.line_term_
	}
}

pub fn (mat SinkMatch) with_line_number(line_number ?u64) SinkMatch {
	return SinkMatch{
		buffer_:                mat.buffer_.clone()
		bytes_range_in_buffer_: mat.bytes_range_in_buffer_
		absolute_byte_offset_:  mat.absolute_byte_offset_
		line_number_:           line_number
		line_term_:             mat.line_term_
	}
}

pub fn (mat SinkMatch) with_line_term(line_term u8) SinkMatch {
	return SinkMatch{
		buffer_:                mat.buffer_.clone()
		bytes_range_in_buffer_: mat.bytes_range_in_buffer_
		absolute_byte_offset_:  mat.absolute_byte_offset_
		line_number_:           mat.line_number_
		line_term_:             line_term
	}
}

pub fn (mat SinkMatch) buffer() []u8 {
	return mat.buffer_.clone()
}

pub fn (mat SinkMatch) bytes_range_in_buffer() matcher.Match {
	return mat.bytes_range_in_buffer_
}

pub fn (mat SinkMatch) bytes() []u8 {
	return mat.buffer_[mat.bytes_range_in_buffer_.start()..mat.bytes_range_in_buffer_.end()].clone()
}

pub fn (mat SinkMatch) absolute_byte_offset() u64 {
	return mat.absolute_byte_offset_
}

pub fn (mat SinkMatch) line_number() ?u64 {
	return mat.line_number_
}

pub fn (mat SinkMatch) lines() LineIter {
	return LineIter.new(mat.bytes(), mat.line_term_)
}

pub interface Sink {
mut:
	matched(searcher Searcher, mat SinkMatch) !bool
	binary_data(searcher Searcher, binary_byte_offset u64) !bool
	begin(searcher Searcher) !bool
	finish(searcher Searcher, finish SinkFinish) !
}
