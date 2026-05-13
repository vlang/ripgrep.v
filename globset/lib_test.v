module globset

fn test_glob_set_works() {
	mut builder := GlobSetBuilder.new()
	builder.add(Glob.new('src/**/*.rs') or { panic(err) })
	builder.add(Glob.new('*.c') or { panic(err) })
	builder.add(Glob.new('src/lib.rs') or { panic(err) })
	set := builder.build() or { panic(err) }

	assert set.is_match('foo.c')
	assert set.is_match('src/foo.c')
	assert !set.is_match('foo.rs')
	assert !set.is_match('tests/foo.rs')
	assert set.is_match('src/foo.rs')
	assert set.is_match('src/grep/src/main.rs')

	matches := set.matches('src/lib.rs')
	assert matches.len == 2
	assert matches[0] == usize(0)
	assert matches[1] == usize(2)
}

fn test_empty_glob_set_works() {
	set := GlobSetBuilder.new().build() or { panic(err) }
	assert !set.is_match('')
	assert !set.is_match('a')
	assert set.matches_all('a')
}

fn test_escape() {
	assert escape('foo') == 'foo'
	assert escape('foo*') == 'foo[*]'
	assert escape('[]') == '[[][]]'
	assert escape('*?') == '[*][?]'
	assert escape('src/**/*.rs') == 'src/[*][*]/[*].rs'
	assert escape('bar[ab]baz') == 'bar[[]ab[]]baz'
	assert escape('bar[!!]!baz') == 'bar[[]!![]]!baz'
}
