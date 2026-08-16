module ignore

fn match_string_len(value string) int {
	return value.len
}

fn test_match_variants() {
	none_match := Match[string]{}
	assert none_match.is_none()
	assert !none_match.is_ignore()
	assert !none_match.is_whitelist()
	assert none_match.inner() == none

	ignored := Match[string]{
		kind:      .ignore
		value:     'ignore'.to_owned()
		has_value: true
	}
	assert ignored.is_ignore()
	value := ignored.inner() or { panic('missing match value') }
	assert *value == 'ignore'

	ignored_copy := ignored.clone()
	whitelisted := ignored_copy.invert()
	assert whitelisted.is_whitelist()
	assert *(whitelisted.inner() or { panic('missing inverted value') }) == 'ignore'
	inverted := whitelisted.invert()
	assert inverted.is_ignore()
}

fn test_match_map_and_or() {
	ignored := Match[string]{
		kind:      .ignore
		value:     'rust'.to_owned()
		has_value: true
	}
	mapped := ignored.map(match_string_len)
	assert mapped.is_ignore()
	assert *(mapped.inner() or { panic('missing mapped value') }) == 4

	none_match := Match[int]{}
	fallback := Match[int]{
		kind:      .whitelist
		value:     7
		has_value: true
	}
	selected := none_match.or(fallback)
	assert selected.is_whitelist()
	assert *(selected.inner() or { panic('missing fallback value') }) == 7
}

fn test_error_display() {
	assert glob_error(none, 'bad glob').str() == 'bad glob'
	assert glob_error('*.rs', 'bad glob').str() == "error parsing glob '*.rs': bad glob"
	assert unrecognized_file_type_error('wat').str() == 'unrecognized file type: wat'
	assert invalid_definition_error().str() == 'invalid definition (format is type:glob, e.g., html:*.html)'
	assert loop_error('/ancestor', '/ancestor/child').str() == 'File system loop found: /ancestor/child points to an ancestor /ancestor'

	tagged := glob_error('bad', 'parse failed').tagged('/tmp/.gitignore', 17)
	assert tagged.str() == "/tmp/.gitignore: line 17: error parsing glob 'bad': parse failed"
	assert tagged.description() == 'parse failed'
	assert glob_error(none, 'parse failed').tagged('', 3).str() == 'line 3: parse failed'
	assert glob_error(none, 'parse failed').with_depth(4).str() == 'parse failed'
}

fn test_error_classification_and_io_access() {
	wrapped := io_error(error_with_code('permission denied', 13)).with_depth(4).with_path('/tmp/x')
	assert wrapped.is_io()
	assert !wrapped.is_partial()
	assert wrapped.depth() == ?usize(4)
	borrowed := wrapped.io_error() or { panic('missing I/O error') }
	assert borrowed.kind == .io
	assert borrowed.msg() == 'permission denied'
	assert borrowed.code() == 13

	owned := wrapped.clone().into_io_error() or { panic('missing owned I/O error') }
	assert owned.kind == .io
	assert owned.msg() == 'permission denied'
	assert owned.code() == 13
	assert loop_error('/a', '/a/b').io_error() == none

	partial_io := IgnoreError{
		kind:   .partial
		nested: [io_error(error('read failed'))]
	}
	assert partial_io.is_partial()
	assert partial_io.is_io()
	two_errors := IgnoreError{
		kind:   .partial
		nested: [
			io_error(error('read failed')),
			glob_error(none, 'parse failed'),
		]
	}
	assert two_errors.is_partial()
	assert !two_errors.is_io()
	assert two_errors.str() == 'read failed\nparse failed'
}

fn test_error_depth_does_not_cross_line_numbers() {
	depth_error := glob_error(none, 'parse failed').with_depth(8)
	line_error := IgnoreError{
		kind:   .with_line_number
		line:   2
		nested: [depth_error]
	}
	assert line_error.depth() == none
}

fn test_partial_error_builder() {
	mut builder := PartialErrorBuilder{}
	builder.push_ignore_io(io_error(error('ignored I/O error')))
	builder.maybe_push(false, glob_error(none, 'not pushed'))
	builder.maybe_push_ignore_io(true, io_error(error('also ignored')))
	builder.maybe_push(true, glob_error(none, 'first'))
	builder.push(glob_error(none, 'second'))
	has_err, err := builder.into_error_option()
	assert has_err
	assert err.is_partial()
	assert err.str() == 'first\nsecond'

	empty_has_err, _ := PartialErrorBuilder{}.into_error_option()
	assert !empty_has_err
	mut single := PartialErrorBuilder{}
	single.push(glob_error(none, 'only'))
	single_has_err, single_err := single.into_error_option()
	assert single_has_err
	assert !single_err.is_partial()
	assert single_err.str() == 'only'
}
