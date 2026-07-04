module cli

const hex_digits_upper = '0123456789ABCDEF'

/// Escapes arbitrary bytes into a human readable string.
///
/// This converts `\t`, `\r` and `\n` into their escaped forms. It also
/// converts the non-printable subset of ASCII in addition to invalid UTF-8
/// bytes to hexadecimal escape sequences. Everything else is left as is.
///
/// The dual of this routine is [`unescape`].
///
/// # Example
///
/// This example shows how to convert a byte string that contains a `\n` and
/// invalid UTF-8 bytes into a `String`.
///
/// Pay special attention to the use of raw strings. That is, `r"\n"` is
/// equivalent to `"\\n"`.
///
/// ```
/// use grep_cli::escape;
///
/// assert_eq!(r"foo\nbar\xFFbaz", escape(b"foo\nbar\xFFbaz"));
/// ```
pub fn escape(bytes []u8) string {
	mut escaped := []u8{cap: bytes.len}
	mut i := 0
	for i < bytes.len {
		b := bytes[i]
		match b {
			`\\` {
				escaped << `\\`
				escaped << `\\`
				i++
			}
			`\0` {
				escaped << `\\`
				escaped << `0`
				i++
			}
			`\t` {
				escaped << `\\`
				escaped << `t`
				i++
			}
			`\n` {
				escaped << `\\`
				escaped << `n`
				i++
			}
			`\r` {
				escaped << `\\`
				escaped << `r`
				i++
			}
			else {
				if is_printable_ascii(b) {
					escaped << b
					i++
					continue
				}
				seq_len := utf8_sequence_len_at(bytes, i)
				if seq_len > 0 {
					for j in 0 .. seq_len {
						escaped << bytes[i + j]
					}
					i += seq_len
					continue
				}
				append_hex_escape(mut escaped, b)
				i++
			}
		}
	}
	return escaped.bytestr()
}

/// Escapes an OS string into a human readable string.
///
/// This is like [`escape`], but accepts an OS string.
pub fn escape_os(string string) string {
	return escape(string.bytes())
}

/// Unescapes a string.
///
/// It supports a limited set of escape sequences:
///
/// * `\t`, `\r` and `\n` are mapped to their corresponding ASCII bytes.
/// * `\xZZ` hexadecimal escapes are mapped to their byte.
///
/// Everything else is left as is, including non-hexadecimal escapes like
/// `\xGG`.
///
/// This is useful when it is desirable for a command line argument to be
/// capable of specifying arbitrary bytes or otherwise make it easier to
/// specify non-printable characters.
///
/// The dual of this routine is [`escape`].
///
/// # Example
///
/// This example shows how to convert an escaped string (which is valid UTF-8)
/// into a corresponding sequence of bytes. Each escape sequence is mapped to
/// its bytes, which may include invalid UTF-8.
///
/// Pay special attention to the use of raw strings. That is, `r"\n"` is
/// equivalent to `"\\n"`.
///
/// ```
/// use grep_cli::unescape;
///
/// assert_eq!(&b"foo\nbar\xFFbaz"[..], &*unescape(r"foo\nbar\xFFbaz"));
/// ```
pub fn unescape(s string) []u8 {
	mut unescaped := []u8{cap: s.len}
	mut i := 0
	for i < s.len {
		if s[i] != `\\` {
			unescaped << s[i]
			i++
			continue
		}
		if i + 1 >= s.len {
			unescaped << `\\`
			break
		}
		next := s[i + 1]
		match next {
			`\\` {
				unescaped << `\\`
				i += 2
			}
			`0` {
				unescaped << u8(0)
				i += 2
			}
			`t` {
				unescaped << `\t`
				i += 2
			}
			`n` {
				unescaped << `\n`
				i += 2
			}
			`r` {
				unescaped << `\r`
				i += 2
			}
			`x` {
				if i + 3 < s.len {
					high, high_ok := hex_value(s[i + 2])
					low, low_ok := hex_value(s[i + 3])
					if high_ok && low_ok {
						unescaped << u8((high << 4) | low)
						i += 4
						continue
					}
				}
				unescaped << `\\`
				unescaped << `x`
				i += 2
			}
			else {
				unescaped << `\\`
				unescaped << next
				i += 2
			}
		}
	}
	return unescaped
}

/// Unescapes an OS string.
///
/// This is like [`unescape`], but accepts an OS string.
///
/// Note that this first lossily decodes the given OS string as UTF-8. That
/// is, an escaped string (the thing given) should be valid UTF-8.
pub fn unescape_os(string string) []u8 {
	return unescape(string)
}

fn is_printable_ascii(b u8) bool {
	return b >= 0x20 && b <= 0x7e
}

fn append_hex_escape(mut escaped []u8, b u8) {
	escaped << `\\`
	escaped << `x`
	escaped << hex_digits_upper[int(b >> 4)]
	escaped << hex_digits_upper[int(b & 0x0f)]
}

fn hex_value(ch u8) (u8, bool) {
	return match ch {
		`0`...`9` { ch - `0`, true }
		`a`...`f` { ch - `a` + 10, true }
		`A`...`F` { ch - `A` + 10, true }
		else { u8(0), false }
	}
}

fn is_utf8_continuation(b u8) bool {
	return b >= 0x80 && b <= 0xbf
}

fn utf8_sequence_len_at(bytes []u8, index int) int {
	b0 := bytes[index]
	remaining := bytes.len - index
	if b0 < 0x80 {
		return 1
	}
	if b0 >= 0xc2 && b0 <= 0xdf {
		if remaining >= 2 && is_utf8_continuation(bytes[index + 1]) {
			return 2
		}
		return 0
	}
	if b0 == 0xe0 {
		if remaining >= 3 && bytes[index + 1] >= 0xa0 && bytes[index + 1] <= 0xbf
			&& is_utf8_continuation(bytes[index + 2]) {
			return 3
		}
		return 0
	}
	if b0 >= 0xe1 && b0 <= 0xec {
		if remaining >= 3 && is_utf8_continuation(bytes[index + 1])
			&& is_utf8_continuation(bytes[index + 2]) {
			return 3
		}
		return 0
	}
	if b0 == 0xed {
		if remaining >= 3 && bytes[index + 1] >= 0x80 && bytes[index + 1] <= 0x9f
			&& is_utf8_continuation(bytes[index + 2]) {
			return 3
		}
		return 0
	}
	if b0 >= 0xee && b0 <= 0xef {
		if remaining >= 3 && is_utf8_continuation(bytes[index + 1])
			&& is_utf8_continuation(bytes[index + 2]) {
			return 3
		}
		return 0
	}
	if b0 == 0xf0 {
		if remaining >= 4 && bytes[index + 1] >= 0x90 && bytes[index + 1] <= 0xbf
			&& is_utf8_continuation(bytes[index + 2])
			&& is_utf8_continuation(bytes[index + 3]) {
			return 4
		}
		return 0
	}
	if b0 >= 0xf1 && b0 <= 0xf3 {
		if remaining >= 4 && is_utf8_continuation(bytes[index + 1])
			&& is_utf8_continuation(bytes[index + 2])
			&& is_utf8_continuation(bytes[index + 3]) {
			return 4
		}
		return 0
	}
	if b0 == 0xf4 {
		if remaining >= 4 && bytes[index + 1] >= 0x80 && bytes[index + 1] <= 0x8f
			&& is_utf8_continuation(bytes[index + 2])
			&& is_utf8_continuation(bytes[index + 3]) {
			return 4
		}
		return 0
	}
	return 0
}
