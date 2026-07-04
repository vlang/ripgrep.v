module flags

import os

fn restore_config_env(previous ?string) {
	if value := previous {
		os.setenv('RIPGREP_CONFIG_PATH', value, true)
	} else {
		os.unsetenv('RIPGREP_CONFIG_PATH')
	}
}

fn test_ngrams_pads_short_names() {
	assert ngrams('') == ['!!!']
	assert ngrams('a') == ['a!!']
	assert ngrams('ab') == ['ab!']
	assert ngrams('abcd') == ['abc', 'bcd']
}

fn test_find_similar_names_includes_close_flags() {
	similar := find_similar_names('maxdepth')
	assert 'maxdepth' in similar
	assert 'max-depth' in similar
}

fn test_parse_low_raw_suggests_similar_long_flags() {
	_ := parse_low_raw(['--max-colums']) or {
		assert err.msg().contains('unrecognized flag --max-colums')
		assert err.msg().contains('similar flags that are available:')
		assert err.msg().contains('--max-columns')
		return
	}
	assert false
}

fn test_parse_low_from_raw_special_skips_config() {
	previous := os.getenv_opt('RIPGREP_CONFIG_PATH')
	path := os.join_path(os.temp_dir(), 'ripgrep_v_parse_special_config')
	os.write_file(path, '--max-colums')!
	defer {
		os.rm(path) or {}
		restore_config_env(previous)
	}
	os.setenv('RIPGREP_CONFIG_PATH', path, true)

	result := parse_low_from_raw(['--help'])
	assert result.kind == .special
	assert result.special == .help_long
}

fn test_parse_low_from_raw_prepends_config_args() {
	previous := os.getenv_opt('RIPGREP_CONFIG_PATH')
	path := os.join_path(os.temp_dir(), 'ripgrep_v_parse_config_args')
	os.write_file(path, '--hidden\n')!
	defer {
		os.rm(path) or {}
		restore_config_env(previous)
	}
	os.setenv('RIPGREP_CONFIG_PATH', path, true)

	result := parse_low_from_raw(['needle'])
	assert result.kind == .ok
	assert result.value.hidden
	assert result.value.positional == ['needle']
}

fn test_parse_low_from_raw_no_config_skips_config_args() {
	previous := os.getenv_opt('RIPGREP_CONFIG_PATH')
	path := os.join_path(os.temp_dir(), 'ripgrep_v_parse_no_config_args')
	os.write_file(path, '--hidden\n')!
	defer {
		os.rm(path) or {}
		restore_config_env(previous)
	}
	os.setenv('RIPGREP_CONFIG_PATH', path, true)

	result := parse_low_from_raw(['--no-config', 'needle'])
	assert result.kind == .ok
	assert result.value.no_config
	assert !result.value.hidden
	assert result.value.positional == ['needle']
}
