module searcher

import matcher

interface IClone {}

/// A minimal translated surface for `grep-searcher` needed by `printer`
/// until the rest of the searcher crate is translated.

enum BinaryDetectionKind {
	none
	quit
	convert
}

pub struct BinaryDetection implements IClone {
	kind BinaryDetectionKind
	byte u8
}

pub fn BinaryDetection.disabled() BinaryDetection {
	return BinaryDetection{
		kind: .none
	}
}

pub fn BinaryDetection.quit(byte u8) BinaryDetection {
	return BinaryDetection{
		kind: .quit
		byte: byte
	}
}

pub fn BinaryDetection.convert(byte u8) BinaryDetection {
	return BinaryDetection{
		kind: .convert
		byte: byte
	}
}

pub fn (d BinaryDetection) quit_byte() ?u8 {
	if d.kind == .quit {
		return d.byte
	}
	return none
}

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

/// An encoding to use when searching.
///
/// An encoding can be used to configure a [`SearcherBuilder`] to transcode
/// source data from an encoding to UTF-8 before searching.
///
/// An `Encoding` will always be cheap to clone.
pub struct Encoding implements IClone {
	label string
}

/// Create a new encoding for the specified label.
///
/// The encoding label provided is mapped to an encoding via the set of
/// available choices specified in the
/// [Encoding Standard](https://encoding.spec.whatwg.org/#concept-encoding-get).
/// If the given label does not correspond to a valid encoding, then this
/// returns an error.
///
/// V-specific: transcoding itself is not wired into the searcher yet, so this
/// stores the label for the later decoder implementation.
pub fn Encoding.new(label string) !Encoding {
	if label.len == 0 {
		return error('grep config error: unknown encoding: ${label}')
	}
	return Encoding{
		label: label.to_owned()
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
	///
	/// V-specific: V2 currently mis-codegens `?Encoding` fields in struct
	/// literals, so this keeps the optional encoding as a value plus a tag.
	encoding     Encoding
	has_encoding bool
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
		has_encoding:     config.has_encoding
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
	if value := encoding {
		builder.config.encoding = value
		builder.config.has_encoding = true
	} else {
		builder.config.encoding = Encoding{}
		builder.config.has_encoding = false
	}
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

pub struct Searcher implements IClone {
mut:
	config            Config
	line_buffer       LineBuffer
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
		if line_term == s.line_terminator() {
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

/// Execute a search over the given slice and write the results to the
/// given sink.
pub fn (mut s Searcher) search_slice(matcher_ matcher.Matcher, slice []u8, write_to Sink) ! {
	s.check_config(matcher_)!

	// We can search the slice directly, unless we need to do transcoding.
	if s.slice_needs_transcoding(slice) {
		return error('grep searcher: transcoding slice search is not translated yet')
	}
	if s.multi_line_with_matcher(matcher_) {
		mut search := MultiLine.new(&s, matcher_, slice, write_to)
		search.run()!
	} else {
		mut search := SliceByLine.new(&s, matcher_, slice, write_to)
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
	if matcher_line_term != s.config.line_term {
		return ConfigError.mismatched_line_terminators(matcher_line_term, s.config.line_term)
	}
}

/// Returns true if and only if the given slice needs to be transcoded.
fn (s Searcher) slice_needs_transcoding(slice []u8) bool {
	return s.config.has_encoding || (s.config.bom_sniffing && slice_has_bom(slice))
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
	before
	after
	other
}

pub struct SinkContext implements IClone {
	kind_                  SinkContextKind
	buffer_                []u8
	bytes_range_in_buffer_ matcher.Match
	absolute_byte_offset_  u64
	line_number_           ?u64
	line_term_             u8 = `\n`
}

pub fn SinkContext.new(kind SinkContextKind, buffer []u8, bytes_range_in_buffer matcher.Match) SinkContext {
	return SinkContext{
		kind_:                  kind
		buffer_:                buffer.clone()
		bytes_range_in_buffer_: bytes_range_in_buffer
	}
}

pub fn (ctx SinkContext) with_absolute_byte_offset(absolute_byte_offset u64) SinkContext {
	return SinkContext{
		kind_:                  ctx.kind_
		buffer_:                ctx.buffer_.clone()
		bytes_range_in_buffer_: ctx.bytes_range_in_buffer_
		absolute_byte_offset_:  absolute_byte_offset
		line_number_:           ctx.line_number_
		line_term_:             ctx.line_term_
	}
}

pub fn (ctx SinkContext) with_line_number(line_number ?u64) SinkContext {
	return SinkContext{
		kind_:                  ctx.kind_
		buffer_:                ctx.buffer_.clone()
		bytes_range_in_buffer_: ctx.bytes_range_in_buffer_
		absolute_byte_offset_:  ctx.absolute_byte_offset_
		line_number_:           line_number
		line_term_:             ctx.line_term_
	}
}

pub fn (ctx SinkContext) with_line_term(line_term u8) SinkContext {
	return SinkContext{
		kind_:                  ctx.kind_
		buffer_:                ctx.buffer_.clone()
		bytes_range_in_buffer_: ctx.bytes_range_in_buffer_
		absolute_byte_offset_:  ctx.absolute_byte_offset_
		line_number_:           ctx.line_number_
		line_term_:             line_term
	}
}

pub fn (ctx SinkContext) kind() SinkContextKind {
	return ctx.kind_
}

pub fn (ctx SinkContext) buffer() []u8 {
	return ctx.buffer_.clone()
}

pub fn (ctx SinkContext) bytes_range_in_buffer() matcher.Match {
	return ctx.bytes_range_in_buffer_
}

pub fn (ctx SinkContext) bytes() []u8 {
	return ctx.buffer_[ctx.bytes_range_in_buffer_.start()..ctx.bytes_range_in_buffer_.end()].clone()
}

pub fn (ctx SinkContext) absolute_byte_offset() u64 {
	return ctx.absolute_byte_offset_
}

pub fn (ctx SinkContext) line_number() ?u64 {
	return ctx.line_number_
}

pub fn (ctx SinkContext) lines() LineIter {
	return LineIter.new(ctx.bytes(), ctx.line_term_)
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

fn (core Core[^s]) pos() usize {
	return core.pos
}

fn (mut core Core[^s]) set_pos(pos usize) {
	core.pos = pos
}

fn (core Core[^s]) count() u64 {
	return core.count_
}

fn (mut core Core[^s]) increment_count() {
	core.count_++
}

fn (core Core[^s]) binary_byte_offset() ?u64 {
	if offset := core.binary_byte_offset_ {
		return u64(offset)
	}
	return none
}

fn (mut core Core[^s]) matched(buf []u8, range matcher.Match) !bool {
	return core.sink_matched(buf, range)!
}

fn (mut core Core[^s]) binary_data(binary_byte_offset u64) !bool {
	return core.sink.binary_data(*core.searcher, binary_byte_offset)!
}

fn (mut core Core[^s]) is_match(line []u8) !bool {
	// We need to strip the line terminator here to match the
	// semantics of line-by-line searching. Namely, regexes
	// like `(?m)^$` can match at the final position beyond a
	// line terminator, which is non-sensical in line oriented
	// matching.
	line_without_term := without_terminator(line, core.config.line_term)
	maybe_match := core.shortest_match(line_without_term)!
	if _ := maybe_match.get() {
		return true
	}
	return false
}

fn (mut core Core[^s]) find(slice []u8) !matcher.FallibleMatch {
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

fn (mut core Core[^s]) shortest_match(slice []u8) !matcher.FallibleUsize {
	if core.has_exceeded_match_limit() {
		return matcher.FallibleUsize.absent()
	}
	maybe_match := core.matcher_.find_at(slice, 0)!
	if mat := maybe_match.get() {
		return matcher.FallibleUsize.some(mat.end())
	}
	return matcher.FallibleUsize.absent()
}

fn (mut core Core[^s]) begin() !bool {
	return core.sink.begin(*core.searcher)!
}

fn (mut core Core[^s]) finish(byte_count u64, binary_byte_offset ?u64) ! {
	core.sink.finish(*core.searcher, SinkFinish{
		byte_count_:         byte_count
		binary_byte_offset_: binary_byte_offset
	})!
}

fn (mut core Core[^s]) match_by_line(buf []u8) !bool {
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

fn (mut core Core[^s]) roll(buf []u8) usize {
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

fn (mut core Core[^s]) detect_binary(buf []u8, range matcher.Match) !bool {
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

fn (mut core Core[^s]) before_context_by_line(buf []u8, upto usize) !bool {
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

fn (mut core Core[^s]) after_context_by_line(buf []u8, upto usize) !bool {
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

fn (mut core Core[^s]) other_context_by_line(buf []u8, upto usize) !bool {
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

fn (mut core Core[^s]) match_by_line_slow(buf []u8) !bool {
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

fn (mut core Core[^s]) match_by_line_fast(buf []u8) !FastMatchResult {
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

fn (mut core Core[^s]) match_by_line_fast_invert(buf []u8) !bool {
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

fn (mut core Core[^s]) find_by_line_fast(buf []u8) !matcher.FallibleMatch {
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

fn (mut core Core[^s]) sink_matched(buf []u8, range matcher.Match) !bool {
	if core.binary && core.detect_binary(buf, range)! {
		return false
	}
	if !core.sink_break_context(range.start())! {
		return false
	}
	core.count_lines(buf, range.start())
	offset := core.absolute_byte_offset + u64(range.start())
	keepgoing := core.sink.matched(*core.searcher, SinkMatch.new(buf, range).with_absolute_byte_offset(offset).with_line_number(core.line_number).with_line_term(core.config.line_term.as_byte()))!
	if !keepgoing {
		return false
	}
	core.last_line_visited = range.end()
	core.after_context_left = core.config.after_context
	core.has_sunk = true
	return true
}

fn (mut core Core[^s]) sink_before_context(buf []u8, range matcher.Match) !bool {
	if core.binary && core.detect_binary(buf, range)! {
		return false
	}
	core.count_lines(buf, range.start())
	offset := core.absolute_byte_offset + u64(range.start())
	keepgoing := core.sink.context(*core.searcher, SinkContext.new(.before, buf, range).with_absolute_byte_offset(offset).with_line_number(core.line_number).with_line_term(core.config.line_term.as_byte()))!
	if !keepgoing {
		return false
	}
	core.last_line_visited = range.end()
	core.has_sunk = true
	return true
}

fn (mut core Core[^s]) sink_after_context(buf []u8, range matcher.Match) !bool {
	assert core.after_context_left >= 1

	if core.binary && core.detect_binary(buf, range)! {
		return false
	}
	core.count_lines(buf, range.start())
	offset := core.absolute_byte_offset + u64(range.start())
	keepgoing := core.sink.context(*core.searcher, SinkContext.new(.after, buf, range).with_absolute_byte_offset(offset).with_line_number(core.line_number).with_line_term(core.config.line_term.as_byte()))!
	if !keepgoing {
		return false
	}
	core.last_line_visited = range.end()
	core.after_context_left--
	core.has_sunk = true
	return true
}

fn (mut core Core[^s]) sink_other_context(buf []u8, range matcher.Match) !bool {
	if core.binary && core.detect_binary(buf, range)! {
		return false
	}
	core.count_lines(buf, range.start())
	offset := core.absolute_byte_offset + u64(range.start())
	keepgoing := core.sink.context(*core.searcher, SinkContext.new(.other, buf, range).with_absolute_byte_offset(offset).with_line_number(core.line_number).with_line_term(core.config.line_term.as_byte()))!
	if !keepgoing {
		return false
	}
	core.last_line_visited = range.end()
	core.has_sunk = true
	return true
}

fn (mut core Core[^s]) sink_break_context(start_of_line usize) !bool {
	is_gap := core.last_line_visited < start_of_line
	any_context := core.config.before_context > 0 || core.config.after_context > 0

	if !any_context || !core.has_sunk || !is_gap {
		return true
	}
	return core.sink.context_break(*core.searcher)!
}

fn (mut core Core[^s]) count_lines(buf []u8, upto usize) {
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

fn (core Core[^s]) is_line_by_line_fast() bool {
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

fn (core Core[^s]) has_exceeded_match_limit() bool {
	if limit := core.config.max_matches {
		return core.count() >= limit
	}
	return false
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

fn (mut search SliceByLine[^s]) run() ! {
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

fn (mut search SliceByLine[^s]) byte_count() u64 {
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

fn (mut search MultiLine[^s]) run() ! {
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

fn (mut search MultiLine[^s]) sink() !bool {
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

fn (mut search MultiLine[^s]) sink_matched_inverted() !bool {
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

fn (mut search MultiLine[^s]) sink_matched(range matcher.Match) !bool {
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

fn (mut search MultiLine[^s]) sink_context(range matcher.Match) !bool {
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

fn (mut search MultiLine[^s]) find() !matcher.FallibleMatch {
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
fn (mut search MultiLine[^s]) advance(range matcher.Match) {
	search.core.set_pos(range.end())
	if range.is_empty() && search.core.pos() < search.slice.len {
		newpos := search.core.pos() + 1
		search.core.set_pos(newpos)
	}
}

fn (mut search MultiLine[^s]) byte_count() u64 {
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
	if slice.len >= 3 && slice[0] == 0xef && slice[1] == 0xbb && slice[2] == 0xbf {
		return true
	}
	if slice.len >= 2 && slice[0] == 0xff && slice[1] == 0xfe {
		return true
	}
	if slice.len >= 2 && slice[0] == 0xfe && slice[1] == 0xff {
		return true
	}
	return false
}
