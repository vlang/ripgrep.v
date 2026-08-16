module flags

const complete_powershell_template_flag = "[CompletionResult]::new('!DASH_NAME!', '!NAME!', [CompletionResultType]::ParameterName, '!DOC!')"

/// Generate completions for PowerShell.
///
/// Note that these completions are based on what was produced for ripgrep <=13
/// using Clap 2.x. Improvements on this are welcome.
pub fn generate_complete_powershell() string {
	mut flags_out := ''
	for i, flag in flag_defs {
		doc := flag.doc_short().replace("'", "''")

		dash_name := '--${flag.name_long()}'
		name := flag.name_long()
		if i > 0 {
			flags_out += '\n'
		}
		flags_out += '      '
		flags_out +=
			complete_powershell_template_flag.replace('!DASH_NAME!', dash_name).replace('!NAME!', name).replace('!DOC!', doc)

		if byte := flag.name_short() {
			short_dash_name := '-${byte.ascii_str()}'
			short_name := byte.ascii_str()
			flags_out += '\n      '
			flags_out += complete_powershell_template_flag.replace('!DASH_NAME!', short_dash_name).replace('!NAME!',
				short_name).replace('!DOC!', doc)
		}

		if negated := flag.name_negated() {
			negated_dash_name := '--${negated}'
			flags_out += '\n      '
			flags_out += complete_powershell_template_flag.replace('!DASH_NAME!', negated_dash_name).replace('!NAME!',
				negated).replace('!DOC!', doc)
		}
	}
	return $embed_file('complete/powershell.ps1').to_string().trim_left('\n').replace('!FLAGS!',
		flags_out)
}
