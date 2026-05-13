module printer

/// Returns a default set of color specifications.
///
/// This may change over time, but the color choices are meant to be fairly
/// conservative that work across terminal themes.
///
/// Additional color specifications can be added to the list returned. More
/// recently added specifications override previously added specifications.
pub fn default_color_specs() []UserColorSpec {
	return [
		$if windows {
			parse_user_color_spec('path:fg:cyan') or { panic(err) }
		} $else {
			parse_user_color_spec('path:fg:magenta') or { panic(err) }
		},
		parse_user_color_spec('line:fg:green') or { panic(err) },
		parse_user_color_spec('match:fg:red') or { panic(err) },
		parse_user_color_spec('match:style:bold') or { panic(err) },
	]
}

/// An error that can occur when parsing color specifications.
pub enum ColorErrorKind {
	unrecognized_out_type
	unrecognized_spec_type
	unrecognized_color
	unrecognized_style
	invalid_format
}

pub struct ColorError {
pub:
	kind     ColorErrorKind
	name     string
	details  string
	original string
}

pub fn (err ColorError) msg() string {
	return match err.kind {
		.unrecognized_out_type {
			'unrecognized output type \'${err.name}\'. Choose from: path, line, column, match, highlight.'
		}
		.unrecognized_spec_type {
			'unrecognized spec type \'${err.name}\'. Choose from: fg, bg, style, none.'
		}
		.unrecognized_color {
			err.details
		}
		.unrecognized_style {
			'unrecognized style attribute \'${err.name}\'. Choose from: nobold, bold, nointense, intense, nounderline, underline, noitalic, italic.'
		}
		.invalid_format {
			'invalid color spec format: \'${err.original}\'. Valid format is \'(path|line|column|match|highlight):(fg|bg|style):(value)\'.'
		}
	}
}

pub fn (err ColorError) code() int {
	_ = err
	return 1
}

fn color_error_from_parse_error(err ParseColorError) ColorError {
	return ColorError{
		kind:    .unrecognized_color
		name:    err.invalid()
		details: err.msg()
	}
}

/// A merged set of color specifications.
///
/// This set of color specifications represents the various color types that
/// are supported by the printers in this crate. A set of color specifications
/// can be created from a sequence of
/// `UserColorSpec`s.
pub struct ColorSpecs implements IClone {
mut:
	path_spec      ColorSpec
	line_spec      ColorSpec
	column_spec    ColorSpec
	matched_spec   ColorSpec
	highlight_spec ColorSpec
}

/// A single color specification provided by the user.
///
/// ## Format
///
/// The format of a `Spec` is a triple: `{type}:{attribute}:{value}`. Each
/// component is defined as follows:
///
/// * `{type}` can be one of `path`, `line`, `column`, `match` or `highlight`.
/// * `{attribute}` can be one of `fg`, `bg` or `style`. `{attribute}` may also
///   be the special value `none`, in which case, `{value}` can be omitted.
/// * `{value}` is either a color name (for `fg`/`bg`) or a style instruction.
///
/// `{type}` controls which part of the output should be styled.
///
/// When `{attribute}` is `none`, then this should cause any existing style
/// settings to be cleared for the specified `type`.
///
/// `{value}` should be a color when `{attribute}` is `fg` or `bg`, or it
/// should be a style instruction when `{attribute}` is `style`. When
/// `{attribute}` is `none`, `{value}` must be omitted.
///
/// Valid colors are `black`, `blue`, `green`, `red`, `cyan`, `magenta`,
/// `yellow`, `white`. Extended colors can also be specified, and are formatted
/// as `x` (for 256-bit colors) or `x,x,x` (for 24-bit true color), where
/// `x` is a number between 0 and 255 inclusive. `x` may be given as a normal
/// decimal number of a hexadecimal number, where the latter is prefixed by
/// `0x`.
///
/// Valid style instructions are `nobold`, `bold`, `intense`, `nointense`,
/// `underline`, `nounderline`, `italic`, `noitalic`.
pub struct UserColorSpec implements IClone {
	ty    OutType
	value SpecValue
}

enum SpecValueKind {
	none_
	fg
	bg
	style
}

struct SpecValue implements IClone {
	kind  SpecValueKind
	color Color
	style Style
}

enum OutType {
	path
	line
	column
	match_
	highlight
}

enum SpecType {
	fg
	bg
	style
	none_
}

enum Style {
	bold
	no_bold
	intense
	no_intense
	underline
	no_underline
	italic
	no_italic
}

/// Convert this user provided color specification to a specification that
/// can be used with `termcolor`. This drops the type of this specification
/// (where the type indicates where the color is applied in the standard
/// printer, e.g., to the file path or the line numbers, etc.).
pub fn (spec UserColorSpec) to_color_spec() ColorSpec {
	mut color_spec := ColorSpec{}
	spec.value.merge_into(mut color_spec)
	return color_spec
}

/// Create color specifications from a list of user supplied
/// specifications.
pub fn ColorSpecs.new(specs []UserColorSpec) ColorSpecs {
	mut merged := ColorSpecs{}
	for spec in specs {
		match spec.ty {
			.path { spec.merge_into(mut merged.path_spec) }
			.line { spec.merge_into(mut merged.line_spec) }
			.column { spec.merge_into(mut merged.column_spec) }
			.match_ { spec.merge_into(mut merged.matched_spec) }
			.highlight { spec.merge_into(mut merged.highlight_spec) }
		}
	}
	return merged
}

/// Create a default set of specifications that have color.
///
/// This is distinct from `ColorSpecs`'s `Default` implementation in that
/// this provides a set of default color choices, where as the `Default`
/// implementation provides no color choices.
pub fn ColorSpecs.default_with_color() ColorSpecs {
	return ColorSpecs.new(default_color_specs())
}

/// Return the color specification for coloring file paths.
pub fn (specs ColorSpecs) path() ColorSpec {
	return specs.path_spec
}

/// Return the color specification for coloring line numbers.
pub fn (specs ColorSpecs) line() ColorSpec {
	return specs.line_spec
}

/// Return the color specification for coloring column numbers.
pub fn (specs ColorSpecs) column() ColorSpec {
	return specs.column_spec
}

/// Return the color specification for coloring matched text.
pub fn (specs ColorSpecs) matched() ColorSpec {
	return specs.matched_spec
}

/// Return the color specification for coloring entire line if there is a
/// matched text.
pub fn (specs ColorSpecs) highlight() ColorSpec {
	return specs.highlight_spec
}

/// Merge this spec into the given color specification.
fn (spec UserColorSpec) merge_into(mut cspec ColorSpec) {
	spec.value.merge_into(mut cspec)
}

/// Merge this spec value into the given color specification.
fn (value SpecValue) merge_into(mut cspec ColorSpec) {
	match value.kind {
		.none_ {
			cspec.clear()
		}
		.fg {
			cspec.set_fg(value.color)
		}
		.bg {
			cspec.set_bg(value.color)
		}
		.style {
			match value.style {
				.bold { cspec.set_bold(true) }
				.no_bold { cspec.set_bold(false) }
				.intense { cspec.set_intense(true) }
				.no_intense { cspec.set_intense(false) }
				.underline { cspec.set_underline(true) }
				.no_underline { cspec.set_underline(false) }
				.italic { cspec.set_italic(true) }
				.no_italic { cspec.set_italic(false) }
			}
		}
	}
}

pub fn parse_user_color_spec(s string) !UserColorSpec {
	pieces := s.split(':')
	if pieces.len <= 1 || pieces.len > 3 {
		return ColorError{
			kind:     .invalid_format
			original: s.clone()
		}
	}
	otype := parse_out_type(pieces[0])!
	match parse_spec_type(pieces[1])! {
		.none_ {
			return UserColorSpec{
				ty:    otype
				value: SpecValue{
					kind: .none_
				}
			}
		}
		.style {
			if pieces.len < 3 {
				return ColorError{
					kind:     .invalid_format
					original: s.clone()
				}
			}
			style := parse_style(pieces[2])!
			return UserColorSpec{
				ty:    otype
				value: SpecValue{
					kind:  .style
					style: style
				}
			}
		}
		.fg {
			if pieces.len < 3 {
				return ColorError{
					kind:     .invalid_format
					original: s.clone()
				}
			}
			color := parse_color(pieces[2]) or {
				return ColorError{
					kind:    .unrecognized_color
					name:    pieces[2].clone()
					details: err.msg()
				}
			}
			return UserColorSpec{
				ty:    otype
				value: SpecValue{
					kind:  .fg
					color: color
				}
			}
		}
		.bg {
			if pieces.len < 3 {
				return ColorError{
					kind:     .invalid_format
					original: s.clone()
				}
			}
			color := parse_color(pieces[2]) or {
				return ColorError{
					kind:    .unrecognized_color
					name:    pieces[2].clone()
					details: err.msg()
				}
			}
			return UserColorSpec{
				ty:    otype
				value: SpecValue{
					kind:  .bg
					color: color
				}
			}
		}
	}
}

fn parse_out_type(s string) !OutType {
	return match s.to_lower() {
		'path' {
			.path
		}
		'line' {
			.line
		}
		'column' {
			.column
		}
		'match' {
			.match_
		}
		'highlight' {
			.highlight
		}
		else {
			return ColorError{
				kind: .unrecognized_out_type
				name: s.clone()
			}
		}
	}
}

fn parse_spec_type(s string) !SpecType {
	return match s.to_lower() {
		'fg' {
			.fg
		}
		'bg' {
			.bg
		}
		'style' {
			.style
		}
		'none' {
			.none_
		}
		else {
			return ColorError{
				kind: .unrecognized_spec_type
				name: s.clone()
			}
		}
	}
}

fn parse_style(s string) !Style {
	return match s.to_lower() {
		'bold' {
			.bold
		}
		'nobold' {
			.no_bold
		}
		'intense' {
			.intense
		}
		'nointense' {
			.no_intense
		}
		'underline' {
			.underline
		}
		'nounderline' {
			.no_underline
		}
		'italic' {
			.italic
		}
		'noitalic' {
			.no_italic
		}
		else {
			return ColorError{
				kind: .unrecognized_style
				name: s.clone()
			}
		}
	}
}
