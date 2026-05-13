module flags

import ownflag as vflag

struct ParseSchema {
	flag_after_context                           string @[long: 'after-context'; short: A]
	flag_auto_hybrid_regex                       bool   @[long: 'auto-hybrid-regex']
	flag_no_auto_hybrid_regex_negated            bool   @[long: 'no-auto-hybrid-regex']
	flag_before_context                          string @[long: 'before-context'; short: B]
	flag_binary                                  bool   @[long: 'binary']
	flag_no_binary_negated                       bool   @[long: 'no-binary']
	flag_block_buffered                          bool   @[long: 'block-buffered']
	flag_no_block_buffered_negated               bool   @[long: 'no-block-buffered']
	flag_byte_offset                             bool   @[long: 'byte-offset'; short: b]
	flag_no_byte_offset_negated                  bool   @[long: 'no-byte-offset']
	flag_case_sensitive                          bool   @[long: 'case-sensitive'; short: s]
	flag_color                                   string @[long: 'color']
	flag_colors                                  string @[long: 'colors']
	flag_column                                  bool   @[long: 'column']
	flag_no_column_negated                       bool   @[long: 'no-column']
	flag_context                                 string @[long: 'context'; short: C]
	flag_context_separator                       string @[long: 'context-separator']
	flag_no_context_separator_negated            bool   @[long: 'no-context-separator']
	flag_count                                   bool   @[long: 'count'; short: c]
	flag_count_matches                           bool   @[long: 'count-matches']
	flag_crlf                                    bool   @[long: 'crlf']
	flag_no_crlf_negated                         bool   @[long: 'no-crlf']
	flag_debug                                   bool   @[long: 'debug']
	flag_dfa_size_limit                          string @[long: 'dfa-size-limit']
	flag_encoding                                string @[long: 'encoding'; short: E]
	flag_no_encoding_negated                     bool   @[long: 'no-encoding']
	flag_engine                                  string @[long: 'engine']
	flag_field_context_separator                 string @[long: 'field-context-separator']
	flag_field_match_separator                   string @[long: 'field-match-separator']
	flag_file                                    string @[long: 'file'; short: f]
	flag_files                                   bool   @[long: 'files']
	flag_files_with_matches                      bool   @[long: 'files-with-matches'; short: l]
	flag_files_without_match                     bool   @[long: 'files-without-match']
	flag_fixed_strings                           bool   @[long: 'fixed-strings'; short: F]
	flag_no_fixed_strings_negated                bool   @[long: 'no-fixed-strings']
	flag_follow                                  bool   @[long: 'follow'; short: L]
	flag_no_follow_negated                       bool   @[long: 'no-follow']
	flag_generate                                string @[long: 'generate']
	flag_glob                                    string @[long: 'glob'; short: g]
	flag_glob_case_insensitive                   bool   @[long: 'glob-case-insensitive']
	flag_no_glob_case_insensitive_negated        bool   @[long: 'no-glob-case-insensitive']
	flag_heading                                 bool   @[long: 'heading']
	flag_no_heading_negated                      bool   @[long: 'no-heading']
	flag_help                                    bool   @[long: 'help'; short: h]
	flag_hidden                                  bool   @[long: 'hidden'; short: '.']
	flag_no_hidden_negated                       bool   @[long: 'no-hidden']
	flag_hostname_bin                            string @[long: 'hostname-bin']
	flag_hyperlink_format                        string @[long: 'hyperlink-format']
	flag_iglob                                   string @[long: 'iglob']
	flag_ignore_case                             bool   @[long: 'ignore-case'; short: i]
	flag_ignore_file                             string @[long: 'ignore-file']
	flag_ignore_file_case_insensitive            bool   @[long: 'ignore-file-case-insensitive']
	flag_no_ignore_file_case_insensitive_negated bool   @[long: 'no-ignore-file-case-insensitive']
	flag_include_zero                            bool   @[long: 'include-zero']
	flag_no_include_zero_negated                 bool   @[long: 'no-include-zero']
	flag_invert_match                            bool   @[long: 'invert-match'; short: v]
	flag_no_invert_match_negated                 bool   @[long: 'no-invert-match']
	flag_json                                    bool   @[long: 'json']
	flag_no_json_negated                         bool   @[long: 'no-json']
	flag_line_buffered                           bool   @[long: 'line-buffered']
	flag_no_line_buffered_negated                bool   @[long: 'no-line-buffered']
	flag_line_number                             bool   @[long: 'line-number'; short: n]
	flag_no_line_number                          bool   @[long: 'no-line-number'; short: N]
	flag_line_regexp                             bool   @[long: 'line-regexp'; short: x]
	flag_max_columns                             string @[long: 'max-columns'; short: M]
	flag_max_columns_preview                     bool   @[long: 'max-columns-preview']
	flag_no_max_columns_preview_negated          bool   @[long: 'no-max-columns-preview']
	flag_max_count                               string @[long: 'max-count'; short: m]
	flag_max_depth                               string @[long: 'max-depth'; short: d]
	flag_maxdepth_alias                          string @[long: 'maxdepth']
	flag_max_filesize                            string @[long: 'max-filesize']
	flag_mmap                                    bool   @[long: 'mmap']
	flag_no_mmap_negated                         bool   @[long: 'no-mmap']
	flag_multiline                               bool   @[long: 'multiline'; short: U]
	flag_no_multiline_negated                    bool   @[long: 'no-multiline']
	flag_multiline_dotall                        bool   @[long: 'multiline-dotall']
	flag_no_multiline_dotall_negated             bool   @[long: 'no-multiline-dotall']
	flag_no_config                               bool   @[long: 'no-config']
	flag_no_ignore                               bool   @[long: 'no-ignore']
	flag_ignore_negated                          bool   @[long: 'ignore']
	flag_no_ignore_dot                           bool   @[long: 'no-ignore-dot']
	flag_ignore_dot_negated                      bool   @[long: 'ignore-dot']
	flag_no_ignore_exclude                       bool   @[long: 'no-ignore-exclude']
	flag_ignore_exclude_negated                  bool   @[long: 'ignore-exclude']
	flag_no_ignore_files                         bool   @[long: 'no-ignore-files']
	flag_ignore_files_negated                    bool   @[long: 'ignore-files']
	flag_no_ignore_global                        bool   @[long: 'no-ignore-global']
	flag_ignore_global_negated                   bool   @[long: 'ignore-global']
	flag_no_ignore_messages                      bool   @[long: 'no-ignore-messages']
	flag_ignore_messages_negated                 bool   @[long: 'ignore-messages']
	flag_no_ignore_parent                        bool   @[long: 'no-ignore-parent']
	flag_ignore_parent_negated                   bool   @[long: 'ignore-parent']
	flag_no_ignore_vcs                           bool   @[long: 'no-ignore-vcs']
	flag_ignore_vcs_negated                      bool   @[long: 'ignore-vcs']
	flag_no_messages                             bool   @[long: 'no-messages']
	flag_messages_negated                        bool   @[long: 'messages']
	flag_no_pcre2_unicode                        bool   @[long: 'no-pcre2-unicode']
	flag_pcre2_unicode_negated                   bool   @[long: 'pcre2-unicode']
	flag_no_require_git                          bool   @[long: 'no-require-git']
	flag_require_git_negated                     bool   @[long: 'require-git']
	flag_no_unicode                              bool   @[long: 'no-unicode']
	flag_unicode_negated                         bool   @[long: 'unicode']
	flag_null                                    bool   @[long: 'null'; short: 0]
	flag_null_data                               bool   @[long: 'null-data']
	flag_one_file_system                         bool   @[long: 'one-file-system']
	flag_no_one_file_system_negated              bool   @[long: 'no-one-file-system']
	flag_only_matching                           bool   @[long: 'only-matching'; short: o]
	flag_path_separator                          string @[long: 'path-separator']
	flag_passthru                                bool   @[long: 'passthru']
	flag_passthrough_alias                       bool   @[long: 'passthrough']
	flag_pcre2                                   bool   @[long: 'pcre2'; short: P]
	flag_no_pcre2_negated                        bool   @[long: 'no-pcre2']
	flag_pcre2_version                           bool   @[long: 'pcre2-version']
	flag_pre                                     string @[long: 'pre']
	flag_no_pre_negated                          bool   @[long: 'no-pre']
	flag_pre_glob                                string @[long: 'pre-glob']
	flag_pretty                                  bool   @[long: 'pretty'; short: p]
	flag_quiet                                   bool   @[long: 'quiet'; short: q]
	flag_regex_size_limit                        string @[long: 'regex-size-limit']
	flag_regexp                                  string @[long: 'regexp'; short: e]
	flag_replace                                 string @[long: 'replace'; short: r]
	flag_search_zip                              bool   @[long: 'search-zip'; short: z]
	flag_no_search_zip_negated                   bool   @[long: 'no-search-zip']
	flag_smart_case                              bool   @[long: 'smart-case'; short: S]
	flag_sort_files                              bool   @[long: 'sort-files']
	flag_no_sort_files_negated                   bool   @[long: 'no-sort-files']
	flag_sort                                    string @[long: 'sort']
	flag_sortr                                   string @[long: 'sortr']
	flag_stats                                   bool   @[long: 'stats']
	flag_no_stats_negated                        bool   @[long: 'no-stats']
	flag_stop_on_nonmatch                        bool   @[long: 'stop-on-nonmatch']
	flag_text                                    bool   @[long: 'text'; short: a]
	flag_no_text_negated                         bool   @[long: 'no-text']
	flag_threads                                 string @[long: 'threads'; short: j]
	flag_trace                                   bool   @[long: 'trace']
	flag_trim                                    bool   @[long: 'trim']
	flag_no_trim_negated                         bool   @[long: 'no-trim']
	flag_type                                    string @[long: 'type'; short: t]
	flag_type_add                                string @[long: 'type-add']
	flag_type_clear                              string @[long: 'type-clear']
	flag_type_not                                string @[long: 'type-not'; short: T]
	flag_type_list                               bool   @[long: 'type-list']
	flag_unrestricted                            bool   @[long: 'unrestricted']
	flag_unrestricted_short                      int    @[repeats; short: u]
	flag_version                                 bool   @[long: 'version'; short: V]
	flag_vimgrep                                 bool   @[long: 'vimgrep']
	flag_with_filename                           bool   @[long: 'with-filename'; short: H]
	flag_no_filename                             bool   @[long: 'no-filename'; short: I]
	flag_word_regexp                             bool   @[long: 'word-regexp'; short: w]
}

struct ParsedOccurrence {
	id      FlagId
	value   FlagValue
	repeats int = 1
}

fn occurrence_from_parsed(parsed vflag.ParsedFlag) !ParsedOccurrence {
	match parsed.field_name {
		'flag_after_context' { return ParsedOccurrence{
				id:    .after_context
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_auto_hybrid_regex' { return ParsedOccurrence{
				id:    .auto_hybrid_regex
				value: flag_switch(true)
			} }
		'flag_no_auto_hybrid_regex_negated' { return ParsedOccurrence{
				id:    .auto_hybrid_regex
				value: flag_switch(false)
			} }
		'flag_before_context' { return ParsedOccurrence{
				id:    .before_context
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_binary' { return ParsedOccurrence{
				id:    .binary
				value: flag_switch(true)
			} }
		'flag_no_binary_negated' { return ParsedOccurrence{
				id:    .binary
				value: flag_switch(false)
			} }
		'flag_block_buffered' { return ParsedOccurrence{
				id:    .block_buffered
				value: flag_switch(true)
			} }
		'flag_no_block_buffered_negated' { return ParsedOccurrence{
				id:    .block_buffered
				value: flag_switch(false)
			} }
		'flag_byte_offset' { return ParsedOccurrence{
				id:    .byte_offset
				value: flag_switch(true)
			} }
		'flag_no_byte_offset_negated' { return ParsedOccurrence{
				id:    .byte_offset
				value: flag_switch(false)
			} }
		'flag_case_sensitive' { return ParsedOccurrence{
				id:    .case_sensitive
				value: flag_switch(true)
			} }
		'flag_color' { return ParsedOccurrence{
				id:    .color
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_colors' { return ParsedOccurrence{
				id:    .colors
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_column' { return ParsedOccurrence{
				id:    .column
				value: flag_switch(true)
			} }
		'flag_no_column_negated' { return ParsedOccurrence{
				id:    .column
				value: flag_switch(false)
			} }
		'flag_context' { return ParsedOccurrence{
				id:    .context
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_context_separator' { return ParsedOccurrence{
				id:    .context_separator
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_no_context_separator_negated' { return ParsedOccurrence{
				id:    .context_separator
				value: flag_switch(false)
			} }
		'flag_count' { return ParsedOccurrence{
				id:    .count
				value: flag_switch(true)
			} }
		'flag_count_matches' { return ParsedOccurrence{
				id:    .count_matches
				value: flag_switch(true)
			} }
		'flag_crlf' { return ParsedOccurrence{
				id:    .crlf
				value: flag_switch(true)
			} }
		'flag_no_crlf_negated' { return ParsedOccurrence{
				id:    .crlf
				value: flag_switch(false)
			} }
		'flag_debug' { return ParsedOccurrence{
				id:    .debug
				value: flag_switch(true)
			} }
		'flag_dfa_size_limit' { return ParsedOccurrence{
				id:    .dfa_size_limit
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_encoding' { return ParsedOccurrence{
				id:    .encoding
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_no_encoding_negated' { return ParsedOccurrence{
				id:    .encoding
				value: flag_switch(false)
			} }
		'flag_engine' { return ParsedOccurrence{
				id:    .engine
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_field_context_separator' { return ParsedOccurrence{
				id:    .field_context_separator
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_field_match_separator' { return ParsedOccurrence{
				id:    .field_match_separator
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_file' { return ParsedOccurrence{
				id:    .file
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_files' { return ParsedOccurrence{
				id:    .files
				value: flag_switch(true)
			} }
		'flag_files_with_matches' { return ParsedOccurrence{
				id:    .files_with_matches
				value: flag_switch(true)
			} }
		'flag_files_without_match' { return ParsedOccurrence{
				id:    .files_without_match
				value: flag_switch(true)
			} }
		'flag_fixed_strings' { return ParsedOccurrence{
				id:    .fixed_strings
				value: flag_switch(true)
			} }
		'flag_no_fixed_strings_negated' { return ParsedOccurrence{
				id:    .fixed_strings
				value: flag_switch(false)
			} }
		'flag_follow' { return ParsedOccurrence{
				id:    .follow
				value: flag_switch(true)
			} }
		'flag_no_follow_negated' { return ParsedOccurrence{
				id:    .follow
				value: flag_switch(false)
			} }
		'flag_generate' { return ParsedOccurrence{
				id:    .generate
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_glob' { return ParsedOccurrence{
				id:    .glob
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_glob_case_insensitive' { return ParsedOccurrence{
				id:    .glob_case_insensitive
				value: flag_switch(true)
			} }
		'flag_no_glob_case_insensitive_negated' { return ParsedOccurrence{
				id:    .glob_case_insensitive
				value: flag_switch(false)
			} }
		'flag_heading' { return ParsedOccurrence{
				id:    .heading
				value: flag_switch(true)
			} }
		'flag_no_heading_negated' { return ParsedOccurrence{
				id:    .heading
				value: flag_switch(false)
			} }
		'flag_help' { return ParsedOccurrence{
				id:    .help
				value: flag_switch(true)
			} }
		'flag_hidden' { return ParsedOccurrence{
				id:    .hidden
				value: flag_switch(true)
			} }
		'flag_no_hidden_negated' { return ParsedOccurrence{
				id:    .hidden
				value: flag_switch(false)
			} }
		'flag_hostname_bin' { return ParsedOccurrence{
				id:    .hostname_bin
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_hyperlink_format' { return ParsedOccurrence{
				id:    .hyperlink_format
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_iglob' { return ParsedOccurrence{
				id:    .i_glob
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_ignore_case' { return ParsedOccurrence{
				id:    .ignore_case
				value: flag_switch(true)
			} }
		'flag_ignore_file' { return ParsedOccurrence{
				id:    .ignore_file
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_ignore_file_case_insensitive' { return ParsedOccurrence{
				id:    .ignore_file_case_insensitive
				value: flag_switch(true)
			} }
		'flag_no_ignore_file_case_insensitive_negated' { return ParsedOccurrence{
				id:    .ignore_file_case_insensitive
				value: flag_switch(false)
			} }
		'flag_include_zero' { return ParsedOccurrence{
				id:    .include_zero
				value: flag_switch(true)
			} }
		'flag_no_include_zero_negated' { return ParsedOccurrence{
				id:    .include_zero
				value: flag_switch(false)
			} }
		'flag_invert_match' { return ParsedOccurrence{
				id:    .invert_match
				value: flag_switch(true)
			} }
		'flag_no_invert_match_negated' { return ParsedOccurrence{
				id:    .invert_match
				value: flag_switch(false)
			} }
		'flag_json' { return ParsedOccurrence{
				id:    .json
				value: flag_switch(true)
			} }
		'flag_no_json_negated' { return ParsedOccurrence{
				id:    .json
				value: flag_switch(false)
			} }
		'flag_line_buffered' { return ParsedOccurrence{
				id:    .line_buffered
				value: flag_switch(true)
			} }
		'flag_no_line_buffered_negated' { return ParsedOccurrence{
				id:    .line_buffered
				value: flag_switch(false)
			} }
		'flag_line_number' { return ParsedOccurrence{
				id:    .line_number
				value: flag_switch(true)
			} }
		'flag_no_line_number' { return ParsedOccurrence{
				id:    .line_number_no
				value: flag_switch(true)
			} }
		'flag_line_regexp' { return ParsedOccurrence{
				id:    .line_regexp
				value: flag_switch(true)
			} }
		'flag_max_columns' { return ParsedOccurrence{
				id:    .max_columns
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_max_columns_preview' { return ParsedOccurrence{
				id:    .max_columns_preview
				value: flag_switch(true)
			} }
		'flag_no_max_columns_preview_negated' { return ParsedOccurrence{
				id:    .max_columns_preview
				value: flag_switch(false)
			} }
		'flag_max_count' { return ParsedOccurrence{
				id:    .max_count
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_max_depth' { return ParsedOccurrence{
				id:    .max_depth
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_maxdepth_alias' { return ParsedOccurrence{
				id:    .max_depth
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_max_filesize' { return ParsedOccurrence{
				id:    .max_filesize
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_mmap' { return ParsedOccurrence{
				id:    .mmap
				value: flag_switch(true)
			} }
		'flag_no_mmap_negated' { return ParsedOccurrence{
				id:    .mmap
				value: flag_switch(false)
			} }
		'flag_multiline' { return ParsedOccurrence{
				id:    .multiline
				value: flag_switch(true)
			} }
		'flag_no_multiline_negated' { return ParsedOccurrence{
				id:    .multiline
				value: flag_switch(false)
			} }
		'flag_multiline_dotall' { return ParsedOccurrence{
				id:    .multiline_dotall
				value: flag_switch(true)
			} }
		'flag_no_multiline_dotall_negated' { return ParsedOccurrence{
				id:    .multiline_dotall
				value: flag_switch(false)
			} }
		'flag_no_config' { return ParsedOccurrence{
				id:    .no_config
				value: flag_switch(true)
			} }
		'flag_no_ignore' { return ParsedOccurrence{
				id:    .no_ignore
				value: flag_switch(true)
			} }
		'flag_ignore_negated' { return ParsedOccurrence{
				id:    .no_ignore
				value: flag_switch(false)
			} }
		'flag_no_ignore_dot' { return ParsedOccurrence{
				id:    .no_ignore_dot
				value: flag_switch(true)
			} }
		'flag_ignore_dot_negated' { return ParsedOccurrence{
				id:    .no_ignore_dot
				value: flag_switch(false)
			} }
		'flag_no_ignore_exclude' { return ParsedOccurrence{
				id:    .no_ignore_exclude
				value: flag_switch(true)
			} }
		'flag_ignore_exclude_negated' { return ParsedOccurrence{
				id:    .no_ignore_exclude
				value: flag_switch(false)
			} }
		'flag_no_ignore_files' { return ParsedOccurrence{
				id:    .no_ignore_files
				value: flag_switch(true)
			} }
		'flag_ignore_files_negated' { return ParsedOccurrence{
				id:    .no_ignore_files
				value: flag_switch(false)
			} }
		'flag_no_ignore_global' { return ParsedOccurrence{
				id:    .no_ignore_global
				value: flag_switch(true)
			} }
		'flag_ignore_global_negated' { return ParsedOccurrence{
				id:    .no_ignore_global
				value: flag_switch(false)
			} }
		'flag_no_ignore_messages' { return ParsedOccurrence{
				id:    .no_ignore_messages
				value: flag_switch(true)
			} }
		'flag_ignore_messages_negated' { return ParsedOccurrence{
				id:    .no_ignore_messages
				value: flag_switch(false)
			} }
		'flag_no_ignore_parent' { return ParsedOccurrence{
				id:    .no_ignore_parent
				value: flag_switch(true)
			} }
		'flag_ignore_parent_negated' { return ParsedOccurrence{
				id:    .no_ignore_parent
				value: flag_switch(false)
			} }
		'flag_no_ignore_vcs' { return ParsedOccurrence{
				id:    .no_ignore_vcs
				value: flag_switch(true)
			} }
		'flag_ignore_vcs_negated' { return ParsedOccurrence{
				id:    .no_ignore_vcs
				value: flag_switch(false)
			} }
		'flag_no_messages' { return ParsedOccurrence{
				id:    .no_messages
				value: flag_switch(true)
			} }
		'flag_messages_negated' { return ParsedOccurrence{
				id:    .no_messages
				value: flag_switch(false)
			} }
		'flag_no_pcre2_unicode' { return ParsedOccurrence{
				id:    .no_pcre_2_unicode
				value: flag_switch(true)
			} }
		'flag_pcre2_unicode_negated' { return ParsedOccurrence{
				id:    .no_pcre_2_unicode
				value: flag_switch(false)
			} }
		'flag_no_require_git' { return ParsedOccurrence{
				id:    .no_require_git
				value: flag_switch(true)
			} }
		'flag_require_git_negated' { return ParsedOccurrence{
				id:    .no_require_git
				value: flag_switch(false)
			} }
		'flag_no_unicode' { return ParsedOccurrence{
				id:    .no_unicode
				value: flag_switch(true)
			} }
		'flag_unicode_negated' { return ParsedOccurrence{
				id:    .no_unicode
				value: flag_switch(false)
			} }
		'flag_null' { return ParsedOccurrence{
				id:    .null
				value: flag_switch(true)
			} }
		'flag_null_data' { return ParsedOccurrence{
				id:    .null_data
				value: flag_switch(true)
			} }
		'flag_one_file_system' { return ParsedOccurrence{
				id:    .one_file_system
				value: flag_switch(true)
			} }
		'flag_no_one_file_system_negated' { return ParsedOccurrence{
				id:    .one_file_system
				value: flag_switch(false)
			} }
		'flag_only_matching' { return ParsedOccurrence{
				id:    .only_matching
				value: flag_switch(true)
			} }
		'flag_path_separator' { return ParsedOccurrence{
				id:    .path_separator
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_passthru' { return ParsedOccurrence{
				id:    .passthru
				value: flag_switch(true)
			} }
		'flag_passthrough_alias' { return ParsedOccurrence{
				id:    .passthru
				value: flag_switch(true)
			} }
		'flag_pcre2' { return ParsedOccurrence{
				id:    .pcre_2
				value: flag_switch(true)
			} }
		'flag_no_pcre2_negated' { return ParsedOccurrence{
				id:    .pcre_2
				value: flag_switch(false)
			} }
		'flag_pcre2_version' { return ParsedOccurrence{
				id:    .pcre_2_version
				value: flag_switch(true)
			} }
		'flag_pre' { return ParsedOccurrence{
				id:    .pre
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_no_pre_negated' { return ParsedOccurrence{
				id:    .pre
				value: flag_switch(false)
			} }
		'flag_pre_glob' { return ParsedOccurrence{
				id:    .pre_glob
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_pretty' { return ParsedOccurrence{
				id:    .pretty
				value: flag_switch(true)
			} }
		'flag_quiet' { return ParsedOccurrence{
				id:    .quiet
				value: flag_switch(true)
			} }
		'flag_regex_size_limit' { return ParsedOccurrence{
				id:    .regex_size_limit
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_regexp' { return ParsedOccurrence{
				id:    .regexp
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_replace' { return ParsedOccurrence{
				id:    .replace
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_search_zip' { return ParsedOccurrence{
				id:    .search_zip
				value: flag_switch(true)
			} }
		'flag_no_search_zip_negated' { return ParsedOccurrence{
				id:    .search_zip
				value: flag_switch(false)
			} }
		'flag_smart_case' { return ParsedOccurrence{
				id:    .smart_case
				value: flag_switch(true)
			} }
		'flag_sort_files' { return ParsedOccurrence{
				id:    .sort_files
				value: flag_switch(true)
			} }
		'flag_no_sort_files_negated' { return ParsedOccurrence{
				id:    .sort_files
				value: flag_switch(false)
			} }
		'flag_sort' { return ParsedOccurrence{
				id:    .sort
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_sortr' { return ParsedOccurrence{
				id:    .sortr
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_stats' { return ParsedOccurrence{
				id:    .stats
				value: flag_switch(true)
			} }
		'flag_no_stats_negated' { return ParsedOccurrence{
				id:    .stats
				value: flag_switch(false)
			} }
		'flag_stop_on_nonmatch' { return ParsedOccurrence{
				id:    .stop_on_nonmatch
				value: flag_switch(true)
			} }
		'flag_text' { return ParsedOccurrence{
				id:    .text
				value: flag_switch(true)
			} }
		'flag_no_text_negated' { return ParsedOccurrence{
				id:    .text
				value: flag_switch(false)
			} }
		'flag_threads' { return ParsedOccurrence{
				id:    .threads
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_trace' { return ParsedOccurrence{
				id:    .trace
				value: flag_switch(true)
			} }
		'flag_trim' { return ParsedOccurrence{
				id:    .trim
				value: flag_switch(true)
			} }
		'flag_no_trim_negated' { return ParsedOccurrence{
				id:    .trim
				value: flag_switch(false)
			} }
		'flag_type' { return ParsedOccurrence{
				id:    .type
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_type_add' { return ParsedOccurrence{
				id:    .type_add
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_type_clear' { return ParsedOccurrence{
				id:    .type_clear
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_type_not' { return ParsedOccurrence{
				id:    .type_not
				value: flag_value(parsed.arg or { return error('missing flag value') })
			} }
		'flag_type_list' { return ParsedOccurrence{
				id:    .type_list
				value: flag_switch(true)
			} }
		'flag_unrestricted' { return ParsedOccurrence{
				id:    .unrestricted
				value: flag_switch(true)
			} }
		'flag_unrestricted_short' { return ParsedOccurrence{
				id:      .unrestricted
				value:   flag_switch(true)
				repeats: parsed.repeats
			} }
		'flag_version' { return ParsedOccurrence{
				id:    .version
				value: flag_switch(true)
			} }
		'flag_vimgrep' { return ParsedOccurrence{
				id:    .vimgrep
				value: flag_switch(true)
			} }
		'flag_with_filename' { return ParsedOccurrence{
				id:    .with_filename
				value: flag_switch(true)
			} }
		'flag_no_filename' { return ParsedOccurrence{
				id:    .with_filename_no
				value: flag_switch(true)
			} }
		'flag_word_regexp' { return ParsedOccurrence{
				id:    .word_regexp
				value: flag_switch(true)
			} }
		else { return error('unrecognized parsed flag') }
	}
}

pub fn lookup(name string) ?FlagId {
	for id in flags {
		if id.name_long() == name {
			return id
		}
		if neg := id.name_negated() {
			if neg == name {
				return id
			}
		}
		for alias in id.aliases() {
			if alias == name {
				return id
			}
		}
	}
	return none
}

pub fn parse_low_raw(rawargs []string) !LowArgs {
	mut fm := vflag.FlagMapper{
		config: vflag.ParseConfig{
			style: .short_long
			mode:  .relaxed
			stop:  '--'
		}
		input:  rawargs
	}
	fm.parse[ParseSchema]()!
	mut args := default_low_args()
	for parsed in fm.parsed_flags() {
		occ := occurrence_from_parsed(parsed)!
		if occ.id == .help {
			args.special = if parsed.name == 'h' { .help_short } else { .help_long }
			continue
		}
		if occ.id == .version {
			args.special = if parsed.name == 'V' { .version_short } else { .version_long }
			continue
		}
		for _ in 0 .. occ.repeats {
			occ.id.update(occ.value, mut args)!
		}
	}
	stop_index := rawargs.index('--')
	mut handled := map[int]bool{}
	for pos in fm.handled_positions() {
		handled[pos] = true
	}
	for i, arg in rawargs {
		if i == stop_index {
			continue
		}
		if stop_index != -1 && i > stop_index {
			args.positional << arg.to_owned()
			continue
		}
		if i in handled {
			continue
		}
		if arg != '-' && arg.starts_with('-') {
			return error('unrecognized flag ${arg}')
		}
		args.positional << arg.to_owned()
	}
	return args
}
