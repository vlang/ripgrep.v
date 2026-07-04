module regex

/// The results of analyzing AST of a regular expression (e.g., for supporting
/// smart case).
pub struct AstAnalysis implements IClone {
	/// True if and only if a literal uppercase character occurs in the regex.
	any_uppercase bool
	/// True if and only if the regex contains any literal at all.
	any_literal bool
}

/// Returns a `AstAnalysis` value by doing analysis on the AST of `pattern`.
///
/// If `pattern` is not a valid regular expression, then `None` is
/// returned.
pub fn AstAnalysis.from_pattern(pattern string) ?AstAnalysis {
	mut parser := AstAnalysisParser.new(pattern)
	return parser.parse()
}

/// Perform an AST analysis given the AST.
///
/// V-specific: until `regex_syntax::ast::Ast` is translated, this takes the
/// original pattern wrapper used by this module's local parser.
pub fn AstAnalysis.from_ast(ast RegexAst) AstAnalysis {
	return AstAnalysis.from_pattern(ast.pattern) or { AstAnalysis.new() }
}

/// Returns true if and only if a literal uppercase character occurs in
/// the pattern.
///
/// For example, a pattern like `\pL` contains no uppercase literals,
/// even though `L` is uppercase and the `\pL` class contains uppercase
/// characters.
pub fn (analysis AstAnalysis) any_uppercase() bool {
	return analysis.any_uppercase
}

/// Returns true if and only if the regex contains any literal at all.
///
/// For example, a pattern like `\pL` reports `false`, but a pattern like
/// `\pLfoo` reports `true`.
pub fn (analysis AstAnalysis) any_literal() bool {
	return analysis.any_literal
}

/// Creates a new `AstAnalysis` value with an initial configuration.
fn AstAnalysis.new() AstAnalysis {
	return AstAnalysis{
		any_uppercase: false
		any_literal:   false
	}
}

/// Returns true if and only if the attributes can never change no matter
/// what other AST it might see.
fn (analysis AstAnalysis) done() bool {
	return analysis.any_uppercase && analysis.any_literal
}

pub struct RegexAst implements IClone {
	pattern string
}

pub fn RegexAst.new(pattern string) RegexAst {
	return RegexAst{
		pattern: pattern.to_owned()
	}
}

struct AstAnalysisParser {
	pattern string
mut:
	pos      int
	analysis AstAnalysis
}

fn AstAnalysisParser.new(pattern string) AstAnalysisParser {
	return AstAnalysisParser{
		pattern:  pattern.to_owned()
		analysis: AstAnalysis.new()
	}
}

fn (mut parser AstAnalysisParser) parse() ?AstAnalysis {
	if !parser.parse_until(0, false) {
		return none
	}
	if parser.pos != parser.pattern.len {
		return none
	}
	return parser.analysis
}

fn (mut parser AstAnalysisParser) parse_until(end byte, in_class bool) bool {
	for parser.pos < parser.pattern.len && !parser.analysis.done() {
		ch := parser.pattern[parser.pos]
		if end != 0 && ch == end {
			return true
		}
		match ch {
			`\\` {
				if !parser.parse_escape(in_class) {
					return false
				}
			}
			`[` {
				parser.pos++
				if !parser.parse_class() {
					return false
				}
			}
			`(` {
				if !parser.parse_group() {
					return false
				}
			}
			`)` {
				if end == 0 {
					return false
				}
				return true
			}
			else {
				if !is_regex_meta_literal(ch, in_class) {
					parser.add_literal_byte(ch)
				}
				parser.pos++
			}
		}
	}
	for parser.pos < parser.pattern.len {
		if end != 0 && parser.pattern[parser.pos] == end {
			return true
		}
		if parser.pattern[parser.pos] == `\\` {
			parser.pos++
			if !parser.skip_escape_tail() {
				return false
			}
		} else if parser.pattern[parser.pos] == `[` {
			parser.pos++
			if !parser.skip_class() {
				return false
			}
		} else if parser.pattern[parser.pos] == `(` {
			if !parser.skip_group() {
				return false
			}
		} else if parser.pattern[parser.pos] == `)` && end == 0 {
			return false
		} else {
			parser.pos++
		}
	}
	if end != 0 {
		return false
	}
	return true
}

fn (mut parser AstAnalysisParser) parse_group() bool {
	parser.pos++
	if parser.pos < parser.pattern.len && parser.pattern[parser.pos] == `?` {
		parser.pos++
		if parser.pos >= parser.pattern.len {
			return false
		}
		if parser.pattern[parser.pos] == `:` {
			parser.pos++
		} else {
			for parser.pos < parser.pattern.len && parser.pattern[parser.pos] != `:` && parser.pattern[parser.pos] != `)` {
				parser.pos++
			}
			if parser.pos < parser.pattern.len && parser.pattern[parser.pos] == `:` {
				parser.pos++
			}
		}
	}
	if !parser.parse_until(`)`, false) {
		return false
	}
	if parser.pos >= parser.pattern.len || parser.pattern[parser.pos] != `)` {
		return false
	}
	parser.pos++
	return true
}

fn (mut parser AstAnalysisParser) parse_class() bool {
	if parser.pos < parser.pattern.len && parser.pattern[parser.pos] == `^` {
		parser.pos++
	}
	for parser.pos < parser.pattern.len && !parser.analysis.done() {
		ch := parser.pattern[parser.pos]
		if ch == `]` {
			parser.pos++
			return true
		}
		if ch == `\\` {
			if !parser.parse_escape(true) {
				return false
			}
		} else if ch == `[` {
			parser.pos++
			if !parser.parse_class() {
				return false
			}
		} else {
			parser.add_literal_byte(ch)
			parser.pos++
		}
	}
	for parser.pos < parser.pattern.len {
		ch := parser.pattern[parser.pos]
		if ch == `]` {
			parser.pos++
			return true
		}
		if ch == `\\` {
			parser.pos++
			if !parser.skip_escape_tail() {
				return false
			}
		} else if ch == `[` {
			parser.pos++
			if !parser.skip_class() {
				return false
			}
		} else {
			parser.pos++
		}
	}
	return false
}

fn (mut parser AstAnalysisParser) parse_escape(in_class bool) bool {
	parser.pos++
	if parser.pos >= parser.pattern.len {
		return false
	}
	ch := parser.pattern[parser.pos]
	match ch {
		`p`, `P` {
			parser.pos++
			if !parser.skip_property_escape() {
				return false
			}
		}
		`u` {
			parser.pos++
			if !parser.parse_hex_escape(4) {
				return false
			}
		}
		`U` {
			parser.pos++
			if !parser.parse_hex_escape(8) {
				return false
			}
		}
		`x` {
			parser.pos++
			if !parser.parse_x_escape() {
				return false
			}
		}
		`d`, `D`, `s`, `S`, `w`, `W`, `b`, `B`, `A`, `z` {
			parser.pos++
		}
		else {
			_ = in_class
			parser.add_literal_byte(ch)
			parser.pos++
		}
	}
	return true
}

fn (mut parser AstAnalysisParser) skip_escape_tail() bool {
	if parser.pos >= parser.pattern.len {
		return false
	}
	ch := parser.pattern[parser.pos]
	match ch {
		`p`, `P` {
			parser.pos++
			if !parser.skip_property_escape() {
				return false
			}
		}
		`u` {
			parser.pos++
			if !parser.skip_n(4) {
				return false
			}
		}
		`U` {
			parser.pos++
			if !parser.skip_n(8) {
				return false
			}
		}
		`x` {
			parser.pos++
			if parser.pos < parser.pattern.len && parser.pattern[parser.pos] == `{` {
				parser.pos++
				for parser.pos < parser.pattern.len && parser.pattern[parser.pos] != `}` {
					parser.pos++
				}
				if parser.pos >= parser.pattern.len {
					return false
				}
				parser.pos++
			} else {
				if !parser.skip_n(2) {
					return false
				}
			}
		}
		else {
			parser.pos++
		}
	}
	return true
}

fn (mut parser AstAnalysisParser) parse_x_escape() bool {
	if parser.pos < parser.pattern.len && parser.pattern[parser.pos] == `{` {
		parser.pos++
		start := parser.pos
		for parser.pos < parser.pattern.len && parser.pattern[parser.pos] != `}` {
			if !is_hex_digit(parser.pattern[parser.pos]) {
				return false
			}
			parser.pos++
		}
		if parser.pos >= parser.pattern.len || parser.pos == start {
			return false
		}
		hex := parser.pattern[start..parser.pos]
		parser.pos++
		parser.add_literal_codepoint(parse_hex_u32(hex) or { return false })
		return true
	}
	start := parser.pos
	if !parser.parse_hex_escape_bytes(2) {
		return false
	}
	parser.add_literal_codepoint(parse_hex_u32(parser.pattern[start..parser.pos]) or { return false })
	return true
}

fn (mut parser AstAnalysisParser) parse_hex_escape(width int) bool {
	start := parser.pos
	if !parser.parse_hex_escape_bytes(width) {
		return false
	}
	parser.add_literal_codepoint(parse_hex_u32(parser.pattern[start..parser.pos]) or { return false })
	return true
}

fn (mut parser AstAnalysisParser) parse_hex_escape_bytes(width int) bool {
	if parser.pos + width > parser.pattern.len {
		return false
	}
	for _ in 0 .. width {
		if !is_hex_digit(parser.pattern[parser.pos]) {
			return false
		}
		parser.pos++
	}
	return true
}

fn (mut parser AstAnalysisParser) skip_property_escape() bool {
	if parser.pos >= parser.pattern.len {
		return false
	}
	if parser.pattern[parser.pos] == `{` {
		parser.pos++
		for parser.pos < parser.pattern.len && parser.pattern[parser.pos] != `}` {
			parser.pos++
		}
		if parser.pos >= parser.pattern.len {
			return false
		}
		parser.pos++
	} else {
		parser.pos++
	}
	return true
}

fn (mut parser AstAnalysisParser) skip_class() bool {
	if parser.pos < parser.pattern.len && parser.pattern[parser.pos] == `^` {
		parser.pos++
	}
	for parser.pos < parser.pattern.len {
		ch := parser.pattern[parser.pos]
		if ch == `]` {
			parser.pos++
			return true
		}
		if ch == `\\` {
			parser.pos++
			if !parser.skip_escape_tail() {
				return false
			}
		} else if ch == `[` {
			parser.pos++
			if !parser.skip_class() {
				return false
			}
		} else {
			parser.pos++
		}
	}
	return false
}

fn (mut parser AstAnalysisParser) skip_group() bool {
	parser.pos++
	if !parser.parse_until(`)`, false) {
		return false
	}
	if parser.pos >= parser.pattern.len || parser.pattern[parser.pos] != `)` {
		return false
	}
	parser.pos++
	return true
}

fn (mut parser AstAnalysisParser) skip_n(n int) bool {
	if parser.pos + n > parser.pattern.len {
		return false
	}
	parser.pos += n
	return true
}

fn (mut parser AstAnalysisParser) add_literal_byte(byte u8) {
	parser.analysis.any_literal = true
	if byte >= `A` && byte <= `Z` {
		parser.analysis.any_uppercase = true
	}
}

fn (mut parser AstAnalysisParser) add_literal_codepoint(code u32) {
	parser.analysis.any_literal = true
	if is_uppercase_codepoint(code) {
		parser.analysis.any_uppercase = true
	}
}

fn is_regex_meta_literal(ch u8, in_class bool) bool {
	if in_class {
		return ch == `[` || ch == `]` || ch == `-` || ch == `&` || ch == `~`
	}
	return ch == `.` || ch == `+` || ch == `*` || ch == `?` || ch == `(` || ch == `)` || ch == `|` || ch == `[` || ch == `]` || ch == `{` || ch == `}` || ch == `^` || ch == `$`
}

fn is_hex_digit(ch u8) bool {
	return (ch >= `0` && ch <= `9`) || (ch >= `a` && ch <= `f`) || (ch >= `A` && ch <= `F`)
}

fn parse_hex_u32(hex string) ?u32 {
	mut value := u32(0)
	for ch in hex.bytes() {
		value *= 16
		if ch >= `0` && ch <= `9` {
			value += u32(ch - `0`)
		} else if ch >= `a` && ch <= `f` {
			value += u32(ch - `a` + 10)
		} else if ch >= `A` && ch <= `F` {
			value += u32(ch - `A` + 10)
		} else {
			return none
		}
	}
	return value
}

fn is_uppercase_codepoint(code u32) bool {
	if code >= u32(`A`) && code <= u32(`Z`) {
		return true
	}
	if code >= u32(0x41) && code <= u32(0x5a) {
		return true
	}
	return false
}
