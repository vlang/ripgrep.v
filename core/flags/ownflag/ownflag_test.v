module ownflag

struct TestSchema {
	after string @[long: 'after-context'; short: A]
	help  bool   @[long: 'help'; short: h]
	unres int    @[repeats; short: u]
}

fn schema_defs_for_test() []FlagDef {
	return [
		FlagDef{field_name: 'after' long_name: 'after-context' short_name: 'A' takes_arg: true},
		FlagDef{field_name: 'help' long_name: 'help' short_name: 'h' takes_arg: false},
		FlagDef{field_name: 'unres' long_name: 'unres' short_name: 'u' takes_arg: false},
	]
}

fn test_parse_short_and_long_flags() {
	mut fm := FlagMapper{
		config: ParseConfig{
			style: .short_long
			mode:  .relaxed
			stop:  '--'
		}
		input:  ['-A5', '--help', '-u', '--after-context', '7']
	}
	fm.parse_defs(schema_defs_for_test()) or { panic(err.msg()) }
	parsed := fm.parsed_flags()
	assert parsed.len == 4
	assert parsed[0].field_name == 'after'
	assert parsed[0].name == 'A'
	assert parsed[0].arg or { '' } == '5'
	assert parsed[1].field_name == 'help'
	assert parsed[1].name == 'help'
	assert parsed[2].field_name == 'unres'
	assert parsed[2].name == 'u'
	assert parsed[3].arg or { '' } == '7'
}

fn test_parse_respects_stop_and_unknown_relaxed() {
	mut fm := FlagMapper{
		config: ParseConfig{
			style: .short_long
			mode:  .relaxed
			stop:  '--'
		}
		input:  ['--help', '--unknown', '--', '-A5']
	}
	fm.parse_defs(schema_defs_for_test()) or { panic(err.msg()) }
	parsed := fm.parsed_flags()
	assert parsed.len == 1
	assert parsed[0].field_name == 'help'
	assert fm.no_matches() == ['--unknown']
	assert fm.handled_positions() == [0]
}
