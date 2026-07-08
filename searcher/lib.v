module searcher

import encoding.iconv
import encoding.utf8.validate
import io
import matcher
import os

$if !windows {
	#include <sys/mman.h>
	#include <unistd.h>
	fn C.mmap(addr voidptr, len u64, prot i32, flags i32, fd i32, offset i64) voidptr
	fn C.munmap(addr voidptr, len u64) i32
	fn C.pread(fd i32, buf voidptr, count u64, offset i64) isize
}

interface IClone {}

fn is_reader_eof(err IError) bool {
	return err is io.Eof || err is os.Eof
}

/*
This module provides an implementation of line oriented search, with optional
support for multi-line search.

# Brief overview

The principle type in this module is a `Searcher`, which can be configured
and built by a `SearcherBuilder`. A `Searcher` is responsible for reading
bytes from a source (e.g., a file), executing a search of those bytes using
a `Matcher` (e.g., a regex) and then reporting the results of that search to
a `Sink` (e.g., stdout). The `Searcher` itself is principally responsible
for managing the consumption of bytes from a source and applying a `Matcher`
over those bytes in an efficient way. The `Searcher` is also responsible for
inverting a search, counting lines, reporting contextual lines, detecting
binary data and even deciding whether or not to use memory maps.

A `Matcher` is an interface for describing the lowest levels of pattern search
in a generic way. The interface itself is very similar to the interface of a
regular expression.

Finally, a `Sink` describes how callers receive search results producer by a
`Searcher`. This includes routines that are called at the beginning and end of
a search, in addition to routines that are called when matching or contextual
lines are found by the `Searcher`. Implementations of `Sink` can be trivially
simple, or extraordinarily complex, such as the `Standard` printer found in
the `grep-printer` module, which effectively implements grep-like output.
*/

enum BinaryDetectionKind {
	none
	quit
	convert
}

/// Binary detection is the process of heuristically identifying whether a
/// particular portion of data is binary or not.
///
/// Binary detection generally works by indicating that a particular byte in
/// a search should be treated as a binary byte.
///
/// When binary detection is enabled and binary data is found, then the
/// search will either halt (as if it reached EOF) or convert the binary
/// byte to a line terminator.
///
/// Binary detection is performed in one of two ways:
///
/// 1. When performing a search using a fixed size buffer, binary detection is
///    applied to the buffer's contents as it is filled. Binary detection must
///    be applied to the buffer directly because binary files may not contain
///    line terminators, which could result in exorbitant memory usage.
/// 2. When performing a search using memory maps or by reading data off the
///    heap, then binary detection is only guaranteed to be applied to the
///    parts corresponding to a match. When `Quit` is enabled, then the first
///    few KB of the data are searched for binary data.
pub struct BinaryDetection implements IClone {
	kind BinaryDetectionKind
	byte u8
}

/// No binary detection is performed. Data reported by the searcher may
/// contain arbitrary bytes.
///
/// This is the default.
///
/// V-specific: Rust calls this constructor `none`, but `none` is the V
/// optional sentinel.
pub fn BinaryDetection.disabled() BinaryDetection {
	return BinaryDetection{
		kind: .none
	}
}

/// Binary detection is performed by looking for the given byte.
///
/// When searching is performed using a fixed size buffer, then the
/// contents of that buffer are always searched for the presence of this
/// byte. If it is found, then the underlying data is considered binary
/// and the search stops as if it reached EOF.
///
/// When searching is performed with the entire contents mapped into
/// memory, then binary detection is more conservative. Namely, only a
/// fixed sized region at the beginning of the contents are detected for
/// binary data. As a compromise, any subsequent matching (or context)
/// lines are also searched for binary data. If binary data is detected at
/// any point, then the search stops as if it reached EOF.
pub fn BinaryDetection.quit(byte u8) BinaryDetection {
	return BinaryDetection{
		kind: .quit
		byte: byte
	}
}

/// Binary detection is performed by looking for the given byte, and
/// replacing it with the line terminator configured on the searcher.
/// (If the searcher is configured to use `CRLF` as the line terminator,
/// then this byte is replaced by just `LF`.)
///
/// When searching is performed using a fixed size buffer, then the
/// contents of that buffer are always searched for the presence of this
/// byte and replaced with the line terminator. In effect, the caller is
/// guaranteed to never observe this byte while searching.
///
/// When searching is performed with the entire contents mapped into
/// memory, then this setting has no effect and is ignored.
pub fn BinaryDetection.convert(byte u8) BinaryDetection {
	return BinaryDetection{
		kind: .convert
		byte: byte
	}
}

/// If this binary detection uses the "quit" strategy, then this returns
/// the byte that will cause a search to quit. In any other case, this
/// returns `None`.
pub fn (d BinaryDetection) quit_byte() ?u8 {
	if d.kind == .quit {
		return d.byte
	}
	return none
}

/// If this binary detection uses the "convert" strategy, then this returns
/// the byte that will be replaced by the line terminator. In any other
/// case, this returns `None`.
pub fn (d BinaryDetection) convert_byte() ?u8 {
	if d.kind == .convert {
		return d.byte
	}
	return none
}

enum MmapChoiceKind {
	auto
	never
}

/// Controls the strategy used for determining when to use memory maps.
///
/// If a searcher is called in circumstances where it is possible to use memory
/// maps, and memory maps are enabled, then it will attempt to do so if it
/// believes it will make the search faster.
///
/// By default, memory maps are disabled.
pub struct MmapChoice implements IClone {
	kind MmapChoiceKind
}

/// Use memory maps when they are believed to be advantageous.
///
/// The heuristics used to determine whether to use a memory map or not
/// may depend on many things, including but not limited to, file size
/// and platform.
///
/// If memory maps are unavailable or cannot be used for a specific input,
/// then normal OS read calls are used instead.
///
/// # Safety
///
/// This constructor is not safe because there is no obvious way to
/// encapsulate the safety of file backed memory maps on all platforms
/// without simultaneously negating some or all of their benefits.
///
/// The specific contract the caller is required to uphold isn't precise,
/// but it basically amounts to something like, "the caller guarantees that
/// the underlying file won't be mutated." This, of course, isn't feasible
/// in many environments. However, command line tools may still decide to
/// take the risk of, say, a `SIGBUS` occurring while attempting to read a
/// memory map.
pub fn MmapChoice.auto() MmapChoice {
	return MmapChoice{
		kind: .auto
	}
}

/// Never use memory maps, no matter what. This is the default.
pub fn MmapChoice.never() MmapChoice {
	return MmapChoice{
		kind: .never
	}
}

/// Whether this strategy may employ memory maps or not.
fn (choice MmapChoice) is_enabled() bool {
	return choice.kind == .auto
}

struct Mmap {
	data &u8 = unsafe { nil }
	len  usize
}

fn (m Mmap) bytes() []u8 {
	if m.len == 0 || isnil(m.data) {
		return []u8{}
	}
	return unsafe { m.data.vbytes(int(m.len)) }
}

fn (m Mmap) unmap() {
	if m.len == 0 || isnil(m.data) {
		return
	}
	$if !windows {
		unsafe {
			C.munmap(m.data, u64(m.len))
		}
	}
}

/// Return a memory map if memory maps are enabled and if creating a
/// memory from the given file succeeded and if memory maps are believed
/// to be advantageous for performance.
///
/// If this does attempt to open a memory map and it fails, then `None`
/// is returned and the corresponding error (along with the file path, if
/// present) is logged at the debug level.
///
/// V-specific: the translated searcher does not have logging wired in yet,
/// so failed memory map attempts currently fall back silently.
fn (choice MmapChoice) open(mut file os.File, path string, has_path bool) ?Mmap {
	if !choice.is_enabled() {
		return none
	}
	$if macos {
		// I guess memory maps on macOS aren't great. Should re-evaluate.
		return none
	} $else $if windows {
		return none
	} $else {
		size := mmap_file_size(mut file, path, has_path) or { return none }
		if size == 0 {
			return none
		}
		data := &u8(C.mmap(C.NULL, u64(size), C.PROT_READ, C.MAP_PRIVATE, file.fd,
			i64(0)))
		if data == &u8(C.MAP_FAILED) || isnil(data) {
			return none
		}
		return Mmap{
			data: data
			len:  size
		}
	}
}

fn mmap_file_size(mut file os.File, path string, has_path bool) ?usize {
	if has_path {
		return usize(os.file_size(path))
	}
	pos := file.tell() or { return none }
	file.seek(0, .end) or {
		file.seek(pos, .start) or {}
		return none
	}
	end := file.tell() or {
		file.seek(pos, .start) or {}
		return none
	}
	file.seek(pos, .start) or { return none }
	if end <= 0 {
		return usize(0)
	}
	return usize(end)
}

/// An encoding to use when searching.
///
/// An encoding can be used to configure a [`SearcherBuilder`] to transcode
/// source data from an encoding to UTF-8 before searching.
///
/// An `Encoding` will always be cheap to clone.
pub struct Encoding implements IClone {
	label string
	kind  EncodingKind
}

enum EncodingKind {
	utf8
	utf16le
	utf16be
	utf32le
	utf32be
	windows1252
	shiftjis
	eucjp
}

/// Create a new encoding for the specified label.
///
/// The encoding label provided is mapped to an encoding via the set of
/// available choices specified in the
/// [Encoding Standard](https://encoding.spec.whatwg.org/#concept-encoding-get).
/// If the given label does not correspond to a valid encoding, then this
/// returns an error.
pub fn Encoding.new(label string) !Encoding {
	normalized := label.to_lower()
	kind, canonical := encoding_for_label(normalized) or {
		return ConfigError.unknown_encoding(label.bytes())
	}
	return Encoding{
		label: canonical.to_owned()
		kind:  kind
	}
}

fn encoding_for_label(label string) ?(EncodingKind, string) {
	match label {
		'unicode-1-1-utf-8', 'unicode11utf8', 'unicode20utf8', 'utf-8', 'utf8', 'x-unicode20utf8' {
			return EncodingKind.utf8, 'utf-8'
		}
		'utf-16', 'utf-16le', 'utf16le' {
			return EncodingKind.utf16le, 'utf-16le'
		}
		'utf-16be', 'utf16be' {
			return EncodingKind.utf16be, 'utf-16be'
		}
		'utf-32', 'utf-32le', 'utf32le' {
			return EncodingKind.utf32le, 'utf-32le'
		}
		'utf-32be', 'utf32be' {
			return EncodingKind.utf32be, 'utf-32be'
		}
		'ansi_x3.4-1968', 'ascii', 'cp1252', 'cp819', 'csisolatin1', 'ibm819', 'iso-8859-1', 'iso-ir-100', 'iso8859-1', 'iso88591', 'iso_8859-1', 'iso_8859-1:1987', 'l1', 'latin1', 'us-ascii', 'windows-1252', 'x-cp1252' {
			return EncodingKind.windows1252, 'windows-1252'
		}
		'csshiftjis', 'ms932', 'ms_kanji', 'shift-jis', 'shift_jis', 'sjis', 'windows-31j', 'x-sjis' {
			return EncodingKind.shiftjis, 'Shift_JIS'
		}
		'cseucpkdfmtjapanese', 'euc-jp', 'eucjp', 'x-euc-jp' {
			return EncodingKind.eucjp, 'EUC-JP'
		}
		else {
			return none
		}
	}
}

/// The internal configuration of a searcher. This is shared among several
/// search related types, but is only ever written to by the SearcherBuilder.
pub struct Config implements IClone {
	/// The line terminator to use.
	line_term matcher.LineTerminator
	/// Whether to invert matching.
	invert_match bool
	/// The number of lines after a match to include.
	after_context usize
	/// The number of lines before a match to include.
	before_context usize
	/// Whether to enable unbounded context or not.
	passthru bool
	/// Whether to count line numbers.
	line_number bool
	/// The maximum amount of heap memory to use.
	///
	/// When not given, no explicit limit is enforced. When set to `0`, then
	/// only the memory map search strategy is available.
	heap_limit ?usize
	/// The memory map strategy.
	mmap MmapChoice
	/// The binary data detection strategy.
	binary BinaryDetection
	/// Whether to enable matching across multiple lines.
	multi_line bool
	/// An encoding that, when present, causes the searcher to transcode all
	/// input from the encoding to UTF-8.
	encoding ?Encoding
	/// Whether to do automatic transcoding based on a BOM or not.
	bom_sniffing bool
	/// Whether to stop searching when a non-matching line is found after a
	/// matching line.
	stop_on_nonmatch bool
	/// The maximum number of matches this searcher should emit.
	max_matches ?u64
}

pub fn (config Config) clone() Config {
	return Config{
		line_term:        config.line_term
		invert_match:     config.invert_match
		after_context:    config.after_context
		before_context:   config.before_context
		passthru:         config.passthru
		line_number:      config.line_number
		heap_limit:       config.heap_limit
		mmap:             config.mmap
		binary:           config.binary
		multi_line:       config.multi_line
		encoding:         config.encoding
		bom_sniffing:     config.bom_sniffing
		stop_on_nonmatch: config.stop_on_nonmatch
		max_matches:      config.max_matches
	}
}

enum ConfigErrorKind {
	search_unavailable
	mismatched_line_terminators
	unknown_encoding
}

/// An error that can occur when building a searcher.
///
/// This error occurs when a non-sensical configuration is present when trying
/// to construct a `Searcher` from a `SearcherBuilder`.
pub struct ConfigError implements IClone {
	kind ConfigErrorKind
	/// The matcher's line terminator.
	matcher_line_term matcher.LineTerminator
	/// The searcher's line terminator.
	searcher_line_term matcher.LineTerminator
	/// The provided encoding label that could not be found.
	label []u8
}

/// Indicates that the heap limit configuration prevents all possible
/// search strategies from being used. For example, if the heap limit is
/// set to 0 and memory map searching is disabled or unavailable.
pub fn ConfigError.search_unavailable() ConfigError {
	return ConfigError{
		kind: .search_unavailable
	}
}

/// Occurs when a matcher reports a line terminator that is different than
/// the one configured in the searcher.
pub fn ConfigError.mismatched_line_terminators(matcher_line_term matcher.LineTerminator, searcher_line_term matcher.LineTerminator) ConfigError {
	return ConfigError{
		kind:               .mismatched_line_terminators
		matcher_line_term:  matcher_line_term
		searcher_line_term: searcher_line_term
	}
}

/// Occurs when no encoding could be found for a particular label.
pub fn ConfigError.unknown_encoding(label []u8) ConfigError {
	return ConfigError{
		kind:  .unknown_encoding
		label: label.clone()
	}
}

pub fn (err ConfigError) msg() string {
	return match err.kind {
		.search_unavailable {
			'grep config error: no available searchers'
		}
		.mismatched_line_terminators {
			'grep config error: mismatched line terminators, matcher has ${err.matcher_line_term} but searcher has ${err.searcher_line_term}'
		}
		.unknown_encoding {
			'grep config error: unknown encoding: ${err.label.bytestr()}'
		}
	}
}

pub fn (err ConfigError) code() int {
	_ = err
	return 0
}

/// Return the maximal amount of lines needed to fulfill this configuration's
/// context.
///
/// If this returns `0`, then no context is ever needed.
fn (config Config) max_context() usize {
	return if config.before_context > config.after_context {
		config.before_context
	} else {
		config.after_context
	}
}

/// Build a line buffer from this configuration.
fn (config Config) line_buffer() LineBuffer {
	mut builder := LineBufferBuilder.new()
	builder.line_terminator(config.line_term.as_byte())
	builder.binary_detection(config.binary)
	if limit := config.heap_limit {
		if limit <= usize(default_buffer_capacity) {
			builder.capacity(limit)
			builder.buffer_alloc(BufferAllocation{
				kind: .error
			})
		} else {
			builder.capacity(usize(default_buffer_capacity))
			builder.buffer_alloc(BufferAllocation{
				kind:       .error
				additional: limit - usize(default_buffer_capacity)
			})
		}
	}
	return builder.build()
}

/// A builder for configuring a searcher.
///
/// A search builder permits specifying the configuration of a searcher,
/// including options like whether to invert the search or to enable multi
/// line search.
///
/// Once a searcher has been built, it is beneficial to reuse that searcher
/// for multiple searches, if possible.
pub struct SearcherBuilder implements IClone {
mut:
	config Config
}

/// Create a new searcher builder with a default configuration.
pub fn SearcherBuilder.new() SearcherBuilder {
	return SearcherBuilder{
		config: Config{
			line_term:    matcher.LineTerminator.default()
			line_number:  true
			mmap:         MmapChoice{
				kind: .never
			}
			bom_sniffing: true
			heap_limit:   none
			max_matches:  none
		}
	}
}

/// Build a searcher with the given matcher.
pub fn (builder SearcherBuilder) build() Searcher {
	mut config := builder.config.clone()
	if config.passthru {
		config.before_context = 0
		config.after_context = 0
	}
	line_buffer := config.line_buffer()
	return Searcher{
		config:            config
		line_buffer:       line_buffer
		multi_line_buffer: []u8{}
	}
}

/// Set the line terminator that is used by the searcher.
///
/// When using a searcher, if the matcher provided has a line terminator
/// set, then it must be the same as this one. If they aren't, building
/// a searcher will return an error.
///
/// By default, this is set to `b'\n'`.
pub fn (mut builder SearcherBuilder) line_terminator(line_term matcher.LineTerminator) &SearcherBuilder {
	builder.config.line_term = line_term
	return builder
}

/// Whether to invert matching, whereby lines that don't match are reported
/// instead of reporting lines that do match.
///
/// By default, this is disabled.
pub fn (mut builder SearcherBuilder) invert_match(yes bool) &SearcherBuilder {
	builder.config.invert_match = yes
	return builder
}

/// Whether to count and include line numbers with matching lines.
///
/// This is enabled by default. There is a small performance penalty
/// associated with computing line numbers, so this can be disabled when
/// this isn't desirable.
pub fn (mut builder SearcherBuilder) line_number(yes bool) &SearcherBuilder {
	builder.config.line_number = yes
	return builder
}

/// Whether to enable multi line search or not.
///
/// When multi line search is enabled, matches *may* match across multiple
/// lines. Conversely, when multi line search is disabled, it is impossible
/// for any match to span more than one line.
///
/// **Warning:** multi line search requires having the entire contents to
/// search mapped in memory at once. When searching files, memory maps
/// will be used if possible and if they are enabled, which avoids using
/// your program's heap. However, if memory maps cannot be used (e.g.,
/// for searching streams like `stdin` or if transcoding is necessary),
/// then the entire contents of the stream are read on to the heap before
/// starting the search.
///
/// This is disabled by default.
pub fn (mut builder SearcherBuilder) multi_line(yes bool) &SearcherBuilder {
	builder.config.multi_line = yes
	return builder
}

/// Whether to include a fixed number of lines after every match.
///
/// When this is set to a non-zero number, then the searcher will report
/// `line_count` contextual lines after every match.
///
/// This is set to `0` by default.
pub fn (mut builder SearcherBuilder) after_context(line_count usize) &SearcherBuilder {
	builder.config.after_context = line_count
	return builder
}

/// Whether to include a fixed number of lines before every match.
///
/// When this is set to a non-zero number, then the searcher will report
/// `line_count` contextual lines before every match.
///
/// This is set to `0` by default.
pub fn (mut builder SearcherBuilder) before_context(line_count usize) &SearcherBuilder {
	builder.config.before_context = line_count
	return builder
}

/// Whether to enable the "passthru" feature or not.
///
/// When passthru is enabled, it effectively treats all non-matching lines
/// as contextual lines. In other words, enabling this is akin to
/// requesting an unbounded number of before and after contextual lines.
///
/// When passthru mode is enabled, any `before_context` or `after_context`
/// settings are ignored by setting them to `0`.
///
/// This is disabled by default.
pub fn (mut builder SearcherBuilder) passthru(yes bool) &SearcherBuilder {
	builder.config.passthru = yes
	return builder
}

/// Set an approximate limit on the amount of heap space used by a searcher.
///
/// The heap limit is enforced in two scenarios:
///
/// * When searching using a fixed size buffer, the heap limit controls
///   how big this buffer is allowed to be. Assuming contexts are disabled,
///   the minimum size of this buffer is the length (in bytes) of the
///   largest single line in the contents being searched. If any line
///   exceeds the heap limit, then an error will be returned.
/// * When performing a multi line search, a fixed size buffer cannot be
///   used. Thus, the only choices are to read the entire contents on to
///   the heap, or use memory maps. In the former case, the heap limit set
///   here is enforced.
///
/// If a heap limit is set to `0`, then no heap space is used. If there are
/// no alternative strategies available for searching without heap space
/// (e.g., memory maps are disabled), then the searcher wil return an error
/// immediately.
///
/// By default, no limit is set.
pub fn (mut builder SearcherBuilder) heap_limit(bytes ?usize) &SearcherBuilder {
	builder.config.heap_limit = bytes
	return builder
}

/// Set the strategy to employ use of memory maps.
pub fn (mut builder SearcherBuilder) memory_map(strategy MmapChoice) &SearcherBuilder {
	builder.config.mmap = strategy
	return builder
}

/// Set the binary detection strategy.
///
/// The binary detection strategy determines not only how the searcher
/// detects binary data, but how it responds to the presence of binary
/// data. See the [`BinaryDetection`] type for more information.
///
/// By default, binary detection is disabled.
pub fn (mut builder SearcherBuilder) binary_detection(detection BinaryDetection) &SearcherBuilder {
	builder.config.binary = detection
	return builder
}

/// Set the encoding used to read the source data before searching.
pub fn (mut builder SearcherBuilder) encoding(encoding ?Encoding) &SearcherBuilder {
	builder.config.encoding = encoding
	return builder
}

/// Enable automatic transcoding based on BOM sniffing.
///
/// When this is enabled and an explicit encoding is not set, then this
/// searcher will try to detect the encoding of the bytes being searched
/// by sniffing its byte-order mark (BOM). In particular, when this is
/// enabled, UTF-16 encoded files will be searched seamlessly.
///
/// When this is disabled and if an explicit encoding is not set, then
/// the bytes from the source stream will be passed through unchanged,
/// including its BOM, if one is present.
///
/// This is enabled by default.
pub fn (mut builder SearcherBuilder) bom_sniffing(yes bool) &SearcherBuilder {
	builder.config.bom_sniffing = yes
	return builder
}

/// Stop searching a file when a non-matching line is found after a
/// matching line.
///
/// This is useful for searching sorted files where it is expected that all
/// the matches will be on adjacent lines.
pub fn (mut builder SearcherBuilder) stop_on_nonmatch(stop_on_nonmatch bool) &SearcherBuilder {
	builder.config.stop_on_nonmatch = stop_on_nonmatch
	return builder
}

/// Sets the maximum number of matches that should be emitted by this
/// searcher.
///
/// If multi line search is enabled and a match spans multiple lines, then
/// that match is counted exactly once for the purposes of enforcing this
/// limit, regardless of how many lines it spans.
///
/// Note that `0` is a legal value. This will cause the searcher to
/// immediately quick without searching anything.
///
/// By default, no limit is set.
pub fn (mut builder SearcherBuilder) max_matches(limit ?u64) &SearcherBuilder {
	builder.config.max_matches = limit
	return builder
}

/// A searcher executes searches over a haystack and writes results to a caller
/// provided sink.
///
/// Matches are detected via implementations of the `Matcher` trait, which must
/// be provided by the caller when executing a search.
///
/// When possible, a searcher should be reused.
pub struct Searcher implements IClone {
mut:
	/// The configuration for this searcher.
	///
	/// We make most of these settings available to users of `Searcher` via
	/// public API methods, which can be queried in implementations of `Sink`
	/// if necessary.
	config            Config
	// V-specific: Rust stores `decode_builder` and `decode_buffer` fields here.
	// This port performs transcoding through `TranscodingReader` and
	// `decode_slice` helpers instead.
	/// A line buffer for use in line oriented searching.
	line_buffer       LineBuffer
	/// A buffer in which to store the contents of a reader when performing a
	/// multi line search. In particular, multi line searches cannot be
	/// performed incrementally, and need the entire haystack in memory at
	/// once.
	multi_line_buffer []u8
}

pub fn Searcher.new() Searcher {
	config := Config{
		line_term:    matcher.LineTerminator.default()
		line_number:  true
		mmap:         MmapChoice{
			kind: .never
		}
		bom_sniffing: true
		heap_limit:   none
		max_matches:  none
	}
	line_buffer := LineBuffer{
		config: LineBufferConfig{
			capacity:     usize(default_buffer_capacity)
			lineterm:     config.line_term.as_byte()
			buffer_alloc: BufferAllocation{
				kind: .eager
			}
			binary:       config.binary
		}
		buf:    []u8{len: int(default_buffer_capacity)}
	}
	return Searcher{
		config:            config
		line_buffer:       line_buffer
		multi_line_buffer: []u8{}
	}
}

pub fn (s Searcher) multi_line_with_matcher(matcher_ matcher.Matcher) bool {
	if !s.multi_line() {
		return false
	}
	if line_term := matcher_.line_terminator() {
		if line_term.equals(s.line_terminator()) {
			return false
		}
	}
	if non_matching := matcher_.non_matching_bytes() {
		if matcher.byte_set_contains(non_matching, s.line_terminator().as_byte()) {
			return false
		}
	}
	return true
}

/// Execute a search over the file with the given path and write the
/// results to the given sink.
///
/// If memory maps are enabled and the searcher heuristically believes
/// memory maps will help the search run faster, then this will use
/// memory maps. For this reason, callers should prefer using this method
/// or `search_file` over the more generic `search_reader` when possible.
pub fn (mut s Searcher) search_path(matcher_ matcher.Matcher, path string, write_to Sink) ! {
	mut file := os.open(path) or { return err }
	defer {
		file.close()
	}
	s.search_file_maybe_path(matcher_, mut file, path, true, write_to)!
}

/// Execute a search over a file and write the results to the given sink.
///
/// If memory maps are enabled and the searcher heuristically believes
/// memory maps will help the search run faster, then this will use
/// memory maps. For this reason, callers should prefer using this method
/// or `search_path` over the more generic `search_reader` when possible.
pub fn (mut s Searcher) search_file(matcher_ matcher.Matcher, mut file os.File, write_to Sink) ! {
	s.search_file_maybe_path(matcher_, mut file, '', false, write_to)!
}

fn (mut s Searcher) search_file_maybe_path(matcher_ matcher.Matcher, mut file os.File, path string, has_path bool, write_to Sink) ! {
	$if !macos {
		if mmap := s.config.mmap.open(mut file, path, has_path) {
			defer {
				mmap.unmap()
			}
			return s.search_slice(matcher_, mmap.bytes(), write_to)
		}
	}
	s.check_config(matcher_)!
	mut needs_transcoding := false
	if !s.multi_line_with_matcher(matcher_) {
		needs_transcoding = file_needs_transcoding(s.config, mut file, path, has_path)
	}
	if s.multi_line_with_matcher(matcher_) {
		s.fill_multi_line_buffer_from_file(mut file, path, has_path)!
			mut search := MultiLine.new(s, matcher_ref_value(&matcher_), s.multi_line_buffer,
				sink_ref_value(&write_to))
		search.run()!
	} else if needs_transcoding {
		s.fill_transcoded_buffer_from_file(mut file, path, has_path)!
			mut search := SliceByLine.new(s, matcher_ref_value(&matcher_), s.multi_line_buffer,
				sink_ref_value(&write_to))
		search.run()!
	} else {
		mut rdr := LineBufferReader.new(&file, &s.line_buffer)
			mut search := ReadByLine.new(s, matcher_ref_value(&matcher_), rdr, sink_ref_value(&write_to))
		search.run()!
	}
}

/// Execute a search over any implementation of `std::io::Read` and write
/// the results to the given sink.
pub fn (mut s Searcher) search_reader(matcher_ matcher.Matcher, mut read_from io.Reader, write_to Sink) ! {
	s.check_config(matcher_)!

	if s.multi_line_with_matcher(matcher_) {
		s.fill_multi_line_buffer_from_reader(mut read_from)!
			mut search := MultiLine.new(s, matcher_ref_value(&matcher_), s.multi_line_buffer,
				sink_ref_value(&write_to))
		search.run()!
	} else if s.config.encoding != none || s.config.bom_sniffing {
		mut decoded := TranscodingReader.new(&read_from, s.config)
		mut rdr := LineBufferReader.new(&decoded, &s.line_buffer)
			mut search := ReadByLine.new(s, matcher_ref_value(&matcher_), rdr, sink_ref_value(&write_to))
		search.run()!
	} else {
		mut rdr := LineBufferReader.new(&read_from, &s.line_buffer)
			mut search := ReadByLine.new(s, matcher_ref_value(&matcher_), rdr, sink_ref_value(&write_to))
		search.run()!
	}
}

/// Execute a search over the given slice and write the results to the
/// given sink.
pub fn (mut s Searcher) search_slice(matcher_ matcher.Matcher, slice []u8, write_to Sink) ! {
	s.check_config(matcher_)!

	// We can search the slice directly, unless we need to do transcoding.
	if s.slice_needs_transcoding(slice) {
		transcoded := s.transcode_slice(slice)!
		if s.multi_line_with_matcher(matcher_) {
				mut search := MultiLine.new(s, matcher_ref_value(&matcher_), transcoded,
					sink_ref_value(&write_to))
			search.run()!
		} else {
				mut search := SliceByLine.new(s, matcher_ref_value(&matcher_), transcoded,
					sink_ref_value(&write_to))
			search.run()!
		}
		return
	}
	if s.multi_line_with_matcher(matcher_) {
			mut search := MultiLine.new(s, matcher_ref_value(&matcher_), slice, sink_ref_value(&write_to))
		search.run()!
	} else {
			mut search := SliceByLine.new(s, matcher_ref_value(&matcher_), slice,
				sink_ref_value(&write_to))
		search.run()!
	}
}

/// Check that the searcher's configuration and the matcher are consistent
/// with each other.
fn (s Searcher) check_config(matcher_ matcher.Matcher) ! {
	if limit := s.config.heap_limit {
		if limit == 0 && !s.config.mmap.is_enabled() {
			return ConfigError.search_unavailable()
		}
	}
	matcher_line_term := matcher_.line_terminator() or {
		return
	}
	if !matcher_line_term.equals(s.config.line_term) {
		return ConfigError.mismatched_line_terminators(matcher_line_term, s.config.line_term)
	}
}

/// Returns true if and only if the given slice needs to be transcoded.
fn (s Searcher) slice_needs_transcoding(slice []u8) bool {
	return s.config.encoding != none || (s.config.bom_sniffing && slice_has_bom(slice))
}

fn file_needs_transcoding(config Config, mut file os.File, path string, has_path bool) bool {
	if config.encoding != none {
		return true
	}
	if !config.bom_sniffing {
		return false
	}
	if has_path {
		return file_has_bom_at_current(mut file)
	}
	return file_has_bom_at_current(mut file)
}

fn file_has_bom(mut file os.File) bool {
	mut prefix := []u8{len: 3}
	nread := file.read(mut prefix) or { return false }
	return slice_has_bom(prefix[..nread])
}

fn file_has_bom_at_current(mut file os.File) bool {
	pos := file.tell() or { return false }
	$if windows {
		// V-specific: the Windows port still needs a positioned-read helper
		// before bare `search_file` can sniff a BOM without moving the cursor.
		return false
	} $else {
		mut prefix := []u8{len: 3}
		nread := C.pread(file.fd, prefix.data, u64(prefix.len), i64(pos))
		if nread <= 0 {
			return false
		}
		return slice_has_bom(prefix[..int(nread)])
	}
}

fn (s Searcher) transcode_slice(slice []u8) ![]u8 {
	return transcode_slice_with_config(s.config, slice)
}

fn transcode_slice_with_config(config Config, slice []u8) ![]u8 {
	if config.bom_sniffing {
		if slice_has_utf8_bom(slice) {
			return slice[3..].clone()
		}
		if slice_has_utf16le_bom(slice) {
			return decode_utf16(slice[2..], false)
		}
		if slice_has_utf16be_bom(slice) {
			return decode_utf16(slice[2..], true)
		}
	}
	if encoding := config.encoding {
		match encoding.kind {
			.utf8 {
				return slice.clone()
			}
			.utf16le {
				return decode_utf16(slice, false)
			}
			.utf16be {
				return decode_utf16(slice, true)
			}
			.utf32le {
				return decode_utf32(slice, false)
			}
			.utf32be {
				return decode_utf32(slice, true)
			}
			.windows1252 {
				return decode_windows1252(slice)
			}
			.shiftjis {
				return decode_iconv(slice, 'SHIFT_JIS')
			}
			.eucjp {
				return decode_iconv(slice, 'EUC-JP')
			}
		}
	}
	return slice.clone()
}

fn decode_iconv(slice []u8, label string) ![]u8 {
	decoded := iconv.encoding_to_vstring(slice, label)!
	return decoded.bytes()
}

fn (mut s Searcher) fill_transcoded_buffer_from_file(mut file os.File, path string, has_path bool) ! {
	if s.config.heap_limit != none {
		s.fill_transcoded_buffer_from_reader(mut file)!
		return
	}
	capacity := mmap_file_size(mut file, path, has_path) or { usize(0) }
	s.multi_line_buffer = []u8{cap: int(capacity + 1)}
	s.read_all_into_multi_line_buffer(mut file)!
}

fn (mut s Searcher) fill_transcoded_buffer_from_reader(mut read_from io.Reader) ! {
	s.multi_line_buffer = []u8{}
	if limit := s.config.heap_limit {
		if limit == 0 {
			return alloc_error(limit)
		}
	}
	s.read_all_into_multi_line_buffer(mut read_from)!
}

struct TranscodingReader[^r] {
mut:
	rdr         &^r io.Reader
	config      Config
	initialized bool
	pending     []u8
	pending_pos int
	passthrough bool
}

fn TranscodingReader.new[^r](rdr &^r io.Reader, config Config) TranscodingReader[^r] {
	return TranscodingReader[^r]{
		rdr:    rdr
		config: config
	}
}

fn (mut rdr TranscodingReader[^r]) read[^r](mut buf []u8) !int {
	if !rdr.initialized {
		rdr.initialize()!
	}
	if rdr.pending_pos < rdr.pending.len {
		nread := copy(mut buf, rdr.pending[rdr.pending_pos..])
		rdr.pending_pos += nread
		return nread
		}
		if rdr.passthrough {
			return reader_ref_read(mut rdr.rdr, mut buf)!
		}
		return io.Eof{}
	}

fn (mut rdr TranscodingReader[^r]) initialize[^r]() ! {
	rdr.initialized = true
	if rdr.config.encoding != none {
		mut raw := []u8{}
		read_to_end(mut rdr.rdr, mut raw)!
		rdr.pending = transcode_slice_with_config(rdr.config, raw)!
		return
	}
	if !rdr.config.bom_sniffing {
		rdr.passthrough = true
		return
	}
	mut prefix := []u8{len: 3}
	mut nread_total := 0
	for nread_total < prefix.len {
			nread := reader_ref_read(mut rdr.rdr, mut prefix[nread_total..]) or {
				if is_reader_eof(err) {
					break
				}
			return err
		}
		if nread == 0 {
			break
		}
		nread_total += nread
	}
	got := prefix[..nread_total]
	if slice_has_utf16le_bom(got) || slice_has_utf16be_bom(got) {
		mut raw := got.clone()
		read_to_end(mut rdr.rdr, mut raw)!
		rdr.pending = transcode_slice_with_config(rdr.config, raw)!
		return
	}
	if slice_has_utf8_bom(got) {
		rdr.pending = got[3..].clone()
		rdr.passthrough = true
		return
	}
	rdr.pending = got.clone()
	rdr.passthrough = true
}

fn read_to_end(mut read_from &io.Reader, mut dst []u8) ! {
	mut scratch := []u8{len: 8 * (1 << 10)}
	for {
		nread := reader_ref_read(mut read_from, mut scratch) or {
			if is_reader_eof(err) {
				break
			}
			return err
		}
		if nread == 0 {
			break
		}
		dst << scratch[..nread]
	}
}

fn reader_ref_read(mut read_from &io.Reader, mut buf []u8) !int {
	return read_from.read(mut buf)!
}

fn decode_utf16(slice []u8, big_endian bool) []u8 {
	mut out := []u8{cap: slice.len}
	mut i := 0
	for i + 1 < slice.len {
		unit := read_u16(slice[i], slice[i + 1], big_endian)
		i += 2
		if unit >= u16(0xd800) && unit <= u16(0xdbff) {
			if i + 1 < slice.len {
				next := read_u16(slice[i], slice[i + 1], big_endian)
				if next >= u16(0xdc00) && next <= u16(0xdfff) {
					codepoint := u32(0x10000) + ((u32(unit) - u32(0xd800)) << 10) +
						(u32(next) - u32(0xdc00))
					append_utf8(mut out, codepoint)
					i += 2
					continue
				}
			}
			append_utf8(mut out, u32(0xfffd))
		} else if unit >= u16(0xdc00) && unit <= u16(0xdfff) {
			append_utf8(mut out, u32(0xfffd))
		} else {
			append_utf8(mut out, u32(unit))
		}
	}
	if i < slice.len {
		append_utf8(mut out, u32(0xfffd))
	}
	return out
}

fn read_u16(first u8, second u8, big_endian bool) u16 {
	if big_endian {
		return (u16(first) << 8) | u16(second)
	}
	return (u16(second) << 8) | u16(first)
}

fn decode_utf32(slice []u8, big_endian bool) []u8 {
	mut out := []u8{cap: slice.len}
	mut i := 0
	for i + 3 < slice.len {
		codepoint := read_u32(slice[i], slice[i + 1], slice[i + 2], slice[i + 3], big_endian)
		i += 4
		if is_valid_unicode_scalar(codepoint) {
			append_utf8(mut out, codepoint)
		} else {
			append_utf8(mut out, u32(0xfffd))
		}
	}
	if i < slice.len {
		append_utf8(mut out, u32(0xfffd))
	}
	return out
}

fn read_u32(first u8, second u8, third u8, fourth u8, big_endian bool) u32 {
	if big_endian {
		return (u32(first) << 24) | (u32(second) << 16) | (u32(third) << 8) | u32(fourth)
	}
	return (u32(fourth) << 24) | (u32(third) << 16) | (u32(second) << 8) | u32(first)
}

fn is_valid_unicode_scalar(codepoint u32) bool {
	if codepoint > u32(0x10ffff) {
		return false
	}
	return codepoint < u32(0xd800) || codepoint > u32(0xdfff)
}

fn decode_windows1252(slice []u8) []u8 {
	mut out := []u8{cap: slice.len}
	for byte in slice {
		if byte < 0x80 || byte >= 0xa0 {
			append_utf8(mut out, u32(byte))
			continue
		}
		append_utf8(mut out, windows1252_codepoint(byte))
	}
	return out
}

fn windows1252_codepoint(byte u8) u32 {
	return match byte {
		0x80 { u32(0x20ac) }
		0x82 { u32(0x201a) }
		0x83 { u32(0x0192) }
		0x84 { u32(0x201e) }
		0x85 { u32(0x2026) }
		0x86 { u32(0x2020) }
		0x87 { u32(0x2021) }
		0x88 { u32(0x02c6) }
		0x89 { u32(0x2030) }
		0x8a { u32(0x0160) }
		0x8b { u32(0x2039) }
		0x8c { u32(0x0152) }
		0x8e { u32(0x017d) }
		0x91 { u32(0x2018) }
		0x92 { u32(0x2019) }
		0x93 { u32(0x201c) }
		0x94 { u32(0x201d) }
		0x95 { u32(0x2022) }
		0x96 { u32(0x2013) }
		0x97 { u32(0x2014) }
		0x98 { u32(0x02dc) }
		0x99 { u32(0x2122) }
		0x9a { u32(0x0161) }
		0x9b { u32(0x203a) }
		0x9c { u32(0x0153) }
		0x9e { u32(0x017e) }
		0x9f { u32(0x0178) }
		else { u32(0xfffd) }
	}
}

fn append_utf8(mut bytes []u8, codepoint u32) {
	if codepoint < 0x80 {
		bytes << u8(codepoint)
	} else if codepoint < 0x800 {
		bytes << u8(0xc0 | (codepoint >> 6))
		bytes << u8(0x80 | (codepoint & 0x3f))
	} else if codepoint < 0x10000 {
		bytes << u8(0xe0 | (codepoint >> 12))
		bytes << u8(0x80 | ((codepoint >> 6) & 0x3f))
		bytes << u8(0x80 | (codepoint & 0x3f))
	} else {
		bytes << u8(0xf0 | (codepoint >> 18))
		bytes << u8(0x80 | ((codepoint >> 12) & 0x3f))
		bytes << u8(0x80 | ((codepoint >> 6) & 0x3f))
		bytes << u8(0x80 | (codepoint & 0x3f))
	}
}

/// Fill the buffer for use with multi-line searching from the given file.
/// This reads from the file until EOF or until an error occurs. If the
/// contents exceed the configured heap limit, then an error is returned.
fn (mut s Searcher) fill_multi_line_buffer_from_file(mut file os.File, path string, has_path bool) ! {
	assert s.config.multi_line

	if s.config.heap_limit != none {
		s.fill_multi_line_buffer_from_reader(mut file)!
		return
	}
	capacity := mmap_file_size(mut file, path, has_path) or { usize(0) }
	s.multi_line_buffer = []u8{cap: int(capacity + 1)}
	s.read_all_into_multi_line_buffer(mut file)!
}

/// Fill the buffer for use with multi-line searching from the given
/// reader. This reads from the reader until EOF or until an error occurs.
/// If the contents exceed the configured heap limit, then an error is
/// returned.
fn (mut s Searcher) fill_multi_line_buffer_from_reader(mut read_from io.Reader) ! {
	assert s.config.multi_line

	s.multi_line_buffer = []u8{}
	if limit := s.config.heap_limit {
		if limit == 0 {
			return alloc_error(limit)
		}
	}
	s.read_all_into_multi_line_buffer(mut read_from)!
}

fn (mut s Searcher) read_all_into_multi_line_buffer(mut read_from io.Reader) ! {
	mut scratch := []u8{len: 8 * (1 << 10)}
	for {
		nread := read_from.read(mut scratch) or {
			if is_reader_eof(err) {
				break
			}
			return err
		}
		if nread == 0 {
			break
		}
		if limit := s.config.heap_limit {
			if usize(s.multi_line_buffer.len + nread) >= limit {
				return alloc_error(limit)
			}
		}
		s.multi_line_buffer << scratch[..nread]
	}
	if s.slice_needs_transcoding(s.multi_line_buffer) {
		transcoded := s.transcode_slice(s.multi_line_buffer)!
		s.multi_line_buffer = transcoded
	}
}

pub fn (s Searcher) line_terminator() matcher.LineTerminator {
	return s.config.line_term
}

pub fn (s Searcher) binary_detection() BinaryDetection {
	return s.config.binary
}

pub fn (s Searcher) invert_match() bool {
	return s.config.invert_match
}

pub fn (s Searcher) line_number() bool {
	return s.config.line_number
}

pub fn (s Searcher) multi_line() bool {
	return s.config.multi_line
}

pub fn (s Searcher) stop_on_nonmatch() bool {
	return s.config.stop_on_nonmatch
}

pub fn (s Searcher) max_matches() ?u64 {
	return s.config.max_matches
}

pub fn (s Searcher) after_context() usize {
	return s.config.after_context
}

pub fn (s Searcher) before_context() usize {
	return s.config.before_context
}

pub fn (s Searcher) passthru() bool {
	return s.config.passthru
}

pub fn (mut s Searcher) set_multi_line(yes bool) {
	s.config.multi_line = yes
}

pub fn (mut s Searcher) set_line_terminator(line_terminator matcher.LineTerminator) {
	s.config.line_term = line_terminator
	s.line_buffer.config.lineterm = line_terminator.as_byte()
}

pub fn (mut s Searcher) set_binary_detection(binary_detection BinaryDetection) {
	s.config.binary = binary_detection
	s.line_buffer.set_binary_detection(binary_detection)
}

pub fn (mut s Searcher) set_invert_match(yes bool) {
	s.config.invert_match = yes
}

/// Summary data reported at the end of a search.
///
/// This reports data such as the total number of bytes searched and the
/// absolute offset of the first occurrence of binary data, if any were found.
///
/// A searcher that stops early because of an error does not call `finish`.
/// A searcher that stops early because the `Sink` implementor instructed it
/// to will still call `finish`.
pub struct SinkFinish implements IClone {
	byte_count_         u64
	binary_byte_offset_ ?u64
}

pub fn SinkFinish.new(byte_count u64) SinkFinish {
	return SinkFinish{
		byte_count_: byte_count
	}
}

/// Return the total number of bytes searched.
pub fn (finish SinkFinish) byte_count() u64 {
	return finish.byte_count_
}

/// If binary detection is enabled and if binary data was found, then this
/// returns the absolute byte offset of the first detected byte of binary
/// data.
///
/// Note that since this is an absolute byte offset, it cannot be relied
/// upon to index into any addressable memory.
pub fn (finish SinkFinish) binary_byte_offset() ?u64 {
	return finish.binary_byte_offset_
}

pub fn (finish SinkFinish) with_binary_byte_offset(binary_byte_offset ?u64) SinkFinish {
	return SinkFinish{
		byte_count_:         finish.byte_count_
		binary_byte_offset_: binary_byte_offset
	}
}

/// An iterator over lines in a particular slice of bytes.
///
/// Line terminators are considered part of the line they terminate. All lines
/// yielded by the iterator are guaranteed to be non-empty.
///
/// `'b` refers to the lifetime of the underlying bytes.
pub struct LineIter implements IClone {
	// V-specific: Rust stores this as a borrowed `&'b [u8]`; this port stores
	// an owned slice because `LineIter` values are passed around directly.
	bytes_   []u8
	stepper_ LineStep
}

/// Create a new line iterator that yields lines in the given bytes that
/// are terminated by `line_term`.
pub fn LineIter.new(line_term u8, bytes []u8) LineIter {
	return LineIter{
		bytes_:   bytes.clone()
		stepper_: LineStep.new(line_term, 0, bytes.len)
	}
}

pub fn (iter LineIter) count() u64 {
	mut stepper := iter.stepper_
	mut count := u64(0)
	for {
		m := stepper.next_match(iter.bytes_) or { break }
		_ = m
		count++
	}
	return count
}

pub fn (mut iter LineIter) next() ?[]u8 {
	m := iter.stepper_.next_match(iter.bytes_) or { return none }
	return iter.bytes_[m.start()..m.end()].clone()
}

/// A type that describes a match reported by a searcher.
pub struct SinkMatch implements IClone {
	line_term_             u8 = `\n`
	// V-specific: Rust stores `bytes` and `buffer` as borrowed `&'b [u8]`.
	// This port keeps slice views into the active search buffer and clones
	// only from public accessors that need owned bytes.
	bytes_                 []u8
	absolute_byte_offset_  u64
	line_number_           ?u64
	buffer_                []u8
	bytes_range_in_buffer_ matcher.Match
}

pub fn SinkMatch.new(buffer []u8, bytes_range_in_buffer matcher.Match) SinkMatch {
	return SinkMatch{
		bytes_:                 buffer[bytes_range_in_buffer.start()..bytes_range_in_buffer.end()]
		buffer_:                buffer
		bytes_range_in_buffer_: bytes_range_in_buffer
	}
}

pub fn (mat SinkMatch) with_absolute_byte_offset(absolute_byte_offset u64) SinkMatch {
	return SinkMatch{
		line_term_:             mat.line_term_
		bytes_:                 mat.bytes_
		absolute_byte_offset_:  absolute_byte_offset
		line_number_:           mat.line_number_
		buffer_:                mat.buffer_
		bytes_range_in_buffer_: mat.bytes_range_in_buffer_
	}
}

pub fn (mat SinkMatch) with_line_number(line_number ?u64) SinkMatch {
	return SinkMatch{
		line_term_:             mat.line_term_
		bytes_:                 mat.bytes_
		absolute_byte_offset_:  mat.absolute_byte_offset_
		line_number_:           line_number
		buffer_:                mat.buffer_
		bytes_range_in_buffer_: mat.bytes_range_in_buffer_
	}
}

pub fn (mat SinkMatch) with_line_term(line_term u8) SinkMatch {
	return SinkMatch{
		line_term_:             line_term
		bytes_:                 mat.bytes_
		absolute_byte_offset_:  mat.absolute_byte_offset_
		line_number_:           mat.line_number_
		buffer_:                mat.buffer_
		bytes_range_in_buffer_: mat.bytes_range_in_buffer_
	}
}

/// Exposes as much of the underlying buffer that was search as possible.
pub fn (mat SinkMatch) buffer() []u8 {
	return mat.buffer_.clone()
}

/// Returns a range that corresponds to where [`SinkMatch::bytes`] appears
/// in [`SinkMatch::buffer`].
pub fn (mat SinkMatch) bytes_range_in_buffer() matcher.Match {
	return mat.bytes_range_in_buffer_
}

/// Returns the bytes for all matching lines, including the line
/// terminators, if they exist.
pub fn (mat SinkMatch) bytes() []u8 {
	return mat.bytes_.clone()
}

// V-specific: exposes the active search-buffer slice for printer internals
// that consume it before the search buffer is reused.
pub fn (mat SinkMatch) bytes_view() []u8 {
	return mat.bytes_
}

/// Returns the absolute byte offset of the start of this match. This
/// offset is absolute in that it is relative to the very beginning of the
/// input in a search, and can never be relied upon to be a valid index
/// into an in-memory slice.
pub fn (mat SinkMatch) absolute_byte_offset() u64 {
	return mat.absolute_byte_offset_
}

/// Returns the line number of the first line in this match, if available.
///
/// Line numbers are only available when the search builder is instructed
/// to compute them.
pub fn (mat SinkMatch) line_number() ?u64 {
	return mat.line_number_
}

/// Return an iterator over the lines in this match.
///
/// If multi line search is enabled, then this may yield more than one
/// line (but always at least one line). If multi line search is disabled,
/// then this always reports exactly one line (but may consist of just
/// the line terminator).
///
/// Lines yielded by this iterator include their terminators.
pub fn (mat SinkMatch) lines() LineIter {
	return LineIter.new(mat.line_term_, mat.bytes())
}

/// An explicit iterator over lines in a particular slice of bytes.
///
/// This iterator avoids borrowing the bytes themselves, and instead requires
/// callers to explicitly provide the bytes when moving through the iterator.
/// While not idiomatic, this provides a simple way of iterating over lines
/// that doesn't require borrowing the slice itself, which can be convenient.
///
/// Line terminators are considered part of the line they terminate. All lines
/// yielded by the iterator are guaranteed to be non-empty.
pub struct LineStep implements IClone {
	line_term u8
mut:
	pos usize
	end usize
}

/// Create a new line iterator over the given range of bytes using the
/// given line terminator.
///
/// Callers should provide the actual bytes for each call to `next`. The
/// same slice must be provided to each call.
///
/// This panics if `start` is not less than or equal to `end`.
pub fn LineStep.new(line_term u8, start usize, end usize) LineStep {
	if start > end {
		panic('${start} is not <= ${end}')
	}
	return LineStep{
		line_term: line_term
		pos:       start
		end:       end
	}
}

/// Return the start and end position of the next line in the given bytes.
///
/// The caller must past exactly the same slice of bytes for each call to
/// `next`.
///
/// The range returned includes the line terminator. Ranges are always
/// non-empty.
pub fn (mut step LineStep) next(bytes []u8) ?(usize, usize) {
	if step.end > bytes.len {
		panic('line step end exceeds byte slice length')
	}
	mut i := step.pos
	for i < step.end {
		if bytes[i] == step.line_term {
			start := step.pos
			end := i + 1
			step.pos = end
			return start, end
		}
		i++
	}
	if step.pos < step.end {
		start := step.pos
		end := step.end
		step.pos = end
		return start, end
	}
	return none
}

pub fn (mut step LineStep) next_match(bytes []u8) ?matcher.Match {
	start, end := step.next(bytes) or { return none }
	return matcher.Match.new(start, end)
}

/// Count the number of occurrences of `line_term` in `bytes`.
pub fn count_lines(bytes []u8, line_term u8) u64 {
	mut count := u64(0)
	for byte in bytes {
		if byte == line_term {
			count++
		}
	}
	return count
}

/// Given a line that possibly ends with a terminator, return that line without
/// the terminator.
pub fn without_terminator(bytes []u8, line_term matcher.LineTerminator) []u8 {
	term := line_term.as_bytes()
	if bytes.len < term.len {
		return bytes.clone()
	}
	start := bytes.len - term.len
	if bytes[start..] == term {
		return bytes[..start].clone()
	}
	return bytes.clone()
}

/// Return the start and end offsets of the lines containing the given range
/// of bytes.
///
/// Line terminators are considered part of the line they terminate.
pub fn locate(bytes []u8, line_term u8, range matcher.Match) matcher.Match {
	mut line_start := usize(0)
	mut i := range.start()
	for i > 0 {
		i--
		if bytes[i] == line_term {
			line_start = i + 1
			break
		}
	}
	mut line_end := bytes.len
	if range.end() > line_start && range.end() > 0 && bytes[range.end() - 1] == line_term {
		line_end = range.end()
	} else {
		mut j := range.end()
		for j < bytes.len {
			if bytes[j] == line_term {
				line_end = j + 1
				break
			}
			j++
		}
	}
	return matcher.Match.new(line_start, line_end)
}

/// Returns the minimal starting offset of the line that occurs `count` lines
/// before the last line in `bytes`.
///
/// Lines are terminated by `line_term`. If `count` is zero, then this returns
/// the starting offset of the last line in `bytes`.
///
/// If `bytes` ends with a line terminator, then the terminator itself is
/// considered part of the last line.
pub fn preceding(bytes []u8, line_term u8, count usize) usize {
	return preceding_by_position(bytes, bytes.len, line_term, count)
}

/// Returns the minimal starting offset of the line that occurs `count` lines
/// before the line containing `pos`. Lines are terminated by `line_term`.
/// If `count` is zero, then this returns the starting offset of the line
/// containing `pos`.
///
/// If `pos` points just past a line terminator, then it is considered part of
/// the line that it terminates. For example, given `bytes = b"abc\nxyz\n"`
/// and `pos = 7`, `preceding(bytes, pos, b'\n', 0)` returns `4` (as does `pos
/// = 8`) and `preceding(bytes, pos, `b'\n', 1)` returns `0`.
fn preceding_by_position(bytes []u8, pos usize, line_term u8, count usize) usize {
	mut cur_pos := pos
	mut remaining := count
	if cur_pos == 0 {
		return 0
	} else if bytes[cur_pos - 1] == line_term {
		cur_pos--
	}
	for {
		mut found_idx := usize(0)
		mut has_found := false
		mut i := cur_pos
		for i > 0 {
			i--
			if bytes[i] == line_term {
				found_idx = i
				has_found = true
				break
			}
		}
		if !has_found {
			return 0
		}
		if remaining == 0 {
			return found_idx + 1
		} else if found_idx == 0 {
			return 0
		}
		remaining--
		cur_pos = found_idx
	}
	return 0
}

pub enum SinkContextKind {
	// The line reported occurred before a match.
	before
	// The line reported occurred after a match.
	after
	// Any other type of context reported, e.g., as a result of a searcher's
	// "passthru" mode.
	other
}

/// A type that describes a contextual line reported by a searcher.
pub struct SinkContext implements IClone {
	// V-specific: Rust only stores this under `#[cfg(test)]` for
	// `SinkContext::lines`, but translated V tests compile as normal module
	// files and still need it.
	line_term_             u8 = `\n`
	// V-specific: Rust stores this as a borrowed `&'b [u8]`; the current V
	// sink interface passes context values, so this stores an owned slice.
	bytes_                 []u8
	kind_                  SinkContextKind
	absolute_byte_offset_  u64
	line_number_           ?u64
}

/// Returns the context bytes, including line terminators.
pub fn (ctx SinkContext) bytes() []u8 {
	return ctx.bytes_.clone()
}

/// Returns the type of context.
pub fn (ctx SinkContext) kind() SinkContextKind {
	return ctx.kind_
}

/// Return an iterator over the lines in this match.
///
/// This always yields exactly one line (and that one line may contain just
/// the line terminator).
///
/// Lines yielded by this iterator include their terminators.
fn (ctx SinkContext) lines() LineIter {
	return LineIter.new(ctx.line_term_, ctx.bytes())
}

/// Returns the absolute byte offset of the start of this context. This
/// offset is absolute in that it is relative to the very beginning of the
/// input in a search, and can never be relied upon to be a valid index
/// into an in-memory slice.
pub fn (ctx SinkContext) absolute_byte_offset() u64 {
	return ctx.absolute_byte_offset_
}

/// Returns the line number of the first line in this context, if available.
///
/// Line numbers are only available when the search builder is instructed to
/// compute them.
pub fn (ctx SinkContext) line_number() ?u64 {
	return ctx.line_number_
}

pub interface Sink {
mut:
	matched(searcher Searcher, mat SinkMatch) !bool
	context(searcher Searcher, ctx SinkContext) !bool
	context_break(searcher Searcher) !bool
	binary_data(searcher Searcher, binary_byte_offset u64) !bool
	begin(searcher Searcher) !bool
	finish(searcher Searcher, finish SinkFinish) !
}

pub type BytesSinkCallback = fn (u64, []u8) !bool

pub type StringSinkCallback = fn (u64, string) !bool

/// A sink that provides line numbers and matches as strings while ignoring
/// everything else.
///
/// This implementation will return an error if a match contains invalid
/// UTF-8 or if the searcher was not configured to count lines. Errors
/// on invalid UTF-8 can be suppressed by using the `Lossy` sink instead
/// of this one.
///
/// The closure accepts two parameters: a line number and a UTF-8 string
/// containing the matched data. The closure returns a
/// `Result<bool, std::io::Error>`. If the `bool` is `false`, then the
/// search stops immediately. Otherwise, searching continues.
///
/// If multi line mode was enabled, the line number refers to the line
/// number of the first line in the match.
pub struct UTF8 implements IClone {
	callback StringSinkCallback
}

pub fn UTF8.new(callback StringSinkCallback) UTF8 {
	return UTF8{
		callback: callback
	}
}

pub fn (sink UTF8) clone() UTF8 {
	return UTF8{
		callback: sink.callback
	}
}

pub fn (mut sink UTF8) matched(searcher Searcher, mat SinkMatch) !bool {
	_ = searcher
	matched := mat.bytes()
	if !is_valid_utf8_bytes(matched) {
		return error('invalid UTF-8 in search match')
	}
	line_number := mat.line_number() or { return error('line numbers not enabled') }
	return sink.callback(line_number, matched.bytestr())!
}

pub fn (mut sink UTF8) context(searcher Searcher, ctx SinkContext) !bool {
	_ = sink
	_ = searcher
	_ = ctx
	return true
}

pub fn (mut sink UTF8) context_break(searcher Searcher) !bool {
	_ = sink
	_ = searcher
	return true
}

pub fn (mut sink UTF8) binary_data(searcher Searcher, binary_byte_offset u64) !bool {
	_ = sink
	_ = searcher
	_ = binary_byte_offset
	return true
}

pub fn (mut sink UTF8) begin(searcher Searcher) !bool {
	_ = sink
	_ = searcher
	return true
}

pub fn (mut sink UTF8) finish(searcher Searcher, finish SinkFinish) ! {
	_ = sink
	_ = searcher
	_ = finish
}

/// A sink that provides line numbers and matches as (lossily converted)
/// strings while ignoring everything else.
///
/// This is like `UTF8`, except that if a match contains invalid UTF-8,
/// then it will be lossily converted to valid UTF-8 by substituting
/// invalid UTF-8 with Unicode replacement characters.
///
/// This implementation will return an error on the first match if the
/// searcher was not configured to count lines.
///
/// The closure accepts two parameters: a line number and a UTF-8 string
/// containing the matched data. The closure returns a
/// `Result<bool, std::io::Error>`. If the `bool` is `false`, then the
/// search stops immediately. Otherwise, searching continues.
///
/// If multi line mode was enabled, the line number refers to the line
/// number of the first line in the match.
pub struct Lossy implements IClone {
	callback StringSinkCallback
}

pub fn Lossy.new(callback StringSinkCallback) Lossy {
	return Lossy{
		callback: callback
	}
}

pub fn (sink Lossy) clone() Lossy {
	return Lossy{
		callback: sink.callback
	}
}

pub fn (mut sink Lossy) matched(searcher Searcher, mat SinkMatch) !bool {
	_ = searcher
	line_number := mat.line_number() or { return error('line numbers not enabled') }
	return sink.callback(line_number, lossy_utf8_string(mat.bytes()))!
}

pub fn (mut sink Lossy) context(searcher Searcher, ctx SinkContext) !bool {
	_ = sink
	_ = searcher
	_ = ctx
	return true
}

pub fn (mut sink Lossy) context_break(searcher Searcher) !bool {
	_ = sink
	_ = searcher
	return true
}

pub fn (mut sink Lossy) binary_data(searcher Searcher, binary_byte_offset u64) !bool {
	_ = sink
	_ = searcher
	_ = binary_byte_offset
	return true
}

pub fn (mut sink Lossy) begin(searcher Searcher) !bool {
	_ = sink
	_ = searcher
	return true
}

pub fn (mut sink Lossy) finish(searcher Searcher, finish SinkFinish) ! {
	_ = sink
	_ = searcher
	_ = finish
}

/// A sink that provides line numbers and matches as raw bytes while
/// ignoring everything else.
///
/// This implementation will return an error on the first match if the
/// searcher was not configured to count lines.
///
/// The closure accepts two parameters: a line number and a raw byte string
/// containing the matched data. The closure returns a
/// `Result<bool, std::io::Error>`. If the `bool` is `false`, then the
/// search stops immediately. Otherwise, searching continues.
///
/// If multi line mode was enabled, the line number refers to the line
/// number of the first line in the match.
pub struct Bytes implements IClone {
	callback BytesSinkCallback
}

pub fn Bytes.new(callback BytesSinkCallback) Bytes {
	return Bytes{
		callback: callback
	}
}

pub fn (sink Bytes) clone() Bytes {
	return Bytes{
		callback: sink.callback
	}
}

pub fn (mut sink Bytes) matched(searcher Searcher, mat SinkMatch) !bool {
	_ = searcher
	line_number := mat.line_number() or { return error('line numbers not enabled') }
	return sink.callback(line_number, mat.bytes())!
}

pub fn (mut sink Bytes) context(searcher Searcher, ctx SinkContext) !bool {
	_ = sink
	_ = searcher
	_ = ctx
	return true
}

pub fn (mut sink Bytes) context_break(searcher Searcher) !bool {
	_ = sink
	_ = searcher
	return true
}

pub fn (mut sink Bytes) binary_data(searcher Searcher, binary_byte_offset u64) !bool {
	_ = sink
	_ = searcher
	_ = binary_byte_offset
	return true
}

pub fn (mut sink Bytes) begin(searcher Searcher) !bool {
	_ = sink
	_ = searcher
	return true
}

pub fn (mut sink Bytes) finish(searcher Searcher, finish SinkFinish) ! {
	_ = sink
	_ = searcher
	_ = finish
}

fn is_valid_utf8_bytes(bytes []u8) bool {
	if bytes.len == 0 {
		return true
	}
	return validate.utf8_data(&bytes[0], bytes.len)
}

fn lossy_utf8_string(bytes []u8) string {
	if is_valid_utf8_bytes(bytes) {
		return bytes.bytestr()
	}
	mut out := []u8{cap: bytes.len}
	mut i := 0
	for i < bytes.len {
		n := valid_utf8_sequence_len(bytes, i)
		if n > 0 {
			append_bytes(mut out, bytes[i..i + n])
			i += n
			continue
		}
		append_utf8(mut out, u32(0xfffd))
		i++
	}
	return out.bytestr()
}

fn valid_utf8_sequence_len(bytes []u8, i int) int {
	first := bytes[i]
	if first < 0x80 {
		return 1
	}
	if first >= 0xc2 && first <= 0xdf {
		if i + 1 < bytes.len && is_utf8_continuation(bytes[i + 1]) {
			return 2
		}
		return 0
	}
	if first == 0xe0 {
		if i + 2 < bytes.len && bytes[i + 1] >= 0xa0 && bytes[i + 1] <= 0xbf
			&& is_utf8_continuation(bytes[i + 2]) {
			return 3
		}
		return 0
	}
	if first >= 0xe1 && first <= 0xec {
		if i + 2 < bytes.len && is_utf8_continuation(bytes[i + 1])
			&& is_utf8_continuation(bytes[i + 2]) {
			return 3
		}
		return 0
	}
	if first == 0xed {
		if i + 2 < bytes.len && bytes[i + 1] >= 0x80 && bytes[i + 1] <= 0x9f
			&& is_utf8_continuation(bytes[i + 2]) {
			return 3
		}
		return 0
	}
	if first >= 0xee && first <= 0xef {
		if i + 2 < bytes.len && is_utf8_continuation(bytes[i + 1])
			&& is_utf8_continuation(bytes[i + 2]) {
			return 3
		}
		return 0
	}
	if first == 0xf0 {
		if i + 3 < bytes.len && bytes[i + 1] >= 0x90 && bytes[i + 1] <= 0xbf
			&& is_utf8_continuation(bytes[i + 2]) && is_utf8_continuation(bytes[i + 3]) {
			return 4
		}
		return 0
	}
	if first >= 0xf1 && first <= 0xf3 {
		if i + 3 < bytes.len && is_utf8_continuation(bytes[i + 1])
			&& is_utf8_continuation(bytes[i + 2]) && is_utf8_continuation(bytes[i + 3]) {
			return 4
		}
		return 0
	}
	if first == 0xf4 {
		if i + 3 < bytes.len && bytes[i + 1] >= 0x80 && bytes[i + 1] <= 0x8f
			&& is_utf8_continuation(bytes[i + 2]) && is_utf8_continuation(bytes[i + 3]) {
			return 4
		}
	}
	return 0
}

fn is_utf8_continuation(byte u8) bool {
	return byte >= 0x80 && byte <= 0xbf
}

fn append_bytes(mut dst []u8, bytes []u8) {
	for byte in bytes {
		dst << byte
	}
}

fn matcher_ref_value(matcher_ &matcher.Matcher) matcher.Matcher {
	return *matcher_
}

fn sink_ref_value(sink &Sink) Sink {
	return *sink
}

enum FastMatchResult {
	continue_search
	stop
	switch_to_slow
}

struct Core[^s] {
	config   &^s Config
	matcher_ matcher.Matcher
	searcher &^s Searcher
mut:
	sink                Sink
	binary              bool
	pos                 usize
	absolute_byte_offset u64
	binary_byte_offset_ ?usize
	line_number         ?u64
	last_line_counted   usize
	last_line_visited   usize
	after_context_left  usize
	has_sunk            bool
	has_matched         bool
	count_              u64
}

fn Core.new[^s](searcher &^s Searcher, matcher_ matcher.Matcher, sink Sink, binary bool) Core[^s] {
	mut line_number := ?u64(none)
	if searcher.config.line_number {
		line_number = u64(1)
	}
	return Core[^s]{
		config:      &searcher.config
		matcher_:    matcher_
		searcher:    searcher
		sink:        sink
		binary:      binary
		line_number: line_number
	}
}

fn (core Core[^s]) pos[^s]() usize {
	return core.pos
}

fn (mut core Core[^s]) set_pos[^s](pos usize) {
	core.pos = pos
}

fn (core Core[^s]) count[^s]() u64 {
	return core.count_
}

fn (mut core Core[^s]) increment_count[^s]() {
	core.count_++
}

fn (core Core[^s]) binary_byte_offset[^s]() ?u64 {
	if offset := core.binary_byte_offset_ {
		return u64(offset)
	}
	return none
}

fn (mut core Core[^s]) matched[^s](buf []u8, range matcher.Match) !bool {
	return core.sink_matched(buf, range)!
}

fn (mut core Core[^s]) binary_data[^s](binary_byte_offset u64) !bool {
	return core.sink.binary_data(*core.searcher, binary_byte_offset)!
}

fn (mut core Core[^s]) is_match[^s](line []u8) !bool {
	// We need to strip the line terminator here to match the
	// semantics of line-by-line searching. Namely, regexes
	// like `(?m)^$` can match at the final position beyond a
	// line terminator, which is non-sensical in line oriented
	// matching.
	line_without_term := without_terminator(line, core.config.line_term)
	return core.matcher_.find_at(line_without_term, 0)!.is_some()
}

fn (mut core Core[^s]) find[^s](slice []u8) !matcher.FallibleMatch {
	if core.has_exceeded_match_limit() {
		return matcher.FallibleMatch.absent()
	}
	maybe_match := core.matcher_.find_at(slice, 0)!
	if mat := maybe_match.get() {
		core.increment_count()
		return matcher.FallibleMatch.some(mat)
	}
	return matcher.FallibleMatch.absent()
}

fn (mut core Core[^s]) shortest_match[^s](slice []u8) !matcher.FallibleUsize {
	if core.has_exceeded_match_limit() {
		return matcher.FallibleUsize.absent()
	}
	maybe_match := core.matcher_.find_at(slice, 0)!
	if mat := maybe_match.get() {
		return matcher.FallibleUsize.some(mat.end())
	}
	return matcher.FallibleUsize.absent()
}

fn (mut core Core[^s]) begin[^s]() !bool {
	return core.sink.begin(*core.searcher)!
}

fn (mut core Core[^s]) finish[^s](byte_count u64, binary_byte_offset ?u64) ! {
	core.sink.finish(*core.searcher, SinkFinish{
		byte_count_:         byte_count
		binary_byte_offset_: binary_byte_offset
	})!
}

fn (mut core Core[^s]) match_by_line[^s](buf []u8) !bool {
	if core.is_line_by_line_fast() {
		result := core.match_by_line_fast(buf)!
		return match result {
			.switch_to_slow { core.match_by_line_slow(buf)! }
			.continue_search { true }
			.stop { false }
		}
	}
	return core.match_by_line_slow(buf)!
}

fn (mut core Core[^s]) roll[^s](buf []u8) usize {
	consumed := if core.config.max_context() == 0 {
		buf.len
	} else {
		// It might seem like all we need to care about here is just
		// the "before context," but in order to sink the context
		// separator (when before_context==0 and after_context>0), we
		// need to know something about the position of the previous
		// line visited, even if we're at the beginning of the buffer.
		//
		// ... however, we only need to find the N preceding lines based
		// on before context. We can skip this (potentially costly, for
		// large values of N) step when before_context==0.
		context_start := preceding(buf, core.config.line_term.as_byte(), core.config.before_context)
		if context_start > core.last_line_visited {
			context_start
		} else {
			core.last_line_visited
		}
	}
	core.count_lines(buf, consumed)
	core.absolute_byte_offset += u64(consumed)
	core.last_line_counted = 0
	core.last_line_visited = 0
	core.set_pos(buf.len - consumed)
	return consumed
}

fn (mut core Core[^s]) detect_binary[^s](buf []u8, range matcher.Match) !bool {
	if _ := core.binary_byte_offset_ {
		if _ := core.config.binary.quit_byte() {
			return true
		}
		return false
	}
	mut binary_byte := u8(0)
	if core.config.binary.kind == .quit || core.config.binary.kind == .convert {
		binary_byte = core.config.binary.byte
	} else {
		return false
	}
	if i := find_byte(buf[range.start()..range.end()], binary_byte) {
		offset := range.start() + i
		core.binary_byte_offset_ = offset
		if !core.binary_data(u64(offset))! {
			return true
		}
		if _ := core.config.binary.quit_byte() {
			return true
		}
	}
	return false
}

fn (mut core Core[^s]) before_context_by_line[^s](buf []u8, upto usize) !bool {
	if core.config.before_context == 0 {
		return true
	}
	range := matcher.Match.new(core.last_line_visited, upto)
	if range.is_empty() {
		return true
	}
	before_context_start := range.start() + preceding(buf[range.start()..range.end()],
		core.config.line_term.as_byte(), core.config.before_context - 1)

	context_range := matcher.Match.new(before_context_start, range.end())
	mut stepper := LineStep.new(core.config.line_term.as_byte(), context_range.start(),
		context_range.end())
	for {
		line := stepper.next_match(buf) or { break }
		if !core.sink_break_context(line.start())! {
			return false
		}
		if !core.sink_before_context(buf, line)! {
			return false
		}
	}
	return true
}

fn (mut core Core[^s]) after_context_by_line[^s](buf []u8, upto usize) !bool {
	if core.after_context_left == 0 {
		return true
	}
	exceeded_match_limit := core.has_exceeded_match_limit()
	range := matcher.Match.new(core.last_line_visited, upto)
	mut stepper := LineStep.new(core.config.line_term.as_byte(), range.start(), range.end())
	for {
		line := stepper.next_match(buf) or { break }
		if exceeded_match_limit
			&& core.is_match(buf[line.start()..line.end()])! != core.config.invert_match {
			after_context_left := core.after_context_left
			core.set_pos(line.end())
			if !core.sink_matched(buf, line)! {
				return false
			}
			core.after_context_left = after_context_left - 1
		} else if !core.sink_after_context(buf, line)! {
			return false
		}
		if core.after_context_left == 0 {
			break
		}
	}
	return true
}

fn (mut core Core[^s]) other_context_by_line[^s](buf []u8, upto usize) !bool {
	range := matcher.Match.new(core.last_line_visited, upto)
	mut stepper := LineStep.new(core.config.line_term.as_byte(), range.start(), range.end())
	for {
		line := stepper.next_match(buf) or { break }
		if !core.sink_other_context(buf, line)! {
			return false
		}
	}
	return true
}

fn (mut core Core[^s]) match_by_line_slow[^s](buf []u8) !bool {
	range := matcher.Match.new(core.pos(), buf.len)
	mut stepper := LineStep.new(core.config.line_term.as_byte(), range.start(), range.end())
	for {
		line := stepper.next_match(buf) or { break }
		if core.has_exceeded_match_limit() && !core.config.passthru && core.after_context_left == 0 {
			return false
		}
		// Stripping the line terminator is necessary to prevent some
		// classes of regexes from matching the empty position *after*
		// the end of the line. For example, `(?m)^$` will match at
		// position (2, 2) in the string `a\n`.
		slice := without_terminator(buf[line.start()..line.end()], core.config.line_term)
		mut matched := false
		if _ := core.shortest_match(slice)!.get() {
			matched = true
		}
		core.set_pos(line.end())

		success := matched != core.config.invert_match
		if success {
			core.has_matched = true
			core.increment_count()
			if !core.before_context_by_line(buf, line.start())! {
				return false
			}
			if !core.sink_matched(buf, line)! {
				return false
			}
		} else if core.after_context_left >= 1 {
			if !core.sink_after_context(buf, line)! {
				return false
			}
		} else if core.config.passthru {
			if !core.sink_other_context(buf, line)! {
				return false
			}
		}
		if core.config.stop_on_nonmatch && !success && core.has_matched {
			return false
		}
	}
	return true
}

fn (mut core Core[^s]) match_by_line_fast[^s](buf []u8) !FastMatchResult {
	for core.pos() < buf.len {
		if core.config.stop_on_nonmatch && core.has_matched {
			return .switch_to_slow
		}
		if core.config.invert_match {
			if !core.match_by_line_fast_invert(buf)! {
				break
			}
		} else {
			maybe_line := core.find_by_line_fast(buf)!
			if line := maybe_line.get() {
				core.has_matched = true
				core.increment_count()
				if core.config.max_context() > 0 {
					if !core.after_context_by_line(buf, line.start())! {
						return .stop
					}
					if !core.before_context_by_line(buf, line.start())! {
						return .stop
					}
				}
				core.set_pos(line.end())
				if !core.sink_matched(buf, line)! {
					return .stop
				}
			} else {
				break
			}
		}
	}
	if !core.after_context_by_line(buf, buf.len)! {
		return .stop
	}
	if core.has_exceeded_match_limit() && core.after_context_left == 0 {
		return .stop
	}
	core.set_pos(buf.len)
	return .continue_search
}

fn (mut core Core[^s]) match_by_line_fast_invert[^s](buf []u8) !bool {
	maybe_line := core.find_by_line_fast(buf)!
	invert_match := if line := maybe_line.get() {
		range := matcher.Match.new(core.pos(), line.start())
		core.set_pos(line.end())
		range
	} else {
		range := matcher.Match.new(core.pos(), buf.len)
		core.set_pos(range.end())
		range
	}
	if invert_match.is_empty() {
		return true
	}
	core.has_matched = true
	if !core.after_context_by_line(buf, invert_match.start())! {
		return false
	}
	if !core.before_context_by_line(buf, invert_match.start())! {
		return false
	}
	mut stepper := LineStep.new(core.config.line_term.as_byte(), invert_match.start(), invert_match.end())
	for {
		line := stepper.next_match(buf) or { break }
		core.increment_count()
		if !core.sink_matched(buf, line)! {
			return false
		}
		if core.has_exceeded_match_limit() {
			return false
		}
	}
	return true
}

fn (mut core Core[^s]) find_by_line_fast[^s](buf []u8) !matcher.FallibleMatch {
	mut pos := core.pos()
	for pos < buf.len {
		if core.has_exceeded_match_limit() {
			return matcher.FallibleMatch.absent()
		}
		maybe_kind := core.matcher_.find_candidate_line(buf[pos..])!
		kind := maybe_kind.get() or {
			return matcher.FallibleMatch.absent()
		}
		if kind.is_confirmed() {
			line := locate(buf, core.config.line_term.as_byte(), matcher.Match.zero(kind.position()).offset(pos))
			// If we matched beyond the end of the buffer, then we
			// don't report this as a match.
			if line.start() == buf.len {
				pos = buf.len
				continue
			}
			return matcher.FallibleMatch.some(line)
		}
		line := locate(buf, core.config.line_term.as_byte(), matcher.Match.zero(kind.position()).offset(pos))
		if core.is_match(buf[line.start()..line.end()])! {
			return matcher.FallibleMatch.some(line)
		}
		pos = line.end()
	}
	return matcher.FallibleMatch.absent()
}

fn (mut core Core[^s]) sink_matched[^s](buf []u8, range matcher.Match) !bool {
	if core.binary && core.detect_binary(buf, range)! {
		return false
	}
	if !core.sink_break_context(range.start())! {
		return false
	}
	core.count_lines(buf, range.start())
	offset := core.absolute_byte_offset + u64(range.start())
	keepgoing := core.sink.matched(*core.searcher, SinkMatch{
		line_term_:             core.config.line_term.as_byte()
		bytes_:                 buf[range.start()..range.end()]
		absolute_byte_offset_:  offset
		line_number_:           core.line_number
		buffer_:                buf
		bytes_range_in_buffer_: range
	})!
	if !keepgoing {
		return false
	}
	core.last_line_visited = range.end()
	core.after_context_left = core.config.after_context
	core.has_sunk = true
	return true
}

fn (mut core Core[^s]) sink_before_context[^s](buf []u8, range matcher.Match) !bool {
	if core.binary && core.detect_binary(buf, range)! {
		return false
	}
	core.count_lines(buf, range.start())
	offset := core.absolute_byte_offset + u64(range.start())
	keepgoing := core.sink.context(*core.searcher, SinkContext{
		line_term_:            core.config.line_term.as_byte()
		bytes_:                buf[range.start()..range.end()].clone()
		kind_:                 .before
		absolute_byte_offset_: offset
		line_number_:          core.line_number
	})!
	if !keepgoing {
		return false
	}
	core.last_line_visited = range.end()
	core.has_sunk = true
	return true
}

fn (mut core Core[^s]) sink_after_context[^s](buf []u8, range matcher.Match) !bool {
	assert core.after_context_left >= 1

	if core.binary && core.detect_binary(buf, range)! {
		return false
	}
	core.count_lines(buf, range.start())
	offset := core.absolute_byte_offset + u64(range.start())
	keepgoing := core.sink.context(*core.searcher, SinkContext{
		line_term_:            core.config.line_term.as_byte()
		bytes_:                buf[range.start()..range.end()].clone()
		kind_:                 .after
		absolute_byte_offset_: offset
		line_number_:          core.line_number
	})!
	if !keepgoing {
		return false
	}
	core.last_line_visited = range.end()
	core.after_context_left--
	core.has_sunk = true
	return true
}

fn (mut core Core[^s]) sink_other_context[^s](buf []u8, range matcher.Match) !bool {
	if core.binary && core.detect_binary(buf, range)! {
		return false
	}
	core.count_lines(buf, range.start())
	offset := core.absolute_byte_offset + u64(range.start())
	keepgoing := core.sink.context(*core.searcher, SinkContext{
		line_term_:            core.config.line_term.as_byte()
		bytes_:                buf[range.start()..range.end()].clone()
		kind_:                 .other
		absolute_byte_offset_: offset
		line_number_:          core.line_number
	})!
	if !keepgoing {
		return false
	}
	core.last_line_visited = range.end()
	core.has_sunk = true
	return true
}

fn (mut core Core[^s]) sink_break_context[^s](start_of_line usize) !bool {
	is_gap := core.last_line_visited < start_of_line
	any_context := core.config.before_context > 0 || core.config.after_context > 0

	if !any_context || !core.has_sunk || !is_gap {
		return true
	}
	return core.sink.context_break(*core.searcher)!
}

fn (mut core Core[^s]) count_lines[^s](buf []u8, upto usize) {
	if line_number := core.line_number {
		if core.last_line_counted >= upto {
			return
		}
		slice := buf[core.last_line_counted..upto]
		count := count_lines(slice, core.config.line_term.as_byte())
		core.line_number = line_number + count
		core.last_line_counted = upto
	}
}

fn (core Core[^s]) is_line_by_line_fast[^s]() bool {
	if core.config.passthru {
		return false
	}
	if core.config.stop_on_nonmatch && core.has_matched {
		return false
	}
	if line_term := core.matcher_.line_terminator() {
		// FIXME: This works around a bug in grep-regex where it does
		// not set the line terminator of the regex itself, and thus
		// line anchors like `(?m:^)` and `(?m:$)` will not match
		// anything except for `\n`. So for now, we just disable the fast
		// line-by-line searcher which requires the regex to be able to
		// deal with line terminators correctly. The slow line-by-line
		// searcher strips line terminators and thus absolves the regex
		// engine from needing to care about whether they are `\n` or NUL.
		if line_term.as_byte() == `\x00` {
			return false
		}
		if line_term == core.config.line_term {
			return true
		}
	}
	if non_matching := core.matcher_.non_matching_bytes() {
		// If the line terminator is CRLF, we don't actually need to care
		// whether the regex can match `\r` or not. Namely, a `\r` is
		// neither necessary nor sufficient to terminate a line. A `\n` is
		// always required.
		if matcher.byte_set_contains(non_matching, core.config.line_term.as_byte()) {
			return true
		}
	}
	return false
}

fn (core Core[^s]) has_exceeded_match_limit[^s]() bool {
	if limit := core.config.max_matches {
		return core.count() >= limit
	}
	return false
}

struct ReadByLine[^s, ^r, ^b] {
	config &^s Config
mut:
	core Core[^s]
	rdr  LineBufferReader[^r, ^b]
}

fn ReadByLine.new[^s, ^r, ^b](searcher &^s Searcher, matcher_ matcher.Matcher, read_from LineBufferReader[^r, ^b], write_to Sink) ReadByLine[^s, ^r, ^b] {
	mut line_number := ?u64(none)
	if searcher.config.line_number {
		line_number = u64(1)
	}
	return ReadByLine[^s, ^r, ^b]{
		config: &searcher.config
		core:   Core[^s]{
			config:      &searcher.config
			matcher_:    matcher_
			searcher:    searcher
			sink:        write_to
			binary:      false
			line_number: line_number
		}
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
mut:
	core  Core[^s]
	slice []u8
}

fn SliceByLine.new[^s](searcher &^s Searcher, matcher_ matcher.Matcher, slice []u8, write_to Sink) SliceByLine[^s] {
	mut line_number := ?u64(none)
	if searcher.config.line_number {
		line_number = u64(1)
	}
	return SliceByLine[^s]{
		core:  Core[^s]{
			config:      &searcher.config
			matcher_:    matcher_
			searcher:    searcher
			sink:        write_to
			binary:      true
			line_number: line_number
		}
		slice: slice.clone()
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
mut:
	core           Core[^s]
	slice          []u8
	last_match     ?matcher.Match
}

fn MultiLine.new[^s](searcher &^s Searcher, matcher_ matcher.Matcher, slice []u8, write_to Sink) MultiLine[^s] {
	mut line_number := ?u64(none)
	if searcher.config.line_number {
		line_number = u64(1)
	}
	return MultiLine[^s]{
		config: &searcher.config
		core:   Core[^s]{
			config:      &searcher.config
			matcher_:    matcher_
			searcher:    searcher
			sink:        write_to
			binary:      true
			line_number: line_number
		}
		slice:  slice.clone()
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

/// Returns true if and only if the given slice begins with a UTF-8 or UTF-16
/// BOM.
///
/// This is used by the searcher to determine if a transcoder is necessary.
/// Otherwise, it is advantageous to search the slice directly.
fn slice_has_bom(slice []u8) bool {
	return slice_has_utf8_bom(slice) || slice_has_utf16le_bom(slice) || slice_has_utf16be_bom(slice)
}

fn slice_has_utf8_bom(slice []u8) bool {
	return slice.len >= 3 && slice[0] == 0xef && slice[1] == 0xbb && slice[2] == 0xbf
}

fn slice_has_utf16le_bom(slice []u8) bool {
	return slice.len >= 2 && slice[0] == 0xff && slice[1] == 0xfe
}

fn slice_has_utf16be_bom(slice []u8) bool {
	return slice.len >= 2 && slice[0] == 0xfe && slice[1] == 0xff
}
