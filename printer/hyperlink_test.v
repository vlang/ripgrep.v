module printer

import os

fn assert_hyperlink_parse_ok(input string) HyperlinkFormat {
	return parse_hyperlink_format(input) or { panic(err.msg()) }
}

fn assert_hyperlink_parse_error(input string, expected HyperlinkFormatError) {
	parse_hyperlink_format(input) or {
		assert err is HyperlinkFormatError
		assert err.msg() == expected.msg()
		return
	}
	assert false
}

fn test_hyperlink_build_format() {
	mut builder := FormatBuilder.new()
	builder.append_slice('foo://'.bytes())
	builder.append_slice('bar-'.bytes())
	builder.append_slice('baz'.bytes())
	builder.append_var('path')!
	format := builder.build()!

	assert format.str() == 'foo://bar-baz{path}'
	assert format.parts_[0].kind == .text
	assert format.parts_[0].text == 'foo://bar-baz'.bytes()
	assert !format.is_empty()
}

fn test_hyperlink_build_empty_format() {
	format := FormatBuilder.new().build()!

	assert format.is_empty()
	assert format.str() == HyperlinkFormat.empty().str()
}

fn test_hyperlink_handle_alias() {
	assert_hyperlink_parse_ok('file')
	assert_hyperlink_parse_ok('none')
	assert assert_hyperlink_parse_ok('none').is_empty()
}

fn test_hyperlink_parse_format() {
	format := assert_hyperlink_parse_ok('foo://{host}/bar/{path}:{line}:{column}')

	assert format.str() == 'foo://{host}/bar/{path}:{line}:{column}'
	assert format.parts_.len == 8
	assert contains_part_kind(format.parts_, .path)
	assert contains_part_kind(format.parts_, .line)
	assert contains_part_kind(format.parts_, .column)
}

fn test_hyperlink_parse_valid() {
	assert assert_hyperlink_parse_ok('').is_empty()
	assert assert_hyperlink_parse_ok('foo://{path}').str() == 'foo://{path}'
	assert assert_hyperlink_parse_ok('foo://{path}/bar').str() == 'foo://{path}/bar'

	assert_hyperlink_parse_ok('f://{path}')
	assert_hyperlink_parse_ok('f:{path}')
	assert_hyperlink_parse_ok('f-+.:{path}')
	assert_hyperlink_parse_ok('f42:{path}')
	assert_hyperlink_parse_ok('42:{path}')
	assert_hyperlink_parse_ok('+:{path}')
	assert_hyperlink_parse_ok('F42:{path}')
	assert_hyperlink_parse_ok('F42://foo{{bar}}{path}')
	assert assert_hyperlink_parse_ok('foo://café/{path}').str() == 'foo://café/{path}'
}

fn test_hyperlink_text_display_is_lossy() {
	part := HyperlinkPart{
		kind: .text
		text: [u8(0xff)]
	}
	assert part.str() == '�'
}

fn test_hyperlink_interpolate_values() {
	mut env := HyperlinkEnvironment.new()
	env.host('example.com'.to_owned())
	env.wsl_prefix('wsl$/Ubuntu'.to_owned())
	path := HyperlinkPath{
		bytes: '/tmp/example'.bytes()
	}
	values := Values.new(&path).line(42).column(7)
	format := assert_hyperlink_parse_ok('foo://{host}/{wslprefix}{path}:{line}:{column}')
	mut dest := []u8{}
	for part in format.parts_ {
		part.interpolate_to(&env, &values, mut dest)
	}
	assert dest.bytestr() == 'foo://example.com/wsl$/Ubuntu/tmp/example:42:7'
}

fn test_hyperlink_parse_invalid() {
	assert_hyperlink_parse_error('foo://bar', HyperlinkFormatError{
		kind: .no_variables
	})
	assert_hyperlink_parse_error('foo://{line}', HyperlinkFormatError{
		kind: .no_path_variable
	})
	assert_hyperlink_parse_error('foo://{path', HyperlinkFormatError{
		kind: .unclosed_variable
	})
	assert_hyperlink_parse_error('foo://{path}:{column}', HyperlinkFormatError{
		kind: .no_line_variable
	})
	assert_hyperlink_parse_error('{path}', HyperlinkFormatError{
		kind: .invalid_scheme
	})
	assert_hyperlink_parse_error(':{path}', HyperlinkFormatError{
		kind: .invalid_scheme
	})
	assert_hyperlink_parse_error('f*:{path}', HyperlinkFormatError{
		kind: .invalid_scheme
	})

	assert_hyperlink_parse_error('foo://{bar}', HyperlinkFormatError{
		kind: .invalid_variable
		name: 'bar'
	})
	assert_hyperlink_parse_error('foo://{}}bar}', HyperlinkFormatError{
		kind: .invalid_variable
		name: ''
	})
	assert_hyperlink_parse_error('foo://{b}}ar}', HyperlinkFormatError{
		kind: .invalid_variable
		name: 'b'
	})
	assert_hyperlink_parse_error('foo://{bar}}}', HyperlinkFormatError{
		kind: .invalid_variable
		name: 'bar'
	})
	assert_hyperlink_parse_error('foo://{{bar}', HyperlinkFormatError{
		kind: .invalid_close_variable
	})
	assert_hyperlink_parse_error('foo://{{{bar}', HyperlinkFormatError{
		kind: .invalid_variable
		name: 'bar'
	})
	assert_hyperlink_parse_error('foo://{b{{ar}', HyperlinkFormatError{
		kind: .invalid_variable
		name: 'b{{ar'
	})
	assert_hyperlink_parse_error('foo://{bar{{}', HyperlinkFormatError{
		kind: .invalid_variable
		name: 'bar{{'
	})
}

fn test_hyperlink_convert_to_hyperlink_path() {
	$if windows {
		convert := fn (path string) string {
			hyperpath := HyperlinkPath.from_path(&path) or { panic('missing hyperlink path') }
			return hyperpath.bytes.bytestr()
		}

		assert convert(r'C:\dir\file.txt') == '/C:/dir/file.txt'
		assert convert(r'C:\foo\bar\..\other\baz.txt') == '/C:/foo/other/baz.txt'

		assert convert(r'\\server\dir\file.txt') == '//server/dir/file.txt'
		assert convert(r'\\server\dir\foo\..\other\file.txt') == '//server/dir/other/file.txt'

		assert convert(r'\\?\C:\dir\file.txt') == '/C:/dir/file.txt'
		assert convert(r'\\?\UNC\server\dir\file.txt') == '//server/dir/file.txt'
	}
}

fn test_hyperlink_missing_path_is_not_canonicalized() {
	$if unix {
		path := os.join_path(os.temp_dir(), 'ripgrep-v-hyperlink-path-that-does-not-exist')
		if _ := HyperlinkPath.from_path(&path) {
			assert false
		}
	}
}

fn test_hyperlink_aliases_are_sorted() {
	aliases := hyperlink_aliases()
	mut prev := aliases[0].name().clone()
	for alias in aliases[1..] {
		name := alias.name().clone()
		assert name > prev, "'${prev}' should come before '${name}' in HYPERLINK_PATTERN_ALIASES"
		prev = name
	}
}

fn test_hyperlink_alias_names_are_reasonable() {
	for alias in hyperlink_aliases() {
		// There's no hard rule here, but if we want to define an alias
		// with a name that doesn't pass this assert, then we should
		// probably flag it as worthy of consideration. For example, we
		// really do not want to define an alias that contains `{` or `}`,
		// which might confuse it for a variable.
		for ch in *alias.name() {
			assert ch.is_alnum() || ch == `+` || ch == `-` || ch == `.`
		}
	}
}

fn test_hyperlink_aliases_are_valid_formats() {
	for alias in hyperlink_aliases() {
		name := alias.name().clone()
		format := alias.format().clone()
		parse_hyperlink_format(format.clone()) or {
			assert false, "invalid hyperlink alias '${name}': ${format}"
		}
	}
}
