module flags

/// Returns a `roff` formatted string corresponding to ripgrep's entire man
/// page.
pub fn generate_man() string {
	categories := doc_category_order()
	mut cats := []string{len: categories.len}
	for flag in flags {
		idx := doc_category_index(flag.doc_category())
		if cats[idx] != '' {
			cats[idx] += '.sp\n'
		}
		cats[idx] += generate_man_flag(flag)
	}

	mut out := $embed_file('doc/template.rg.1').to_string().replace('!!VERSION!!',
		generate_version_digits())
	for i, cat in categories {
		var := '!!${cat.as_str()}!!'
		out = out.replace(var, cats[i])
	}
	return out
}

/// Writes `roff` formatted documentation for `flag` to `out`.
fn generate_man_flag(flag FlagId) string {
	mut out := ''
	if byte := flag.name_short() {
		out += r'\fB\-'
		out += byte.ascii_str()
		out += r'\fP'
		if var := flag.doc_variable() {
			out += r' \fI'
			out += var
			out += r'\fP'
		}
		out += ', '
	}

	name := flag.name_long().replace('-', r'\-')
	out += r'\fB\-\-'
	out += name
	out += r'\fP'
	if var := flag.doc_variable() {
		out += r'=\fI'
		out += var
		out += r'\fP'
	}
	out += '\n'

	out += '.RS 4\n'
	doc := flag.doc_long().trim_space()
	// Convert \flag{foo} into something nicer.
	mut rendered := render_custom_markup(doc, 'flag', fn (name string, mut out []string) {
		flag := lookup(name) or { panic('found unrecognized \\flag{${name}} in roff docs') }
		out << r'\fB'
		if byte := flag.name_short() {
			out << r'\-'
			out << byte.ascii_str()
			out << '/'
		}
		out << r'\-\-'
		out << flag.name_long().replace('-', r'\-')
		out << r'\fP'
	})
	// Convert \flag-negate{foo} into something nicer.
	rendered = render_custom_markup(rendered, 'flag-negate', fn (name string, mut out []string) {
		flag := lookup(name) or { panic('found unrecognized \\flag-negate{${name}} in roff docs') }
		negated := flag.name_negated() or {
			long := flag.name_long()
			panic('found \\flag-negate{${long}} in roff docs but ${long} does not have a negation')
		}
		out << r'\fB'
		out << r'\-\-'
		out << negated
		out << r'\fP'
	})
	out += rendered
	out += '\n'
	if negated := flag.name_negated() {
		// Flags that can be negated that aren't switches, like
		// --context-separator, are somewhat weird. Because of that, the docs
		// for those flags should discuss the semantics of negation explicitly.
		// But for switches, the behavior is always the same.
		if flag.is_switch() {
			out += '.sp\n'
			out += r'This flag can be disabled with \fB\-\-'
			out += negated
			out += r'\fP.'
			out += '\n'
		}
	}
	out += '.RE\n'
	return out
}
