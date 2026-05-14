module printer

import log
import matcher
import searcher
import time

/// The configuration for the summary printer.
///
/// This is manipulated by the SummaryBuilder and then referenced by the actual
/// implementation. Once a printer is build, the configuration is frozen and
/// cannot changed.
struct SummaryConfig {
mut:
	kind            SummaryKind
	colors          ColorSpecs
	hyperlink       HyperlinkConfig
	stats           bool
	path            bool
	exclude_zero    bool
	separator_field []u8
	separator_path  ?u8
	path_terminator ?u8
}

fn default_summary_config() SummaryConfig {
	return SummaryConfig{
		kind:            .count
		colors:          ColorSpecs{}
		hyperlink:       HyperlinkConfig{}
		stats:           false
		path:            true
		exclude_zero:    true
		separator_field: [u8(`:`)]
	}
}

/// The type of summary output (if any) to print.
pub enum SummaryKind {
	/// Show only a count of the total number of matches (counting each line
	/// at most once) found.
	///
	/// If the `path` setting is enabled, then the count is prefixed by the
	/// corresponding file path.
	count
	/// Show only a count of the total number of matches (counting possibly
	/// many matches on each line) found.
	///
	/// If the `path` setting is enabled, then the count is prefixed by the
	/// corresponding file path.
	count_matches
	/// Show only the file path if and only if a match was found.
	///
	/// This ignores the `path` setting and always shows the file path. If no
	/// file path is provided, then searching will immediately stop and return
	/// an error.
	path_with_match
	/// Show only the file path if and only if a match was found.
	///
	/// This ignores the `path` setting and always shows the file path. If no
	/// file path is provided, then searching will immediately stop and return
	/// an error.
	path_without_match
	/// Don't show any output and the stop the search once a match is found.
	///
	/// Note that if `stats` is enabled, then searching continues in order to
	/// compute statistics.
	quiet_with_match
	/// Don't show any output and the stop the search once a non-matching file
	/// is found.
	///
	/// Note that if `stats` is enabled, then searching continues in order to
	/// compute statistics.
	quiet_without_match
}

/// Returns true if and only if this output mode requires a file path.
///
/// When an output mode requires a file path, then the summary printer
/// will report an error at the start of every search that lacks a file
/// path.
fn (kind SummaryKind) requires_path() bool {
	return match kind {
		.path_with_match, .path_without_match { true }
		.count, .count_matches, .quiet_with_match, .quiet_without_match { false }
	}
}

/// Returns true if and only if this output mode requires computing
/// statistics, regardless of whether they have been enabled or not.
fn (kind SummaryKind) requires_stats() bool {
	return match kind {
		.count_matches { true }
		.count, .path_with_match, .path_without_match, .quiet_with_match, .quiet_without_match { false }
	}
}

/// Returns true if and only if a printer using this output mode can
/// quit after seeing the first match.
fn (kind SummaryKind) quit_early() bool {
	return match kind {
		.path_with_match, .quiet_with_match { true }
		.count, .count_matches, .path_without_match, .quiet_without_match { false }
	}
}

/// A builder for summary printer.
///
/// The builder permits configuring how the printer behaves. The summary
/// printer has fewer configuration options than the standard printer because
/// it aims to produce aggregate output about a single search (typically just
/// one line) instead of output for each match.
///
/// Once a `Summary` printer is built, its configuration cannot be changed.
pub struct SummaryBuilder {
mut:
	config SummaryConfig
}

/// Return a new builder for configuring the summary printer.
pub fn SummaryBuilder.new() SummaryBuilder {
	return SummaryBuilder{
		config: default_summary_config()
	}
}

/// Build a printer using any implementation of `termcolor::WriteColor`.
///
/// The implementation of `WriteColor` used here controls whether colors
/// are used or not when colors have been configured using the
/// `color_specs` method.
pub fn (builder SummaryBuilder) build[W](wtr W) Summary[W] {
	return Summary[W]{
		config: builder.config
		wtr:    CounterWriter[W]{
			wtr: wtr
		}
	}
}

/// Build a printer from any implementation of `io::Write` and never emit
/// any colors, regardless of the user color specification settings.
///
/// This is a convenience routine for
/// `SummaryBuilder::build(termcolor::NoColor::new(wtr))`.
pub fn (builder SummaryBuilder) build_no_color[W](wtr W) Summary[NoColor[W]] {
	return builder.build(NoColor.new(wtr))
}

/// Set the output mode for this printer.
///
/// The output mode controls how aggregate results of a search are printed.
///
/// By default, this printer uses the `Count` mode.
pub fn (mut builder SummaryBuilder) kind(kind SummaryKind) &SummaryBuilder {
	builder.config.kind = kind
	return builder
}

/// Set the user color specifications to use for coloring in this printer.
///
/// This completely overrides any previous color specifications. This does
/// not add to any previously provided color specifications on this
/// builder.
///
/// The default color specifications provide no styling.
pub fn (mut builder SummaryBuilder) color_specs(specs ColorSpecs) &SummaryBuilder {
	builder.config.colors = specs
	return builder
}

/// Set the configuration to use for hyperlinks output by this printer.
///
/// This completely overrides any previous hyperlink format.
///
/// The default configuration results in not emitting any hyperlinks.
pub fn (mut builder SummaryBuilder) hyperlink(config HyperlinkConfig) &SummaryBuilder {
	builder.config.hyperlink = config
	return builder
}

/// Enable the gathering of various aggregate statistics.
///
/// When this is enabled (it's disabled by default), statistics will be
/// gathered for all uses of `Summary` printer returned by `build`,
/// including but not limited to, the total number of matches, the total
/// number of bytes searched and the total number of bytes printed.
pub fn (mut builder SummaryBuilder) stats(yes bool) &SummaryBuilder {
	builder.config.stats = yes
	return builder
}

/// When enabled, if a path was given to the printer, then it is shown in
/// the output (either as a heading or as a prefix to each matching line).
/// When disabled, then no paths are ever included in the output even when
/// a path is provided to the printer.
///
/// This setting has no effect in `PathWithMatch` and `PathWithoutMatch`
/// modes.
///
/// This is enabled by default.
pub fn (mut builder SummaryBuilder) path(yes bool) &SummaryBuilder {
	builder.config.path = yes
	return builder
}

/// Exclude count-related summary results with no matches.
///
/// When enabled and the mode is either `Count` or `CountMatches`, then
/// results are not printed if no matches were found. Otherwise, every
/// search prints a result with a possibly `0` number of matches.
///
/// This is enabled by default.
pub fn (mut builder SummaryBuilder) exclude_zero(yes bool) &SummaryBuilder {
	builder.config.exclude_zero = yes
	return builder
}

/// Set the separator used between fields for the `Count` and
/// `CountMatches` modes.
///
/// By default, this is set to `:`.
pub fn (mut builder SummaryBuilder) separator_field(sep []u8) &SummaryBuilder {
	builder.config.separator_field = sep.clone()
	return builder
}

/// Set the path separator used when printing file paths.
///
/// Typically, printing is done by emitting the file path as is. However,
/// this setting provides the ability to use a different path separator
/// from what the current environment has configured.
pub fn (mut builder SummaryBuilder) separator_path(sep ?u8) &SummaryBuilder {
	builder.config.separator_path = sep
	return builder
}

/// Set the path terminator used.
///
/// The path terminator is a byte that is printed after every file path
/// emitted by this printer.
///
/// If no path terminator is set (the default), then paths are terminated
/// by either new lines or the configured field separator.
pub fn (mut builder SummaryBuilder) path_terminator(terminator ?u8) &SummaryBuilder {
	builder.config.path_terminator = terminator
	return builder
}

/// The summary printer, which emits aggregate results from a search.
///
/// Aggregate results generally correspond to file paths and/or the number of
/// matches found.
///
/// A default printer can be created with either of the `Summary::new` or
/// `Summary::new_no_color` constructors. However, there are a number of
/// options that configure this printer's output. Those options can be
/// configured using [`SummaryBuilder`].
pub struct Summary[W] {
	config SummaryConfig
mut:
	wtr CounterWriter[W]
}

/// Return a summary printer with a default configuration that writes
/// matches to the given writer.
///
/// The default configuration uses the `Count` summary mode.
pub fn Summary.new[W](wtr W) Summary[W] {
	return SummaryBuilder.new().build(wtr)
}

/// Return a summary printer with a default configuration that writes
/// matches to the given writer.
///
/// The writer can be any implementation of `io::Write`. With this
/// constructor, the printer will never emit colors.
///
/// The default configuration uses the `Count` summary mode.
pub fn Summary.new_no_color[W](wtr W) Summary[NoColor[W]] {
	return SummaryBuilder.new().build_no_color(wtr)
}

/// Return an implementation of `Sink` for the summary printer.
///
/// This does not associate the printer with a file path, which means this
/// implementation will never print a file path. If the output mode of
/// this summary printer does not make sense without a file path (such as
/// `PathWithMatch` or `PathWithoutMatch`), then any searches executed
/// using this sink will immediately quit with an error.
pub fn (mut summary Summary[W]) sink[^s, M](matcher_ M) SummarySink[^s, ^s, M, W] {
	mut stats := ?Stats(none)
	if summary.config.stats || summary.config.kind.requires_stats() {
		stats = Stats.new()
	}
	return SummarySink[^s, ^s, M, W]{
		matcher:      matcher_
		summary:      &summary
		interpolator: Interpolator.new(summary.config.hyperlink)
		path:         ?PrinterPath(none)
		start_time:   time.now()
		match_count:  0
		stats:        stats
	}
}

/// Return an implementation of `Sink` associated with a file path.
///
/// When the printer is associated with a path, then it may, depending on
/// its configuration, print the path.
pub fn (mut summary Summary[W]) sink_with_path[^p, ^s, M](matcher_ M, path &^p string) SummarySink[^p, ^s, M, W] {
	mut stats := ?Stats(none)
	if summary.config.stats || summary.config.kind.requires_stats() {
		stats = Stats.new()
	}
	if !summary.config.path && !summary.config.kind.requires_path() {
			return SummarySink[^p, ^s, M, W]{
				matcher:      matcher_
				summary:      &summary
			interpolator: Interpolator.new(summary.config.hyperlink)
			path:         ?PrinterPath(none)
			start_time:   time.now()
			match_count:  0
			stats:        stats
		}
	}
	ppath := PrinterPath.new(path).with_separator(summary.config.separator_path)
	return SummarySink[^p, ^s, M, W]{
		matcher:      matcher_
		summary:      &summary
		interpolator: Interpolator.new(summary.config.hyperlink)
		path:         ppath
		start_time:   time.now()
		match_count:  0
		stats:        stats
	}
}

/// Returns true if and only if this printer has written at least one byte
/// to the underlying writer during any of the previous searches.
pub fn (summary Summary[W]) has_written() bool {
	return summary.wtr.total_count_ + summary.wtr.count_ > 0
}

/// Return a mutable reference to the underlying writer.
pub fn (mut summary Summary[W]) get_mut() &W {
	return unsafe { &summary.wtr.wtr }
}

/// Consume this printer and return back ownership of the underlying
/// writer.
pub fn (mut summary Summary[W]) into_inner() W {
	return summary.wtr.wtr
}

/// An implementation of `Sink` associated with a matcher and an optional file
/// path for the summary printer.
///
pub struct SummarySink[^p, ^s, M, W] {
	matcher M
mut:
	summary            &^s Summary[W]
	interpolator       Interpolator
	path               ?PrinterPath[^p]
	start_time         time.Time
	match_count        u64
	binary_byte_offset ?u64
	stats              ?Stats
}

/// Returns true if and only if this printer received a match in the
/// previous search.
///
/// This is unaffected by the result of searches before the previous
/// search.
pub fn (sink SummarySink[^p, ^s, M, W]) has_match() bool {
	return match sink.summary.config.kind {
		.path_without_match, .quiet_without_match { sink.match_count == 0 }
		else { sink.match_count > 0 }
	}
}

/// If binary data was found in the previous search, this returns the
/// offset at which the binary data was first detected.
///
/// The offset returned is an absolute offset relative to the entire
/// set of bytes searched.
pub fn (sink SummarySink[^p, ^s, M, W]) binary_byte_offset() ?u64 {
	return sink.binary_byte_offset
}

/// Return a reference to the stats produced by the printer for all
/// searches executed on this sink.
///
/// This only returns stats if they were requested via the
/// [`SummaryBuilder`] configuration.
pub fn (sink &^a SummarySink[^p, ^s, M, W]) stats[^a]() ?&^a Stats {
	if sink.stats != none {
		return unsafe { &sink.stats? }
	}
	return none
}

/// Returns true if and only if the searcher may report matches over
/// multiple lines.
///
/// Note that this doesn't just return whether the searcher is in multi
/// line mode, but also checks if the matter can match over multiple lines.
/// If it can't, then we don't need multi line handling, even if the
/// searcher has multi line mode enabled.
fn (sink SummarySink[^p, ^s, M, W]) multi_line(searcher_ searcher.Searcher) bool {
	return searcher_.multi_line_with_matcher(sink.matcher)
}

/// If this printer has a file path associated with it, then this will
/// write that path to the underlying writer followed by a line terminator.
/// (If a path terminator is set, then that is used instead of the line
/// terminator.)
fn (mut sink SummarySink[^p, ^s, M, W]) write_path_line(searcher_ searcher.Searcher) ! {
	if sink.path != none {
		sink.write_path()!
		if term := sink.summary.config.path_terminator {
			sink.write_all([term])!
		} else {
			sink.write_line_term(searcher_)!
		}
	}
}

/// If this printer has a file path associated with it, then this will
/// write that path to the underlying writer followed by the field
/// separator. (If a path terminator is set, then that is used instead of
/// the field separator.)
fn (mut sink SummarySink[^p, ^s, M, W]) write_path_field() ! {
	if sink.path != none {
		sink.write_path()!
		if term := sink.summary.config.path_terminator {
			sink.write_all([term])!
		} else {
			sink.write_all(sink.summary.config.separator_field)!
		}
	}
}

/// If this printer has a file path associated with it, then this will
/// write that path to the underlying writer in the appropriate style
/// (color and hyperlink).
fn (mut sink SummarySink[^p, ^s, M, W]) write_path() ! {
	if path := sink.path {
		status := sink.start_hyperlink()!
		sink.write_spec(sink.summary.config.colors.path(), path.as_bytes())!
		sink.end_hyperlink(status)!
	}
}

/// Starts a hyperlink span when applicable.
fn (mut sink SummarySink[^p, ^s, M, W]) start_hyperlink() !InterpolatorStatus {
	if mut path := sink.path {
		hyperpath := path.as_hyperlink() or { return InterpolatorStatus.inactive() }
		values := Values.new(hyperpath)
		return sink.interpolator.begin(values, mut sink.summary.wtr)
	}
	return InterpolatorStatus.inactive()
}

fn (mut sink SummarySink[^p, ^s, M, W]) end_hyperlink(status InterpolatorStatus) ! {
	sink.interpolator.finish(status, mut sink.summary.wtr)!
}

/// Write the line terminator configured on the given searcher.
fn (mut sink SummarySink[^p, ^s, M, W]) write_line_term(searcher_ searcher.Searcher) ! {
	sink.write_all(searcher_.line_terminator().as_bytes())!
}

/// Write the given bytes using the give style.
fn (mut sink SummarySink[^p, ^s, M, W]) write_spec(spec ColorSpec, buf []u8) ! {
	sink.summary.wtr.set_color(spec)!
	sink.write_all(buf)!
	sink.summary.wtr.reset()!
}

/// Write all of the given bytes.
fn (mut sink SummarySink[^p, ^s, M, W]) write_all(buf []u8) ! {
	mut written := usize(0)
	for written < buf.len {
			n := sink.summary.wtr.write(buf[written..])!
			if n <= 0 {
				return error('failed to write all bytes')
			}
			written += usize(n)
	}
}

pub fn (mut sink SummarySink[^p, ^s, M, W]) matched(searcher_ searcher.Searcher, mat searcher.SinkMatch) !bool {
	is_multi_line := sink.multi_line(searcher_)
	sink_match_count := if sink.stats == none && !is_multi_line {
		u64(1)
	} else {
		// This gives us as many bytes as the searcher can offer. This
		// isn't guaranteed to hold the necessary context to get match
		// detection correct (because of look-around), but it does in
		// practice.
		buf := mat.buffer()
		range := mat.bytes_range_in_buffer()
		mut count := u64(0)
		find_iter_at_in_context(searcher_, sink.matcher, buf, range, fn [mut count] (_mat matcher.Match) bool {
			count++
			return true
		})!
		// Because of `find_iter_at_in_context` being a giant
		// kludge internally, it's possible that it won't find
		// *any* matches even though we clearly know that there is
		// at least one. So make sure we record at least one here.
		if count > 0 {
			count
		} else {
			1
		}
	}
	if is_multi_line {
		sink.match_count += sink_match_count
	} else {
		sink.match_count += 1
	}
	if sink.stats != none {
		mut stats := sink.stats or { panic('stats missing unexpectedly') }
		stats.add_matches(sink_match_count)
		stats.add_matched_lines(mat.lines().count())
		sink.stats = stats
	} else if sink.summary.config.kind.quit_early() {
		return false
	}
	return true
}

pub fn (mut sink SummarySink[^p, ^s, M, W]) context(searcher_ searcher.Searcher, ctx searcher.SinkContext) !bool {
	_ = sink
	_ = searcher_
	_ = ctx
	return true
}

pub fn (mut sink SummarySink[^p, ^s, M, W]) context_break(searcher_ searcher.Searcher) !bool {
	_ = sink
	_ = searcher_
	return true
}

pub fn (mut sink SummarySink[^p, ^s, M, W]) binary_data(searcher_ searcher.Searcher, binary_byte_offset u64) !bool {
	if searcher_.binary_detection().quit_byte() != none {
		if path := sink.path {
			log.debug('ignoring ${path.as_path()}: found binary data at offset ${binary_byte_offset}')
		}
	}
	return true
}

pub fn (mut sink SummarySink[^p, ^s, M, W]) begin(_searcher searcher.Searcher) !bool {
	if sink.path == none && sink.summary.config.kind.requires_path() {
		return error('output kind ${sink.summary.config.kind} requires a file path')
	}
	sink.summary.wtr.reset_count()
	sink.start_time = time.now()
	sink.match_count = 0
	sink.binary_byte_offset = none
	return true
}

pub fn (mut sink SummarySink[^p, ^s, M, W]) finish(searcher_ searcher.Searcher, finish searcher.SinkFinish) ! {
	sink.binary_byte_offset = finish.binary_byte_offset()
	if sink.stats != none {
		mut stats := sink.stats or { panic('stats missing unexpectedly') }
		stats.add_elapsed(time.since(sink.start_time))
		stats.add_searches(1)
		if sink.match_count > 0 {
			stats.add_searches_with_match(1)
		}
		stats.add_bytes_searched(finish.byte_count())
		stats.add_bytes_printed(sink.summary.wtr.count())
		sink.stats = stats
	}
	// If our binary detection method says to quit after seeing binary
	// data, then we shouldn't print any results at all, even if we've
	// found a match before detecting binary data. The intent here is to
	// keep BinaryDetection::quit as a form of filter. Otherwise, we can
	// present a matching file with a smaller number of matches than
	// there might be, which can be quite misleading.
	//
	// If our binary detection method is to convert binary data, then we
	// don't quit and therefore search the entire contents of the file.
	//
	// There is an unfortunate inconsistency here. Namely, when using
	// QuietWithMatch or PathWithMatch, then the printer can quit after the
	// first match seen, which could be long before seeing binary data.
	// This means that using PathWithMatch can print a path where as using
	// Count might not print it at all because of binary data.
	//
	// It's not possible to fix this without also potentially significantly
	// impacting the performance of QuietWithMatch or PathWithMatch, so we
	// accept the bug.
	if sink.binary_byte_offset != none && searcher_.binary_detection().quit_byte() != none {
		// Squash the match count. The statistics reported will still
		// contain the match count, but the "official" match count should
		// be zero.
		sink.match_count = 0
		return
	}

	show_count := !sink.summary.config.exclude_zero || sink.match_count > 0
	match sink.summary.config.kind {
		.count {
			if show_count {
				sink.write_path_field()!
				sink.write_all(DecimalFormatter.new(sink.match_count).as_bytes())!
				sink.write_line_term(searcher_)!
			}
		}
		.count_matches {
			if show_count {
				sink.write_path_field()!
				stats := sink.stats or { panic('CountMatches should enable stats tracking') }
				sink.write_all(DecimalFormatter.new(stats.matches()).as_bytes())!
				sink.write_line_term(searcher_)!
			}
		}
		.path_with_match {
			if sink.match_count > 0 {
				sink.write_path_line(searcher_)!
			}
		}
		.path_without_match {
			if sink.match_count == 0 {
				sink.write_path_line(searcher_)!
			}
		}
		.quiet_with_match, .quiet_without_match {}
	}
}
