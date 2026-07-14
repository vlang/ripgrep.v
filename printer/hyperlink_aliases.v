module printer

fn alias(name string, description string, format string) HyperlinkAlias {
	return HyperlinkAlias{
		name_:        name.to_owned()
		description_: description.to_owned()
		format_:      format.to_owned()
	}
}

fn prioritized_alias(priority i16, name string, description string, format string) HyperlinkAlias {
	return HyperlinkAlias{
		name_:             name.to_owned()
		description_:      description.to_owned()
		format_:           format.to_owned()
		display_priority_: priority
	}
}

fn hyperlink_pattern_aliases() []HyperlinkAlias {
	return [
		alias('cursor', 'Cursor scheme (cursor://)', 'cursor://file{path}:{line}:{column}'),
		$if windows {
			prioritized_alias(0, 'default', 'RFC 8089 scheme (file://) (platform-aware)',
				'file://{path}')
		} $else {
			prioritized_alias(0, 'default', 'RFC 8089 scheme (file://) (platform-aware)',
				'file://{host}{path}')
		},
		alias('file', 'RFC 8089 scheme (file://) with host', 'file://{host}{path}'),
		alias('grep+', 'grep+ scheme (grep+://)', 'grep+://{path}:{line}'),
		alias('kitty', 'kitty-style RFC 8089 scheme (file://) with line number',
			'file://{host}{path}#{line}'),
		alias('macvim', 'MacVim scheme (mvim://)',
			'mvim://open?url=file://{path}&line={line}&column={column}'),
		prioritized_alias(1, 'none', 'disable hyperlinks', ''),
		alias('textmate', 'TextMate scheme (txmt://)',
			'txmt://open?url=file://{path}&line={line}&column={column}'),
		alias('vscode', 'VS Code scheme (vscode://)', 'vscode://file{path}:{line}:{column}'),
		alias('vscode-insiders', 'VS Code Insiders scheme (vscode-insiders://)',
			'vscode-insiders://file{path}:{line}:{column}'),
		alias('vscodium', 'VSCodium scheme (vscodium://)', 'vscodium://file{path}:{line}:{column}'),
	]
}
