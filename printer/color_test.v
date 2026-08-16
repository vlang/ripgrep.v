module printer

fn parse_color_spec_ok(input string) UserColorSpec {
	return parse_user_color_spec(input) or { panic(err.msg()) }
}

fn assert_color_parse_error(input string, kind ColorErrorKind, message string) {
	parse_user_color_spec(input) or {
		assert err is ColorError
		color_err := err as ColorError
		assert color_err.kind == kind
		assert color_err.msg() == message
		return
	}
	assert false, 'expected color parse error for ${input}'
}

fn test_default_color_specs() {
	specs := ColorSpecs.default_with_color()
	path_color := specs.path().fg() or { panic('missing path color') }
	$if windows {
		assert *path_color == color_cyan()
	} $else {
		assert *path_color == color_magenta()
	}
	line_color := specs.line().fg() or { panic('missing line color') }
	assert *line_color == color_green()
	match_color := specs.matched().fg() or { panic('missing match color') }
	assert *match_color == color_red()
	assert specs.matched().bold()
	assert specs.column().is_none()
	assert specs.highlight().is_none()
}

fn test_color_specs_merge_in_order() {
	user_specs := [
		parse_color_spec_ok('path:fg:blue'),
		parse_color_spec_ok('path:bg:red'),
		parse_color_spec_ok('path:style:bold'),
		parse_color_spec_ok('path:none:anything'),
		parse_color_spec_ok('path:style:italic'),
		parse_color_spec_ok('line:fg:green'),
		parse_color_spec_ok('column:fg:yellow'),
		parse_color_spec_ok('match:fg:cyan'),
		parse_color_spec_ok('highlight:fg:magenta'),
	]
	specs := ColorSpecs.new(&user_specs)

	assert specs.path().fg() == none
	assert specs.path().bg() == none
	assert !specs.path().bold()
	assert specs.path().italic()
	line_color := specs.line().fg() or { panic('missing line color') }
	assert *line_color == color_green()
	column_color := specs.column().fg() or { panic('missing column color') }
	assert *column_color == color_yellow()
	match_color := specs.matched().fg() or { panic('missing match color') }
	assert *match_color == color_cyan()
	highlight_color := specs.highlight().fg() or { panic('missing highlight color') }
	assert *highlight_color == color_magenta()

	cloned := specs.clone()
	assert cloned.path().italic()
	cloned_match_color := cloned.matched().fg() or { panic('missing cloned match color') }
	assert *cloned_match_color == color_cyan()
}

fn test_user_color_spec_is_case_insensitive() {
	fg := parse_color_spec_ok('PaTh:Fg:BlUe').to_color_spec()
	fg_color := fg.fg() or { panic('missing foreground color') }
	assert *fg_color == color_blue()
	style := parse_color_spec_ok('MaTcH:StYlE:UnDeRlInE').to_color_spec()
	assert style.underline()
}

fn test_user_color_spec_numeric_colors() {
	ansi_decimal := parse_color_spec_ok('match:fg:255').to_color_spec()
	ansi_decimal_color := ansi_decimal.fg() or { panic('missing ANSI color') }
	assert *ansi_decimal_color == color_ansi256(255)
	ansi_hex := parse_color_spec_ok('match:fg:0xff').to_color_spec()
	ansi_hex_color := ansi_hex.fg() or { panic('missing hexadecimal ANSI color') }
	assert *ansi_hex_color == color_ansi256(255)
	ansi_plus := parse_color_spec_ok('match:fg:+1').to_color_spec()
	ansi_plus_color := ansi_plus.fg() or { panic('missing signed ANSI color') }
	assert *ansi_plus_color == color_ansi256(1)
	rgb := parse_color_spec_ok('match:bg:0xff,0x7f,0').to_color_spec()
	rgb_color := rgb.bg() or { panic('missing RGB color') }
	assert *rgb_color == color_rgb(255, 127, 0)
	rgb_plus := parse_color_spec_ok('match:bg:+1,2,3').to_color_spec()
	rgb_plus_color := rgb_plus.bg() or { panic('missing signed RGB color') }
	assert *rgb_plus_color == color_rgb(1, 2, 3)
}

fn test_user_color_spec_styles() {
	assert parse_color_spec_ok('match:style:bold').to_color_spec().bold()
	assert !parse_color_spec_ok('match:style:nobold').to_color_spec().bold()
	assert parse_color_spec_ok('match:style:intense').to_color_spec().intense()
	assert !parse_color_spec_ok('match:style:nointense').to_color_spec().intense()
	assert parse_color_spec_ok('match:style:underline').to_color_spec().underline()
	assert !parse_color_spec_ok('match:style:nounderline').to_color_spec().underline()
	assert parse_color_spec_ok('match:style:italic').to_color_spec().italic()
	assert !parse_color_spec_ok('match:style:noitalic').to_color_spec().italic()
}

fn test_user_color_spec_format_errors() {
	assert_color_parse_error('path', .invalid_format,
		"invalid color spec format: 'path'. Valid format is '(path|line|column|match|highlight):(fg|bg|style):(value)'.")
	assert_color_parse_error('path:fg:red:extra', .invalid_format,
		"invalid color spec format: 'path:fg:red:extra'. Valid format is '(path|line|column|match|highlight):(fg|bg|style):(value)'.")
	assert_color_parse_error('path:fg', .invalid_format,
		"invalid color spec format: 'path:fg'. Valid format is '(path|line|column|match|highlight):(fg|bg|style):(value)'.")
	assert_color_parse_error('path:style', .invalid_format,
		"invalid color spec format: 'path:style'. Valid format is '(path|line|column|match|highlight):(fg|bg|style):(value)'.")
}

fn test_user_color_spec_name_errors() {
	assert_color_parse_error('wat:fg:red', .unrecognized_out_type,
		"unrecognized output type 'wat'. Choose from: path, line, column, match, highlight.")
	assert_color_parse_error('path:wat:red', .unrecognized_spec_type,
		"unrecognized spec type 'wat'. Choose from: fg, bg, style, none.")
	assert_color_parse_error('path:style:wat', .unrecognized_style,
		"unrecognized style attribute 'wat'. Choose from: nobold, bold, nointense, intense, nounderline, underline, noitalic, italic.")
	assert_color_parse_error('path:fg:wat', .unrecognized_color,
		"unrecognized color name 'wat'. Choose from: black, blue, green, red, cyan, magenta, yellow, white")
}

fn test_user_color_spec_numeric_color_errors() {
	assert_color_parse_error('path:fg:256', .unrecognized_color,
		"unrecognized ansi256 color number, should be '[0-255]' (or a hex number), but is '256'")
	assert_color_parse_error('path:fg:fff', .unrecognized_color,
		"unrecognized ansi256 color number, should be '[0-255]' (or a hex number), but is 'fff'")
	assert_color_parse_error('path:fg:', .unrecognized_color,
		"unrecognized ansi256 color number, should be '[0-255]' (or a hex number), but is ''")
	assert_color_parse_error('path:fg:0Xff', .unrecognized_color,
		"unrecognized color name '0Xff'. Choose from: black, blue, green, red, cyan, magenta, yellow, white")
	assert_color_parse_error('path:fg:1,2', .unrecognized_color,
		"unrecognized RGB color triple, should be '[0-255],[0-255],[0-255]' (or a hex triple), but is '1,2'")
	assert_color_parse_error('path:fg:256,0,0', .unrecognized_color,
		"unrecognized RGB color triple, should be '[0-255],[0-255],[0-255]' (or a hex triple), but is '256,0,0'")
}
