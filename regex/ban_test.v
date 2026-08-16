module regex

/// Returns true when the given pattern is detected to contain the given
/// banned byte.
fn ban_check_detects(pattern string, byte u8) bool {
	ban_check(pattern, byte) or { return true }
	return false
}

fn test_ban_check_various() {
	assert ban_check_detects(r'\x00', 0)
	assert ban_check_detects(r'a\x00', 0)
	assert ban_check_detects(r'\x00b', 0)
	assert ban_check_detects(r'a\x00b', 0)
	assert ban_check_detects(r'\x00|ab', 0)
	assert ban_check_detects(r'ab|\x00', 0)
	assert ban_check_detects(r'\x00?', 0)
	assert ban_check_detects(r'(\x00)', 0)

	assert ban_check_detects(r'[\x00]', 0)
	assert ban_check_detects(r'[^[^\x00]]', 0)

	assert !ban_check_detects(r'[^\x00]', 0)
	assert !ban_check_detects(r'[\x00a]', 0)
}

fn test_ban_check_hex_forms() {
	assert ban_check_detects(r'\x{0}', 0)
	assert ban_check_detects(r'\u0000', 0)
	assert ban_check_detects(r'\U00000000', 0)
}
