module flags

struct CompletionHyperlinkAlias {
	name        string
	description string
}

// V2 direct-file compilation for core/flags cannot resolve sibling module
// imports yet, so this mirrors grep-printer's public hyperlink alias
// descriptions used by ripgrep's Rust zsh generator.
fn completion_hyperlink_aliases() []CompletionHyperlinkAlias {
	return [
		CompletionHyperlinkAlias{
			name:        'cursor'
			description: 'Cursor scheme (cursor://)'
		},
		CompletionHyperlinkAlias{
			name:        'default'
			description: 'RFC 8089 scheme (file://) (platform-aware)'
		},
		CompletionHyperlinkAlias{
			name:        'file'
			description: 'RFC 8089 scheme (file://) with host'
		},
		CompletionHyperlinkAlias{
			name:        'grep+'
			description: 'grep+ scheme (grep+://)'
		},
		CompletionHyperlinkAlias{
			name:        'kitty'
			description: 'kitty-style RFC 8089 scheme (file://) with line number'
		},
		CompletionHyperlinkAlias{
			name:        'macvim'
			description: 'MacVim scheme (mvim://)'
		},
		CompletionHyperlinkAlias{
			name:        'none'
			description: 'disable hyperlinks'
		},
		CompletionHyperlinkAlias{
			name:        'textmate'
			description: 'TextMate scheme (txmt://)'
		},
		CompletionHyperlinkAlias{
			name:        'vscode'
			description: 'VS Code scheme (vscode://)'
		},
		CompletionHyperlinkAlias{
			name:        'vscode-insiders'
			description: 'VS Code Insiders scheme (vscode-insiders://)'
		},
		CompletionHyperlinkAlias{
			name:        'vscodium'
			description: 'VSCodium scheme (vscodium://)'
		},
	]
}

/// Generate completions for zsh.
pub fn generate_complete_zsh() string {
	mut alias_lines := []string{}
	for alias in completion_hyperlink_aliases() {
		alias_lines << '    ${alias.name}:"${alias.description}"'
	}
	hyperlink_alias_descriptions := alias_lines.join('\n')
	return $embed_file('complete/rg.zsh').to_string().replace('!ENCODINGS!',
		completion_encodings().trim_right('\n')).replace('!HYPERLINK_ALIASES!',
		hyperlink_alias_descriptions)
}
