module printer

import matcher
import pcre2
import regex
import searcher
import time

fn match_new(start usize, end usize) matcher.Match {
	return matcher.Match.new(start, end)
}

enum PrinterMatcherKind {
	rust_regex
	pcre2
}

pub struct PrinterMatcher implements IClone, Drop {
	kind  PrinterMatcherKind
	regex regex.RegexMatcher
	pcre2 pcre2.RegexMatcher
}

pub fn PrinterMatcher.rust_regex(matcher_ &regex.RegexMatcher) PrinterMatcher {
	return PrinterMatcher{
		kind:  .rust_regex
		regex: matcher_.clone()
	}
}

pub fn PrinterMatcher.pcre2(matcher_ &pcre2.RegexMatcher) PrinterMatcher {
	return PrinterMatcher{
		kind:  .pcre2
		pcre2: matcher_.clone()
	}
}

pub fn (pm &PrinterMatcher) clone() PrinterMatcher {
	return match pm.kind {
		.rust_regex {
			PrinterMatcher{
				kind:  .rust_regex
				regex: pm.regex.clone()
			}
		}
		.pcre2 {
			PrinterMatcher{
				kind:  .pcre2
				pcre2: pm.pcre2.clone()
			}
		}
	}
}

fn (mut pm PrinterMatcher) drop() {
	match pm.kind {
		.rust_regex { pm.regex.drop() }
		.pcre2 { pm.pcre2.drop() }
	}
}

fn (pm &PrinterMatcher) find_at(haystack &[]u8, at usize) !matcher.FallibleMatch {
	return match pm.kind {
		.rust_regex { pm.regex.find_at(haystack, at)! }
		.pcre2 { pm.pcre2.find_at(haystack, at)! }
	}
}

fn (pm &PrinterMatcher) shortest_match_at(haystack &[]u8, at usize) !matcher.FallibleUsize {
	return match pm.kind {
		.rust_regex { pm.regex.shortest_match_at(haystack, at)! }
		.pcre2 { pm.pcre2.shortest_match_at(haystack, at)! }
	}
}

fn (pm &PrinterMatcher) new_captures() !matcher.NoCaptures {
	// V-specific: the Matcher interface cannot express the capture type of
	// either printer backend. Replacement uses `capture_groups_at` below.
	_ = pm
	return matcher.NoCaptures.new()
}

fn (pm &PrinterMatcher) capture_count() usize {
	return match pm.kind {
		.rust_regex { pm.regex.capture_count() }
		.pcre2 { pm.pcre2.capture_count() }
	}
}

fn (pm &PrinterMatcher) capture_index(name string) ?usize {
	return match pm.kind {
		.rust_regex { pm.regex.capture_index(name) }
		.pcre2 { pm.pcre2.capture_index(name) }
	}
}

fn (pm &PrinterMatcher) captures_at(haystack &[]u8, at usize, mut caps matcher.NoCaptures) !bool {
	_ = pm
	return matcher.default_captures_at(haystack, at, mut caps)
}

fn (pm &PrinterMatcher) capture_groups_at(haystack &[]u8, at usize) !(matcher.FallibleMatch, []string) {
	return match pm.kind {
		.rust_regex { pm.regex.capture_groups_at(haystack, at)! }
		.pcre2 { pm.pcre2.capture_groups_at(haystack, at)! }
	}
}

fn (pm &^a PrinterMatcher) non_matching_bytes[^a]() ?&^a matcher.ByteSet {
	return match pm.kind {
		.rust_regex { pm.regex.non_matching_bytes() }
		.pcre2 { none }
	}
}

fn (pm &PrinterMatcher) line_terminator() ?matcher.LineTerminator {
	return match pm.kind {
		.rust_regex { pm.regex.line_terminator() }
		.pcre2 { pm.pcre2.line_terminator() }
	}
}

fn (pm &PrinterMatcher) find_candidate_line(haystack &[]u8) !matcher.FallibleLineMatchKind {
	return match pm.kind {
		.rust_regex { pm.regex.find_candidate_line(haystack)! }
		.pcre2 { pm.pcre2.find_candidate_line(haystack)! }
	}
}

// V-specific: keep the concrete printer matcher type at printer call sites
// while delegating the decision to the translated searcher API.
fn printer_matcher_multi_line(searcher_ &searcher.Searcher, matcher_ &PrinterMatcher) bool {
	return searcher_.multi_line_with_matcher(matcher_)
}

/// A simple encapsulation of a file path used by a printer.
///
/// This represents any transforms that we might want to perform on the path,
/// such as converting it to valid UTF-8 and/or replacing its separator with
/// something else. This allows us to amortize work if we are printing the
/// file path for every match.
///
/// In the Rust implementation, the common case needs no transformation and
/// therefore avoids allocation. Typically, only Windows requires a transform,
/// since it's fraught to access the raw bytes of a path directly and first
/// needs to lossily convert to UTF-8. Windows is also typically where the path
/// separator replacement is used, e.g., in cygwin environments to use `/`
/// instead of `\`.
///
/// Users of this type are expected to construct it from a normal path string.
/// It can then be written to any writer implementation using the `as_bytes`
/// method.
///
/// V-specific: V strings replace Rust's `Path` and `Cow` representation, so
/// path bytes are materialized eagerly.
pub struct PrinterPath[^a] implements IClone {
	path &^a string
mut:
	bytes                 []u8
	rendered_path         string
	has_rendered_path     bool
	hyperlink             HyperlinkPath
	hyperlink_initialized bool
	has_hyperlink         bool
}

fn (mut pp PrinterPath[^a]) free[^a]() {
	// Assigning defaults auto-drops (frees) each owned field exactly once under
	// v3 ownership; a manual `.free()` first would double-free.
	pp.bytes = []u8{}
	pp.rendered_path = ''
	pp.has_rendered_path = false
	pp.hyperlink = HyperlinkPath{}
	pp.hyperlink_initialized = false
	pp.has_hyperlink = false
}

/// Create a new path suitable for printing.
pub fn PrinterPath.new[^a](path &^a string) PrinterPath[^a] {
	return PrinterPath[^a]{
		path:  path
		bytes: path.bytes()
	}
}

/// Set the separator on this path.
///
/// When set, `PrinterPath::as_bytes` will return the path provided but
/// with its separator replaced with the one given.
pub fn (pp PrinterPath[^a]) with_separator[^a](sep ?u8) PrinterPath[^a] {
	sep_value := sep or { return pp }
	mut result := pp.clone()
	for i, byte in result.bytes {
		$if windows {
			if byte == `/` || byte == `\\` {
				result.bytes[i] = sep_value
			}
		} $else {
			if byte == `/` {
				result.bytes[i] = sep_value
			}
		}
	}
	$if unix {
		result.rendered_path = result.bytes.bytestr()
		result.has_rendered_path = true
	}
	return result
}

/// Return the raw bytes for this path.
pub fn (pp &PrinterPath[^a]) as_bytes[^a]() []u8 {
	return pp.bytes
}

/// Return this path as a hyperlink.
///
/// Note that a hyperlink may not be able to be created from a path.
/// Namely, computing the hyperlink may require touching the file system
/// (e.g., for path canonicalization) and that can fail. This failure is
/// silent but is logged.
///
/// V-specific: the initialized bit plus optional cached value implement
/// Rust's `OnceCell<Option<HyperlinkPath>>` behavior.
pub fn (mut pp PrinterPath[^a]) as_hyperlink[^a]() ?&HyperlinkPath {
	if !pp.hyperlink_initialized {
		if hyperlink := HyperlinkPath.from_path(pp.as_path()) {
			pp.hyperlink = hyperlink
			pp.has_hyperlink = true
		}
		pp.hyperlink_initialized = true
	}
	if !pp.has_hyperlink {
		return none
	}
	return &pp.hyperlink
}

/// Return this path as an actual path string.
pub fn (pp &PrinterPath[^a]) as_path[^a]() &string {
	$if unix {
		if pp.has_rendered_path {
			return &pp.rendered_path
		}
	}
	return pp.path
}

/// A type that provides a "nicer" string representation for `time.Duration`.
///
/// V-specific: JSON serialization is implemented by the translated message
/// encoder instead of a serde implementation on this type.
pub struct NiceDuration implements IClone {
mut:
	duration time.Duration
}

pub fn (d NiceDuration) str() string {
	return '${d.fractional_seconds():0.6f}s'
}

/// Returns the number of seconds in this duration in fraction form.
/// The number to the left of the decimal point is the number of seconds,
/// and the number to the right is the number of milliseconds.
fn (d NiceDuration) fractional_seconds() f64 {
	return d.duration.seconds()
}

/// A simple formatter for converting `u64` values to ASCII byte strings.
///
/// This avoids going through the formatting machinery which seems to
/// substantially slow things down.
///
/// The `itoa` crate does the same thing as this formatter, but is a bit
/// faster. We roll our own which is a bit slower, but gets us enough of a win
/// to be satisfied with and with pure safe code.
pub struct DecimalFormatter {
	buf   [decimal_formatter_max_u64_len]u8
	start usize
}

/// Discovered via `u64::MAX.to_string().len()`.
const decimal_formatter_max_u64_len = 20

/// Create a new decimal formatter for the given 64-bit unsigned integer.
pub fn DecimalFormatter.new(n u64) DecimalFormatter {
	mut value := n
	mut buf := [decimal_formatter_max_u64_len]u8{}
	mut i := buf.len
	for {
		i--
		digit := u8(value % 10)
		value /= 10
		buf[i] = `0` + digit
		if value == 0 {
			break
		}
	}
	return DecimalFormatter{
		buf:   buf
		start: i
	}
}

/// Return the decimal formatted as an ASCII byte string.
pub fn (fmt &DecimalFormatter) as_bytes() []u8 {
	return fmt.buf[fmt.start..]
}

/// Trim prefix ASCII spaces from the given slice and return the corresponding
/// range.
///
/// This stops trimming a prefix as soon as it sees non-whitespace or a line
/// terminator.
pub fn trim_ascii_prefix(line_term matcher.LineTerminator, slice []u8, range matcher.Match) matcher.Match {
	mut count := usize(0)
	for b in slice[range.start()..range.end()] {
		if !(b == `\t` || b == `\n` || b == 0x0b || b == 0x0c || b == `\r` || b == ` `) {
			break
		}
		if b == line_term.as_byte() || (line_term.is_crlf() && b == `\r`) {
			break
		}
		count++
	}
	return range.with_start(range.start() + count)
}

pub fn find_iter_at_in_context(searcher_ &searcher.Searcher, matcher_ &PrinterMatcher, bytes_in []u8, range matcher.Match, matched fn (matcher.Match) bool) ! {
	mut bytes := bytes_in
	// This strange dance is to account for the possibility of look-ahead in
	// the regex. The problem here is that mat.bytes() doesn't include the
	// lines beyond the match boundaries in mulit-line mode, which means that
	// when we try to rediscover the full set of matches here, the regex may no
	// longer match if it required some look-ahead beyond the matching lines.
	//
	// PCRE2 (and the grep-matcher interfaces) has no way of specifying an end
	// bound of the search. So we kludge it and let the regex engine search the
	// rest of the buffer... But to avoid things getting too crazy, we cap the
	// buffer.
	//
	// If it weren't for multi-line mode, then none of this would be needed.
	// Alternatively, if we refactored the grep interfaces to pass along the
	// full set of matches (if available) from the searcher, then that might
	// also help here. But that winds up paying an upfront unavoidable cost for
	// the case where matches don't need to be counted. So then you'd have to
	// introduce a way to pass along matches conditionally, only when needed.
	// Yikes.
	//
	// Maybe the bigger picture thing here is that the searcher should be
	// responsible for finding matches when necessary, and the printer
	// shouldn't be involved in this business in the first place. Sigh. Live
	// and learn. Abstraction boundaries are hard.
	is_multi_line := printer_matcher_multi_line(searcher_, matcher_)
	if is_multi_line {
		if range.end() <= bytes.len && bytes[range.end()..].len >= max_look_ahead {
			bytes = bytes[..range.end() + max_look_ahead]
		}
	} else {
		mut line := matcher.Match.new(0, range.end())
		_ := trim_line_terminator(searcher_, &bytes, mut line)
		bytes = bytes[..line.end()]
	}
	matcher.find_iter_at(matcher_, bytes, range.start(), fn [range, matched] (m matcher.Match) bool {
		if m.start() >= range.end() {
			return false
		}
		return matched(m)
	})!
}

// V-specific: `PrinterMatcher` unifies matcher backends whose Rust associated
// capture types differ, so replacement interpolation uses this common view.
struct ReplacementCaptures implements IClone {
	overall     matcher.Match
	has_overall bool
	groups      []string
}

fn ReplacementCaptures.new(mat matcher.Match, groups []string) ReplacementCaptures {
	return ReplacementCaptures{
		overall:     mat
		has_overall: true
		groups:      groups
	}
}

fn (caps &ReplacementCaptures) len() usize {
	return if caps.has_overall { usize(caps.groups.len + 1) } else { usize(0) }
}

fn (caps &ReplacementCaptures) get(i usize) ?matcher.Match {
	if i == 0 && caps.has_overall {
		return caps.overall
	}
	return none
}

fn (caps &ReplacementCaptures) append(i usize, haystack []u8, mut dst []u8) {
	if i == 0 {
		if overall := caps.get(0) {
			append_match_bytes(mut dst, haystack, overall)
		}
		return
	}
	group_index := i - 1
	if group_index >= usize(caps.groups.len) {
		return
	}
	group := caps.groups[group_index]
	for i := 0; i < group.len; i++ {
		dst << group[i]
	}
}

fn append_bytes(mut dst []u8, bytes []u8) {
	for byte in bytes {
		dst << byte
	}
}

fn append_match_bytes(mut dst []u8, haystack []u8, mat matcher.Match) {
	for i := mat.start(); i < mat.end(); i++ {
		dst << haystack[i]
	}
}

/// A type for handling replacements while amortizing allocation.
pub struct Replacer {
mut:
	/// The place to write a replacement to.
	dst []u8
	/// The place to store match offsets in terms of `dst`.
	matches []matcher.Match
	// V-specific: arrays have an allocated empty state, so track whether a
	// replacement occurred separately from their allocation state.
	active bool
}

fn (mut replacer Replacer) free() {
	// Assigning empty arrays auto-drops (frees) the buffers exactly once under
	// v3 ownership; a manual `.free()` first would double-free.
	replacer.dst = []u8{}
	replacer.matches = []matcher.Match{}
	replacer.active = false
}

/// Create a new replacer for use with a particular matcher.
///
/// This constructor does not allocate. Instead, space for dealing with
/// replacements is allocated lazily only when needed.
pub fn Replacer.new() Replacer {
	return Replacer{}
}

/// Executes a replacement on the given haystack string by replacing all
/// matches with the given replacement. To access the result of the
/// replacement, use the `replacement` method.
///
/// This can fail if the underlying matcher reports an error.
pub fn (mut replacer Replacer) replace_all(searcher_ &searcher.Searcher, matcher_ &PrinterMatcher, haystack_in []u8, range matcher.Match, replacement []u8) ! {
	mut haystack := haystack_in
	mut line_terminator := []u8{}
	is_multi_line := printer_matcher_multi_line(searcher_, matcher_)
	if is_multi_line {
		if range.end() <= haystack.len && haystack[range.end()..].len >= max_look_ahead {
			haystack = haystack[..range.end() + max_look_ahead]
		}
	} else {
		mut m := matcher.Match.new(0, range.end())
		trimmed := trim_line_terminator(searcher_, &haystack, mut m)
		line_terminator = trimmed.bytes
		haystack = haystack[..m.end()]
	}
	replacer.dst.clear()
	replacer.matches.clear()
	replace_with_captures_in_context(matcher_, haystack, line_terminator, range, replacement,
		mut replacer.dst, mut replacer.matches)!
	replacer.active = replacer.matches.len > 0
}

/// Return the result of the prior replacement and the match offsets for
/// all replacement occurrences within the returned replacement buffer.
///
/// If no replacement has occurred then `None` is returned.
pub fn (replacer &^a Replacer) replacement[^a]() ?Replacement[^a] {
	if !replacer.active || replacer.matches.len == 0 {
		return none
	}
	return Replacement[^a]{
		bytes:   replacer.dst[0..replacer.dst.len]
		matches: replacer.matches[0..replacer.matches.len]
	}
}

/// Clear space used for performing a replacement.
///
/// Subsequent calls to `replacement` after calling `clear` (but before
/// executing another replacement) will always return `None`.
pub fn (mut replacer Replacer) clear() {
	replacer.dst.clear()
	replacer.matches.clear()
	replacer.active = false
}

// V-specific: this lifetime-only wrapper represents Rust's
// `Option<(&[u8], &[Match])`; its slices are borrowed views into `Replacer`.
pub struct Replacement[^a] {
	bytes   []u8
	matches []matcher.Match
}

/// A simple layer of abstraction over either a match or a contextual line
/// reported by the searcher.
///
/// In particular, this provides an API that unions the `SinkMatch` and
/// `SinkContext` types while also exposing a list of all individual match
/// locations.
///
/// While this serves as a convenient mechanism to abstract over `SinkMatch`
/// and `SinkContext`, this also provides a way to abstract over replacements.
/// Namely, after a replacement, a `Sunk` value can be constructed using the
/// results of the replacement instead of the bytes reported directly by the
/// searcher.
pub struct Sunk[^a] {
	// V-specific: V slice descriptors carry the borrowed views represented by
	// the explicit lifetime parameter.
	bytes_                []u8
	absolute_byte_offset_ u64
	line_number_          ?u64
	context_kind_         ?&^a searcher.SinkContextKind
	matches_              []matcher.Match
	original_matches_     []matcher.Match
}

@[inline]
pub fn Sunk.empty[^a]() Sunk[^a] {
	return Sunk[^a]{}
}

@[inline]
pub fn Sunk.from_sink_match[^a, ^b](sunk &^a searcher.SinkMatch[^b], original_matches &^a []matcher.Match, replacement ?Replacement[^a]) Sunk[^a] {
	if repl := replacement {
		return Sunk[^a]{
			bytes_:                repl.bytes[0..repl.bytes.len]
			absolute_byte_offset_: sunk.absolute_byte_offset()
			line_number_:          sunk.line_number()
			matches_:              repl.matches[0..repl.matches.len]
			original_matches_:     unsafe {
				(*original_matches)[0..original_matches.len]
			}
		}
	}
	bytes := sunk.bytes()
	return Sunk[^a]{
		bytes_:                bytes[0..bytes.len]
		absolute_byte_offset_: sunk.absolute_byte_offset()
		line_number_:          sunk.line_number()
		matches_:              unsafe { (*original_matches)[0..original_matches.len] }
		original_matches_:     unsafe { (*original_matches)[0..original_matches.len] }
	}
}

@[inline]
pub fn Sunk.from_sink_context[^a, ^b](sunk &^a searcher.SinkContext[^b], original_matches &^a []matcher.Match, replacement ?Replacement[^a]) Sunk[^a] {
	if repl := replacement {
		return Sunk[^a]{
			bytes_:                repl.bytes[0..repl.bytes.len]
			absolute_byte_offset_: sunk.absolute_byte_offset()
			line_number_:          sunk.line_number()
			context_kind_:         sunk.kind()
			matches_:              repl.matches[0..repl.matches.len]
			original_matches_:     unsafe {
				(*original_matches)[0..original_matches.len]
			}
		}
	}
	bytes := sunk.bytes()
	return Sunk[^a]{
		bytes_:                bytes[0..bytes.len]
		absolute_byte_offset_: sunk.absolute_byte_offset()
		line_number_:          sunk.line_number()
		context_kind_:         sunk.kind()
		matches_:              unsafe { (*original_matches)[0..original_matches.len] }
		original_matches_:     unsafe { (*original_matches)[0..original_matches.len] }
	}
}

@[inline]
pub fn (sunk &^a Sunk[^a]) context_kind[^a]() ?&^a searcher.SinkContextKind {
	return sunk.context_kind_
}

@[inline]
pub fn (sunk &Sunk[^a]) bytes[^a]() []u8 {
	return sunk.bytes_
}

@[inline]
pub fn (sunk &Sunk[^a]) matches[^a]() []matcher.Match {
	return sunk.matches_
}

@[inline]
pub fn (sunk &Sunk[^a]) original_matches[^a]() []matcher.Match {
	return sunk.original_matches_
}

@[inline]
pub fn (sunk &Sunk[^a]) lines[^a](line_term u8) searcher.LineIter[^a] {
	return searcher.LineIter.new(line_term, sunk.bytes())
}

@[inline]
pub fn (sunk &Sunk[^a]) absolute_byte_offset[^a]() u64 {
	return sunk.absolute_byte_offset_
}

@[inline]
pub fn (sunk &Sunk[^a]) line_number[^a]() ?u64 {
	return sunk.line_number_
}

// V-specific: a lifetime-only carrier expresses that the removed terminator
// is a borrowed view into the input buffer.
struct BorrowedLineTerminator[^b] {
	bytes []u8
}

/// Given a buf and some bounds, if there is a line terminator at the end of
/// the given bounds in buf, then the bounds are trimmed to remove the line
/// terminator, returning the slice of the removed line terminator (if any).
fn trim_line_terminator[^b](searcher_ &searcher.Searcher, buf &^b []u8, mut line matcher.Match) BorrowedLineTerminator[^b] {
	lineterm := searcher_.line_terminator()
	bytes := *buf
	if lineterm.is_suffix(bytes[line.start()..line.end()]) {
		mut end := line.end() - 1
		if lineterm.is_crlf() && end > 0 && bytes[end - 1] == `\r` {
			end--
		}
		orig_end := line.end()
		line = line.with_end(end)
		return BorrowedLineTerminator[^b]{
			bytes: bytes[end..orig_end]
		}
	}
	return BorrowedLineTerminator[^b]{}
}

/// Like `Matcher::replace_with_captures_at`, but accepts an end bound.
///
/// See also: `find_iter_at_in_context` for why we need this.
fn replace_with_captures_in_context(matcher_ &PrinterMatcher, bytes []u8, line_terminator []u8, range matcher.Match, replacement []u8, mut dst []u8, mut matches []matcher.Match) ! {
	mut last_match := range.start()
	mut search_start := range.start()
	mut has_last_match := false
	mut last_match_end := usize(0)
	for {
		if search_start > bytes.len {
			break
		}
		maybe_mat, groups := matcher_.capture_groups_at(bytes, search_start)!
		if !maybe_mat.has_value {
			break
		}
		mat := maybe_mat.value
		if mat.start() >= range.end() {
			break
		}
		next_start := if mat.start() == mat.end() {
			next := mat.end() + 1
			if has_last_match && mat.end() == last_match_end {
				search_start = next
				continue
			}
			next
		} else {
			mat.end()
		}
		append_bytes(mut dst, bytes[last_match..mat.start()])
		start := dst.len
		caps := ReplacementCaptures.new(mat, groups)
		matcher.interpolate(replacement, fn [caps, bytes] (i usize, mut output []u8) {
			caps.append(i, bytes, mut output)
		}, fn [matcher_] (name string) ?usize {
			return matcher_.capture_index(name)
		}, mut dst)
		end := dst.len
		matches << match_new(start, end)
		last_match = mat.end()
		search_start = next_start
		has_last_match = true
		last_match_end = mat.end()
	}
	end := if last_match > range.end() {
		bytes.len
	} else if range.end() < bytes.len {
		range.end()
	} else {
		bytes.len
	}
	append_bytes(mut dst, bytes[last_match..end])
	// Add back any line terminator.
	append_bytes(mut dst, line_terminator)
}
