module regex

import matcher

// V-specific: direct `v -ownership some_test.v` compilation does not load
// helper functions from sibling `_test.v` files, so shared translated regex
// test helpers live in this normal module file.
fn sparse(set matcher.ByteSet) []u8 {
	mut sparse_set := []u8{}
	for i in 0 .. 256 {
		byte := u8(i)
		if set.contains(byte) {
			sparse_set << byte
		}
	}
	return sparse_set
}

fn sparse_except(except []u8) []u8 {
	mut except_set := []bool{len: 256}
	for byte in except {
		except_set[int(byte)] = true
	}
	mut set := []u8{}
	for i in 0 .. 256 {
		byte := u8(i)
		if !except_set[i] {
			set << byte
		}
	}
	return set
}

fn sparse_unicode_dot(dotall bool) []u8 {
	mut set := []u8{}
	if !dotall {
		set << `\n`
	}
	set << u8(0xc0)
	set << u8(0xc1)
	for i in 0xf5 .. 0x100 {
		set << u8(i)
	}
	return set
}
