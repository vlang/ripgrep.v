module ignore

fn test_default_types_are_sorted() {
	defs := default_types()
	if defs.len == 0 {
		return
	}
	mut previous_name := defs[0].names[0]
	for def in defs[1..] {
		name := def.names[0]
		assert name > previous_name, '"${name}" should be sorted before "${previous_name}" in `DEFAULT_TYPES`'
		previous_name = name
	}
}
