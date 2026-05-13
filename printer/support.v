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
pub struct PrinterPath implements IClone {
	path string
mut:
	bytes     []u8
	hyperlink ?HyperlinkPath
}

/// Create a new path suitable for printing.
pub fn PrinterPath.new(path &string) PrinterPath {
	return PrinterPath{
		path:  (*path).clone()
		bytes: path.bytes()
	}
}

/// Set the separator on this path.
///
/// When set, `PrinterPath::as_bytes` will return the path provided but
/// with its separator replaced with the one given.
pub fn (pp PrinterPath) with_separator(sep ?u8) PrinterPath {
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
	return PrinterPath{
		path:  pp.path
		bytes: bytes
	}
}

/// Return the raw bytes for this path.
pub fn (pp PrinterPath) as_bytes() []u8 {
	return pp.bytes.clone()
}

/// Return this path as a hyperlink.
///
/// This port uses an optional cached hyperlink value instead of a `OnceCell`.
pub fn (mut pp PrinterPath) as_hyperlink() ?HyperlinkPath {
	if pp.hyperlink == none {
		pp.hyperlink = HyperlinkPath.from_path(pp.path) or { return none }
	}
	return pp.hyperlink
}

/// Return this path as an actual path string.
pub fn (pp PrinterPath) as_path() string {
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
