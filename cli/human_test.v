module cli

fn test_parse_human_readable_size_suffix_none() {
	assert parse_human_readable_size('123')! == u64(123)
}

fn test_parse_human_readable_size_suffix_k() {
	assert parse_human_readable_size('123K')! == u64(123) * (u64(1) << 10)
}

fn test_parse_human_readable_size_suffix_m() {
	assert parse_human_readable_size('123M')! == u64(123) * (u64(1) << 20)
}

fn test_parse_human_readable_size_suffix_g() {
	assert parse_human_readable_size('123G')! == u64(123) * (u64(1) << 30)
}

fn test_parse_human_readable_size_invalid_empty() {
	parse_human_readable_size('') or {
		assert err.msg().contains('invalid format')
		return
	}
	assert false, 'expected invalid empty size'
}

fn test_parse_human_readable_size_invalid_non_digit() {
	parse_human_readable_size('a') or {
		assert err.msg().contains('invalid format')
		return
	}
	assert false, 'expected invalid non-digit size'
}

fn test_parse_human_readable_size_invalid_overflow() {
	parse_human_readable_size('9999999999999999G') or {
		assert err.msg().contains('size too big')
		return
	}
	assert false, 'expected overflow size'
}

fn test_parse_human_readable_size_invalid_suffix() {
	parse_human_readable_size('123T') or {
		assert err.msg().contains('invalid format')
		return
	}
	assert false, 'expected invalid suffix'
}
