module regex

interface IClone {}

/// An error that can occur in this crate.
///
/// Generally, this error corresponds to problems building a regular
/// expression, whether it's in parsing, compilation or a problem with
/// guaranteeing a configured optimization.
pub struct Error implements IClone {
	kind ErrorKind
}

pub fn Error.new(kind ErrorKind) Error {
	return Error{
		kind: kind
	}
}

pub fn Error.regex(message string) Error {
	return Error{
		kind: ErrorKind.regex(message)
	}
}

pub fn Error.generic(err IError) Error {
	return Error{
		kind: ErrorKind.regex(err.msg())
	}
}

pub fn Error.generic_message(message string) Error {
	return Error{
		kind: ErrorKind.regex(message)
	}
}

/// Return the kind of this error.
pub fn (err &^a Error) kind[^a]() &^a ErrorKind {
	return &err.kind
}

enum ErrorKindTag {
	regex
	not_allowed
	invalid_line_terminator
	banned
}

/// The kind of an error that can occur.
pub struct ErrorKind implements IClone {
	tag  ErrorKindTag
	text string
	byte u8
}

/// An error that occurred as a result of parsing a regular expression.
/// This can be a syntax error or an error that results from attempting to
/// compile a regular expression that is too big.
///
/// The string here is the underlying error converted to a string.
pub fn ErrorKind.regex(message string) ErrorKind {
	return ErrorKind{
		tag:  .regex
		text: message.to_owned()
	}
}

/// An error that occurs when a building a regex that isn't permitted to
/// match a line terminator. In general, building the regex will do its
/// best to make matching a line terminator impossible (e.g., by removing
/// `\n` from the `\s` character class), but if the regex contains a
/// `\n` literal, then there is no reasonable choice that can be made and
/// therefore an error is reported.
///
/// The string is the literal sequence found in the regex that is not
/// allowed.
pub fn ErrorKind.not_allowed(lit string) ErrorKind {
	return ErrorKind{
		tag:  .not_allowed
		text: lit.to_owned()
	}
}

/// This error occurs when a non-ASCII line terminator was provided.
///
/// The invalid byte is included in this error.
pub fn ErrorKind.invalid_line_terminator(byte u8) ErrorKind {
	return ErrorKind{
		tag:  .invalid_line_terminator
		byte: byte
	}
}

/// Occurs when a banned byte was found in a pattern.
pub fn ErrorKind.banned(byte u8) ErrorKind {
	return ErrorKind{
		tag:  .banned
		byte: byte
	}
}

pub fn (kind ErrorKind) is_regex() bool {
	return kind.tag == .regex
}

pub fn (kind ErrorKind) is_not_allowed() bool {
	return kind.tag == .not_allowed
}

pub fn (kind ErrorKind) is_invalid_line_terminator() bool {
	return kind.tag == .invalid_line_terminator
}

pub fn (kind ErrorKind) is_banned() bool {
	return kind.tag == .banned
}

pub fn (kind ErrorKind) text() string {
	return kind.text
}

pub fn (kind ErrorKind) byte() u8 {
	return kind.byte
}

pub fn (err Error) msg() string {
	return match err.kind.tag {
		.regex {
			err.kind.text
		}
		.not_allowed {
			'the literal ${quote_string(err.kind.text)} is not allowed in a regex'
		}
		.invalid_line_terminator {
			'line terminators must be ASCII, but ${quote_byte(err.kind.byte)} is not'
		}
		.banned {
			'pattern contains ${quote_byte(err.kind.byte)} but it is impossible to match'
		}
	}
}

pub fn (err Error) code() int {
	_ = err
	return 0
}

pub fn (err Error) str() string {
	return err.msg()
}

fn quote_string(s string) string {
	return '"${escape_debug(s.bytes())}"'
}

fn quote_byte(byte u8) string {
	return '"${escape_debug([byte])}"'
}

fn escape_debug(bytes []u8) string {
	mut out := []u8{}
	for byte in bytes {
		match byte {
			`\n` {
				out << `\\`
				out << `n`
			}
			`\r` {
				out << `\\`
				out << `r`
			}
			`\t` {
				out << `\\`
				out << `t`
			}
			`\\` {
				out << `\\`
				out << `\\`
			}
			`"` {
				out << `\\`
				out << `"`
			}
			else {
				if byte < 0x20 || byte == 0x7f || byte >= 0x80 {
					hex := '0123456789ABCDEF'
					out << `\\`
					out << `x`
					out << hex[int(byte >> 4)]
					out << hex[int(byte & 0x0f)]
				} else {
					out << byte
				}
			}
		}
	}
	return out.bytestr()
}
