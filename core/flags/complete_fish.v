module flags

const complete_fish_template = "complete -c rg !SHORT! -l !LONG! -d '!DOC!'"
const complete_fish_template_negated = "complete -c rg -l !NEGATED! -n '__rg_contains_opt !LONG! !SHORT!' -d '!DOC!'\n"

/// Generate completions for Fish.
///
/// Reference: <https://fishshell.com/docs/current/completions.html>
pub fn generate_complete_fish() string {
	mut out := ''
	out += $embed_file('complete/prelude.fish').to_string()
	out += '\n'
	for flag in flags {
		short := if short_byte := flag.name_short() {
			'-s ${short_byte.ascii_str()}'
		} else {
			''
		}
		long := flag.name_long()
		doc := flag.doc_short().replace("'", "\\'")
		mut completion :=
			complete_fish_template.replace('!SHORT!', short).replace('!LONG!', long).replace('!DOC!', doc)

		match flag.completion_type() {
			.filename {
				completion += ' -r -F'
			}
			.executable {
				completion += " -r -f -a '(__fish_complete_command)'"
			}
			.filetype {
				completion += " -r -f -a '(rg --type-list | string replace : \\t)'"
			}
			.encoding {
				completion += " -r -f -a '"
				completion += completion_encodings()
				completion += "'"
			}
			.other {
				if flag.doc_choices().len > 0 {
					completion += " -r -f -a '"
					completion += flag.doc_choices().join(' ')
					completion += "'"
				} else if !flag.is_switch() {
					completion += ' -r -f'
				}
			}
		}

		completion += '\n'
		out += completion

		if negated := flag.name_negated() {
			short_negated := if short_byte := flag.name_short() {
				short_byte.ascii_str()
			} else {
				''
			}
			out += complete_fish_template_negated.replace('!NEGATED!', negated).replace('!SHORT!',
				short_negated).replace('!LONG!', long).replace('!DOC!', doc)
		}
	}
	return out
}
