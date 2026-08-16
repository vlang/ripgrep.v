module regex

fn analysis(pattern string) AstAnalysis {
	return AstAnalysis.from_pattern(pattern) or { panic('analysis failed') }
}

fn test_ast_analysis_various() {
	mut x := analysis('')
	assert !x.any_uppercase()
	assert !x.any_literal()

	x = analysis('foo')
	assert !x.any_uppercase()
	assert x.any_literal()

	x = analysis('Foo')
	assert x.any_uppercase()
	assert x.any_literal()

	x = analysis('foO')
	assert x.any_uppercase()
	assert x.any_literal()

	x = analysis(r'foo\\\\')
	assert !x.any_uppercase()
	assert x.any_literal()

	x = analysis(r'foo\w')
	assert !x.any_uppercase()
	assert x.any_literal()

	x = analysis(r'foo\S')
	assert !x.any_uppercase()
	assert x.any_literal()

	x = analysis(r'foo\p{Ll}')
	assert !x.any_uppercase()
	assert x.any_literal()

	x = analysis(r'foo[a-z]')
	assert !x.any_uppercase()
	assert x.any_literal()

	x = analysis(r'foo[A-Z]')
	assert x.any_uppercase()
	assert x.any_literal()

	x = analysis(r'foo[\S\t]')
	assert !x.any_uppercase()
	assert x.any_literal()

	x = analysis(r'foo\\\\S')
	assert x.any_uppercase()
	assert x.any_literal()

	x = analysis(r'\p{Ll}')
	assert !x.any_uppercase()
	assert !x.any_literal()

	x = analysis(r'aBc\w')
	assert x.any_uppercase()
	assert x.any_literal()

	x = analysis(r'a\u0061')
	assert !x.any_uppercase()
	assert x.any_literal()
}

fn test_ast_analysis_unicode_uppercase_literals() {
	for pattern in ['Δ', 'Я', r'\u0394', r'\x{042F}'] {
		x := analysis(pattern.clone())
		assert x.any_uppercase(), pattern
		assert x.any_literal(), pattern
	}
	for pattern in ['δ', 'я', 'ǅ', r'\u03B4', r'\x{044F}'] {
		x := analysis(pattern.clone())
		assert !x.any_uppercase(), pattern
		assert x.any_literal(), pattern
	}
}
