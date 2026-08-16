module regex

import matcher

fn extract_non_matching(pattern string) matcher.ByteSet {
	hir := Hir.from_pattern(pattern, Config.default())
	return non_matching_bytes(&hir)
}

fn test_non_matching_dot() {
	assert sparse(extract_non_matching('.')) == sparse_unicode_dot(false)
	assert sparse(extract_non_matching('(?s).')) == sparse_unicode_dot(true)
	assert sparse(extract_non_matching('(?-u).')) == [`\n`]
	assert sparse(extract_non_matching('(?s-u).')) == []u8{}
}

fn test_non_matching_literal() {
	assert sparse(extract_non_matching('a')) == sparse_except([u8(`a`)])
	snowman := [u8(0xe2), 0x98, 0x83].bytestr()
	assert sparse(extract_non_matching(snowman)) == sparse_except([u8(0xe2), 0x98, 0x83])
}

fn test_non_matching_anchor() {
	// FIXME: The first four tests below should correspond to a full set
	// of bytes for the non-matching bytes I think.
	assert sparse(extract_non_matching(r'^')) == sparse_except([u8(`\n`)])
	assert sparse(extract_non_matching(r'$')) == sparse_except([u8(`\n`)])
	assert sparse(extract_non_matching(r'\A')) == sparse_except([u8(`\n`)])
	assert sparse(extract_non_matching(r'\z')) == sparse_except([u8(`\n`)])
	assert sparse(extract_non_matching(r'(?m)^')) == sparse_except([u8(`\n`)])
	assert sparse(extract_non_matching(r'(?m)$')) == sparse_except([u8(`\n`)])
}
