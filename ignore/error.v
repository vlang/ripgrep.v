module ignore

pub enum ErrorKind {
	/// A collection of "soft" errors. These occur when adding an ignore
	/// file partially succeeded.
	partial
	/// An error associated with a specific line number.
	with_line_number
	/// An error associated with a particular file path.
	with_path
	/// An error associated with a particular directory depth when recursively
	/// walking a directory.
	with_depth
	/// An error that occurs when a file loop is detected when traversing
	/// symbolic links.
	loop_
	/// An error that occurs when doing I/O, such as reading an ignore file.
	io
	/// An error that occurs when trying to parse a glob.
	glob
	/// A type selection for a file type that is not defined.
	unrecognized_file_type
	/// A user specified file type definition could not be parsed.
	invalid_definition
	// V-specific: callers use the zero value as a no-error result slot, and
	// translated platform helpers can attach errors outside Rust's variants.
	other
}

/// Represents an error that can occur when parsing a gitignore file.
//
// V-specific: Rust represents this as an enum. V enum payloads are represented
// explicitly here with a tag and fields for each variant.
pub struct IgnoreError implements IClone {
pub mut:
	// V-specific: identifies which Rust enum variant the shared payload fields
	// represent.
	kind       ErrorKind = .other
	// V-specific: stores the I/O, glob, unrecognized-type or platform error
	// message for the active variant.
	message    string
	/// The line number.
	line       u64
	/// The file path.
	path       string
	/// The directory depth.
	depth_value ?usize
	/// The original glob that caused this error. This glob, when
	/// available, always corresponds to the glob provided by an end user.
	/// e.g., It is the glob as written in a `.gitignore` file.
	///
	/// (This glob may be distinct from the glob that is actually
	/// compiled, after accounting for `gitignore` semantics.)
	glob       ?string
	// V-specific: preserves the code exposed by the original IError.
	error_code int
	/// The ancestor file path in the loop.
	ancestor   string
	/// The child file path in the loop.
	child      string
	// V-specific: stores the collection or boxed underlying error payloads.
	nested     []IgnoreError
}

pub fn (err IgnoreError) clone() IgnoreError {
	mut nested := []IgnoreError{cap: err.nested.len}
	for item in err.nested {
		nested << item.clone()
	}
	mut cloned := IgnoreError{
		kind:       err.kind
		message:    err.message.clone()
		line:       err.line
		path:       err.path.clone()
		depth_value: err.depth_value
		error_code: err.error_code
		ancestor:   err.ancestor.clone()
		child:      err.child.clone()
		nested:     nested
	}
	if glob := err.glob {
		cloned.glob = glob.clone()
	}
	return cloned
}

// V-specific: releases storage owned by this translated error value.
pub fn (mut err IgnoreError) free() {
	// Assigning defaults makes v3 ownership auto-drop (free) each owned field
	// exactly once (recursively for `nested`). Manually calling `.free()` first
	// would double-free, because the assignment already drops the old value.
	err.message = ''
	err.path = ''
	err.glob = none
	err.ancestor = ''
	err.child = ''
	err.nested = []IgnoreError{}
}

// V-specific: V's IError surface is normalized into the I/O variant while
// preserving the original message and error code.
pub fn io_error(err IError) IgnoreError {
	return IgnoreError{
		kind:       .io
		message:    err.msg().to_owned()
		error_code: err.code()
	}
}

// V-specific: represents an error produced by a translated platform helper.
pub fn other_error(msg string) IgnoreError {
	return IgnoreError{
		kind:    .other
		message: msg.to_owned()
	}
}

pub fn glob_error(glob ?string, msg string) IgnoreError {
	mut err := IgnoreError{
		kind:    .glob
		message: msg.to_owned()
	}
	if value := glob {
		err.glob = value.to_owned()
	}
	return err
}

pub fn loop_error(ancestor string, child string) IgnoreError {
	return IgnoreError{
		kind:     .loop_
		ancestor: ancestor.to_owned()
		child:    child.to_owned()
	}
}

pub fn unrecognized_file_type_error(name string) IgnoreError {
	return IgnoreError{
		kind:    .unrecognized_file_type
		message: name.to_owned()
	}
}

pub fn invalid_definition_error() IgnoreError {
	return IgnoreError{
		kind: .invalid_definition
	}
}

/// Turn an error into a tagged error with the given file path.
fn (err IgnoreError) with_path(path string) IgnoreError {
	return IgnoreError{
		kind:   .with_path
		path:   path.to_owned()
		nested: [err]
	}
}

/// Turn an error into a tagged error with the given depth.
fn (err IgnoreError) with_depth(depth usize) IgnoreError {
	return IgnoreError{
		kind:   .with_depth
		depth_value: depth
		nested: [err]
	}
}

/// Turn an error into a tagged error with the given file path and line
/// number. If path is empty, then it is omitted from the error.
fn (err IgnoreError) tagged(path string, lineno u64) IgnoreError {
	errline := IgnoreError{
		kind:   .with_line_number
		line:   lineno
		nested: [err]
	}
	if path == '' {
		return errline
	}
	return errline.with_path(path)
}

/// Returns true if this is a partial error.
///
/// A partial error occurs when only some operations failed while others
/// may have succeeded. For example, an ignore file may contain an invalid
/// glob among otherwise valid globs.
pub fn (err &IgnoreError) is_partial() bool {
	match err.kind {
		.partial {
			return true
		}
		.with_line_number, .with_path, .with_depth {
			return err.nested.len == 1 && err.nested[0].is_partial()
		}
		else {
			return false
		}
	}
}

/// Returns true if this error is exclusively an I/O error.
pub fn (err &IgnoreError) is_io() bool {
	match err.kind {
		.partial, .with_line_number, .with_path, .with_depth {
			return err.nested.len == 1 && err.nested[0].is_io()
		}
		.io {
			return true
		}
		else {
			return false
		}
	}
}

/// Inspect the original I/O error if there is one.
///
/// `none` is returned if the `IgnoreError` doesn't correspond to an I/O
/// error. This might happen, for example, when the error was produced because
/// a cycle was found in the directory tree while following symbolic links.
///
/// This method returns a borrowed value that is bound to the lifetime of the
/// `IgnoreError`. To obtain an owned value, `into_io_error` can be used instead.
//
// V-specific: the direct `.io` IgnoreError is the normalized owned form of
// the original IError.
pub fn (err &^a IgnoreError) io_error[^a]() ?&^a IgnoreError {
	match err.kind {
		.partial, .with_line_number, .with_path, .with_depth {
			if err.nested.len == 1 {
				return err.nested[0].io_error()
			}
		}
		.io {
			return err
		}
		else {}
	}
	return none
}

/// Similar to `io_error` except consumes self to convert to the original I/O
/// error if one exists.
//
// V-specific: the returned direct `.io` IgnoreError is the normalized owned
// form of the original IError.
pub fn (err IgnoreError) into_io_error() ?IgnoreError {
	match err.kind {
		.partial, .with_line_number, .with_path, .with_depth {
			if err.nested.len == 1 {
				mut nested := err.nested.clone()
				return nested.pop().into_io_error()
			}
		}
		.io {
			return err
		}
		else {}
	}
	return none
}

/// Returns a depth associated with recursively walking a directory (if
/// this error was generated from a recursive directory iterator).
pub fn (err &IgnoreError) depth() ?usize {
	match err.kind {
		.with_path {
			if err.nested.len == 1 {
				return err.nested[0].depth()
			}
		}
		.with_depth {
			return err.depth_value
		}
		else {}
	}
	return none
}

fn (err &IgnoreError) description() string {
	match err.kind {
		.partial {
			return 'partial error'
		}
		.with_line_number, .with_path, .with_depth {
			if err.nested.len == 1 {
				return err.nested[0].description()
			}
			return ''
		}
		.loop_ {
			return 'file system loop found'
		}
		.io, .glob, .other {
			return err.message.clone()
		}
		.unrecognized_file_type {
			return 'unrecognized file type'
		}
		.invalid_definition {
			return 'invalid definition'
		}
	}
}

pub fn (err &IgnoreError) str() string {
	match err.kind {
		.partial {
			mut msgs := []string{cap: err.nested.len}
			for nested in err.nested {
				msgs << nested.str()
			}
			return msgs.join('\n')
		}
		.with_line_number {
			if err.nested.len == 1 {
				return 'line ${err.line}: ${err.nested[0].str()}'
			}
		}
		.with_path {
			if err.nested.len == 1 {
				return '${err.path}: ${err.nested[0].str()}'
			}
		}
		.with_depth {
			if err.nested.len == 1 {
				return err.nested[0].str()
			}
		}
		.loop_ {
			return 'File system loop found: ${err.child} points to an ancestor ${err.ancestor}'
		}
		.io, .other {
			return err.message.clone()
		}
		.glob {
			if glob := err.glob {
				return "error parsing glob '${glob}': ${err.message}"
			}
			return err.message.clone()
		}
		.unrecognized_file_type {
			return 'unrecognized file type: ${err.message}'
		}
		.invalid_definition {
			return 'invalid definition (format is type:glob, e.g., html:*.html)'
		}
	}
	return ''
}

// V-specific: formats the translated Display implementation at call sites
// that need a standalone helper.
pub fn ignore_error_str(err &IgnoreError) string {
	return err.str()
}

// V-specific: exposes the translated error through V's IError interface.
pub fn (err &IgnoreError) msg() string {
	return err.str()
}

// V-specific: exposes the translated error through V's IError interface.
pub fn (err &IgnoreError) code() int {
	if err.kind == .io {
		return err.error_code
	}
	return 1
}

pub struct PartialErrorBuilder {
mut:
	errs []IgnoreError
}

fn (mut builder PartialErrorBuilder) push(err IgnoreError) {
	builder.errs << err
}

fn (mut builder PartialErrorBuilder) push_ignore_io(err IgnoreError) {
	if !err.is_io() {
		builder.push(err)
	}
}

// V-specific: V tuple results expose the optional error as a presence flag
// plus a value slot.
fn (mut builder PartialErrorBuilder) maybe_push(has_err bool, err IgnoreError) {
	if has_err {
		builder.push(err)
	}
}

// V-specific: V tuple results expose the optional error as a presence flag
// plus a value slot.
fn (mut builder PartialErrorBuilder) maybe_push_ignore_io(has_err bool, err IgnoreError) {
	if has_err {
		builder.push_ignore_io(err)
	}
}

fn (builder PartialErrorBuilder) into_error_option() (bool, IgnoreError) {
	if builder.errs.len == 0 {
		return false, IgnoreError{}
	}
	mut errs := builder.errs.clone()
	if errs.len == 1 {
		return true, errs.pop()
	}
	return true, IgnoreError{
		kind:   .partial
		nested: errs
	}
}
