module printer

/// Hyperlink configuration.
///
/// This configuration specifies both the hyperlink format and an environment
/// for interpolating a subset of variables. The specific subset includes
/// variables that are intended to be invariant throughout the lifetime of a
/// process, such as a machine's hostname.
pub struct HyperlinkConfig implements IClone {
	env_    HyperlinkEnvironment
	format_ HyperlinkFormat
}

pub fn HyperlinkConfig.new(env HyperlinkEnvironment, format HyperlinkFormat) HyperlinkConfig {
	return HyperlinkConfig{
		env_:    env
		format_: format
	}
}

pub fn (config HyperlinkConfig) environment() HyperlinkEnvironment {
	return config.env_
}

pub fn (config HyperlinkConfig) format() HyperlinkFormat {
	return config.format_
}

/// A hyperlink format with variables.
///
/// This can be created by parsing a string using `parse_hyperlink_format`.
///
/// The default format is empty. An empty format is valid and effectively
/// disables hyperlinks.
pub struct HyperlinkFormat implements IClone {
	parts_             []HyperlinkPart
	is_line_dependent_ bool
}

pub fn HyperlinkFormat.empty() HyperlinkFormat {
	return HyperlinkFormat{}
}

pub fn (format HyperlinkFormat) is_empty() bool {
	return format.parts_.len == 0
}

pub fn (format HyperlinkFormat) into_config(env HyperlinkEnvironment) HyperlinkConfig {
	return HyperlinkConfig.new(env, format)
}

pub fn (format HyperlinkFormat) is_line_dependent() bool {
	return format.is_line_dependent_
}

pub fn (format HyperlinkFormat) str() string {
	mut parts := []string{cap: format.parts_.len}
	for part in format.parts_ {
		parts << part.str()
	}
	return parts.join('')
}

pub fn parse_hyperlink_format(s string) !HyperlinkFormat {
	mut builder := FormatBuilder.new()
	mut input := s.clone()
	if alias := HyperlinkAlias.find(s) {
		input = alias.format()
	}
	mut name := ''
	mut state := HyperlinkParseState.verbatim
	for ch in input.bytes() {
		state = match state {
			.verbatim {
				if ch == `{` {
					HyperlinkParseState.open_variable
				} else if ch == `}` {
					HyperlinkParseState.verbatim_close_variable
				} else {
					builder.append_char(ch)
					HyperlinkParseState.verbatim
				}
			}
			.verbatim_close_variable {
				if ch == `}` {
					builder.append_char(`}`)
					HyperlinkParseState.verbatim
				} else {
					return error(HyperlinkFormatError{
						kind: .invalid_close_variable
					}.msg())
				}
			}
			.open_variable {
				if ch == `{` {
					builder.append_char(`{`)
					HyperlinkParseState.verbatim
				} else {
					name = ''
					if ch == `}` {
						builder.append_var(name)!
						HyperlinkParseState.verbatim
					} else {
						name += ch.ascii_str()
						HyperlinkParseState.in_variable
					}
				}
			}
			.in_variable {
				if ch == `}` {
					builder.append_var(name)!
					HyperlinkParseState.verbatim
				} else {
					name += ch.ascii_str()
					HyperlinkParseState.in_variable
				}
			}
		}
	}
	if state == .verbatim {
		return builder.build()
	}
	if state == .verbatim_close_variable {
		return error(HyperlinkFormatError{
			kind: .invalid_close_variable
		}.msg())
	}
	return error(HyperlinkFormatError{
		kind: .unclosed_variable
	}.msg())
}

/// An alias for a hyperlink format.
///
/// Hyperlink aliases are built-in formats, therefore they hold static values.
pub struct HyperlinkAlias implements IClone {
	name_             string
	description_      string
	format_           string
	display_priority_ ?i16
}

pub fn (alias HyperlinkAlias) name() string {
	return alias.name_
}

pub fn (alias HyperlinkAlias) description() string {
	return alias.description_
}

pub fn (alias HyperlinkAlias) display_priority() ?i16 {
	return alias.display_priority_
}

pub fn (alias HyperlinkAlias) format() string {
	return alias.format_
}

fn HyperlinkAlias.find(name string) ?HyperlinkAlias {
	for alias in hyperlink_pattern_aliases() {
		if alias.name() == name {
			return alias
		}
	}
	return none
}

/// A static environment for hyperlink interpolation.
///
/// This environment permits setting the values of variables used in hyperlink
/// interpolation that are not expected to change for the lifetime of a program.
/// That is, these values are invariant.
///
/// Currently, this includes the hostname and a WSL distro prefix.
pub struct HyperlinkEnvironment implements IClone {
mut:
	host_       ?string
	wsl_prefix_ ?string
}

pub fn HyperlinkEnvironment.new() HyperlinkEnvironment {
	return HyperlinkEnvironment{}
}

/// Set the `{host}` variable, which fills in any hostname components of
/// a hyperlink.
pub fn (mut env HyperlinkEnvironment) host(host ?string) &HyperlinkEnvironment {
	if value := host {
		env.host_ = value.clone()
	} else {
		env.host_ = none
	}
	return env
}

/// Set the `{wslprefix}` variable, which contains the WSL distro prefix.
/// An example value is `wsl$/Ubuntu`. The distro name can typically be
/// discovered from the `WSL_DISTRO_NAME` environment variable.
pub fn (mut env HyperlinkEnvironment) wsl_prefix(wsl_prefix ?string) &HyperlinkEnvironment {
	if value := wsl_prefix {
		env.wsl_prefix_ = value.clone()
	} else {
		env.wsl_prefix_ = none
	}
	return env
}

fn (env HyperlinkEnvironment) host_value() string {
	if value := env.host_ {
		return value
	}
	return ''
}

fn (env HyperlinkEnvironment) wsl_prefix_value() string {
	if value := env.wsl_prefix_ {
		return value
	}
	return ''
}

/// An error that can occur when parsing a hyperlink format.
pub struct HyperlinkFormatError implements IClone {
pub:
	kind HyperlinkFormatErrorKind
	name string
}

pub enum HyperlinkFormatErrorKind {
	no_variables
	no_path_variable
	no_line_variable
	invalid_variable
	invalid_scheme
	invalid_close_variable
	unclosed_variable
}

pub fn (err HyperlinkFormatError) msg() string {
	return match err.kind {
		.no_variables {
			mut aliases := hyperlink_aliases()
			sort_aliases_by_display_priority(mut aliases)
			mut names := []string{cap: aliases.len}
			for alias in aliases {
				names << alias.name()
			}
			'at least a {path} variable is required in a hyperlink format, or otherwise use a valid alias: ${names.join(', ')}'
		}
		.no_path_variable {
			'the {path} variable is required in a hyperlink format'
		}
		.no_line_variable {
			'the hyperlink format contains a {column} variable, but no {line} variable is present'
		}
		.invalid_variable {
			'invalid hyperlink format variable: \'${err.name}\', choose from: path, line, column, host, wslprefix'
		}
		.invalid_scheme {
			'the hyperlink format must start with a valid URL scheme, i.e., [0-9A-Za-z+-.]+:'
		}
		.invalid_close_variable {
			"unopened variable: found '}' without a corresponding '{' preceding it"
		}
		.unclosed_variable {
			"unclosed variable: found '{' without a corresponding '}' following it"
		}
	}
}

pub fn (err HyperlinkFormatError) code() int {
	_ = err
	return 1
}

struct FormatBuilder {
mut:
	parts []HyperlinkPart
}

fn FormatBuilder.new() FormatBuilder {
	return FormatBuilder{}
}

fn (mut builder FormatBuilder) append_slice(text []u8) &FormatBuilder {
	if text.len == 0 {
		return builder
	}
	if builder.parts.len > 0 && builder.parts[builder.parts.len - 1].kind == .text {
		mut last := builder.parts[builder.parts.len - 1]
		last.text << text
		builder.parts[builder.parts.len - 1] = last
	} else {
		builder.parts << HyperlinkPart{
			kind: .text
			text: text.clone()
		}
	}
	return builder
}

fn (mut builder FormatBuilder) append_char(ch u8) &FormatBuilder {
	return builder.append_slice([ch])
}

fn (mut builder FormatBuilder) append_var(name string) ! {
	part := match name {
		'host' {
			HyperlinkPart{
				kind: .host
			}
		}
		'wslprefix' {
			HyperlinkPart{
				kind: .wsl_prefix
			}
		}
		'path' {
			HyperlinkPart{
				kind: .path
			}
		}
		'line' {
			HyperlinkPart{
				kind: .line
			}
		}
		'column' {
			HyperlinkPart{
				kind: .column
			}
		}
		else {
			return error(HyperlinkFormatError{
				kind: .invalid_variable
				name: name.clone()
			}.msg())
		}
	}
	builder.parts << part
}

fn (builder FormatBuilder) build() !HyperlinkFormat {
	builder.validate()!
	return HyperlinkFormat{
		parts_:             builder.parts.clone()
		is_line_dependent_: contains_part_kind(builder.parts, .line)
	}
}

fn (builder FormatBuilder) validate() ! {
	if builder.parts.len == 0 {
		return
	}
	if all_parts_are_text(builder.parts) {
		return error(HyperlinkFormatError{
			kind: .no_variables
		}.msg())
	}
	if !contains_part_kind(builder.parts, .path) {
		return error(HyperlinkFormatError{
			kind: .no_path_variable
		}.msg())
	}
	if contains_part_kind(builder.parts, .column) && !contains_part_kind(builder.parts, .line) {
		return error(HyperlinkFormatError{
			kind: .no_line_variable
		}.msg())
	}
	builder.validate_scheme()!
}

fn (builder FormatBuilder) validate_scheme() ! {
	if builder.parts.len == 0 || builder.parts[0].kind != .text {
		return error(HyperlinkFormatError{
			kind: .invalid_scheme
		}.msg())
	}
	part := builder.parts[0].text
	colon := index_byte(part, `:`) or {
		return error(HyperlinkFormatError{
			kind: .invalid_scheme
		}.msg())
	}
	scheme := part[..colon]
	if scheme.len == 0 {
		return error(HyperlinkFormatError{
			kind: .invalid_scheme
		}.msg())
	}
	for byte in scheme {
		if !is_valid_scheme_char(byte) {
			return error(HyperlinkFormatError{
				kind: .invalid_scheme
			}.msg())
		}
	}
}

enum HyperlinkPartKind {
	text
	host
	wsl_prefix
	path
	line
	column
}

struct HyperlinkPart implements IClone {
	kind HyperlinkPartKind
mut:
	text []u8
}

fn (values Values[^a]) interpolate_to[^a](part HyperlinkPart, env HyperlinkEnvironment, mut dest []u8) {
	match part.kind {
		.text {
			dest << part.text
		}
		.host {
			dest << env.host_value().bytes()
		}
		.wsl_prefix {
			dest << env.wsl_prefix_value().bytes()
		}
		.path {
			dest << values.path.bytes
		}
		.line {
			formatted_line := DecimalFormatter.new(values.line or { 1 })
			dest << formatted_line.as_bytes()
		}
		.column {
			formatted_column := DecimalFormatter.new(values.column or { 1 })
			dest << formatted_column.as_bytes()
		}
	}
}

fn (part HyperlinkPart) str() string {
	return match part.kind {
		.text { part.text.bytestr() }
		.host { '{host}' }
		.wsl_prefix { '{wslprefix}' }
		.path { '{path}' }
		.line { '{line}' }
		.column { '{column}' }
	}
}

/// The values to replace the format variables with.
///
/// This only consists of values that depend on each path or match printed.
/// Values that are invariant throughout the lifetime of the process are set
/// via a `HyperlinkEnvironment`.
pub struct Values[^a] implements IClone {
	path   &^a HyperlinkPath
	line   ?u64
	column ?u64
}

pub fn Values.new[^a](path &^a HyperlinkPath) Values[^a] {
	return Values[^a]{
		path: path
	}
}

pub fn (values Values[^a]) line[^a](line ?u64) Values[^a] {
	return Values[^a]{
		path:   values.path
		line:   line
		column: values.column
	}
}

pub fn (values Values[^a]) column[^a](column ?u64) Values[^a] {
	return Values[^a]{
		path:   values.path
		line:   values.line
		column: column
	}
}

/// An abstraction for interpolating a hyperlink format with values for every
/// variable.
pub struct Interpolator implements IClone {
	config HyperlinkConfig
mut:
	buf []u8
}

fn (mut interpolator Interpolator) free() {
	unsafe { interpolator.buf.free() }
	interpolator.buf = []u8{}
}

pub fn Interpolator.new(config HyperlinkConfig) Interpolator {
	return Interpolator{
		config: config
		buf:    []u8{}
	}
}

pub fn (mut interpolator Interpolator) begin[^a, W](values Values[^a], mut wtr W) !InterpolatorStatus {
	$if W is WriteColor {
		if interpolator.config.format().is_empty() || !wtr.supports_hyperlinks()
			|| !wtr.supports_color() {
			return InterpolatorStatus.inactive()
		}
		interpolator.buf.clear()
		for part in interpolator.config.format().parts_ {
			values.interpolate_to(part, interpolator.config.environment(), mut interpolator.buf)
		}
		wtr.set_hyperlink(HyperlinkSpec.open(interpolator.buf))!
		return InterpolatorStatus{
			active: true
		}
	} $else {
		_ = values
		return InterpolatorStatus.inactive()
	}
}

pub fn (interpolator Interpolator) finish[W](status InterpolatorStatus, mut wtr W) ! {
	$if W is WriteColor {
		_ = interpolator
		if !status.active {
			return
		}
		wtr.set_hyperlink(HyperlinkSpec.close())!
	} $else {
		_ = interpolator
		_ = status
		_ = wtr
	}
}

/// A status indicating whether a hyperlink was written or not.
pub struct InterpolatorStatus {
	active bool
}

pub fn InterpolatorStatus.inactive() InterpolatorStatus {
	return InterpolatorStatus{
		active: false
	}
}

/// Represents the `{path}` part of a hyperlink.
///
/// This is the value to use as-is in the hyperlink, converted from an OS file
/// path.
pub struct HyperlinkPath implements IClone {
pub:
	bytes []u8
}

pub fn HyperlinkPath.from_path(original_path string) ?HyperlinkPath {
	normalized := normalize_hyperlink_path(original_path) or { return none }
	return HyperlinkPath.encode(normalized.bytes())
}

fn HyperlinkPath.encode(input []u8) HyperlinkPath {
	mut result := []u8{cap: input.len}
	for byte in input {
		if (byte >= `0` && byte <= `9`) || (byte >= `A` && byte <= `Z`)
			|| (byte >= `a` && byte <= `z`) || byte == `/` || byte == `:`
			|| byte == `-` || byte == `.` || byte == `_` || byte == `~`
			|| byte >= 128 {
			result << byte
			continue
		}
		$if windows {
			if byte == `\\` {
				result << `/`
				continue
			}
		}
		result << `%`
		result << hex_upper(byte >> 4)
		result << hex_upper(byte & 0x0f)
	}
	return HyperlinkPath{
		bytes: result
	}
}

/// Returns the set of hyperlink aliases supported by this crate.
pub fn hyperlink_aliases() []HyperlinkAlias {
	return hyperlink_pattern_aliases()
}

enum HyperlinkParseState {
	verbatim
	verbatim_close_variable
	open_variable
	in_variable
}

fn all_parts_are_text(parts []HyperlinkPart) bool {
	for part in parts {
		if part.kind != .text {
			return false
		}
	}
	return true
}

fn contains_part_kind(parts []HyperlinkPart, kind HyperlinkPartKind) bool {
	for part in parts {
		if part.kind == kind {
			return true
		}
	}
	return false
}

fn is_valid_scheme_char(byte u8) bool {
	return (byte >= `0` && byte <= `9`) || (byte >= `A` && byte <= `Z`)
		|| (byte >= `a` && byte <= `z`) || byte == `+` || byte == `-` || byte == `.`
}

fn index_byte(haystack []u8, needle u8) ?int {
	for i, byte in haystack {
		if byte == needle {
			return i
		}
	}
	return none
}

fn hex_upper(value u8) u8 {
	return if value < 10 { `0` + value } else { `A` + (value - 10) }
}

fn sort_aliases_by_display_priority(mut aliases []HyperlinkAlias) {
	for i in 1 .. aliases.len {
		mut j := i
		for j > 0 && alias_less(aliases[j], aliases[j - 1]) {
			aliases[j], aliases[j - 1] = aliases[j - 1], aliases[j]
			j--
		}
	}
}

fn alias_less(a HyperlinkAlias, b HyperlinkAlias) bool {
	pa := a.display_priority() or { i16(32767) }
	pb := b.display_priority() or { i16(32767) }
	if pa != pb {
		return pa < pb
	}
	return a.name() < b.name()
}
