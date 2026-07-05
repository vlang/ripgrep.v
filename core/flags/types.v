module flags

import encoding.utf8
import os
import printer
import strconv

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

pub enum SpecialMode {
	help_short
	help_long
	version_short
	version_long
	version_pcre2
}

pub enum SearchMode {
	standard
	files_with_matches
	files_without_match
	count
	count_matches
	json
}

pub enum GenerateMode {
	man
	complete_bash
	complete_zsh
	complete_fish
	complete_powershell
}

pub enum ModeKind {
	search
	files
	types
	generate
}

pub struct Mode {
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

pub fn (mut m Mode) update(new Mode) {
	m = new
}

pub enum BinaryMode {
	auto
	search_and_suppress
	as_text
}

pub enum BoundaryMode {
	line
	word
}

pub enum BufferMode {
	auto
	line
	block
}

pub enum CaseMode {
	sensitive
	insensitive
	smart
}

pub enum ColorChoice {
	never
	auto
	always
	ansi
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

pub struct ContextModeLimited {
pub mut:
	before ?usize
	after  ?usize
	both   ?usize
}

pub fn (m ContextModeLimited) get() (usize, usize) {
	mut before := usize(0)
	mut after := usize(0)
	if lines := m.both {
		before = lines
		after = lines
	}
	if lines := m.before {
		before = lines
	}
	if lines := m.after {
		after = lines
	}
	return before, after
}

pub enum ContextModeKind {
	passthru
	limited
}

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

pub fn (m ContextMode) get_limited() (usize, usize) {
	if m.kind == .passthru {
		panic('context mode is passthru')
	}
	return m.limited.get()
}

pub struct ContextSeparator {
pub:
	enabled bool
	bytes   []u8
}

pub fn default_context_separator() ContextSeparator {
	return ContextSeparator{
		enabled: true
		bytes:   '--'.bytes().clone()
	}
}

pub fn disabled_context_separator() ContextSeparator {
	return ContextSeparator{
		enabled: false
		bytes:   []u8{}
	}
}

pub fn new_context_separator(value string) !ContextSeparator {
	if !utf8.validate_str(value) {
		return error('separator must be valid UTF-8 (use escape sequences to provide a separator that is not valid UTF-8)')
	}
	return ContextSeparator{
		enabled: true
		bytes:   unescape_bytes(value)!
	}
}

pub fn (s ContextSeparator) into_bytes() ?[]u8 {
	if !s.enabled {
		return none
	}
	return s.bytes.clone()
}

pub struct FieldContextSeparator {
pub:
	bytes []u8
}

pub fn default_field_context_separator() FieldContextSeparator {
	return FieldContextSeparator{
		bytes: '-'.bytes().clone()
	}
}

pub fn new_field_context_separator(value string) !FieldContextSeparator {
	if !utf8.validate_str(value) {
		return error('separator must be valid UTF-8 (use escape sequences to provide a separator that is not valid UTF-8)')
	}
	return FieldContextSeparator{
		bytes: unescape_bytes(value)!
	}
}

pub fn (s FieldContextSeparator) into_bytes() []u8 {
	return s.bytes.clone()
}

pub struct FieldMatchSeparator {
pub:
	bytes []u8
}

pub fn default_field_match_separator() FieldMatchSeparator {
	return FieldMatchSeparator{
		bytes: ':'.bytes().clone()
	}
}

pub fn new_field_match_separator(value string) !FieldMatchSeparator {
	if !utf8.validate_str(value) {
		return error('separator must be valid UTF-8 (use escape sequences to provide a separator that is not valid UTF-8)')
	}
	return FieldMatchSeparator{
		bytes: unescape_bytes(value)!
	}
}

pub fn (s FieldMatchSeparator) into_bytes() []u8 {
	return s.bytes.clone()
}

pub struct Encoding {
pub:
	label string
}

pub fn new_encoding(label string) !Encoding {
	normalized := label.to_lower()
	if canonical := canonical_encoding_label(normalized) {
		return Encoding{
			label: canonical
		}
	}
	return error('unrecognized encoding')
}

fn canonical_encoding_label(label string) ?string {
	match label {
		'unicode-1-1-utf-8', 'unicode11utf8', 'unicode20utf8', 'utf-8', 'utf8', 'x-unicode20utf8' {
			return 'utf-8'
		}
		'utf-16', 'utf-16le', 'utf16le' {
			return 'utf-16le'
		}
		'utf-16be', 'utf16be' {
			return 'utf-16be'
		}
		'utf-32', 'utf-32le', 'utf32le' {
			return 'utf-32le'
		}
		'utf-32be', 'utf32be' {
			return 'utf-32be'
		}
		'ansi_x3.4-1968', 'ascii', 'cp1252', 'cp819', 'csisolatin1', 'ibm819', 'iso-8859-1', 'iso-ir-100', 'iso8859-1', 'iso88591', 'iso_8859-1', 'iso_8859-1:1987', 'l1', 'latin1', 'us-ascii', 'windows-1252', 'x-cp1252' {
			return 'windows-1252'
		}
		'csshiftjis', 'ms932', 'ms_kanji', 'shift-jis', 'shift_jis', 'sjis', 'windows-31j', 'x-sjis' {
			return 'Shift_JIS'
		}
		'cseucpkdfmtjapanese', 'euc-jp', 'eucjp', 'x-euc-jp' {
			return 'EUC-JP'
		}
		else {
			return none
		}
	}
}

pub enum EncodingModeKind {
	auto
	disabled
	some
}

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

pub enum EngineChoice {
	default
	auto
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

pub enum LoggingMode {
	debug
	trace
}

pub enum MmapMode {
	auto
	always_try_mmap
	never
}

pub enum PatternSourceKind {
	regexp
	file
}

pub struct PatternSource {
pub:
	kind  PatternSourceKind
	value string
}

pub fn pattern_regexp(value string) PatternSource {
	return PatternSource{
		kind:  .regexp
		value: value.to_owned()
	}
}

pub fn pattern_file(path string) PatternSource {
	return PatternSource{
		kind:  .file
		value: path.to_owned()
	}
}

pub struct SortMode {
pub:
	reverse bool
	kind    SortModeKind
}

pub enum SortModeKind {
	path
	last_modified
	last_accessed
	created
}

/// Checks whether the selected sort mode is supported. If it isn't, an
/// error (hopefully explaining why) is returned.
pub fn (sort SortMode) supported() ! {
	if sort.kind == .path {
		return
	}
	exe := os.executable()
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
	clear
	add
	select
	negate
}

pub struct TypeChange {
pub:
	kind TypeChangeKind
	name string
	def  string
}

pub fn type_change_clear(name string) TypeChange {
	return TypeChange{
		kind: .clear
		name: name.to_owned()
	}
}

pub fn type_change_add(def string) TypeChange {
	return TypeChange{
		kind: .add
		def:  def.to_owned()
	}
}

pub fn type_change_select(name string) TypeChange {
	return TypeChange{
		kind: .select
		name: name.to_owned()
	}
}

pub fn type_change_negate(name string) TypeChange {
	return TypeChange{
		kind: .negate
		name: name.to_owned()
	}
}

pub struct LowArgs {
pub mut:
	special                      ?SpecialMode
	mode                         Mode
	positional                   []string
	patterns                     []PatternSource
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
	// V-specific: `?LoggingMode` is represented explicitly because the current
	// ownership frontend misreads optional enum fields.
	logging                      LoggingMode
	has_logging                  bool
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
		logging:                 .debug
		has_logging:             false
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
