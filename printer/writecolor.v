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

pub struct ParseColorError {
	invalid_value string
	message       string
}

pub fn (err ParseColorError) invalid() string {
	return err.invalid_value
}

pub fn (err ParseColorError) msg() string {
	return err.message
}

pub fn (err ParseColorError) code() int {
	return 1
}

fn parse_u8_component(value string) !u8 {
	if value.starts_with('0x') || value.starts_with('0X') {
		parsed := strconv.parse_uint(value[2..], 16, 8)!
		return u8(parsed)
	}
	parsed := strconv.parse_uint(value, 10, 8)!
	return u8(parsed)
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
			if lower.contains(',') {
				pieces := lower.split(',')
				if pieces.len != 3 {
					return ParseColorError{
						invalid_value: name.clone()
						message:       'invalid color ${name}'.clone()
					}
				}
				return color_rgb(parse_u8_component(pieces[0])!, parse_u8_component(pieces[1])!,
					parse_u8_component(pieces[2])!)
			}
			return color_ansi256(parse_u8_component(lower)!)
		}
	}
}

pub struct ColorSpec implements IClone {
mut:
	fg        ?Color
	bg        ?Color
	bold      ?bool
	intense   ?bool
	underline ?bool
	italic    ?bool
}

pub fn (mut spec ColorSpec) clear() {
	spec.fg = none
	spec.bg = none
	spec.bold = none
	spec.intense = none
	spec.underline = none
	spec.italic = none
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

pub fn (spec ColorSpec) fg() ?Color {
	if value := spec.fg {
		return value
	}
	return none
}

pub fn (spec ColorSpec) bg() ?Color {
	if value := spec.bg {
		return value
	}
	return none
}

pub fn (spec ColorSpec) bold() ?bool {
	return spec.bold
}

pub fn (spec ColorSpec) intense() ?bool {
	return spec.intense
}

pub fn (spec ColorSpec) underline() ?bool {
	return spec.underline
}

pub fn (spec ColorSpec) italic() ?bool {
	return spec.italic
}

pub fn (spec ColorSpec) is_none() bool {
	return spec.fg == none && spec.bg == none && spec.bold == none && spec.intense == none
		&& spec.underline == none && spec.italic == none
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
