module printer

import matcher
import searcher
import time

/// The configuration for the JSON printer.
///
/// This is manipulated by the JSONBuilder and then referenced by the actual
/// implementation. Once a printer is build, the configuration is frozen and
/// cannot changed.
struct JSONConfig implements IClone {
mut:
	pretty           bool
	always_begin_end bool
	replacement      ?[]u8
}

fn (config JSONConfig) clone() JSONConfig {
	mut replacement := ?[]u8(none)
	if value := config.replacement {
		replacement = json_clone_u8_range(value, 0, value.len)
	}
	return JSONConfig{
		pretty:           config.pretty
		always_begin_end: config.always_begin_end
		replacement:      replacement
	}
}

fn json_clone_u8_range(bytes []u8, start usize, end usize) []u8 {
	mut cloned := []u8{cap: int(end - start)}
	for i := start; i < end; i++ {
		cloned << bytes[i]
	}
	return cloned
}

/// A builder for a JSON lines printer.
///
/// The builder permits configuring how the printer behaves. The JSON printer
/// has fewer configuration options than the standard printer because it is
/// a structured format, and the printer always attempts to find the most
/// information possible.
pub struct JSONBuilder implements IClone {
mut:
	config JSONConfig
}

/// Return a new builder for configuring the JSON printer.
pub fn JSONBuilder.new() JSONBuilder {
	return JSONBuilder{}
}

/// Create a JSON printer that writes results to the given writer.
pub fn (builder JSONBuilder) build[W](wtr W) JSON[W] {
	return JSON[W]{
		config:  builder.config.clone()
		wtr:     CounterWriter.new(wtr)
		matches: []matcher.Match{}
	}
}

/// Print JSON in a pretty printed format.
///
/// Enabling this will no longer produce a "JSON lines" format, in that
/// each JSON object printed may span multiple lines.
///
/// This is disabled by default.
pub fn (mut builder JSONBuilder) pretty(yes bool) &JSONBuilder {
	builder.config.pretty = yes
	return builder
}

/// When enabled, the `begin` and `end` messages are always emitted, even
/// when no match is found.
pub fn (mut builder JSONBuilder) always_begin_end(yes bool) &JSONBuilder {
	builder.config.always_begin_end = yes
	return builder
}

/// Set the bytes that will be used to replace each occurrence of a match
/// found.
pub fn (mut builder JSONBuilder) replacement(replacement ?[]u8) &JSONBuilder {
	if repl := replacement {
		builder.config.replacement = repl.clone()
	} else {
		builder.config.replacement = none
	}
	return builder
}

/// The JSON printer, which emits results in a JSON lines format.
pub struct JSON[W] {
	config JSONConfig
mut:
	wtr     CounterWriter[W]
	matches []matcher.Match
}

/// Return a JSON lines printer with a default configuration that writes
/// matches to the given writer.
pub fn JSON.new[W](wtr W) JSON[W] {
	return JSONBuilder.new().build(wtr)
}

/// Return an implementation of `Sink` for the JSON printer.
///
/// This does not associate the printer with a file path, which means this
/// implementation will never print a file path along with the matches.
pub fn (mut json JSON[W]) sink[^s](matcher_ PrinterMatcher) JSONSink[^s, ^s, W] {
	return JSONSink[^s, ^s, W]{
		matcher:    matcher_
		replacer:   Replacer{}
		json:       &json
		path:       none
		start_time: time.now()
		stats_:     Stats.new()
	}
}

/// Return an implementation of `Sink` associated with a file path.
///
/// When the printer is associated with a path, then it may, depending on
/// its configuration, print the path along with the matches found.
pub fn (mut json JSON[W]) sink_with_path[^p, ^s](matcher_ PrinterMatcher, path &^p string) JSONSink[^p, ^s, W] {
	return JSONSink[^p, ^s, W]{
		matcher:    matcher_
		replacer:   Replacer{}
		json:       &json
		path:       (*path).to_owned()
		start_time: time.now()
		stats_:     Stats.new()
	}
}

/// Write the given message followed by a new line. The new line is
/// determined from the configuration of the given searcher.
fn (mut json JSON[W]) write_message(message Message) ! {
	_ = json.config.pretty
	json.write(message.to_json().bytes())!
	json.write([u8(`\n`)])!
}

/// Returns true if and only if this printer has written at least one byte
/// to the underlying writer during any of the previous searches.
pub fn (json JSON[W]) has_written() bool {
	return json.wtr.total_count() > 0
}

/// Return a mutable reference to the underlying writer.
pub fn (mut json JSON[W]) get_mut() &W {
	return json.wtr.get_mut()
}

/// Flush the underlying writer.
pub fn (mut json JSON[W]) flush() ! {
	json.wtr.flush()!
}

/// Consume this printer and return back ownership of the underlying
/// writer.
pub fn (mut json JSON[W]) into_inner() W {
	return json.wtr.into_inner()
}

fn (mut json JSON[W]) write(buf []u8) ! {
	mut written := usize(0)
	for written < buf.len {
		n := json.wtr.write(buf[written..])!
		if n <= 0 {
			return error('failed to write all bytes')
		}
		written += usize(n)
	}
}

/// An implementation of `Sink` associated with a matcher and an optional file
/// path for the JSON printer.
pub struct JSONSink[^p, ^s, W] {
	matcher PrinterMatcher
mut:
	replacer           Replacer
	json               &^s JSON[W]
	// V-specific: the JSON message path is stored owned so messages can be
	// materialized without carrying an optional reference through the emitter.
	path               ?string
	start_time         time.Time
	match_count_       u64
	binary_byte_offset ?u64
	begin_printed      bool
	stats_             Stats
}

/// Returns true if and only if this printer received a match in the
/// previous search.
pub fn (sink JSONSink[^p, ^s, W]) has_match[^p, ^s]() bool {
	return sink.match_count_ > 0
}

/// Return the total number of matches reported to this sink.
pub fn (sink JSONSink[^p, ^s, W]) match_count[^p, ^s]() u64 {
	return sink.match_count_
}

/// If binary data was found in the previous search, this returns the
/// offset at which the binary data was first detected.
pub fn (sink JSONSink[^p, ^s, W]) binary_byte_offset[^p, ^s]() ?u64 {
	return sink.binary_byte_offset
}

/// Return a reference to the stats produced by the printer for all
/// searches executed on this sink.
pub fn (sink &^a JSONSink[^p, ^s, W]) stats[^a, ^p, ^s]() &^a Stats {
	return unsafe { &sink.stats_ }
}

fn (mut sink JSONSink[^p, ^s, W]) record_matches[^p, ^s](searcher_ searcher.Searcher, bytes []u8, range matcher.Match) ! {
	mut matches := []matcher.Match{}
	find_iter_at_in_context(searcher_, sink.matcher, bytes, range, fn [range, mut matches] (m matcher.Match) bool {
		s := m.start() - range.start()
		e := m.end() - range.start()
		matches << match_new(s, e)
		return true
	})!
	if matches.len > 0 {
		last := matches[matches.len - 1]
		if last.is_empty() && last.start() >= bytes.len {
			matches.delete(matches.len - 1)
		}
	}
	sink.json.matches = matches
}

fn (mut sink JSONSink[^p, ^s, W]) replace[^p, ^s](searcher_ searcher.Searcher, bytes []u8, range matcher.Match) ! {
	sink.replacer.clear()
	if replacement := sink.json.config.replacement {
		sink.replacer.replace_all(searcher_, sink.matcher, bytes, range, replacement)!
	}
}

fn (mut sink JSONSink[^p, ^s, W]) write_begin_message[^p, ^s]() ! {
	if sink.begin_printed {
		return
	}
	msg := Message.begin(Begin{
		path: sink.path_value()
	})
	sink.json.write_message(msg)!
	sink.begin_printed = true
}

fn (sink &JSONSink[^p, ^s, W]) path_value[^p, ^s]() ?string {
	if path := sink.path {
		return path.clone()
	}
	return none
}

pub fn (mut sink JSONSink[^p, ^s, W]) matched[^p, ^s](searcher_ searcher.Searcher, mat searcher.SinkMatch) !bool {
	sink.match_count_++
	sink.write_begin_message()!
	sink.record_matches(searcher_, mat.buffer(), mat.bytes_range_in_buffer())!
	sink.replace(searcher_, mat.buffer(), mat.bytes_range_in_buffer())!
	sink.stats_.add_matches(u64(sink.json.matches.len))
	sink.stats_.add_matched_lines(mat.lines().count())
	submatches := json_submatches(mat.bytes(), sink.json.matches, sink.replacer.replacement())
	msg := Message.match_(MatchMessage{
		path:            sink.path_value()
		lines:           mat.bytes()
		line_number:     mat.line_number()
		absolute_offset: mat.absolute_byte_offset()
		submatches:      submatches
	})
	sink.json.write_message(msg)!
	return true
}

pub fn (mut sink JSONSink[^p, ^s, W]) context[^p, ^s](searcher_ searcher.Searcher, ctx searcher.SinkContext) !bool {
	sink.write_begin_message()!
	sink.json.matches.clear()
	mut submatches := []SubMatch{}
	if searcher_.invert_match() {
		full_range := matcher.Match.new(0, ctx.bytes().len)
		sink.record_matches(searcher_, ctx.bytes(), full_range)!
		sink.replace(searcher_, ctx.bytes(), full_range)!
		submatches = json_submatches(ctx.bytes(), sink.json.matches, sink.replacer.replacement())
	}
	msg := Message.context(Context{
		path:            sink.path_value()
		lines:           ctx.bytes()
		line_number:     ctx.line_number()
		absolute_offset: ctx.absolute_byte_offset()
		submatches:      submatches
	})
	sink.json.write_message(msg)!
	return true
}

pub fn (mut sink JSONSink[^p, ^s, W]) context_break[^p, ^s](searcher_ searcher.Searcher) !bool {
	_ = sink
	_ = searcher_
	return true
}

pub fn (mut sink JSONSink[^p, ^s, W]) binary_data[^p, ^s](searcher_ searcher.Searcher, binary_byte_offset u64) !bool {
	_ = searcher_
	sink.binary_byte_offset = binary_byte_offset
	return true
}

pub fn (mut sink JSONSink[^p, ^s, W]) begin[^p, ^s](_searcher searcher.Searcher) !bool {
	sink.json.wtr.reset_count()
	sink.start_time = time.now()
	sink.match_count_ = 0
	sink.binary_byte_offset = none
	sink.begin_printed = false
	sink.stats_ = Stats.new()
	if !sink.json.config.always_begin_end {
		return true
	}
	sink.write_begin_message()!
	return true
}

pub fn (mut sink JSONSink[^p, ^s, W]) finish[^p, ^s](_searcher searcher.Searcher, finish searcher.SinkFinish) ! {
	sink.binary_byte_offset = finish.binary_byte_offset()
	sink.stats_.add_elapsed(time.since(sink.start_time))
	sink.stats_.add_searches(1)
	if sink.match_count_ > 0 {
		sink.stats_.add_searches_with_match(1)
	}
	sink.stats_.add_bytes_searched(finish.byte_count())
	sink.stats_.add_bytes_printed(sink.json.wtr.count())
	if !sink.begin_printed {
		return
	}
	msg := Message.end(End{
		path:          sink.path_value()
		binary_offset: finish.binary_byte_offset()
		stats:         sink.stats_.clone()
	})
	sink.json.write_message(msg)!
}

fn json_submatches(bytes []u8, matches []matcher.Match, replacement ?Replacement) []SubMatch {
	mut submatches := []SubMatch{cap: matches.len}
	for i, mat in matches {
		mut repl := ?[]u8(none)
		if r := replacement {
			if i < r.matches.len {
				rmat := r.matches[i]
				repl = json_clone_u8_range(r.bytes, rmat.start(), rmat.end())
			}
		}
		submatches << SubMatch{
			m:           json_clone_u8_range(bytes, mat.start(), mat.end())
			replacement: repl
			start:       mat.start()
			end:         mat.end()
		}
	}
	return submatches
}
