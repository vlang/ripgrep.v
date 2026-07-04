module flags

fn test_render_custom_markup_replaces_all_tags() {
	got := render_custom_markup('before \\flag{foo} middle \\flag{bar} after', 'flag', fn (name string, mut out []string) {
		out << '<${name}>'
	})
	assert got == 'before <foo> middle <bar> after'
}

fn test_render_custom_markup_leaves_other_tags_alone() {
	got := render_custom_markup('\\flag{foo} \\other{bar}', 'flag', fn (name string, mut out []string) {
		out << name.to_upper()
	})
	assert got == 'FOO \\other{bar}'
}
