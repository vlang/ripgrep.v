module printer

import log
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
///
/// Some configuration options, such as whether line numbers are included or
/// whether contextual lines are shown, are drawn directly from the
/// `grep_searcher::Searcher`'s configuration.
///
/// Once a `JSON` printer is built, its configuration cannot be changed.
pub struct JSONBuilder implements IClone {
mut:
	config JSONConfig
}

/// Return a new builder for configuring the JSON printer.
pub fn JSONBuilder.new() JSONBuilder {
	return JSONBuilder{}
}

/// Create a JSON printer that writes results to the given writer.
pub fn (builder &JSONBuilder) build[W](wtr W) JSON[W] {
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
///
/// When disabled, the `begin` and `end` messages are only shown if there
/// is at least one `match` or `context` message.
///
/// This is disabled by default.
pub fn (mut builder JSONBuilder) always_begin_end(yes bool) &JSONBuilder {
	builder.config.always_begin_end = yes
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
pub fn (mut builder JSONBuilder) replacement(replacement ?[]u8) &JSONBuilder {
	builder.config.replacement = replacement
	return builder
}

/// The JSON printer, which emits results in a JSON lines format.
///
/// This type is generic over `W`, which represents any implementation of
/// the standard library `io::Write` trait.
///
/// # Format
///
/// This section describes the JSON format used by this printer.
///
/// To skip the rigamarole, take a look at the
/// [example](#example)
/// at the end.
///
/// ## Overview
///
/// The format of this printer is the [JSON Lines](https://jsonlines.org/)
/// format. Specifically, this printer emits a sequence of messages, where
/// each message is encoded as a single JSON value on a single line. There are
/// four different types of messages (and this number may expand over time):
///
/// * **begin** - A message that indicates a file is being searched.
/// * **end** - A message the indicates a file is done being searched. This
///   message also include summary statistics about the search.
/// * **match** - A message that indicates a match was found. This includes
///   the text and offsets of the match.
/// * **context** - A message that indicates a contextual line was found.
///   This includes the text of the line, along with any match information if
///   the search was inverted.
///
/// Every message is encoded in the same envelope format, which includes a tag
/// indicating the message type along with an object for the payload:
///
/// ```json
/// {
///     "type": "{begin|end|match|context}",
///     "data": { ... }
/// }
/// ```
///
/// The message itself is encoded in the envelope's `data` key.
///
/// ## Text encoding
///
/// Before describing each message format, we first must briefly discuss text
/// encoding, since it factors into every type of message. In particular, JSON
/// may only be encoded in UTF-8, UTF-16 or UTF-32. For the purposes of this
/// printer, we need only worry about UTF-8. The problem here is that searching
/// is not limited to UTF-8 exclusively, which in turn implies that matches
/// may be reported that contain invalid UTF-8. Moreover, this printer may
/// also print file paths, and the encoding of file paths is itself not
/// guaranteed to be valid UTF-8. Therefore, this printer must deal with the
/// presence of invalid UTF-8 somehow. The printer could silently ignore such
/// things completely, or even lossily transcode invalid UTF-8 to valid UTF-8
/// by replacing all invalid sequences with the Unicode replacement character.
/// However, this would prevent consumers of this format from accessing the
/// original data in a non-lossy way.
///
/// Therefore, this printer will emit valid UTF-8 encoded bytes as normal
/// JSON strings and otherwise base64 encode data that isn't valid UTF-8. To
/// communicate whether this process occurs or not, strings are keyed by the
/// name `text` where as arbitrary bytes are keyed by `bytes`.
///
/// For example, when a path is included in a message, it is formatted like so,
/// if and only if the path is valid UTF-8:
///
/// ```json
/// {
///     "path": {
///         "text": "/home/ubuntu/lib.rs"
///     }
/// }
/// ```
///
/// If instead our path was `/home/ubuntu/lib\xFF.rs`, where the `\xFF` byte
/// makes it invalid UTF-8, the path would instead be encoded like so:
///
/// ```json
/// {
///     "path": {
///         "bytes": "L2hvbWUvdWJ1bnR1L2xpYv8ucnM="
///     }
/// }
/// ```
///
/// This same representation is used for reporting matches as well.
///
/// The printer guarantees that the `text` field is used whenever the
/// underlying bytes are valid UTF-8.
///
/// ## Wire format
///
/// This section documents the wire format emitted by this printer, starting
/// with the four types of messages.
///
/// Each message has its own format, and is contained inside an envelope that
/// indicates the type of message. The envelope has these fields:
///
/// * **type** - A string indicating the type of this message. It may be one
///   of four possible strings: `begin`, `end`, `match` or `context`. This
///   list may expand over time.
/// * **data** - The actual message data. The format of this field depends on
///   the value of `type`. The possible message formats are
///   [`begin`](#message-begin),
///   [`end`](#message-end),
///   [`match`](#message-match),
///   [`context`](#message-context).
///
/// #### Message: **begin**
///
/// This message indicates that a search has begun. It has these fields:
///
/// * **path** - An
///   [arbitrary data object](#object-arbitrary-data)
///   representing the file path corresponding to the search, if one is
///   present. If no file path is available, then this field is `null`.
///
/// #### Message: **end**
///
/// This message indicates that a search has finished. It has these fields:
///
/// * **path** - An
///   [arbitrary data object](#object-arbitrary-data)
///   representing the file path corresponding to the search, if one is
///   present. If no file path is available, then this field is `null`.
/// * **binary_offset** - The absolute offset in the data searched
///   corresponding to the place at which binary data was detected. If no
///   binary data was detected (or if binary detection was disabled), then this
///   field is `null`.
/// * **stats** - A [`stats` object](#object-stats) that contains summary
///   statistics for the previous search.
///
/// #### Message: **match**
///
/// This message indicates that a match has been found. A match generally
/// corresponds to a single line of text, although it may correspond to
/// multiple lines if the search can emit matches over multiple lines. It
/// has these fields:
///
/// * **path** - An
///   [arbitrary data object](#object-arbitrary-data)
///   representing the file path corresponding to the search, if one is
///   present. If no file path is available, then this field is `null`.
/// * **lines** - An
///   [arbitrary data object](#object-arbitrary-data)
///   representing one or more lines contained in this match.
/// * **line_number** - If the searcher has been configured to report line
///   numbers, then this corresponds to the line number of the first line
///   in `lines`. If no line numbers are available, then this is `null`.
/// * **absolute_offset** - The absolute byte offset corresponding to the start
///   of `lines` in the data being searched.
/// * **submatches** - An array of [`submatch` objects](#object-submatch)
///   corresponding to matches in `lines`. The offsets included in each
///   `submatch` correspond to byte offsets into `lines`. (If `lines` is base64
///   encoded, then the byte offsets correspond to the data after base64
///   decoding.) The `submatch` objects are guaranteed to be sorted by their
///   starting offsets. Note that it is possible for this array to be empty,
///   for example, when searching reports inverted matches. If the configuration
///   specifies a replacement, the resulting replacement text is also present.
///
/// #### Message: **context**
///
/// This message indicates that a contextual line has been found. A contextual
/// line is a line that doesn't contain a match, but is generally adjacent to
/// a line that does contain a match. The precise way in which contextual lines
/// are reported is determined by the searcher. It has these fields, which are
/// exactly the same fields found in a [`match`](#message-match):
///
/// * **path** - An
///   [arbitrary data object](#object-arbitrary-data)
///   representing the file path corresponding to the search, if one is
///   present. If no file path is available, then this field is `null`.
/// * **lines** - An
///   [arbitrary data object](#object-arbitrary-data)
///   representing one or more lines contained in this context. This includes
///   line terminators, if they're present.
/// * **line_number** - If the searcher has been configured to report line
///   numbers, then this corresponds to the line number of the first line
///   in `lines`. If no line numbers are available, then this is `null`.
/// * **absolute_offset** - The absolute byte offset corresponding to the start
///   of `lines` in the data being searched.
/// * **submatches** - An array of [`submatch` objects](#object-submatch)
///   corresponding to matches in `lines`. The offsets included in each
///   `submatch` correspond to byte offsets into `lines`. (If `lines` is base64
///   encoded, then the byte offsets correspond to the data after base64
///   decoding.) The `submatch` objects are guaranteed to be sorted by
///   their starting offsets. Note that it is possible for this array to be
///   non-empty, for example, when searching reports inverted matches such that
///   the original matcher could match things in the contextual lines. If the
///   configuration specifies a replacemement, the resulting replacement text
///   is also present.
///
/// #### Object: **submatch**
///
/// This object describes submatches found within `match` or `context`
/// messages. The `start` and `end` fields indicate the half-open interval on
/// which the match occurs (`start` is included, but `end` is not). It is
/// guaranteed that `start <= end`. It has these fields:
///
/// * **match** - An
///   [arbitrary data object](#object-arbitrary-data)
///   corresponding to the text in this submatch.
/// * **start** - A byte offset indicating the start of this match. This offset
///   is generally reported in terms of the parent object's data. For example,
///   the `lines` field in the
///   [`match`](#message-match) or [`context`](#message-context)
///   messages.
/// * **end** - A byte offset indicating the end of this match. This offset
///   is generally reported in terms of the parent object's data. For example,
///   the `lines` field in the
///   [`match`](#message-match) or [`context`](#message-context)
///   messages.
/// * **replacement** (optional) - An
///   [arbitrary data object](#object-arbitrary-data) corresponding to the
///   replacement text for this submatch, if the configuration specifies
///   a replacement.
///
/// #### Object: **stats**
///
/// This object is included in messages and contains summary statistics about
/// a search. It has these fields:
///
/// * **elapsed** - A [`duration` object](#object-duration) describing the
///   length of time that elapsed while performing the search.
/// * **searches** - The number of searches that have run. For this printer,
///   this value is always `1`. (Implementations may emit additional message
///   types that use this same `stats` object that represents summary
///   statistics over multiple searches.)
/// * **searches_with_match** - The number of searches that have run that have
///   found at least one match. This is never more than `searches`.
/// * **bytes_searched** - The total number of bytes that have been searched.
/// * **bytes_printed** - The total number of bytes that have been printed.
///   This includes everything emitted by this printer.
/// * **matched_lines** - The total number of lines that participated in a
///   match. When matches may contain multiple lines, then this includes every
///   line that is part of every match.
/// * **matches** - The total number of matches. There may be multiple matches
///   per line. When matches may contain multiple lines, each match is counted
///   only once, regardless of how many lines it spans.
///
/// #### Object: **duration**
///
/// This object includes a few fields for describing a duration. Two of its
/// fields, `secs` and `nanos`, can be combined to give nanosecond precision
/// on systems that support it. It has these fields:
///
/// * **secs** - A whole number of seconds indicating the length of this
///   duration.
/// * **nanos** - A fractional part of this duration represent by nanoseconds.
///   If nanosecond precision isn't supported, then this is typically rounded
///   up to the nearest number of nanoseconds.
/// * **human** - A human readable string describing the length of the
///   duration. The format of the string is itself unspecified.
///
/// #### Object: **arbitrary data**
///
/// This object is used whenever arbitrary data needs to be represented as a
/// JSON value. This object contains two fields, where generally only one of
/// the fields is present:
///
/// * **text** - A normal JSON string that is UTF-8 encoded. This field is
///   populated if and only if the underlying data is valid UTF-8.
/// * **bytes** - A normal JSON string that is a base64 encoding of the
///   underlying bytes.
///
/// More information on the motivation for this representation can be seen in
/// the section [text encoding](#text-encoding) above.
///
/// ## Example
///
/// This section shows a small example that includes all message types.
///
/// Here's the file we want to search, located at `/home/andrew/sherlock`:
///
/// ```text
/// For the Doctor Watsons of this world, as opposed to the Sherlock
/// Holmeses, success in the province of detective work must always
/// be, to a very large extent, the result of luck. Sherlock Holmes
/// can extract a clew from a wisp of straw or a flake of cigar ash;
/// but Doctor Watson has to have it taken out for him and dusted,
/// and exhibited clearly, with a label attached.
/// ```
///
/// Searching for `Watson` with a `before_context` of `1` with line numbers
/// enabled shows something like this using the standard printer:
///
/// ```text
/// sherlock:1:For the Doctor Watsons of this world, as opposed to the Sherlock
/// --
/// sherlock-4-can extract a clew from a wisp of straw or a flake of cigar ash;
/// sherlock:5:but Doctor Watson has to have it taken out for him and dusted,
/// ```
///
/// Here's what the same search looks like using the JSON wire format described
/// above, where in we show semi-prettified JSON (instead of a strict JSON
/// Lines format), for illustrative purposes:
///
/// ```json
/// {
///   "type": "begin",
///   "data": {
///     "path": {"text": "/home/andrew/sherlock"}}
///   }
/// }
/// {
///   "type": "match",
///   "data": {
///     "path": {"text": "/home/andrew/sherlock"},
///     "lines": {"text": "For the Doctor Watsons of this world, as opposed to the Sherlock\n"},
///     "line_number": 1,
///     "absolute_offset": 0,
///     "submatches": [
///       {"match": {"text": "Watson"}, "start": 15, "end": 21}
///     ]
///   }
/// }
/// {
///   "type": "context",
///   "data": {
///     "path": {"text": "/home/andrew/sherlock"},
///     "lines": {"text": "can extract a clew from a wisp of straw or a flake of cigar ash;\n"},
///     "line_number": 4,
///     "absolute_offset": 193,
///     "submatches": []
///   }
/// }
/// {
///   "type": "match",
///   "data": {
///     "path": {"text": "/home/andrew/sherlock"},
///     "lines": {"text": "but Doctor Watson has to have it taken out for him and dusted,\n"},
///     "line_number": 5,
///     "absolute_offset": 258,
///     "submatches": [
///       {"match": {"text": "Watson"}, "start": 11, "end": 17}
///     ]
///   }
/// }
/// {
///   "type": "end",
///   "data": {
///     "path": {"text": "/home/andrew/sherlock"},
///     "binary_offset": null,
///     "stats": {
///       "elapsed": {"secs": 0, "nanos": 36296, "human": "0.0000s"},
///       "searches": 1,
///       "searches_with_match": 1,
///       "bytes_searched": 367,
///       "bytes_printed": 1151,
///       "matched_lines": 2,
///       "matches": 2
///     }
///   }
/// }
/// ```
/// and here's what a match type item would looks like if a replacement text
/// of 'Moriarity' was given as a parameter:
/// ```json
/// {
///   "type": "match",
///   "data": {
///     "path": {"text": "/home/andrew/sherlock"},
///     "lines": {"text": "For the Doctor Watsons of this world, as opposed to the Sherlock\n"},
///     "line_number": 1,
///     "absolute_offset": 0,
///     "submatches": [
///       {"match": {"text": "Watson"}, "replacement": {"text": "Moriarity"}, "start": 15, "end": 21}
///     ]
///   }
/// }
/// ```
pub struct JSON[W] implements IClone {
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
		path:       path
		start_time: time.now()
		stats_:     Stats.new()
	}
}

/// Write the given message followed by a new line. The new line is
/// determined from the configuration of the given searcher.
fn (mut json JSON[W]) write_message(message Message) ! {
	encoded := if json.config.pretty { message.to_json_pretty() } else { message.to_json() }
	json.write(encoded.bytes())!
	json.write([u8(`\n`)])!
}

/// Returns true if and only if this printer has written at least one byte
/// to the underlying writer during any of the previous searches.
pub fn (json &JSON[W]) has_written() bool {
	return json.wtr.total_count() > 0
}

/// Return a mutable reference to the underlying writer.
pub fn (mut json JSON[W]) get_mut() &W {
	return json.wtr.get_mut()
}

/// Flush the underlying writer.
// V-specific: the translated printer sum type uses this to flush every
// concrete printer uniformly.
pub fn (mut json JSON[W]) flush() ! {
	json.wtr.flush()!
}

/// Consume this printer and return back ownership of the underlying
/// writer.
pub fn (json JSON[W]) into_inner() W {
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
///
/// This type is generic over a few type parameters:
///
/// * `^p` refers to the lifetime of the file path, if one is provided. When
/// no file path is given, then this is the sink lifetime.
/// * `^s` refers to the lifetime of the `JSON` printer that this type borrows.
/// * `W` refers to the underlying writer that this printer is writing its
/// output to.
pub struct JSONSink[^p, ^s, W] implements Drop {
	matcher PrinterMatcher
mut:
	replacer           Replacer
	json               &^s JSON[W]
	path               ?&^p string
	start_time         time.Time
	match_count_       u64
	binary_byte_offset ?u64
	begin_printed      bool
	stats_             Stats
}

fn (mut sink JSONSink[^p, ^s, W]) drop[^p, ^s]() {
	sink.matcher.drop()
	sink.replacer.free()
}

/// Release resources owned by this sink once its search is complete.
// V-specific: callers may release the owned matcher and replacer buffers
// deterministically instead of waiting for the generated drop path.
pub fn (mut sink JSONSink[^p, ^s, W]) free[^p, ^s]() {
	sink.drop()
}

/// Returns true if and only if this printer received a match in the
/// previous search.
pub fn (sink &JSONSink[^p, ^s, W]) has_match[^p, ^s]() bool {
	return sink.match_count_ > 0
}

/// Return the total number of matches reported to this sink.
///
/// This corresponds to the number of times `Sink::matched` is called.
pub fn (sink &JSONSink[^p, ^s, W]) match_count[^p, ^s]() u64 {
	return sink.match_count_
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
/// return `none`.
pub fn (sink &JSONSink[^p, ^s, W]) binary_byte_offset[^p, ^s]() ?u64 {
	return sink.binary_byte_offset
}

/// Return a reference to the stats produced by the printer for all
/// searches executed on this sink.
pub fn (sink &^a JSONSink[^p, ^s, W]) stats[^a, ^p, ^s]() &^a Stats {
	return &sink.stats_
}

/// Execute the matcher over the given bytes and record the match
/// locations if the current configuration demands match granularity.
fn (mut sink JSONSink[^p, ^s, W]) record_matches[^p, ^s](searcher_ searcher.Searcher, bytes []u8, range matcher.Match) ! {
	// If printing requires knowing the location of each individual match,
	// then compute and stored those right now for use later. While this
	// adds an extra copy for storing the matches, we do amortize the
	// allocation for it and this greatly simplifies the printing logic to
	// the extent that it's easy to ensure that we never do more than
	// one search to find the matches.
	mut matches := sink.json.matches
	matches.clear()
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

/// If the configuration specifies a replacement, then this executes the
/// replacement, lazily allocating memory if necessary.
///
/// To access the result of a replacement, use `replacer.replacement()`.
fn (mut sink JSONSink[^p, ^s, W]) replace[^p, ^s](searcher_ searcher.Searcher, bytes []u8, range matcher.Match) ! {
	sink.replacer.clear()
	if replacement := sink.json.config.replacement {
		sink.replacer.replace_all(searcher_, sink.matcher, bytes, range, replacement)!
	}
}

/// Write the "begin" message.
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
		// V-specific: the translated message representation owns its path, so
		// materialize the borrowed sink path at the serialization boundary.
		return (*path).to_owned()
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

// V-specific: this no-op callback completes the translated `Sink` interface.
pub fn (mut sink JSONSink[^p, ^s, W]) context_break[^p, ^s](searcher_ searcher.Searcher) !bool {
	_ = sink
	_ = searcher_
	return true
}

pub fn (mut sink JSONSink[^p, ^s, W]) binary_data[^p, ^s](searcher_ searcher.Searcher, binary_byte_offset u64) !bool {
	if searcher_.binary_detection().quit_byte() != none {
		if path := sink.path {
			log.debug('ignoring ${*path}: found binary data at offset ${binary_byte_offset}')
		}
	}
	return true
}

pub fn (mut sink JSONSink[^p, ^s, W]) begin[^p, ^s](_searcher searcher.Searcher) !bool {
	sink.json.wtr.reset_count()
	sink.start_time = time.now()
	sink.match_count_ = 0
	sink.binary_byte_offset = none
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

/// SubMatches represents a set of matches in a contiguous range of bytes.
///
/// A simpler representation for this would just simply be `Vec<SubMatch>`,
/// but the common case is exactly one match per range of bytes, which we
/// specialize here using a fixed size array without any allocation.
// V-specific: the translated wire message owns its submatches, so this helper
// materializes the dynamic representation expected by `Message`.
fn json_submatches(bytes []u8, matches []matcher.Match, replacement ?Replacement) []SubMatch {
	mut submatches := []SubMatch{cap: matches.len}
	for i, mat in matches {
		mut repl := ?[]u8(none)
		if r := replacement {
			rmat := r.matches[i]
			repl = json_clone_u8_range(r.bytes, rmat.start(), rmat.end())
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
