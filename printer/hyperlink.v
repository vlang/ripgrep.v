module printer

import log
import os
import sync.arc

/// Hyperlink configuration.
///
/// This configuration specifies both the hyperlink format and an environment
/// for interpolating a subset of variables. The specific subset includes
/// variables that are intended to be invariant throughout the lifetime of a
/// process, such as a machine's hostname.
///
/// A hyperlink configuration can be provided to printer builders such as
/// `StandardBuilder.hyperlink`.
// V-specific: Rust models this as `HyperlinkConfig(Arc<HyperlinkConfigInner>)`.
// The inner value holds the environment and format; cloning the config shares
// it via the atomic refcount instead of copying it.
struct HyperlinkConfigInner implements IClone {
	env_    HyperlinkEnvironment
	format_ HyperlinkFormat
}

pub struct HyperlinkConfig implements IClone {
	inner arc.Arc[HyperlinkConfigInner]
}

/// Create a new configuration from an environment and a format.
pub fn HyperlinkConfig.new(env HyperlinkEnvironment, format HyperlinkFormat) HyperlinkConfig {
	return HyperlinkConfig{
		inner: arc.new(HyperlinkConfigInner{
			env_:    env
			format_: format
		})
	}
}

// default returns a configuration that emits no hyperlinks (an empty format).
// This mirrors Rust's `impl Default for HyperlinkConfig`, and gives every
// `HyperlinkConfig`-typed field a live Arc instead of a nil zero value.
pub fn HyperlinkConfig.default() HyperlinkConfig {
	return HyperlinkConfig.new(HyperlinkEnvironment{}, HyperlinkFormat{})
}

/// Returns the hyperlink environment in this configuration.
fn (config &^a HyperlinkConfig) environment[^a]() &^a HyperlinkEnvironment {
	return &config.inner.get().env_
}

/// Returns the hyperlink format in this configuration.
fn (config &^a HyperlinkConfig) format[^a]() &^a HyperlinkFormat {
	return &config.inner.get().format_
}

/// A hyperlink format with variables.
///
/// This can be created by parsing a string using `parse_hyperlink_format`.
///
/// The default format is empty. An empty format is valid and effectively
/// disables hyperlinks.
///
/// # Example
///
/// ```
/// import printer
///
/// fmt := printer.parse_hyperlink_format('vscode')!
/// assert fmt.str() == 'vscode://file{path}:{line}:{column}'
/// ```
pub struct HyperlinkFormat implements IClone {
	parts_             []HyperlinkPart
	is_line_dependent_ bool
}

/// Creates an empty hyperlink format.
pub fn HyperlinkFormat.empty() HyperlinkFormat {
	return HyperlinkFormat{}
}

/// Returns true if this format is empty.
pub fn (format &HyperlinkFormat) is_empty() bool {
	return format.parts_.len == 0
}

/// Creates a `HyperlinkConfig` from this format and the environment given.
pub fn (format HyperlinkFormat) into_config(env HyperlinkEnvironment) HyperlinkConfig {
	return HyperlinkConfig.new(env, format)
}

/// Returns true if the format can produce line-dependent hyperlinks.
fn (format &HyperlinkFormat) is_line_dependent() bool {
	return format.is_line_dependent_
}

pub fn (format &HyperlinkFormat) str() string {
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
		input = alias.format().clone()
	}
	mut name := ''
	mut state := HyperlinkParseState.verbatim
	for ch in input.runes() {
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
					return HyperlinkFormatError{
						kind: .invalid_close_variable
					}
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
						name += ch.str()
						HyperlinkParseState.in_variable
					}
				}
			}
			.in_variable {
				if ch == `}` {
					builder.append_var(name)!
					HyperlinkParseState.verbatim
				} else {
					name += ch.str()
					HyperlinkParseState.in_variable
				}
			}
		}
	}
	if state == .verbatim {
		return builder.build()
	}
	if state == .verbatim_close_variable {
		return HyperlinkFormatError{
			kind: .invalid_close_variable
		}
	}
	return HyperlinkFormatError{
		kind: .unclosed_variable
	}
}

/// An alias for a hyperlink format.
///
/// Hyperlink aliases are built-in formats. The Rust representation holds
/// static values; this V representation owns the same values because the
/// built-in alias list is constructed at runtime.
pub struct HyperlinkAlias implements IClone {
	name_             string
	description_      string
	format_           string
	display_priority_ ?i16
}

/// Returns the name of the alias.
pub fn (alias &^a HyperlinkAlias) name[^a]() &^a string {
	return &alias.name_
}

/// Returns a very short description of this hyperlink alias.
pub fn (alias &^a HyperlinkAlias) description[^a]() &^a string {
	return &alias.description_
}

/// Returns the display priority of this alias.
///
/// If no priority is set, then `none` is returned.
///
/// The display priority is meant to reflect some special status associated
/// with an alias. For example, the `default` and `none` aliases have a
/// display priority. This is meant to encourage listing them first in
/// documentation.
///
/// A lower display priority implies the alias should be shown before
/// aliases with a higher (or absent) display priority.
///
/// Callers cannot rely on any specific display priority value to remain
/// stable across semver compatible releases of this crate.
pub fn (alias &HyperlinkAlias) display_priority() ?i16 {
	return alias.display_priority_
}

/// Returns the format string of the alias.
fn (alias &^a HyperlinkAlias) format[^a]() &^a string {
	return &alias.format_
}

/// Looks for the hyperlink alias defined by the given name.
///
/// If one does not exist, `none` is returned.
fn HyperlinkAlias.find(name string) ?HyperlinkAlias {
	aliases := hyperlink_pattern_aliases()
	mut low := 0
	mut high := aliases.len
	for low < high {
		mid := low + (high - low) / 2
		candidate := *aliases[mid].name()
		if candidate < name {
			low = mid + 1
		} else {
			high = mid
		}
	}
	if low < aliases.len && *aliases[low].name() == name {
		return aliases[low].clone()
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

/// Create a new empty hyperlink environment.
pub fn HyperlinkEnvironment.new() HyperlinkEnvironment {
	return HyperlinkEnvironment{}
}

/// Set the `{host}` variable, which fills in any hostname components of
/// a hyperlink.
///
/// One can get the hostname in the current environment via the `hostname`
/// function in the `cli` module.
pub fn (mut env HyperlinkEnvironment) host(host ?string) &HyperlinkEnvironment {
	env.host_ = host
	return env
}

/// Set the `{wslprefix}` variable, which contains the WSL distro prefix.
/// An example value is `wsl$/Ubuntu`. The distro name can typically be
/// discovered from the `WSL_DISTRO_NAME` environment variable.
pub fn (mut env HyperlinkEnvironment) wsl_prefix(wsl_prefix ?string) &HyperlinkEnvironment {
	env.wsl_prefix_ = wsl_prefix
	return env
}

/// An error that can occur when parsing a hyperlink format.
pub struct HyperlinkFormatError implements IClone {
	// V-specific: the Rust `InvalidVariable` variant payload is stored in
	// `name` because V enums do not carry per-variant data.
	kind HyperlinkFormatErrorKind
	name string
}

enum HyperlinkFormatErrorKind {
	// This occurs when there are zero variables in the format.
	no_variables
	// This occurs when the {path} variable is missing.
	no_path_variable
	// This occurs when the {line} variable is missing, while the {column}
	// variable is present.
	no_line_variable
	// This occurs when an unknown variable is used.
	invalid_variable
	// The format doesn't start with a valid scheme.
	invalid_scheme
	// This occurs when an unescaped `}` is found without a corresponding
	// `{` preceding it.
	invalid_close_variable
	// This occurs when a `{` is found without a corresponding `}` following
	// it.
	unclosed_variable
}

// V-specific: `msg` implements the Rust `Display` representation.
pub fn (err HyperlinkFormatError) msg() string {
	return match err.kind {
		.no_variables {
			mut aliases := hyperlink_aliases()
			sort_aliases_by_display_priority(mut aliases)
			mut names := []string{cap: aliases.len}
			for alias in aliases {
				names << alias.name().clone()
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

// V-specific: `code` completes V's `IError` interface.
pub fn (err HyperlinkFormatError) code() int {
	_ = err
	return 1
}

/// A builder for `HyperlinkFormat`.
///
/// Once a `HyperlinkFormat` is built, it is immutable.
struct FormatBuilder {
mut:
	parts []HyperlinkPart
}

/// Creates a new hyperlink format builder.
fn FormatBuilder.new() FormatBuilder {
	return FormatBuilder{}
}

/// Appends static text.
fn (mut builder FormatBuilder) append_slice(text []u8) &FormatBuilder {
	if text.len == 0 {
		return builder
	}
	if builder.parts.len > 0 && builder.parts[builder.parts.len - 1].kind == .text {
		builder.parts[builder.parts.len - 1].text << text
	} else {
		builder.parts << HyperlinkPart{
			kind: .text
			text: text.clone()
		}
	}
	return builder
}

/// Appends a single character.
fn (mut builder FormatBuilder) append_char(ch rune) &FormatBuilder {
	return builder.append_slice(ch.str().bytes())
}

/// Appends a variable with the given name. If the name isn't recognized,
/// then this returns an error.
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
			return HyperlinkFormatError{
				kind: .invalid_variable
				name: name.clone()
			}
		}
	}
	builder.parts << part
}

/// Builds the format.
fn (builder &FormatBuilder) build() !HyperlinkFormat {
	builder.validate()!
	return HyperlinkFormat{
		parts_:             builder.parts.clone()
		is_line_dependent_: contains_part_kind(builder.parts, .line)
	}
}

/// Validate that the format is well-formed.
fn (builder &FormatBuilder) validate() ! {
	// An empty format is fine. It just means hyperlink support is
	// disabled.
	if builder.parts.len == 0 {
		return
	}
	// If all parts are just text, then there are no variables. It's
	// likely a reference to an invalid alias.
	if all_parts_are_text(builder.parts) {
		return HyperlinkFormatError{
			kind: .no_variables
		}
	}
	// Even if we have other variables, no path variable means the
	// hyperlink can't possibly work the way it is intended.
	if !contains_part_kind(builder.parts, .path) {
		return HyperlinkFormatError{
			kind: .no_path_variable
		}
	}
	// If the {column} variable is used, then we also need a {line}
	// variable or else {column} can't possibly work.
	if contains_part_kind(builder.parts, .column) && !contains_part_kind(builder.parts, .line) {
		return HyperlinkFormatError{
			kind: .no_line_variable
		}
	}
	builder.validate_scheme()!
}

/// Validate that the format starts with a valid scheme. Validation is done
/// according to how a scheme is defined in RFC 1738 sections 2.1[1] and
/// 5[2]. In short, a scheme is this:
///
/// scheme = 1*[ lowalpha | digit | "+" | "-" | "." ]
///
/// but is case insensitive.
///
/// [1]: https://datatracker.ietf.org/doc/html/rfc1738#section-2.1
/// [2]: https://datatracker.ietf.org/doc/html/rfc1738#section-5
fn (builder &FormatBuilder) validate_scheme() ! {
	if builder.parts.len == 0 || builder.parts[0].kind != .text {
		return HyperlinkFormatError{
			kind: .invalid_scheme
		}
	}
	part := builder.parts[0].text
	colon := index_byte(part, `:`) or {
		return HyperlinkFormatError{
			kind: .invalid_scheme
		}
	}
	scheme := part[..colon]
	if scheme.len == 0 {
		return HyperlinkFormatError{
			kind: .invalid_scheme
		}
	}
	for byte in scheme {
		if !is_valid_scheme_char(byte) {
			return HyperlinkFormatError{
				kind: .invalid_scheme
			}
		}
	}
}

enum HyperlinkPartKind {
	// Static text.
	text
	// Variable for the hostname.
	host
	// Variable for a WSL path prefix.
	wsl_prefix
	// Variable for the file path.
	path
	// Variable for the line number.
	line
	// Variable for the column number.
	column
}

/// A hyperlink format part.
///
/// A sequence of these corresponds to a complete format. (Not all sequences
/// are valid.)
struct HyperlinkPart implements IClone {
	// V-specific: the Rust tagged enum is represented by a kind plus its text
	// payload.
	//
	// We use `[]u8` here (and more generally treat a format string as a
	// sequence of bytes) because file paths may be arbitrary bytes. A rare
	// case, but one for which there is no good reason to choke on.
	kind HyperlinkPartKind
mut:
	text []u8
}

/// Interpolate this part using the given `env` and `values`, and write
/// the result of interpolation to the buffer provided.
fn (part &HyperlinkPart) interpolate_to[^a](env &HyperlinkEnvironment, values &Values[^a], mut dest []u8) {
	match part.kind {
		.text {
			dest << part.text
		}
		.host {
			if host := env.host_ {
				dest << host.bytes()
			}
		}
		.wsl_prefix {
			if prefix := env.wsl_prefix_ {
				dest << prefix.bytes()
			}
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

fn (part &HyperlinkPart) str() string {
	return match part.kind {
		.text { hyperlink_text_lossy(part.text) }
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
struct Values[^a] implements IClone {
	path   &^a HyperlinkPath
	line   ?u64
	column ?u64
}

/// Creates a new set of values, starting with the path given.
///
/// Callers may also set the line and column number using the mutator
/// methods.
fn Values.new[^a](path &^a HyperlinkPath) Values[^a] {
	return Values[^a]{
		path: path
	}
}

/// Sets the line number for these values.
///
/// If a line number is not set and a hyperlink format contains a `{line}`
/// variable, then it is interpolated with the value of `1` automatically.
fn (values Values[^a]) line[^a](line ?u64) Values[^a] {
	return Values[^a]{
		path:   values.path
		line:   line
		column: values.column
	}
}

/// Sets the column number for these values.
///
/// If a column number is not set and a hyperlink format contains a
/// `{column}` variable, then it is interpolated with the value of `1`
/// automatically.
fn (values Values[^a]) column[^a](column ?u64) Values[^a] {
	return Values[^a]{
		path:   values.path
		line:   values.line
		column: column
	}
}

/// An abstraction for interpolating a hyperlink format with values for every
/// variable.
///
/// Interpolation of variables occurs through two different sources. The
/// first is via a `HyperlinkEnvironment` for values that are expected to
/// be invariant. This comes from the `HyperlinkConfig` used to build this
/// interpolator. The second source is via `Values`, which is provided to
/// `Interpolator.begin`. The `Values` contains things like the file path,
/// line number and column number.
struct Interpolator implements IClone {
	config HyperlinkConfig
mut:
	buf []u8
}

// V-specific: explicitly releases the reusable interpolation buffer.
fn (mut interpolator Interpolator) free() {
	// Assigning an empty array auto-drops (frees) the buffer once under v3
	// ownership; a manual `.free()` first would double-free.
	interpolator.buf = []u8{}
}

/// Create a new interpolator for the given hyperlink format configuration.
fn Interpolator.new(config &HyperlinkConfig) Interpolator {
	return Interpolator{
		config: config.clone()
		buf:    []u8{}
	}
}

/// Start interpolation with the given values by writing a hyperlink
/// to `wtr`. Subsequent writes to `wtr`, until `Interpolator.finish` is
/// called, are the label for the hyperlink.
///
/// This returns an interpolator status which indicates whether the
/// hyperlink was written. It might not be written, for example, if the
/// underlying writer doesn't support hyperlinks or if the hyperlink
/// format is empty. The status should be provided to `Interpolator.finish`
/// as an instruction for whether to close the hyperlink or not.
// V-specific: this receiver is mutable because the reusable buffer is stored
// directly instead of behind Rust's `RefCell`.
fn (mut interpolator Interpolator) begin[^a, W](values &Values[^a], mut wtr W) !InterpolatorStatus {
	$if W is WriteColor {
		if interpolator.config.format().is_empty() || !wtr.supports_hyperlinks()
			|| !wtr.supports_color() {
			return InterpolatorStatus.inactive()
		}
		interpolator.buf.clear()
		for part in interpolator.config.format().parts_ {
			part.interpolate_to(interpolator.config.environment(), values, mut interpolator.buf)
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

/// Writes the correct escape sequences to `wtr` to close any extant
/// hyperlink, marking the end of a hyperlink's label.
///
/// The status given should be returned from a corresponding
/// `Interpolator.begin` call. Since `begin` may not write a hyperlink
/// (e.g., if the underlying writer doesn't support hyperlinks), it follows
/// that `finish` must not close a hyperlink that was never opened. The
/// status indicates whether the hyperlink was opened or not.
fn (interpolator &Interpolator) finish[W](status InterpolatorStatus, mut wtr W) ! {
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
///
/// This is created by `Interpolator.begin` and used by `Interpolator.finish`
/// to determine whether a hyperlink was actually opened or not. If it wasn't
/// opened, then finishing interpolation is a no-op.
struct InterpolatorStatus {
	active bool
}

/// Create an inactive interpolator status.
fn InterpolatorStatus.inactive() InterpolatorStatus {
	return InterpolatorStatus{
		active: false
	}
}

/// Represents the `{path}` part of a hyperlink.
///
/// This is the value to use as-is in the hyperlink, converted from an OS file
/// path.
@[heap]
struct HyperlinkPath implements IClone {
	// V-specific: the tuple struct payload is exposed to the rest of the
	// translated printer module as a named field.
	bytes []u8
}

/// Returns a hyperlink path from an OS path.
fn HyperlinkPath.from_path(original_path &string) ?HyperlinkPath {
	$if unix {
		// We canonicalize the path in order to get an absolute version of it
		// without any `.` or `..` or superfluous separators. Unfortunately,
		// this does also remove symlinks, and in theory, it would be nice to
		// retain them. Perhaps even simpler, we could just join the current
		// working directory with the path and be done with it. There was
		// some discussion about this on PR#2483, and there generally appears
		// to be some uncertainty about the extent to which hyperlinks with
		// things like `..` in them actually work. So for now, we do the safest
		// thing possible even though I think it can result in worse user
		// experience. (Because it means the path you click on and the actual
		// path that gets followed are different, even though they ostensibly
		// refer to the same file.)
		//
		// There's also the potential issue that path canonicalization is
		// expensive since it can touch the file system. That is probably
		// less of an issue since hyperlinks are only created when they're
		// supported, i.e., when writing to a tty.
		//
		// [1]: https://github.com/BurntSushi/ripgrep/pull/2483
		// V-specific: `os.real_path` returns its input instead of an error when
		// canonicalization fails, so check accessibility first to preserve the
		// original failure behavior for missing or inaccessible paths.
		if !os.exists(*original_path) {
			log.debug('hyperlink creation for ${*original_path} failed, error occurred during path canonicalization')
			return none
		}
		path := os.real_path(*original_path)
		// This should not be possible since one imagines that canonicalization
		// should always return an absolute path. But it doesn't actually
		// appear guaranteed by POSIX, so we check whether it's true or not and
		// refuse to create a hyperlink from a relative path if it isn't.
		if !path.starts_with('/') {
			log.debug('hyperlink creation for ${*original_path} failed, canonicalization returned ${path}, which does not start with a slash')
			return none
		}
		return HyperlinkPath.encode(path.bytes())
	} $else $if windows {
		// On Windows, we use `os.abs_path` instead of path canonicalization as
		// it can be much faster since it does not touch the file system. It
		// wraps the `GetFullPathNameW` API, except for verbatim paths (those
		// which start with `\\?\`).
		//
		// Here, we strip any verbatim path prefixes since we cannot use them
		// in hyperlinks anyway. This can only happen if the user explicitly
		// supplies a verbatim path as input, which already needs to be absolute:
		//
		//   \\?\C:\dir\file.txt           (local path)
		//   \\?\UNC\server\dir\file.txt   (network share)
		//
		// The `\\?\` prefix is constant for verbatim paths, and can be followed
		// by `UNC\` (universal naming convention), which denotes a network share.
		//
		// Given that the default URL format on Windows is file://{path}
		// we need to return the following from this function:
		//
		//   /C:/dir/file.txt        (local path)
		//   //server/dir/file.txt   (network share)
		//
		// Which produces the following links:
		//
		//   file:///C:/dir/file.txt        (local path)
		//   file:////server/dir/file.txt   (network share)
		//
		// This substitutes the {path} variable with the expected value for
		// the most common DOS paths, but on the other hand, network paths
		// start with a single slash, which may be unexpected. It seems to work
		// though?
		//
		// Note that the following URL syntax also seems to be valid?
		//
		//   file://server/dir/file.txt
		//
		// But the initial implementation of this routine went for the format
		// above.
		//
		// Also note that the file://C:/dir/file.txt syntax is not correct,
		// even though it often works in practice.
		//
		// In the end, this choice was confirmed by VSCode, whose format is
		//
		//   vscode://file{path}:{line}:{column}
		//
		// and which correctly understands the following URL format for network
		// drives:
		//
		//   vscode://file//server/dir/file.txt:1:1
		//
		// It doesn't parse any other number of slashes in "file//server" as a
		// network path.
		//
		// [1]: https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfullpathnamew
		// [2]: https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file
		// V-specific: V paths are UTF-8 strings already, and `os.abs_path`
		// returns a string instead of a result, so the Rust conversion and
		// invalid-UTF-16 error branches have no direct V equivalent.
		mut path := os.abs_path(*original_path)
		// Strip verbatim path prefixes (see the comment above for details).
		if path.starts_with(r'\\?\') {
			path = path[4..].clone()
			// Drop the UNC prefix if there is one, but keep the leading slash.
			if path.starts_with(r'UNC\') {
				path = path[3..].clone()
			}
		} else if path.starts_with(r'\\') || path.starts_with('//') {
			path = path[1..].clone()
		}
		// Finally, add a leading slash. In the local file case, this turns
		// C:\foo\bar into /C:\foo\bar (and then percent encoding turns it into
		// /C:/foo/bar). In the network share case, this turns \share\foo\bar
		// into /\share/foo/bar (and then percent encoding turns it into
		// //share/foo/bar).
		with_slash := '/' + path
		return HyperlinkPath.encode(with_slash.bytes())
	} $else {
		// For other platforms (not windows, not unix), return none and log a debug message.
		log.debug('hyperlinks are not supported on this platform')
		return none
	}
}

/// Percent-encodes a path.
///
/// The alphanumeric ASCII characters and "-", ".", "_", "~" are unreserved
/// as per section 2.3 of RFC 3986 (Uniform Resource Identifier (URI):
/// Generic Syntax), and are not encoded. The other ASCII characters except
/// "/" and ":" are percent-encoded, and "\" is replaced by "/" on Windows.
///
/// Section 4 of RFC 8089 (The "file" URI Scheme) does not mandate precise
/// encoding requirements for non-ASCII characters, and this implementation
/// leaves them unencoded. On Windows, the UrlCreateFromPathW function does
/// not encode non-ASCII characters. Doing so with UTF-8 encoded paths
/// creates invalid file:// URLs on that platform.
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
///
/// Aliases are supported by `parse_hyperlink_format`. That is, if an alias
/// is seen, then it is automatically replaced with the corresponding format.
/// For example, the `vscode` alias maps to
/// `vscode://file{path}:{line}:{column}`.
///
/// This is exposed to allow callers to include hyperlink aliases in
/// documentation in a way that is guaranteed to match what is actually
/// supported.
///
/// The list returned is guaranteed to be sorted lexicographically
/// by the alias name. Callers may want to re-sort the list using
/// `HyperlinkAlias.display_priority` via a stable sort when showing the
/// list to users. This will cause special aliases like `none` and `default`
/// to appear first.
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

// V-specific: this is the equivalent of Rust's `String::from_utf8_lossy`
// for the byte-backed text representation used by hyperlink parts.
fn hyperlink_text_lossy(text []u8) string {
	mut runes := []rune{cap: text.len}
	mut at := usize(0)
	for at < text.len {
		r, width := decode_utf8_lossy(text, at, text.len)
		runes << r
		at += width
	}
	return runes.string()
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
	return pa < pb
}
