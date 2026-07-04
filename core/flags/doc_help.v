module flags

fn doc_category_order() []Category {
	return [
		Category.input,
		.search,
		.filter,
		.output,
		.output_modes,
		.logging,
		.other_behaviors,
	]
}

fn doc_category_index(category Category) int {
	for i, cat in doc_category_order() {
		if cat == category {
			return i
		}
	}
	panic('unrecognized documentation category')
}

/// Generate short documentation, i.e., for `-h`.
pub fn generate_help_short() string {
	categories := doc_category_order()
	mut maxcol1 := 0
	mut maxcol2 := 0
	for flag in flags {
		col1, col2 := generate_short_flag(flag)
		if col1.len > maxcol1 {
			maxcol1 = col1.len
		}
		if col2.len > maxcol2 {
			maxcol2 = col2.len
		}
	}
	mut out := $embed_file('doc/template.short.help').to_string().replace('!!VERSION!!',
		generate_version_digits())
	for cat in categories {
		mut col1 := []string{}
		mut col2 := []string{}
		for flag in flags {
			if flag.doc_category() != cat {
				continue
			}
			c1, c2 := generate_short_flag(flag)
			col1 << c1
			col2 << c2
		}
		var := '!!${cat.as_str()}!!'
		val := format_short_columns(col1, col2, maxcol1, maxcol2)
		out = out.replace(var, val)
	}
	return out
}

/// Generate short for a single flag.
///
/// The first element corresponds to the flag name while the second element
/// corresponds to the documentation string.
fn generate_short_flag(flag FlagId) (string, string) {
	mut col1 := ''
	mut col2 := ''

	// Some of the variable names are fine for longer form
	// docs, but they make the succinct short help very noisy.
	// So just shorten some of them.
	var := if value := flag.doc_variable() {
		value.replace('SEPARATOR', 'SEP').replace('REPLACEMENT', 'TEXT').replace('NUM+SUFFIX?',
			'NUM')
	} else {
		''
	}

	// Generate the first column, the flag name.
	if byte := flag.name_short() {
		col1 += '-${byte.ascii_str()}'
		col1 += ', '
	}
	col1 += '--${flag.name_long()}'
	if var != '' {
		col1 += '=${var}'
	}

	// And now the second column, with the description.
	col2 += flag.doc_short()

	return col1, col2
}

/// Write two columns of documentation.
///
/// `maxcol1` should be the maximum length (in bytes) of the first column,
/// while `maxcol2` should be the maximum length (in bytes) of the second
/// column.
fn format_short_columns(col1 []string, col2 []string, maxcol1 int, _maxcol2 int) string {
	assert col1.len == col2.len, 'columns must have equal length'
	pad_width := 2
	mut target_maxcol1 := maxcol1
	for c1 in col1 {
		if c1.len > target_maxcol1 {
			target_maxcol1 = c1.len
		}
	}
	mut out := ''
	for i, c1 in col1 {
		if i > 0 {
			out += '\n'
		}
		pad := target_maxcol1 - c1.len + pad_width
		out += '  '
		out += c1
		out += ' '.repeat(pad)
		out += col2[i]
	}
	return out
}

/// Generate long documentation, i.e., for `--help`.
pub fn generate_help_long() string {
	categories := doc_category_order()
	mut cats := []string{len: categories.len}
	for flag in flags {
		idx := doc_category_index(flag.doc_category())
		if cats[idx] != '' {
			cats[idx] += '\n\n'
		}
		cats[idx] += generate_long_flag(flag)
	}

	mut out := $embed_file('doc/template.long.help').to_string().replace('!!VERSION!!',
		generate_version_digits())
	for i, cat in categories {
		var := '!!${cat.as_str()}!!'
		out = out.replace(var, cats[i])
	}
	return out
}

/// Write generated documentation for `flag` to `out`.
fn generate_long_flag(flag FlagId) string {
	mut out := ''
	if byte := flag.name_short() {
		out += '    -${byte.ascii_str()}'
		if var := flag.doc_variable() {
			out += ' ${var}'
		}
		out += ', '
	} else {
		out += '    '
	}

	name := flag.name_long()
	out += '--${name}'
	if var := flag.doc_variable() {
		out += '=${var}'
	}
	out += '\n'

	doc := flag.doc_long().trim_space()
	mut rendered := render_custom_markup(doc, 'flag', fn (name string, mut out []string) {
		flag := lookup(name) or { panic('found unrecognized \\flag{${name}} in --help docs') }
		if byte := flag.name_short() {
			out << '-${byte.ascii_str()}/'
		}
		out << '--${flag.name_long()}'
	})
	rendered = render_custom_markup(rendered, 'flag-negate', fn (name string, mut out []string) {
		flag := lookup(name) or {
			panic('found unrecognized \\flag-negate{${name}} in --help docs')
		}
		negated := flag.name_negated() or {
			long := flag.name_long()
			panic('found \\flag-negate{${long}} in --help docs but ${long} does not have a negation')
		}
		out << '--${negated}'
	})

	mut cleaned := remove_roff(rendered)
	if negated := flag.name_negated() {
		// Flags that can be negated that aren't switches, like
		// --context-separator, are somewhat weird. Because of that, the docs
		// for those flags should discuss the semantics of negation explicitly.
		// But for switches, the behavior is always the same.
		if flag.is_switch() {
			cleaned += '\n\nThis flag can be disabled with --${negated}.'
		}
	}
	indent := ' '.repeat(8)
	for i, paragraph in cleaned.split('\n\n') {
		if i > 0 {
			out += '\n\n'
		}
		mut new_paragraph := paragraph
		if paragraph.split('\n').all(it.starts_with('    ')) {
			// Re-indent but don't refill so as to preserve line breaks
			// in code/shell example snippets.
			new_paragraph = indent_text(new_paragraph, indent)
		} else {
			new_paragraph = new_paragraph.replace('\n', ' ')
			new_paragraph = refill_no_hyphen(new_paragraph, 71)
			new_paragraph = indent_text(new_paragraph, indent)
		}
		out += new_paragraph.trim_right(' \n\t\r')
	}
	return out
}

/// Removes roff syntax from `v` such that the result is approximately plain
/// text readable.
///
/// This is basically a mish mash of heuristics based on the specific roff used
/// in the docs for the flags in this tool. If new kinds of roff are used in
/// the docs, then this may need to be updated to handle them.
fn remove_roff(v string) string {
	mut lines := []string{}
	for raw_line in v.trim_space().split('\n') {
		line := raw_line
		assert line != '', 'roff should have no empty lines'
		if line.starts_with('.') {
			if line.starts_with('.IP ') {
				parts := line.split(' ')
				item_label :=
					parts[1].replace(r'\(bu', '\u2022').replace(r'\fB', '').replace(r'\fP', ':')
				lines << item_label
			} else if line.starts_with('.IB ') || line.starts_with('.BI ') {
				pieces := split_ascii_whitespace(line)[1..].join('')
				lines << pieces
			} else if line.starts_with('.sp') || line.starts_with('.PP') || line.starts_with('.TP') {
				lines << ''
			}
		} else if line.starts_with(r'\fB') && line.ends_with(r'\fP') {
			lines << line.replace(r'\fB', '').replace(r'\fP', '') + ':'
		} else {
			lines << line
		}
	}
	// Squash multiple adjacent paragraph breaks into one.
	mut squashed := []string{}
	for line in lines {
		if line == '' && squashed.len > 0 && squashed[squashed.len - 1] == '' {
			continue
		}
		squashed << line
	}
	return squashed.join('\n').replace(r'\fB', '').replace(r'\fI', '').replace(r'\fP', '').replace(r'\-',
		'-').replace(r'\\', r'\')
}

fn split_ascii_whitespace(s string) []string {
	mut fields := []string{}
	mut start := 0
	mut in_field := false
	for i, b in s.bytes() {
		is_space := b == ` ` || b == `\t` || b == `\n` || b == `\r` || b == `\v` || b == `\f`
		if is_space {
			if in_field {
				fields << s[start..i]
				in_field = false
			}
		} else if !in_field {
			start = i
			in_field = true
		}
	}
	if in_field {
		fields << s[start..]
	}
	return fields
}

fn refill_no_hyphen(s string, width int) string {
	words := split_ascii_whitespace(s)
	if words.len == 0 {
		return ''
	}
	mut out := ''
	mut line_len := 0
	for word in words {
		if line_len == 0 {
			out += word
			line_len = word.len
		} else if line_len + 1 + word.len <= width {
			out += ' '
			out += word
			line_len += 1 + word.len
		} else {
			out += '\n'
			out += word
			line_len = word.len
		}
	}
	return out
}

fn indent_text(s string, prefix string) string {
	mut out := ''
	lines := s.split('\n')
	for i, line in lines {
		if i > 0 {
			out += '\n'
		}
		out += prefix
		out += line
	}
	return out
}
