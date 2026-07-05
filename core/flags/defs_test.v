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

fn before_context(lines usize) ContextMode {
	mut mode := default_context_mode()
	mode.set_before(lines)
	return mode
}

fn both_context(lines usize) ContextMode {
	mut mode := default_context_mode()
	mode.set_both(lines)
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

fn assert_opt_u64(value ?u64, expected u64) {
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

fn assert_opt_special(value ?SpecialMode, expected SpecialMode) {
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

fn user_color_spec(spec string) UserColorSpec {
	return parse_user_color_spec(spec) or { panic(err.msg()) }
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

fn test_after_context() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.context == default_context_mode()

	args = parse_low_raw(['--after-context', '5']) or { panic(err.msg()) }
	assert args.context == after_context(5)

	args = parse_low_raw(['--after-context=5']) or { panic(err.msg()) }
	assert args.context == after_context(5)

	args = parse_low_raw(['-A', '5']) or { panic(err.msg()) }
	assert args.context == after_context(5)

	args = parse_low_raw(['-A5']) or { panic(err.msg()) }
	assert args.context == after_context(5)

	args = parse_low_raw(['-A5', '-A10']) or { panic(err.msg()) }
	assert args.context == after_context(10)

	args = parse_low_raw(['-A5', '-A0']) or { panic(err.msg()) }
	assert args.context == after_context(0)

	args = parse_low_raw(['-A5', '--passthru']) or { panic(err.msg()) }
	assert args.context == passthru_context_mode()

	args = parse_low_raw(['--passthru', '-A5']) or { panic(err.msg()) }
	assert args.context == after_context(5)

	args = parse_low_raw(['--after-context', '18446744073709551615']) or { panic(err.msg()) }
	assert args.context == after_context(usize(-1))

	if _ := parse_low_raw(['--after-context', '18446744073709551616']) {
		assert false
	}
}

fn test_auto_hybrid_regex() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.engine == .default

	args = parse_low_raw(['--auto-hybrid-regex']) or { panic(err.msg()) }
	assert args.engine == .auto

	args = parse_low_raw(['--auto-hybrid-regex', '--no-auto-hybrid-regex']) or {
		panic(err.msg())
	}
	assert args.engine == .default

	args = parse_low_raw(['--no-auto-hybrid-regex', '--auto-hybrid-regex']) or {
		panic(err.msg())
	}
	assert args.engine == .auto

	args = parse_low_raw(['--auto-hybrid-regex', '-P']) or { panic(err.msg()) }
	assert args.engine == .pcre2

	args = parse_low_raw(['-P', '--auto-hybrid-regex']) or { panic(err.msg()) }
	assert args.engine == .auto

	args = parse_low_raw(['--engine=auto', '--auto-hybrid-regex']) or { panic(err.msg()) }
	assert args.engine == .auto

	args = parse_low_raw(['--engine=default', '--auto-hybrid-regex']) or { panic(err.msg()) }
	assert args.engine == .auto

	args = parse_low_raw(['--auto-hybrid-regex', '--engine=default']) or { panic(err.msg()) }
	assert args.engine == .default
}

fn test_before_context() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.context == default_context_mode()

	args = parse_low_raw(['--before-context', '5']) or { panic(err.msg()) }
	assert args.context == before_context(5)

	args = parse_low_raw(['--before-context=5']) or { panic(err.msg()) }
	assert args.context == before_context(5)

	args = parse_low_raw(['-B', '5']) or { panic(err.msg()) }
	assert args.context == before_context(5)

	args = parse_low_raw(['-B5']) or { panic(err.msg()) }
	assert args.context == before_context(5)

	args = parse_low_raw(['-B5', '-B10']) or { panic(err.msg()) }
	assert args.context == before_context(10)

	args = parse_low_raw(['-B5', '-B0']) or { panic(err.msg()) }
	assert args.context == before_context(0)

	args = parse_low_raw(['-B5', '--passthru']) or { panic(err.msg()) }
	assert args.context == passthru_context_mode()

	args = parse_low_raw(['--passthru', '-B5']) or { panic(err.msg()) }
	assert args.context == before_context(5)

	args = parse_low_raw(['--before-context', '18446744073709551615']) or { panic(err.msg()) }
	assert args.context == before_context(usize(-1))

	if _ := parse_low_raw(['--before-context', '18446744073709551616']) {
		assert false
	}
}

fn test_binary() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.binary == .auto

	args = parse_low_raw(['--binary']) or { panic(err.msg()) }
	assert args.binary == .search_and_suppress

	args = parse_low_raw(['--binary', '--no-binary']) or { panic(err.msg()) }
	assert args.binary == .auto

	args = parse_low_raw(['--no-binary', '--binary']) or { panic(err.msg()) }
	assert args.binary == .search_and_suppress

	args = parse_low_raw(['--binary', '-a']) or { panic(err.msg()) }
	assert args.binary == .as_text

	args = parse_low_raw(['-a', '--binary']) or { panic(err.msg()) }
	assert args.binary == .search_and_suppress

	args = parse_low_raw(['-a', '--no-binary']) or { panic(err.msg()) }
	assert args.binary == .auto
}

fn test_block_buffered() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.buffer == .auto

	args = parse_low_raw(['--block-buffered']) or { panic(err.msg()) }
	assert args.buffer == .block

	args = parse_low_raw(['--block-buffered', '--no-block-buffered']) or { panic(err.msg()) }
	assert args.buffer == .auto

	args = parse_low_raw(['--block-buffered', '--line-buffered']) or { panic(err.msg()) }
	assert args.buffer == .line
}

fn test_byte_offset() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.byte_offset

	args = parse_low_raw(['--byte-offset']) or { panic(err.msg()) }
	assert args.byte_offset

	args = parse_low_raw(['-b']) or { panic(err.msg()) }
	assert args.byte_offset

	args = parse_low_raw(['--byte-offset', '--no-byte-offset']) or { panic(err.msg()) }
	assert !args.byte_offset

	args = parse_low_raw(['--no-byte-offset', '-b']) or { panic(err.msg()) }
	assert args.byte_offset
}

fn test_case_sensitive() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.case == .sensitive

	args = parse_low_raw(['--case-sensitive']) or { panic(err.msg()) }
	assert args.case == .sensitive

	args = parse_low_raw(['-s']) or { panic(err.msg()) }
	assert args.case == .sensitive
}

fn test_color() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.color == .auto

	args = parse_low_raw(['--color', 'never']) or { panic(err.msg()) }
	assert args.color == .never

	args = parse_low_raw(['--color', 'auto']) or { panic(err.msg()) }
	assert args.color == .auto

	args = parse_low_raw(['--color', 'always']) or { panic(err.msg()) }
	assert args.color == .always

	args = parse_low_raw(['--color', 'ansi']) or { panic(err.msg()) }
	assert args.color == .ansi

	args = parse_low_raw(['--color=never']) or { panic(err.msg()) }
	assert args.color == .never

	args = parse_low_raw(['--color', 'always', '--color', 'never']) or { panic(err.msg()) }
	assert args.color == .never

	args = parse_low_raw(['--color', 'never', '--color', 'always']) or { panic(err.msg()) }
	assert args.color == .always

	if _ := parse_low_raw(['--color', 'foofoo']) {
		assert false
	}

	if _ := parse_low_raw(['--color', 'Always']) {
		assert false
	}
}

fn test_colors() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.colors.len == 0

	args = parse_low_raw(['--colors', 'match:fg:magenta']) or { panic(err.msg()) }
	assert args.colors == [user_color_spec('match:fg:magenta')]

	args = parse_low_raw(['--colors', 'match:fg:magenta', '--colors', 'line:bg:yellow']) or {
		panic(err.msg())
	}
	assert args.colors == [user_color_spec('match:fg:magenta'), user_color_spec('line:bg:yellow')]

	args = parse_low_raw(['--colors', 'highlight:bg:240']) or { panic(err.msg()) }
	assert args.colors == [user_color_spec('highlight:bg:240')]

	args = parse_low_raw(['--colors', 'match:fg:magenta', '--colors', 'highlight:bg:blue']) or {
		panic(err.msg())
	}
	assert args.colors == [user_color_spec('match:fg:magenta'), user_color_spec('highlight:bg:blue')]
}

fn test_column() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.column == none

	args = parse_low_raw(['--column']) or { panic(err.msg()) }
	assert_opt_bool(args.column, true)

	args = parse_low_raw(['--column', '--no-column']) or { panic(err.msg()) }
	assert_opt_bool(args.column, false)

	args = parse_low_raw(['--no-column', '--column']) or { panic(err.msg()) }
	assert_opt_bool(args.column, true)
}

fn test_context() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.context == default_context_mode()

	args = parse_low_raw(['--context', '5']) or { panic(err.msg()) }
	assert args.context == both_context(5)

	args = parse_low_raw(['--context=5']) or { panic(err.msg()) }
	assert args.context == both_context(5)

	args = parse_low_raw(['-C', '5']) or { panic(err.msg()) }
	assert args.context == both_context(5)

	args = parse_low_raw(['-C5']) or { panic(err.msg()) }
	assert args.context == both_context(5)

	args = parse_low_raw(['-C5', '-C10']) or { panic(err.msg()) }
	assert args.context == both_context(10)

	args = parse_low_raw(['-C5', '-C0']) or { panic(err.msg()) }
	assert args.context == both_context(0)

	args = parse_low_raw(['-C5', '--passthru']) or { panic(err.msg()) }
	assert args.context == passthru_context_mode()

	args = parse_low_raw(['--passthru', '-C5']) or { panic(err.msg()) }
	assert args.context == both_context(5)

	args = parse_low_raw(['--context', '18446744073709551615']) or { panic(err.msg()) }
	assert args.context == both_context(usize(-1))

	if _ := parse_low_raw(['--context', '18446744073709551616']) {
		assert false
	}

	// Test the interaction between -A/-B and -C. Basically, -A/-B always
	// partially overrides -C, regardless of where they appear relative to
	// each other. This behavior is also how GNU grep works, and it also makes
	// logical sense to me: -A/-B are the more specific flags.
	args = parse_low_raw(['-A1', '-C5']) or { panic(err.msg()) }
	mut mode := default_context_mode()
	mode.set_after(1)
	mode.set_both(5)
	assert mode == args.context
	mut before, mut after := args.context.get_limited()
	assert before == 5
	assert after == 1

	args = parse_low_raw(['-B1', '-C5']) or { panic(err.msg()) }
	mode = default_context_mode()
	mode.set_before(1)
	mode.set_both(5)
	assert mode == args.context
	before, after = args.context.get_limited()
	assert before == 1
	assert after == 5

	args = parse_low_raw(['-A1', '-B2', '-C5']) or { panic(err.msg()) }
	mode = default_context_mode()
	mode.set_before(2)
	mode.set_after(1)
	mode.set_both(5)
	assert mode == args.context
	before, after = args.context.get_limited()
	assert before == 2
	assert after == 1

	// These next three are like the ones above, but with -C before -A/-B. This
	// tests that -A and -B only partially override -C. That is, -C1 -A2 is
	// equivalent to -B1 -A2.
	args = parse_low_raw(['-C5', '-A1']) or { panic(err.msg()) }
	mode = default_context_mode()
	mode.set_after(1)
	mode.set_both(5)
	assert mode == args.context
	before, after = args.context.get_limited()
	assert before == 5
	assert after == 1

	args = parse_low_raw(['-C5', '-B1']) or { panic(err.msg()) }
	mode = default_context_mode()
	mode.set_before(1)
	mode.set_both(5)
	assert mode == args.context
	before, after = args.context.get_limited()
	assert before == 1
	assert after == 5

	args = parse_low_raw(['-C5', '-A1', '-B2']) or { panic(err.msg()) }
	mode = default_context_mode()
	mode.set_before(2)
	mode.set_after(1)
	mode.set_both(5)
	assert mode == args.context
	before, after = args.context.get_limited()
	assert before == 2
	assert after == 1
}

fn test_context_separator() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert_context_separator_bytes(args.context_separator, '--'.bytes())

	args = parse_low_raw(['--context-separator', 'XYZ']) or { panic(err.msg()) }
	assert_context_separator_bytes(args.context_separator, 'XYZ'.bytes())

	args = parse_low_raw(['--no-context-separator']) or { panic(err.msg()) }
	assert_context_separator_bytes(args.context_separator, none)

	args = parse_low_raw(['--context-separator', 'XYZ', '--no-context-separator']) or {
		panic(err.msg())
	}
	assert_context_separator_bytes(args.context_separator, none)

	args = parse_low_raw(['--no-context-separator', '--context-separator', 'XYZ']) or {
		panic(err.msg())
	}
	assert_context_separator_bytes(args.context_separator, 'XYZ'.bytes())

	// This checks that invalid UTF-8 can be used. This case isn't too tricky
	// to handle, because it passes the invalid UTF-8 as an escape sequence
	// that is itself valid UTF-8. It doesn't become invalid UTF-8 until after
	// the argument is parsed and then unescaped.
	args = parse_low_raw(['--context-separator', r'\xFF']) or { panic(err.msg()) }
	assert_context_separator_bytes(args.context_separator, [u8(0xff)])

	// In this case, we specifically try to pass an invalid UTF-8 argument to
	// the flag. In theory we might be able to support this, but because we do
	// unescaping and because unescaping wants valid UTF-8, we do a UTF-8 check
	// on the value. Since we pass invalid UTF-8, it fails. This demonstrates
	// that the only way to use an invalid UTF-8 separator is by specifying an
	// escape sequence that is itself valid UTF-8.
	if _ := parse_low_raw(['--context-separator', [u8(0xff)].bytestr()]) {
		assert false
	}
}

fn test_count() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.mode == mode_search(.standard)

	args = parse_low_raw(['--count']) or { panic(err.msg()) }
	assert args.mode == mode_search(.count)

	args = parse_low_raw(['-c']) or { panic(err.msg()) }
	assert args.mode == mode_search(.count)

	args = parse_low_raw(['--count-matches', '--count']) or { panic(err.msg()) }
	assert args.mode == mode_search(.count)

	args = parse_low_raw(['--count-matches', '-c']) or { panic(err.msg()) }
	assert args.mode == mode_search(.count)
}

fn test_count_matches() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.mode == mode_search(.standard)

	args = parse_low_raw(['--count-matches']) or { panic(err.msg()) }
	assert args.mode == mode_search(.count_matches)

	args = parse_low_raw(['--count', '--count-matches']) or { panic(err.msg()) }
	assert args.mode == mode_search(.count_matches)

	args = parse_low_raw(['-c', '--count-matches']) or { panic(err.msg()) }
	assert args.mode == mode_search(.count_matches)
}

fn test_crlf() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.crlf

	args = parse_low_raw(['--crlf']) or { panic(err.msg()) }
	assert args.crlf
	assert !args.null_data

	args = parse_low_raw(['--crlf', '--null-data']) or { panic(err.msg()) }
	assert !args.crlf
	assert args.null_data

	args = parse_low_raw(['--null-data', '--crlf']) or { panic(err.msg()) }
	assert args.crlf
	assert !args.null_data

	args = parse_low_raw(['--null-data', '--no-crlf']) or { panic(err.msg()) }
	assert !args.crlf
	assert args.null_data

	args = parse_low_raw(['--null-data', '--crlf', '--no-crlf']) or { panic(err.msg()) }
	assert !args.crlf
	assert !args.null_data
}

fn test_debug() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.has_logging

	args = parse_low_raw(['--debug']) or { panic(err.msg()) }
	assert args.has_logging
	assert args.logging == .debug

	args = parse_low_raw(['--trace', '--debug']) or { panic(err.msg()) }
	assert args.has_logging
	assert args.logging == .debug
}

fn test_dfa_size_limit() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.dfa_size_limit == none

	args = parse_low_raw(['--dfa-size-limit', '9G']) or { panic(err.msg()) }
	assert_opt_usize(args.dfa_size_limit, usize(9) * (usize(1) << 30))

	args = parse_low_raw(['--dfa-size-limit=9G']) or { panic(err.msg()) }
	assert_opt_usize(args.dfa_size_limit, usize(9) * (usize(1) << 30))

	args = parse_low_raw(['--dfa-size-limit=9G', '--dfa-size-limit=0']) or {
		panic(err.msg())
	}
	assert_opt_usize(args.dfa_size_limit, 0)

	args = parse_low_raw(['--dfa-size-limit=0K']) or { panic(err.msg()) }
	assert_opt_usize(args.dfa_size_limit, 0)

	args = parse_low_raw(['--dfa-size-limit=0M']) or { panic(err.msg()) }
	assert_opt_usize(args.dfa_size_limit, 0)

	args = parse_low_raw(['--dfa-size-limit=0G']) or { panic(err.msg()) }
	assert_opt_usize(args.dfa_size_limit, 0)

	if _ := parse_low_raw(['--dfa-size-limit', '9999999999999999999999']) {
		assert false
	}

	if _ := parse_low_raw(['--dfa-size-limit', '9999999999999999G']) {
		assert false
	}
}

fn test_encoding() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.encoding == encoding_auto()

	args = parse_low_raw(['--encoding', 'auto']) or { panic(err.msg()) }
	assert args.encoding == encoding_auto()

	args = parse_low_raw(['--encoding', 'none']) or { panic(err.msg()) }
	assert args.encoding == encoding_disabled()

	args = parse_low_raw(['--encoding=none']) or { panic(err.msg()) }
	assert args.encoding == encoding_disabled()

	args = parse_low_raw(['-E', 'none']) or { panic(err.msg()) }
	assert args.encoding == encoding_disabled()

	args = parse_low_raw(['-Enone']) or { panic(err.msg()) }
	assert args.encoding == encoding_disabled()

	args = parse_low_raw(['-E', 'none', '--no-encoding']) or { panic(err.msg()) }
	assert args.encoding == encoding_auto()

	args = parse_low_raw(['--no-encoding', '-E', 'none']) or { panic(err.msg()) }
	assert args.encoding == encoding_disabled()

	args = parse_low_raw(['-E', 'utf-16']) or { panic(err.msg()) }
	enc := new_encoding('utf-16') or { panic(err.msg()) }
	assert args.encoding == encoding_some(enc)

	args = parse_low_raw(['-E', 'utf-16', '--no-encoding']) or { panic(err.msg()) }
	assert args.encoding == encoding_auto()

	if _ := parse_low_raw(['-E', 'foo']) {
		assert false
	}
}

fn test_engine() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.engine == .default

	args = parse_low_raw(['--engine', 'pcre2']) or { panic(err.msg()) }
	assert args.engine == .pcre2

	args = parse_low_raw(['--engine=pcre2']) or { panic(err.msg()) }
	assert args.engine == .pcre2

	args = parse_low_raw(['--auto-hybrid-regex', '--engine=pcre2']) or { panic(err.msg()) }
	assert args.engine == .pcre2

	args = parse_low_raw(['--engine=pcre2', '--auto-hybrid-regex']) or { panic(err.msg()) }
	assert args.engine == .auto

	args = parse_low_raw(['--auto-hybrid-regex', '--engine=auto']) or { panic(err.msg()) }
	assert args.engine == .auto

	args = parse_low_raw(['--auto-hybrid-regex', '--engine=default']) or { panic(err.msg()) }
	assert args.engine == .default

	args = parse_low_raw(['--engine=pcre2', '--no-auto-hybrid-regex']) or { panic(err.msg()) }
	assert args.engine == .default
}

fn test_field_context_separator() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.field_context_separator.into_bytes() == '-'.bytes()

	args = parse_low_raw(['--field-context-separator', 'XYZ']) or { panic(err.msg()) }
	assert args.field_context_separator.into_bytes() == 'XYZ'.bytes()

	args = parse_low_raw(['--field-context-separator=XYZ']) or { panic(err.msg()) }
	assert args.field_context_separator.into_bytes() == 'XYZ'.bytes()

	args = parse_low_raw(['--field-context-separator', 'XYZ', '--field-context-separator',
		'ABC']) or {
		panic(err.msg())
	}
	assert args.field_context_separator.into_bytes() == 'ABC'.bytes()

	args = parse_low_raw(['--field-context-separator', r'\t']) or { panic(err.msg()) }
	assert args.field_context_separator.into_bytes() == '\t'.bytes()

	args = parse_low_raw(['--field-context-separator', r'\x00']) or { panic(err.msg()) }
	assert args.field_context_separator.into_bytes() == [u8(0)]

	// This checks that invalid UTF-8 can be used. This case isn't too tricky
	// to handle, because it passes the invalid UTF-8 as an escape sequence
	// that is itself valid UTF-8. It doesn't become invalid UTF-8 until after
	// the argument is parsed and then unescaped.
	args = parse_low_raw(['--field-context-separator', r'\xFF']) or { panic(err.msg()) }
	assert args.field_context_separator.into_bytes() == [u8(0xff)]

	// In this case, we specifically try to pass an invalid UTF-8 argument to
	// the flag. In theory we might be able to support this, but because we do
	// unescaping and because unescaping wants valid UTF-8, we do a UTF-8 check
	// on the value. Since we pass invalid UTF-8, it fails. This demonstrates
	// that the only way to use an invalid UTF-8 separator is by specifying an
	// escape sequence that is itself valid UTF-8.
	if _ := parse_low_raw(['--field-context-separator', [u8(0xff)].bytestr()]) {
		assert false
	}
}

fn test_field_match_separator() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.field_match_separator.into_bytes() == ':'.bytes()

	args = parse_low_raw(['--field-match-separator', 'XYZ']) or { panic(err.msg()) }
	assert args.field_match_separator.into_bytes() == 'XYZ'.bytes()

	args = parse_low_raw(['--field-match-separator=XYZ']) or { panic(err.msg()) }
	assert args.field_match_separator.into_bytes() == 'XYZ'.bytes()

	args = parse_low_raw(['--field-match-separator', 'XYZ', '--field-match-separator',
		'ABC']) or {
		panic(err.msg())
	}
	assert args.field_match_separator.into_bytes() == 'ABC'.bytes()

	args = parse_low_raw(['--field-match-separator', r'\t']) or { panic(err.msg()) }
	assert args.field_match_separator.into_bytes() == '\t'.bytes()

	args = parse_low_raw(['--field-match-separator', r'\x00']) or { panic(err.msg()) }
	assert args.field_match_separator.into_bytes() == [u8(0)]

	// This checks that invalid UTF-8 can be used. This case isn't too tricky
	// to handle, because it passes the invalid UTF-8 as an escape sequence
	// that is itself valid UTF-8. It doesn't become invalid UTF-8 until after
	// the argument is parsed and then unescaped.
	args = parse_low_raw(['--field-match-separator', r'\xFF']) or { panic(err.msg()) }
	assert args.field_match_separator.into_bytes() == [u8(0xff)]

	// In this case, we specifically try to pass an invalid UTF-8 argument to
	// the flag. In theory we might be able to support this, but because we do
	// unescaping and because unescaping wants valid UTF-8, we do a UTF-8 check
	// on the value. Since we pass invalid UTF-8, it fails. This demonstrates
	// that the only way to use an invalid UTF-8 separator is by specifying an
	// escape sequence that is itself valid UTF-8.
	if _ := parse_low_raw(['--field-match-separator', [u8(0xff)].bytestr()]) {
		assert false
	}
}

fn test_file() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.patterns == []PatternSource{}

	args = parse_low_raw(['--file', 'foo']) or { panic(err.msg()) }
	assert args.patterns == [pattern_file('foo')]

	args = parse_low_raw(['--file=foo']) or { panic(err.msg()) }
	assert args.patterns == [pattern_file('foo')]

	args = parse_low_raw(['-f', 'foo']) or { panic(err.msg()) }
	assert args.patterns == [pattern_file('foo')]

	args = parse_low_raw(['-ffoo']) or { panic(err.msg()) }
	assert args.patterns == [pattern_file('foo')]

	args = parse_low_raw(['--file', '-foo']) or { panic(err.msg()) }
	assert args.patterns == [pattern_file('-foo')]

	args = parse_low_raw(['--file=-foo']) or { panic(err.msg()) }
	assert args.patterns == [pattern_file('-foo')]

	args = parse_low_raw(['-f', '-foo']) or { panic(err.msg()) }
	assert args.patterns == [pattern_file('-foo')]

	args = parse_low_raw(['-f-foo']) or { panic(err.msg()) }
	assert args.patterns == [pattern_file('-foo')]

	args = parse_low_raw(['--file=foo', '--file', 'bar']) or { panic(err.msg()) }
	assert args.patterns == [pattern_file('foo'), pattern_file('bar')]

	// We permit path arguments to be invalid UTF-8. So test that. Some of
	// these cases are tricky and depend on lexopt doing the right thing.
	//
	// We probably should add tests for this handling on Windows too, but paths
	// that are invalid UTF-16 appear incredibly rare in the Windows world.
	path := [u8(`A`), 0xff, `Z`].bytestr()

	args = parse_low_raw(['--file', path]) or { panic(err.msg()) }
	assert args.patterns == [pattern_file(path)]

	args = parse_low_raw(['-f', path]) or { panic(err.msg()) }
	assert args.patterns == [pattern_file(path)]

	args = parse_low_raw(['--file=' + path]) or { panic(err.msg()) }
	assert args.patterns == [pattern_file(path)]

	args = parse_low_raw(['-f' + path]) or { panic(err.msg()) }
	assert args.patterns == [pattern_file(path)]
}

fn test_files() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.mode == mode_search(.standard)

	args = parse_low_raw(['--files']) or { panic(err.msg()) }
	assert args.mode == mode_files()
}

fn test_files_with_matches() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.mode == mode_search(.standard)

	args = parse_low_raw(['--files-with-matches']) or { panic(err.msg()) }
	assert args.mode == mode_search(.files_with_matches)

	args = parse_low_raw(['-l']) or { panic(err.msg()) }
	assert args.mode == mode_search(.files_with_matches)
}

fn test_files_without_match() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.mode == mode_search(.standard)

	args = parse_low_raw(['--files-without-match']) or { panic(err.msg()) }
	assert args.mode == mode_search(.files_without_match)

	args = parse_low_raw(['--files-with-matches', '--files-without-match']) or {
		panic(err.msg())
	}
	assert args.mode == mode_search(.files_without_match)

	args = parse_low_raw(['--files-without-match', '--files-with-matches']) or {
		panic(err.msg())
	}
	assert args.mode == mode_search(.files_with_matches)
}

fn test_fixed_strings() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.fixed_strings

	args = parse_low_raw(['--fixed-strings']) or { panic(err.msg()) }
	assert args.fixed_strings

	args = parse_low_raw(['-F']) or { panic(err.msg()) }
	assert args.fixed_strings

	args = parse_low_raw(['-F', '--no-fixed-strings']) or { panic(err.msg()) }
	assert !args.fixed_strings

	args = parse_low_raw(['--no-fixed-strings', '-F']) or { panic(err.msg()) }
	assert args.fixed_strings
}

fn test_follow() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.follow

	args = parse_low_raw(['--follow']) or { panic(err.msg()) }
	assert args.follow

	args = parse_low_raw(['-L']) or { panic(err.msg()) }
	assert args.follow

	args = parse_low_raw(['-L', '--no-follow']) or { panic(err.msg()) }
	assert !args.follow

	args = parse_low_raw(['--no-follow', '-L']) or { panic(err.msg()) }
	assert args.follow
}

fn test_generate() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.mode == mode_search(.standard)

	args = parse_low_raw(['--generate', 'man']) or { panic(err.msg()) }
	assert args.mode == mode_generate(.man)

	args = parse_low_raw(['--generate', 'complete-bash']) or { panic(err.msg()) }
	assert args.mode == mode_generate(.complete_bash)

	args = parse_low_raw(['--generate', 'complete-zsh']) or { panic(err.msg()) }
	assert args.mode == mode_generate(.complete_zsh)

	args = parse_low_raw(['--generate', 'complete-fish']) or { panic(err.msg()) }
	assert args.mode == mode_generate(.complete_fish)

	args = parse_low_raw(['--generate', 'complete-powershell']) or { panic(err.msg()) }
	assert args.mode == mode_generate(.complete_powershell)

	args = parse_low_raw(['--generate', 'complete-bash', '--generate=man']) or { panic(err.msg()) }
	assert args.mode == mode_generate(.man)

	args = parse_low_raw(['--generate', 'man', '-l']) or { panic(err.msg()) }
	assert args.mode == mode_search(.files_with_matches)

	// An interesting quirk of how the modes override each other that lets
	// you get back to the "default" mode of searching.
	args = parse_low_raw(['--generate', 'man', '--json', '--no-json']) or { panic(err.msg()) }
	assert args.mode == mode_search(.standard)
}

fn test_glob() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.globs == []string{}

	args = parse_low_raw(['--glob', 'foo']) or { panic(err.msg()) }
	assert args.globs == ['foo']

	args = parse_low_raw(['--glob=foo']) or { panic(err.msg()) }
	assert args.globs == ['foo']

	args = parse_low_raw(['-g', 'foo']) or { panic(err.msg()) }
	assert args.globs == ['foo']

	args = parse_low_raw(['-gfoo']) or { panic(err.msg()) }
	assert args.globs == ['foo']

	args = parse_low_raw(['--glob', '-foo']) or { panic(err.msg()) }
	assert args.globs == ['-foo']

	args = parse_low_raw(['--glob=-foo']) or { panic(err.msg()) }
	assert args.globs == ['-foo']

	args = parse_low_raw(['-g', '-foo']) or { panic(err.msg()) }
	assert args.globs == ['-foo']

	args = parse_low_raw(['-g-foo']) or { panic(err.msg()) }
	assert args.globs == ['-foo']
}

fn test_glob_case_insensitive() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.glob_case_insensitive

	args = parse_low_raw(['--glob-case-insensitive']) or { panic(err.msg()) }
	assert args.glob_case_insensitive

	args = parse_low_raw(['--glob-case-insensitive', '--no-glob-case-insensitive']) or {
		panic(err.msg())
	}
	assert !args.glob_case_insensitive

	args = parse_low_raw(['--no-glob-case-insensitive', '--glob-case-insensitive']) or {
		panic(err.msg())
	}
	assert args.glob_case_insensitive
}

fn test_heading() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.heading == none

	args = parse_low_raw(['--heading']) or { panic(err.msg()) }
	assert_opt_bool(args.heading, true)

	args = parse_low_raw(['--no-heading']) or { panic(err.msg()) }
	assert_opt_bool(args.heading, false)

	args = parse_low_raw(['--heading', '--no-heading']) or { panic(err.msg()) }
	assert_opt_bool(args.heading, false)

	args = parse_low_raw(['--no-heading', '--heading']) or { panic(err.msg()) }
	assert_opt_bool(args.heading, true)
}

fn test_help() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.special == none

	args = parse_low_raw(['-h']) or { panic(err.msg()) }
	assert_opt_special(args.special, .help_short)

	args = parse_low_raw(['--help']) or { panic(err.msg()) }
	assert_opt_special(args.special, .help_long)

	args = parse_low_raw(['-h', '--help']) or { panic(err.msg()) }
	assert_opt_special(args.special, .help_long)

	args = parse_low_raw(['--help', '-h']) or { panic(err.msg()) }
	assert_opt_special(args.special, .help_short)
}

fn test_hidden() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.hidden

	args = parse_low_raw(['--hidden']) or { panic(err.msg()) }
	assert args.hidden

	args = parse_low_raw(['-.']) or { panic(err.msg()) }
	assert args.hidden

	args = parse_low_raw(['-.', '--no-hidden']) or { panic(err.msg()) }
	assert !args.hidden

	args = parse_low_raw(['--no-hidden', '-.']) or { panic(err.msg()) }
	assert args.hidden
}

fn test_hostname_bin() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.hostname_bin == none

	args = parse_low_raw(['--hostname-bin', 'foo']) or { panic(err.msg()) }
	assert_opt_string(args.hostname_bin, 'foo')

	args = parse_low_raw(['--hostname-bin=foo']) or { panic(err.msg()) }
	assert_opt_string(args.hostname_bin, 'foo')
}

fn test_hyperlink_format() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.hyperlink_format == parse_hyperlink_format('none') or { panic(err.msg()) }

	args = parse_low_raw(['--hyperlink-format', 'default']) or { panic(err.msg()) }
	assert args.hyperlink_format == parse_hyperlink_format('file://{host}{path}') or {
		panic(err.msg())
	}

	args = parse_low_raw(['--hyperlink-format', 'file']) or { panic(err.msg()) }
	assert args.hyperlink_format == parse_hyperlink_format('file://{host}{path}') or {
		panic(err.msg())
	}

	args = parse_low_raw(['--hyperlink-format', 'file', '--hyperlink-format=grep+']) or {
		panic(err.msg())
	}
	assert args.hyperlink_format == parse_hyperlink_format('grep+://{path}:{line}') or {
		panic(err.msg())
	}

	args = parse_low_raw(['--hyperlink-format', 'file://{host}{path}#{line}']) or {
		panic(err.msg())
	}
	assert args.hyperlink_format == parse_hyperlink_format('file://{host}{path}#{line}') or {
		panic(err.msg())
	}

	if _ := parse_low_raw(['--hyperlink-format', 'file://heythere']) {
		assert false
	}
}

fn test_iglob() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.iglobs == []string{}

	args = parse_low_raw(['--iglob', 'foo']) or { panic(err.msg()) }
	assert args.iglobs == ['foo']

	args = parse_low_raw(['--iglob=foo']) or { panic(err.msg()) }
	assert args.iglobs == ['foo']

	args = parse_low_raw(['--iglob', '-foo']) or { panic(err.msg()) }
	assert args.iglobs == ['-foo']

	args = parse_low_raw(['--iglob=-foo']) or { panic(err.msg()) }
	assert args.iglobs == ['-foo']
}

fn test_ignore_case() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.case == .sensitive

	args = parse_low_raw(['--ignore-case']) or { panic(err.msg()) }
	assert args.case == .insensitive

	args = parse_low_raw(['-i']) or { panic(err.msg()) }
	assert args.case == .insensitive

	args = parse_low_raw(['-i', '-s']) or { panic(err.msg()) }
	assert args.case == .sensitive

	args = parse_low_raw(['-s', '-i']) or { panic(err.msg()) }
	assert args.case == .insensitive
}

fn test_ignore_file() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.ignore_file == []string{}

	args = parse_low_raw(['--ignore-file', 'foo']) or { panic(err.msg()) }
	assert args.ignore_file == ['foo']

	args = parse_low_raw(['--ignore-file', 'foo', '--ignore-file', 'bar']) or {
		panic(err.msg())
	}
	assert args.ignore_file == ['foo', 'bar']
}

fn test_ignore_file_case_insensitive() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.ignore_file_case_insensitive

	args = parse_low_raw(['--ignore-file-case-insensitive']) or { panic(err.msg()) }
	assert args.ignore_file_case_insensitive

	args = parse_low_raw(['--ignore-file-case-insensitive',
		'--no-ignore-file-case-insensitive']) or {
		panic(err.msg())
	}
	assert !args.ignore_file_case_insensitive

	args = parse_low_raw(['--no-ignore-file-case-insensitive',
		'--ignore-file-case-insensitive']) or {
		panic(err.msg())
	}
	assert args.ignore_file_case_insensitive
}

fn test_include_zero() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.include_zero

	args = parse_low_raw(['--include-zero']) or { panic(err.msg()) }
	assert args.include_zero

	args = parse_low_raw(['--include-zero', '--no-include-zero']) or { panic(err.msg()) }
	assert !args.include_zero
}

fn test_invert_match() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.invert_match

	args = parse_low_raw(['--invert-match']) or { panic(err.msg()) }
	assert args.invert_match

	args = parse_low_raw(['-v']) or { panic(err.msg()) }
	assert args.invert_match

	args = parse_low_raw(['-v', '--no-invert-match']) or { panic(err.msg()) }
	assert !args.invert_match
}

fn test_json() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.mode == mode_search(.standard)

	args = parse_low_raw(['--json']) or { panic(err.msg()) }
	assert args.mode == mode_search(.json)

	args = parse_low_raw(['--json', '--no-json']) or { panic(err.msg()) }
	assert args.mode == mode_search(.standard)

	args = parse_low_raw(['--json', '--files', '--no-json']) or { panic(err.msg()) }
	assert args.mode == mode_files()

	args = parse_low_raw(['--json', '-l', '--no-json']) or { panic(err.msg()) }
	assert args.mode == mode_search(.files_with_matches)
}

fn test_line_buffered() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.buffer == .auto

	args = parse_low_raw(['--line-buffered']) or { panic(err.msg()) }
	assert args.buffer == .line

	args = parse_low_raw(['--line-buffered', '--no-line-buffered']) or { panic(err.msg()) }
	assert args.buffer == .auto

	args = parse_low_raw(['--line-buffered', '--block-buffered']) or { panic(err.msg()) }
	assert args.buffer == .block
}

fn test_line_number() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.line_number == none

	args = parse_low_raw(['--line-number']) or { panic(err.msg()) }
	assert_opt_bool(args.line_number, true)

	args = parse_low_raw(['-n']) or { panic(err.msg()) }
	assert_opt_bool(args.line_number, true)

	args = parse_low_raw(['-n', '--no-line-number']) or { panic(err.msg()) }
	assert_opt_bool(args.line_number, false)
}

fn test_no_line_number() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.line_number == none

	args = parse_low_raw(['--no-line-number']) or { panic(err.msg()) }
	assert_opt_bool(args.line_number, false)

	args = parse_low_raw(['-N']) or { panic(err.msg()) }
	assert_opt_bool(args.line_number, false)

	args = parse_low_raw(['-N', '--line-number']) or { panic(err.msg()) }
	assert_opt_bool(args.line_number, true)
}

fn test_line_regexp() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.boundary == none

	args = parse_low_raw(['--line-regexp']) or { panic(err.msg()) }
	assert_opt_boundary(args.boundary, .line)

	args = parse_low_raw(['-x']) or { panic(err.msg()) }
	assert_opt_boundary(args.boundary, .line)
}

fn test_max_columns() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.max_columns == none

	args = parse_low_raw(['--max-columns', '5']) or { panic(err.msg()) }
	assert_opt_u64(args.max_columns, 5)

	args = parse_low_raw(['-M', '5']) or { panic(err.msg()) }
	assert_opt_u64(args.max_columns, 5)

	args = parse_low_raw(['-M5']) or { panic(err.msg()) }
	assert_opt_u64(args.max_columns, 5)

	args = parse_low_raw(['--max-columns', '5', '-M0']) or { panic(err.msg()) }
	assert args.max_columns == none
}

fn test_max_columns_preview() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.max_columns_preview

	args = parse_low_raw(['--max-columns-preview']) or { panic(err.msg()) }
	assert args.max_columns_preview

	args = parse_low_raw(['--max-columns-preview', '--no-max-columns-preview']) or {
		panic(err.msg())
	}
	assert !args.max_columns_preview
}

fn test_max_count() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.max_count == none

	args = parse_low_raw(['--max-count', '5']) or { panic(err.msg()) }
	assert_opt_u64(args.max_count, 5)

	args = parse_low_raw(['-m', '5']) or { panic(err.msg()) }
	assert_opt_u64(args.max_count, 5)

	args = parse_low_raw(['-m', '5', '--max-count=10']) or { panic(err.msg()) }
	assert_opt_u64(args.max_count, 10)

	args = parse_low_raw(['-m0']) or { panic(err.msg()) }
	assert_opt_u64(args.max_count, 0)
}

fn test_max_depth() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.max_depth == none

	args = parse_low_raw(['--max-depth', '5']) or { panic(err.msg()) }
	assert_opt_usize(args.max_depth, 5)

	args = parse_low_raw(['-d', '5']) or { panic(err.msg()) }
	assert_opt_usize(args.max_depth, 5)

	args = parse_low_raw(['--max-depth', '5', '--max-depth=10']) or { panic(err.msg()) }
	assert_opt_usize(args.max_depth, 10)

	args = parse_low_raw(['--max-depth', '0']) or { panic(err.msg()) }
	assert_opt_usize(args.max_depth, 0)

	args = parse_low_raw(['--maxdepth', '5']) or { panic(err.msg()) }
	assert_opt_usize(args.max_depth, 5)
}

fn test_max_filesize() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.max_filesize == none

	args = parse_low_raw(['--max-filesize', '1024']) or { panic(err.msg()) }
	assert_opt_u64(args.max_filesize, 1024)

	args = parse_low_raw(['--max-filesize', '1K']) or { panic(err.msg()) }
	assert_opt_u64(args.max_filesize, 1024)

	args = parse_low_raw(['--max-filesize', '1K', '--max-filesize=1M']) or {
		panic(err.msg())
	}
	assert_opt_u64(args.max_filesize, u64(1024) * 1024)
}

fn test_mmap() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.mmap == .auto

	args = parse_low_raw(['--mmap']) or { panic(err.msg()) }
	assert args.mmap == .always_try_mmap

	args = parse_low_raw(['--no-mmap']) or { panic(err.msg()) }
	assert args.mmap == .never

	args = parse_low_raw(['--mmap', '--no-mmap']) or { panic(err.msg()) }
	assert args.mmap == .never

	args = parse_low_raw(['--no-mmap', '--mmap']) or { panic(err.msg()) }
	assert args.mmap == .always_try_mmap
}

fn test_multiline() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.multiline

	args = parse_low_raw(['--multiline']) or { panic(err.msg()) }
	assert args.multiline

	args = parse_low_raw(['-U']) or { panic(err.msg()) }
	assert args.multiline

	args = parse_low_raw(['-U', '--no-multiline']) or { panic(err.msg()) }
	assert !args.multiline
}

fn test_multiline_dotall() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.multiline_dotall

	args = parse_low_raw(['--multiline-dotall']) or { panic(err.msg()) }
	assert args.multiline_dotall

	args = parse_low_raw(['--multiline-dotall', '--no-multiline-dotall']) or {
		panic(err.msg())
	}
	assert !args.multiline_dotall
}

fn test_no_config() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.no_config

	args = parse_low_raw(['--no-config']) or { panic(err.msg()) }
	assert args.no_config
}

fn test_no_ignore() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.no_ignore_dot
	assert !args.no_ignore_exclude
	assert !args.no_ignore_global
	assert !args.no_ignore_parent
	assert !args.no_ignore_vcs

	args = parse_low_raw(['--no-ignore']) or { panic(err.msg()) }
	assert args.no_ignore_dot
	assert args.no_ignore_exclude
	assert args.no_ignore_global
	assert args.no_ignore_parent
	assert args.no_ignore_vcs

	args = parse_low_raw(['--no-ignore', '--ignore']) or { panic(err.msg()) }
	assert !args.no_ignore_dot
	assert !args.no_ignore_exclude
	assert !args.no_ignore_global
	assert !args.no_ignore_parent
	assert !args.no_ignore_vcs
}

fn test_no_ignore_dot() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.no_ignore_dot

	args = parse_low_raw(['--no-ignore-dot']) or { panic(err.msg()) }
	assert args.no_ignore_dot

	args = parse_low_raw(['--no-ignore-dot', '--ignore-dot']) or { panic(err.msg()) }
	assert !args.no_ignore_dot
}

fn test_no_ignore_exclude() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.no_ignore_exclude

	args = parse_low_raw(['--no-ignore-exclude']) or { panic(err.msg()) }
	assert args.no_ignore_exclude

	args = parse_low_raw(['--no-ignore-exclude', '--ignore-exclude']) or { panic(err.msg()) }
	assert !args.no_ignore_exclude
}

fn test_no_ignore_files() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.no_ignore_files

	args = parse_low_raw(['--no-ignore-files']) or { panic(err.msg()) }
	assert args.no_ignore_files

	args = parse_low_raw(['--no-ignore-files', '--ignore-files']) or { panic(err.msg()) }
	assert !args.no_ignore_files
}

fn test_no_ignore_global() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.no_ignore_global

	args = parse_low_raw(['--no-ignore-global']) or { panic(err.msg()) }
	assert args.no_ignore_global

	args = parse_low_raw(['--no-ignore-global', '--ignore-global']) or { panic(err.msg()) }
	assert !args.no_ignore_global
}

fn test_no_ignore_messages() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.no_ignore_messages

	args = parse_low_raw(['--no-ignore-messages']) or { panic(err.msg()) }
	assert args.no_ignore_messages

	args = parse_low_raw(['--no-ignore-messages', '--ignore-messages']) or { panic(err.msg()) }
	assert !args.no_ignore_messages
}

fn test_no_ignore_parent() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.no_ignore_parent

	args = parse_low_raw(['--no-ignore-parent']) or { panic(err.msg()) }
	assert args.no_ignore_parent

	args = parse_low_raw(['--no-ignore-parent', '--ignore-parent']) or { panic(err.msg()) }
	assert !args.no_ignore_parent
}

fn test_no_ignore_vcs() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.no_ignore_vcs

	args = parse_low_raw(['--no-ignore-vcs']) or { panic(err.msg()) }
	assert args.no_ignore_vcs

	args = parse_low_raw(['--no-ignore-vcs', '--ignore-vcs']) or { panic(err.msg()) }
	assert !args.no_ignore_vcs
}

fn test_no_messages() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.no_messages

	args = parse_low_raw(['--no-messages']) or { panic(err.msg()) }
	assert args.no_messages

	args = parse_low_raw(['--no-messages', '--messages']) or { panic(err.msg()) }
	assert !args.no_messages
}

fn test_no_pcre2_unicode() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.no_unicode

	args = parse_low_raw(['--no-pcre2-unicode']) or { panic(err.msg()) }
	assert args.no_unicode

	args = parse_low_raw(['--no-pcre2-unicode', '--pcre2-unicode']) or { panic(err.msg()) }
	assert !args.no_unicode
}

fn test_no_require_git() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.no_require_git

	args = parse_low_raw(['--no-require-git']) or { panic(err.msg()) }
	assert args.no_require_git

	args = parse_low_raw(['--no-require-git', '--require-git']) or { panic(err.msg()) }
	assert !args.no_require_git
}

fn test_no_unicode() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.no_unicode

	args = parse_low_raw(['--no-unicode']) or { panic(err.msg()) }
	assert args.no_unicode

	args = parse_low_raw(['--no-unicode', '--unicode']) or { panic(err.msg()) }
	assert !args.no_unicode

	args = parse_low_raw(['--no-unicode', '--pcre2-unicode']) or { panic(err.msg()) }
	assert !args.no_unicode

	args = parse_low_raw(['--no-pcre2-unicode', '--unicode']) or { panic(err.msg()) }
	assert !args.no_unicode
}

fn test_null() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.null

	args = parse_low_raw(['--null']) or { panic(err.msg()) }
	assert args.null

	args = parse_low_raw(['-0']) or { panic(err.msg()) }
	assert args.null
}

fn test_null_data() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.null_data

	args = parse_low_raw(['--null-data']) or { panic(err.msg()) }
	assert args.null_data

	args = parse_low_raw(['--null-data', '--crlf']) or { panic(err.msg()) }
	assert !args.null_data
	assert args.crlf

	args = parse_low_raw(['--crlf', '--null-data']) or { panic(err.msg()) }
	assert args.null_data
	assert !args.crlf

	args = parse_low_raw(['--null-data', '--no-crlf']) or { panic(err.msg()) }
	assert args.null_data
	assert !args.crlf
}

fn test_one_file_system() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.one_file_system

	args = parse_low_raw(['--one-file-system']) or { panic(err.msg()) }
	assert args.one_file_system

	args = parse_low_raw(['--one-file-system', '--no-one-file-system']) or { panic(err.msg()) }
	assert !args.one_file_system
}

fn test_only_matching() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.only_matching

	args = parse_low_raw(['--only-matching']) or { panic(err.msg()) }
	assert args.only_matching

	args = parse_low_raw(['-o']) or { panic(err.msg()) }
	assert args.only_matching
}

fn test_path_separator() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.path_separator == none

	args = parse_low_raw(['--path-separator', '/']) or { panic(err.msg()) }
	assert_opt_u8(args.path_separator, `/`)

	args = parse_low_raw(['--path-separator', r'\']) or { panic(err.msg()) }
	assert_opt_u8(args.path_separator, `\\`)

	args = parse_low_raw(['--path-separator', r'\x00']) or { panic(err.msg()) }
	assert_opt_u8(args.path_separator, u8(0))

	args = parse_low_raw(['--path-separator', r'\0']) or { panic(err.msg()) }
	assert_opt_u8(args.path_separator, u8(0))

	args = parse_low_raw(['--path-separator', [u8(0)].bytestr()]) or { panic(err.msg()) }
	assert_opt_u8(args.path_separator, u8(0))

	args = parse_low_raw(['--path-separator', '\0']) or { panic(err.msg()) }
	assert_opt_u8(args.path_separator, u8(0))

	args = parse_low_raw(['--path-separator', r'\x00', '--path-separator=/']) or {
		panic(err.msg())
	}
	assert_opt_u8(args.path_separator, `/`)

	if _ := parse_low_raw(['--path-separator', 'foo']) {
		assert false
	}

	if _ := parse_low_raw(['--path-separator', r'\\x00']) {
		assert false
	}
}

fn test_passthru() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.context == default_context_mode()

	args = parse_low_raw(['--passthru']) or { panic(err.msg()) }
	assert args.context == passthru_context_mode()

	args = parse_low_raw(['--passthrough']) or { panic(err.msg()) }
	assert args.context == passthru_context_mode()
}

fn test_pcre2() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.engine == .default

	args = parse_low_raw(['--pcre2']) or { panic(err.msg()) }
	assert args.engine == .pcre2

	args = parse_low_raw(['-P']) or { panic(err.msg()) }
	assert args.engine == .pcre2

	args = parse_low_raw(['-P', '--no-pcre2']) or { panic(err.msg()) }
	assert args.engine == .default

	args = parse_low_raw(['--engine=auto', '-P', '--no-pcre2']) or { panic(err.msg()) }
	assert args.engine == .default

	args = parse_low_raw(['-P', '--engine=auto']) or { panic(err.msg()) }
	assert args.engine == .auto
}

fn test_pcre2_version() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.special == none

	args = parse_low_raw(['--pcre2-version']) or { panic(err.msg()) }
	assert_opt_special(args.special, .version_pcre2)
}

fn test_pre() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.pre == none

	args = parse_low_raw(['--pre', 'foo/bar']) or { panic(err.msg()) }
	assert_opt_string(args.pre, 'foo/bar')

	args = parse_low_raw(['--pre', '']) or { panic(err.msg()) }
	assert args.pre == none

	args = parse_low_raw(['--pre', 'foo/bar', '--pre', '']) or { panic(err.msg()) }
	assert args.pre == none

	args = parse_low_raw(['--pre', 'foo/bar', '--pre=']) or { panic(err.msg()) }
	assert args.pre == none

	args = parse_low_raw(['--pre', 'foo/bar', '--no-pre']) or { panic(err.msg()) }
	assert args.pre == none
}

fn test_pre_glob() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.pre_glob == []string{}

	args = parse_low_raw(['--pre-glob', '*.pdf']) or { panic(err.msg()) }
	assert args.pre_glob == ['*.pdf']

	args = parse_low_raw(['--pre-glob', '*.pdf', '--pre-glob=foo']) or { panic(err.msg()) }
	assert args.pre_glob == ['*.pdf', 'foo']
}

fn test_pretty() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.color == .auto
	assert args.heading == none
	assert args.line_number == none

	args = parse_low_raw(['--pretty']) or { panic(err.msg()) }
	assert args.color == .always
	assert_opt_bool(args.heading, true)
	assert_opt_bool(args.line_number, true)

	args = parse_low_raw(['-p']) or { panic(err.msg()) }
	assert args.color == .always
	assert_opt_bool(args.heading, true)
	assert_opt_bool(args.line_number, true)
}

fn test_quiet() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.quiet

	args = parse_low_raw(['--quiet']) or { panic(err.msg()) }
	assert args.quiet

	args = parse_low_raw(['-q']) or { panic(err.msg()) }
	assert args.quiet

	// flags like -l and --json cannot override -q, regardless of order
	args = parse_low_raw(['-q', '--json']) or { panic(err.msg()) }
	assert args.quiet

	args = parse_low_raw(['-q', '--files-with-matches']) or { panic(err.msg()) }
	assert args.quiet

	args = parse_low_raw(['-q', '--files-without-match']) or { panic(err.msg()) }
	assert args.quiet

	args = parse_low_raw(['-q', '--count']) or { panic(err.msg()) }
	assert args.quiet

	args = parse_low_raw(['-q', '--count-matches']) or { panic(err.msg()) }
	assert args.quiet
}

fn test_regex_size_limit() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.regex_size_limit == none

	args = parse_low_raw(['--regex-size-limit', '9G']) or { panic(err.msg()) }
	assert_opt_usize(args.regex_size_limit, usize(9) * (usize(1) << 30))

	args = parse_low_raw(['--regex-size-limit=9G']) or { panic(err.msg()) }
	assert_opt_usize(args.regex_size_limit, usize(9) * (usize(1) << 30))

	args = parse_low_raw(['--regex-size-limit=9G', '--regex-size-limit=0']) or {
		panic(err.msg())
	}
	assert_opt_usize(args.regex_size_limit, 0)

	args = parse_low_raw(['--regex-size-limit=0K']) or { panic(err.msg()) }
	assert_opt_usize(args.regex_size_limit, 0)

	args = parse_low_raw(['--regex-size-limit=0M']) or { panic(err.msg()) }
	assert_opt_usize(args.regex_size_limit, 0)

	args = parse_low_raw(['--regex-size-limit=0G']) or { panic(err.msg()) }
	assert_opt_usize(args.regex_size_limit, 0)

	if _ := parse_low_raw(['--regex-size-limit', '9999999999999999999999']) {
		assert false
	}

	if _ := parse_low_raw(['--regex-size-limit', '9999999999999999G']) {
		assert false
	}
}

fn test_regexp() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.patterns == []PatternSource{}

	args = parse_low_raw(['--regexp', 'foo']) or { panic(err.msg()) }
	assert args.patterns == [pattern_regexp('foo')]

	args = parse_low_raw(['--regexp=foo']) or { panic(err.msg()) }
	assert args.patterns == [pattern_regexp('foo')]

	args = parse_low_raw(['-e', 'foo']) or { panic(err.msg()) }
	assert args.patterns == [pattern_regexp('foo')]

	args = parse_low_raw(['-efoo']) or { panic(err.msg()) }
	assert args.patterns == [pattern_regexp('foo')]

	args = parse_low_raw(['--regexp', '-foo']) or { panic(err.msg()) }
	assert args.patterns == [pattern_regexp('-foo')]

	args = parse_low_raw(['--regexp=-foo']) or { panic(err.msg()) }
	assert args.patterns == [pattern_regexp('-foo')]

	args = parse_low_raw(['-e', '-foo']) or { panic(err.msg()) }
	assert args.patterns == [pattern_regexp('-foo')]

	args = parse_low_raw(['-e-foo']) or { panic(err.msg()) }
	assert args.patterns == [pattern_regexp('-foo')]

	args = parse_low_raw(['--regexp=foo', '--regexp', 'bar']) or { panic(err.msg()) }
	assert args.patterns == [pattern_regexp('foo'), pattern_regexp('bar')]

	// While we support invalid UTF-8 arguments in general, patterns must be
	// valid UTF-8.
	bytes := [u8(`A`), 0xff, `Z`].bytestr()
	if _ := parse_low_raw(['-e', bytes]) {
		assert false
	}

	// Check that combining -e/--regexp and -f/--file works as expected.
	args = parse_low_raw(['-efoo', '-fbar']) or { panic(err.msg()) }
	assert args.patterns == [pattern_regexp('foo'), pattern_file('bar')]

	args = parse_low_raw(['-efoo', '-fbar', '-equux']) or { panic(err.msg()) }
	assert args.patterns == [pattern_regexp('foo'), pattern_file('bar'),
		pattern_regexp('quux')]
}

fn test_replace() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.replace == none

	args = parse_low_raw(['--replace', 'foo']) or { panic(err.msg()) }
	assert_opt_string(args.replace, 'foo')

	args = parse_low_raw(['--replace', '-foo']) or { panic(err.msg()) }
	assert_opt_string(args.replace, '-foo')

	args = parse_low_raw(['-r', 'foo']) or { panic(err.msg()) }
	assert_opt_string(args.replace, 'foo')

	args = parse_low_raw(['-r', 'foo', '-rbar']) or { panic(err.msg()) }
	assert_opt_string(args.replace, 'bar')

	args = parse_low_raw(['-r', 'foo', '-r', '']) or { panic(err.msg()) }
	assert_opt_string(args.replace, '')
}

fn test_search_zip() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.search_zip

	args = parse_low_raw(['--search-zip']) or { panic(err.msg()) }
	assert args.search_zip

	args = parse_low_raw(['-z']) or { panic(err.msg()) }
	assert args.search_zip

	args = parse_low_raw(['-z', '--no-search-zip']) or { panic(err.msg()) }
	assert !args.search_zip

	args = parse_low_raw(['--pre=foo', '--no-search-zip']) or { panic(err.msg()) }
	assert_opt_string(args.pre, 'foo')
	assert !args.search_zip

	args = parse_low_raw(['--pre=foo', '--search-zip']) or { panic(err.msg()) }
	assert args.pre == none
	assert args.search_zip

	args = parse_low_raw(['--pre=foo', '-z', '--no-search-zip']) or { panic(err.msg()) }
	assert args.pre == none
	assert !args.search_zip
}

fn test_smart_case() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.case == .sensitive

	args = parse_low_raw(['--smart-case']) or { panic(err.msg()) }
	assert args.case == .smart

	args = parse_low_raw(['-S']) or { panic(err.msg()) }
	assert args.case == .smart

	args = parse_low_raw(['-S', '-s']) or { panic(err.msg()) }
	assert args.case == .sensitive

	args = parse_low_raw(['-S', '-i']) or { panic(err.msg()) }
	assert args.case == .insensitive

	args = parse_low_raw(['-s', '-S']) or { panic(err.msg()) }
	assert args.case == .smart

	args = parse_low_raw(['-i', '-S']) or { panic(err.msg()) }
	assert args.case == .smart
}

fn test_sort_files() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.sort == none

	args = parse_low_raw(['--sort-files']) or { panic(err.msg()) }
	assert_opt_sort_mode(args.sort, SortMode{
		reverse: false
		kind:    .path
	})

	args = parse_low_raw(['--sort-files', '--no-sort-files']) or { panic(err.msg()) }
	assert args.sort == none

	args = parse_low_raw(['--sort', 'created', '--sort-files']) or { panic(err.msg()) }
	assert_opt_sort_mode(args.sort, SortMode{
		reverse: false
		kind:    .path
	})

	args = parse_low_raw(['--sort-files', '--sort', 'created']) or { panic(err.msg()) }
	assert_opt_sort_mode(args.sort, SortMode{
		reverse: false
		kind:    .created
	})

	args = parse_low_raw(['--sortr', 'created', '--sort-files']) or { panic(err.msg()) }
	assert_opt_sort_mode(args.sort, SortMode{
		reverse: false
		kind:    .path
	})

	args = parse_low_raw(['--sort-files', '--sortr', 'created']) or { panic(err.msg()) }
	assert_opt_sort_mode(args.sort, SortMode{
		reverse: true
		kind:    .created
	})

	args = parse_low_raw(['--sort=path', '--no-sort-files']) or { panic(err.msg()) }
	assert args.sort == none

	args = parse_low_raw(['--sortr=path', '--no-sort-files']) or { panic(err.msg()) }
	assert args.sort == none
}

fn test_sort() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.sort == none

	args = parse_low_raw(['--sort', 'path']) or { panic(err.msg()) }
	assert_opt_sort_mode(args.sort, SortMode{
		reverse: false
		kind:    .path
	})

	args = parse_low_raw(['--sort', 'path', '--sort=created']) or { panic(err.msg()) }
	assert_opt_sort_mode(args.sort, SortMode{
		reverse: false
		kind:    .created
	})

	args = parse_low_raw(['--sort=none']) or { panic(err.msg()) }
	assert args.sort == none

	args = parse_low_raw(['--sort', 'path', '--sort=none']) or { panic(err.msg()) }
	assert args.sort == none
}

fn test_sortr() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.sort == none

	args = parse_low_raw(['--sortr', 'path']) or { panic(err.msg()) }
	assert_opt_sort_mode(args.sort, SortMode{
		reverse: true
		kind:    .path
	})

	args = parse_low_raw(['--sortr', 'path', '--sortr=created']) or { panic(err.msg()) }
	assert_opt_sort_mode(args.sort, SortMode{
		reverse: true
		kind:    .created
	})

	args = parse_low_raw(['--sortr=none']) or { panic(err.msg()) }
	assert args.sort == none

	args = parse_low_raw(['--sortr', 'path', '--sortr=none']) or { panic(err.msg()) }
	assert args.sort == none

	args = parse_low_raw(['--sort=path', '--sortr=path']) or { panic(err.msg()) }
	assert_opt_sort_mode(args.sort, SortMode{
		reverse: true
		kind:    .path
	})

	args = parse_low_raw(['--sortr=path', '--sort=path']) or { panic(err.msg()) }
	assert_opt_sort_mode(args.sort, SortMode{
		reverse: false
		kind:    .path
	})
}

fn test_stats() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.stats

	args = parse_low_raw(['--stats']) or { panic(err.msg()) }
	assert args.stats

	args = parse_low_raw(['--stats', '--no-stats']) or { panic(err.msg()) }
	assert !args.stats
}

fn test_stop_on_nonmatch() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.stop_on_nonmatch

	args = parse_low_raw(['--stop-on-nonmatch']) or { panic(err.msg()) }
	assert args.stop_on_nonmatch

	args = parse_low_raw(['--stop-on-nonmatch', '-U']) or { panic(err.msg()) }
	assert args.multiline
	assert !args.stop_on_nonmatch

	args = parse_low_raw(['-U', '--stop-on-nonmatch']) or { panic(err.msg()) }
	assert !args.multiline
	assert args.stop_on_nonmatch

	args = parse_low_raw(['--stop-on-nonmatch', '--no-multiline']) or { panic(err.msg()) }
	assert !args.multiline
	assert args.stop_on_nonmatch
}

fn test_text() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.binary == .auto

	args = parse_low_raw(['--text']) or { panic(err.msg()) }
	assert args.binary == .as_text

	args = parse_low_raw(['-a']) or { panic(err.msg()) }
	assert args.binary == .as_text

	args = parse_low_raw(['-a', '--no-text']) or { panic(err.msg()) }
	assert args.binary == .auto

	args = parse_low_raw(['-a', '--binary']) or { panic(err.msg()) }
	assert args.binary == .search_and_suppress

	args = parse_low_raw(['--binary', '-a']) or { panic(err.msg()) }
	assert args.binary == .as_text

	args = parse_low_raw(['-a', '--no-binary']) or { panic(err.msg()) }
	assert args.binary == .auto

	args = parse_low_raw(['--binary', '--no-text']) or { panic(err.msg()) }
	assert args.binary == .auto
}

fn test_threads() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.threads == none

	args = parse_low_raw(['--threads', '5']) or { panic(err.msg()) }
	assert_opt_usize(args.threads, 5)

	args = parse_low_raw(['-j', '5']) or { panic(err.msg()) }
	assert_opt_usize(args.threads, 5)

	args = parse_low_raw(['-j5']) or { panic(err.msg()) }
	assert_opt_usize(args.threads, 5)

	args = parse_low_raw(['-j5', '-j10']) or { panic(err.msg()) }
	assert_opt_usize(args.threads, 10)

	args = parse_low_raw(['-j5', '-j0']) or { panic(err.msg()) }
	assert args.threads == none
}

fn test_trace() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.has_logging

	args = parse_low_raw(['--trace']) or { panic(err.msg()) }
	assert args.has_logging
	assert args.logging == .trace

	args = parse_low_raw(['--debug', '--trace']) or { panic(err.msg()) }
	assert args.has_logging
	assert args.logging == .trace
}

fn test_trim() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.trim

	args = parse_low_raw(['--trim']) or { panic(err.msg()) }
	assert args.trim

	args = parse_low_raw(['--trim', '--no-trim']) or { panic(err.msg()) }
	assert !args.trim
}

fn test_type() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.type_changes == []TypeChange{}

	args = parse_low_raw(['--type', 'rust']) or { panic(err.msg()) }
	assert args.type_changes == [select_type('rust')]

	args = parse_low_raw(['-t', 'rust']) or { panic(err.msg()) }
	assert args.type_changes == [select_type('rust')]

	args = parse_low_raw(['-trust']) or { panic(err.msg()) }
	assert args.type_changes == [select_type('rust')]

	args = parse_low_raw(['-trust', '-tpython']) or { panic(err.msg()) }
	assert args.type_changes == [select_type('rust'), select_type('python')]

	args = parse_low_raw(['-tabcdefxyz']) or { panic(err.msg()) }
	assert args.type_changes == [select_type('abcdefxyz')]
}

fn test_type_add() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.type_changes == []TypeChange{}

	args = parse_low_raw(['--type-add', 'foo']) or { panic(err.msg()) }
	assert args.type_changes == [add_type('foo')]

	args = parse_low_raw(['--type-add', 'foo', '--type-add=bar']) or { panic(err.msg()) }
	assert args.type_changes == [add_type('foo'), add_type('bar')]
}

fn test_type_clear() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.type_changes == []TypeChange{}

	args = parse_low_raw(['--type-clear', 'foo']) or { panic(err.msg()) }
	assert args.type_changes == [clear_type('foo')]

	args = parse_low_raw(['--type-clear', 'foo', '--type-clear=bar']) or { panic(err.msg()) }
	assert args.type_changes == [clear_type('foo'), clear_type('bar')]
}

fn test_type_not() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.type_changes == []TypeChange{}

	args = parse_low_raw(['--type-not', 'rust']) or { panic(err.msg()) }
	assert args.type_changes == [negate_type('rust')]

	args = parse_low_raw(['-T', 'rust']) or { panic(err.msg()) }
	assert args.type_changes == [negate_type('rust')]

	args = parse_low_raw(['-Trust']) or { panic(err.msg()) }
	assert args.type_changes == [negate_type('rust')]

	args = parse_low_raw(['-Trust', '-Tpython']) or { panic(err.msg()) }
	assert args.type_changes == [negate_type('rust'), negate_type('python')]

	args = parse_low_raw(['-Tabcdefxyz']) or { panic(err.msg()) }
	assert args.type_changes == [negate_type('abcdefxyz')]

	args = parse_low_raw(['-Trust', '-ttoml', '-Tjson']) or { panic(err.msg()) }
	assert args.type_changes == [negate_type('rust'), select_type('toml'),
		negate_type('json')]
}

fn test_type_list() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.mode == mode_search(.standard)

	args = parse_low_raw(['--type-list']) or { panic(err.msg()) }
	assert args.mode == mode_types()
}

fn test_unrestricted() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.no_ignore_vcs
	assert !args.hidden
	assert args.binary == .auto

	args = parse_low_raw(['--unrestricted']) or { panic(err.msg()) }
	assert args.no_ignore_vcs
	assert !args.hidden
	assert args.binary == .auto

	args = parse_low_raw(['--unrestricted', '-u']) or { panic(err.msg()) }
	assert args.no_ignore_vcs
	assert args.hidden
	assert args.binary == .auto

	args = parse_low_raw(['-uuu']) or { panic(err.msg()) }
	assert args.no_ignore_vcs
	assert args.hidden
	assert args.binary == .search_and_suppress

	if _ := parse_low_raw(['-uuuu']) {
		assert false
	}
}

fn test_version() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.special == none

	args = parse_low_raw(['-V']) or { panic(err.msg()) }
	assert_opt_special(args.special, .version_short)

	args = parse_low_raw(['--version']) or { panic(err.msg()) }
	assert_opt_special(args.special, .version_long)

	args = parse_low_raw(['-V', '--version']) or { panic(err.msg()) }
	assert_opt_special(args.special, .version_long)

	args = parse_low_raw(['--version', '-V']) or { panic(err.msg()) }
	assert_opt_special(args.special, .version_short)
}

fn test_vimgrep() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert !args.vimgrep

	args = parse_low_raw(['--vimgrep']) or { panic(err.msg()) }
	assert args.vimgrep
}

fn test_with_filename() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.with_filename == none

	args = parse_low_raw(['--with-filename']) or { panic(err.msg()) }
	assert_opt_bool(args.with_filename, true)

	args = parse_low_raw(['-H']) or { panic(err.msg()) }
	assert_opt_bool(args.with_filename, true)
}

fn test_with_filename_no() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.with_filename == none

	args = parse_low_raw(['--no-filename']) or { panic(err.msg()) }
	assert_opt_bool(args.with_filename, false)

	args = parse_low_raw(['-I']) or { panic(err.msg()) }
	assert_opt_bool(args.with_filename, false)

	args = parse_low_raw(['-I', '-H']) or { panic(err.msg()) }
	assert_opt_bool(args.with_filename, true)

	args = parse_low_raw(['-H', '-I']) or { panic(err.msg()) }
	assert_opt_bool(args.with_filename, false)
}

fn test_word_regexp() {
	mut args := parse_low_raw([]string{}) or { panic(err.msg()) }
	assert args.boundary == none

	args = parse_low_raw(['--word-regexp']) or { panic(err.msg()) }
	assert_opt_boundary(args.boundary, .word)

	args = parse_low_raw(['-w']) or { panic(err.msg()) }
	assert_opt_boundary(args.boundary, .word)

	args = parse_low_raw(['-x', '-w']) or { panic(err.msg()) }
	assert_opt_boundary(args.boundary, .word)

	args = parse_low_raw(['-w', '-x']) or { panic(err.msg()) }
	assert_opt_boundary(args.boundary, .line)
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

fn test_available_shorts() {
	mut total := []bool{len: 128}
	for byte in 0 .. 128 {
		match u8(byte) {
			`.`, `0`...`9`, `A`...`Z`, `a`...`z` {
				total[byte] = true
			}
			else {
				continue
			}
		}
	}

	mut taken := []bool{len: 128}
	for id in flags {
		short := id.name_short() or { continue }
		taken[int(short)] = true
	}

	for byte in 0 .. 128 {
		if total[byte] && !taken[byte] {
			eprintln('${u8(byte).ascii_str()}')
		}
	}
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
