module printer

import log
import matcher
import searcher
import time

/// The configuration for the standard printer.
///
/// This is manipulated by the StandardBuilder and then referenced by the
/// actual implementation. Once a printer is build, the configuration is frozen
/// and cannot changed.
struct StandardConfig implements IClone {
mut:
	colors                  ColorSpecs
	hyperlink               HyperlinkConfig
	stats                   bool
	heading                 bool
	path                    bool
	only_matching           bool
	per_match               bool
	per_match_one_line      bool
	replacement             ?[]u8
	max_columns             ?u64
	max_columns_preview     bool
	column                  bool
	byte_offset             bool
	trim_ascii              bool
	separator_search        ?[]u8
	separator_context       ?[]u8
	separator_field_match   []u8
	separator_field_context []u8
	separator_path          ?u8
	path_terminator         ?u8
}

/// A builder for the "standard" grep-like printer.
///
/// The builder permits configuring how the printer behaves. Configurable
/// behavior includes, but is not limited to, limiting the number of matches,
/// tweaking separators, executing pattern replacements, recording statistics
/// and setting colors.
///
/// Some configuration options, such as the display of line numbers or
/// contextual lines, are drawn directly from the
/// `grep_searcher::Searcher`'s configuration.
///
/// Once a `Standard` printer is built, its configuration cannot be changed.
pub struct StandardBuilder implements IClone {
mut:
	config StandardConfig
}

/// Return a new builder for configuring the standard printer.
pub fn StandardBuilder.new() StandardBuilder {
	return StandardBuilder{
		config: StandardConfig{
			colors:                  ColorSpecs{}
			hyperlink:               HyperlinkConfig{}
			stats:                   false
			heading:                 false
			path:                    true
			only_matching:           false
			per_match:               false
			per_match_one_line:      false
			replacement:             none
			max_columns:             none
			max_columns_preview:     false
			column:                  false
			byte_offset:             false
			trim_ascii:              false
			separator_search:        none
			separator_context:       [u8(`-`), `-`]
			separator_field_match:   [u8(`:`)]
			separator_field_context: [u8(`-`)]
			separator_path:          none
			path_terminator:         none
		}
	}
}

/// Build a printer using any implementation of `termcolor::WriteColor`.
///
/// The implementation of `WriteColor` used here controls whether colors
/// are used or not when colors have been configured using the
/// `color_specs` method.
pub fn (builder StandardBuilder) build[W](wtr W) Standard[W] {
	return Standard[W]{
		config:  builder.config.clone()
		wtr:     CounterWriter.new(wtr)
		matches: []matcher.Match{}
	}
}

/// Build a printer from any implementation of `io::Write` and never emit
/// any colors, regardless of the user color specification settings.
///
/// This is a convenience routine for
/// `StandardBuilder::build(termcolor::NoColor::new(wtr))`.
pub fn (builder StandardBuilder) build_no_color[W](wtr W) Standard[NoColor[W]] {
	return builder.build(NoColor.new(wtr))
}

/// Set the user color specifications to use for coloring in this printer.
///
/// This completely overrides any previous color specifications. This does
/// not add to any previously provided color specifications on this
/// builder.
pub fn (mut builder StandardBuilder) color_specs(specs ColorSpecs) &StandardBuilder {
	builder.config.colors = specs
	return builder
}

/// Set the configuration to use for hyperlinks output by this printer.
///
/// This completely overrides any previous hyperlink format.
///
/// The default configuration results in not emitting any hyperlinks.
pub fn (mut builder StandardBuilder) hyperlink(config HyperlinkConfig) &StandardBuilder {
	builder.config.hyperlink = config
	return builder
}

/// Enable the gathering of various aggregate statistics.
pub fn (mut builder StandardBuilder) stats(yes bool) &StandardBuilder {
	builder.config.stats = yes
	return builder
}

/// Enable the use of "headings" in the printer.
pub fn (mut builder StandardBuilder) heading(yes bool) &StandardBuilder {
	builder.config.heading = yes
	return builder
}

/// When enabled, if a path was given to the printer, then it is shown in
/// the output (either as a heading or as a prefix to each matching line).
pub fn (mut builder StandardBuilder) path(yes bool) &StandardBuilder {
	builder.config.path = yes
	return builder
}

/// Only print the specific matches instead of the entire line containing
/// each match.
pub fn (mut builder StandardBuilder) only_matching(yes bool) &StandardBuilder {
	builder.config.only_matching = yes
	return builder
}

/// Print at least one line for every match.
pub fn (mut builder StandardBuilder) per_match(yes bool) &StandardBuilder {
	builder.config.per_match = yes
	return builder
}

/// Print at most one line per match when `per_match` is enabled.
pub fn (mut builder StandardBuilder) per_match_one_line(yes bool) &StandardBuilder {
	builder.config.per_match_one_line = yes
	return builder
}

/// Set the bytes that will be used to replace each occurrence of a match
/// found.
pub fn (mut builder StandardBuilder) replacement(replacement ?[]u8) &StandardBuilder {
	if repl := replacement {
		builder.config.replacement = repl.clone()
	} else {
		builder.config.replacement = none
	}
	return builder
}

/// Set the maximum number of columns allowed for each line printed. A
/// single column is heuristically defined as a single byte.
pub fn (mut builder StandardBuilder) max_columns(limit ?u64) &StandardBuilder {
	builder.config.max_columns = limit
	return builder
}

/// When enabled, if a line is found to be over the configured maximum
/// column limit (measured in terms of bytes), then a preview of the long
/// line will be printed instead.
pub fn (mut builder StandardBuilder) max_columns_preview(yes bool) &StandardBuilder {
	builder.config.max_columns_preview = yes
	return builder
}

/// Print the column number of the first match in a line.
pub fn (mut builder StandardBuilder) column(yes bool) &StandardBuilder {
	builder.config.column = yes
	return builder
}

/// Print the absolute byte offset of the beginning of each line printed.
pub fn (mut builder StandardBuilder) byte_offset(yes bool) &StandardBuilder {
	builder.config.byte_offset = yes
	return builder
}

/// When enabled, all lines will have prefix ASCII whitespace trimmed
/// before being written.
pub fn (mut builder StandardBuilder) trim_ascii(yes bool) &StandardBuilder {
	builder.config.trim_ascii = yes
	return builder
}

/// Set the separator used between sets of search results.
pub fn (mut builder StandardBuilder) separator_search(sep ?[]u8) &StandardBuilder {
	if value := sep {
		builder.config.separator_search = value.clone()
	} else {
		builder.config.separator_search = none
	}
	return builder
}

/// Set the separator used between discontiguous runs of search context,
/// but only when the searcher is configured to report contextual lines.
pub fn (mut builder StandardBuilder) separator_context(sep ?[]u8) &StandardBuilder {
	if value := sep {
		builder.config.separator_context = value.clone()
	} else {
		builder.config.separator_context = none
	}
	return builder
}

/// Set the separator used between fields emitted for matching lines.
pub fn (mut builder StandardBuilder) separator_field_match(sep []u8) &StandardBuilder {
	builder.config.separator_field_match = sep.clone()
	return builder
}

/// Set the separator used between fields emitted for context lines.
pub fn (mut builder StandardBuilder) separator_field_context(sep []u8) &StandardBuilder {
	builder.config.separator_field_context = sep.clone()
	return builder
}

/// Set the path separator used when printing file paths.
pub fn (mut builder StandardBuilder) separator_path(sep ?u8) &StandardBuilder {
	builder.config.separator_path = sep
	return builder
}

/// Set the path terminator used.
///
/// The path terminator is a byte that is printed after every file path
/// emitted by this printer.
pub fn (mut builder StandardBuilder) path_terminator(terminator ?u8) &StandardBuilder {
	builder.config.path_terminator = terminator
	return builder
}

/// The standard printer, which implements grep-like formatting, including
/// color support.
pub struct Standard[W] {
	config StandardConfig
mut:
	wtr     CounterWriter[W]
	matches []matcher.Match
}

/// Return a standard printer with a default configuration that writes
/// matches to the given writer.
pub fn Standard.new[W](wtr W) Standard[W] {
	return StandardBuilder.new().build(wtr)
}

/// Return a standard printer with a default configuration that writes
/// matches to the given writer.
pub fn Standard.new_no_color[W](wtr W) Standard[NoColor[W]] {
	return StandardBuilder.new().build_no_color(wtr)
}

/// Return an implementation of `Sink` for the standard printer.
pub fn (mut standard Standard[W]) sink[^s](matcher_ PrinterMatcher) StandardSink[^s, ^s, W] {
	mut stats := ?Stats(none)
	if standard.config.stats {
		stats = Stats.new()
	}
	return StandardSink[^s, ^s, W]{
		matcher:                 matcher_
		standard:                &standard
		replacer:                Replacer{}
		interpolator:            Interpolator.new(standard.config.hyperlink)
		path:                    none
		start_time:              time.now()
		match_count:             0
		binary_byte_offset:      none
		stats:                   stats
		needs_match_granularity: standard.needs_match_granularity()
	}
}

/// Return an implementation of `Sink` associated with a file path.
pub fn (mut standard Standard[W]) sink_with_path[^p, ^s](matcher_ PrinterMatcher, path &^p string) StandardSink[^p, ^s, W] {
	if !standard.config.path {
		return standard.sink(matcher_)
	}
	mut stats := ?Stats(none)
	if standard.config.stats {
		stats = Stats.new()
	}
	ppath := PrinterPath.new(path).with_separator(standard.config.separator_path)
	return StandardSink[^p, ^s, W]{
		matcher:                 matcher_
		standard:                &standard
		replacer:                Replacer{}
		interpolator:            Interpolator.new(standard.config.hyperlink)
		path:                    ppath
		start_time:              time.now()
		match_count:             0
		binary_byte_offset:      none
		stats:                   stats
		needs_match_granularity: standard.needs_match_granularity()
	}
}

/// Returns true if and only if the configuration of the printer requires
/// us to find each individual match in the lines reported by the searcher.
fn (standard Standard[W]) needs_match_granularity() bool {
	mut supports_color := false
	$if W is WriteColor {
		supports_color = standard.wtr.wtr.supports_color()
	}
	match_colored := !standard.config.colors.matched().is_none()
	return (supports_color && match_colored) || standard.config.column
		|| standard.config.replacement != none || standard.config.per_match
		|| standard.config.only_matching || standard.config.stats
}

/// Returns true if and only if this printer has written at least one byte
/// to the underlying writer during any of the previous searches.
pub fn (standard Standard[W]) has_written() bool {
	return standard.wtr.total_count() > 0
}

/// Return a mutable reference to the underlying writer.
pub fn (mut standard Standard[W]) get_mut() &W {
	return standard.wtr.get_mut()
}

/// Flush the underlying writer.
pub fn (mut standard Standard[W]) flush() ! {
	standard.wtr.flush()!
}

/// Consume this printer and return back ownership of the underlying
/// writer.
pub fn (mut standard Standard[W]) into_inner() W {
	return standard.wtr.into_inner()
}

/// An implementation of `Sink` associated with a matcher and an optional file
/// path for the standard printer.
pub struct StandardSink[^p, ^s, W] {
	matcher PrinterMatcher
mut:
	standard                &^s Standard[W]
	replacer                Replacer
	interpolator            Interpolator
	path                    ?PrinterPath[^p]
	start_time              time.Time
	match_count             u64
	binary_byte_offset      ?u64
	stats                   ?Stats
	needs_match_granularity bool
}

/// Returns true if and only if this printer received a match in the
/// previous search.
pub fn (sink StandardSink[^p, ^s, W]) has_match[^p, ^s]() bool {
	return sink.match_count > 0
}

/// Return the total number of matches reported to this sink.
pub fn (sink StandardSink[^p, ^s, W]) match_count[^p, ^s]() u64 {
	return sink.match_count
}

/// If binary data was found in the previous search, this returns the
/// offset at which the binary data was first detected.
pub fn (sink StandardSink[^p, ^s, W]) binary_byte_offset[^p, ^s]() ?u64 {
	return sink.binary_byte_offset
}

/// Return a reference to the stats produced by the printer for all
/// searches executed on this sink.
pub fn (sink &^a StandardSink[^p, ^s, W]) stats[^a, ^p, ^s]() ?&^a Stats {
	if sink.stats != none {
		return unsafe { &sink.stats? }
	}
	return none
}

fn (mut sink StandardSink[^p, ^s, W]) record_matches[^p, ^s](searcher_ searcher.Searcher, bytes []u8, range matcher.Match) ! {
	sink.standard.matches = []matcher.Match{}
	if !sink.needs_match_granularity {
		return
	}
	mut matches := []matcher.Match{}
	find_iter_at_in_context(searcher_, sink.matcher, bytes, range, fn [range, mut matches] (m matcher.Match) bool {
		s := m.start() - range.start()
		e := m.end() - range.start()
		matches << match_new(s, e)
		return true
	})!
	if matches.len > 0 {
		last := matches[matches.len - 1]
		if last.is_empty() && last.start() >= range.end() {
			matches.delete(matches.len - 1)
		}
	}
	sink.standard.matches = matches
}

fn (mut sink StandardSink[^p, ^s, W]) replace[^p, ^s](searcher_ searcher.Searcher, bytes []u8, range matcher.Match) ! {
	sink.replacer.clear()
	if replacement := sink.standard.config.replacement {
		sink.replacer.replace_all(searcher_, sink.matcher, bytes, range, replacement)!
	}
}

pub fn (mut sink StandardSink[^p, ^s, W]) matched[^p, ^s](searcher_ searcher.Searcher, mat searcher.SinkMatch) !bool {
	sink.match_count++
	if sink.needs_match_granularity {
		buf := mat.buffer()
		range := mat.bytes_range_in_buffer()
		sink.record_matches(searcher_, buf, range)!
		sink.replace(searcher_, buf, range)!
	} else {
		sink.standard.matches.clear()
		sink.replacer.clear()
	}
	if sink.stats != none {
		mut stats := sink.stats or { panic('stats missing unexpectedly') }
		stats.add_matches(u64(sink.standard.matches.len))
		stats.add_matched_lines(mat.lines().count())
		sink.stats = stats
	}
	if searcher_.binary_detection().convert_byte() != none {
		if sink.binary_byte_offset != none {
			return false
		}
	}
	if sink.can_fast_plain_match(searcher_) {
		sink.write_fast_plain_match(searcher_, mat)!
		return true
	}
	mut imp := StandardImpl.from_match(searcher_, &sink, mat)
	imp.sink()!
	return true
}

fn (sink StandardSink[^p, ^s, W]) can_fast_plain_match[^p, ^s](searcher_ searcher.Searcher) bool {
	if sink.path == none || sink.needs_match_granularity || sink.standard.wtr.supports_color()
		|| sink.standard.wtr.supports_hyperlinks() {
		return false
	}
	config := sink.standard.config
	if config.stats || config.heading || !config.path || config.only_matching || config.per_match
		|| config.replacement != none || config.max_columns != none || config.max_columns_preview
		|| config.column || config.byte_offset || config.trim_ascii || config.separator_search != none
		|| config.separator_path != none || config.path_terminator != none
		|| !config.hyperlink.format().is_empty() {
		return false
	}
	if config.separator_field_match.len != 1 || config.separator_field_match[0] != `:` {
		return false
	}
	if searcher_.line_number() || searcher_.invert_match() || searcher_.before_context() != 0
		|| searcher_.after_context() != 0 || searcher_.passthru()
		|| searcher_.binary_detection().convert_byte() != none
		|| printer_matcher_multi_line(searcher_, sink.matcher) {
		return false
	}
	return true
}

fn (mut sink StandardSink[^p, ^s, W]) write_fast_plain_match[^p, ^s](searcher_ searcher.Searcher, mat searcher.SinkMatch) ! {
	if path := sink.path {
		sink.write_all(path.as_bytes_view())!
		sink.write_all(sink.standard.config.separator_field_match)!
	}
	line := mat.bytes_view()
	sink.write_all(line)!
	if !searcher_.line_terminator().is_suffix(line) {
		sink.write_all(searcher_.line_terminator().as_bytes())!
	}
}

fn (mut sink StandardSink[^p, ^s, W]) write_all[^p, ^s](buf []u8) ! {
	mut written := usize(0)
	for written < buf.len {
		n := sink.standard.wtr.write(buf[written..])!
		if n <= 0 {
			return error('failed to write all bytes')
		}
		written += usize(n)
	}
}

pub fn (mut sink StandardSink[^p, ^s, W]) context[^p, ^s](searcher_ searcher.Searcher, ctx searcher.SinkContext) !bool {
	sink.standard.matches.clear()
	sink.replacer.clear()
	if searcher_.invert_match() {
		full_range := matcher.Match.new(0, ctx.bytes().len)
		sink.record_matches(searcher_, ctx.bytes(), full_range)!
		sink.replace(searcher_, ctx.bytes(), full_range)!
	}
	if searcher_.binary_detection().convert_byte() != none {
		if sink.binary_byte_offset != none {
			return false
		}
	}
	mut imp := StandardImpl.from_context(searcher_, &sink, ctx)
	imp.sink()!
	return true
}

pub fn (mut sink StandardSink[^p, ^s, W]) context_break[^p, ^s](searcher_ searcher.Searcher) !bool {
	mut imp := StandardImpl.new(searcher_, &sink)
	imp.write_context_separator()!
	return true
}

pub fn (mut sink StandardSink[^p, ^s, W]) binary_data[^p, ^s](searcher_ searcher.Searcher, binary_byte_offset u64) !bool {
	if searcher_.binary_detection().quit_byte() != none {
		if sink.path != none {
			log.debug('ignoring file: found binary data at offset ${binary_byte_offset}')
		}
	}
	sink.binary_byte_offset = binary_byte_offset
	return true
}

pub fn (mut sink StandardSink[^p, ^s, W]) begin[^p, ^s](_searcher searcher.Searcher) !bool {
	sink.standard.wtr.reset_count()
	sink.start_time = time.now()
	sink.match_count = 0
	sink.binary_byte_offset = none
	return true
}

pub fn (mut sink StandardSink[^p, ^s, W]) finish[^p, ^s](searcher_ searcher.Searcher, finish searcher.SinkFinish) ! {
	if offset := sink.binary_byte_offset {
		mut imp := StandardImpl.new(searcher_, &sink)
		imp.write_binary_message(offset)!
	}
	if sink.stats != none {
		mut stats := sink.stats or { panic('stats missing unexpectedly') }
		stats.add_elapsed(time.since(sink.start_time))
		stats.add_searches(1)
		if sink.match_count > 0 {
			stats.add_searches_with_match(1)
		}
		stats.add_bytes_searched(finish.byte_count())
		stats.add_bytes_printed(sink.standard.wtr.count())
		sink.stats = stats
	}
}

struct StandardImpl[^p, ^s, W] {
	searcher searcher.Searcher
mut:
	sink           &^s StandardSink[^p, ^s, W]
	sunk           Sunk
	in_color_match bool
}

fn StandardImpl.new[^p, ^s, W](searcher_ searcher.Searcher, sink &^s StandardSink[^p, ^s, W]) StandardImpl[^p, ^s, W] {
	return StandardImpl[^p, ^s, W]{
		searcher: searcher_
		sink:     sink
		sunk:     Sunk.empty()
	}
}

fn StandardImpl.from_match[^p, ^s, W](searcher_ searcher.Searcher, sink &^s StandardSink[^p, ^s, W], mat searcher.SinkMatch) StandardImpl[^p, ^s, W] {
	sunk := Sunk.from_sink_match(mat, sink.standard.matches, sink.replacer.replacement())
	return StandardImpl[^p, ^s, W]{
		searcher: searcher_
		sink:     sink
		sunk:     sunk
	}
}

fn StandardImpl.from_context[^p, ^s, W](searcher_ searcher.Searcher, sink &^s StandardSink[^p, ^s, W], ctx searcher.SinkContext) StandardImpl[^p, ^s, W] {
	sunk := Sunk.from_sink_context(ctx, sink.standard.matches, sink.replacer.replacement())
	return StandardImpl[^p, ^s, W]{
		searcher: searcher_
		sink:     sink
		sunk:     sunk
	}
}

fn (mut imp StandardImpl[^p, ^s, W]) sink[^p, ^s]() ! {
	imp.write_search_prelude()!
	matches := imp.sunk.matches()
	if matches.len == 0 {
		if imp.multi_line() && !imp.is_context() {
			imp.sink_fast_multi_line()!
		} else {
			imp.sink_fast()!
		}
	} else if imp.multi_line() && !imp.is_context() {
		imp.sink_slow_multi_line()!
	} else {
		imp.sink_slow()!
	}
}

fn (mut imp StandardImpl[^p, ^s, W]) sink_fast[^p, ^s]() ! {
	imp.write_prelude(imp.sunk.absolute_byte_offset(), imp.sunk.line_number(), none)!
	imp.write_line(imp.sunk.bytes())!
}

fn (mut imp StandardImpl[^p, ^s, W]) sink_fast_multi_line[^p, ^s]() ! {
	line_term := imp.searcher.line_terminator().as_byte()
	mut absolute_byte_offset := imp.sunk.absolute_byte_offset()
	bytes := imp.sunk.bytes()
	mut i := u64(0)
	mut stepper := searcher.LineStep.new(line_term, 0, bytes.len)
	for {
		start, end := stepper.next(bytes) or { break }
		imp.write_prelude(absolute_byte_offset, add_line_number(imp.sunk.line_number(), i),
			none)!
		absolute_byte_offset += u64(end - start)
		imp.write_line(bytes[start..end])!
		i++
	}
}

fn (mut imp StandardImpl[^p, ^s, W]) sink_slow[^p, ^s]() ! {
	matches := imp.sunk.matches()
	bytes := imp.sunk.bytes()
	if imp.config().only_matching {
		for m in matches {
			imp.write_prelude(imp.sunk.absolute_byte_offset() + u64(m.start()),
				imp.sunk.line_number(), u64(m.start()) + 1)!
			buf := bytes[m.start()..m.end()]
			imp.write_colored_line([matcher.Match.new(0, buf.len)], buf)!
		}
	} else if imp.config().per_match {
		for m in matches {
			imp.write_prelude(imp.sunk.absolute_byte_offset() + u64(m.start()),
				imp.sunk.line_number(), u64(m.start()) + 1)!
			imp.write_colored_line([m], bytes)!
		}
	} else {
		imp.write_prelude(imp.sunk.absolute_byte_offset(), imp.sunk.line_number(),
			u64(matches[0].start()) + 1)!
		imp.write_colored_line(matches, bytes)!
	}
}

fn (mut imp StandardImpl[^p, ^s, W]) sink_slow_multi_line[^p, ^s]() ! {
	if imp.config().only_matching {
		imp.sink_slow_multi_line_only_matching()!
		return
	} else if imp.config().per_match {
		imp.sink_slow_multi_per_match()!
		return
	}
	line_term := imp.searcher.line_terminator().as_byte()
	bytes := imp.sunk.bytes()
	matches := imp.sunk.matches()
	mut midx := usize(0)
	mut count := u64(0)
	mut stepper := searcher.LineStep.new(line_term, 0, bytes.len)
	for {
		start, end := stepper.next(bytes) or { break }
		mut line := matcher.Match.new(start, end)
		imp.write_prelude(imp.sunk.absolute_byte_offset() + u64(line.start()),
			add_line_number(imp.sunk.line_number(), count), u64(matches[0].start()) + 1)!
		count++
		imp.trim_ascii_prefix(bytes, mut line)
		if imp.exceeds_max_columns(bytes[line.start()..line.end()]) {
			imp.write_exceeded_line(bytes, line, matches, mut midx)!
		} else {
			imp.write_colored_matches(bytes, line, matches, mut midx)!
			imp.write_line_term()!
		}
	}
}

fn (mut imp StandardImpl[^p, ^s, W]) sink_slow_multi_line_only_matching[^p, ^s]() ! {
	line_term := imp.searcher.line_terminator().as_byte()
	spec := imp.config().colors.matched()
	bytes := imp.sunk.bytes()
	matches := imp.sunk.matches()
	mut midx := usize(0)
	mut count := u64(0)
	mut stepper := searcher.LineStep.new(line_term, 0, bytes.len)
	for {
		start, end := stepper.next(bytes) or { break }
		mut line := matcher.Match.new(start, end)
		imp.trim_line_terminator(bytes, mut line)
		imp.trim_ascii_prefix(bytes, mut line)
		for !line.is_empty() && midx < matches.len {
			if matches[midx].end() <= line.start() {
				if midx + 1 < matches.len {
					midx++
					continue
				}
				break
			}
			m := matches[midx]
			if line.start() < m.start() {
				upto := min_usize(line.end(), m.start())
				line = line.with_start(upto)
			} else {
				upto := min_usize(line.end(), m.end())
				imp.write_prelude(imp.sunk.absolute_byte_offset() + u64(m.start()),
					add_line_number(imp.sunk.line_number(), count), u64(m.start()) + 1)!
				this_line := line.with_end(upto)
				line = line.with_start(upto)
				if imp.exceeds_max_columns(bytes[this_line.start()..this_line.end()]) {
					imp.write_exceeded_line(bytes, this_line, matches, mut midx)!
				} else {
					imp.write_spec(spec, bytes[this_line.start()..this_line.end()])!
					imp.write_line_term()!
				}
			}
		}
		count++
	}
}

fn (mut imp StandardImpl[^p, ^s, W]) sink_slow_multi_per_match[^p, ^s]() ! {
	line_term := imp.searcher.line_terminator().as_byte()
	spec := imp.config().colors.matched()
	bytes := imp.sunk.bytes()
	for m in imp.sunk.matches() {
		mut count := u64(0)
		mut stepper := searcher.LineStep.new(line_term, 0, bytes.len)
		for {
			start, end := stepper.next(bytes) or { break }
			mut line := matcher.Match.new(start, end)
			if line.start() >= m.end() {
				break
			} else if line.end() <= m.start() {
				count++
				continue
			}
			imp.write_prelude(imp.sunk.absolute_byte_offset() + u64(line.start()),
				add_line_number(imp.sunk.line_number(), count),
				u64(saturating_sub_usize(m.start(), line.start())) + 1)!
			count++
			imp.trim_line_terminator(bytes, mut line)
			imp.trim_ascii_prefix(bytes, mut line)
			if imp.exceeds_max_columns(bytes[line.start()..line.end()]) {
				mut zero := usize(0)
				imp.write_exceeded_line(bytes, line, [m], mut zero)!
				continue
			}
			for !line.is_empty() {
				if m.end() <= line.start() {
					imp.write(bytes[line.start()..line.end()])!
					line = line.with_start(line.end())
				} else if line.start() < m.start() {
					upto := min_usize(line.end(), m.start())
					part := line.with_end(upto)
					imp.write(bytes[part.start()..part.end()])!
					line = line.with_start(upto)
				} else {
					upto := min_usize(line.end(), m.end())
					part := line.with_end(upto)
					imp.write_spec(spec, bytes[part.start()..part.end()])!
					line = line.with_start(upto)
				}
			}
			imp.write_line_term()!
			if imp.config().per_match_one_line {
				break
			}
		}
	}
}

fn (mut imp StandardImpl[^p, ^s, W]) write_prelude[^p, ^s](absolute_byte_offset u64, line_number ?u64, column ?u64) ! {
	mut next_separator := PreludeSeparator.none_
	field_separator := imp.separator_field()
	mut interp_status := InterpolatorStatus.inactive()
	if mut path := imp.path() {
		if imp.config().hyperlink.format().is_line_dependent() || !imp.config().heading {
			interp_status = imp.start_hyperlink(mut path, line_number, column)!
		}
	}
	if !imp.config().heading {
		if mut path := imp.path() {
			imp.write_prelude_separator(mut next_separator, field_separator)!
			imp.write_path(mut path)!
			next_separator = if imp.config().path_terminator != none {
				.path_terminator
			} else {
				.field_separator
			}
		}
	}
	if line := line_number {
		imp.write_prelude_separator(mut next_separator, field_separator)!
		n := DecimalFormatter.new(line)
		imp.write_spec(imp.config().colors.line(), n.as_bytes())!
		next_separator = .field_separator
	}
	if imp.config().column {
		if col := column {
			imp.write_prelude_separator(mut next_separator, field_separator)!
			n := DecimalFormatter.new(col)
			imp.write_spec(imp.config().colors.column(), n.as_bytes())!
			next_separator = .field_separator
		}
	}
	if imp.config().byte_offset {
		imp.write_prelude_separator(mut next_separator, field_separator)!
		n := DecimalFormatter.new(absolute_byte_offset)
		imp.write_spec(imp.config().colors.column(), n.as_bytes())!
		next_separator = .field_separator
	}
	imp.end_hyperlink(interp_status)!
	imp.write_prelude_separator(mut next_separator, field_separator)!
}

fn (mut imp StandardImpl[^p, ^s, W]) write_prelude_separator[^p, ^s](mut next_separator PreludeSeparator, field_separator []u8) ! {
	match next_separator {
		.none_ {}
		.field_separator {
			imp.write(field_separator)!
		}
		.path_terminator {
			if term := imp.config().path_terminator {
				imp.write([term])!
			}
		}
	}
	next_separator = .none_
}

fn (mut imp StandardImpl[^p, ^s, W]) write_line[^p, ^s](line []u8) ! {
	if !imp.config().trim_ascii && !imp.exceeds_max_columns(line) {
		imp.write(line)!
		if !imp.has_line_terminator(line) {
			imp.write_line_term()!
		}
		return
	}
	mut line2 := line
	if imp.config().trim_ascii {
		lineterm := imp.searcher.line_terminator()
		full_range := matcher.Match.new(0, line2.len)
		range := trim_ascii_prefix(lineterm, line2, full_range)
		line2 = line2[range.start()..range.end()].clone()
	}
	if imp.exceeds_max_columns(line2) {
		range := matcher.Match.new(0, line2.len)
		mut zero := usize(0)
		imp.write_exceeded_line(line2, range, imp.sunk.matches(), mut zero)!
	} else {
		imp.write(line2)!
		if !imp.has_line_terminator(line2) {
			imp.write_line_term()!
		}
	}
}

fn (mut imp StandardImpl[^p, ^s, W]) write_colored_line[^p, ^s](matches []matcher.Match, bytes []u8) ! {
	spec := imp.config().colors.matched()
	if !imp.sink.standard.wtr.supports_color() || spec.is_none() {
		imp.write_line(bytes)!
		return
	}
	mut line := matcher.Match.new(0, bytes.len)
	imp.trim_ascii_prefix(bytes, mut line)
	if imp.exceeds_max_columns(bytes) {
		mut zero := usize(0)
		imp.write_exceeded_line(bytes, line, matches, mut zero)!
	} else {
		mut zero := usize(0)
		imp.write_colored_matches(bytes, line, matches, mut zero)!
		imp.write_line_term()!
	}
}

fn (mut imp StandardImpl[^p, ^s, W]) write_colored_matches[^p, ^s](bytes []u8, mut line matcher.Match, matches []matcher.Match, mut match_index usize) ! {
	imp.trim_line_terminator(bytes, mut line)
	if matches.len == 0 {
		imp.write(bytes[line.start()..line.end()])!
		return
	}
	imp.start_line_highlight()!
	for !line.is_empty() {
		idx := *match_index
		if matches[idx].end() <= line.start() {
			if idx + 1 < matches.len {
				match_index++
				continue
			}
			imp.end_color_match()!
			imp.write(bytes[line.start()..line.end()])!
			break
		}
		m := matches[*match_index]
		if line.start() < m.start() {
			upto := min_usize(line.end(), m.start())
			imp.end_color_match()!
			part := line.with_end(upto)
			imp.write(bytes[part.start()..part.end()])!
			line = line.with_start(upto)
		} else {
			upto := min_usize(line.end(), m.end())
			imp.start_color_match()!
			part := line.with_end(upto)
			imp.write(bytes[part.start()..part.end()])!
			line = line.with_start(upto)
		}
	}
	imp.end_color_match()!
	imp.end_line_highlight()!
}

fn (mut imp StandardImpl[^p, ^s, W]) write_exceeded_line[^p, ^s](bytes []u8, mut line matcher.Match, matches []matcher.Match, mut match_index usize) ! {
	if imp.config().max_columns_preview {
		original_end := line.end()
		limit := usize(imp.config().max_columns or { 0 })
		preview_end := min_usize(line.start() + limit, original_end)
		line = line.with_end(preview_end)
		imp.write_colored_matches(bytes, line, matches, mut match_index)!
		if matches.len == 0 {
			imp.write(' [... omitted end of long line]'.bytes())!
		} else {
			mut remaining := 0
			for m in matches {
				if m.start() >= preview_end && m.start() < original_end {
					remaining++
				}
			}
			tense := if remaining == 1 { 'match' } else { 'matches' }
			imp.write(' [... ${remaining} more ${tense}]'.bytes())!
		}
		imp.write_line_term()!
		return
	}
	if imp.sunk.original_matches().len == 0 {
		if imp.is_context() {
			imp.write('[Omitted long context line]'.bytes())!
		} else {
			imp.write('[Omitted long matching line]'.bytes())!
		}
	} else if imp.config().only_matching {
		if imp.is_context() {
			imp.write('[Omitted long context line]'.bytes())!
		} else {
			imp.write('[Omitted long matching line]'.bytes())!
		}
	} else {
		imp.write('[Omitted long line with ${imp.sunk.original_matches().len} matches]'.bytes())!
	}
	imp.write_line_term()!
}

fn (mut imp StandardImpl[^p, ^s, W]) write_path_line[^p, ^s]() ! {
	if mut path := imp.path() {
		imp.write_path_hyperlink(mut path)!
		if term := imp.config().path_terminator {
			imp.write([term])!
		} else {
			imp.write_line_term()!
		}
	}
}

fn (mut imp StandardImpl[^p, ^s, W]) write_search_prelude[^p, ^s]() ! {
	this_search_written := imp.sink.standard.wtr.count() > 0
	if this_search_written {
		return
	}
	if sep := imp.config().separator_search {
		ever_written := imp.sink.standard.wtr.total_count() > 0
		if ever_written {
			imp.write(sep)!
			imp.write_line_term()!
		}
	}
	if imp.config().heading {
		imp.write_path_line()!
	}
}

fn (mut imp StandardImpl[^p, ^s, W]) write_binary_message[^p, ^s](offset u64) ! {
	if !imp.sink.has_match() {
		return
	}
	bin := imp.searcher.binary_detection()
	if byte := bin.quit_byte() {
		if mut path := imp.path() {
			imp.write_path_hyperlink(mut path)!
			imp.write(': '.bytes())!
		}
		imp.write('WARNING: stopped searching binary file after match (found ${binary_byte_debug(byte)} byte around offset ${offset})\n'.bytes())!
	} else if byte := bin.convert_byte() {
		if mut path := imp.path() {
			imp.write_path_hyperlink(mut path)!
			imp.write(': '.bytes())!
		}
		imp.write('binary file matches (found ${binary_byte_debug(byte)} byte around offset ${offset})\n'.bytes())!
	}
}

fn binary_byte_debug(byte u8) string {
	return '"${binary_byte_debug_escape(byte)}"'
}

fn binary_byte_debug_escape(byte u8) string {
	return match byte {
		0 { '\\0' }
		`\n` { '\\n' }
		`\r` { '\\r' }
		`\t` { '\\t' }
		`\\` { '\\\\' }
		`"` { '\\"' }
		else {
			if byte < 0x20 || byte == 0x7f || byte >= 0x80 {
				hex := '0123456789ABCDEF'
				'\\x${hex[int(byte >> 4)].ascii_str()}${hex[int(byte & 0x0f)].ascii_str()}'
			} else {
				byte.ascii_str()
			}
		}
	}
}

fn (mut imp StandardImpl[^p, ^s, W]) write_context_separator[^p, ^s]() ! {
	if sep := imp.config().separator_context {
		imp.write(sep)!
		imp.write_line_term()!
	}
}

fn (mut imp StandardImpl[^p, ^s, W]) write_line_term[^p, ^s]() ! {
	imp.write(imp.searcher.line_terminator().as_bytes())!
}

fn (mut imp StandardImpl[^p, ^s, W]) write_spec[^p, ^s](spec ColorSpec, buf []u8) ! {
	if spec.is_none() || !imp.sink.standard.wtr.supports_color() {
		imp.write(buf)!
		return
	}
	imp.sink.standard.wtr.set_color(spec)!
	imp.write(buf)!
	imp.sink.standard.wtr.reset()!
}

fn (mut imp StandardImpl[^p, ^s, W]) write_path[^p, ^s](mut path PrinterPath[^p]) ! {
	spec := imp.config().colors.path()
	if spec.is_none() || !imp.sink.standard.wtr.supports_color() {
		imp.write(path.as_bytes_view())!
		return
	}
	imp.sink.standard.wtr.set_color(spec)!
	imp.write(path.as_bytes_view())!
	imp.sink.standard.wtr.reset()!
}

fn (mut imp StandardImpl[^p, ^s, W]) write_path_hyperlink[^p, ^s](mut path PrinterPath[^p]) ! {
	status := imp.start_hyperlink(mut path, none, none)!
	imp.write_path(mut path)!
	imp.end_hyperlink(status)!
}

fn (mut imp StandardImpl[^p, ^s, W]) start_hyperlink[^p, ^s](mut path PrinterPath[^p], line_number ?u64, column ?u64) !InterpolatorStatus {
	hyperpath := path.as_hyperlink() or { return InterpolatorStatus.inactive() }
	values := Values.new(hyperpath).line(line_number).column(column)
	return imp.sink.interpolator.begin(values, mut imp.sink.standard.wtr)
}

fn (mut imp StandardImpl[^p, ^s, W]) end_hyperlink[^p, ^s](status InterpolatorStatus) ! {
	imp.sink.interpolator.finish(status, mut imp.sink.standard.wtr)!
}

fn (mut imp StandardImpl[^p, ^s, W]) start_color_match[^p, ^s]() ! {
	if imp.in_color_match {
		return
	}
	imp.sink.standard.wtr.set_color(imp.config().colors.matched())!
	imp.in_color_match = true
}

fn (mut imp StandardImpl[^p, ^s, W]) end_color_match[^p, ^s]() ! {
	if !imp.in_color_match {
		return
	}
	if imp.highlight_on() {
		imp.sink.standard.wtr.set_color(imp.config().colors.highlight())!
	} else {
		imp.sink.standard.wtr.reset()!
	}
	imp.in_color_match = false
}

fn (imp StandardImpl[^p, ^s, W]) highlight_on[^p, ^s]() bool {
	return !imp.config().colors.highlight().is_none() && !imp.is_context()
}

fn (mut imp StandardImpl[^p, ^s, W]) start_line_highlight[^p, ^s]() ! {
	if imp.highlight_on() {
		imp.sink.standard.wtr.set_color(imp.config().colors.highlight())!
	}
}

fn (mut imp StandardImpl[^p, ^s, W]) end_line_highlight[^p, ^s]() ! {
	if imp.highlight_on() {
		imp.sink.standard.wtr.reset()!
	}
}

fn (mut imp StandardImpl[^p, ^s, W]) write[^p, ^s](buf []u8) ! {
	mut written := usize(0)
	for written < buf.len {
		n := imp.sink.standard.wtr.write(buf[written..])!
		if n <= 0 {
			return error('failed to write all bytes')
		}
		written += usize(n)
	}
}

fn (imp StandardImpl[^p, ^s, W]) has_line_terminator[^p, ^s](buf []u8) bool {
	return imp.searcher.line_terminator().is_suffix(buf)
}

fn (imp StandardImpl[^p, ^s, W]) is_context[^p, ^s]() bool {
	return imp.sunk.context_kind() != none
}

fn (imp StandardImpl[^p, ^s, W]) config[^p, ^s]() StandardConfig {
	return imp.sink.standard.config
}

fn (imp StandardImpl[^p, ^s, W]) path[^p, ^s]() ?PrinterPath[^p] {
	return imp.sink.path
}

fn (imp StandardImpl[^p, ^s, W]) separator_field[^p, ^s]() []u8 {
	config := imp.config()
	if imp.is_context() {
		return config.separator_field_context.clone()
	}
	return config.separator_field_match.clone()
}

fn (imp StandardImpl[^p, ^s, W]) exceeds_max_columns[^p, ^s](line []u8) bool {
	if max := imp.config().max_columns {
		return u64(line.len) > max
	}
	return false
}

fn (imp StandardImpl[^p, ^s, W]) multi_line[^p, ^s]() bool {
	return printer_matcher_multi_line(imp.searcher, imp.sink.matcher)
}

fn (imp StandardImpl[^p, ^s, W]) trim_line_terminator[^p, ^s](buf []u8, mut line matcher.Match) {
	line2, _ := trim_line_terminator(imp.searcher, buf, line)
	line = line2
}

fn (imp StandardImpl[^p, ^s, W]) trim_ascii_prefix[^p, ^s](slice []u8, mut range matcher.Match) {
	if !imp.config().trim_ascii {
		return
	}
	range = trim_ascii_prefix(imp.searcher.line_terminator(), slice, range)
}

/// A type of separator used in the prelude
enum PreludeSeparator {
	/// No separator.
	none_
	/// The field separator, either for a matching or contextual line.
	field_separator
	/// The path terminator.
	path_terminator
}

fn add_line_number(line ?u64, add u64) ?u64 {
	if n := line {
		return n + add
	}
	return none
}

fn min_usize(a usize, b usize) usize {
	return if a < b { a } else { b }
}

fn saturating_sub_usize(a usize, b usize) usize {
	if a < b {
		return 0
	}
	return a - b
}
