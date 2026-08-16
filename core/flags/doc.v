module flags

/*
Modules for generating documentation for ripgrep's flags.
*/

/// Searches for `\tag{...}` occurrences in `doc` and calls `replacement` for
/// each such tag found.
///
/// The first argument given to `replacement` is the tag value, `...`. The
/// second argument is the buffer that accumulates the full replacement text.
///
/// Since this function is only intended to be used on doc strings written into
/// the program source code, callers should panic in `replacement` if there are
/// any errors or unexpected circumstances.
fn render_custom_markup(doc string, tag string, replacement fn (string, mut []string)) string {
	mut remaining := doc
	mut out := []string{cap: doc.len}
	tag_prefix := r'\' + tag + '{'
	for {
		offset := remaining.index(tag_prefix) or {
			out << remaining
			break
		}
		out << remaining[..offset]
		start := offset + tag_prefix.len
		end_delta := remaining[start..].index('}') or {
			panic('found ${tag_prefix} without closing }')
		}
		end := start + end_delta
		name := remaining[start..end]
		replacement(name, mut out)
		remaining = remaining[end + 1..]
	}
	return out.join('')
}
