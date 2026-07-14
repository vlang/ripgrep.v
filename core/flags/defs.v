module flags

/*
Defines all of the flags available in ripgrep.

Each flag corresponds to a unit struct with a corresponding implementation
of `Flag`. Note that each implementation of `Flag` might actually have many
possible manifestations of the same "flag." That is, each implementation of
`Flag` can have the following flags available to an end user of ripgrep:

* The long flag name.
* An optional short flag name.
* An optional negated long flag name.
* An arbitrarily long list of aliases.

The idea is that even though there are multiple flags that a user can type,
one implementation of `Flag` corresponds to a single _logical_ flag inside of
ripgrep. For example, `-E`, `--encoding` and `--no-encoding` all manipulate the
same encoding state in ripgrep.
*/

// V-specific: Rust represents each logical flag with a unit struct that
// implements `Flag`. This port uses `FlagId` and exhaustive methods so the
// static flag registry remains ownership-free.

import encoding.utf8

pub enum FlagId {
	after_context
	auto_hybrid_regex
	before_context
	binary
	block_buffered
	byte_offset
	case_sensitive
	color
	colors
	column
	context
	context_separator
	count
	count_matches
	crlf
	debug
	dfa_size_limit
	encoding
	engine
	field_context_separator
	field_match_separator
	file
	files
	files_with_matches
	files_without_match
	fixed_strings
	follow
	generate
	glob
	glob_case_insensitive
	heading
	help
	hidden
	hostname_bin
	hyperlink_format
	i_glob
	ignore_case
	ignore_file
	ignore_file_case_insensitive
	include_zero
	invert_match
	json
	line_buffered
	line_number
	line_number_no
	line_regexp
	max_columns
	max_columns_preview
	max_count
	max_depth
	max_filesize
	mmap
	multiline
	multiline_dotall
	no_config
	no_ignore
	no_ignore_dot
	no_ignore_exclude
	no_ignore_files
	no_ignore_global
	no_ignore_messages
	no_ignore_parent
	no_ignore_vcs
	no_messages
	no_pcre_2_unicode
	no_require_git
	no_unicode
	null
	null_data
	one_file_system
	only_matching
	path_separator
	passthru
	pcre_2
	pcre_2_version
	pre
	pre_glob
	pretty
	quiet
	regex_size_limit
	regexp
	replace
	search_zip
	smart_case
	sort_files
	sort
	sortr
	stats
	stop_on_nonmatch
	text
	threads
	trace
	trim
	type
	type_add
	type_clear
	type_not
	type_list
	unrestricted
	version
	vimgrep
	with_filename
	with_filename_no
	word_regexp
}

pub const flags = [
	FlagId.regexp,
	FlagId.file,
	FlagId.after_context,
	FlagId.before_context,
	FlagId.binary,
	FlagId.block_buffered,
	FlagId.byte_offset,
	FlagId.case_sensitive,
	FlagId.color,
	FlagId.colors,
	FlagId.column,
	FlagId.context,
	FlagId.context_separator,
	FlagId.count,
	FlagId.count_matches,
	FlagId.crlf,
	FlagId.debug,
	FlagId.dfa_size_limit,
	FlagId.encoding,
	FlagId.engine,
	FlagId.field_context_separator,
	FlagId.field_match_separator,
	FlagId.files,
	FlagId.files_with_matches,
	FlagId.files_without_match,
	FlagId.fixed_strings,
	FlagId.follow,
	FlagId.generate,
	FlagId.glob,
	FlagId.glob_case_insensitive,
	FlagId.heading,
	FlagId.help,
	FlagId.hidden,
	FlagId.hostname_bin,
	FlagId.hyperlink_format,
	FlagId.i_glob,
	FlagId.ignore_case,
	FlagId.ignore_file,
	FlagId.ignore_file_case_insensitive,
	FlagId.include_zero,
	FlagId.invert_match,
	FlagId.json,
	FlagId.line_buffered,
	FlagId.line_number,
	FlagId.line_number_no,
	FlagId.line_regexp,
	FlagId.max_columns,
	FlagId.max_columns_preview,
	FlagId.max_count,
	FlagId.max_depth,
	FlagId.max_filesize,
	FlagId.mmap,
	FlagId.multiline,
	FlagId.multiline_dotall,
	FlagId.no_config,
	FlagId.no_ignore,
	FlagId.no_ignore_dot,
	FlagId.no_ignore_exclude,
	FlagId.no_ignore_files,
	FlagId.no_ignore_global,
	FlagId.no_ignore_messages,
	FlagId.no_ignore_parent,
	FlagId.no_ignore_vcs,
	FlagId.no_messages,
	FlagId.no_require_git,
	FlagId.no_unicode,
	FlagId.null,
	FlagId.null_data,
	FlagId.one_file_system,
	FlagId.only_matching,
	FlagId.path_separator,
	FlagId.passthru,
	FlagId.pcre_2,
	FlagId.pcre_2_version,
	FlagId.pre,
	FlagId.pre_glob,
	FlagId.pretty,
	FlagId.quiet,
	FlagId.regex_size_limit,
	FlagId.replace,
	FlagId.search_zip,
	FlagId.smart_case,
	FlagId.sort,
	FlagId.sortr,
	FlagId.stats,
	FlagId.stop_on_nonmatch,
	FlagId.text,
	FlagId.threads,
	FlagId.trace,
	FlagId.trim,
	FlagId.type,
	FlagId.type_not,
	FlagId.type_add,
	FlagId.type_clear,
	FlagId.type_list,
	FlagId.unrestricted,
	FlagId.version,
	FlagId.vimgrep,
	FlagId.with_filename,
	FlagId.with_filename_no,
	FlagId.word_regexp,
	FlagId.auto_hybrid_regex,
	FlagId.no_pcre_2_unicode,
	FlagId.sort_files,
]

pub fn (id FlagId) is_switch() bool {
	return match id {
		.after_context { false }
		.auto_hybrid_regex { true }
		.before_context { false }
		.binary { true }
		.block_buffered { true }
		.byte_offset { true }
		.case_sensitive { true }
		.color { false }
		.colors { false }
		.column { true }
		.context { false }
		.context_separator { false }
		.count { true }
		.count_matches { true }
		.crlf { true }
		.debug { true }
		.dfa_size_limit { false }
		.encoding { false }
		.engine { false }
		.field_context_separator { false }
		.field_match_separator { false }
		.file { false }
		.files { true }
		.files_with_matches { true }
		.files_without_match { true }
		.fixed_strings { true }
		.follow { true }
		.generate { false }
		.glob { false }
		.glob_case_insensitive { true }
		.heading { true }
		.help { true }
		.hidden { true }
		.hostname_bin { false }
		.hyperlink_format { false }
		.i_glob { false }
		.ignore_case { true }
		.ignore_file { false }
		.ignore_file_case_insensitive { true }
		.include_zero { true }
		.invert_match { true }
		.json { true }
		.line_buffered { true }
		.line_number { true }
		.line_number_no { true }
		.line_regexp { true }
		.max_columns { false }
		.max_columns_preview { true }
		.max_count { false }
		.max_depth { false }
		.max_filesize { false }
		.mmap { true }
		.multiline { true }
		.multiline_dotall { true }
		.no_config { true }
		.no_ignore { true }
		.no_ignore_dot { true }
		.no_ignore_exclude { true }
		.no_ignore_files { true }
		.no_ignore_global { true }
		.no_ignore_messages { true }
		.no_ignore_parent { true }
		.no_ignore_vcs { true }
		.no_messages { true }
		.no_pcre_2_unicode { true }
		.no_require_git { true }
		.no_unicode { true }
		.null { true }
		.null_data { true }
		.one_file_system { true }
		.only_matching { true }
		.path_separator { false }
		.passthru { true }
		.pcre_2 { true }
		.pcre_2_version { true }
		.pre { false }
		.pre_glob { false }
		.pretty { true }
		.quiet { true }
		.regex_size_limit { false }
		.regexp { false }
		.replace { false }
		.search_zip { true }
		.smart_case { true }
		.sort_files { true }
		.sort { false }
		.sortr { false }
		.stats { true }
		.stop_on_nonmatch { true }
		.text { true }
		.threads { false }
		.trace { true }
		.trim { true }
		.type { false }
		.type_add { false }
		.type_clear { false }
		.type_not { false }
		.type_list { true }
		.unrestricted { true }
		.version { true }
		.vimgrep { true }
		.with_filename { true }
		.with_filename_no { true }
		.word_regexp { true }
	}
}

pub fn (id FlagId) name_short() ?u8 {
	return match id {
		.after_context { u8(`A`) }
		.auto_hybrid_regex { none }
		.before_context { u8(`B`) }
		.binary { none }
		.block_buffered { none }
		.byte_offset { u8(`b`) }
		.case_sensitive { u8(`s`) }
		.color { none }
		.colors { none }
		.column { none }
		.context { u8(`C`) }
		.context_separator { none }
		.count { u8(`c`) }
		.count_matches { none }
		.crlf { none }
		.debug { none }
		.dfa_size_limit { none }
		.encoding { u8(`E`) }
		.engine { none }
		.field_context_separator { none }
		.field_match_separator { none }
		.file { u8(`f`) }
		.files { none }
		.files_with_matches { u8(`l`) }
		.files_without_match { none }
		.fixed_strings { u8(`F`) }
		.follow { u8(`L`) }
		.generate { none }
		.glob { u8(`g`) }
		.glob_case_insensitive { none }
		.heading { none }
		.help { u8(`h`) }
		.hidden { u8(`.`) }
		.hostname_bin { none }
		.hyperlink_format { none }
		.i_glob { none }
		.ignore_case { u8(`i`) }
		.ignore_file { none }
		.ignore_file_case_insensitive { none }
		.include_zero { none }
		.invert_match { u8(`v`) }
		.json { none }
		.line_buffered { none }
		.line_number { u8(`n`) }
		.line_number_no { u8(`N`) }
		.line_regexp { u8(`x`) }
		.max_columns { u8(`M`) }
		.max_columns_preview { none }
		.max_count { u8(`m`) }
		.max_depth { u8(`d`) }
		.max_filesize { none }
		.mmap { none }
		.multiline { u8(`U`) }
		.multiline_dotall { none }
		.no_config { none }
		.no_ignore { none }
		.no_ignore_dot { none }
		.no_ignore_exclude { none }
		.no_ignore_files { none }
		.no_ignore_global { none }
		.no_ignore_messages { none }
		.no_ignore_parent { none }
		.no_ignore_vcs { none }
		.no_messages { none }
		.no_pcre_2_unicode { none }
		.no_require_git { none }
		.no_unicode { none }
		.null { u8(`0`) }
		.null_data { none }
		.one_file_system { none }
		.only_matching { u8(`o`) }
		.path_separator { none }
		.passthru { none }
		.pcre_2 { u8(`P`) }
		.pcre_2_version { none }
		.pre { none }
		.pre_glob { none }
		.pretty { u8(`p`) }
		.quiet { u8(`q`) }
		.regex_size_limit { none }
		.regexp { u8(`e`) }
		.replace { u8(`r`) }
		.search_zip { u8(`z`) }
		.smart_case { u8(`S`) }
		.sort_files { none }
		.sort { none }
		.sortr { none }
		.stats { none }
		.stop_on_nonmatch { none }
		.text { u8(`a`) }
		.threads { u8(`j`) }
		.trace { none }
		.trim { none }
		.type { u8(`t`) }
		.type_add { none }
		.type_clear { none }
		.type_not { u8(`T`) }
		.type_list { none }
		.unrestricted { u8(`u`) }
		.version { u8(`V`) }
		.vimgrep { none }
		.with_filename { u8(`H`) }
		.with_filename_no { u8(`I`) }
		.word_regexp { u8(`w`) }
		else { none }
	}
}

pub fn (id FlagId) name_long() string {
	return match id {
		.after_context { 'after-context' }
		.auto_hybrid_regex { 'auto-hybrid-regex' }
		.before_context { 'before-context' }
		.binary { 'binary' }
		.block_buffered { 'block-buffered' }
		.byte_offset { 'byte-offset' }
		.case_sensitive { 'case-sensitive' }
		.color { 'color' }
		.colors { 'colors' }
		.column { 'column' }
		.context { 'context' }
		.context_separator { 'context-separator' }
		.count { 'count' }
		.count_matches { 'count-matches' }
		.crlf { 'crlf' }
		.debug { 'debug' }
		.dfa_size_limit { 'dfa-size-limit' }
		.encoding { 'encoding' }
		.engine { 'engine' }
		.field_context_separator { 'field-context-separator' }
		.field_match_separator { 'field-match-separator' }
		.file { 'file' }
		.files { 'files' }
		.files_with_matches { 'files-with-matches' }
		.files_without_match { 'files-without-match' }
		.fixed_strings { 'fixed-strings' }
		.follow { 'follow' }
		.generate { 'generate' }
		.glob { 'glob' }
		.glob_case_insensitive { 'glob-case-insensitive' }
		.heading { 'heading' }
		.help { 'help' }
		.hidden { 'hidden' }
		.hostname_bin { 'hostname-bin' }
		.hyperlink_format { 'hyperlink-format' }
		.i_glob { 'iglob' }
		.ignore_case { 'ignore-case' }
		.ignore_file { 'ignore-file' }
		.ignore_file_case_insensitive { 'ignore-file-case-insensitive' }
		.include_zero { 'include-zero' }
		.invert_match { 'invert-match' }
		.json { 'json' }
		.line_buffered { 'line-buffered' }
		.line_number { 'line-number' }
		.line_number_no { 'no-line-number' }
		.line_regexp { 'line-regexp' }
		.max_columns { 'max-columns' }
		.max_columns_preview { 'max-columns-preview' }
		.max_count { 'max-count' }
		.max_depth { 'max-depth' }
		.max_filesize { 'max-filesize' }
		.mmap { 'mmap' }
		.multiline { 'multiline' }
		.multiline_dotall { 'multiline-dotall' }
		.no_config { 'no-config' }
		.no_ignore { 'no-ignore' }
		.no_ignore_dot { 'no-ignore-dot' }
		.no_ignore_exclude { 'no-ignore-exclude' }
		.no_ignore_files { 'no-ignore-files' }
		.no_ignore_global { 'no-ignore-global' }
		.no_ignore_messages { 'no-ignore-messages' }
		.no_ignore_parent { 'no-ignore-parent' }
		.no_ignore_vcs { 'no-ignore-vcs' }
		.no_messages { 'no-messages' }
		.no_pcre_2_unicode { 'no-pcre2-unicode' }
		.no_require_git { 'no-require-git' }
		.no_unicode { 'no-unicode' }
		.null { 'null' }
		.null_data { 'null-data' }
		.one_file_system { 'one-file-system' }
		.only_matching { 'only-matching' }
		.path_separator { 'path-separator' }
		.passthru { 'passthru' }
		.pcre_2 { 'pcre2' }
		.pcre_2_version { 'pcre2-version' }
		.pre { 'pre' }
		.pre_glob { 'pre-glob' }
		.pretty { 'pretty' }
		.quiet { 'quiet' }
		.regex_size_limit { 'regex-size-limit' }
		.regexp { 'regexp' }
		.replace { 'replace' }
		.search_zip { 'search-zip' }
		.smart_case { 'smart-case' }
		.sort_files { 'sort-files' }
		.sort { 'sort' }
		.sortr { 'sortr' }
		.stats { 'stats' }
		.stop_on_nonmatch { 'stop-on-nonmatch' }
		.text { 'text' }
		.threads { 'threads' }
		.trace { 'trace' }
		.trim { 'trim' }
		.type { 'type' }
		.type_add { 'type-add' }
		.type_clear { 'type-clear' }
		.type_not { 'type-not' }
		.type_list { 'type-list' }
		.unrestricted { 'unrestricted' }
		.version { 'version' }
		.vimgrep { 'vimgrep' }
		.with_filename { 'with-filename' }
		.with_filename_no { 'no-filename' }
		.word_regexp { 'word-regexp' }
	}
}

pub fn (id FlagId) aliases() []string {
	return match id {
		.after_context { []string{} }
		.auto_hybrid_regex { []string{} }
		.before_context { []string{} }
		.binary { []string{} }
		.block_buffered { []string{} }
		.byte_offset { []string{} }
		.case_sensitive { []string{} }
		.color { []string{} }
		.colors { []string{} }
		.column { []string{} }
		.context { []string{} }
		.context_separator { []string{} }
		.count { []string{} }
		.count_matches { []string{} }
		.crlf { []string{} }
		.debug { []string{} }
		.dfa_size_limit { []string{} }
		.encoding { []string{} }
		.engine { []string{} }
		.field_context_separator { []string{} }
		.field_match_separator { []string{} }
		.file { []string{} }
		.files { []string{} }
		.files_with_matches { []string{} }
		.files_without_match { []string{} }
		.fixed_strings { []string{} }
		.follow { []string{} }
		.generate { []string{} }
		.glob { []string{} }
		.glob_case_insensitive { []string{} }
		.heading { []string{} }
		.help { []string{} }
		.hidden { []string{} }
		.hostname_bin { []string{} }
		.hyperlink_format { []string{} }
		.i_glob { []string{} }
		.ignore_case { []string{} }
		.ignore_file { []string{} }
		.ignore_file_case_insensitive { []string{} }
		.include_zero { []string{} }
		.invert_match { []string{} }
		.json { []string{} }
		.line_buffered { []string{} }
		.line_number { []string{} }
		.line_number_no { []string{} }
		.line_regexp { []string{} }
		.max_columns { []string{} }
		.max_columns_preview { []string{} }
		.max_count { []string{} }
		.max_depth { ['maxdepth'] }
		.max_filesize { []string{} }
		.mmap { []string{} }
		.multiline { []string{} }
		.multiline_dotall { []string{} }
		.no_config { []string{} }
		.no_ignore { []string{} }
		.no_ignore_dot { []string{} }
		.no_ignore_exclude { []string{} }
		.no_ignore_files { []string{} }
		.no_ignore_global { []string{} }
		.no_ignore_messages { []string{} }
		.no_ignore_parent { []string{} }
		.no_ignore_vcs { []string{} }
		.no_messages { []string{} }
		.no_pcre_2_unicode { []string{} }
		.no_require_git { []string{} }
		.no_unicode { []string{} }
		.null { []string{} }
		.null_data { []string{} }
		.one_file_system { []string{} }
		.only_matching { []string{} }
		.path_separator { []string{} }
		.passthru { ['passthrough'] }
		.pcre_2 { []string{} }
		.pcre_2_version { []string{} }
		.pre { []string{} }
		.pre_glob { []string{} }
		.pretty { []string{} }
		.quiet { []string{} }
		.regex_size_limit { []string{} }
		.regexp { []string{} }
		.replace { []string{} }
		.search_zip { []string{} }
		.smart_case { []string{} }
		.sort_files { []string{} }
		.sort { []string{} }
		.sortr { []string{} }
		.stats { []string{} }
		.stop_on_nonmatch { []string{} }
		.text { []string{} }
		.threads { []string{} }
		.trace { []string{} }
		.trim { []string{} }
		.type { []string{} }
		.type_add { []string{} }
		.type_clear { []string{} }
		.type_not { []string{} }
		.type_list { []string{} }
		.unrestricted { []string{} }
		.version { []string{} }
		.vimgrep { []string{} }
		.with_filename { []string{} }
		.with_filename_no { []string{} }
		.word_regexp { []string{} }
		else { []string{} }
	}
}

pub fn (id FlagId) name_negated() ?string {
	return match id {
		.after_context { none }
		.auto_hybrid_regex { 'no-auto-hybrid-regex' }
		.before_context { none }
		.binary { 'no-binary' }
		.block_buffered { 'no-block-buffered' }
		.byte_offset { 'no-byte-offset' }
		.case_sensitive { none }
		.color { none }
		.colors { none }
		.column { 'no-column' }
		.context { none }
		.context_separator { 'no-context-separator' }
		.count { none }
		.count_matches { none }
		.crlf { 'no-crlf' }
		.debug { none }
		.dfa_size_limit { none }
		.encoding { 'no-encoding' }
		.engine { none }
		.field_context_separator { none }
		.field_match_separator { none }
		.file { none }
		.files { none }
		.files_with_matches { none }
		.files_without_match { none }
		.fixed_strings { 'no-fixed-strings' }
		.follow { 'no-follow' }
		.generate { none }
		.glob { none }
		.glob_case_insensitive { 'no-glob-case-insensitive' }
		.heading { 'no-heading' }
		.help { none }
		.hidden { 'no-hidden' }
		.hostname_bin { none }
		.hyperlink_format { none }
		.i_glob { none }
		.ignore_case { none }
		.ignore_file { none }
		.ignore_file_case_insensitive { 'no-ignore-file-case-insensitive' }
		.include_zero { 'no-include-zero' }
		.invert_match { 'no-invert-match' }
		.json { 'no-json' }
		.line_buffered { 'no-line-buffered' }
		.line_number { none }
		.line_number_no { none }
		.line_regexp { none }
		.max_columns { none }
		.max_columns_preview { 'no-max-columns-preview' }
		.max_count { none }
		.max_depth { none }
		.max_filesize { none }
		.mmap { 'no-mmap' }
		.multiline { 'no-multiline' }
		.multiline_dotall { 'no-multiline-dotall' }
		.no_config { none }
		.no_ignore { 'ignore' }
		.no_ignore_dot { 'ignore-dot' }
		.no_ignore_exclude { 'ignore-exclude' }
		.no_ignore_files { 'ignore-files' }
		.no_ignore_global { 'ignore-global' }
		.no_ignore_messages { 'ignore-messages' }
		.no_ignore_parent { 'ignore-parent' }
		.no_ignore_vcs { 'ignore-vcs' }
		.no_messages { 'messages' }
		.no_pcre_2_unicode { 'pcre2-unicode' }
		.no_require_git { 'require-git' }
		.no_unicode { 'unicode' }
		.null { none }
		.null_data { none }
		.one_file_system { 'no-one-file-system' }
		.only_matching { none }
		.path_separator { none }
		.passthru { none }
		.pcre_2 { 'no-pcre2' }
		.pcre_2_version { none }
		.pre { 'no-pre' }
		.pre_glob { none }
		.pretty { none }
		.quiet { none }
		.regex_size_limit { none }
		.regexp { none }
		.replace { none }
		.search_zip { 'no-search-zip' }
		.smart_case { none }
		.sort_files { 'no-sort-files' }
		.sort { none }
		.sortr { none }
		.stats { 'no-stats' }
		.stop_on_nonmatch { none }
		.text { 'no-text' }
		.threads { none }
		.trace { none }
		.trim { 'no-trim' }
		.type { none }
		.type_add { none }
		.type_clear { none }
		.type_not { none }
		.type_list { none }
		.unrestricted { none }
		.version { none }
		.vimgrep { none }
		.with_filename { none }
		.with_filename_no { none }
		.word_regexp { none }
		else { none }
	}
}

pub fn (id FlagId) doc_variable() ?string {
	return match id {
		.after_context { 'NUM' }
		.auto_hybrid_regex { none }
		.before_context { 'NUM' }
		.binary { none }
		.block_buffered { none }
		.byte_offset { none }
		.case_sensitive { none }
		.color { 'WHEN' }
		.colors { 'COLOR_SPEC' }
		.column { none }
		.context { 'NUM' }
		.context_separator { 'SEPARATOR' }
		.count { none }
		.count_matches { none }
		.crlf { none }
		.debug { none }
		.dfa_size_limit { 'NUM+SUFFIX?' }
		.encoding { 'ENCODING' }
		.engine { 'ENGINE' }
		.field_context_separator { 'SEPARATOR' }
		.field_match_separator { 'SEPARATOR' }
		.file { 'PATTERNFILE' }
		.files { none }
		.files_with_matches { none }
		.files_without_match { none }
		.fixed_strings { none }
		.follow { none }
		.generate { 'KIND' }
		.glob { 'GLOB' }
		.glob_case_insensitive { none }
		.heading { none }
		.help { none }
		.hidden { none }
		.hostname_bin { 'COMMAND' }
		.hyperlink_format { 'FORMAT' }
		.i_glob { 'GLOB' }
		.ignore_case { none }
		.ignore_file { 'PATH' }
		.ignore_file_case_insensitive { none }
		.include_zero { none }
		.invert_match { none }
		.json { none }
		.line_buffered { none }
		.line_number { none }
		.line_number_no { none }
		.line_regexp { none }
		.max_columns { 'NUM' }
		.max_columns_preview { none }
		.max_count { 'NUM' }
		.max_depth { 'NUM' }
		.max_filesize { 'NUM+SUFFIX?' }
		.mmap { none }
		.multiline { none }
		.multiline_dotall { none }
		.no_config { none }
		.no_ignore { none }
		.no_ignore_dot { none }
		.no_ignore_exclude { none }
		.no_ignore_files { none }
		.no_ignore_global { none }
		.no_ignore_messages { none }
		.no_ignore_parent { none }
		.no_ignore_vcs { none }
		.no_messages { none }
		.no_pcre_2_unicode { none }
		.no_require_git { none }
		.no_unicode { none }
		.null { none }
		.null_data { none }
		.one_file_system { none }
		.only_matching { none }
		.path_separator { 'SEPARATOR' }
		.passthru { none }
		.pcre_2 { none }
		.pcre_2_version { none }
		.pre { 'COMMAND' }
		.pre_glob { 'GLOB' }
		.pretty { none }
		.quiet { none }
		.regex_size_limit { 'NUM+SUFFIX?' }
		.regexp { 'PATTERN' }
		.replace { 'REPLACEMENT' }
		.search_zip { none }
		.smart_case { none }
		.sort_files { none }
		.sort { 'SORTBY' }
		.sortr { 'SORTBY' }
		.stats { none }
		.stop_on_nonmatch { none }
		.text { none }
		.threads { 'NUM' }
		.trace { none }
		.trim { none }
		.type { 'TYPE' }
		.type_add { 'TYPESPEC' }
		.type_clear { 'TYPE' }
		.type_not { 'TYPE' }
		.type_list { none }
		.unrestricted { none }
		.version { none }
		.vimgrep { none }
		.with_filename { none }
		.with_filename_no { none }
		.word_regexp { none }
		else { none }
	}
}

pub fn (id FlagId) doc_category() Category {
	return match id {
		.after_context { .output }
		.auto_hybrid_regex { .search }
		.before_context { .output }
		.binary { .filter }
		.block_buffered { .output }
		.byte_offset { .output }
		.case_sensitive { .search }
		.color { .output }
		.colors { .output }
		.column { .output }
		.context { .output }
		.context_separator { .output }
		.count { .output_modes }
		.count_matches { .output_modes }
		.crlf { .search }
		.debug { .logging }
		.dfa_size_limit { .search }
		.encoding { .search }
		.engine { .search }
		.field_context_separator { .output }
		.field_match_separator { .output }
		.file { .input }
		.files { .other_behaviors }
		.files_with_matches { .output_modes }
		.files_without_match { .output_modes }
		.fixed_strings { .search }
		.follow { .filter }
		.generate { .other_behaviors }
		.glob { .filter }
		.glob_case_insensitive { .filter }
		.heading { .output }
		.help { .output }
		.hidden { .filter }
		.hostname_bin { .output }
		.hyperlink_format { .output }
		.i_glob { .filter }
		.ignore_case { .search }
		.ignore_file { .filter }
		.ignore_file_case_insensitive { .filter }
		.include_zero { .output }
		.invert_match { .search }
		.json { .output_modes }
		.line_buffered { .output }
		.line_number { .output }
		.line_number_no { .output }
		.line_regexp { .search }
		.max_columns { .output }
		.max_columns_preview { .output }
		.max_count { .search }
		.max_depth { .filter }
		.max_filesize { .filter }
		.mmap { .search }
		.multiline { .search }
		.multiline_dotall { .search }
		.no_config { .other_behaviors }
		.no_ignore { .filter }
		.no_ignore_dot { .filter }
		.no_ignore_exclude { .filter }
		.no_ignore_files { .filter }
		.no_ignore_global { .filter }
		.no_ignore_messages { .logging }
		.no_ignore_parent { .filter }
		.no_ignore_vcs { .filter }
		.no_messages { .logging }
		.no_pcre_2_unicode { .search }
		.no_require_git { .filter }
		.no_unicode { .search }
		.null { .output }
		.null_data { .search }
		.one_file_system { .filter }
		.only_matching { .output }
		.path_separator { .output }
		.passthru { .output }
		.pcre_2 { .search }
		.pcre_2_version { .other_behaviors }
		.pre { .input }
		.pre_glob { .input }
		.pretty { .output }
		.quiet { .output }
		.regex_size_limit { .search }
		.regexp { .input }
		.replace { .output }
		.search_zip { .input }
		.smart_case { .search }
		.sort_files { .output }
		.sort { .output }
		.sortr { .output }
		.stats { .logging }
		.stop_on_nonmatch { .search }
		.text { .search }
		.threads { .search }
		.trace { .logging }
		.trim { .output }
		.type { .filter }
		.type_add { .filter }
		.type_clear { .filter }
		.type_not { .filter }
		.type_list { .other_behaviors }
		.unrestricted { .filter }
		.version { .other_behaviors }
		.vimgrep { .output }
		.with_filename { .output }
		.with_filename_no { .output }
		.word_regexp { .search }
	}
}

pub fn (id FlagId) doc_short() string {
	return match id {
		.after_context { 'Show NUM lines after each match.' }
		.auto_hybrid_regex { '(DEPRECATED) Use PCRE2 if appropriate.' }
		.before_context { 'Show NUM lines before each match.' }
		.binary { 'Search binary files.' }
		.block_buffered { 'Force block buffering.' }
		.byte_offset { 'Print the byte offset for each matching line.' }
		.case_sensitive { 'Search case sensitively (default).' }
		.color { 'When to use color.' }
		.colors { 'Configure color settings and styles.' }
		.column { 'Show column numbers.' }
		.context { 'Show NUM lines before and after each match.' }
		.context_separator { 'Set the separator for contextual chunks.' }
		.count { 'Show count of matching lines for each file.' }
		.count_matches { 'Show count of every match for each file.' }
		.crlf { 'Use CRLF line terminators (nice for Windows).' }
		.debug { 'Show debug messages.' }
		.dfa_size_limit { 'The upper size limit of the regex DFA.' }
		.encoding { 'Specify the text encoding of files to search.' }
		.engine { 'Specify which regex engine to use.' }
		.field_context_separator { 'Set the field context separator.' }
		.field_match_separator { 'Set the field match separator.' }
		.file { 'Search for patterns from the given file.' }
		.files { 'Print each file that would be searched.' }
		.files_with_matches { 'Print the paths with at least one match.' }
		.files_without_match { 'Print the paths that contain zero matches.' }
		.fixed_strings { 'Treat all patterns as literals.' }
		.follow { 'Follow symbolic links.' }
		.generate { 'Generate man pages and completion scripts.' }
		.glob { 'Include or exclude file paths.' }
		.glob_case_insensitive { 'Process all glob patterns case insensitively.' }
		.heading { 'Print matches grouped by each file.' }
		.help { 'Show help output.' }
		.hidden { 'Search hidden files and directories.' }
		.hostname_bin { 'Run a program to get this system\'s hostname.' }
		.hyperlink_format { 'Set the format of hyperlinks.' }
		.i_glob { 'Include/exclude paths case insensitively.' }
		.ignore_case { 'Case insensitive search.' }
		.ignore_file { 'Specify additional ignore files.' }
		.ignore_file_case_insensitive { 'Process ignore files case insensitively.' }
		.include_zero { 'Include zero matches in summary output.' }
		.invert_match { 'Invert matching.' }
		.json { 'Show search results in a JSON Lines format.' }
		.line_buffered { 'Force line buffering.' }
		.line_number { 'Show line numbers.' }
		.line_number_no { 'Suppress line numbers.' }
		.line_regexp { 'Show matches surrounded by line boundaries.' }
		.max_columns { 'Omit lines longer than this limit.' }
		.max_columns_preview { 'Show preview for lines exceeding the limit.' }
		.max_count { 'Limit the number of matching lines.' }
		.max_depth { 'Descend at most NUM directories.' }
		.max_filesize { 'Ignore files larger than NUM in size.' }
		.mmap { 'Search with memory maps when possible.' }
		.multiline { 'Enable searching across multiple lines.' }
		.multiline_dotall { 'Make \'.\' match line terminators.' }
		.no_config { 'Never read configuration files.' }
		.no_ignore { 'Don\'t use ignore files.' }
		.no_ignore_dot { 'Don\'t use .ignore or .rgignore files.' }
		.no_ignore_exclude { 'Don\'t use local exclusion files.' }
		.no_ignore_files { 'Don\'t use --ignore-file arguments.' }
		.no_ignore_global { 'Don\'t use global ignore files.' }
		.no_ignore_messages { 'Suppress gitignore parse error messages.' }
		.no_ignore_parent { 'Don\'t use ignore files in parent directories.' }
		.no_ignore_vcs { 'Don\'t use ignore files from source control.' }
		.no_messages { 'Suppress some error messages.' }
		.no_pcre_2_unicode { '(DEPRECATED) Disable Unicode mode for PCRE2.' }
		.no_require_git { 'Use .gitignore outside of git repositories.' }
		.no_unicode { 'Disable Unicode mode.' }
		.null { 'Print a NUL byte after file paths.' }
		.null_data { 'Use NUL as a line terminator.' }
		.one_file_system { 'Skip directories on other file systems.' }
		.only_matching { 'Print only matched parts of a line.' }
		.path_separator { 'Set the path separator for printing paths.' }
		.passthru { 'Print both matching and non-matching lines.' }
		.pcre_2 { 'Enable PCRE2 matching.' }
		.pcre_2_version { 'Print the version of PCRE2 that ripgrep uses.' }
		.pre { 'Search output of COMMAND for each PATH.' }
		.pre_glob { 'Include or exclude files from a preprocessor.' }
		.pretty { 'Alias for colors, headings and line numbers.' }
		.quiet { 'Do not print anything to stdout.' }
		.regex_size_limit { 'The size limit of the compiled regex.' }
		.regexp { 'A pattern to search for.' }
		.replace { 'Replace matches with the given text.' }
		.search_zip { 'Search in compressed files.' }
		.smart_case { 'Smart case search.' }
		.sort_files { '(DEPRECATED) Sort results by file path.' }
		.sort { 'Sort results in ascending order.' }
		.sortr { 'Sort results in descending order.' }
		.stats { 'Print statistics about the search.' }
		.stop_on_nonmatch { 'Stop searching after a non-match.' }
		.text { 'Search binary files as if they were text.' }
		.threads { 'Set the approximate number of threads to use.' }
		.trace { 'Show trace messages.' }
		.trim { 'Trim prefix whitespace from matches.' }
		.type { 'Only search files matching TYPE.' }
		.type_add { 'Add a new glob for a file type.' }
		.type_clear { 'Clear globs for a file type.' }
		.type_not { 'Do not search files matching TYPE.' }
		.type_list { 'Show all supported file types.' }
		.unrestricted { 'Reduce the level of "smart" filtering.' }
		.version { 'Print ripgrep\'s version.' }
		.vimgrep { 'Print results in a vim compatible format.' }
		.with_filename { 'Print the file path with each matching line.' }
		.with_filename_no { 'Never print the path with each matching line.' }
		.word_regexp { 'Show matches surrounded by word boundaries.' }
	}
}

pub fn (id FlagId) doc_long() string {
	return match id {
		.after_context { '
Show \\fINUM\\fP lines after each match.
.sp
This overrides the \\flag{passthru} flag and partially overrides the
\\flag{context} flag.
' }
		.auto_hybrid_regex { '
DEPRECATED. Use \\flag{engine} instead.
.sp
When this flag is used, ripgrep will dynamically choose between supported regex
engines depending on the features used in a pattern. When ripgrep chooses a
regex engine, it applies that choice for every regex provided to ripgrep (e.g.,
via multiple \\flag{regexp} or \\flag{file} flags).
.sp
As an example of how this flag might behave, ripgrep will attempt to use
its default finite automata based regex engine whenever the pattern can be
successfully compiled with that regex engine. If PCRE2 is enabled and if the
pattern given could not be compiled with the default regex engine, then PCRE2
will be automatically used for searching. If PCRE2 isn\'t available, then this
flag has no effect because there is only one regex engine to choose from.
.sp
In the future, ripgrep may adjust its heuristics for how it decides which
regex engine to use. In general, the heuristics will be limited to a static
analysis of the patterns, and not to any specific runtime behavior observed
while searching files.
.sp
The primary downside of using this flag is that it may not always be obvious
which regex engine ripgrep uses, and thus, the match semantics or performance
profile of ripgrep may subtly and unexpectedly change. However, in many cases,
all regex engines will agree on what constitutes a match and it can be nice
to transparently support more advanced regex features like look-around and
backreferences without explicitly needing to enable them.
' }
		.before_context { '
Show \\fINUM\\fP lines before each match.
.sp
This overrides the \\flag{passthru} flag and partially overrides the
\\flag{context} flag.
' }
		.binary { '
Enabling this flag will cause ripgrep to search binary files. By default,
ripgrep attempts to automatically skip binary files in order to improve the
relevance of results and make the search faster.
.sp
Binary files are heuristically detected based on whether they contain a
\\fBNUL\\fP byte or not. By default (without this flag set), once a \\fBNUL\\fP
byte is seen, ripgrep will stop searching the file. Usually, \\fBNUL\\fP bytes
occur in the beginning of most binary files. If a \\fBNUL\\fP byte occurs after
a match, then ripgrep will not print the match, stop searching that file, and
emit a warning that some matches are being suppressed.
.sp
In contrast, when this flag is provided, ripgrep will continue searching a
file even if a \\fBNUL\\fP byte is found. In particular, if a \\fBNUL\\fP byte is
found then ripgrep will continue searching until either a match is found or
the end of the file is reached, whichever comes sooner. If a match is found,
then ripgrep will stop and print a warning saying that the search stopped
prematurely.
.sp
If you want ripgrep to search a file without any special \\fBNUL\\fP byte
handling at all (and potentially print binary data to stdout), then you should
use the \\flag{text} flag.
.sp
The \\flag{binary} flag is a flag for controlling ripgrep\'s automatic filtering
mechanism. As such, it does not need to be used when searching a file
explicitly or when searching stdin. That is, it is only applicable when
recursively searching a directory.
.sp
When the \\flag{unrestricted} flag is provided for a third time, then this flag
is automatically enabled.
.sp
This flag overrides the \\flag{text} flag.
' }
		.block_buffered { '
When enabled, ripgrep will use block buffering. That is, whenever a matching
line is found, it will be written to an in-memory buffer and will not be
written to stdout until the buffer reaches a certain size. This is the default
when ripgrep\'s stdout is redirected to a pipeline or a file. When ripgrep\'s
stdout is connected to a tty, line buffering will be used by default. Forcing
block buffering can be useful when dumping a large amount of contents to a tty.
.sp
This overrides the \\flag{line-buffered} flag.
' }
		.byte_offset { '
Print the 0-based byte offset within the input file before each line of output.
If \\flag{only-matching} is specified, print the offset of the matched text
itself.
.sp
If ripgrep does transcoding, then the byte offset is in terms of the result
of transcoding and not the original data. This applies similarly to other
transformations on the data, such as decompression or a \\flag{pre} filter.
' }
		.case_sensitive { '
Execute the search case sensitively. This is the default mode.
.sp
This is a global option that applies to all patterns given to ripgrep.
Individual patterns can still be matched case insensitively by using inline
regex flags. For example, \\fB(?i)abc\\fP will match \\fBabc\\fP case insensitively
even when this flag is used.
.sp
This flag overrides the \\flag{ignore-case} and \\flag{smart-case} flags.
' }
		.color { '
This flag controls when to use colors. The default setting is \\fBauto\\fP, which
means ripgrep will try to guess when to use colors. For example, if ripgrep is
printing to a tty, then it will use colors, but if it is redirected to a file
or a pipe, then it will suppress color output.
.sp
ripgrep will suppress color output by default in some other circumstances as
well. These include, but are not limited to:
.sp
.IP \\(bu 3n
When the \\fBTERM\\fP environment variable is not set or set to \\fBdumb\\fP.
.sp
.IP \\(bu 3n
When the \\fBNO_COLOR\\fP environment variable is set (regardless of value).
.sp
.IP \\(bu 3n
When flags that imply no use for colors are given. For example,
\\flag{vimgrep} and \\flag{json}.
.
.PP
The possible values for this flag are:
.sp
.IP \\fBnever\\fP 10n
Colors will never be used.
.sp
.IP \\fBauto\\fP 10n
The default. ripgrep tries to be smart.
.sp
.IP \\fBalways\\fP 10n
Colors will always be used regardless of where output is sent.
.sp
.IP \\fBansi\\fP 10n
Like \'always\', but emits ANSI escapes (even in a Windows console).
.
.PP
This flag also controls whether hyperlinks are emitted. For example, when
a hyperlink format is specified, hyperlinks won\'t be used when color is
suppressed. If one wants to emit hyperlinks but no colors, then one must use
the \\flag{colors} flag to manually set all color styles to \\fBnone\\fP:
.sp
.EX
    \\-\\-colors \'path:none\' \\\\
    \\-\\-colors \'line:none\' \\\\
    \\-\\-colors \'column:none\' \\\\
    \\-\\-colors \'match:none\' \\\\
    \\-\\-colors \'highlight:none\'
.EE
.sp
' }
		.colors { '
This flag specifies color settings for use in the output. This flag may be
provided multiple times. Settings are applied iteratively. Pre-existing color
labels are limited to one of eight choices: \\fBred\\fP, \\fBblue\\fP, \\fBgreen\\fP,
\\fBcyan\\fP, \\fBmagenta\\fP, \\fByellow\\fP, \\fBwhite\\fP and \\fBblack\\fP. Styles
are limited to \\fBnobold\\fP, \\fBbold\\fP, \\fBnointense\\fP, \\fBintense\\fP,
\\fBnounderline\\fP, \\fBunderline\\fP, \\fBnoitalic\\fP or \\fBitalic\\fP.
.sp
The format of the flag is
\\fB{\\fP\\fItype\\fP\\fB}:{\\fP\\fIattribute\\fP\\fB}:{\\fP\\fIvalue\\fP\\fB}\\fP.
\\fItype\\fP should be one of \\fBpath\\fP, \\fBline\\fP, \\fBcolumn\\fP,
\\fBhighlight\\fP or \\fBmatch\\fP. \\fIattribute\\fP can be \\fBfg\\fP, \\fBbg\\fP or
\\fBstyle\\fP. \\fIvalue\\fP is either a color (for \\fBfg\\fP and \\fBbg\\fP) or a
text style. A special format, \\fB{\\fP\\fItype\\fP\\fB}:none\\fP, will clear all
color settings for \\fItype\\fP.
.sp
For example, the following command will change the match color to magenta and
the background color for line numbers to yellow:
.sp
.EX
    rg \\-\\-colors \'match:fg:magenta\' \\-\\-colors \'line:bg:yellow\'
.EE
.sp
Another example, the following command will "highlight" the non-matching text
in matching lines:
.sp
.EX
    rg \\-\\-colors \'highlight:bg:yellow\' \\-\\-colors \'highlight:fg:black\'
.EE
.sp
The "highlight" color type is particularly useful for contrasting matching
lines with surrounding context printed by the \\flag{before-context},
\\flag{after-context}, \\flag{context} or \\flag{passthru} flags.
.sp
Extended colors can be used for \\fIvalue\\fP when the tty supports ANSI color
sequences. These are specified as either \\fIx\\fP (256-color) or
.IB x , x , x
(24-bit truecolor) where \\fIx\\fP is a number between \\fB0\\fP and \\fB255\\fP
inclusive. \\fIx\\fP may be given as a normal decimal number or a hexadecimal
number, which is prefixed by \\fB0x\\fP.
.sp
For example, the following command will change the match background color to
that represented by the rgb value (0,128,255):
.sp
.EX
    rg \\-\\-colors \'match:bg:0,128,255\'
.EE
.sp
or, equivalently,
.sp
.EX
    rg \\-\\-colors \'match:bg:0x0,0x80,0xFF\'
.EE
.sp
Note that the \\fBintense\\fP and \\fBnointense\\fP styles will have no effect when
used alongside these extended color codes.
' }
		.column { '
Show column numbers (1-based). This only shows the column numbers for the first
match on each line. This does not try to account for Unicode. One byte is equal
to one column. This implies \\flag{line-number}.
.sp
When \\flag{only-matching} is used, then the column numbers written correspond
to the start of each match.
' }
		.context { '
Show \\fINUM\\fP lines before and after each match. This is equivalent to
providing both the \\flag{before-context} and \\flag{after-context} flags with
the same value.
.sp
This overrides the \\flag{passthru} flag. The \\flag{after-context} and
\\flag{before-context} flags both partially override this flag, regardless of
the order. For example, \\fB\\-A2 \\-C1\\fP is equivalent to \\fB\\-A2 \\-B1\\fP.
' }
		.context_separator { '
The string used to separate non-contiguous context lines in the output. This is
only used when one of the context flags is used (that is, \\flag{after-context},
\\flag{before-context} or \\flag{context}). Escape sequences like \\fB\\\\x7F\\fP or
\\fB\\\\t\\fP may be used. The default value is \\fB\\-\\-\\fP.
.sp
When the context separator is set to an empty string, then a line break
is still inserted. To completely disable context separators, use the
\\flag-negate{context-separator} flag.
' }
		.count { '
This flag suppresses normal output and shows the number of lines that match
the given patterns for each file searched. Each file containing a match has
its path and count printed on each line. Note that unless \\flag{multiline} is
enabled and the pattern(s) given can match over multiple lines, this reports
the number of lines that match and not the total number of matches. When
multiline mode is enabled and the pattern(s) given can match over multiple
lines, \\flag{count} is equivalent to \\flag{count-matches}.
.sp
If only one file is given to ripgrep, then only the count is printed if there
is a match. The \\flag{with-filename} flag can be used to force printing the
file path in this case. If you need a count to be printed regardless of whether
there is a match, then use \\flag{include-zero}.
.sp
Note that it is possible for this flag to have results inconsistent with
the output of \\flag{files-with-matches}. Notably, by default, ripgrep tries
to avoid searching files with binary data. With this flag, ripgrep needs to
search the entire content of files, which may include binary data. But with
\\flag{files-with-matches}, ripgrep can stop as soon as a match is observed,
which may come well before any binary data. To avoid this inconsistency without
disabling binary detection, use the \\flag{binary} flag.
.sp
This overrides the \\flag{count-matches} flag. Note that when \\flag{count}
is combined with \\flag{only-matching}, then ripgrep behaves as if
\\flag{count-matches} was given.
' }
		.count_matches { '
This flag suppresses normal output and shows the number of individual matches
of the given patterns for each file searched. Each file containing matches has
its path and match count printed on each line. Note that this reports the total
number of individual matches and not the number of lines that match.
.sp
If only one file is given to ripgrep, then only the count is printed if there
is a match. The \\flag{with-filename} flag can be used to force printing the
file path in this case.
.sp
This overrides the \\flag{count} flag. Note that when \\flag{count} is combined
with \\flag{only-matching}, then ripgrep behaves as if \\flag{count-matches} was
given.
' }
		.crlf { '
When enabled, ripgrep will treat CRLF (\\fB\\\\r\\\\n\\fP) as a line terminator
instead of just \\fB\\\\n\\fP.
.sp
Principally, this permits the line anchor assertions \\fB^\\fP and \\fB\$\\fP in
regex patterns to treat CRLF, CR or LF as line terminators instead of just LF.
Note that they will never match between a CR and a LF. CRLF is treated as one
single line terminator.
.sp
When using the default regex engine, CRLF support can also be enabled inside
the pattern with the \\fBR\\fP flag. For example, \\fB(?R:\$)\\fP will match just
before either CR or LF, but never between CR and LF.
.sp
This flag overrides \\flag{null-data}.
' }
		.debug { '
Show debug messages. Please use this when filing a bug report.
.sp
The \\flag{debug} flag is generally useful for figuring out why ripgrep skipped
searching a particular file. The debug messages should mention all files
skipped and why they were skipped.
.sp
To get even more debug output, use the \\flag{trace} flag, which implies
\\flag{debug} along with additional trace data.
' }
		.dfa_size_limit { '
The upper size limit of the regex DFA. The default limit is something generous
for any single pattern or for many smallish patterns. This should only be
changed on very large regex inputs where the (slower) fallback regex engine may
otherwise be used if the limit is reached.
.sp
The input format accepts suffixes of \\fBK\\fP, \\fBM\\fP or \\fBG\\fP which
correspond to kilobytes, megabytes and gigabytes, respectively. If no suffix is
provided the input is treated as bytes.
' }
		.encoding { '
Specify the text encoding that ripgrep will use on all files searched. The
default value is \\fBauto\\fP, which will cause ripgrep to do a best effort
automatic detection of encoding on a per-file basis. Automatic detection in
this case only applies to files that begin with a UTF-8 or UTF-16 byte-order
mark (BOM). No other automatic detection is performed. One can also specify
\\fBnone\\fP which will then completely disable BOM sniffing and always result
in searching the raw bytes, including a BOM if it\'s present, regardless of its
encoding.
.sp
Other supported values can be found in the list of labels here:
\\fIhttps://encoding.spec.whatwg.org/#concept-encoding-get\\fP.
.sp
For more details on encoding and how ripgrep deals with it, see \\fBGUIDE.md\\fP.
.sp
The encoding detection that ripgrep uses can be reverted to its automatic mode
via the \\flag-negate{encoding} flag.
' }
		.engine { '
Specify which regular expression engine to use. When you choose a regex engine,
it applies that choice for every regex provided to ripgrep (e.g., via multiple
\\flag{regexp} or \\flag{file} flags).
.sp
Accepted values are \\fBdefault\\fP, \\fBpcre2\\fP, or \\fBauto\\fP.
.sp
The default value is \\fBdefault\\fP, which is usually the fastest and should be
good for most use cases. The \\fBpcre2\\fP engine is generally useful when you
want to use features such as look-around or backreferences. \\fBauto\\fP will
dynamically choose between supported regex engines depending on the features
used in a pattern on a best effort basis.
.sp
Note that the \\fBpcre2\\fP engine is an optional ripgrep feature. If PCRE2
wasn\'t included in your build of ripgrep, then using this flag will result in
ripgrep printing an error message and exiting.
.sp
This overrides previous uses of the \\flag{pcre2} and \\flag{auto-hybrid-regex}
flags.
' }
		.field_context_separator { '
Set the field context separator. This separator is only used when printing
contextual lines. It is used to delimit file paths, line numbers, columns and
the contextual line itself. The separator may be any number of bytes, including
zero. Escape sequences like \\fB\\\\x7F\\fP or \\fB\\\\t\\fP may be used.
.sp
The \\fB-\\fP character is the default value.
' }
		.field_match_separator { '
Set the field match separator. This separator is only used when printing
matching lines. It is used to delimit file paths, line numbers, columns and the
matching line itself. The separator may be any number of bytes, including zero.
Escape sequences like \\fB\\\\x7F\\fP or \\fB\\\\t\\fP may be used.
.sp
The \\fB:\\fP character is the default value.
' }
		.file { '
Search for patterns from the given file, with one pattern per line. When this
flag is used multiple times or in combination with the \\flag{regexp} flag, then
all patterns provided are searched. Empty pattern lines will match all input
lines, and the newline is not counted as part of the pattern.
.sp
A line is printed if and only if it matches at least one of the patterns.
.sp
When \\fIPATTERNFILE\\fP is \\fB-\\fP, then \\fBstdin\\fP will be read for the
patterns.
.sp
When \\flag{file} or \\flag{regexp} is used, then ripgrep treats all positional
arguments as files or directories to search.
' }
		.files { '
Print each file that would be searched without actually performing the search.
This is useful to determine whether a particular file is being searched or not.
.sp
This overrides \\flag{type-list}.
' }
		.files_with_matches { '
Print only the paths with at least one match and suppress match contents.
.sp
Note that it is possible for this flag to have results inconsistent with the
output of \\flag{count}. Notably, by default, ripgrep tries to avoid searching
files with binary data. With this flag, ripgrep might stop searching before
the binary data is observed. But with \\flag{count}, ripgrep has to search the
entire contents to determine the match count, which means it might see binary
data that causes it to skip searching that file. To avoid this inconsistency
without disabling binary detection, use the \\flag{binary} flag.
.sp
This overrides \\flag{files-without-match}.
' }
		.files_without_match { '
Print the paths that contain zero matches and suppress match contents.
.sp
This overrides \\flag{files-with-matches}.
' }
		.fixed_strings { '
Treat all patterns as literals instead of as regular expressions. When this
flag is used, special regular expression meta characters such as \\fB.(){}*+\\fP
should not need be escaped.
' }
		.follow { '
This flag instructs ripgrep to follow symbolic links while traversing
directories. This behavior is disabled by default. Note that ripgrep will
check for symbolic link loops and report errors if it finds one. ripgrep will
also report errors for broken links. To suppress error messages, use the
\\flag{no-messages} flag.
' }
		.generate { '
This flag instructs ripgrep to generate some special kind of output identified
by \\fIKIND\\fP and then quit without searching. \\fIKIND\\fP can be one of the
following values:
.sp
.TP 15
\\fBman\\fP
Generates a manual page for ripgrep in the \\fBroff\\fP format.
.TP 15
\\fBcomplete\\-bash\\fP
Generates a completion script for the \\fBbash\\fP shell.
.TP 15
\\fBcomplete\\-zsh\\fP
Generates a completion script for the \\fBzsh\\fP shell.
.TP 15
\\fBcomplete\\-fish\\fP
Generates a completion script for the \\fBfish\\fP shell.
.TP 15
\\fBcomplete\\-powershell\\fP
Generates a completion script for PowerShell.
.PP
The output is written to \\fBstdout\\fP. The list above may expand over time.
' }
		.glob { '
Include or exclude files and directories for searching that match the given
glob. This always overrides any other ignore logic. Multiple glob flags may
be used. Globbing rules match \\fB.gitignore\\fP globs. Precede a glob with a
\\fB!\\fP to exclude it. If multiple globs match a file or directory, the glob
given later in the command line takes precedence.
.sp
As an extension, globs support specifying alternatives:
.BI "\\-g \'" ab{c,d}* \'
is equivalent to
.BI "\\-g " "abc " "\\-g " abd.
Empty alternatives like
.BI "\\-g \'" ab{,c} \'
are not currently supported. Note that this syntax extension is also currently
enabled in \\fBgitignore\\fP files, even though this syntax isn\'t supported by
git itself. ripgrep may disable this syntax extension in gitignore files, but
it will always remain available via the \\flag{glob} flag.
.sp
When this flag is set, every file and directory is applied to it to test for
a match. For example, if you only want to search in a particular directory
\\fIfoo\\fP, then
.BI "\\-g " foo
is incorrect because \\fIfoo/bar\\fP does not match
the glob \\fIfoo\\fP. Instead, you should use
.BI "\\-g \'" foo/** \'.
' }
		.glob_case_insensitive { '
Process all glob patterns given with the \\flag{glob} flag case insensitively.
This effectively treats \\flag{glob} as \\flag{iglob}.
' }
		.heading { '
This flag prints the file path above clusters of matches from each file instead
of printing the file path as a prefix for each matched line.
.sp
This is the default mode when printing to a tty.
.sp
When \\fBstdout\\fP is not a tty, then ripgrep will default to the standard
grep-like format. One can force this format in Unix-like environments by
piping the output of ripgrep to \\fBcat\\fP. For example, \\fBrg\\fP \\fIfoo\\fP \\fB|
cat\\fP.
' }
		.help { '
This flag prints the help output for ripgrep.
.sp
Unlike most other flags, the behavior of the short flag, \\fB\\-h\\fP, and the
long flag, \\fB\\-\\-help\\fP, is different. The short flag will show a condensed
help output while the long flag will show a verbose help output. The verbose
help output has complete documentation, where as the condensed help output will
show only a single line for every flag.
' }
		.hidden { '
Search hidden files and directories. By default, hidden files and directories
are skipped. Note that if a hidden file or a directory is whitelisted in
an ignore file, then it will be searched even if this flag isn\'t provided.
Similarly if a hidden file or directory is given explicitly as an argument to
ripgrep.
.sp
A file or directory is considered hidden if its base name starts with a dot
character (\\fB.\\fP). On operating systems which support a "hidden" file
attribute, like Windows, files with this attribute are also considered hidden.
.sp
Note that \\flag{hidden} will include files and folders like \\fB.git\\fP
regardless of \\flag{no-ignore-vcs}. To exclude such paths when using
\\flag{hidden}, you must explicitly ignore them using another flag or ignore
file.
' }
		.hostname_bin { '
This flag controls how ripgrep determines this system\'s hostname. The flag\'s
value should correspond to an executable (either a path or something that can
be found via your system\'s \\fBPATH\\fP environment variable). When set, ripgrep
will run this executable, with no arguments, and treat its output (with leading
and trailing whitespace stripped) as your system\'s hostname.
.sp
When not set (the default, or the empty string), ripgrep will try to
automatically detect your system\'s hostname. On Unix, this corresponds
to calling \\fBgethostname\\fP. On Windows, this corresponds to calling
\\fBGetComputerNameExW\\fP to fetch the system\'s "physical DNS hostname."
.sp
ripgrep uses your system\'s hostname for producing hyperlinks.
' }
		.hyperlink_format { hyperlink_format_doc_long() }
		.i_glob { '
Include or exclude files and directories for searching that match the given
glob. This always overrides any other ignore logic. Multiple glob flags may
be used. Globbing rules match \\fB.gitignore\\fP globs. Precede a glob with a
\\fB!\\fP to exclude it. If multiple globs match a file or directory, the glob
given later in the command line takes precedence. Globs used via this flag are
matched case insensitively.
' }
		.ignore_case { '
When this flag is provided, all patterns will be searched case insensitively.
The case insensitivity rules used by ripgrep\'s default regex engine conform to
Unicode\'s "simple" case folding rules.
.sp
This is a global option that applies to all patterns given to ripgrep.
Individual patterns can still be matched case sensitively by using
inline regex flags. For example, \\fB(?\\-i)abc\\fP will match \\fBabc\\fP
case sensitively even when this flag is used.
.sp
This flag overrides \\flag{case-sensitive} and \\flag{smart-case}.
' }
		.ignore_file { '
Specifies a path to one or more \\fBgitignore\\fP formatted rules files.
These patterns are applied after the patterns found in \\fB.gitignore\\fP,
\\fB.rgignore\\fP and \\fB.ignore\\fP are applied and are matched relative to the
current working directory. That is, files specified via this flag have lower
precedence than files automatically found in the directory tree. Multiple
additional ignore files can be specified by using this flag repeatedly. When
specifying multiple ignore files, earlier files have lower precedence than
later files.
.sp
If you are looking for a way to include or exclude files and directories
directly on the command line, then use \\flag{glob} instead.
' }
		.ignore_file_case_insensitive { '
Process ignore files (\\fB.gitignore\\fP, \\fB.ignore\\fP, etc.) case
insensitively. Note that this comes with a performance penalty and is most
useful on case insensitive file systems (such as Windows).
' }
		.include_zero { '
When used with \\flag{count} or \\flag{count-matches}, this causes ripgrep to
print the number of matches for each file even if there were zero matches. This
is disabled by default but can be enabled to make ripgrep behave more like
grep.
' }
		.invert_match { '
This flag inverts matching. That is, instead of printing lines that match,
ripgrep will print lines that don\'t match.
.sp
Note that this only inverts line-by-line matching. For example, combining this
flag with \\flag{files-with-matches} will emit files that contain any lines
that do not match the patterns given. That\'s not the same as, for example,
\\flag{files-without-match}, which will emit files that do not contain any
matching lines.
' }
		.json { '
Enable printing results in a JSON Lines format.
.sp
When this flag is provided, ripgrep will emit a sequence of messages, each
encoded as a JSON object, where there are five different message types:
.sp
.TP 12
\\fBbegin\\fP
A message that indicates a file is being searched and contains at least one
match.
.TP 12
\\fBend\\fP
A message the indicates a file is done being searched. This message also
include summary statistics about the search for a particular file.
.TP 12
\\fBmatch\\fP
A message that indicates a match was found. This includes the text and offsets
of the match.
.TP 12
\\fBcontext\\fP
A message that indicates a contextual line was found. This includes the text of
the line, along with any match information if the search was inverted.
.TP 12
\\fBsummary\\fP
The final message emitted by ripgrep that contains summary statistics about the
search across all files.
.PP
Since file paths or the contents of files are not guaranteed to be valid
UTF-8 and JSON itself must be representable by a Unicode encoding, ripgrep
will emit all data elements as objects with one of two keys: \\fBtext\\fP or
\\fBbytes\\fP. \\fBtext\\fP is a normal JSON string when the data is valid UTF-8
while \\fBbytes\\fP is the base64 encoded contents of the data.
.sp
The JSON Lines format is only supported for showing search results. It cannot
be used with other flags that emit other types of output, such as \\flag{files},
\\flag{files-with-matches}, \\flag{files-without-match}, \\flag{count} or
\\flag{count-matches}. ripgrep will report an error if any of the aforementioned
flags are used in concert with \\flag{json}.
.sp
Other flags that control aspects of the standard output such as
\\flag{only-matching}, \\flag{heading}, \\flag{replace}, \\flag{max-columns}, etc.,
have no effect when \\flag{json} is set. However, enabling JSON output will
always implicitly and unconditionally enable \\flag{stats}.
.sp
A more complete description of the JSON format used can be found here:
\\fIhttps://docs.rs/grep-printer/*/grep_printer/struct.JSON.html\\fP.
' }
		.line_buffered { '
When enabled, ripgrep will always use line buffering. That is, whenever a
matching line is found, it will be flushed to stdout immediately. This is the
default when ripgrep\'s stdout is connected to a tty, but otherwise, ripgrep
will use block buffering, which is typically faster. This flag forces ripgrep
to use line buffering even if it would otherwise use block buffering. This is
typically useful in shell pipelines, for example:
.sp
.EX
    tail -f something.log | rg foo --line-buffered | rg bar
.EE
.sp
This overrides the \\flag{block-buffered} flag.
' }
		.line_number { '
Show line numbers (1-based).
.sp
This is enabled by default when stdout is connected to a tty.
.sp
This flag can be disabled by \\flag{no-line-number}.
' }
		.line_number_no { '
Suppress line numbers.
.sp
Line numbers are off by default when stdout is not connected to a tty.
.sp
Line numbers can be forcefully turned on by \\flag{line-number}.
' }
		.line_regexp { '
When enabled, ripgrep will only show matches surrounded by line boundaries.
This is equivalent to surrounding every pattern with \\fB^\\fP and \\fB\$\\fP. In
other words, this only prints lines where the entire line participates in a
match.
.sp
This overrides the \\flag{word-regexp} flag.
' }
		.max_columns { '
When given, ripgrep will omit lines longer than this limit in bytes. Instead of
printing long lines, only the number of matches in that line is printed.
.sp
When this flag is omitted or is set to \\fB0\\fP, then it has no effect.
' }
		.max_columns_preview { '
Prints a preview for lines exceeding the configured max column limit.
.sp
When the \\flag{max-columns} flag is used, ripgrep will by default completely
replace any line that is too long with a message indicating that a matching
line was removed. When this flag is combined with \\flag{max-columns}, a preview
of the line (corresponding to the limit size) is shown instead, where the part
of the line exceeding the limit is not shown.
.sp
If the \\flag{max-columns} flag is not set, then this has no effect.
' }
		.max_count { '
Limit the number of matching lines per file searched to \\fINUM\\fP.
.sp
When \\flag{multiline} is used, a single match that spans multiple lines is only
counted once for the purposes of this limit. Multiple matches in a single line
are counted only once, as they would be in non-multiline mode.
.sp
When combined with \\flag{after-context} or \\flag{context}, it\'s possible for
more matches than the maximum to be printed if contextual lines contain a
match.
.sp
Note that \\fB0\\fP is a legal value but not likely to be useful. When used,
ripgrep won\'t search anything.
' }
		.max_depth { '
This flag limits the depth of directory traversal to \\fINUM\\fP levels beyond
the paths given. A value of \\fB0\\fP only searches the explicitly given paths
themselves.
.sp
For example, \\fBrg --max-depth 0 \\fP\\fIdir/\\fP is a no-op because \\fIdir/\\fP
will not be descended into. \\fBrg --max-depth 1 \\fP\\fIdir/\\fP will search only
the direct children of \\fIdir\\fP.
.sp
An alternative spelling for this flag is \\fB\\-\\-maxdepth\\fP.
' }
		.max_filesize { '
Ignore files larger than \\fINUM\\fP in size. This does not apply to directories.
.sp
The input format accepts suffixes of \\fBK\\fP, \\fBM\\fP or \\fBG\\fP which
correspond to kilobytes, megabytes and gigabytes, respectively. If no suffix is
provided the input is treated as bytes.
.sp
Examples: \\fB\\-\\-max-filesize 50K\\fP or \\fB\\-\\-max\\-filesize 80M\\fP.
' }
		.mmap { '
When enabled, ripgrep will search using memory maps when possible. This is
enabled by default when ripgrep thinks it will be faster.
.sp
Memory map searching cannot be used in all circumstances. For example, when
searching virtual files or streams likes \\fBstdin\\fP. In such cases, memory
maps will not be used even when this flag is enabled.
.sp
Note that ripgrep may abort unexpectedly when memory maps are used if it
searches a file that is simultaneously truncated. Users can opt out of this
possibility by disabling memory maps.
' }
		.multiline { '
This flag enable searching across multiple lines.
.sp
When multiline mode is enabled, ripgrep will lift the restriction that a
match cannot include a line terminator. For example, when multiline mode
is not enabled (the default), then the regex \\fB\\\\p{any}\\fP will match any
Unicode codepoint other than \\fB\\\\n\\fP. Similarly, the regex \\fB\\\\n\\fP is
explicitly forbidden, and if you try to use it, ripgrep will return an error.
However, when multiline mode is enabled, \\fB\\\\p{any}\\fP will match any Unicode
codepoint, including \\fB\\\\n\\fP, and regexes like \\fB\\\\n\\fP are permitted.
.sp
An important caveat is that multiline mode does not change the match semantics
of \\fB.\\fP. Namely, in most regex matchers, a \\fB.\\fP will by default match any
character other than \\fB\\\\n\\fP, and this is true in ripgrep as well. In order
to make \\fB.\\fP match \\fB\\\\n\\fP, you must enable the "dot all" flag inside the
regex. For example, both \\fB(?s).\\fP and \\fB(?s:.)\\fP have the same semantics,
where \\fB.\\fP will match any character, including \\fB\\\\n\\fP. Alternatively, the
\\flag{multiline-dotall} flag may be passed to make the "dot all" behavior the
default. This flag only applies when multiline search is enabled.
.sp
There is no limit on the number of the lines that a single match can span.
.sp
\\fBWARNING\\fP: Because of how the underlying regex engine works, multiline
searches may be slower than normal line-oriented searches, and they may also
use more memory. In particular, when multiline mode is enabled, ripgrep
requires that each file it searches is laid out contiguously in memory (either
by reading it onto the heap or by memory-mapping it). Things that cannot be
memory-mapped (such as \\fBstdin\\fP) will be consumed until EOF before searching
can begin. In general, ripgrep will only do these things when necessary.
Specifically, if the \\flag{multiline} flag is provided but the regex does
not contain patterns that would match \\fB\\\\n\\fP characters, then ripgrep
will automatically avoid reading each file into memory before searching it.
Nevertheless, if you only care about matches spanning at most one line, then it
is always better to disable multiline mode.
.sp
This overrides the \\flag{stop-on-nonmatch} flag.
' }
		.multiline_dotall { '
This flag enables "dot all" mode in all regex patterns. This causes \\fB.\\fP to
match line terminators when multiline searching is enabled. This flag has no
effect if multiline searching isn\'t enabled with the \\flag{multiline} flag.
.sp
Normally, a \\fB.\\fP will match any character except line terminators. While
this behavior typically isn\'t relevant for line-oriented matching (since
matches can span at most one line), this can be useful when searching with the
\\flag{multiline} flag. By default, multiline mode runs without "dot all" mode
enabled.
.sp
This flag is generally intended to be used in an alias or your ripgrep config
file if you prefer "dot all" semantics by default. Note that regardless of
whether this flag is used, "dot all" semantics can still be controlled via
inline flags in the regex pattern itself, e.g., \\fB(?s:.)\\fP always enables
"dot all" whereas \\fB(?-s:.)\\fP always disables "dot all". Moreover, you
can use character classes like \\fB\\\\p{any}\\fP to match any Unicode codepoint
regardless of whether "dot all" mode is enabled or not.
' }
		.no_config { '
When set, ripgrep will never read configuration files. When this flag is
present, ripgrep will not respect the \\fBRIPGREP_CONFIG_PATH\\fP environment
variable.
.sp
If ripgrep ever grows a feature to automatically read configuration files in
pre-defined locations, then this flag will also disable that behavior as well.
' }
		.no_ignore { '
When set, ignore files such as \\fB.gitignore\\fP, \\fB.ignore\\fP and
\\fB.rgignore\\fP will not be respected. This implies \\flag{no-ignore-dot},
\\flag{no-ignore-exclude}, \\flag{no-ignore-global}, \\flag{no-ignore-parent} and
\\flag{no-ignore-vcs}.
.sp
This does not imply \\flag{no-ignore-files}, since \\flag{ignore-file} is
specified explicitly as a command line argument.
.sp
When given only once, the \\flag{unrestricted} flag is identical in
behavior to this flag and can be considered an alias. However, subsequent
\\flag{unrestricted} flags have additional effects.
' }
		.no_ignore_dot { '
Don\'t respect filter rules from \\fB.ignore\\fP or \\fB.rgignore\\fP files.
.sp
This does not impact whether ripgrep will ignore files and directories whose
names begin with a dot. For that, see the \\flag{hidden} flag. This flag also
does not impact whether filter rules from \\fB.gitignore\\fP files are respected.
' }
		.no_ignore_exclude { '
Don\'t respect filter rules from files that are manually configured for the repository.
For example, this includes \\fBgit\\fP\'s \\fB.git/info/exclude\\fP.
' }
		.no_ignore_files { '
When set, any \\flag{ignore-file} flags, even ones that come after this flag,
are ignored.
' }
		.no_ignore_global { '
Don\'t respect filter rules from ignore files that come from "global" sources
such as \\fBgit\\fP\'s \\fBcore.excludesFile\\fP configuration option (which
defaults to \\fB\$HOME/.config/git/ignore\\fP).
' }
		.no_ignore_messages { '
When this flag is enabled, all error messages related to parsing ignore files
are suppressed. By default, error messages are printed to stderr. In cases
where these errors are expected, this flag can be used to avoid seeing the
noise produced by the messages.
' }
		.no_ignore_parent { '
When this flag is set, filter rules from ignore files found in parent
directories are not respected. By default, ripgrep will ascend the parent
directories of the current working directory to look for any applicable ignore
files that should be applied. In some cases this may not be desirable.
' }
		.no_ignore_vcs { '
When given, filter rules from source control ignore files (e.g.,
\\fB.gitignore\\fP) are not respected. By default, ripgrep respects \\fBgit\\fP\'s
ignore rules for automatic filtering. In some cases, it may not be desirable
to respect the source control\'s ignore rules and instead only respect rules in
\\fB.ignore\\fP or \\fB.rgignore\\fP.
.sp
Note that this flag does not directly affect the filtering of source control
files or folders that start with a dot (\\fB.\\fP), like \\fB.git\\fP. These are
affected by \\flag{hidden} and its related flags instead.
.sp
This flag implies \\flag{no-ignore-parent} for source control ignore files as
well.
' }
		.no_messages { '
This flag suppresses some error messages. Specifically, messages related to
the failed opening and reading of files. Error messages related to the syntax
of the pattern are still shown.
' }
		.no_pcre_2_unicode { '
DEPRECATED. Use \\flag{no-unicode} instead.
.sp
Note that Unicode mode is enabled by default.
' }
		.no_require_git { '
When this flag is given, source control ignore files such as \\fB.gitignore\\fP
are respected even if no \\fBgit\\fP repository is present.
.sp
By default, ripgrep will only respect filter rules from source control ignore
files when ripgrep detects that the search is executed inside a source control
repository. For example, when a \\fB.git\\fP directory is observed.
.sp
This flag relaxes the default restriction. For example, it might be useful when
the contents of a \\fBgit\\fP repository are stored or copied somewhere, but
where the repository state is absent.
' }
		.no_unicode { '
This flag disables Unicode mode for all patterns given to ripgrep.
.sp
By default, ripgrep will enable "Unicode mode" in all of its regexes. This has
a number of consequences:
.sp
.IP \\(bu 3n
\\fB.\\fP will only match valid UTF-8 encoded Unicode scalar values.
.sp
.IP \\(bu 3n
Classes like \\fB\\\\w\\fP, \\fB\\\\s\\fP, \\fB\\\\d\\fP are all Unicode aware and much
bigger than their ASCII only versions.
.sp
.IP \\(bu 3n
Case insensitive matching will use Unicode case folding.
.sp
.IP \\(bu 3n
A large array of classes like \\fB\\\\p{Emoji}\\fP are available. (Although the
specific set of classes available varies based on the regex engine. In general,
the default regex engine has more classes available to it.)
.sp
.IP \\(bu 3n
Word boundaries (\\fB\\\\b\\fP and \\fB\\\\B\\fP) use the Unicode definition of a word
character.
.PP
In some cases it can be desirable to turn these things off. This flag will do
exactly that. For example, Unicode mode can sometimes have a negative impact
on performance, especially when things like \\fB\\\\w\\fP are used frequently
(including via bounded repetitions like \\fB\\\\w{100}\\fP) when only their ASCII
interpretation is needed.
' }
		.null { '
Whenever a file path is printed, follow it with a \\fBNUL\\fP byte. This includes
printing file paths before matches, and when printing a list of matching files
such as with \\flag{count}, \\flag{files-with-matches} and \\flag{files}. This
option is useful for use with \\fBxargs\\fP.
' }
		.null_data { '
Enabling this flag causes ripgrep to use \\fBNUL\\fP as a line terminator instead
of the default of \\fP\\\\n\\fP.
.sp
This is useful when searching large binary files that would otherwise have
very long lines if \\fB\\\\n\\fP were used as the line terminator. In particular,
ripgrep requires that, at a minimum, each line must fit into memory. Using
\\fBNUL\\fP instead can be a useful stopgap to keep memory requirements low and
avoid OOM (out of memory) conditions.
.sp
This is also useful for processing NUL delimited data, such as that emitted
when using ripgrep\'s \\flag{null} flag or \\fBfind\\fP\'s \\fB\\-\\-print0\\fP flag.
.sp
Using this flag implies \\flag{text}. It also overrides \\flag{crlf}.
' }
		.one_file_system { '
When enabled, ripgrep will not cross file system boundaries relative to where
the search started from.
.sp
Note that this applies to each path argument given to ripgrep. For example, in
the command
.sp
.EX
    rg \\-\\-one\\-file\\-system /foo/bar /quux/baz
.EE
.sp
ripgrep will search both \\fI/foo/bar\\fP and \\fI/quux/baz\\fP even if they are
on different file systems, but will not cross a file system boundary when
traversing each path\'s directory tree.
.sp
This is similar to \\fBfind\\fP\'s \\fB\\-xdev\\fP or \\fB\\-mount\\fP flag.
' }
		.only_matching { '
Print only the matched (non-empty) parts of a matching line, with each such
part on a separate output line.
' }
		.path_separator { '
Set the path separator to use when printing file paths. This defaults to your
platform\'s path separator, which is \\fB/\\fP on Unix and \\fB\\\\\\fP on Windows.
This flag is intended for overriding the default when the environment demands
it (e.g., cygwin). A path separator is limited to a single byte.
.sp
Setting this flag to an empty string reverts it to its default behavior. That
is, the path separator is automatically chosen based on the environment.
' }
		.passthru { '
Print both matching and non-matching lines.
.sp
Another way to achieve a similar effect is by modifying your pattern to match
the empty string. For example, if you are searching using \\fBrg\\fP \\fIfoo\\fP,
then using \\fBrg\\fP \\fB\'^|\\fP\\fIfoo\\fP\\fB\'\\fP instead will emit every line in
every file searched, but only occurrences of \\fIfoo\\fP will be highlighted.
This flag enables the same behavior without needing to modify the pattern.
.sp
An alternative spelling for this flag is \\fB\\-\\-passthrough\\fP.
.sp
This overrides the \\flag{context}, \\flag{after-context} and
\\flag{before-context} flags.
' }
		.pcre_2 { '
When this flag is present, ripgrep will use the PCRE2 regex engine instead of
its default regex engine.
.sp
This is generally useful when you want to use features such as look-around
or backreferences.
.sp
Using this flag is the same as passing \\fB\\-\\-engine=pcre2\\fP. Users may
instead elect to use \\fB\\-\\-engine=auto\\fP to ask ripgrep to automatically
select the right regex engine based on the patterns given. This flag and the
\\flag{engine} flag override one another.
.sp
Note that PCRE2 is an optional ripgrep feature. If PCRE2 wasn\'t included in
your build of ripgrep, then using this flag will result in ripgrep printing
an error message and exiting. PCRE2 may also have worse user experience in
some cases, since it has fewer introspection APIs than ripgrep\'s default
regex engine. For example, if you use a \\fB\\\\n\\fP in a PCRE2 regex without
the \\flag{multiline} flag, then ripgrep will silently fail to match anything
instead of reporting an error immediately (like it does with the default regex
engine).
' }
		.pcre_2_version { '
When this flag is present, ripgrep will print the version of PCRE2 in use,
along with other information, and then exit. If PCRE2 is not available, then
ripgrep will print an error message and exit with an error code.
' }
		.pre { '
For each input \\fIPATH\\fP, this flag causes ripgrep to search the standard
output of \\fICOMMAND\\fP \\fIPATH\\fP instead of the contents of \\fIPATH\\fP.
This option expects the \\fICOMMAND\\fP program to either be a path or to be
available in your \\fBPATH\\fP. Either an empty string \\fICOMMAND\\fP or the
\\fB\\-\\-no\\-pre\\fP flag will disable this behavior.
.sp
.TP 12
\\fBWARNING\\fP
When this flag is set, ripgrep will unconditionally spawn a process for every
file that is searched. Therefore, this can incur an unnecessarily large
performance penalty if you don\'t otherwise need the flexibility offered by this
flag. One possible mitigation to this is to use the \\flag{pre-glob} flag to
limit which files a preprocessor is run with.
.PP
A preprocessor is not run when ripgrep is searching stdin.
.sp
When searching over sets of files that may require one of several
preprocessors, \\fICOMMAND\\fP should be a wrapper program which first classifies
\\fIPATH\\fP based on magic numbers/content or based on the \\fIPATH\\fP name and
then dispatches to an appropriate preprocessor. Each \\fICOMMAND\\fP also has its
standard input connected to \\fIPATH\\fP for convenience.
.sp
For example, a shell script for \\fICOMMAND\\fP might look like:
.sp
.EX
    case "\$1" in
    *.pdf)
        exec pdftotext "\$1" -
        ;;
    *)
        case \$(file "\$1") in
        *Zstandard*)
            exec pzstd -cdq
            ;;
        *)
            exec cat
            ;;
        esac
        ;;
    esac
.EE
.sp
The above script uses \\fBpdftotext\\fP to convert a PDF file to plain text. For
all other files, the script uses the \\fBfile\\fP utility to sniff the type of
the file based on its contents. If it is a compressed file in the Zstandard
format, then \\fBpzstd\\fP is used to decompress the contents to stdout.
.sp
This overrides the \\flag{search-zip} flag.
' }
		.pre_glob { '
This flag works in conjunction with the \\flag{pre} flag. Namely, when one or
more \\flag{pre-glob} flags are given, then only files that match the given set
of globs will be handed to the command specified by the \\flag{pre} flag. Any
non-matching files will be searched without using the preprocessor command.
.sp
This flag is useful when searching many files with the \\flag{pre} flag.
Namely, it provides the ability to avoid process overhead for files that
don\'t need preprocessing. For example, given the following shell script,
\\fIpre-pdftotext\\fP:
.sp
.EX
    #!/bin/sh
    pdftotext "\$1" -
.EE
.sp
then it is possible to use \\fB\\-\\-pre\\fP \\fIpre-pdftotext\\fP
\\fB\\-\\-pre\\-glob\\fP \'\\fI*.pdf\\fP\' to make it so ripgrep only executes
the \\fIpre-pdftotext\\fP command on files with a \\fI.pdf\\fP extension.
.sp
Multiple \\flag{pre-glob} flags may be used. Globbing rules match
\\fBgitignore\\fP globs. Precede a glob with a \\fB!\\fP to exclude it.
.sp
This flag has no effect if the \\flag{pre} flag is not used.
' }
		.pretty { '
This is a convenience alias for \\fB\\-\\-color=always \\-\\-heading
\\-\\-line\\-number\\fP. This flag is useful when you still want pretty output even
if you\'re piping ripgrep to another program or file. For example: \\fBrg -p
\\fP\\fIfoo\\fP \\fB| less -R\\fP.
' }
		.quiet { '
Do not print anything to stdout. If a match is found in a file, then ripgrep
will stop searching. This is useful when ripgrep is used only for its exit code
(which will be an error code if no matches are found).
.sp
When \\flag{files} is used, ripgrep will stop finding files after finding the
first file that does not match any ignore rules.
' }
		.regex_size_limit { '
The size limit of the compiled regex, where the compiled regex generally
corresponds to a single object in memory that can match all of the patterns
provided to ripgrep. The default limit is generous enough that most reasonable
patterns (or even a small number of them) should fit.
.sp
This useful to change when you explicitly want to let ripgrep spend potentially
much more time and/or memory building a regex matcher.
.sp
The input format accepts suffixes of \\fBK\\fP, \\fBM\\fP or \\fBG\\fP which
correspond to kilobytes, megabytes and gigabytes, respectively. If no suffix is
provided the input is treated as bytes.
' }
		.regexp { '
A pattern to search for. This option can be provided multiple times, where
all patterns given are searched, in addition to any patterns provided by
\\flag{file}. Lines matching at least one of the provided patterns are printed.
This flag can also be used when searching for patterns that start with a dash.
.sp
For example, to search for the literal \\fB\\-foo\\fP:
.sp
.EX
    rg \\-e \\-foo
.EE
.sp
You can also use the special \\fB\\-\\-\\fP delimiter to indicate that no more
flags will be provided. Namely, the following is equivalent to the above:
.sp
.EX
    rg \\-\\- \\-foo
.EE
.sp
When \\flag{file} or \\flag{regexp} is used, then ripgrep treats all positional
arguments as files or directories to search.
' }
		.replace { '
Replaces every match with the text given when printing results. Neither this
flag nor any other ripgrep flag will modify your files.
.sp
Capture group indices (e.g., \\fB\$\\fP\\fI5\\fP) and names (e.g., \\fB\$\\fP\\fIfoo\\fP)
are supported in the replacement string. Capture group indices are numbered
based on the position of the opening parenthesis of the group, where the
leftmost such group is \\fB\$\\fP\\fI1\\fP. The special \\fB\$\\fP\\fI0\\fP group
corresponds to the entire match.
.sp
The name of a group is formed by taking the longest string of letters, numbers
and underscores (i.e. \\fB[_0-9A-Za-z]\\fP) after the \\fB\$\\fP. For example,
\\fB\$\\fP\\fI1a\\fP will be replaced with the group named \\fI1a\\fP, not the
group at index \\fI1\\fP. If the group\'s name contains characters that aren\'t
letters, numbers or underscores, or you want to immediately follow the group
with another string, the name should be put inside braces. For example,
\\fB\${\\fP\\fI1\\fP\\fB}\\fP\\fIa\\fP will take the content of the group at index
\\fI1\\fP and append \\fIa\\fP to the end of it.
.sp
If an index or name does not refer to a valid capture group, it will be
replaced with an empty string.
.sp
In shells such as Bash and zsh, you should wrap the pattern in single quotes
instead of double quotes. Otherwise, capture group indices will be replaced by
expanded shell variables which will most likely be empty.
.sp
To write a literal \\fB\$\\fP, use \\fB\$\$\\fP.
.sp
Note that the replacement by default replaces each match, and not the entire
line. To replace the entire line, you should match the entire line.
.sp
This flag can be used with the \\flag{only-matching} flag.
' }
		.search_zip { '
This flag instructs ripgrep to search in compressed files. Currently gzip,
bzip2, xz, LZ4, LZMA, Brotli and Zstd files are supported. This option expects
the decompression binaries (such as \\fBgzip\\fP) to be available in your
\\fBPATH\\fP. If the required binaries are not found, then ripgrep will not
emit an error messages by default. Use the \\flag{debug} flag to see more
information.
.sp
Note that this flag does not make ripgrep search archive formats as directory
trees. It only makes ripgrep detect compressed files and then decompress them
before searching their contents as it would any other file.
.sp
This overrides the \\flag{pre} flag.
' }
		.smart_case { '
This flag instructs ripgrep to searches case insensitively if the pattern is
all lowercase. Otherwise, ripgrep will search case sensitively.
.sp
A pattern is considered all lowercase if both of the following rules hold:
.sp
.IP \\(bu 3n
First, the pattern contains at least one literal character. For example,
\\fBa\\\\w\\fP contains a literal (\\fBa\\fP) but just \\fB\\\\w\\fP does not.
.sp
.IP \\(bu 3n
Second, of the literals in the pattern, none of them are considered to be
uppercase according to Unicode. For example, \\fBfoo\\\\pL\\fP has no uppercase
literals but \\fBFoo\\\\pL\\fP does.
.PP
This overrides the \\flag{case-sensitive} and \\flag{ignore-case} flags.
' }
		.sort_files { '
DEPRECATED. Use \\fB\\-\\-sort=path\\fP instead.
.sp
This flag instructs ripgrep to sort search results by file path
lexicographically in ascending order. Note that this currently disables all
parallelism and runs search in a single thread.
.sp
This flag overrides \\flag{sort} and \\flag{sortr}.
' }
		.sort { '
This flag enables sorting of results in ascending order. The possible values
for this flag are:
.sp
.TP 12
\\fBnone\\fP
(Default) Do not sort results. Fastest. Can be multi-threaded.
.TP 12
\\fBpath\\fP
Sort by file path. Always single-threaded. The order is determined by sorting
files in each directory entry during traversal. This means that given the files
\\fBa/b\\fP and \\fBa+\\fP, the latter will sort after the former even though
\\fB+\\fP would normally sort before \\fB/\\fP.
.TP 12
\\fBmodified\\fP
Sort by the last modified time on a file. Always single-threaded.
.TP 12
\\fBaccessed\\fP
Sort by the last accessed time on a file. Always single-threaded.
.TP 12
\\fBcreated\\fP
Sort by the creation time on a file. Always single-threaded.
.PP
If the chosen (manually or by-default) sorting criteria isn\'t available on your
system (for example, creation time is not available on ext4 file systems), then
ripgrep will attempt to detect this, print an error and exit without searching.
.sp
To sort results in reverse or descending order, use the \\flag{sortr} flag.
Also, this flag overrides \\flag{sortr}.
.sp
Note that sorting results currently always forces ripgrep to abandon
parallelism and run in a single thread.
' }
		.sortr { '
This flag enables sorting of results in descending order. The possible values
for this flag are:
.sp
.TP 12
\\fBnone\\fP
(Default) Do not sort results. Fastest. Can be multi-threaded.
.TP 12
\\fBpath\\fP
Sort by file path. Always single-threaded. The order is determined by sorting
files in each directory entry during traversal. This means that given the files
\\fBa/b\\fP and \\fBa+\\fP, the latter will sort before the former even though
\\fB+\\fP would normally sort after \\fB/\\fP when doing a reverse lexicographic
sort.
.TP 12
\\fBmodified\\fP
Sort by the last modified time on a file. Always single-threaded.
.TP 12
\\fBaccessed\\fP
Sort by the last accessed time on a file. Always single-threaded.
.TP 12
\\fBcreated\\fP
Sort by the creation time on a file. Always single-threaded.
.PP
If the chosen (manually or by-default) sorting criteria isn\'t available on your
system (for example, creation time is not available on ext4 file systems), then
ripgrep will attempt to detect this, print an error and exit without searching.
.sp
To sort results in ascending order, use the \\flag{sort} flag. Also, this flag
overrides \\flag{sort}.
.sp
Note that sorting results currently always forces ripgrep to abandon
parallelism and run in a single thread.
' }
		.stats { '
When enabled, ripgrep will print aggregate statistics about the search. When
this flag is present, ripgrep will print at least the following stats to
stdout at the end of the search: number of matched lines, number of files with
matches, number of files searched, and the time taken for the entire search to
complete.
.sp
This set of aggregate statistics may expand over time.
.sp
This flag is always and implicitly enabled when \\flag{json} is used.
.sp
Note that this flag has no effect if \\flag{files}, \\flag{files-with-matches} or
\\flag{files-without-match} is passed.
' }
		.stop_on_nonmatch { '
Enabling this option will cause ripgrep to stop reading a file once it
encounters a non-matching line after it has encountered a matching line.
This is useful if it is expected that all matches in a given file will be on
sequential lines, for example due to the lines being sorted.
.sp
This overrides the \\flag{multiline} flag.
' }
		.text { '
This flag instructs ripgrep to search binary files as if they were text. When
this flag is present, ripgrep\'s binary file detection is disabled. This means
that when a binary file is searched, its contents may be printed if there is
a match. This may cause escape codes to be printed that alter the behavior of
your terminal.
.sp
When binary file detection is enabled, it is imperfect. In general, it uses
a simple heuristic. If a \\fBNUL\\fP byte is seen during search, then the file
is considered binary and searching stops (unless this flag is present).
Alternatively, if the \\flag{binary} flag is used, then ripgrep will only quit
when it sees a \\fBNUL\\fP byte after it sees a match (or searches the entire
file).
.sp
This flag overrides the \\flag{binary} flag.
' }
		.threads { '
This flag sets the approximate number of threads to use. A value of \\fB0\\fP
(which is the default) causes ripgrep to choose the thread count using
heuristics.
' }
		.trace { '
Show trace messages. This shows even more detail than the \\flag{debug}
flag. Generally, one should only use this if \\flag{debug} doesn\'t emit the
information you\'re looking for.
' }
		.trim { '
When set, all ASCII whitespace at the beginning of each line printed will be
removed.
' }
		.type { '
This flag limits ripgrep to searching files matching \\fITYPE\\fP. Multiple
\\flag{type} flags may be provided.
.sp
This flag supports the special value \\fBall\\fP, which will behave as if
\\flag{type} was provided for every file type supported by ripgrep (including
any custom file types). The end result is that \\fB\\-\\-type=all\\fP causes
ripgrep to search in "whitelist" mode, where it will only search files it
recognizes via its type definitions.
.sp
Note that this flag has lower precedence than both the \\flag{glob} flag and
any rules found in ignore files.
.sp
To see the list of available file types, use the \\flag{type-list} flag.
' }
		.type_add { '
This flag adds a new glob for a particular file type. Only one glob can be
added at a time. Multiple \\flag{type-add} flags can be provided. Unless
\\flag{type-clear} is used, globs are added to any existing globs defined inside
of ripgrep.
.sp
Note that this must be passed to every invocation of ripgrep. Type settings are
not persisted. See \\fBCONFIGURATION FILES\\fP for a workaround.
.sp
Example:
.sp
.EX
    rg \\-\\-type\\-add \'foo:*.foo\' -tfoo \\fIPATTERN\\fP
.EE
.sp
This flag can also be used to include rules from other types with the special
include directive. The include directive permits specifying one or more other
type names (separated by a comma) that have been defined and its rules will
automatically be imported into the type specified. For example, to create a
type called src that matches C++, Python and Markdown files, one can use:
.sp
.EX
    \\-\\-type\\-add \'src:include:cpp,py,md\'
.EE
.sp
Additional glob rules can still be added to the src type by using this flag
again:
.sp
.EX
    \\-\\-type\\-add \'src:include:cpp,py,md\' \\-\\-type\\-add \'src:*.foo\'
.EE
.sp
Note that type names must consist only of Unicode letters or numbers.
Punctuation characters are not allowed.
' }
		.type_clear { '
Clear the file type globs previously defined for \\fITYPE\\fP. This clears any
previously defined globs for the \\fITYPE\\fP, but globs can be added after this
flag.
.sp
Note that this must be passed to every invocation of ripgrep. Type settings are
not persisted. See \\fBCONFIGURATION FILES\\fP for a workaround.
' }
		.type_not { '
Do not search files matching \\fITYPE\\fP. Multiple \\flag{type-not} flags may be
provided. Use the \\flag{type-list} flag to list all available types.
.sp
This flag supports the special value \\fBall\\fP, which will behave
as if \\flag{type-not} was provided for every file type supported by
ripgrep (including any custom file types). The end result is that
\\fB\\-\\-type\\-not=all\\fP causes ripgrep to search in "blacklist" mode, where it
will only search files that are unrecognized by its type definitions.
.sp
To see the list of available file types, use the \\flag{type-list} flag.
' }
		.type_list { '
Show all supported file types and their corresponding globs. This takes any
\\flag{type-add} and \\flag{type-clear} flags given into account. Each type is
printed on its own line, followed by a \\fB:\\fP and then a comma-delimited list
of globs for that type on the same line.
' }
		.unrestricted { '
This flag reduces the level of "smart" filtering. Repeated uses (up to 3) reduces
the filtering even more. When repeated three times, ripgrep will search every
file in a directory tree.
.sp
A single \\flag{unrestricted} flag is equivalent to \\flag{no-ignore}. Two
\\flag{unrestricted} flags is equivalent to \\flag{no-ignore} \\flag{hidden}.
Three \\flag{unrestricted} flags is equivalent to \\flag{no-ignore} \\flag{hidden}
\\flag{binary}.
.sp
The only filtering ripgrep still does when \\fB-uuu\\fP is given is to skip
symbolic links and to avoid printing matches from binary files. Symbolic links
can be followed via the \\flag{follow} flag, and binary files can be treated as
text files via the \\flag{text} flag.
' }
		.version { '
This flag prints ripgrep\'s version. This also may print other relevant
information, such as the presence of target specific optimizations and the
\\fBgit\\fP revision that this build of ripgrep was compiled from.
' }
		.vimgrep { '
This flag instructs ripgrep to print results with every match on its own line,
including line numbers and column numbers.
.sp
With this option, a line with more than one match will be printed in its
entirety more than once. For that reason, the total amount of output as a
result of this flag can be quadratic in the size of the input. For example,
if the pattern matches every byte in an input file, then each line will be
repeated for every byte matched. For this reason, users should only use this
flag when there is no other choice. Editor integrations should prefer some
other way of reading results from ripgrep, such as via the \\flag{json} flag.
One alternative to avoiding exorbitant memory usage is to force ripgrep into
single threaded mode with the \\flag{threads} flag. Note though that this will
not impact the total size of the output, just the heap memory that ripgrep will
use.
' }
		.with_filename { '
This flag instructs ripgrep to print the file path for each matching line.
This is the default when more than one file is searched. If \\flag{heading} is
enabled (the default when printing to a tty), the file path will be shown above
clusters of matches from each file; otherwise, the file name will be shown as a
prefix for each matched line.
.sp
This flag overrides \\flag{no-filename}.
' }
		.with_filename_no { '
This flag instructs ripgrep to never print the file path with each matching
line. This is the default when ripgrep is explicitly instructed to search one
file or stdin.
.sp
This flag overrides \\flag{with-filename}.
' }
		.word_regexp { '
When enabled, ripgrep will only show matches surrounded by word boundaries.
This is equivalent to surrounding every pattern with \\fB\\\\b{start-half}\\fP and
\\fB\\\\b{end-half}\\fP. These are a custom syntax from ripgrep\'s default regex
engine that, unlike \\fB\\\\b\\fP, doesn\'t require matching a word character on one
side. That is, \\fB\\\\b{start-half}\\fP corresponds to matching \\fB\\\\W|\\\\A\\fP on
the left and \\fB\\\\b{end-half}\\fP corresponds to matching \\fB\\\\W|\\\\z\\fP on the
right.
.sp
This overrides the \\flag{line-regexp} flag.
' }
	}
}

pub fn (id FlagId) doc_choices() []string {
	return match id {
		.after_context { []string{} }
		.auto_hybrid_regex { []string{} }
		.before_context { []string{} }
		.binary { []string{} }
		.block_buffered { []string{} }
		.byte_offset { []string{} }
		.case_sensitive { []string{} }
		.color { ['never', 'auto', 'always', 'ansi'] }
		.colors { []string{} }
		.column { []string{} }
		.context { []string{} }
		.context_separator { []string{} }
		.count { []string{} }
		.count_matches { []string{} }
		.crlf { []string{} }
		.debug { []string{} }
		.dfa_size_limit { []string{} }
		.encoding { []string{} }
		.engine { ['default', 'pcre2', 'auto'] }
		.field_context_separator { []string{} }
		.field_match_separator { []string{} }
		.file { []string{} }
		.files { []string{} }
		.files_with_matches { []string{} }
		.files_without_match { []string{} }
		.fixed_strings { []string{} }
		.follow { []string{} }
		.generate { ['man', 'complete-bash', 'complete-zsh', 'complete-fish', 'complete-powershell'] }
		.glob { []string{} }
		.glob_case_insensitive { []string{} }
		.heading { []string{} }
		.help { []string{} }
		.hidden { []string{} }
		.hostname_bin { []string{} }
		.hyperlink_format { hyperlink_choices() }
		.i_glob { []string{} }
		.ignore_case { []string{} }
		.ignore_file { []string{} }
		.ignore_file_case_insensitive { []string{} }
		.include_zero { []string{} }
		.invert_match { []string{} }
		.json { []string{} }
		.line_buffered { []string{} }
		.line_number { []string{} }
		.line_number_no { []string{} }
		.line_regexp { []string{} }
		.max_columns { []string{} }
		.max_columns_preview { []string{} }
		.max_count { []string{} }
		.max_depth { []string{} }
		.max_filesize { []string{} }
		.mmap { []string{} }
		.multiline { []string{} }
		.multiline_dotall { []string{} }
		.no_config { []string{} }
		.no_ignore { []string{} }
		.no_ignore_dot { []string{} }
		.no_ignore_exclude { []string{} }
		.no_ignore_files { []string{} }
		.no_ignore_global { []string{} }
		.no_ignore_messages { []string{} }
		.no_ignore_parent { []string{} }
		.no_ignore_vcs { []string{} }
		.no_messages { []string{} }
		.no_pcre_2_unicode { []string{} }
		.no_require_git { []string{} }
		.no_unicode { []string{} }
		.null { []string{} }
		.null_data { []string{} }
		.one_file_system { []string{} }
		.only_matching { []string{} }
		.path_separator { []string{} }
		.passthru { []string{} }
		.pcre_2 { []string{} }
		.pcre_2_version { []string{} }
		.pre { []string{} }
		.pre_glob { []string{} }
		.pretty { []string{} }
		.quiet { []string{} }
		.regex_size_limit { []string{} }
		.regexp { []string{} }
		.replace { []string{} }
		.search_zip { []string{} }
		.smart_case { []string{} }
		.sort_files { []string{} }
		.sort { ['none', 'path', 'modified', 'accessed', 'created'] }
		.sortr { ['none', 'path', 'modified', 'accessed', 'created'] }
		.stats { []string{} }
		.stop_on_nonmatch { []string{} }
		.text { []string{} }
		.threads { []string{} }
		.trace { []string{} }
		.trim { []string{} }
		.type { []string{} }
		.type_add { []string{} }
		.type_clear { []string{} }
		.type_not { []string{} }
		.type_list { []string{} }
		.unrestricted { []string{} }
		.version { []string{} }
		.vimgrep { []string{} }
		.with_filename { []string{} }
		.with_filename_no { []string{} }
		.word_regexp { []string{} }
	}
}

pub fn (id FlagId) completion_type() CompletionType {
	return match id {
		.after_context { .other }
		.auto_hybrid_regex { .other }
		.before_context { .other }
		.binary { .other }
		.block_buffered { .other }
		.byte_offset { .other }
		.case_sensitive { .other }
		.color { .other }
		.colors { .other }
		.column { .other }
		.context { .other }
		.context_separator { .other }
		.count { .other }
		.count_matches { .other }
		.crlf { .other }
		.debug { .other }
		.dfa_size_limit { .other }
		.encoding { .encoding }
		.engine { .other }
		.field_context_separator { .other }
		.field_match_separator { .other }
		.file { .filename }
		.files { .other }
		.files_with_matches { .other }
		.files_without_match { .other }
		.fixed_strings { .other }
		.follow { .other }
		.generate { .other }
		.glob { .other }
		.glob_case_insensitive { .other }
		.heading { .other }
		.help { .other }
		.hidden { .other }
		.hostname_bin { .executable }
		.hyperlink_format { .other }
		.i_glob { .other }
		.ignore_case { .other }
		.ignore_file { .filename }
		.ignore_file_case_insensitive { .other }
		.include_zero { .other }
		.invert_match { .other }
		.json { .other }
		.line_buffered { .other }
		.line_number { .other }
		.line_number_no { .other }
		.line_regexp { .other }
		.max_columns { .other }
		.max_columns_preview { .other }
		.max_count { .other }
		.max_depth { .other }
		.max_filesize { .other }
		.mmap { .other }
		.multiline { .other }
		.multiline_dotall { .other }
		.no_config { .other }
		.no_ignore { .other }
		.no_ignore_dot { .other }
		.no_ignore_exclude { .other }
		.no_ignore_files { .other }
		.no_ignore_global { .other }
		.no_ignore_messages { .other }
		.no_ignore_parent { .other }
		.no_ignore_vcs { .other }
		.no_messages { .other }
		.no_pcre_2_unicode { .other }
		.no_require_git { .other }
		.no_unicode { .other }
		.null { .other }
		.null_data { .other }
		.one_file_system { .other }
		.only_matching { .other }
		.path_separator { .other }
		.passthru { .other }
		.pcre_2 { .other }
		.pcre_2_version { .other }
		.pre { .executable }
		.pre_glob { .other }
		.pretty { .other }
		.quiet { .other }
		.regex_size_limit { .other }
		.regexp { .other }
		.replace { .other }
		.search_zip { .other }
		.smart_case { .other }
		.sort_files { .other }
		.sort { .other }
		.sortr { .other }
		.stats { .other }
		.stop_on_nonmatch { .other }
		.text { .other }
		.threads { .other }
		.trace { .other }
		.trim { .other }
		.type { .filetype }
		.type_add { .other }
		.type_clear { .other }
		.type_not { .filetype }
		.type_list { .other }
		.unrestricted { .other }
		.version { .other }
		.vimgrep { .other }
		.with_filename { .other }
		.with_filename_no { .other }
		.word_regexp { .other }
		else { .other }
	}
}

fn hyperlink_format_doc_long() string {
	return 'Set the format of hyperlinks to use when printing results. Hyperlinks make
certain elements of ripgrep\'s output, such as file paths, clickable. This
generally only works in terminal emulators that support OSC-8 hyperlinks. For
example, the format Bfile://{host}{path}P will emit an RFC 8089 hyperlink.
To see the format that ripgrep is using, pass the lag{debug} flag.
.sp
Alternatively, a format string may correspond to one of the following aliases:
default, none, cursor, file, grep+, kitty, macvim, textmate, vscode,
vscode-insiders, vscodium.
The alias will be replaced with a format string that is intended to work for
the corresponding application.
.sp
The following variables are available in the format string:
.sp
.TP 12
B{path}P
Required. This is replaced with a path to a matching file. The path is
guaranteed to be absolute and percent encoded such that it is valid to put into
a URI. Note that a path is guaranteed to start with a /.
.TP 12
B{host}P
Optional. This is replaced with your system\'s hostname. On Unix, this
corresponds to calling BgethostnameP. On Windows, this corresponds to
calling BGetComputerNameExWP to fetch the system\'s "physical DNS hostname."
Alternatively, if lag{hostname-bin} was provided, then the hostname returned
from the output of that program will be returned. If no hostname could be
found, then this variable is replaced with the empty string.
.TP 12
B{line}P
Optional. If appropriate, this is replaced with the line number of a match. If
no line number is available (for example, if B\\-\\-no\\-line\\-numberP was
given), then it is automatically replaced with the value 1.
.TP 12
B{column}P
Optional, but requires the presence of B{line}P. If appropriate, this is
replaced with the column number of a match. If no column number is available
(for example, if B\\-\\-no\\-columnP was given), then it is automatically
replaced with the value 1.
.TP 12
B{wslprefix}P
Optional. This is a special value that is set to
Bwsl\$/PIWSL_DISTRO_NAMEP, where IWSL_DISTRO_NAMEP corresponds to
the value of the equivalent environment variable. If the system is not Unix
or if the IWSL_DISTRO_NAMEP environment variable is not set, then this is
replaced with the empty string.
.PP
A format string may be empty. An empty format string is equivalent to the
BnoneP alias. In this case, hyperlinks will be disabled.
.sp
At present, ripgrep does not enable hyperlinks by default. Users must opt into
them. If you aren\'t sure what format to use, try BdefaultP.
.sp
Like colors, when ripgrep detects that stdout is not connected to a tty, then
hyperlinks are automatically disabled, regardless of the value of this flag.
Users can pass B\\-\\-color=alwaysP to forcefully emit hyperlinks.
.sp
Note that hyperlinks are only written when a path is also in the output
and colors are enabled. To write hyperlinks without colors, you\'ll need to
configure ripgrep to not colorize anything without actually disabling all ANSI
escape codes completely:
.sp
.EX
    \\-\\-colors \'path:none\' \\
    \\-\\-colors \'line:none\' \\
    \\-\\-colors \'column:none\' \\
    \\-\\-colors \'match:none\'
.EE
.sp
ripgrep works this way because it treats the lag{color} flag as a proxy for
whether ANSI escape codes should be used at all. This means that environment
variables like BNO_COLOR=1P and BTERM=dumbP not only disable colors,
but hyperlinks as well. Similarly, colors and hyperlinks are disabled when
ripgrep is not writing to a tty. (Unless one forces the issue by setting
B\\-\\-color=alwaysP.)
.sp
If you\'re searching a file directly, for example:
.sp
.EX
    rg foo path/to/file
.EE
.sp
then hyperlinks will not be emitted since the path given does not appear
in the output. To make the path appear, and thus also a hyperlink, use the
lag{with-filename} flag.
.sp
For more information on hyperlinks in terminal emulators, see:
https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda'
}

pub fn (id FlagId) update(v FlagValue, mut args LowArgs) ! {
	match id {
		.after_context {
			args.context.set_after(parse_usize(v.unwrap_value())!)
		}
		.auto_hybrid_regex {
			args.engine = if v.unwrap_switch() { .auto } else { .default }
		}
		.before_context {
			args.context.set_before(parse_usize(v.unwrap_value())!)
		}
		.binary {
			args.binary = if v.unwrap_switch() { .search_and_suppress } else { .auto }
		}
		.block_buffered {
			args.buffer = if v.unwrap_switch() { .block } else { .auto }
		}
		.byte_offset {
			args.byte_offset = v.unwrap_switch()
		}
		.case_sensitive {
			assert v.unwrap_switch()
			args.case = .sensitive
		}
		.color {
			value := v.unwrap_value()
			args.color = match value {
						'never' { .never }
						'auto' { .auto }
						'always' { .always }
						'ansi' { .ansi }
						else { return error("choice '${value}' is unrecognized") }
					}
		}
		.colors {
			value := v.unwrap_value()
			args.colors << parse_user_color_spec(value)!
		}
		.column {
			args.column = v.unwrap_switch()
		}
		.context {
			args.context.set_both(parse_usize(v.unwrap_value())!)
		}
		.context_separator {
			if v.kind == .switch_value {
						if v.switch_value {
							panic('flag can only be disabled')
						}
						args.context_separator = disabled_context_separator()
					} else {
						args.context_separator = new_context_separator(v.value)!
					}
		}
		.count {
			assert v.unwrap_switch()
			args.mode.update(mode_search(.count))
		}
		.count_matches {
			assert v.unwrap_switch()
			args.mode.update(mode_search(.count_matches))
		}
		.crlf {
			args.crlf = v.unwrap_switch()
			if args.crlf {
						args.null_data = false
					}
		}
		.debug {
			assert v.unwrap_switch()
			args.logging = .debug
		}
		.dfa_size_limit {
			args.dfa_size_limit = parse_human_readable_usize(v.unwrap_value())!
		}
		.encoding {
			if v.kind == .switch_value {
						assert !v.switch_value
						args.encoding = encoding_auto()
						return
					}
			label := v.value
			args.encoding = match label {
						'auto' { encoding_auto() }
						'none' { encoding_disabled() }
						else { encoding_some(new_encoding(label)!) }
					}
		}
		.engine {
			value := v.unwrap_value()
			args.engine = match value {
						'default' { .default }
						'pcre2' { .pcre2 }
						'auto' { .auto }
						else { return error("unrecognized regex engine '${value}'") }
					}
		}
		.field_context_separator {
			args.field_context_separator = new_field_context_separator(v.unwrap_value())!
		}
		.field_match_separator {
			args.field_match_separator = new_field_match_separator(v.unwrap_value())!
		}
		.file {
			path := v.unwrap_value()
			args.patterns << pattern_file(path)
		}
		.files {
			assert v.unwrap_switch()
			args.mode.update(mode_files())
		}
		.files_with_matches {
			assert v.unwrap_switch()
			args.mode.update(mode_search(.files_with_matches))
		}
		.files_without_match {
			assert v.unwrap_switch()
			args.mode.update(mode_search(.files_without_match))
		}
		.fixed_strings {
			args.fixed_strings = v.unwrap_switch()
		}
		.follow {
			args.follow = v.unwrap_switch()
		}
		.generate {
			value := v.unwrap_value()
			genmode := match value {
						'man' { GenerateMode.man }
						'complete-bash' { GenerateMode.complete_bash }
						'complete-zsh' { GenerateMode.complete_zsh }
						'complete-fish' { GenerateMode.complete_fish }
						'complete-powershell' { GenerateMode.complete_powershell }
						else { return error("choice '${value}' is unrecognized") }
					}
			args.mode.update(mode_generate(genmode))
		}
		.glob {
			args.globs << v.unwrap_value()
		}
		.glob_case_insensitive {
			args.glob_case_insensitive = v.unwrap_switch()
		}
		.heading {
			args.heading = v.unwrap_switch()
		}
		.help {
			assert v.unwrap_switch()
		}
		.hidden {
			args.hidden = v.unwrap_switch()
		}
		.hostname_bin {
			path := v.unwrap_value()
			args.hostname_bin = if path == '' { none } else { path }
		}
		.hyperlink_format {
			args.hyperlink_format = parse_hyperlink_format(v.unwrap_value())!
		}
		.i_glob {
			args.iglobs << v.unwrap_value()
		}
		.ignore_case {
			assert v.unwrap_switch()
			args.case = .insensitive
		}
		.ignore_file {
			path := v.unwrap_value()
			args.ignore_file << path
		}
		.ignore_file_case_insensitive {
			args.ignore_file_case_insensitive = v.unwrap_switch()
		}
		.include_zero {
			args.include_zero = v.unwrap_switch()
		}
		.invert_match {
			args.invert_match = v.unwrap_switch()
		}
		.json {
			if v.unwrap_switch() {
						args.mode.update(mode_search(.json))
					} else if args.mode.kind == .search && args.mode.search == .json {
						args.mode.update(mode_search(.standard))
					}
		}
		.line_buffered {
			args.buffer = if v.unwrap_switch() { .line } else { .auto }
		}
		.line_number {
			assert v.unwrap_switch()
			args.line_number = true
		}
		.line_number_no {
			assert v.unwrap_switch()
			args.line_number = false
		}
		.line_regexp {
			assert v.unwrap_switch()
			args.boundary = .line
		}
		.max_columns {
			max := parse_u64(v.unwrap_value())!
			args.max_columns = if max == 0 { none } else { max }
		}
		.max_columns_preview {
			args.max_columns_preview = v.unwrap_switch()
		}
		.max_count {
			args.max_count = parse_u64(v.unwrap_value())!
		}
		.max_depth {
			args.max_depth = parse_usize(v.unwrap_value())!
		}
		.max_filesize {
			args.max_filesize = parse_human_readable_u64(v.unwrap_value())!
		}
		.mmap {
			args.mmap = if v.unwrap_switch() { .always_try_mmap } else { .never }
		}
		.multiline {
			args.multiline = v.unwrap_switch()
			if args.multiline {
						args.stop_on_nonmatch = false
					}
		}
		.multiline_dotall {
			args.multiline_dotall = v.unwrap_switch()
		}
		.no_config {
			assert v.unwrap_switch()
			args.no_config = true
		}
		.no_ignore {
			yes := v.unwrap_switch()
			args.no_ignore_dot = yes
			args.no_ignore_exclude = yes
			args.no_ignore_global = yes
			args.no_ignore_parent = yes
			args.no_ignore_vcs = yes
		}
		.no_ignore_dot {
			args.no_ignore_dot = v.unwrap_switch()
		}
		.no_ignore_exclude {
			args.no_ignore_exclude = v.unwrap_switch()
		}
		.no_ignore_files {
			args.no_ignore_files = v.unwrap_switch()
		}
		.no_ignore_global {
			args.no_ignore_global = v.unwrap_switch()
		}
		.no_ignore_messages {
			args.no_ignore_messages = v.unwrap_switch()
		}
		.no_ignore_parent {
			args.no_ignore_parent = v.unwrap_switch()
		}
		.no_ignore_vcs {
			args.no_ignore_vcs = v.unwrap_switch()
		}
		.no_messages {
			args.no_messages = v.unwrap_switch()
		}
		.no_pcre_2_unicode {
			args.no_unicode = v.unwrap_switch()
		}
		.no_require_git {
			args.no_require_git = v.unwrap_switch()
		}
		.no_unicode {
			args.no_unicode = v.unwrap_switch()
		}
		.null {
			assert v.unwrap_switch()
			args.null = true
		}
		.null_data {
			assert v.unwrap_switch()
			args.crlf = false
			args.null_data = true
		}
		.one_file_system {
			args.one_file_system = v.unwrap_switch()
		}
		.only_matching {
			assert v.unwrap_switch()
			args.only_matching = true
		}
		.path_separator {
			s := v.unwrap_value()
			raw := unescape_bytes(s)!
			if raw.len == 0 {
						args.path_separator = none
					} else if raw.len == 1 {
						args.path_separator = raw[0]
					} else {
						return error("A path separator must be exactly one byte, but the given separator is ${raw.len} bytes: ${s}
In some shells on Windows '/' is automatically expanded. Use '//' instead.")
					}
		}
		.passthru {
			assert v.unwrap_switch()
			args.context = passthru_context_mode()
		}
		.pcre_2 {
			args.engine = if v.unwrap_switch() { .pcre2 } else { .default }
		}
		.pcre_2_version {
			assert v.unwrap_switch()
			args.special = .version_pcre2
		}
		.pre {
			if v.kind == .switch_value {
						assert !v.switch_value
						args.pre = none
						return
					}
			path := v.value
			args.pre = if path == '' { none } else { path }
			if _ := args.pre {
						args.search_zip = false
					}
		}
		.pre_glob {
			args.pre_glob << v.unwrap_value()
		}
		.pretty {
			assert v.unwrap_switch()
			args.color = .always
			args.heading = true
			args.line_number = true
		}
		.quiet {
			assert v.unwrap_switch()
			args.quiet = true
		}
		.regex_size_limit {
			args.regex_size_limit = parse_human_readable_usize(v.unwrap_value())!
		}
		.regexp {
			regexp := v.unwrap_value()
			if !utf8.validate_str(regexp) {
				return error('value is not valid UTF-8')
			}
			args.patterns << pattern_regexp(regexp)
		}
		.replace {
			args.replace = v.unwrap_value()
		}
		.search_zip {
			if v.unwrap_switch() {
						args.pre = none
						args.search_zip = true
					} else {
						args.search_zip = false
					}
		}
		.smart_case {
			assert v.unwrap_switch()
			args.case = .smart
		}
		.sort_files {
			args.sort = if v.unwrap_switch() { SortMode{ reverse: false, kind: .path } } else { none }
		}
		.sort {
			value := v.unwrap_value()
			if value == 'none' {
						args.sort = none
						return
					}
			kind := match value {
						'path' { SortModeKind.path }
						'modified' { SortModeKind.last_modified }
						'accessed' { SortModeKind.last_accessed }
						'created' { SortModeKind.created }
						else { return error("choice '${value}' is unrecognized") }
					}
			args.sort = SortMode{
						reverse: false
						kind: kind
					}
		}
		.sortr {
			value := v.unwrap_value()
			if value == 'none' {
						args.sort = none
						return
					}
			kind := match value {
						'path' { SortModeKind.path }
						'modified' { SortModeKind.last_modified }
						'accessed' { SortModeKind.last_accessed }
						'created' { SortModeKind.created }
						else { return error("choice '${value}' is unrecognized") }
					}
			args.sort = SortMode{
						reverse: true
						kind: kind
					}
		}
		.stats {
			args.stats = v.unwrap_switch()
		}
		.stop_on_nonmatch {
			assert v.unwrap_switch()
			args.stop_on_nonmatch = true
			args.multiline = false
		}
		.text {
			args.binary = if v.unwrap_switch() { .as_text } else { .auto }
		}
		.threads {
			threads := parse_usize(v.unwrap_value())!
			args.threads = if threads == 0 { none } else { threads }
		}
		.trace {
			assert v.unwrap_switch()
			args.logging = .trace
		}
		.trim {
			args.trim = v.unwrap_switch()
		}
		.type {
			args.type_changes << type_change_select(v.unwrap_value())
		}
		.type_add {
			args.type_changes << type_change_add(v.unwrap_value())
		}
		.type_clear {
			args.type_changes << type_change_clear(v.unwrap_value())
		}
		.type_not {
			args.type_changes << type_change_negate(v.unwrap_value())
		}
		.type_list {
			assert v.unwrap_switch()
			args.mode.update(mode_types())
		}
		.unrestricted {
			assert v.unwrap_switch()
			if args.unrestricted < ~usize(0) {
				args.unrestricted++
			}
			if args.unrestricted > 3 {
						return error('flag can only be repeated up to 3 times')
					}
			if args.unrestricted == 1 {
						FlagId.no_ignore.update(flag_switch(true), mut args)!
					} else if args.unrestricted == 2 {
						FlagId.hidden.update(flag_switch(true), mut args)!
					} else {
						FlagId.binary.update(flag_switch(true), mut args)!
					}
		}
		.version {
			assert v.unwrap_switch()
		}
		.vimgrep {
			assert v.unwrap_switch()
			args.vimgrep = true
		}
		.with_filename {
			assert v.unwrap_switch()
			args.with_filename = true
		}
		.with_filename_no {
			assert v.unwrap_switch()
			args.with_filename = false
		}
		.word_regexp {
			assert v.unwrap_switch()
			args.boundary = .word
		}
	}
}
