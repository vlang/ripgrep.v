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

fn parse_schema_defs() []vflag.FlagDef {
	return [
		vflag.FlagDef{field_name: 'flag_after_context' long_name: 'after-context' short_name: 'A' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_auto_hybrid_regex' long_name: 'auto-hybrid-regex' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_auto_hybrid_regex_negated' long_name: 'no-auto-hybrid-regex' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_before_context' long_name: 'before-context' short_name: 'B' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_binary' long_name: 'binary' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_binary_negated' long_name: 'no-binary' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_block_buffered' long_name: 'block-buffered' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_block_buffered_negated' long_name: 'no-block-buffered' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_byte_offset' long_name: 'byte-offset' short_name: 'b' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_byte_offset_negated' long_name: 'no-byte-offset' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_case_sensitive' long_name: 'case-sensitive' short_name: 's' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_color' long_name: 'color' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_colors' long_name: 'colors' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_column' long_name: 'column' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_column_negated' long_name: 'no-column' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_context' long_name: 'context' short_name: 'C' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_context_separator' long_name: 'context-separator' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_no_context_separator_negated' long_name: 'no-context-separator' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_count' long_name: 'count' short_name: 'c' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_count_matches' long_name: 'count-matches' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_crlf' long_name: 'crlf' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_crlf_negated' long_name: 'no-crlf' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_debug' long_name: 'debug' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_dfa_size_limit' long_name: 'dfa-size-limit' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_encoding' long_name: 'encoding' short_name: 'E' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_no_encoding_negated' long_name: 'no-encoding' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_engine' long_name: 'engine' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_field_context_separator' long_name: 'field-context-separator' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_field_match_separator' long_name: 'field-match-separator' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_file' long_name: 'file' short_name: 'f' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_files' long_name: 'files' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_files_with_matches' long_name: 'files-with-matches' short_name: 'l' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_files_without_match' long_name: 'files-without-match' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_fixed_strings' long_name: 'fixed-strings' short_name: 'F' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_fixed_strings_negated' long_name: 'no-fixed-strings' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_follow' long_name: 'follow' short_name: 'L' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_follow_negated' long_name: 'no-follow' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_generate' long_name: 'generate' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_glob' long_name: 'glob' short_name: 'g' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_glob_case_insensitive' long_name: 'glob-case-insensitive' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_glob_case_insensitive_negated' long_name: 'no-glob-case-insensitive' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_heading' long_name: 'heading' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_heading_negated' long_name: 'no-heading' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_help' long_name: 'help' short_name: 'h' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_hidden' long_name: 'hidden' short_name: '.' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_hidden_negated' long_name: 'no-hidden' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_hostname_bin' long_name: 'hostname-bin' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_hyperlink_format' long_name: 'hyperlink-format' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_iglob' long_name: 'iglob' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_ignore_case' long_name: 'ignore-case' short_name: 'i' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_ignore_file' long_name: 'ignore-file' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_ignore_file_case_insensitive' long_name: 'ignore-file-case-insensitive' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_ignore_file_case_insensitive_negated' long_name: 'no-ignore-file-case-insensitive' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_include_zero' long_name: 'include-zero' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_include_zero_negated' long_name: 'no-include-zero' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_invert_match' long_name: 'invert-match' short_name: 'v' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_invert_match_negated' long_name: 'no-invert-match' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_json' long_name: 'json' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_json_negated' long_name: 'no-json' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_line_buffered' long_name: 'line-buffered' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_line_buffered_negated' long_name: 'no-line-buffered' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_line_number' long_name: 'line-number' short_name: 'n' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_line_number' long_name: 'no-line-number' short_name: 'N' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_line_regexp' long_name: 'line-regexp' short_name: 'x' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_max_columns' long_name: 'max-columns' short_name: 'M' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_max_columns_preview' long_name: 'max-columns-preview' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_max_columns_preview_negated' long_name: 'no-max-columns-preview' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_max_count' long_name: 'max-count' short_name: 'm' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_max_depth' long_name: 'max-depth' short_name: 'd' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_maxdepth_alias' long_name: 'maxdepth' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_max_filesize' long_name: 'max-filesize' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_mmap' long_name: 'mmap' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_mmap_negated' long_name: 'no-mmap' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_multiline' long_name: 'multiline' short_name: 'U' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_multiline_negated' long_name: 'no-multiline' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_multiline_dotall' long_name: 'multiline-dotall' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_multiline_dotall_negated' long_name: 'no-multiline-dotall' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_config' long_name: 'no-config' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_ignore' long_name: 'no-ignore' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_ignore_negated' long_name: 'ignore' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_ignore_dot' long_name: 'no-ignore-dot' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_ignore_dot_negated' long_name: 'ignore-dot' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_ignore_exclude' long_name: 'no-ignore-exclude' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_ignore_exclude_negated' long_name: 'ignore-exclude' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_ignore_files' long_name: 'no-ignore-files' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_ignore_files_negated' long_name: 'ignore-files' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_ignore_global' long_name: 'no-ignore-global' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_ignore_global_negated' long_name: 'ignore-global' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_ignore_messages' long_name: 'no-ignore-messages' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_ignore_messages_negated' long_name: 'ignore-messages' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_ignore_parent' long_name: 'no-ignore-parent' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_ignore_parent_negated' long_name: 'ignore-parent' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_ignore_vcs' long_name: 'no-ignore-vcs' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_ignore_vcs_negated' long_name: 'ignore-vcs' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_messages' long_name: 'no-messages' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_messages_negated' long_name: 'messages' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_pcre2_unicode' long_name: 'no-pcre2-unicode' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_pcre2_unicode_negated' long_name: 'pcre2-unicode' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_require_git' long_name: 'no-require-git' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_require_git_negated' long_name: 'require-git' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_unicode' long_name: 'no-unicode' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_unicode_negated' long_name: 'unicode' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_null' long_name: 'null' short_name: '0' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_null_data' long_name: 'null-data' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_one_file_system' long_name: 'one-file-system' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_one_file_system_negated' long_name: 'no-one-file-system' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_only_matching' long_name: 'only-matching' short_name: 'o' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_path_separator' long_name: 'path-separator' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_passthru' long_name: 'passthru' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_passthrough_alias' long_name: 'passthrough' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_pcre2' long_name: 'pcre2' short_name: 'P' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_pcre2_negated' long_name: 'no-pcre2' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_pcre2_version' long_name: 'pcre2-version' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_pre' long_name: 'pre' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_no_pre_negated' long_name: 'no-pre' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_pre_glob' long_name: 'pre-glob' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_pretty' long_name: 'pretty' short_name: 'p' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_quiet' long_name: 'quiet' short_name: 'q' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_regex_size_limit' long_name: 'regex-size-limit' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_regexp' long_name: 'regexp' short_name: 'e' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_replace' long_name: 'replace' short_name: 'r' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_search_zip' long_name: 'search-zip' short_name: 'z' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_search_zip_negated' long_name: 'no-search-zip' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_smart_case' long_name: 'smart-case' short_name: 'S' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_sort_files' long_name: 'sort-files' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_sort_files_negated' long_name: 'no-sort-files' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_sort' long_name: 'sort' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_sortr' long_name: 'sortr' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_stats' long_name: 'stats' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_stats_negated' long_name: 'no-stats' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_stop_on_nonmatch' long_name: 'stop-on-nonmatch' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_text' long_name: 'text' short_name: 'a' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_text_negated' long_name: 'no-text' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_threads' long_name: 'threads' short_name: 'j' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_trace' long_name: 'trace' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_trim' long_name: 'trim' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_trim_negated' long_name: 'no-trim' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_type' long_name: 'type' short_name: 't' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_type_add' long_name: 'type-add' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_type_clear' long_name: 'type-clear' short_name: '' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_type_not' long_name: 'type-not' short_name: 'T' takes_arg: true},
		vflag.FlagDef{field_name: 'flag_type_list' long_name: 'type-list' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_unrestricted' long_name: 'unrestricted' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_unrestricted_short' long_name: 'flag-unrestricted-short' short_name: 'u' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_version' long_name: 'version' short_name: 'V' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_vimgrep' long_name: 'vimgrep' short_name: '' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_with_filename' long_name: 'with-filename' short_name: 'H' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_no_filename' long_name: 'no-filename' short_name: 'I' takes_arg: false},
		vflag.FlagDef{field_name: 'flag_word_regexp' long_name: 'word-regexp' short_name: 'w' takes_arg: false},
	]
}

struct ParsedOccurrence {
	id      FlagId
	value   FlagValue
	repeats int = 1
}

fn occurrence_from_parsed(parsed vflag.ParsedFlag) !ParsedOccurrence {
	match parsed.field_name {
		'flag_after_context' {
			return ParsedOccurrence{
				id:    .after_context
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_auto_hybrid_regex' {
			return ParsedOccurrence{
				id:    .auto_hybrid_regex
				value: flag_switch(true)
			}
		}
		'flag_no_auto_hybrid_regex_negated' {
			return ParsedOccurrence{
				id:    .auto_hybrid_regex
				value: flag_switch(false)
			}
		}
		'flag_before_context' {
			return ParsedOccurrence{
				id:    .before_context
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_binary' {
			return ParsedOccurrence{
				id:    .binary
				value: flag_switch(true)
			}
		}
		'flag_no_binary_negated' {
			return ParsedOccurrence{
				id:    .binary
				value: flag_switch(false)
			}
		}
		'flag_block_buffered' {
			return ParsedOccurrence{
				id:    .block_buffered
				value: flag_switch(true)
			}
		}
		'flag_no_block_buffered_negated' {
			return ParsedOccurrence{
				id:    .block_buffered
				value: flag_switch(false)
			}
		}
		'flag_byte_offset' {
			return ParsedOccurrence{
				id:    .byte_offset
				value: flag_switch(true)
			}
		}
		'flag_no_byte_offset_negated' {
			return ParsedOccurrence{
				id:    .byte_offset
				value: flag_switch(false)
			}
		}
		'flag_case_sensitive' {
			return ParsedOccurrence{
				id:    .case_sensitive
				value: flag_switch(true)
			}
		}
		'flag_color' {
			return ParsedOccurrence{
				id:    .color
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_colors' {
			return ParsedOccurrence{
				id:    .colors
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_column' {
			return ParsedOccurrence{
				id:    .column
				value: flag_switch(true)
			}
		}
		'flag_no_column_negated' {
			return ParsedOccurrence{
				id:    .column
				value: flag_switch(false)
			}
		}
		'flag_context' {
			return ParsedOccurrence{
				id:    .context
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_context_separator' {
			return ParsedOccurrence{
				id:    .context_separator
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_no_context_separator_negated' {
			return ParsedOccurrence{
				id:    .context_separator
				value: flag_switch(false)
			}
		}
		'flag_count' {
			return ParsedOccurrence{
				id:    .count
				value: flag_switch(true)
			}
		}
		'flag_count_matches' {
			return ParsedOccurrence{
				id:    .count_matches
				value: flag_switch(true)
			}
		}
		'flag_crlf' {
			return ParsedOccurrence{
				id:    .crlf
				value: flag_switch(true)
			}
		}
		'flag_no_crlf_negated' {
			return ParsedOccurrence{
				id:    .crlf
				value: flag_switch(false)
			}
		}
		'flag_debug' {
			return ParsedOccurrence{
				id:    .debug
				value: flag_switch(true)
			}
		}
		'flag_dfa_size_limit' {
			return ParsedOccurrence{
				id:    .dfa_size_limit
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_encoding' {
			return ParsedOccurrence{
				id:    .encoding
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_no_encoding_negated' {
			return ParsedOccurrence{
				id:    .encoding
				value: flag_switch(false)
			}
		}
		'flag_engine' {
			return ParsedOccurrence{
				id:    .engine
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_field_context_separator' {
			return ParsedOccurrence{
				id:    .field_context_separator
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_field_match_separator' {
			return ParsedOccurrence{
				id:    .field_match_separator
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_file' {
			return ParsedOccurrence{
				id:    .file
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_files' {
			return ParsedOccurrence{
				id:    .files
				value: flag_switch(true)
			}
		}
		'flag_files_with_matches' {
			return ParsedOccurrence{
				id:    .files_with_matches
				value: flag_switch(true)
			}
		}
		'flag_files_without_match' {
			return ParsedOccurrence{
				id:    .files_without_match
				value: flag_switch(true)
			}
		}
		'flag_fixed_strings' {
			return ParsedOccurrence{
				id:    .fixed_strings
				value: flag_switch(true)
			}
		}
		'flag_no_fixed_strings_negated' {
			return ParsedOccurrence{
				id:    .fixed_strings
				value: flag_switch(false)
			}
		}
		'flag_follow' {
			return ParsedOccurrence{
				id:    .follow
				value: flag_switch(true)
			}
		}
		'flag_no_follow_negated' {
			return ParsedOccurrence{
				id:    .follow
				value: flag_switch(false)
			}
		}
		'flag_generate' {
			return ParsedOccurrence{
				id:    .generate
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_glob' {
			return ParsedOccurrence{
				id:    .glob
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_glob_case_insensitive' {
			return ParsedOccurrence{
				id:    .glob_case_insensitive
				value: flag_switch(true)
			}
		}
		'flag_no_glob_case_insensitive_negated' {
			return ParsedOccurrence{
				id:    .glob_case_insensitive
				value: flag_switch(false)
			}
		}
		'flag_heading' {
			return ParsedOccurrence{
				id:    .heading
				value: flag_switch(true)
			}
		}
		'flag_no_heading_negated' {
			return ParsedOccurrence{
				id:    .heading
				value: flag_switch(false)
			}
		}
		'flag_help' {
			return ParsedOccurrence{
				id:    .help
				value: flag_switch(true)
			}
		}
		'flag_hidden' {
			return ParsedOccurrence{
				id:    .hidden
				value: flag_switch(true)
			}
		}
		'flag_no_hidden_negated' {
			return ParsedOccurrence{
				id:    .hidden
				value: flag_switch(false)
			}
		}
		'flag_hostname_bin' {
			return ParsedOccurrence{
				id:    .hostname_bin
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_hyperlink_format' {
			return ParsedOccurrence{
				id:    .hyperlink_format
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_iglob' {
			return ParsedOccurrence{
				id:    .i_glob
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_ignore_case' {
			return ParsedOccurrence{
				id:    .ignore_case
				value: flag_switch(true)
			}
		}
		'flag_ignore_file' {
			return ParsedOccurrence{
				id:    .ignore_file
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_ignore_file_case_insensitive' {
			return ParsedOccurrence{
				id:    .ignore_file_case_insensitive
				value: flag_switch(true)
			}
		}
		'flag_no_ignore_file_case_insensitive_negated' {
			return ParsedOccurrence{
				id:    .ignore_file_case_insensitive
				value: flag_switch(false)
			}
		}
		'flag_include_zero' {
			return ParsedOccurrence{
				id:    .include_zero
				value: flag_switch(true)
			}
		}
		'flag_no_include_zero_negated' {
			return ParsedOccurrence{
				id:    .include_zero
				value: flag_switch(false)
			}
		}
		'flag_invert_match' {
			return ParsedOccurrence{
				id:    .invert_match
				value: flag_switch(true)
			}
		}
		'flag_no_invert_match_negated' {
			return ParsedOccurrence{
				id:    .invert_match
				value: flag_switch(false)
			}
		}
		'flag_json' {
			return ParsedOccurrence{
				id:    .json
				value: flag_switch(true)
			}
		}
		'flag_no_json_negated' {
			return ParsedOccurrence{
				id:    .json
				value: flag_switch(false)
			}
		}
		'flag_line_buffered' {
			return ParsedOccurrence{
				id:    .line_buffered
				value: flag_switch(true)
			}
		}
		'flag_no_line_buffered_negated' {
			return ParsedOccurrence{
				id:    .line_buffered
				value: flag_switch(false)
			}
		}
		'flag_line_number' {
			return ParsedOccurrence{
				id:    .line_number
				value: flag_switch(true)
			}
		}
		'flag_no_line_number' {
			return ParsedOccurrence{
				id:    .line_number_no
				value: flag_switch(true)
			}
		}
		'flag_line_regexp' {
			return ParsedOccurrence{
				id:    .line_regexp
				value: flag_switch(true)
			}
		}
		'flag_max_columns' {
			return ParsedOccurrence{
				id:    .max_columns
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_max_columns_preview' {
			return ParsedOccurrence{
				id:    .max_columns_preview
				value: flag_switch(true)
			}
		}
		'flag_no_max_columns_preview_negated' {
			return ParsedOccurrence{
				id:    .max_columns_preview
				value: flag_switch(false)
			}
		}
		'flag_max_count' {
			return ParsedOccurrence{
				id:    .max_count
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_max_depth' {
			return ParsedOccurrence{
				id:    .max_depth
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_maxdepth_alias' {
			return ParsedOccurrence{
				id:    .max_depth
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_max_filesize' {
			return ParsedOccurrence{
				id:    .max_filesize
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_mmap' {
			return ParsedOccurrence{
				id:    .mmap
				value: flag_switch(true)
			}
		}
		'flag_no_mmap_negated' {
			return ParsedOccurrence{
				id:    .mmap
				value: flag_switch(false)
			}
		}
		'flag_multiline' {
			return ParsedOccurrence{
				id:    .multiline
				value: flag_switch(true)
			}
		}
		'flag_no_multiline_negated' {
			return ParsedOccurrence{
				id:    .multiline
				value: flag_switch(false)
			}
		}
		'flag_multiline_dotall' {
			return ParsedOccurrence{
				id:    .multiline_dotall
				value: flag_switch(true)
			}
		}
		'flag_no_multiline_dotall_negated' {
			return ParsedOccurrence{
				id:    .multiline_dotall
				value: flag_switch(false)
			}
		}
		'flag_no_config' {
			return ParsedOccurrence{
				id:    .no_config
				value: flag_switch(true)
			}
		}
		'flag_no_ignore' {
			return ParsedOccurrence{
				id:    .no_ignore
				value: flag_switch(true)
			}
		}
		'flag_ignore_negated' {
			return ParsedOccurrence{
				id:    .no_ignore
				value: flag_switch(false)
			}
		}
		'flag_no_ignore_dot' {
			return ParsedOccurrence{
				id:    .no_ignore_dot
				value: flag_switch(true)
			}
		}
		'flag_ignore_dot_negated' {
			return ParsedOccurrence{
				id:    .no_ignore_dot
				value: flag_switch(false)
			}
		}
		'flag_no_ignore_exclude' {
			return ParsedOccurrence{
				id:    .no_ignore_exclude
				value: flag_switch(true)
			}
		}
		'flag_ignore_exclude_negated' {
			return ParsedOccurrence{
				id:    .no_ignore_exclude
				value: flag_switch(false)
			}
		}
		'flag_no_ignore_files' {
			return ParsedOccurrence{
				id:    .no_ignore_files
				value: flag_switch(true)
			}
		}
		'flag_ignore_files_negated' {
			return ParsedOccurrence{
				id:    .no_ignore_files
				value: flag_switch(false)
			}
		}
		'flag_no_ignore_global' {
			return ParsedOccurrence{
				id:    .no_ignore_global
				value: flag_switch(true)
			}
		}
		'flag_ignore_global_negated' {
			return ParsedOccurrence{
				id:    .no_ignore_global
				value: flag_switch(false)
			}
		}
		'flag_no_ignore_messages' {
			return ParsedOccurrence{
				id:    .no_ignore_messages
				value: flag_switch(true)
			}
		}
		'flag_ignore_messages_negated' {
			return ParsedOccurrence{
				id:    .no_ignore_messages
				value: flag_switch(false)
			}
		}
		'flag_no_ignore_parent' {
			return ParsedOccurrence{
				id:    .no_ignore_parent
				value: flag_switch(true)
			}
		}
		'flag_ignore_parent_negated' {
			return ParsedOccurrence{
				id:    .no_ignore_parent
				value: flag_switch(false)
			}
		}
		'flag_no_ignore_vcs' {
			return ParsedOccurrence{
				id:    .no_ignore_vcs
				value: flag_switch(true)
			}
		}
		'flag_ignore_vcs_negated' {
			return ParsedOccurrence{
				id:    .no_ignore_vcs
				value: flag_switch(false)
			}
		}
		'flag_no_messages' {
			return ParsedOccurrence{
				id:    .no_messages
				value: flag_switch(true)
			}
		}
		'flag_messages_negated' {
			return ParsedOccurrence{
				id:    .no_messages
				value: flag_switch(false)
			}
		}
		'flag_no_pcre2_unicode' {
			return ParsedOccurrence{
				id:    .no_pcre_2_unicode
				value: flag_switch(true)
			}
		}
		'flag_pcre2_unicode_negated' {
			return ParsedOccurrence{
				id:    .no_pcre_2_unicode
				value: flag_switch(false)
			}
		}
		'flag_no_require_git' {
			return ParsedOccurrence{
				id:    .no_require_git
				value: flag_switch(true)
			}
		}
		'flag_require_git_negated' {
			return ParsedOccurrence{
				id:    .no_require_git
				value: flag_switch(false)
			}
		}
		'flag_no_unicode' {
			return ParsedOccurrence{
				id:    .no_unicode
				value: flag_switch(true)
			}
		}
		'flag_unicode_negated' {
			return ParsedOccurrence{
				id:    .no_unicode
				value: flag_switch(false)
			}
		}
		'flag_null' {
			return ParsedOccurrence{
				id:    .null
				value: flag_switch(true)
			}
		}
		'flag_null_data' {
			return ParsedOccurrence{
				id:    .null_data
				value: flag_switch(true)
			}
		}
		'flag_one_file_system' {
			return ParsedOccurrence{
				id:    .one_file_system
				value: flag_switch(true)
			}
		}
		'flag_no_one_file_system_negated' {
			return ParsedOccurrence{
				id:    .one_file_system
				value: flag_switch(false)
			}
		}
		'flag_only_matching' {
			return ParsedOccurrence{
				id:    .only_matching
				value: flag_switch(true)
			}
		}
		'flag_path_separator' {
			return ParsedOccurrence{
				id:    .path_separator
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_passthru' {
			return ParsedOccurrence{
				id:    .passthru
				value: flag_switch(true)
			}
		}
		'flag_passthrough_alias' {
			return ParsedOccurrence{
				id:    .passthru
				value: flag_switch(true)
			}
		}
		'flag_pcre2' {
			return ParsedOccurrence{
				id:    .pcre_2
				value: flag_switch(true)
			}
		}
		'flag_no_pcre2_negated' {
			return ParsedOccurrence{
				id:    .pcre_2
				value: flag_switch(false)
			}
		}
		'flag_pcre2_version' {
			return ParsedOccurrence{
				id:    .pcre_2_version
				value: flag_switch(true)
			}
		}
		'flag_pre' {
			return ParsedOccurrence{
				id:    .pre
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_no_pre_negated' {
			return ParsedOccurrence{
				id:    .pre
				value: flag_switch(false)
			}
		}
		'flag_pre_glob' {
			return ParsedOccurrence{
				id:    .pre_glob
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_pretty' {
			return ParsedOccurrence{
				id:    .pretty
				value: flag_switch(true)
			}
		}
		'flag_quiet' {
			return ParsedOccurrence{
				id:    .quiet
				value: flag_switch(true)
			}
		}
		'flag_regex_size_limit' {
			return ParsedOccurrence{
				id:    .regex_size_limit
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_regexp' {
			return ParsedOccurrence{
				id:    .regexp
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_replace' {
			return ParsedOccurrence{
				id:    .replace
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_search_zip' {
			return ParsedOccurrence{
				id:    .search_zip
				value: flag_switch(true)
			}
		}
		'flag_no_search_zip_negated' {
			return ParsedOccurrence{
				id:    .search_zip
				value: flag_switch(false)
			}
		}
		'flag_smart_case' {
			return ParsedOccurrence{
				id:    .smart_case
				value: flag_switch(true)
			}
		}
		'flag_sort_files' {
			return ParsedOccurrence{
				id:    .sort_files
				value: flag_switch(true)
			}
		}
		'flag_no_sort_files_negated' {
			return ParsedOccurrence{
				id:    .sort_files
				value: flag_switch(false)
			}
		}
		'flag_sort' {
			return ParsedOccurrence{
				id:    .sort
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_sortr' {
			return ParsedOccurrence{
				id:    .sortr
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_stats' {
			return ParsedOccurrence{
				id:    .stats
				value: flag_switch(true)
			}
		}
		'flag_no_stats_negated' {
			return ParsedOccurrence{
				id:    .stats
				value: flag_switch(false)
			}
		}
		'flag_stop_on_nonmatch' {
			return ParsedOccurrence{
				id:    .stop_on_nonmatch
				value: flag_switch(true)
			}
		}
		'flag_text' {
			return ParsedOccurrence{
				id:    .text
				value: flag_switch(true)
			}
		}
		'flag_no_text_negated' {
			return ParsedOccurrence{
				id:    .text
				value: flag_switch(false)
			}
		}
		'flag_threads' {
			return ParsedOccurrence{
				id:    .threads
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_trace' {
			return ParsedOccurrence{
				id:    .trace
				value: flag_switch(true)
			}
		}
		'flag_trim' {
			return ParsedOccurrence{
				id:    .trim
				value: flag_switch(true)
			}
		}
		'flag_no_trim_negated' {
			return ParsedOccurrence{
				id:    .trim
				value: flag_switch(false)
			}
		}
		'flag_type' {
			return ParsedOccurrence{
				id:    .type
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_type_add' {
			return ParsedOccurrence{
				id:    .type_add
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_type_clear' {
			return ParsedOccurrence{
				id:    .type_clear
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_type_not' {
			return ParsedOccurrence{
				id:    .type_not
				value: flag_value(parsed.arg or { return error('missing flag value') })
			}
		}
		'flag_type_list' {
			return ParsedOccurrence{
				id:    .type_list
				value: flag_switch(true)
			}
		}
		'flag_unrestricted' {
			return ParsedOccurrence{
				id:    .unrestricted
				value: flag_switch(true)
			}
		}
		'flag_unrestricted_short' {
			return ParsedOccurrence{
				id:      .unrestricted
				value:   flag_switch(true)
				repeats: parsed.repeats
			}
		}
		'flag_version' {
			return ParsedOccurrence{
				id:    .version
				value: flag_switch(true)
			}
		}
		'flag_vimgrep' {
			return ParsedOccurrence{
				id:    .vimgrep
				value: flag_switch(true)
			}
		}
		'flag_with_filename' {
			return ParsedOccurrence{
				id:    .with_filename
				value: flag_switch(true)
			}
		}
		'flag_no_filename' {
			return ParsedOccurrence{
				id:    .with_filename_no
				value: flag_switch(true)
			}
		}
		'flag_word_regexp' {
			return ParsedOccurrence{
				id:    .word_regexp
				value: flag_switch(true)
			}
		}
		else {
			return error('unrecognized parsed flag')
		}
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
		input:  rawargs.clone()
	}
	fm.parse_defs(parse_schema_defs())!
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
		mut flag_display := '--${parsed.name}'
		if short_name := occ.id.name_short() {
			if parsed.name.len == 1 && parsed.name[0] == short_name {
				flag_display = '-${parsed.name}'
			}
		}
		for _ in 0 .. occ.repeats {
			occ.id.update(occ.value, mut args) or {
				return error('error parsing flag ${flag_display}: ${err.msg()}')
			}
		}
	}
	mut stop_index := -1
	for i in 0 .. rawargs.len {
		if rawargs[i] == '--' {
			stop_index = i
			break
		}
	}
	mut handled := map[int]bool{}
	for pos in fm.handled_positions() {
		handled[pos] = true
	}
	for i in 0 .. rawargs.len {
		arg := rawargs[i].clone()
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
			if arg.starts_with('--') && arg.len > 2 {
				mut name := arg[2..]
				if eq := name.index('=') {
					name = name[..eq]
				}
				if suggest_msg := suggest(name) {
					return error('unrecognized flag ${arg}\n\n${suggest_msg}')
				}
			}
			return error('unrecognized flag ${arg}')
		}
		args.positional << arg.to_owned()
	}
	return args
}
