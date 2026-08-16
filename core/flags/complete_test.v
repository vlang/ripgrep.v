module flags

fn test_generate_complete_bash_includes_flags_and_operands() {
	got := generate_complete_bash()
	assert got.starts_with('_rg() {')
	assert got.contains('complete -F _rg -o bashdefault -o default rg')
	assert got.contains('--regexp -e ')
	assert got.contains('--no-ignore ')
	assert got.contains('<PATTERN> <PATH>...')
	assert got.contains('--color)')
	assert got.contains('compgen -W "never auto always ansi"')
}

fn test_generate_complete_fish_includes_prelude_and_argument_completions() {
	got := generate_complete_fish()
	assert got.contains("function __rg_contains_opt --description 'Specialized __fish_contains_opt'")
	assert got.contains("complete -c rg -s e -l regexp -d 'A pattern to search for.' -r -f")
	assert got.contains("complete -c rg -l ignore -n '__rg_contains_opt no-ignore '")
	assert got.contains("complete -c rg -s E -l encoding -d 'Specify the text encoding of files to search.' -r -f -a '")
}

fn test_generate_complete_powershell_includes_all_flag_forms() {
	got := generate_complete_powershell()
	assert got.starts_with('using namespace System.Management.Automation')
	assert got.contains("Register-ArgumentCompleter -Native -CommandName 'rg'")
	assert got.contains("[CompletionResult]::new('--regexp', 'regexp', [CompletionResultType]::ParameterName, 'A pattern to search for.')")
	assert got.contains("[CompletionResult]::new('-e', 'e', [CompletionResultType]::ParameterName, 'A pattern to search for.')")
	assert got.contains("[CompletionResult]::new('--no-ignore', 'no-ignore', [CompletionResultType]::ParameterName, 'Don''t use ignore files.')")
}

fn test_generate_complete_zsh_replaces_static_template_markers() {
	got := generate_complete_zsh()
	assert got.starts_with('#compdef rg')
	assert !got.contains('!ENCODINGS!')
	assert !got.contains('!HYPERLINK_ALIASES!')
	assert got.contains('utf{,-}8 utf-16{,be,le} unicode-1-1-utf-8')
	assert got.contains('    vscode:"VS Code scheme (vscode://)"')
}
