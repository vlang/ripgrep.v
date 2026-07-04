module cli

import io
import os

fn is_reader_eof(err IError) bool {
	return err is io.Eof || err is os.Eof
}

/// An error that occurs when a pattern could not be converted to valid UTF-8.
///
/// The purpose of this error is to give a more targeted failure mode for
/// patterns written by end users that are not valid UTF-8.
pub struct InvalidPatternError implements IClone {
	original    string
	valid_up_to usize
}

/// Returns the index in the given string up to which valid UTF-8 was
/// verified.
pub fn (err InvalidPatternError) valid_up_to() usize {
	return err.valid_up_to
}

pub fn (err InvalidPatternError) msg() string {
	return 'found invalid UTF-8 in pattern at byte offset ${err.valid_up_to}: ${err.original} (disable Unicode mode and use hex escape sequences to match arbitrary bytes in a pattern, e.g., \'(?-u)\\xFF\')'
}

pub fn (err InvalidPatternError) code() int {
	return 0
}

pub fn (err InvalidPatternError) str() string {
	return err.msg()
}

/// Convert an OS string into a regular expression pattern.
///
/// This conversion fails if the given pattern is not valid UTF-8, in which
/// case, a targeted error with more information about where the invalid UTF-8
/// occurs is given. The error also suggests the use of hex escape sequences,
/// which are supported by many regex engines.
pub fn pattern_from_os(pattern string) !string {
	return pattern_from_bytes(pattern.bytes()) or {
		return InvalidPatternError{
			original:    escape_os(pattern)
			valid_up_to: (err as InvalidPatternError).valid_up_to()
		}
	}
}

/// Convert arbitrary bytes into a regular expression pattern.
///
/// This conversion fails if the given pattern is not valid UTF-8, in which
/// case, a targeted error with more information about where the invalid UTF-8
/// occurs is given. The error also suggests the use of hex escape sequences,
/// which are supported by many regex engines.
///
/// V-specific: Rust returns a borrowed `&str` view into the input bytes. V
/// cannot express that string view lifetime over `[]u8`, so this returns an
/// owned string after validating the bytes.
pub fn pattern_from_bytes(pattern []u8) !string {
	valid_up_to, valid := utf8_valid_up_to(pattern)
	if !valid {
		return InvalidPatternError{
			original:    escape(pattern)
			valid_up_to: valid_up_to
		}
	}
	return pattern.bytestr()
}

/// Read patterns from a file path, one per line.
///
/// If there was a problem reading or if any of the patterns contain invalid
/// UTF-8, then an error is returned. If there was a problem with a specific
/// pattern, then the error message will include the line number and the file
/// path.
pub fn patterns_from_path(path string) ![]string {
	mut file := os.open(path) or { return error('${path}: ${err.msg()}') }
	defer {
		file.close()
	}
	return patterns_from_reader(mut file) or { return error('${path}:${err.msg()}') }
}

/// Read patterns from stdin, one per line.
///
/// If there was a problem reading or if any of the patterns contain invalid
/// UTF-8, then an error is returned. If there was a problem with a specific
/// pattern, then the error message will include the line number and the fact
/// that it came from stdin.
pub fn patterns_from_stdin() ![]string {
	bytes := os.get_raw_stdin()
	return patterns_from_reader_bytes(bytes) or { return error('<stdin>:${err.msg()}') }
}

/// Read patterns from any reader, one per line.
///
/// If there was a problem reading or if any of the patterns contain invalid
/// UTF-8, then an error is returned. If there was a problem with a specific
/// pattern, then the error message will include the line number.
///
/// Note that this routine uses its own internal buffer, so the caller should
/// not provide their own buffered reader if possible.
///
/// # Example
///
/// This shows how to parse patterns, one per line.
///
/// ```
/// use grep_cli::patterns_from_reader;
///
/// let patterns = "\
/// foo
/// bar\\s+foo
/// [a-z]{3}
/// ";
///
/// assert_eq!(patterns_from_reader(patterns.as_bytes())?, vec![
///     r"foo",
///     r"bar\s+foo",
///     r"[a-z]{3}",
/// ]);
/// # Ok::<(), Box<dyn std::error::Error>>(())
/// ```
pub fn patterns_from_reader(mut rdr io.Reader) ![]string {
	mut bytes := []u8{}
	mut buf := []u8{len: 32 * 1024}
	for {
		nread := rdr.read(mut buf) or {
			if is_reader_eof(err) {
				break
			}
			return err
		}
		if nread == 0 {
			break
		}
		bytes << buf[..nread]
	}
	return patterns_from_reader_bytes(bytes)
}

fn patterns_from_reader_bytes(bytes []u8) ![]string {
	mut patterns := []string{}
	mut line_number := 0
	mut start := 0
	for i, b in bytes {
		if b != `\n` {
			continue
		}
		mut end := i
		if end > start && bytes[end - 1] == `\r` {
			end--
		}
		line_number++
		push_pattern_line(mut patterns, bytes[start..end], line_number)!
		start = i + 1
	}
	if start < bytes.len {
		line_number++
		push_pattern_line(mut patterns, bytes[start..], line_number)!
	}
	return patterns
}

fn push_pattern_line(mut patterns []string, line []u8, line_number int) ! {
	pattern := pattern_from_bytes(line) or {
		return error('${line_number}: ${err.msg()}')
	}
	patterns << pattern.to_owned()
}

fn utf8_valid_up_to(bytes []u8) (usize, bool) {
	mut i := 0
	for i < bytes.len {
		b0 := bytes[i]
		if b0 < 0x80 {
			i++
			continue
		}
		if b0 >= 0xc2 && b0 <= 0xdf {
			if i + 1 >= bytes.len || !is_utf8_continuation(bytes[i + 1]) {
				return usize(i), false
			}
			i += 2
			continue
		}
		if b0 == 0xe0 {
			if i + 2 >= bytes.len || bytes[i + 1] < 0xa0 || bytes[i + 1] > 0xbf
				|| !is_utf8_continuation(bytes[i + 2]) {
				return usize(i), false
			}
			i += 3
			continue
		}
		if b0 >= 0xe1 && b0 <= 0xec {
			if i + 2 >= bytes.len || !is_utf8_continuation(bytes[i + 1])
				|| !is_utf8_continuation(bytes[i + 2]) {
				return usize(i), false
			}
			i += 3
			continue
		}
		if b0 == 0xed {
			if i + 2 >= bytes.len || bytes[i + 1] < 0x80 || bytes[i + 1] > 0x9f
				|| !is_utf8_continuation(bytes[i + 2]) {
				return usize(i), false
			}
			i += 3
			continue
		}
		if b0 >= 0xee && b0 <= 0xef {
			if i + 2 >= bytes.len || !is_utf8_continuation(bytes[i + 1])
				|| !is_utf8_continuation(bytes[i + 2]) {
				return usize(i), false
			}
			i += 3
			continue
		}
		if b0 == 0xf0 {
			if i + 3 >= bytes.len || bytes[i + 1] < 0x90 || bytes[i + 1] > 0xbf
				|| !is_utf8_continuation(bytes[i + 2]) || !is_utf8_continuation(bytes[i + 3]) {
				return usize(i), false
			}
			i += 4
			continue
		}
		if b0 >= 0xf1 && b0 <= 0xf3 {
			if i + 3 >= bytes.len || !is_utf8_continuation(bytes[i + 1])
				|| !is_utf8_continuation(bytes[i + 2])
				|| !is_utf8_continuation(bytes[i + 3]) {
				return usize(i), false
			}
			i += 4
			continue
		}
		if b0 == 0xf4 {
			if i + 3 >= bytes.len || bytes[i + 1] < 0x80 || bytes[i + 1] > 0x8f
				|| !is_utf8_continuation(bytes[i + 2]) || !is_utf8_continuation(bytes[i + 3]) {
				return usize(i), false
			}
			i += 4
			continue
		}
		return usize(i), false
	}
	return usize(i), true
}
