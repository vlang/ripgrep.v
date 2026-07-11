module ignore

pub enum ErrorKind {
	partial
	with_line_number
	with_path
	with_depth
	loop_
	io
	glob
	unrecognized_file_type
	invalid_definition
	other
}

pub struct IgnoreError implements IClone {
pub mut:
	kind     ErrorKind = .other
	message  string
	line     u64
	path     string
	depth    int = -1
	ancestor string
	child    string
	nested   []IgnoreError
}

pub fn (err IgnoreError) clone() IgnoreError {
	mut nested := []IgnoreError{cap: err.nested.len}
	for item in err.nested {
		nested << item.clone()
	}
	return IgnoreError{
		kind:     err.kind
		message:  err.message.clone()
		line:     err.line
		path:     err.path.clone()
		depth:    err.depth
		ancestor: err.ancestor.clone()
		child:    err.child.clone()
		nested:   nested
	}
}

// V-specific: releases storage owned by this translated error value.
pub fn (mut err IgnoreError) free() {
	for mut nested in err.nested {
		nested.free()
	}
	unsafe {
		err.message.free()
		err.path.free()
		err.ancestor.free()
		err.child.free()
		err.nested.free()
	}
	err.message = ''
	err.path = ''
	err.ancestor = ''
	err.child = ''
	err.nested = []IgnoreError{}
}

pub fn io_error(err IError) IgnoreError {
	return IgnoreError{
		kind: .io
		message: err.msg().to_owned()
	}
}

pub fn other_error(msg string) IgnoreError {
	return IgnoreError{
		kind:    .other
		message: msg.to_owned()
	}
}

pub fn glob_error(glob string, msg string) IgnoreError {
	return IgnoreError{
		kind:    .glob
		message: msg.to_owned()
		path:    glob.to_owned()
	}
}

pub fn loop_error(ancestor string, child string) IgnoreError {
	return IgnoreError{
		kind:     .loop_
		message:  'symbolic link loop detected'.to_owned()
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
		kind:    .invalid_definition
		message: 'invalid definition'.to_owned()
	}
}

pub fn (err IgnoreError) with_path(path string) IgnoreError {
	mut cloned := err
	cloned.kind = .with_path
	cloned.path = path.to_owned()
	return cloned
}

pub fn (err IgnoreError) with_depth(depth int) IgnoreError {
	mut cloned := err
	cloned.kind = .with_depth
	cloned.depth = depth
	return cloned
}

pub fn (err IgnoreError) with_line_number(line u64) IgnoreError {
	mut cloned := err
	cloned.kind = .with_line_number
	cloned.line = line
	return cloned
}

pub fn ignore_error_is_partial(err IgnoreError) bool {
	match err.kind {
		.partial { return true }
		else {}
	}
	for nested in err.nested {
		if ignore_error_is_partial(nested) {
			return true
		}
	}
	return false
}

pub fn ignore_error_is_io(err IgnoreError) bool {
	match err.kind {
		.io { return true }
		.partial {
			return err.nested.len == 1 && ignore_error_is_io(err.nested[0])
		}
		else {}
	}
	return false
}

pub fn (err IgnoreError) has_depth() bool {
	return err.depth >= 0
}

pub fn ignore_error_str(err IgnoreError) string {
	mut parts := []string{}
	if err.message != '' {
		parts << err.message.clone()
	}
	if err.path != '' {
		parts << 'path=${err.path}'
	}
	if err.depth >= 0 {
		parts << 'depth=${err.depth}'
	}
	if err.ancestor != '' || err.child != '' {
		parts << 'ancestor=${err.ancestor} child=${err.child}'
	}
	if parts.len == 0 {
		return 'ignore.IgnoreError{}'
	}
	return parts.join(' ')
}

pub fn (err IgnoreError) msg() string {
	return ignore_error_str(err)
}

pub fn (err IgnoreError) code() int {
	return 1
}

pub struct PartialErrorBuilder {
mut:
	errs []IgnoreError
}

pub fn (mut builder PartialErrorBuilder) push(err IgnoreError) {
	builder.errs << err
}

pub fn (mut builder PartialErrorBuilder) maybe_push(has_err bool, err IgnoreError) {
	if has_err {
		builder.push(err)
	}
}

pub fn (mut builder PartialErrorBuilder) maybe_push_ignore_io(has_err bool, err IgnoreError) {
	if has_err && !ignore_error_is_io(err) {
		builder.push(err)
	}
}

pub fn (builder PartialErrorBuilder) into_error_option() (bool, IgnoreError) {
	if builder.errs.len == 0 {
		return false, IgnoreError{}
	}
	if builder.errs.len == 1 {
		return true, builder.errs[0]
	}
	return true, IgnoreError{
		kind:   .partial
		message: 'partial error'.to_owned()
		nested: builder.errs.clone()
	}
}
