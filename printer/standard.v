module printer

import log
import matcher
import searcher
import time

const standard_utf8_replacement_rune = rune(0xfffd)

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
///
/// For maximum portability, callers should generally use either
/// `termcolor::StandardStream` or `termcolor::BufferedStandardStream`
/// where appropriate, which will automatically enable colors on Windows
/// when possible.
///
/// However, callers may also provide an arbitrary writer using the
/// `termcolor::Ansi` or `termcolor::NoColor` wrappers, which always enable
/// colors via ANSI escapes or always disable colors, respectively.
///
/// As a convenience, callers may use `build_no_color` to automatically
/// select the `termcolor::NoColor` wrapper to avoid needing to import
/// from `termcolor` explicitly.
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
/// A [`UserColorSpec`](crate::UserColorSpec) can be constructed from
/// a string in accordance with the color specification format. See
/// the `UserColorSpec` type documentation for more details on the
/// format. A [`ColorSpecs`] can then be generated from zero or more
/// `UserColorSpec`s.
///
/// Regardless of the color specifications provided here, whether color
/// is actually used or not is determined by the implementation of
/// `WriteColor` provided to `build`. For example, if `termcolor::NoColor`
/// is provided to `build`, then no color will ever be printed regardless
/// of the color specifications provided here.
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
/// Regardless of the hyperlink format provided here, whether hyperlinks
/// are actually used or not is determined by the implementation of
/// `WriteColor` provided to `build`. For example, if `termcolor::NoColor`
/// is provided to `build`, then no hyperlinks will ever be printed
/// regardless of the format provided here.
///
/// This completely overrides any previous hyperlink format.
///
/// The default configuration results in not emitting any hyperlinks.
pub fn (mut builder StandardBuilder) hyperlink(config HyperlinkConfig) &StandardBuilder {
	builder.config.hyperlink = config
	return builder
}

/// Enable the gathering of various aggregate statistics.
///
/// When this is enabled (it's disabled by default), statistics will be
/// gathered for all uses of `Standard` printer returned by `build`,
/// including but not limited to, the total number of matches, the total
/// number of bytes searched and the total number of bytes printed.
///
/// Aggregate statistics can be accessed via the sink's
/// [`StandardSink::stats`] method.
///
/// When this is enabled, this printer may need to do extra work in order
/// to compute certain statistics, which could cause the search to take
/// longer.
///
/// For a complete description of available statistics, see [`Stats`].
pub fn (mut builder StandardBuilder) stats(yes bool) &StandardBuilder {
	builder.config.stats = yes
	return builder
}

/// Enable the use of "headings" in the printer.
///
/// When this is enabled, and if a file path has been given to the printer,
/// then the file path will be printed once on its own line before showing
/// any matches. If the heading is not the first thing emitted by the
/// printer, then a line terminator is printed before the heading.
///
/// By default, this option is disabled. When disabled, the printer will
/// not show any heading and will instead print the file path (if one is
/// given) on the same line as each matching (or context) line.
pub fn (mut builder StandardBuilder) heading(yes bool) &StandardBuilder {
	builder.config.heading = yes
	return builder
}

/// When enabled, if a path was given to the printer, then it is shown in
/// the output (either as a heading or as a prefix to each matching line).
/// When disabled, then no paths are ever included in the output even when
/// a path is provided to the printer.
///
/// This is enabled by default.
pub fn (mut builder StandardBuilder) path(yes bool) &StandardBuilder {
	builder.config.path = yes
	return builder
}

/// Only print the specific matches instead of the entire line containing
/// each match. Each match is printed on its own line. When multi line
/// search is enabled, then matches spanning multiple lines are printed
/// such that only the matching portions of each line are shown.
pub fn (mut builder StandardBuilder) only_matching(yes bool) &StandardBuilder {
	builder.config.only_matching = yes
	return builder
}

/// Print at least one line for every match.
///
/// This is similar to the `only_matching` option, except the entire line
/// is printed for each match. This is typically useful in conjunction with
/// the `column` option, which will show the starting column number for
/// every match on every line.
///
/// When multi-line mode is enabled, each match is printed, including every
/// line in the match. As with single line matches, if a line contains
/// multiple matches (even if only partially), then that line is printed
/// once for each match it participates in, assuming it's the first line in
/// that match. In multi-line mode, column numbers only indicate the start
/// of a match. Subsequent lines in a multi-line match always have a column
/// number of `1`.
///
/// When a match contains multiple lines, enabling `per_match_one_line`
/// will cause only the first line each in match to be printed.
pub fn (mut builder StandardBuilder) per_match(yes bool) &StandardBuilder {
	builder.config.per_match = yes
	return builder
}

/// Print at most one line per match when `per_match` is enabled.
///
/// By default, every line in each match found is printed when `per_match`
/// is enabled. However, this is sometimes undesirable, e.g., when you
/// only ever want one line per match.
///
/// This is only applicable when multi-line matching is enabled, since
/// otherwise, matches are guaranteed to span one line.
///
/// This is disabled by default.
pub fn (mut builder StandardBuilder) per_match_one_line(yes bool) &StandardBuilder {
	builder.config.per_match_one_line = yes
	return builder
}

/// Set the bytes that will be used to replace each occurrence of a match
/// found.
///
/// The replacement bytes given may include references to capturing groups,
/// which may either be in index form (e.g., `$2`) or can reference named
/// capturing groups if present in the original pattern (e.g., `$foo`).
///
/// For documentation on the full format, please see the `Capture` trait's
/// `interpolate` method in the
/// [grep-printer](https://docs.rs/grep-printer) crate.
pub fn (mut builder StandardBuilder) replacement(replacement ?[]u8) &StandardBuilder {
	builder.config.replacement = replacement
	return builder
}

/// Set the maximum number of columns allowed for each line printed. A
/// single column is heuristically defined as a single byte.
///
/// If a line is found which exceeds this maximum, then it is replaced
/// with a message indicating that the line has been omitted.
///
/// The default is to not specify a limit, in which each matching or
/// contextual line is printed regardless of how long it is.
pub fn (mut builder StandardBuilder) max_columns(limit ?u64) &StandardBuilder {
	builder.config.max_columns = limit
	return builder
}

/// When enabled, if a line is found to be over the configured maximum
/// column limit (measured in terms of bytes), then a preview of the long
/// line will be printed instead.
///
/// The preview will correspond to the first `N` *grapheme clusters* of
/// the line, where `N` is the limit configured by `max_columns`.
///
/// If no limit is set, then enabling this has no effect.
///
/// This is disabled by default.
pub fn (mut builder StandardBuilder) max_columns_preview(yes bool) &StandardBuilder {
	builder.config.max_columns_preview = yes
	return builder
}

/// Print the column number of the first match in a line.
///
/// This option is convenient for use with `per_match` which will print a
/// line for every match along with the starting offset for that match.
///
/// Column numbers are computed in terms of bytes from the start of the
/// line being printed.
///
/// This is disabled by default.
pub fn (mut builder StandardBuilder) column(yes bool) &StandardBuilder {
	builder.config.column = yes
	return builder
}

/// Print the absolute byte offset of the beginning of each line printed.
///
/// The absolute byte offset starts from the beginning of each search and
/// is zero based.
///
/// If the `only_matching` option is set, then this will print the absolute
/// byte offset of the beginning of each match.
pub fn (mut builder StandardBuilder) byte_offset(yes bool) &StandardBuilder {
	builder.config.byte_offset = yes
	return builder
}

/// When enabled, all lines will have prefix ASCII whitespace trimmed
/// before being written.
///
/// This is disabled by default.
pub fn (mut builder StandardBuilder) trim_ascii(yes bool) &StandardBuilder {
	builder.config.trim_ascii = yes
	return builder
}

/// Set the separator used between sets of search results.
///
/// When this is set, then it will be printed on its own line immediately
/// before the results for a single search if and only if a previous search
/// had already printed results. In effect, this permits showing a divider
/// between sets of search results that does not appear at the beginning
/// or end of all search results.
///
/// To reproduce the classic grep format, this is typically set to `--`
/// (the same as the context separator) if and only if contextual lines
/// have been requested, but disabled otherwise.
///
/// By default, this is disabled.
pub fn (mut builder StandardBuilder) separator_search(sep ?[]u8) &StandardBuilder {
	builder.config.separator_search = sep
	return builder
}

/// Set the separator used between discontiguous runs of search context,
/// but only when the searcher is configured to report contextual lines.
///
/// The separator is always printed on its own line, even if it's empty.
///
/// If no separator is set, then nothing is printed when a context break
/// occurs.
///
/// By default, this is set to `--`.
pub fn (mut builder StandardBuilder) separator_context(sep ?[]u8) &StandardBuilder {
	builder.config.separator_context = sep
	return builder
}

/// Set the separator used between fields emitted for matching lines.
///
/// For example, when the searcher has line numbers enabled, this printer
/// will print the line number before each matching line. The bytes given
/// here will be written after the line number but before the matching
/// line.
///
/// By default, this is set to `:`.
pub fn (mut builder StandardBuilder) separator_field_match(sep []u8) &StandardBuilder {
	builder.config.separator_field_match = sep
	return builder
}

/// Set the separator used between fields emitted for context lines.
///
/// For example, when the searcher has line numbers enabled, this printer
/// will print the line number before each context line. The bytes given
/// here will be written after the line number but before the context
/// line.
///
/// By default, this is set to `-`.
pub fn (mut builder StandardBuilder) separator_field_context(sep []u8) &StandardBuilder {
	builder.config.separator_field_context = sep
	return builder
}

/// Set the path separator used when printing file paths.
///
/// When a printer is configured with a file path, and when a match is
/// found, that file path will be printed (either as a heading or as a
/// prefix to each matching or contextual line, depending on other
/// configuration settings). Typically, printing is done by emitting the
/// file path as is. However, this setting provides the ability to use a
/// different path separator from what the current environment has
/// configured.
///
/// A typical use for this option is to permit cygwin users on Windows to
/// set the path separator to `/` instead of using the system default of
/// `\`.
pub fn (mut builder StandardBuilder) separator_path(sep ?u8) &StandardBuilder {
	builder.config.separator_path = sep
	return builder
}

/// Set the path terminator used.
///
/// The path terminator is a byte that is printed after every file path
/// emitted by this printer.
///
/// If no path terminator is set (the default), then paths are terminated
/// by either new lines (for when `heading` is enabled) or the match or
/// context field separators (e.g., `:` or `-`).
pub fn (mut builder StandardBuilder) path_terminator(terminator ?u8) &StandardBuilder {
	builder.config.path_terminator = terminator
	return builder
}

/// The standard printer, which implements grep-like formatting, including
/// color support.
///
/// A default printer can be created with either of the `Standard::new` or
/// `Standard::new_no_color` constructors. However, there are a considerable
/// number of options that configure this printer's output. Those options can
/// be configured using [`StandardBuilder`].
///
/// This type is generic over `W`, which represents any implementation
/// of the `termcolor::WriteColor` trait. If colors are not desired,
/// then the `new_no_color` constructor can be used, or, alternatively,
/// the `termcolor::NoColor` adapter can be used to wrap any `io::Write`
/// implementation without enabling any colors.
pub struct Standard[W] {
	config StandardConfig
mut:
	wtr     CounterWriter[W]
	matches []matcher.Match
}

/// Return a standard printer with a default configuration that writes
/// matches to the given writer.
///
/// The writer should be an implementation of `termcolor::WriteColor`
/// and not just a bare implementation of `io::Write`. To use a normal
/// `io::Write` implementation (simultaneously sacrificing colors), use
/// the `new_no_color` constructor.
pub fn Standard.new[W](wtr W) Standard[W] {
	return StandardBuilder.new().build(wtr)
}

/// Return a standard printer with a default configuration that writes
/// matches to the given writer.
///
/// The writer can be any implementation of `io::Write`. With this
/// constructor, the printer will never emit colors.
pub fn Standard.new_no_color[W](wtr W) Standard[NoColor[W]] {
	return StandardBuilder.new().build_no_color(wtr)
}

/// Return an implementation of `Sink` for the standard printer.
///
/// This does not associate the printer with a file path, which means this
/// implementation will never print a file path along with the matches.
pub fn (mut standard Standard[W]) sink[^s](matcher_ PrinterMatcher) StandardSink[^s, ^s, W] {
	return StandardSink[^s, ^s, W]{
		matcher:                 matcher_
		standard:                &standard
		replacer:                Replacer{}
		interpolator:            Interpolator.new(standard.config.hyperlink)
		path:                    none
		start_time:              time.now()
		match_count:             0
		binary_byte_offset:      none
		stats:                   Stats.new()
		has_stats:               standard.config.stats
		needs_match_granularity: standard.needs_match_granularity()
	}
}

/// Return an implementation of `Sink` associated with a file path.
///
/// When the printer is associated with a path, then it may, depending on
/// its configuration, print the path along with the matches found.
pub fn (mut standard Standard[W]) sink_with_path[^p, ^s](matcher_ PrinterMatcher, path &^p string) StandardSink[^p, ^s, W] {
	if !standard.config.path {
		return standard.sink(matcher_)
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
		stats:                   Stats.new()
		has_stats:               standard.config.stats
		needs_match_granularity: standard.needs_match_granularity()
	}
}

/// Returns true if and only if the configuration of the printer requires
/// us to find each individual match in the lines reported by the searcher.
///
/// We care about this distinction because finding each individual match
/// costs more, so we only do it when we need to.
fn (standard Standard[W]) needs_match_granularity() bool {
	mut supports_color := false
	$if W is WriteColor {
		supports_color = standard.wtr.wtr.supports_color()
	}
	match_colored := !standard.config.colors.matched().is_none()
	// Coloring requires identifying each individual match.
	return (supports_color && match_colored)
		// The column feature requires finding the position of the first match.
		|| standard.config.column
		// Requires finding each match for performing replacement.
		|| standard.config.replacement != none
		// Emitting a line for each match requires finding each match.
		|| standard.config.per_match
		// Emitting only the match requires finding each match.
		|| standard.config.only_matching
		// Computing certain statistics requires finding each match.
		|| standard.config.stats
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
///
/// A `Sink` can be created via the [`Standard::sink`] or
/// [`Standard::sink_with_path`] methods, depending on whether you want to
/// include a file path in the printer's output.
///
/// Building a `StandardSink` is cheap, and callers should create a new one
/// for each thing that is searched. After a search has completed, callers may
/// query this sink for information such as whether a match occurred or whether
/// binary data was found (and if so, the offset at which it occurred).
///
/// This type is generic over a few type parameters:
///
/// * `'p` refers to the lifetime of the file path, if one is provided. When
/// no file path is given, then this is `'static`.
/// * `'s` refers to the lifetime of the [`Standard`] printer that this type
/// borrows.
/// * `M` refers to the type of matcher used by
/// `grep_searcher::Searcher` that is reporting results to this sink.
/// * `W` refers to the underlying writer that this printer is writing its
/// output to.
pub struct StandardSink[^p, ^s, W] implements Drop {
	matcher PrinterMatcher
mut:
	standard                &^s Standard[W]
	replacer                Replacer
	interpolator            Interpolator
	path                    ?PrinterPath[^p]
	start_time              time.Time
	match_count             u64
	binary_byte_offset      ?u64
	stats                   Stats
	has_stats               bool
	needs_match_granularity bool
}

fn (mut sink StandardSink[^p, ^s, W]) drop[^p, ^s]() {
	sink.matcher.drop()
	sink.replacer.free()
	sink.interpolator.free()
	if mut path := sink.path {
		path.free()
		sink.path = ?PrinterPath(none)
	}
}

/// Release resources owned by this sink once its search is complete.
pub fn (mut sink StandardSink[^p, ^s, W]) free[^p, ^s]() {
	sink.drop()
}

/// Returns true if and only if this printer received a match in the
/// previous search.
///
/// This is unaffected by the result of searches before the previous
/// search on this sink.
pub fn (sink &StandardSink[^p, ^s, W]) has_match[^p, ^s]() bool {
	return sink.match_count > 0
}

/// Return the total number of matches reported to this sink.
///
/// This corresponds to the number of times `Sink::matched` is called
/// on the previous search.
///
/// This is unaffected by the result of searches before the previous
/// search on this sink.
pub fn (sink StandardSink[^p, ^s, W]) match_count[^p, ^s]() u64 {
	return sink.match_count
}

/// If binary data was found in the previous search, this returns the
/// offset at which the binary data was first detected.
///
/// The offset returned is an absolute offset relative to the entire
/// set of bytes searched.
///
/// This is unaffected by the result of searches before the previous
/// search. e.g., If the search prior to the previous search found binary
/// data but the previous search found no binary data, then this will
/// return `None`.
pub fn (sink StandardSink[^p, ^s, W]) binary_byte_offset[^p, ^s]() ?u64 {
	return sink.binary_byte_offset
}

/// Return a reference to the stats produced by the printer for all
/// searches executed on this sink.
///
/// This only returns stats if they were requested via the
/// [`StandardBuilder`] configuration.
pub fn (sink &^a StandardSink[^p, ^s, W]) stats[^a, ^p, ^s]() ?&^a Stats {
	if sink.has_stats {
		return &sink.stats
	}
	return none
}

/// Execute the matcher over the given bytes and record the match
/// locations if the current configuration demands match granularity.
fn (mut sink StandardSink[^p, ^s, W]) record_matches[^p, ^s](searcher_ searcher.Searcher, bytes []u8, range matcher.Match) ! {
	sink.standard.matches = []matcher.Match{}
	if !sink.needs_match_granularity {
		return
	}
	// If printing requires knowing the location of each individual match,
	// then compute and stored those right now for use later. While this
	// adds an extra copy for storing the matches, we do amortize the
	// allocation for it and this greatly simplifies the printing logic to
	// the extent that it's easy to ensure that we never do more than
	// one search to find the matches (well, for replacements, we do one
	// additional search to perform the actual replacement).
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

/// If the configuration specifies a replacement, then this executes the
/// replacement, lazily allocating memory if necessary.
///
/// To access the result of a replacement, use `replacer.replacement()`.
fn (mut sink StandardSink[^p, ^s, W]) replace[^p, ^s](searcher_ searcher.Searcher, bytes []u8, range matcher.Match) ! {
	sink.replacer.clear()
	if replacement := sink.standard.config.replacement {
		sink.replacer.replace_all(searcher_, sink.matcher, bytes, range, replacement)!
	}
}

pub fn (mut sink StandardSink[^p, ^s, W]) matched[^p, ^s](searcher_ searcher.Searcher, mat searcher.SinkMatch) !bool {
	sink.match_count++
	sink.record_matches(searcher_, mat.buffer(), mat.bytes_range_in_buffer())!
	sink.replace(searcher_, mat.buffer(), mat.bytes_range_in_buffer())!
	if sink.has_stats {
		sink.stats.add_matches(u64(sink.standard.matches.len))
		sink.stats.add_matched_lines(mat.lines().count())
	}
	if searcher_.binary_detection().convert_byte() != none {
		if sink.binary_byte_offset != none {
			return false
		}
	}
	mut imp := StandardImpl.from_match(searcher_, &sink, mat)
	imp.sink()!
	return true
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
	if sink.has_stats {
		sink.stats.add_elapsed(time.since(sink.start_time))
		sink.stats.add_searches(1)
		if sink.match_count > 0 {
			sink.stats.add_searches_with_match(1)
		}
		sink.stats.add_bytes_searched(finish.byte_count())
		sink.stats.add_bytes_printed(sink.standard.wtr.count())
	}
}

/// The actual implementation of the standard printer. This couples together
/// the searcher, the sink implementation and information about the match.
///
/// A StandardImpl is initialized every time a match or a contextual line is
/// reported.
struct StandardImpl[^p, ^s, W] {
	searcher searcher.Searcher
mut:
	sink           &^s StandardSink[^p, ^s, W]
	sunk           Sunk
	/// Set to true if and only if we are writing a match with color.
	in_color_match bool
}

/// Bundle self with a searcher and return the core implementation of Sink.
fn StandardImpl.new[^p, ^s, W](searcher_ searcher.Searcher, sink &^s StandardSink[^p, ^s, W]) StandardImpl[^p, ^s, W] {
	return StandardImpl[^p, ^s, W]{
		searcher: searcher_
		sink:     sink
		sunk:     Sunk.empty()
	}
}

/// Bundle self with a searcher and return the core implementation of Sink
/// for use with handling matching lines.
fn StandardImpl.from_match[^p, ^s, W](searcher_ searcher.Searcher, sink &^s StandardSink[^p, ^s, W], mat searcher.SinkMatch) StandardImpl[^p, ^s, W] {
	sunk := Sunk.from_sink_match(mat, sink.standard.matches, sink.replacer.replacement())
	return StandardImpl[^p, ^s, W]{
		searcher: searcher_
		sink:     sink
		sunk:     sunk
	}
}

/// Bundle self with a searcher and return the core implementation of Sink
/// for use with handling contextual lines.
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

/// Print matches (limited to one line) quickly by avoiding the detection
/// of each individual match in the lines reported in the given
/// `SinkMatch`.
///
/// This should only be used when the configuration does not demand match
/// granularity and the searcher is not in multi line mode.
fn (mut imp StandardImpl[^p, ^s, W]) sink_fast[^p, ^s]() ! {
	$if debug {
		assert imp.sunk.matches().len == 0
		assert !imp.multi_line() || imp.is_context()
	}
	imp.write_prelude(imp.sunk.absolute_byte_offset(), imp.sunk.line_number(), none)!
	imp.write_line(imp.sunk.bytes())!
}

/// Print matches (possibly spanning more than one line) quickly by
/// avoiding the detection of each individual match in the lines reported
/// in the given `SinkMatch`.
///
/// This should only be used when the configuration does not demand match
/// granularity. This may be used when the searcher is in multi line mode.
fn (mut imp StandardImpl[^p, ^s, W]) sink_fast_multi_line[^p, ^s]() ! {
	$if debug {
		assert imp.sunk.matches().len == 0
		// This isn't actually a required invariant for using this method,
		// but if we wind up here and multi line mode is disabled, then we
		// should still treat it as a bug since we should be using matched_fast
		// instead.
		assert imp.multi_line()
	}
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

/// Print a matching line where the configuration of the printer requires
/// finding each individual match (e.g., for coloring).
fn (mut imp StandardImpl[^p, ^s, W]) sink_slow[^p, ^s]() ! {
	$if debug {
		assert imp.sunk.matches().len > 0
		assert !imp.multi_line() || imp.is_context()
	}
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
	$if debug {
		assert imp.sunk.matches().len > 0
		assert imp.multi_line()
	}
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
			// It turns out that vimgrep really only wants one line per
			// match, even when a match spans multiple lines. So when
			// that option is enabled, we just quit after printing the
			// first line.
			//
			// See: https://github.com/BurntSushi/ripgrep/issues/1866
			if imp.config().per_match_one_line {
				break
			}
		}
	}
}

/// Write the beginning part of a matching line. This (may) include things
/// like the file path, line number among others, depending on the
/// configuration and the parameters given.
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
	mut range := matcher.Match.new(0, line.len)
	if imp.config().trim_ascii {
		lineterm := imp.searcher.line_terminator()
		range = trim_ascii_prefix(lineterm, line, range)
	}
	trimmed := line[range.start()..range.end()]
	if imp.exceeds_max_columns(trimmed) {
		full_range := matcher.Match.new(0, trimmed.len)
		mut zero := usize(0)
		imp.write_exceeded_line(trimmed, full_range, imp.sunk.matches(), mut zero)!
	} else {
		imp.write(trimmed)!
		if !imp.has_line_terminator(trimmed) {
			imp.write_line_term()!
		}
	}
}

fn (mut imp StandardImpl[^p, ^s, W]) write_colored_line[^p, ^s](matches []matcher.Match, bytes []u8) ! {
	// If we know we aren't going to emit color, then we can go faster.
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

/// Write the `line` portion of `bytes`, with appropriate coloring for
/// each `match`, starting at `match_index`.
///
/// This accounts for trimming any whitespace prefix and will *never* print
/// a line terminator. If a match exceeds the range specified by `line`,
/// then only the part of the match within `line` (if any) is printed.
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
		preview_end := grapheme_preview_end(bytes, line, limit)
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

/// If this printer has a file path associated with it, then this will
/// write that path to the underlying writer followed by a line terminator.
/// (If a path terminator is set, then that is used instead of the line
/// terminator.)
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
	imp.sink.standard.wtr.set_color(spec)!
	imp.write(buf)!
	imp.sink.standard.wtr.reset()!
}

fn (mut imp StandardImpl[^p, ^s, W]) write_path[^p, ^s](mut path PrinterPath[^p]) ! {
	spec := imp.config().colors.path()
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

/// Return the underlying configuration for this printer.
fn (imp StandardImpl[^p, ^s, W]) config[^p, ^s]() &^s StandardConfig {
	return &imp.sink.standard.config
}

/// Return the path associated with this printer, if one exists.
fn (imp StandardImpl[^p, ^s, W]) path[^p, ^s]() ?&^s PrinterPath[^p] {
	if imp.sink.path != none {
		return unsafe { &imp.sink.path? }
	}
	return none
}

/// Return the appropriate field separator based on whether we are emitting
/// matching or contextual lines.
fn (imp StandardImpl[^p, ^s, W]) separator_field[^p, ^s]() &^s []u8 {
	if imp.is_context() {
		return &imp.config().separator_field_context
	}
	return &imp.config().separator_field_match
}

/// Returns true if and only if the given line exceeds the maximum number
/// of columns set. If no maximum is set, then this always returns false.
fn (imp StandardImpl[^p, ^s, W]) exceeds_max_columns[^p, ^s](line []u8) bool {
	if max := imp.config().max_columns {
		return u64(line.len) > max
	}
	return false
}

/// Returns true if and only if the searcher may report matches over
/// multiple lines.
///
/// Note that this doesn't just return whether the searcher is in multi
/// line mode, but also checks if the matter can match over multiple lines.
/// If it can't, then we don't need multi line handling, even if the
/// searcher has multi line mode enabled.
fn (imp StandardImpl[^p, ^s, W]) multi_line[^p, ^s]() bool {
	return printer_matcher_multi_line(imp.searcher, imp.sink.matcher)
}

fn (imp StandardImpl[^p, ^s, W]) trim_line_terminator[^p, ^s](buf []u8, mut line matcher.Match) {
	line2, _ := trim_line_terminator(imp.searcher, buf, line)
	line = line2
}

/// Trim prefix ASCII spaces from the given slice and return the
/// corresponding range.
///
/// This stops trimming a prefix as soon as it sees non-whitespace or a
/// line terminator.
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

// V-specific: `bstr::ByteSlice::grapheme_indices` treats invalid UTF-8
// lossily. Decode the original byte range while retaining each rune's byte
// width so the grapheme boundary maps back to the correct byte offset.
fn grapheme_preview_end(bytes []u8, line matcher.Match, limit usize) usize {
	if limit == 0 || line.is_empty() {
		return line.start()
	}
	mut runes := []rune{cap: int(line.end() - line.start())}
	mut widths := []usize{cap: int(line.end() - line.start())}
	mut at := line.start()
	for at < line.end() {
		r, width := decode_utf8_lossy(bytes, at, line.end())
		runes << r
		widths << width
		at += width
	}
	mut end := line.start()
	mut rune_index := 0
	mut taken := usize(0)
	graphemes := runes.string().graphemes()
	for grapheme in graphemes {
		if taken >= limit {
			break
		}
		for _ in grapheme.runes() {
			end += widths[rune_index]
			rune_index++
		}
		taken++
	}
	return end
}

fn decode_utf8_lossy(bytes []u8, at usize, end usize) (rune, usize) {
	b0 := bytes[at]
	if b0 < 0x80 {
		return rune(b0), 1
	}
	if b0 < 0xc2 || b0 >= 0xf5 {
		return standard_utf8_replacement_rune, 1
	}
	if at + 1 >= end {
		return standard_utf8_replacement_rune, 1
	}
	b1 := bytes[at + 1]
	if b1 < 0x80 || b1 > 0xbf {
		return standard_utf8_replacement_rune, 1
	}
	if b0 < 0xe0 {
		return rune((u32(b0 & 0x1f) << 6) | u32(b1 & 0x3f)), 2
	}
	if (b0 == 0xe0 && b1 < 0xa0) || (b0 == 0xed && b1 >= 0xa0) {
		return standard_utf8_replacement_rune, 1
	}
	if at + 2 >= end {
		return standard_utf8_replacement_rune, 2
	}
	b2 := bytes[at + 2]
	if b2 < 0x80 || b2 > 0xbf {
		return standard_utf8_replacement_rune, 2
	}
	if b0 < 0xf0 {
		return rune((u32(b0 & 0x0f) << 12) | (u32(b1 & 0x3f) << 6) | u32(b2 & 0x3f)), 3
	}
	if (b0 == 0xf0 && b1 < 0x90) || (b0 == 0xf4 && b1 >= 0x90) {
		return standard_utf8_replacement_rune, 1
	}
	if at + 3 >= end {
		return standard_utf8_replacement_rune, 3
	}
	b3 := bytes[at + 3]
	if b3 < 0x80 || b3 > 0xbf {
		return standard_utf8_replacement_rune, 3
	}
	return rune((u32(b0 & 0x07) << 18) | (u32(b1 & 0x3f) << 12) | (u32(b2 & 0x3f) << 6) |
		u32(b3 & 0x3f)), 4
}
