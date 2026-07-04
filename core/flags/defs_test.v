module flags

struct UpdateStep {
	name  string
	value FlagValue
}

fn must_lookup(name string) FlagId {
	return lookup(name) or { panic('missing flag ${name}') }
}

fn must_apply(steps []UpdateStep) LowArgs {
	mut args := default_low_args()
	for step in steps {
		id := must_lookup(step.name)
		mut is_negated_name := false
		if negated := id.name_negated() {
			is_negated_name = negated == step.name
		}
		value := if step.value.kind == .switch_value && is_negated_name {
			flag_switch(!step.value.switch_value)
		} else {
			step.value
		}
		id.update(value, mut args) or { panic(err.msg()) }
	}
	return args
}

fn after_context(lines usize) ContextMode {
	mut mode := default_context_mode()
	mode.set_after(lines)
	return mode
}

fn select_type(name string) TypeChange {
	return type_change_select(name)
}

fn add_type(def string) TypeChange {
	return type_change_add(def)
}

fn clear_type(name string) TypeChange {
	return type_change_clear(name)
}

fn negate_type(name string) TypeChange {
	return type_change_negate(name)
}

fn assert_opt_bool(value ?bool, expected bool) {
	if actual := value {
		assert actual == expected
	} else {
		assert false
	}
}

fn assert_opt_usize(value ?usize, expected usize) {
	if actual := value {
		assert actual == expected
	} else {
		assert false
	}
}

fn assert_opt_u8(value ?u8, expected u8) {
	if actual := value {
		assert actual == expected
	} else {
		assert false
	}
}

fn assert_opt_string(value ?string, expected string) {
	if actual := value {
		assert actual == expected
	} else {
		assert false
	}
}

fn assert_opt_sort_mode(value ?SortMode, expected SortMode) {
	if actual := value {
		assert actual == expected
	} else {
		assert false
	}
}

fn assert_opt_boundary(value ?BoundaryMode, expected BoundaryMode) {
	if actual := value {
		assert actual == expected
	} else {
		assert false
	}
}

fn assert_context_separator_bytes(value ContextSeparator, expected ?[]u8) {
	if bytes := value.into_bytes() {
		want := expected or {
			assert false
			return
		}

		assert bytes == want
	} else {
		assert expected == none
	}
}

fn test_lookup_matches_longs_aliases_and_negations() {
	assert must_lookup('hidden') == .hidden
	assert must_lookup('no-hidden') == .hidden
	assert must_lookup('regexp') == .regexp
	assert must_lookup('type-not') == .type_not
	assert must_lookup('no-line-number') == .line_number_no
}

fn test_update_after_context() {
	args := must_apply([
		UpdateStep{'after-context', flag_value('5')},
	])
	assert args.context == after_context(5)

	args = must_apply([
		UpdateStep{'after-context', flag_value('5')},
		UpdateStep{'after-context', flag_value('10')},
	])
	assert args.context == after_context(10)

	args = must_apply([
		UpdateStep{'after-context', flag_value('5')},
		UpdateStep{'passthru', flag_switch(true)},
	])
	assert args.context == passthru_context_mode()

	args = must_apply([
		UpdateStep{'passthru', flag_switch(true)},
		UpdateStep{'after-context', flag_value('5')},
	])
	assert args.context == after_context(5)
}

fn test_update_color() {
	assert must_apply([UpdateStep{'color', flag_value('never')}]).color == .never
	assert must_apply([UpdateStep{'color', flag_value('auto')}]).color == .auto
	assert must_apply([UpdateStep{'color', flag_value('always')}]).color == .always
	assert must_apply([UpdateStep{'color', flag_value('ansi')}]).color == .ansi
	assert must_apply([
		UpdateStep{'color', flag_value('always')},
		UpdateStep{'color', flag_value('never')},
	]).color == .never
	assert must_apply([
		UpdateStep{'color', flag_value('never')},
		UpdateStep{'color', flag_value('always')},
	]).color == .always
}

fn test_update_context_separator() {
	args := must_apply([]UpdateStep{})
	assert_context_separator_bytes(args.context_separator, '--'.bytes())

	args = must_apply([UpdateStep{'context-separator', flag_value('XYZ')}])
	assert_context_separator_bytes(args.context_separator, 'XYZ'.bytes())

	args = must_apply([UpdateStep{'no-context-separator', flag_switch(true)}])
	assert_context_separator_bytes(args.context_separator, none)

	args = must_apply([
		UpdateStep{'context-separator', flag_value('XYZ')},
		UpdateStep{'no-context-separator', flag_switch(true)},
	])
	assert_context_separator_bytes(args.context_separator, none)

	args = must_apply([
		UpdateStep{'no-context-separator', flag_switch(true)},
		UpdateStep{'context-separator', flag_value('XYZ')},
	])
	assert_context_separator_bytes(args.context_separator, 'XYZ'.bytes())

	args = must_apply([UpdateStep{'context-separator', flag_value(r'\x00')}])
	assert_context_separator_bytes(args.context_separator, [u8(0)])
}

fn test_update_encoding() {
	assert must_apply([]UpdateStep{}).encoding == encoding_auto()
	assert must_apply([UpdateStep{'encoding', flag_value('auto')}]).encoding == encoding_auto()
	assert must_apply([UpdateStep{'encoding', flag_value('none')}]).encoding == encoding_disabled()
	assert must_apply([
		UpdateStep{'encoding', flag_value('none')},
		UpdateStep{'no-encoding', flag_switch(true)},
	]).encoding == encoding_auto()
	assert must_apply([
		UpdateStep{'no-encoding', flag_switch(true)},
		UpdateStep{'encoding', flag_value('utf-16')},
	]).encoding == encoding_some(new_encoding('utf-16') or { panic(err.msg()) })
	assert must_apply([UpdateStep{'encoding', flag_value('latin1')}]).encoding == encoding_some(new_encoding('windows-1252') or {
		panic(err.msg())
	})
}

fn test_update_engine() {
	assert must_apply([]UpdateStep{}).engine == .default
	assert must_apply([UpdateStep{'engine', flag_value('pcre2')}]).engine == .pcre2
	assert must_apply([
		UpdateStep{'auto-hybrid-regex', flag_switch(true)},
		UpdateStep{'engine', flag_value('pcre2')},
	]).engine == .pcre2
	assert must_apply([
		UpdateStep{'engine', flag_value('pcre2')},
		UpdateStep{'auto-hybrid-regex', flag_switch(true)},
	]).engine == .auto
	assert must_apply([
		UpdateStep{'engine', flag_value('pcre2')},
		UpdateStep{'no-auto-hybrid-regex', flag_switch(true)},
	]).engine == .default
}

fn test_update_generate() {
	assert must_apply([]UpdateStep{}).mode == mode_search(.standard)
	assert must_apply([UpdateStep{'generate', flag_value('man')}]).mode == mode_generate(.man)
	assert must_apply([UpdateStep{'generate', flag_value('complete-bash')}]).mode == mode_generate(.complete_bash)
	assert must_apply([
		UpdateStep{'generate', flag_value('complete-bash')},
		UpdateStep{'generate', flag_value('man')},
	]).mode == mode_generate(.man)
	assert must_apply([
		UpdateStep{'generate', flag_value('man')},
		UpdateStep{'files-with-matches', flag_switch(true)},
	]).mode == mode_search(.files_with_matches)
	assert must_apply([
		UpdateStep{'generate', flag_value('man')},
		UpdateStep{'json', flag_switch(true)},
		UpdateStep{'no-json', flag_switch(true)},
	]).mode == mode_search(.standard)
}

fn test_update_hidden() {
	assert !must_apply([]UpdateStep{}).hidden
	assert must_apply([UpdateStep{'hidden', flag_switch(true)}]).hidden
	assert !must_apply([
		UpdateStep{'hidden', flag_switch(true)},
		UpdateStep{'no-hidden', flag_switch(true)},
	]).hidden
	assert must_apply([
		UpdateStep{'no-hidden', flag_switch(true)},
		UpdateStep{'hidden', flag_switch(true)},
	]).hidden
}

fn test_update_hyperlink_format() {
	args := must_apply([]UpdateStep{})
	assert args.hyperlink_format == parse_hyperlink_format('none') or { panic(err.msg()) }

	args = must_apply([UpdateStep{'hyperlink-format', flag_value('file')}])
	assert args.hyperlink_format == parse_hyperlink_format('file://{host}{path}') or {
		panic(err.msg())
	}

	args = must_apply([
		UpdateStep{'hyperlink-format', flag_value('file')},
		UpdateStep{'hyperlink-format', flag_value('grep+')},
	])
	assert args.hyperlink_format == parse_hyperlink_format('grep+://{path}:{line}') or {
		panic(err.msg())
	}
}

fn test_update_json() {
	assert must_apply([]UpdateStep{}).mode == mode_search(.standard)
	assert must_apply([UpdateStep{'json', flag_switch(true)}]).mode == mode_search(.json)
	assert must_apply([
		UpdateStep{'json', flag_switch(true)},
		UpdateStep{'no-json', flag_switch(true)},
	]).mode == mode_search(.standard)
	assert must_apply([
		UpdateStep{'json', flag_switch(true)},
		UpdateStep{'files', flag_switch(true)},
		UpdateStep{'no-json', flag_switch(true)},
	]).mode == mode_files()
}

fn test_update_line_number() {
	assert must_apply([]UpdateStep{}).line_number == none
	assert_opt_bool(must_apply([UpdateStep{'line-number', flag_switch(true)}]).line_number,
		true)
	assert_opt_bool(must_apply([UpdateStep{'no-line-number', flag_switch(true)}]).line_number,
		false)
	assert_opt_bool(must_apply([
		UpdateStep{'no-line-number', flag_switch(true)},
		UpdateStep{'line-number', flag_switch(true)},
	]).line_number, true)
}

fn test_update_path_separator() {
	assert must_apply([]UpdateStep{}).path_separator == none
	assert_opt_u8(must_apply([UpdateStep{'path-separator', flag_value('/')}]).path_separator,
		`/`)
	assert_opt_u8(must_apply([UpdateStep{'path-separator', flag_value(r'\x00')}]).path_separator,
		u8(0))
	assert_opt_u8(must_apply([
		UpdateStep{'path-separator', flag_value(r'\x00')},
		UpdateStep{'path-separator', flag_value('/')},
	]).path_separator, `/`)
}

fn test_update_pre() {
	assert must_apply([]UpdateStep{}).pre == none
	assert_opt_string(must_apply([UpdateStep{'pre', flag_value('foo/bar')}]).pre, 'foo/bar')
	assert must_apply([UpdateStep{'pre', flag_value('')}]).pre == none
	assert must_apply([
		UpdateStep{'pre', flag_value('foo/bar')},
		UpdateStep{'pre', flag_value('')},
	]).pre == none
	assert must_apply([
		UpdateStep{'pre', flag_value('foo/bar')},
		UpdateStep{'no-pre', flag_switch(true)},
	]).pre == none
}

fn test_update_sort_and_sortr() {
	assert must_apply([]UpdateStep{}).sort == none
	assert_opt_sort_mode(must_apply([UpdateStep{'sort', flag_value('path')}]).sort, SortMode{
		reverse: false
		kind:    .path
	})
	assert must_apply([UpdateStep{'sort', flag_value('none')}]).sort == none
	assert_opt_sort_mode(must_apply([UpdateStep{'sortr', flag_value('created')}]).sort,
		SortMode{
		reverse: true
		kind:    .created
	})
	assert_opt_sort_mode(must_apply([
		UpdateStep{'sort', flag_value('path')},
		UpdateStep{'sortr', flag_value('path')},
	]).sort, SortMode{
		reverse: true
		kind:    .path
	})
	assert_opt_sort_mode(must_apply([
		UpdateStep{'sortr', flag_value('path')},
		UpdateStep{'sort', flag_value('path')},
	]).sort, SortMode{
		reverse: false
		kind:    .path
	})
}

fn test_update_stop_on_nonmatch() {
	assert !must_apply([]UpdateStep{}).stop_on_nonmatch

	args := must_apply([UpdateStep{'stop-on-nonmatch', flag_switch(true)}])
	assert args.stop_on_nonmatch

	args = must_apply([
		UpdateStep{'stop-on-nonmatch', flag_switch(true)},
		UpdateStep{'multiline', flag_switch(true)},
	])
	assert args.multiline
	assert !args.stop_on_nonmatch

	args = must_apply([
		UpdateStep{'multiline', flag_switch(true)},
		UpdateStep{'stop-on-nonmatch', flag_switch(true)},
	])
	assert !args.multiline
	assert args.stop_on_nonmatch
}

fn test_update_text() {
	assert must_apply([]UpdateStep{}).binary == .auto
	assert must_apply([UpdateStep{'text', flag_switch(true)}]).binary == .as_text
	assert must_apply([
		UpdateStep{'text', flag_switch(true)},
		UpdateStep{'no-text', flag_switch(true)},
	]).binary == .auto
	assert must_apply([
		UpdateStep{'text', flag_switch(true)},
		UpdateStep{'binary', flag_switch(true)},
	]).binary == .search_and_suppress
	assert must_apply([
		UpdateStep{'binary', flag_switch(true)},
		UpdateStep{'text', flag_switch(true)},
	]).binary == .as_text
}

fn test_update_threads() {
	assert must_apply([]UpdateStep{}).threads == none
	assert_opt_usize(must_apply([UpdateStep{'threads', flag_value('5')}]).threads, 5)
	assert must_apply([UpdateStep{'threads', flag_value('0')}]).threads == none
}

fn test_update_type_changes() {
	assert must_apply([]UpdateStep{}).type_changes == []TypeChange{}
	assert must_apply([UpdateStep{'type', flag_value('rust')}]).type_changes == [
		select_type('rust'),
	]
	assert must_apply([UpdateStep{'type-add', flag_value('foo')}]).type_changes == [
		add_type('foo'),
	]
	assert must_apply([UpdateStep{'type-clear', flag_value('foo')}]).type_changes == [
		clear_type('foo'),
	]
	assert must_apply([UpdateStep{'type-not', flag_value('rust')}]).type_changes == [
		negate_type('rust'),
	]
	assert must_apply([
		UpdateStep{'type-not', flag_value('rust')},
		UpdateStep{'type', flag_value('toml')},
		UpdateStep{'type-not', flag_value('json')},
	]).type_changes == [negate_type('rust'), select_type('toml'),
		negate_type('json')]
}

fn test_update_unrestricted() {
	args := must_apply([]UpdateStep{})
	assert !args.no_ignore_vcs
	assert !args.hidden
	assert args.binary == .auto

	args = must_apply([UpdateStep{'unrestricted', flag_switch(true)}])
	assert args.no_ignore_vcs
	assert !args.hidden
	assert args.binary == .auto

	args = must_apply([
		UpdateStep{'unrestricted', flag_switch(true)},
		UpdateStep{'unrestricted', flag_switch(true)},
	])
	assert args.no_ignore_vcs
	assert args.hidden
	assert args.binary == .auto

	args = must_apply([
		UpdateStep{'unrestricted', flag_switch(true)},
		UpdateStep{'unrestricted', flag_switch(true)},
		UpdateStep{'unrestricted', flag_switch(true)},
	])
	assert args.no_ignore_vcs
	assert args.hidden
	assert args.binary == .search_and_suppress
}

fn test_update_with_filename() {
	assert must_apply([]UpdateStep{}).with_filename == none
	assert_opt_bool(must_apply([UpdateStep{'with-filename', flag_switch(true)}]).with_filename,
		true)
	assert_opt_bool(must_apply([UpdateStep{'no-filename', flag_switch(true)}]).with_filename,
		false)
	assert_opt_bool(must_apply([
		UpdateStep{'no-filename', flag_switch(true)},
		UpdateStep{'with-filename', flag_switch(true)},
	]).with_filename, true)
}

fn test_update_word_regexp() {
	assert must_apply([]UpdateStep{}).boundary == none
	assert_opt_boundary(must_apply([UpdateStep{'word-regexp', flag_switch(true)}]).boundary,
		.word)
	assert_opt_boundary(must_apply([
		UpdateStep{'line-regexp', flag_switch(true)},
		UpdateStep{'word-regexp', flag_switch(true)},
	]).boundary, .word)
	assert_opt_boundary(must_apply([
		UpdateStep{'word-regexp', flag_switch(true)},
		UpdateStep{'line-regexp', flag_switch(true)},
	]).boundary, .line)
}

fn test_shorts_all_ascii_alphanumeric() {
	for id in flags {
		short := id.name_short() or { continue }
		assert short.is_alnum() || short == `.`
	}
}

fn test_longs_all_ascii_alphanumeric() {
	for id in flags {
		long := id.name_long()
		assert long.len >= 2
		for ch in long.bytes() {
			assert ch.is_alnum() || ch == `-`
		}
		for alias in id.aliases() {
			assert alias.len >= 2
			for ch in alias.bytes() {
				assert ch.is_alnum() || ch == `-`
			}
		}
		negated := id.name_negated() or { continue }
		assert negated.len >= 2
		for ch in negated.bytes() {
			assert ch.is_alnum() || ch == `-`
		}
	}
}

fn test_shorts_no_duplicates() {
	mut taken := map[u8]bool{}
	for id in flags {
		short := id.name_short() or { continue }
		assert short !in taken
		taken[short] = true
	}
}

fn test_longs_no_duplicates() {
	mut taken := map[string]bool{}
	for id in flags {
		long := id.name_long()
		assert long !in taken
		taken[long] = true
		for alias in id.aliases() {
			assert alias !in taken
			taken[alias] = true
		}
		negated := id.name_negated() or { continue }
		assert negated !in taken
		taken[negated] = true
	}
}

fn test_non_switches_have_variable_names() {
	for id in flags {
		if id.is_switch() {
			continue
		}
		assert id.doc_variable() != none
	}
}

fn test_switches_have_no_choices() {
	for id in flags {
		if !id.is_switch() {
			continue
		}
		assert id.doc_choices().len == 0
	}
}

fn test_choices_ascii_alphanumeric() {
	for id in flags {
		for choice in id.doc_choices() {
			for ch in choice.bytes() {
				assert ch.is_alnum() || ch in [`-`, `:`, `+`]
			}
		}
	}
}
