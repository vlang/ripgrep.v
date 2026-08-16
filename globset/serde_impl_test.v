module globset

fn test_glob_deserialize_borrowed() {
	json_text := r'{"markdown": "*.md"}'
	map_ := glob_map_from_json(json_text)!
	got := map_['markdown'] or { panic('missing markdown glob') }
	assert got.glob().clone() == '*.md'
}

fn test_glob_deserialize_owned() {
	json_text := r'{"markdown": "*.md"}'
	map_ := glob_map_from_json(json_text)!
	got := map_['markdown'] or { panic('missing markdown glob') }
	assert got.glob().clone() == '*.md'
}

fn test_glob_deserialize_error() {
	json_text := r'{"error": "["}'
	if _ := glob_map_from_json(json_text) {
		assert false
	}
}

fn test_glob_json_works() {
	test_glob := Glob.new('src/**/*.rs')!
	ser := test_glob.to_json()
	assert ser == '"src/**/*.rs"'
	de := Glob.from_json(ser)!
	assert de.glob().clone() == test_glob.glob().clone()
}

fn test_glob_set_deserialize() {
	j := r' ["src/**/*.rs", "README.md"] '
	set := GlobSet.from_json(j)!
	assert set.is_match('src/lib.rs')
	assert !set.is_match('Cargo.lock')
}
