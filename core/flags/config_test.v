module flags

fn test_config_parse_basic() {
	args_, errs := parse_config_reader('# Test
--context=0
   --smart-case
-u


   # --bar
--foo
'.bytes()) or {
		panic(err.msg())
	}
	assert errs.len == 0
	assert args_ == ['--context=0', '--smart-case', '-u', '--foo']
}

fn test_config_parse_invalid_utf8() {
	args_, errs := parse_config_reader([u8(`q`), `u`, `u`, `x`, `\n`, `f`, `o`, `o`, 0xff, `b`,
		`a`, `r`, `\n`, `b`, `a`, `z`, `\n`]) or { panic(err.msg()) }
	$if windows {
		assert errs.len == 1
		assert args_ == ['quux', 'baz']
	} $else {
		assert errs.len == 0
		assert args_.len == 3
		assert args_[0] == 'quux'
		assert args_[2] == 'baz'
	}
}
