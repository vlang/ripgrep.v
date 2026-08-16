module pcre2

interface IClone {}

/// An error that can occur in this crate.
///
/// Generally, this error corresponds to problems building a regular
/// expression, whether it's in parsing, compilation or a problem with
/// guaranteeing a configured optimization.
pub struct Error implements IClone {
	kind ErrorKind
}

pub fn Error.regex(err IError) Error {
	return Error{
		kind: ErrorKind.regex(err.msg())
	}
}

pub fn Error.regex_message(message string) Error {
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
}

/// The kind of an error that can occur.
pub struct ErrorKind implements IClone {
	tag  ErrorKindTag
	text string
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

pub fn (kind &ErrorKind) is_regex() bool {
	return kind.tag == .regex
}

pub fn (kind &ErrorKind) text() string {
	return kind.text
}

pub fn (err &Error) msg() string {
	return match err.kind.tag {
		.regex {
			err.kind.text
		}
	}
}

pub fn (err &Error) code() int {
	_ = err
	return 0
}

pub fn (err &Error) str() string {
	return err.msg()
}
