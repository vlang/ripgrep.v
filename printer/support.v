module printer

import os
import matcher
import searcher
import time

/// A simple encapsulation of a file path used by a printer.
///
/// This represents any transforms that we might want to perform on the path,
/// such as converting it to valid UTF-8 and/or replacing its separator with
/// something else. This allows us to amortize work if we are printing the
/// file path for every match.
///
/// This port uses V strings for paths instead of Rust's `Path` and `Cow`
/// representation. The original behavior is preserved, but the path bytes are
/// always materialized eagerly.
pub struct PrinterPath[^a] implements IClone {
	path &^a string
mut:
	bytes     []u8
	hyperlink ?HyperlinkPath
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
pub fn (pp PrinterPath[^a]) with_separator(sep ?u8) PrinterPath[^a] {
	sep_value := sep or { return pp }
	mut bytes := pp.bytes.clone()
	for i, byte in bytes {
		$if windows {
			if byte == `/` || byte == `\\` {
				bytes[i] = sep_value
			}
		} $else {
			if byte == `/` {
				bytes[i] = sep_value
			}
		}
	}
	return PrinterPath[^a]{
		path:  pp.path
		bytes: bytes
	}
}

/// Return the raw bytes for this path.
pub fn (pp PrinterPath[^a]) as_bytes() []u8 {
	return pp.bytes.clone()
}

/// Return this path as a hyperlink.
///
/// This port uses an optional cached hyperlink value instead of a `OnceCell`.
pub fn (mut pp PrinterPath[^a]) as_hyperlink[^a]() ?&^a HyperlinkPath {
	if pp.hyperlink == none {
		hyperlink := HyperlinkPath.from_path(*pp.path) or { return none }
		pp.hyperlink = hyperlink
	}
	return unsafe { &pp.hyperlink? }
}

/// Return this path as an actual path string.
pub fn (pp PrinterPath[^a]) as_path[^a]() &^a string {
	return pp.path
}

/// A type that provides "nicer" Display impls for `time.Duration`.
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
pub struct DecimalFormatter {
	buf   []u8
	start usize
}

/// Create a new decimal formatter for the given 64-bit unsigned integer.
pub fn DecimalFormatter.new(n u64) DecimalFormatter {
	mut value := n
	mut buf := []u8{len: 20, init: u8(0)}
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
		start: usize(i)
	}
}

/// Return the decimal formatted as an ASCII byte string.
pub fn (fmt DecimalFormatter) as_bytes() []u8 {
	return fmt.buf[fmt.start..].clone()
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
		if line_term.is_suffix([b]) {
			break
		}
		count++
	}
	return range.with_start(range.start() + count)
}

pub fn normalize_hyperlink_path(path string) ?string {
	canonical := os.real_path(path)
	if canonical == '' || !os.is_abs_path(canonical) {
		return none
	}
	return canonical.clone()
}

pub fn find_iter_at_in_context[M](searcher_ searcher.Searcher, matcher_ M, bytes_in []u8, range matcher.Match, matched fn (matcher.Match) bool) ! {
	mut bytes := bytes_in.clone()
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
	is_multi_line := searcher_.multi_line_with_matcher(matcher_)
	if is_multi_line {
		if range.end() <= bytes.len && bytes[range.end()..].len >= max_look_ahead {
			bytes = bytes[..range.end() + max_look_ahead].clone()
		}
	} else {
		mut line := matcher.Match.new(0, range.end())
		line, _ = trim_line_terminator(searcher_, bytes, line)
		bytes = bytes[..line.end()].clone()
	}
	matcher.find_iter_at(matcher_, bytes, range.start(), fn [range, matched] (m matcher.Match) bool {
		if m.start() >= range.end() {
			return false
		}
		return matched(m)
	})!
}

// V does not have Rust's associated `M::Captures` type here, so replacements
// use the overall match found by `find_iter_at` for `$0` interpolation.
struct ReplacementCaptures implements IClone {
	overall     matcher.Match
	has_overall bool
}

fn ReplacementCaptures.overall(mat matcher.Match) ReplacementCaptures {
	return ReplacementCaptures{
		overall:     mat
		has_overall: true
	}
}

fn (caps ReplacementCaptures) len() usize {
	return if caps.has_overall { usize(1) } else { usize(0) }
}

fn (caps ReplacementCaptures) get(i usize) ?matcher.Match {
	if i == 0 && caps.has_overall {
		return caps.overall
	}
	return none
}

fn replacement_no_capture_index(name string) ?usize {
	_ = name
	return none
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
pub struct Replacer[M] {
mut:
	dst     []u8
	matches []matcher.Match
	active  bool
}

/// Create a new replacer for use with a particular matcher.
///
/// This constructor does not allocate. Instead, space for dealing with
/// replacements is allocated lazily only when needed.
pub fn Replacer.new[M]() Replacer[M] {
	return Replacer[M]{}
}

/// Executes a replacement on the given haystack string by replacing all
/// matches with the given replacement. To access the result of the
/// replacement, use the `replacement` method.
///
/// This can fail if the underlying matcher reports an error.
pub fn (mut replacer Replacer[M]) replace_all(searcher_ searcher.Searcher, matcher_ M, haystack_in []u8, range matcher.Match, replacement []u8) ! {
	mut haystack := haystack_in.clone()
	mut line_terminator := []u8{}
	is_multi_line := searcher_.multi_line_with_matcher(matcher_)
	if is_multi_line {
		if range.end() <= haystack.len && haystack[range.end()..].len >= max_look_ahead {
			haystack = haystack[..range.end() + max_look_ahead].clone()
		}
	} else {
		mut m := matcher.Match.new(0, range.end())
		m, line_terminator = trim_line_terminator(searcher_, haystack, m)
		haystack = haystack[..m.end()].clone()
	}
	replacer.dst.clear()
	replacer.matches.clear()
	mut last_match := range.start()
	matcher.find_iter_at(matcher_, haystack, range.start(), fn [haystack, replacement, range, mut last_match, mut replacer] (mat matcher.Match) bool {
		if mat.start() >= range.end() {
			return false
		}
		append_bytes(mut replacer.dst, haystack[last_match..mat.start()])
		start := replacer.dst.len
		caps := ReplacementCaptures.overall(mat)
		matcher.interpolate(replacement, fn [caps, haystack] (i usize, mut dst []u8) {
			cap_match := caps.get(i) or {
				return
			}
			append_match_bytes(mut dst, haystack, cap_match)
		}, replacement_no_capture_index, mut replacer.dst)
		end := replacer.dst.len
		replacer.matches << matcher.Match.new(start, end)
		last_match = mat.end()
		return true
	})!
	end := if last_match > range.end() {
		haystack.len
	} else if range.end() < haystack.len {
		range.end()
	} else {
		haystack.len
	}
	append_bytes(mut replacer.dst, haystack[last_match..end])
	append_bytes(mut replacer.dst, line_terminator)
	replacer.active = replacer.matches.len > 0
}

/// Return the result of the prior replacement and the match offsets for
/// all replacement occurrences within the returned replacement buffer.
///
/// If no replacement has occurred then `None` is returned.
pub fn (replacer Replacer[M]) replacement() ?Replacement {
	if !replacer.active || replacer.matches.len == 0 {
		return none
	}
	return Replacement{
		bytes:   replacer.dst.clone()
		matches: replacer.matches.clone()
	}
}

/// Clear space used for performing a replacement.
///
/// Subsequent calls to `replacement` after calling `clear` (but before
/// executing another replacement) will always return `None`.
pub fn (mut replacer Replacer[M]) clear() {
	replacer.dst.clear()
	replacer.matches.clear()
	replacer.active = false
}

pub struct Replacement implements IClone {
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
pub struct Sunk implements IClone {
	bytes_                []u8
	absolute_byte_offset_ u64
	line_number_          ?u64
	context_kind_         ?searcher.SinkContextKind
	matches_              []matcher.Match
	original_matches_     []matcher.Match
}

pub fn Sunk.empty() Sunk {
	return Sunk{}
}

pub fn Sunk.from_sink_match(sunk searcher.SinkMatch, original_matches []matcher.Match, replacement ?Replacement) Sunk {
	if repl := replacement {
		return Sunk{
			bytes_:                repl.bytes.clone()
			absolute_byte_offset_: sunk.absolute_byte_offset()
			line_number_:          sunk.line_number()
			matches_:              repl.matches.clone()
			original_matches_:     original_matches.clone()
		}
	}
	return Sunk{
		bytes_:                sunk.bytes()
		absolute_byte_offset_: sunk.absolute_byte_offset()
		line_number_:          sunk.line_number()
		matches_:              original_matches.clone()
		original_matches_:     original_matches.clone()
	}
}

pub fn Sunk.from_sink_context(sunk searcher.SinkContext, original_matches []matcher.Match, replacement ?Replacement) Sunk {
	if repl := replacement {
		return Sunk{
			bytes_:                repl.bytes.clone()
			absolute_byte_offset_: sunk.absolute_byte_offset()
			line_number_:          sunk.line_number()
			context_kind_:         sunk.kind()
			matches_:              repl.matches.clone()
			original_matches_:     original_matches.clone()
		}
	}
	return Sunk{
		bytes_:                sunk.bytes()
		absolute_byte_offset_: sunk.absolute_byte_offset()
		line_number_:          sunk.line_number()
		context_kind_:         sunk.kind()
		matches_:              original_matches.clone()
		original_matches_:     original_matches.clone()
	}
}

pub fn (sunk Sunk) context_kind() ?searcher.SinkContextKind {
	return sunk.context_kind_
}

pub fn (sunk Sunk) bytes() []u8 {
	return sunk.bytes_.clone()
}

pub fn (sunk Sunk) matches() []matcher.Match {
	return sunk.matches_.clone()
}

pub fn (sunk Sunk) original_matches() []matcher.Match {
	return sunk.original_matches_.clone()
}

pub fn (sunk Sunk) lines(line_term u8) searcher.LineIter {
	return searcher.LineIter.new(sunk.bytes(), line_term)
}

pub fn (sunk Sunk) absolute_byte_offset() u64 {
	return sunk.absolute_byte_offset_
}

pub fn (sunk Sunk) line_number() ?u64 {
	return sunk.line_number_
}

fn trim_line_terminator(searcher_ searcher.Searcher, buf []u8, line matcher.Match) (matcher.Match, []u8) {
	lineterm := searcher_.line_terminator()
	if lineterm.is_suffix(buf[line.start()..line.end()]) {
		mut end := line.end() - 1
		if lineterm.is_crlf() && end > 0 && buf[end - 1] == `\r` {
			end--
		}
		orig_end := line.end()
		new_line := line.with_end(end)
		return new_line, buf[end..orig_end].clone()
	}
	return line, []u8{}
}
