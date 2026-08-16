module flags

fn test_generate_help_short_replaces_category_markers() {
	got := generate_help_short()
	assert got.starts_with('ripgrep ')
	assert got.contains('USAGE:')
	assert got.contains('INPUT OPTIONS:')
	assert got.contains('-e, --regexp=PATTERN')
	assert got.contains('A pattern to search for.')
	assert !got.contains('!!input!!')
	assert !got.contains('!!search!!')
}

fn test_generate_help_long_renders_flag_markup_and_wrapping() {
	got := generate_help_long()
	assert got.starts_with('ripgrep ')
	assert got.contains('    -e PATTERN, --regexp=PATTERN')
	assert got.contains('-e/--regexp')
	assert got.contains('This flag can be disabled with --ignore.')
	assert !got.contains(r'\flag{')
	assert !got.contains(r'\fB')
}

fn test_generate_man_renders_roff_markup_and_negations() {
	got := generate_man()
	assert got.starts_with('.TH RG 1 ')
	assert got.contains(r'\fB\-e\fP \fIPATTERN\fP, \fB\-\-regexp\fP=\fIPATTERN\fP')
	assert got.contains(r'\fB\-e/\-\-regexp\fP')
	assert got.contains(r'This flag can be disabled with \fB\-\-ignore\fP.')
	assert !got.contains('!!input!!')
	assert !got.contains(r'\flag{')
}

fn test_remove_roff_plain_text_heuristics() {
	got := remove_roff(r'
.IP \(bu 3n
\fBthing\fP
.sp
.BI foo bar
plain \fBbold\fP and escaped \- dash
')
	assert got == '\u2022\nthing:\n\nfoobar\nplain bold and escaped - dash'
}
