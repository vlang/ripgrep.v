module matcher

struct NameIndex {
	name  string
	index usize
}

fn assert_find_cap_ref_none(text string) {
	assert find_cap_ref(text.bytes()) == none
}

fn assert_find_cap_ref_named(text string, name string, end usize) {
	cap_ref := find_cap_ref(text.bytes()) or {
		assert false
		return
	}
	assert cap_ref == CaptureRef.named(name, end)
}

fn assert_find_cap_ref_numbered(text string, number usize, end usize) {
	cap_ref := find_cap_ref(text.bytes()) or {
		assert false
		return
	}
	assert cap_ref == CaptureRef.numbered(number, end)
}

fn test_find_cap_ref1() {
	assert_find_cap_ref_named('\$foo', 'foo', 4)
}

fn test_find_cap_ref2() {
	assert_find_cap_ref_named('\${foo}', 'foo', 6)
}

fn test_find_cap_ref3() {
	assert_find_cap_ref_numbered('\$0', 0, 2)
}

fn test_find_cap_ref4() {
	assert_find_cap_ref_numbered('\$5', 5, 2)
}

fn test_find_cap_ref5() {
	assert_find_cap_ref_numbered('\$10', 10, 3)
}

fn test_find_cap_ref6() {
	assert_find_cap_ref_named('\$42a', '42a', 4)
}

fn test_find_cap_ref7() {
	assert_find_cap_ref_numbered('\${42}a', 42, 5)
}

fn test_find_cap_ref8() {
	assert_find_cap_ref_none('\${42')
}

fn test_find_cap_ref9() {
	assert_find_cap_ref_none('\${42 ')
}

fn test_find_cap_ref10() {
	assert_find_cap_ref_none(' \$0 ')
}

fn test_find_cap_ref11() {
	assert_find_cap_ref_none('\$')
}

fn test_find_cap_ref12() {
	assert_find_cap_ref_none(' ')
}

fn test_find_cap_ref13() {
	assert_find_cap_ref_none('')
}

// A convenience routine for using interpolate's unwieldy but flexible API.
fn interpolate_string(mut name_to_index []NameIndex, caps []string, replacement string) string {
	sort_name_indices(mut name_to_index)
	mut dst := []u8{}
	interpolate(replacement.bytes(), fn [caps] (i usize, mut dst []u8) {
		if i < caps.len {
			dst << caps[i].bytes()
		}
	}, fn [name_to_index] (name string) ?usize {
		return binary_search_name_index(name_to_index, name)
	}, mut dst)
	return dst.bytestr()
}

fn sort_name_indices(mut items []NameIndex) {
	for i := 0; i < items.len; i++ {
		for j := i + 1; j < items.len; j++ {
			if items[j].name < items[i].name {
				items[i], items[j] = items[j], items[i]
			}
		}
	}
}

fn binary_search_name_index(items []NameIndex, name string) ?usize {
	mut lo := 0
	mut hi := items.len
	for lo < hi {
		mid := lo + (hi - lo) / 2
		if items[mid].name < name {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	if lo < items.len && items[lo].name == name {
		return items[lo].index
	}
	return none
}

fn test_interp1() {
	assert interpolate_string(mut [NameIndex{'foo', 2}], ['', '', 'xxx'], 'test \$foo test') == 'test xxx test'
}

fn test_interp2() {
	assert interpolate_string(mut [NameIndex{'foo', 2}], ['', '', 'xxx'], 'test\$footest') == 'test'
}

fn test_interp3() {
	assert interpolate_string(mut [NameIndex{'foo', 2}], ['', '', 'xxx'], 'test\${foo}test') == 'testxxxtest'
}

fn test_interp4() {
	assert interpolate_string(mut [NameIndex{'foo', 2}], ['', '', 'xxx'], 'test\$2test') == 'test'
}

fn test_interp5() {
	assert interpolate_string(mut [NameIndex{'foo', 2}], ['', '', 'xxx'], 'test\${2}test') == 'testxxxtest'
}

fn test_interp6() {
	assert interpolate_string(mut [NameIndex{'foo', 2}], ['', '', 'xxx'], 'test \$\$foo test') == 'test \$foo test'
}

fn test_interp7() {
	assert interpolate_string(mut [NameIndex{'foo', 2}], ['', '', 'xxx'], 'test \$foo') == 'test xxx'
}

fn test_interp8() {
	assert interpolate_string(mut [NameIndex{'foo', 2}], ['', '', 'xxx'], '\$foo test') == 'xxx test'
}

fn test_interp9() {
	assert interpolate_string(mut [NameIndex{'bar', 1}, NameIndex{'foo', 2}], ['', 'yyy', 'xxx'], 'test \$bar\$foo') == 'test yyyxxx'
}

fn test_interp10() {
	assert interpolate_string(mut [NameIndex{'bar', 1}, NameIndex{'foo', 2}], ['', 'yyy', 'xxx'], 'test \$ test') == 'test \$ test'
}

fn test_interp11() {
	assert interpolate_string(mut [NameIndex{'bar', 1}, NameIndex{'foo', 2}], ['', 'yyy', 'xxx'], 'test \${} test') == 'test \${} test'
}

fn test_interp12() {
	assert interpolate_string(mut [NameIndex{'bar', 1}, NameIndex{'foo', 2}], ['', 'yyy', 'xxx'], 'test \${ } test') == 'test \${ } test'
}

fn test_interp13() {
	assert interpolate_string(mut [NameIndex{'bar', 1}, NameIndex{'foo', 2}], ['', 'yyy', 'xxx'], 'test \${a b} test') == 'test \${a b} test'
}

fn test_interp14() {
	assert interpolate_string(mut [NameIndex{'bar', 1}, NameIndex{'foo', 2}], ['', 'yyy', 'xxx'], 'test \${a} test') == 'test  test'
}
