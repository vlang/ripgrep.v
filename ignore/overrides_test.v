module ignore

const overrides_root = '/home/andrew/foo'

fn override_from_globs(globs []string) Override {
	mut builder := OverrideBuilder.new(overrides_root)
	for glob in globs {
		add_has_err, add_err := builder.add(glob)
		assert !add_has_err, add_err.msg()
	}
	matcher, build_has_err, build_err := builder.build()
	assert !build_has_err, build_err.msg()
	return matcher
}

fn test_override_empty() {
	ov := override_from_globs([]string{})
	assert ov.matched('a.foo', false).is_none()
	assert ov.matched('a', false).is_none()
	assert ov.matched('', false).is_none()
}

fn test_override_simple() {
	ov := override_from_globs(['*.foo', '!*.bar'])
	assert ov.matched('a.foo', false).is_whitelist()
	assert ov.matched('a.foo', true).is_whitelist()
	assert ov.matched('a.rs', false).is_ignore()
	assert ov.matched('a.rs', true).is_none()
	assert ov.matched('a.bar', false).is_ignore()
	assert ov.matched('a.bar', true).is_ignore()
}

fn test_override_only_ignores() {
	ov := override_from_globs(['!*.bar'])
	assert ov.matched('a.rs', false).is_none()
	assert ov.matched('a.rs', true).is_none()
	assert ov.matched('a.bar', false).is_ignore()
	assert ov.matched('a.bar', true).is_ignore()
}

fn test_override_precedence() {
	ov := override_from_globs(['*.foo', '!*.bar.foo'])
	assert ov.matched('a.foo', false).is_whitelist()
	assert ov.matched('a.baz', false).is_ignore()
	assert ov.matched('a.bar.foo', false).is_ignore()
}

fn test_override_gitignore_semantics() {
	ov := override_from_globs(['/foo', 'bar/*.rs', 'baz/**'])
	assert ov.matched('bar/lib.rs', false).is_whitelist()
	assert ov.matched('bar/wat/lib.rs', false).is_ignore()
	assert ov.matched('wat/bar/lib.rs', false).is_ignore()
	assert ov.matched('foo', false).is_whitelist()
	assert ov.matched('wat/foo', false).is_ignore()
	assert ov.matched('baz', false).is_ignore()
	assert ov.matched('baz/a', false).is_whitelist()
	assert ov.matched('baz/a/b', false).is_whitelist()
}

fn test_override_allow_directories() {
	ov := override_from_globs(['*.rs'])
	assert ov.matched('foo.rs', false).is_whitelist()
	assert ov.matched('foo.c', false).is_ignore()
	assert ov.matched('foo', false).is_ignore()
	assert ov.matched('foo', true).is_none()
	assert ov.matched('src/foo.rs', false).is_whitelist()
	assert ov.matched('src/foo.c', false).is_ignore()
	assert ov.matched('src/foo', false).is_ignore()
	assert ov.matched('src/foo', true).is_none()
}

fn test_override_absolute_path() {
	ov := override_from_globs(['!/bar'])
	assert ov.matched('./foo/bar', false).is_none()
}

fn test_override_case_insensitive() {
	mut builder := OverrideBuilder.new(overrides_root)
	case_has_err, case_err := builder.case_insensitive(true)
	assert !case_has_err, case_err.msg()
	add_has_err, add_err := builder.add('*.html')
	assert !add_has_err, add_err.msg()
	ov, build_has_err, build_err := builder.build()
	assert !build_has_err, build_err.msg()
	assert ov.matched('foo.html', false).is_whitelist()
	assert ov.matched('foo.HTML', false).is_whitelist()
	assert ov.matched('foo.htm', false).is_ignore()
	assert ov.matched('foo.HTM', false).is_ignore()
}

fn test_override_default_case_sensitive() {
	mut builder := OverrideBuilder.new(overrides_root)
	add_has_err, add_err := builder.add('*.html')
	assert !add_has_err, add_err.msg()
	ov, build_has_err, build_err := builder.build()
	assert !build_has_err, build_err.msg()
	assert ov.matched('foo.html', false).is_whitelist()
	assert ov.matched('foo.HTML', false).is_ignore()
	assert ov.matched('foo.htm', false).is_ignore()
	assert ov.matched('foo.HTM', false).is_ignore()
}
