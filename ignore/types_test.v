module ignore

fn assert_types_match(defs []string, sel []string, selnot []string, path string, matched bool) {
	mut btypes := TypesBuilder.new()
	for tydef in defs {
		has_err, err := btypes.add_def(tydef)
		assert !has_err, err.msg()
	}
	for selected in sel {
		btypes.select(selected)
	}
	for negated in selnot {
		btypes.negate(negated)
	}
	types, has_err, err := btypes.build()
	assert !has_err, err.msg()
	mat := types.matched(path, false)
	assert matched == !mat.is_ignore()
}

fn types_test_defs() []string {
	return [
		'html:*.html',
		'html:*.htm',
		'rust:*.rs',
		'js:*.js',
		'py:*.py',
		'python:*.py',
		'foo:*.{rs,foo}',
		'combo:include:html,rust',
	]
}

fn test_types_match1() {
	assert_types_match(types_test_defs(), ['rust'], [], 'lib.rs', true)
}

fn test_types_match2() {
	assert_types_match(types_test_defs(), ['html'], [], 'index.html', true)
}

fn test_types_match3() {
	assert_types_match(types_test_defs(), ['html'], [], 'index.htm', true)
}

fn test_types_match4() {
	assert_types_match(types_test_defs(), ['html', 'rust'], [], 'main.rs', true)
}

fn test_types_match5() {
	assert_types_match(types_test_defs(), [], [], 'index.html', true)
}

fn test_types_match6() {
	assert_types_match(types_test_defs(), [], ['rust'], 'index.html', true)
}

fn test_types_match7() {
	assert_types_match(types_test_defs(), ['foo'], ['rust'], 'main.foo', true)
}

fn test_types_match8() {
	assert_types_match(types_test_defs(), ['combo'], [], 'index.html', true)
}

fn test_types_match9() {
	assert_types_match(types_test_defs(), ['combo'], [], 'lib.rs', true)
}

fn test_types_match10() {
	assert_types_match(types_test_defs(), ['py'], [], 'main.py', true)
}

fn test_types_match11() {
	assert_types_match(types_test_defs(), ['python'], [], 'main.py', true)
}

fn test_types_matchnot1() {
	assert_types_match(types_test_defs(), ['rust'], [], 'index.html', false)
}

fn test_types_matchnot2() {
	assert_types_match(types_test_defs(), [], ['rust'], 'main.rs', false)
}

fn test_types_matchnot3() {
	assert_types_match(types_test_defs(), ['foo'], ['rust'], 'main.rs', false)
}

fn test_types_matchnot4() {
	assert_types_match(types_test_defs(), ['rust'], ['foo'], 'main.rs', false)
}

fn test_types_matchnot5() {
	assert_types_match(types_test_defs(), ['rust'], ['foo'], 'main.foo', false)
}

fn test_types_matchnot6() {
	assert_types_match(types_test_defs(), ['combo'], [], 'leftpad.js', false)
}

fn test_types_matchnot7() {
	assert_types_match(types_test_defs(), ['py'], [], 'index.html', false)
}

fn test_types_matchnot8() {
	assert_types_match(types_test_defs(), ['python'], [], 'doc.md', false)
}

fn test_types_invalid_defs() {
	mut btypes := TypesBuilder.new()
	for tydef in types_test_defs() {
		has_err, err := btypes.add_def(tydef)
		assert !has_err, err.msg()
	}
	// Preserve the original definitions for later comparison.
	original_defs := btypes.definitions()
	bad_defs := [
		// Reference to type that does not exist
		'combo:include:html,qwerty',
		// Bad format
		'combo:foobar:html,rust',
		'',
	]
	for def in bad_defs {
		has_err, _ := btypes.add_def(def)
		assert has_err
		// Ensure that nothing changed, even if some of the includes were valid.
		assert btypes.definitions() == original_defs
	}
}
