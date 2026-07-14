module printer

import io
import strconv

pub enum ColorKind {
	black
	blue
	green
	red
	cyan
	magenta
	yellow
	white
	ansi256
	rgb
}

pub struct Color implements IClone {
pub:
	kind  ColorKind
	value u8
	red   u8
	green u8
	blue  u8
}

pub fn color_black() Color {
	return Color{
		kind: .black
	}
}

pub fn color_blue() Color {
	return Color{
		kind: .blue
	}
}

pub fn color_green() Color {
	return Color{
		kind: .green
	}
}

pub fn color_red() Color {
	return Color{
		kind: .red
	}
}

pub fn color_cyan() Color {
	return Color{
		kind: .cyan
	}
}

pub fn color_magenta() Color {
	return Color{
		kind: .magenta
	}
}

pub fn color_yellow() Color {
	return Color{
		kind: .yellow
	}
}

pub fn color_white() Color {
	return Color{
		kind: .white
	}
}

pub fn color_ansi256(value u8) Color {
	return Color{
		kind:  .ansi256
		value: value
	}
}

pub fn color_rgb(red u8, green u8, blue u8) Color {
	return Color{
		kind:  .rgb
		red:   red
		green: green
		blue:  blue
	}
}

enum ParseColorErrorKind {
	invalid_name
	invalid_ansi256
	invalid_rgb
}

/// An error from parsing an invalid color specification.
pub struct ParseColorError implements IClone {
	kind  ParseColorErrorKind
	given string
}

/// Return the string that couldn't be parsed as a valid color.
pub fn (err &^a ParseColorError) invalid[^a]() &^a string {
	return &err.given
}

pub fn (err ParseColorError) msg() string {
	return match err.kind {
		.invalid_name {
			'unrecognized color name \'${err.given}\'. Choose from: black, blue, green, red, cyan, magenta, yellow, white'
		}
		.invalid_ansi256 {
			'unrecognized ansi256 color number, should be \'[0-255]\' (or a hex number), but is \'${err.given}\''
		}
		.invalid_rgb {
			'unrecognized RGB color triple, should be \'[0-255],[0-255],[0-255]\' (or a hex triple), but is \'${err.given}\''
		}
	}
}

pub fn (err ParseColorError) code() int {
	return 1
}

fn parse_color_number(value string) ?u8 {
	if value.starts_with('0x') {
		parsed := strconv.parse_uint(value[2..], 16, 8) or { return none }
		return u8(parsed)
	}
	digits := if value.starts_with('+') { value[1..] } else { value }
	if digits.len == 0 {
		return none
	}
	parsed := strconv.parse_uint(digits, 10, 8) or { return none }
	return u8(parsed)
}

fn is_ascii_hex_digit(c rune) bool {
	return (c >= `0` && c <= `9`) || (c >= `a` && c <= `f`) || (c >= `A` && c <= `F`)
}

/// Parses a numeric color string, either ANSI or RGB.
fn parse_color_numeric(s string) !Color {
	// The "ansi256" format is a single number (decimal or hex)
	// corresponding to one of 256 colors.
	//
	// The "rgb" format is a triple of numbers (decimal or hex) delimited
	// by a comma corresponding to one of 256^3 colors.
	codes := s.split(',')
	if codes.len == 1 {
		if n := parse_color_number(codes[0]) {
			return color_ansi256(n)
		}
		mut all_hex_digits := true
		for c in s {
			if !is_ascii_hex_digit(c) {
				all_hex_digits = false
				break
			}
		}
		return ParseColorError{
			kind:  if all_hex_digits { .invalid_ansi256 } else { .invalid_name }
			given: s.to_owned()
		}
	} else if codes.len == 3 {
		mut values := []u8{cap: 3}
		for code in codes {
			value := parse_color_number(code) or {
				return ParseColorError{
					kind:  .invalid_rgb
					given: s.to_owned()
				}
			}
			values << value
		}
		return color_rgb(values[0], values[1], values[2])
	}
	return ParseColorError{
		kind:  if s.contains(',') { .invalid_rgb } else { .invalid_name }
		given: s.to_owned()
	}
}

pub fn parse_color(name string) !Color {
	lower := name.to_lower()
	return match lower {
		'black' {
			color_black()
		}
		'blue' {
			color_blue()
		}
		'green' {
			color_green()
		}
		'red' {
			color_red()
		}
		'cyan' {
			color_cyan()
		}
		'magenta' {
			color_magenta()
		}
		'yellow' {
			color_yellow()
		}
		'white' {
			color_white()
		}
		else {
			parse_color_numeric(name)!
		}
	}
}

pub struct ColorSpec implements IClone {
mut:
	fg        ?Color
	bg        ?Color
	bold      bool
	intense   bool
	underline bool
	italic    bool
}

pub fn (mut spec ColorSpec) clear() {
	spec.fg = none
	spec.bg = none
	spec.bold = false
	spec.intense = false
	spec.underline = false
	spec.italic = false
}

pub fn (mut spec ColorSpec) set_fg(color ?Color) {
	spec.fg = color
}

pub fn (mut spec ColorSpec) set_bg(color ?Color) {
	spec.bg = color
}

pub fn (mut spec ColorSpec) set_bold(value bool) {
	spec.bold = value
}

pub fn (mut spec ColorSpec) set_intense(value bool) {
	spec.intense = value
}

pub fn (mut spec ColorSpec) set_underline(value bool) {
	spec.underline = value
}

pub fn (mut spec ColorSpec) set_italic(value bool) {
	spec.italic = value
}

pub fn (spec &^a ColorSpec) fg[^a]() ?&^a Color {
	if spec.fg != none {
		return unsafe { &spec.fg? }
	}
	return none
}

pub fn (spec &^a ColorSpec) bg[^a]() ?&^a Color {
	if spec.bg != none {
		return unsafe { &spec.bg? }
	}
	return none
}

pub fn (spec &ColorSpec) bold() bool {
	return spec.bold
}

pub fn (spec &ColorSpec) intense() bool {
	return spec.intense
}

pub fn (spec &ColorSpec) underline() bool {
	return spec.underline
}

pub fn (spec &ColorSpec) italic() bool {
	return spec.italic
}

pub fn (spec &ColorSpec) is_none() bool {
	return spec.fg == none && spec.bg == none && !spec.bold && !spec.intense && !spec.underline
		&& !spec.italic
}

pub struct HyperlinkSpec implements IClone {
pub:
	kind HyperlinkSpecKind
	url  []u8
}

pub enum HyperlinkSpecKind {
	open
	close
}

pub fn HyperlinkSpec.open(url []u8) HyperlinkSpec {
	return HyperlinkSpec{
		kind: .open
		url:  url.clone()
	}
}

pub fn HyperlinkSpec.close() HyperlinkSpec {
	return HyperlinkSpec{
		kind: .close
		url:  []u8{}
	}
}

pub interface WriteColor {
mut:
	write(buf []u8) !int
	flush() !
	set_color(spec ColorSpec) !
	set_hyperlink(link HyperlinkSpec) !
	reset() !
	supports_color() bool
	supports_hyperlinks() bool
	is_synchronous() bool
}

// NoColor is a writer adapter that never emits colors or hyperlinks.
pub struct NoColor[W] {
mut:
	wtr W
}

pub fn NoColor.new[W](wtr W) NoColor[W] {
	return NoColor[W]{
		wtr: wtr
	}
}

pub fn (mut w NoColor[W]) write(buf []u8) !int {
	$if W is io.Writer {
		return w.wtr.write(buf)!
	} $else {
		return error('NoColor requires a writer implementation')
	}
}

pub fn (mut w NoColor[W]) flush() ! {
	_ = w
}

pub fn (mut w NoColor[W]) set_color(spec ColorSpec) ! {
	_ = w
	_ = spec
}

pub fn (mut w NoColor[W]) set_hyperlink(link HyperlinkSpec) ! {
	_ = w
	_ = link
}

pub fn (mut w NoColor[W]) reset() ! {
	_ = w
}

pub fn (w NoColor[W]) supports_color() bool {
	_ = w
	return false
}

pub fn (w NoColor[W]) supports_hyperlinks() bool {
	_ = w
	return false
}

pub fn (w NoColor[W]) is_synchronous() bool {
	_ = w
	return true
}

pub fn (w NoColor[W]) into_inner() W {
	return w.wtr
}

pub fn (mut w NoColor[W]) get_mut() &W {
	return &w.wtr
}
