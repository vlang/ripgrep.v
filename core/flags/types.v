module flags

import cli
import encoding.utf8
import os
import printer
import searcher
import strconv

/*!
Provides the definition of low level arguments from CLI flags.
*/

pub enum Category {
	input
	search
	filter
	output
	output_modes
	logging
	other_behaviors
}

pub fn (c Category) as_str() string {
	return match c {
		.input { 'input' }
		.search { 'search' }
		.filter { 'filter' }
		.output { 'output' }
		.output_modes { 'output-modes' }
		.logging { 'logging' }
		.other_behaviors { 'other-behaviors' }
	}
}

pub enum CompletionType {
	other
	filename
	executable
	filetype
	encoding
}

pub enum FlagValueKind {
	switch_value
	string_value
}

pub struct FlagValue {
pub:
	kind         FlagValueKind
	switch_value bool
	value        string
}

pub fn flag_switch(yes bool) FlagValue {
	return FlagValue{
		kind:         .switch_value
		switch_value: yes
	}
}

pub fn flag_value(value string) FlagValue {
	return FlagValue{
		kind:  .string_value
		value: value.to_owned()
	}
}

pub fn (v FlagValue) unwrap_switch() bool {
	if v.kind != .switch_value {
		panic('got flag value but expected switch')
	}
	return v.switch_value
}

pub fn (v FlagValue) unwrap_value() string {
	if v.kind != .string_value {
		panic('got switch but expected flag value')
	}
	return v.value
}

/// A "special" mode that supercedes everything else.
///
/// When one of these modes is present, it overrides everything else and causes
/// ripgrep to short-circuit. In particular, we avoid converting low-level
/// argument types into higher level arguments types that can fail for various
/// reasons related to the environment. (Parsing the low-level arguments can
/// fail too, but usually not in a way that can't be worked around by removing
/// the corresponding arguments from the CLI command.) This is overall a hedge
/// to ensure that version and help information are basically always available.
pub enum SpecialMode {
	/// Show a condensed version of "help" output. Generally speaking, this
	/// shows each flag and an extremely terse description of that flag on
	/// a single line. This corresponds to the `-h` flag.
	help_short
	/// Shows a very verbose version of the "help" output. The docs for some
	/// flags will be paragraphs long. This corresponds to the `--help` flag.
	help_long
	/// Show condensed version information. e.g., `ripgrep x.y.z`.
	version_short
	/// Show verbose version information. Includes "short" information as well
	/// as features included in the build.
	version_long
	/// Show PCRE2's version information, or an error if this version of
	/// ripgrep wasn't compiled with PCRE2 support.
	version_pcre2
}

/// The kind of search that ripgrep is going to perform.
pub enum SearchMode {
	/// The default standard mode of operation. ripgrep looks for matches and
	/// prints them when found.
	///
	/// There is no specific flag for this mode since it's the default. But
	/// some of the modes below, like JSON, have negation flags like --no-json
	/// that let you revert back to this default mode.
	standard
	/// Show files containing at least one match.
	files_with_matches
	/// Show files that don't contain any matches.
	files_without_match
	/// Show files containing at least one match and the number of matching
	/// lines.
	count
	/// Show files containing at least one match and the total number of
	/// matches.
	count_matches
	/// Print matches in a JSON lines format.
	json
}

/// The thing to generate via the --generate flag.
pub enum GenerateMode {
	/// Generate the raw roff used for the man page.
	man
	/// Completions for bash.
	complete_bash
	/// Completions for zsh.
	complete_zsh
	/// Completions for fish.
	complete_fish
	/// Completions for PowerShell.
	complete_powershell
}

pub enum ModeKind {
	/// ripgrep will execute a search of some kind.
	search
	/// Show the files that *would* be searched, but don't actually search
	/// them.
	files
	/// List all file type definitions configured, including the default file
	/// types and any additional file types added to the command line.
	types
	/// Generate various things like the man page and completion files.
	generate
}

/// The overall mode that ripgrep should operate in.
///
/// If ripgrep were designed without the legacy of grep, these would probably
/// be sub-commands? Perhaps not, since they aren't as frequently used.
///
/// The point of putting these in one enum is that they are all mutually
/// exclusive and override one another.
///
/// Note that -h/--help and -V/--version are not included in this because
/// they always overrides everything else, regardless of where it appears
/// in the command line. They are treated as "special" modes that short-circuit
/// ripgrep's usual flow.
///
/// V-specific: payload variants are represented by `kind` plus payload fields.
pub struct Mode implements IClone {
pub mut:
	kind     ModeKind   = .search
	search   SearchMode = .standard
	generate GenerateMode
}

pub fn mode_search(search SearchMode) Mode {
	return Mode{
		kind:   .search
		search: search
	}
}

pub fn mode_files() Mode {
	return Mode{
		kind: .files
	}
}

pub fn mode_types() Mode {
	return Mode{
		kind: .types
	}
}

pub fn mode_generate(generate GenerateMode) Mode {
	return Mode{
		kind:     .generate
		generate: generate
	}
}

/// Update this mode to the new mode while implementing various override
/// semantics. For example, a search mode cannot override a non-search
/// mode.
pub fn (mut m Mode) update(new Mode) {
	match m.kind {
		.search {
			// If we're in a search mode, then anything can override it.
			m = new
		}
		else {
			// Once we're in a non-search mode, other non-search modes
			// can override it. But search modes cannot. So for example,
			// `--files -l` will still be Mode::Files.
			if m.kind != .search {
				m = new
			}
		}
	}
}

/// Indicates how ripgrep should treat binary data.
pub enum BinaryMode {
	/// Automatically determine the binary mode to use. Essentially, when
	/// a file is searched explicitly, then it will be searched using the
	/// `SearchAndSuppress` strategy. Otherwise, it will be searched in a way
	/// that attempts to skip binary files as much as possible. That is, once
	/// a file is classified as binary, searching will immediately stop.
	auto
	/// Search files even when they have binary data, but if a match is found,
	/// suppress it and emit a warning.
	///
	/// In this mode, `NUL` bytes are replaced with line terminators. This is
	/// a heuristic meant to reduce heap memory usage, since true binary data
	/// isn't line oriented. If one attempts to treat such data as line
	/// oriented, then one may wind up with impractically large lines. For
	/// example, many binary files contain very long runs of NUL bytes.
	search_and_suppress
	/// Treat all files as if they were plain text. There's no skipping and no
	/// replacement of `NUL` bytes with line terminators.
	as_text
}

/// Indicates what kind of boundary mode to use (line or word).
pub enum BoundaryMode {
	/// Only allow matches when surrounded by line bounaries.
	line
	/// Only allow matches when surrounded by word bounaries.
	word
}

/// Indicates the buffer mode that ripgrep should use when printing output.
///
/// The default is `Auto`.
pub enum BufferMode {
	/// Select the buffer mode, 'line' or 'block', automatically based on
	/// whether stdout is connected to a tty.
	auto
	/// Flush the output buffer whenever a line terminator is seen.
	///
	/// This is useful when wants to see search results more immediately,
	/// for example, with `tail -f`.
	line
	/// Flush the output buffer whenever it reaches some fixed size. The size
	/// is usually big enough to hold many lines.
	///
	/// This is useful for maximum performance, particularly when printing
	/// lots of results.
	block
}

/// Indicates the case mode for how to interpret all patterns given to ripgrep.
///
/// The default is `Sensitive`.
pub enum CaseMode {
	/// Patterns are matched case sensitively. i.e., `a` does not match `A`.
	sensitive
	/// Patterns are matched case insensitively. i.e., `a` does match `A`.
	insensitive
	/// Patterns are automatically matched case insensitively only when they
	/// consist of all lowercase literal characters. For example, the pattern
	/// `a` will match `A` but `A` will not match `a`.
	smart
}

/// Indicates whether ripgrep should include color/hyperlinks in its output.
///
/// The default is `Auto`.
pub enum ColorChoice {
	/// Color and hyperlinks will never be used.
	never
	/// Color and hyperlinks will be used only when stdout is connected to a
	/// tty.
	auto
	/// Color will always be used.
	always
	/// Color will always be used and only ANSI escapes will be used.
	///
	/// This only makes sense in the context of legacy Windows console APIs.
	/// At time of writing, ripgrep will try to use the legacy console APIs
	/// if ANSI coloring isn't believed to be possible. This option will force
	/// ripgrep to use ANSI coloring.
	ansi
}

/// Convert this color choice to the corresponding termcolor type.
pub fn (choice &ColorChoice) to_termcolor() cli.ColorChoice {
	return match *choice {
		.never { cli.ColorChoice.never }
		.auto { cli.ColorChoice.auto }
		.always { cli.ColorChoice.always }
		.ansi { cli.ColorChoice.ansi }
	}
}

pub struct UserColorSpec {
pub:
	spec string
}

pub fn parse_user_color_spec(spec string) !UserColorSpec {
	_ = printer.parse_user_color_spec(spec)!
	return UserColorSpec{
		spec: spec.to_owned()
	}
}

/// A context mode for a finite number of lines.
///
/// Namely, this indicates that a specific number of lines (possibly zero)
/// should be shown before and/or after each matching line.
///
/// Note that there is a subtle difference between `Some(0)` and `None`. In the
/// former case, it happens when `0` is given explicitly, where as `None` is
/// the default value and occurs when no value is specified.
///
/// `both` is only set by the -C/--context flag. The reason why we don't just
/// set before = after = --context is because the before and after context
/// settings always take precedent over the -C/--context setting, regardless of
/// order. Thus, we need to keep track of them separately.
pub struct ContextModeLimited {
pub mut:
	before ?usize
	after  ?usize
	both   ?usize
}

/// Returns the specific number of contextual lines that should be shown
/// around each match. This takes proper precedent into account, i.e.,
/// that `before` and `after` both partially override `both` in all cases.
///
/// By default, this returns `(0, 0)`.
pub fn (m &ContextModeLimited) get() (usize, usize) {
	mut before := usize(0)
	mut after := usize(0)
	if lines := m.both {
		before = lines
		after = lines
	}
	// --before and --after always override --context, regardless
	// of where they appear relative to each other.
	if lines := m.before {
		before = lines
	}
	if lines := m.after {
		after = lines
	}
	return before, after
}

pub enum ContextModeKind {
	/// All lines will be printed. That is, the context is unbounded.
	passthru
	/// Only show a certain number of lines before and after each match.
	limited
}

/// Indicates the line context options ripgrep should use for output.
///
/// The default is no context at all.
///
/// V-specific: payload variants are represented by `kind` plus a payload field.
pub struct ContextMode {
pub mut:
	kind    ContextModeKind = .limited
	limited ContextModeLimited
}

pub fn default_context_mode() ContextMode {
	return ContextMode{
		kind:    .limited
		limited: ContextModeLimited{
			before: none
			after:  none
			both:   none
		}
	}
}

pub fn passthru_context_mode() ContextMode {
	return ContextMode{
		kind: .passthru
	}
}

/// Set the "before" context.
///
/// If this was set to "passthru" context, then it is overridden in favor
/// of limited context with the given value for "before" and `0` for
/// "after."
pub fn (mut m ContextMode) set_before(lines usize) {
	if m.kind == .passthru {
		m.kind = .limited
		m.limited = ContextModeLimited{
			before: lines
		}
		return
	}
	m.limited.before = lines
}

/// Set the "after" context.
///
/// If this was set to "passthru" context, then it is overridden in favor
/// of limited context with the given value for "after" and `0` for
/// "before."
pub fn (mut m ContextMode) set_after(lines usize) {
	if m.kind == .passthru {
		m.kind = .limited
		m.limited = ContextModeLimited{
			after: lines
		}
		return
	}
	m.limited.after = lines
}

/// Set the "both" context.
///
/// If this was set to "passthru" context, then it is overridden in favor
/// of limited context with the given value for "both" and `None` for
/// "before" and "after".
pub fn (mut m ContextMode) set_both(lines usize) {
	if m.kind == .passthru {
		m.kind = .limited
		m.limited = ContextModeLimited{
			both: lines
		}
		return
	}
	m.limited.both = lines
}

/// A convenience function for use in tests that returns the limited
/// context. If this mode isn't limited, then it panics.
pub fn (m &ContextMode) get_limited() (usize, usize) {
	if m.kind == .passthru {
		panic('context mode is passthru')
	}
	return m.limited.get()
}

/// Represents the separator to use between non-contiguous sections of
/// contextual lines.
///
/// The default is `--`.
pub struct ContextSeparator implements IClone {
	bytes ?[]u8
}

pub fn default_context_separator() ContextSeparator {
	return ContextSeparator{
		bytes: '--'.bytes()
	}
}

/// Creates a new separator that intructs the printer to disable contextual
/// separators entirely.
pub fn disabled_context_separator() ContextSeparator {
	return ContextSeparator{
		bytes: none
	}
}

/// Create a new context separator from the user provided argument. This
/// handles unescaping.
pub fn new_context_separator(value string) !ContextSeparator {
	if !utf8.validate_str(value) {
		return error('separator must be valid UTF-8 (use escape sequences to provide a separator that is not valid UTF-8)')
	}
	return ContextSeparator{
		bytes: unescape_bytes(value)!
	}
}

/// Return the raw bytes of this separator.
///
/// If context separators were disabled, then this returns `None`.
///
/// Note that this may return a `Some` variant with zero bytes.
pub fn (s ContextSeparator) into_bytes() ?[]u8 {
	return s.bytes
}

/// The field context separator to use to between metadata for each contextual
/// line.
///
/// The default is `-`.
pub struct FieldContextSeparator implements IClone {
	bytes []u8
}

pub fn default_field_context_separator() FieldContextSeparator {
	return FieldContextSeparator{
		bytes: '-'.bytes()
	}
}

/// Create a new separator from the given argument value provided by the
/// user. Unescaping it automatically handled.
pub fn new_field_context_separator(value string) !FieldContextSeparator {
	if !utf8.validate_str(value) {
		return error('separator must be valid UTF-8 (use escape sequences to provide a separator that is not valid UTF-8)')
	}
	return FieldContextSeparator{
		bytes: unescape_bytes(value)!
	}
}

/// Return the raw bytes of this separator.
///
/// Note that this may return an empty `Vec`.
pub fn (s FieldContextSeparator) into_bytes() []u8 {
	return s.bytes
}

/// The field match separator to use to between metadata for each matching
/// line.
///
/// The default is `:`.
pub struct FieldMatchSeparator implements IClone {
	bytes []u8
}

pub fn default_field_match_separator() FieldMatchSeparator {
	return FieldMatchSeparator{
		bytes: ':'.bytes()
	}
}

/// Create a new separator from the given argument value provided by the
/// user. Unescaping it automatically handled.
pub fn new_field_match_separator(value string) !FieldMatchSeparator {
	if !utf8.validate_str(value) {
		return error('separator must be valid UTF-8 (use escape sequences to provide a separator that is not valid UTF-8)')
	}
	return FieldMatchSeparator{
		bytes: unescape_bytes(value)!
	}
}

/// Return the raw bytes of this separator.
///
/// Note that this may return an empty `Vec`.
pub fn (s FieldMatchSeparator) into_bytes() []u8 {
	return s.bytes
}

pub struct Encoding {
pub:
	label string
}

pub fn new_encoding(label string) !Encoding {
	encoding := searcher.Encoding.new(label) or { return error('unrecognized encoding') }
	return Encoding{
		label: encoding.label.clone()
	}
}

pub enum EncodingModeKind {
	/// Use only BOM sniffing to auto-detect an encoding.
	auto
	/// Use an explicit encoding forcefully, but let BOM sniffing override it.
	some
	/// Use no explicit encoding and disable all BOM sniffing. This will
	/// always result in searching the raw bytes, regardless of their
	/// true encoding.
	disabled
}

/// The encoding mode the searcher will use.
///
/// The default is `Auto`.
///
/// V-specific: payload variants are represented by `kind` plus a payload field.
pub struct EncodingMode {
pub:
	kind     EncodingModeKind = .auto
	encoding Encoding
}

pub fn encoding_auto() EncodingMode {
	return EncodingMode{
		kind: .auto
	}
}

pub fn encoding_disabled() EncodingMode {
	return EncodingMode{
		kind: .disabled
	}
}

pub fn encoding_some(encoding Encoding) EncodingMode {
	return EncodingMode{
		kind:     .some
		encoding: encoding
	}
}

/// The regex engine to use.
///
/// The default is `Default`.
pub enum EngineChoice {
	/// Uses the default regex engine: Rust's `regex` crate.
	///
	/// (Well, technically it uses `regex-automata`, but `regex-automata` is
	/// the implementation of the `regex` crate.)
	default
	/// Dynamically select the right engine to use.
	///
	/// This works by trying to use the default engine, and if the pattern does
	/// not compile, it switches over to the PCRE2 engine if it's available.
	auto
	/// Uses the PCRE2 regex engine if it's available.
	pcre2
}

pub struct HyperlinkFormat {
pub:
	format string
}

const hyperlink_alias_choices = [
	'default',
	'none',
	'cursor',
	'file',
	'grep+',
	'kitty',
	'macvim',
	'textmate',
	'vscode',
	'vscode-insiders',
	'vscodium',
]

pub fn hyperlink_choices() []string {
	return hyperlink_alias_choices.clone()
}

pub fn parse_hyperlink_format(input string) !HyperlinkFormat {
	mut format := input.to_owned()
	match input {
		'cursor' {
			format = 'cursor://file{path}:{line}:{column}'
		}
		'default' {
			$if windows {
				format = 'file://{path}'
			} $else {
				format = 'file://{host}{path}'
			}
		}
		'file' {
			format = 'file://{host}{path}'
		}
		'grep+' {
			format = 'grep+://{path}:{line}'
		}
		'kitty' {
			format = 'file://{host}{path}#{line}'
		}
		'macvim' {
			format = 'mvim://open?url=file://{path}&line={line}&column={column}'
		}
		'none' {
			format = ''
		}
		'textmate' {
			format = 'txmt://open?url=file://{path}&line={line}&column={column}'
		}
		'vscode' {
			format = 'vscode://file{path}:{line}:{column}'
		}
		'vscode-insiders' {
			format = 'vscode-insiders://file{path}:{line}:{column}'
		}
		'vscodium' {
			format = 'vscodium://file{path}:{line}:{column}'
		}
		else {}
	}

	if format != '' {
		if !format.contains('{path}') {
			return error('invalid hyperlink format')
		}
		if format.contains('{column}') && !format.contains('{line}') {
			return error('invalid hyperlink format')
		}
	}
	return HyperlinkFormat{
		format: format
	}
}

/// The type of logging to do. `Debug` emits some details while `Trace` emits
/// much more.
pub enum LoggingMode {
	debug
	trace
}

/// Indicates when to use memory maps.
///
/// The default is `Auto`.
pub enum MmapMode {
	/// This instructs ripgrep to use heuristics for selecting when to and not
	/// to use memory maps for searching.
	auto
	/// This instructs ripgrep to always try memory maps when possible. (Memory
	/// maps are not possible to use in all circumstances, for example, for
	/// virtual files.)
	always_try_mmap
	/// Never use memory maps under any circumstances. This includes even
	/// when multi-line search is enabled where ripgrep will read the entire
	/// contents of a file on to the heap before searching it.
	never
}

pub enum PatternSourceKind {
	/// Comes from the `-e/--regexp` flag.
	regexp
	/// Comes from the `-f/--file` flag.
	file
}

/// Represents a source of patterns that ripgrep should search for.
///
/// The reason to unify these is so that we can retain the order of `-f/--flag`
/// and `-e/--regexp` flags relative to one another.
///
/// V-specific: payload variants are represented by `kind` plus a payload field.
pub struct PatternSource {
pub:
	kind  PatternSourceKind
	value string
}

/// Comes from the `-e/--regexp` flag.
pub fn pattern_regexp(value string) PatternSource {
	return PatternSource{
		kind:  .regexp
		value: value.to_owned()
	}
}

/// Comes from the `-f/--file` flag.
pub fn pattern_file(path string) PatternSource {
	return PatternSource{
		kind:  .file
		value: path.to_owned()
	}
}

/// The sort criteria, if present.
pub struct SortMode {
pub:
	/// Whether to reverse the sort criteria (i.e., descending order).
	reverse bool
	/// The actual sorting criteria.
	kind SortModeKind
}

/// The criteria to use for sorting.
pub enum SortModeKind {
	/// Sort by path.
	path
	/// Sort by last modified time.
	last_modified
	/// Sort by last accessed time.
	last_accessed
	/// Sort by creation time.
	created
}

/// Checks whether the selected sort mode is supported. If it isn't, an
/// error (hopefully explaining why) is returned.
pub fn (sort &SortMode) supported() ! {
	if sort.kind == .path {
		return
	}
	exe := os.executable()
	if sort.kind == .created {
		_ = creation_time_for_path(exe) or {
			return error("sorting by creation time isn't supported: ${err.msg()}")
		}
		return
	}
	_ = os.stat(exe) or {
		return match sort.kind {
			.path { error('unreachable path sort support check') }
			.last_modified { error("sorting by last modified isn't supported: ${err.msg()}") }
			.last_accessed { error("sorting by last accessed isn't supported: ${err.msg()}") }
			.created { error("sorting by creation time isn't supported: ${err.msg()}") }
		}
	}
}

pub enum TypeChangeKind {
	/// Clear the given type from ripgrep.
	clear
	/// Add the given type definition (name and glob) to ripgrep.
	add
	/// Select the given type for filtering.
	select
	/// Select the given type for filtering but negate it.
	negate
}

/// A single instance of either a change or a selection of one ripgrep's
/// file types.
///
/// V-specific: payload variants are represented by `kind` plus payload fields.
pub struct TypeChange {
pub:
	kind TypeChangeKind
	name string
	def  string
}

/// Clear the given type from ripgrep.
pub fn type_change_clear(name string) TypeChange {
	return TypeChange{
		kind: .clear
		name: name.to_owned()
	}
}

/// Add the given type definition (name and glob) to ripgrep.
pub fn type_change_add(def string) TypeChange {
	return TypeChange{
		kind: .add
		def:  def.to_owned()
	}
}

/// Select the given type for filtering.
pub fn type_change_select(name string) TypeChange {
	return TypeChange{
		kind: .select
		name: name.to_owned()
	}
}

/// Select the given type for filtering but negate it.
pub fn type_change_negate(name string) TypeChange {
	return TypeChange{
		kind: .negate
		name: name.to_owned()
	}
}

/// A collection of "low level" arguments.
///
/// The "low level" here is meant to constrain this type to be as close to the
/// actual CLI flags and arguments as possible. Namely, other than some
/// convenience types to help validate flag values and deal with overrides
/// between flags, these low level arguments do not contain any higher level
/// abstractions.
///
/// Another self-imposed constraint is that populating low level arguments
/// should not require anything other than validating what the user has
/// provided. For example, low level arguments should not contain a
/// `HyperlinkConfig`, since in order to get a full configuration, one needs to
/// discover the hostname of the current system (which might require running a
/// binary or a syscall).
///
/// Low level arguments are populated by the parser directly via the `update`
/// method on the corresponding implementation of the `Flag` trait.
pub struct LowArgs {
pub mut:
	// Essential arguments.
	special    ?SpecialMode
	mode       Mode
	positional []string
	patterns   []PatternSource
	// Everything else, sorted lexicographically.
	binary                       BinaryMode
	boundary                     ?BoundaryMode
	buffer                       BufferMode
	byte_offset                  bool
	case                         CaseMode
	color                        ColorChoice
	colors                       []UserColorSpec
	column                       ?bool
	context                      ContextMode
	context_separator            ContextSeparator
	crlf                         bool
	dfa_size_limit               ?usize
	encoding                     EncodingMode
	engine                       EngineChoice
	field_context_separator      FieldContextSeparator
	field_match_separator        FieldMatchSeparator
	fixed_strings                bool
	follow                       bool
	glob_case_insensitive        bool
	globs                        []string
	heading                      ?bool
	hidden                       bool
	hostname_bin                 ?string
	hyperlink_format             HyperlinkFormat
	iglobs                       []string
	ignore_file                  []string
	ignore_file_case_insensitive bool
	include_zero                 bool
	invert_match                 bool
	line_number                  ?bool
	logging                      ?LoggingMode
	max_columns                  ?u64
	max_columns_preview          bool
	max_count                    ?u64
	max_depth                    ?usize
	max_filesize                 ?u64
	mmap                         MmapMode
	multiline                    bool
	multiline_dotall             bool
	no_config                    bool
	no_ignore_dot                bool
	no_ignore_exclude            bool
	no_ignore_files              bool
	no_ignore_global             bool
	no_ignore_messages           bool
	no_ignore_parent             bool
	no_ignore_vcs                bool
	no_messages                  bool
	no_require_git               bool
	no_unicode                   bool
	null                         bool
	null_data                    bool
	one_file_system              bool
	only_matching                bool
	path_separator               ?u8
	pre                          ?string
	pre_glob                     []string
	quiet                        bool
	regex_size_limit             ?usize
	replace                      ?string
	search_zip                   bool
	sort                         ?SortMode
	stats                        bool
	stop_on_nonmatch             bool
	threads                      ?usize
	trim                         bool
	type_changes                 []TypeChange
	unrestricted                 usize
	vimgrep                      bool
	with_filename                ?bool
}

pub fn default_low_args() LowArgs {
	return LowArgs{
		special:                 none
		mode:                    mode_search(.standard)
		boundary:                none
		binary:                  .auto
		buffer:                  .auto
		case:                    .sensitive
		color:                   .auto
		column:                  none
		context:                 default_context_mode()
		context_separator:       default_context_separator()
		dfa_size_limit:          none
		encoding:                encoding_auto()
		engine:                  .default
		field_context_separator: default_field_context_separator()
		field_match_separator:   default_field_match_separator()
		heading:                 none
		hostname_bin:            none
		hyperlink_format:        parse_hyperlink_format('none') or { HyperlinkFormat{} }
		line_number:             none
		logging:                 none
		max_columns:             none
		max_count:               none
		max_depth:               none
		max_filesize:            none
		mmap:                    .auto
		path_separator:          none
		pre:                     none
		regex_size_limit:        none
		replace:                 none
		sort:                    none
		threads:                 none
		with_filename:           none
	}
}

pub fn parse_usize(value string) !usize {
	if !is_decimal_number(value) {
		return error('value is not a valid number')
	}
	parsed := strconv.atou64(value) or { return error('value is not a valid number') }
	cast := usize(parsed)
	if u64(cast) != parsed {
		return error('value is too big')
	}
	return cast
}

pub fn parse_u64(value string) !u64 {
	if !is_decimal_number(value) {
		return error('value is not a valid number')
	}
	return strconv.atou64(value) or { return error('value is not a valid number') }
}

fn is_decimal_number(value string) bool {
	if value.len == 0 {
		return false
	}
	for byte in value.bytes() {
		if byte < `0` || byte > `9` {
			return false
		}
	}
	return true
}

pub fn parse_human_readable_u64(value string) !u64 {
	if value.len == 0 {
		return error('invalid size')
	}
	mut multiplier := u64(1)
	mut digits := value
	last := value[value.len - 1]
	match last {
		`K`, `k` {
			multiplier = 1024
			digits = value[..value.len - 1]
		}
		`M`, `m` {
			multiplier = 1024 * 1024
			digits = value[..value.len - 1]
		}
		`G`, `g` {
			multiplier = 1024 * 1024 * 1024
			digits = value[..value.len - 1]
		}
		else {}
	}

	parsed := parse_u64(digits) or { return error('invalid size') }
	if multiplier != 1 && parsed > u64(-1) / multiplier {
		return error('invalid size')
	}
	return parsed * multiplier
}

pub fn parse_human_readable_usize(value string) !usize {
	parsed := parse_human_readable_u64(value)!
	cast := usize(parsed)
	if u64(cast) != parsed {
		return error('size is too big')
	}
	return cast
}

fn hex_value(ch u8) !u8 {
	return match ch {
		`0`...`9` { ch - `0` }
		`a`...`f` { ch - `a` + 10 }
		`A`...`F` { ch - `A` + 10 }
		else { return error('invalid escape sequence') }
	}
}

pub fn unescape_bytes(input string) ![]u8 {
	mut out := []u8{cap: input.len}
	mut i := 0
	for i < input.len {
		if input[i] != `\\` {
			out << input[i]
			i++
			continue
		}
		if i + 1 >= input.len {
			out << `\\`
			break
		}
		next := input[i + 1]
		match next {
			`\\` {
				out << `\\`
				i += 2
			}
			`t` {
				out << `\t`
				i += 2
			}
			`n` {
				out << `\n`
				i += 2
			}
			`r` {
				out << `\r`
				i += 2
			}
			`0` {
				out << u8(0)
				i += 2
			}
			`x` {
				if i + 3 >= input.len {
					return error('invalid escape sequence')
				}
				high := hex_value(input[i + 2])!
				low := hex_value(input[i + 3])!
				out << u8((high << 4) | low)
				i += 4
			}
			else {
				out << `\\`
				out << next
				i += 2
			}
		}
	}
	return out
}
