module searcher

import matcher

struct ReadByLine[^s, ^r, ^b] {
	config &^s Config
mut:
	core Core[^s]
	rdr  LineBufferReader[^r, ^b]
}

fn ReadByLine.new[^s, ^r, ^b](searcher_ &^s Searcher, matcher_ SearchMatcher, read_from LineBufferReader[^r, ^b], write_to Sink) ReadByLine[^s, ^r, ^b] {
	$if debug {
		assert !searcher_.multi_line_with_matcher(&matcher_)
	}
	return ReadByLine[^s, ^r, ^b]{
		config: &searcher_.config
		core:   Core.new(searcher_, matcher_, write_to, false)
		rdr:    read_from
	}
}

fn (mut search ReadByLine[^s, ^r, ^b]) run[^s, ^r, ^b]() ! {
	if search.core.begin()! {
		for search.fill()! {
			if !search.core.match_by_line(search.rdr.buffer())! {
				search.consume_remaining()
				break
			}
		}
	}
	search.core.finish(search.rdr.absolute_byte_offset(), search.rdr.binary_byte_offset())!
}

fn (mut search ReadByLine[^s, ^r, ^b]) consume_remaining[^s, ^r, ^b]() {
	consumed := search.core.pos()
	search.rdr.consume(consumed)
}

fn (mut search ReadByLine[^s, ^r, ^b]) fill[^s, ^r, ^b]() !bool {
	assert search.rdr.buffer()[search.core.pos()..].len == 0

	already_binary := search.rdr.binary_byte_offset() != none
	old_buf_len := search.rdr.buffer().len
	consumed := search.core.roll(search.rdr.buffer())
	search.rdr.consume(consumed)
	didread := search.rdr.fill()!
	if !already_binary {
		if offset := search.rdr.binary_byte_offset() {
			if !search.core.binary_data(offset)! {
				return false
			}
		}
	}
	if !didread || search.should_binary_quit() {
		return false
	}
	// If rolling the buffer didn't result in consuming anything and if
	// re-filling the buffer didn't add any bytes, then the only thing in
	// our buffer is leftover context, which we no longer need since there
	// is nothing left to search. So forcefully quit.
	if consumed == 0 && old_buf_len == search.rdr.buffer().len {
		search.rdr.consume(old_buf_len)
		return false
	}
	return true
}

fn (search ReadByLine[^s, ^r, ^b]) should_binary_quit[^s, ^r, ^b]() bool {
	return search.rdr.binary_byte_offset() != none && search.config.binary.quit_byte() != none
}

struct SliceByLine[^s] {
	slice &^s []u8
mut:
	core Core[^s]
}

fn SliceByLine.new[^s](searcher_ &^s Searcher, matcher_ SearchMatcher, slice &^s []u8, write_to Sink) SliceByLine[^s] {
	$if debug {
		assert !searcher_.multi_line_with_matcher(&matcher_)
	}
	return SliceByLine[^s]{
		core:  Core.new(searcher_, matcher_, write_to, true)
		slice: slice
	}
}

fn (mut search SliceByLine[^s]) run[^s]() ! {
	if search.core.begin()! {
		binary_upto := if search.slice.len < int(default_buffer_capacity) {
			search.slice.len
		} else {
			int(default_buffer_capacity)
		}
		binary_range := matcher.Match.new(0, usize(binary_upto))
		if !search.core.detect_binary(search.slice, binary_range)! {
			for search.core.pos() < search.slice.len && search.core.match_by_line(search.slice)! {}
		}
	}
	byte_count := search.byte_count()
	binary_byte_offset := search.core.binary_byte_offset()
	search.core.finish(byte_count, binary_byte_offset)!
}

fn (mut search SliceByLine[^s]) byte_count[^s]() u64 {
	if offset := search.core.binary_byte_offset() {
		if offset < u64(search.core.pos()) {
			return offset
		}
	}
	return u64(search.core.pos())
}

struct MultiLine[^s] {
	config &^s Config
	slice  &^s []u8
mut:
	core       Core[^s]
	last_match ?matcher.Match
}

fn MultiLine.new[^s](searcher_ &^s Searcher, matcher_ SearchMatcher, slice &^s []u8, write_to Sink) MultiLine[^s] {
	$if debug {
		assert searcher_.multi_line_with_matcher(&matcher_)
	}
	return MultiLine[^s]{
		config: &searcher_.config
		core:   Core.new(searcher_, matcher_, write_to, true)
		slice:  slice
	}
}

fn (mut search MultiLine[^s]) run[^s]() ! {
	if search.core.begin()! {
		binary_upto := if search.slice.len < int(default_buffer_capacity) {
			search.slice.len
		} else {
			int(default_buffer_capacity)
		}
		binary_range := matcher.Match.new(0, usize(binary_upto))
		if !search.core.detect_binary(search.slice, binary_range)! {
			mut keepgoing := true
			for search.core.pos() < search.slice.len && keepgoing {
				keepgoing = search.sink()!
			}
			if keepgoing {
				if last_match := search.last_match {
					if search.sink_context(last_match)! {
						search.sink_matched(last_match)!
					}
					search.last_match = none
				}
			}
			// Take care of any remaining context after the last match.
			if keepgoing {
				if search.config.passthru {
					search.core.other_context_by_line(search.slice, search.slice.len)!
				} else {
					search.core.after_context_by_line(search.slice, search.slice.len)!
				}
			}
		}
	}
	byte_count := search.byte_count()
	binary_byte_offset := search.core.binary_byte_offset()
	search.core.finish(byte_count, binary_byte_offset)!
}

fn (mut search MultiLine[^s]) sink[^s]() !bool {
	if search.config.invert_match {
		return search.sink_matched_inverted()!
	}
	maybe_mat := search.find()!
	mat := maybe_mat.get() or {
		search.core.set_pos(search.slice.len)
		return true
	}
	search.advance(mat)

	line := locate(search.slice, search.config.line_term.as_byte(), mat)
	// We delay sinking the match to make sure we group adjacent matches
	// together in a single sink. Adjacent matches are distinct matches
	// that start and end on the same line, respectively. This guarantees
	// that a single line is never sinked more than once.
	if last_match := search.last_match {
		// If the lines in the previous match overlap with the lines
		// in this match, then simply grow the match and move on. This
		// happens when the next match begins on the same line that the
		// last match ends on.
		//
		// Note that we do not technically require strict overlap here.
		// Instead, we only require that the lines are adjacent. This
		// provides larger blocks of lines to the printer, and results
		// in overall better behavior with respect to how replacements
		// are handled.
		//
		// See: https://github.com/BurntSushi/ripgrep/issues/1311
		// And also the associated commit fixing #1311.
		if last_match.end() >= line.start() {
			search.last_match = last_match.with_end(line.end())
			return true
		}
		search.last_match = line
		if !search.sink_context(last_match)! {
			return false
		}
		return search.sink_matched(last_match)!
	}
	search.last_match = line
	return true
}

fn (mut search MultiLine[^s]) sink_matched_inverted[^s]() !bool {
	assert search.config.invert_match

	maybe_mat := search.find()!
	invert_match := if mat := maybe_mat.get() {
		line := locate(search.slice, search.config.line_term.as_byte(), mat)
		range := matcher.Match.new(search.core.pos(), line.start())
		search.advance(line)
		range
	} else {
		range := matcher.Match.new(search.core.pos(), search.slice.len)
		search.core.set_pos(range.end())
		range
	}
	if invert_match.is_empty() {
		return true
	}
	if !search.sink_context(invert_match)! {
		return false
	}
	mut stepper := LineStep.new(search.config.line_term.as_byte(), invert_match.start(), invert_match.end())
	for {
		line := stepper.next_match(search.slice) or { break }
		if !search.sink_matched(line)! {
			return false
		}
	}
	return true
}

fn (mut search MultiLine[^s]) sink_matched[^s](range matcher.Match) !bool {
	if range.is_empty() {
		// The only way we can produce an empty line for a match is if we
		// match the position immediately following the last byte that we
		// search, and where that last byte is also the line terminator. We
		// never want to report that match, and we know we're done at that
		// point anyway, so stop the search.
		return false
	}
	return search.core.matched(search.slice, range)!
}

fn (mut search MultiLine[^s]) sink_context[^s](range matcher.Match) !bool {
	if search.config.passthru {
		if !search.core.other_context_by_line(search.slice, range.start())! {
			return false
		}
	} else {
		if !search.core.after_context_by_line(search.slice, range.start())! {
			return false
		}
		if !search.core.before_context_by_line(search.slice, range.start())! {
			return false
		}
	}
	return true
}

fn (mut search MultiLine[^s]) find[^s]() !matcher.FallibleMatch {
	maybe_match := search.core.find(search.slice[search.core.pos()..])!
	if mat := maybe_match.get() {
		return matcher.FallibleMatch.some(mat.offset(search.core.pos()))
	}
	return matcher.FallibleMatch.absent()
}

/// Advance the search position based on the previous match.
///
/// If the previous match is zero width, then this advances the search
/// position one byte past the end of the match.
fn (mut search MultiLine[^s]) advance[^s](range matcher.Match) {
	search.core.set_pos(range.end())
	if range.is_empty() && search.core.pos() < search.slice.len {
		newpos := search.core.pos() + 1
		search.core.set_pos(newpos)
	}
}

fn (mut search MultiLine[^s]) byte_count[^s]() u64 {
	if offset := search.core.binary_byte_offset() {
		if offset < u64(search.core.pos()) {
			return offset
		}
	}
	return u64(search.core.pos())
}
