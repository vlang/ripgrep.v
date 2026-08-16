module globset

/// Serialize a glob as a JSON string.
///
/// V-specific: Rust implements serde's `Serialize` trait for `Glob`. V does
/// not have serde traits, so this exposes the equivalent operation directly.
pub fn (g &Glob) to_json() string {
	return json_quote(*g.glob())
}

/// Deserialize a glob from a JSON string.
///
/// V-specific counterpart to Rust's serde `Deserialize` implementation.
pub fn Glob.from_json(input string) !Glob {
	mut parser := JsonGlobParser.new(input)
	value := parser.parse_string()!
	parser.finish()!
	return Glob.new(value)
}

/// Deserialize a glob from a JSON string.
pub fn glob_from_json(input string) !Glob {
	return Glob.from_json(input)
}

/// Deserialize a glob set from a JSON array of glob strings.
///
/// V-specific counterpart to Rust's serde `Deserialize` implementation for
/// `GlobSet`.
pub fn GlobSet.from_json(input string) !GlobSet {
	mut parser := JsonGlobParser.new(input)
	mut builder := GlobSetBuilder.new()
	parser.skip_ws()
	parser.expect(`[`)!
	parser.skip_ws()
	if parser.consume(`]`) {
		parser.finish()!
		return builder.build()
	}
	for {
		glob := parser.parse_string()!
		builder.add(Glob.new(glob)!)
		parser.skip_ws()
		if parser.consume(`]`) {
			break
		}
		parser.expect(`,`)!
	}
	parser.finish()!
	return builder.build()
}

/// Deserialize a map of strings to glob patterns from a JSON object.
///
/// This is a small helper used by translated tests for the serde behavior.
pub fn glob_map_from_json(input string) !map[string]Glob {
	mut parser := JsonGlobParser.new(input)
	mut out := map[string]Glob{}
	parser.skip_ws()
	parser.expect(`{`)!
	parser.skip_ws()
	if parser.consume(`}`) {
		parser.finish()!
		return out
	}
	for {
		key := parser.parse_string()!
		parser.skip_ws()
		parser.expect(`:`)!
		value := parser.parse_string()!
		out[key] = Glob.new(value)!
		parser.skip_ws()
		if parser.consume(`}`) {
			break
		}
		parser.expect(`,`)!
	}
	parser.finish()!
	return out
}

struct JsonGlobParser {
	input string
mut:
	pos int
}

fn JsonGlobParser.new(input string) JsonGlobParser {
	return JsonGlobParser{
		input: input.to_owned()
	}
}

fn (mut parser JsonGlobParser) finish() ! {
	parser.skip_ws()
	if parser.pos != parser.input.len {
		return error('unexpected trailing JSON input')
	}
}

fn (mut parser JsonGlobParser) skip_ws() {
	for parser.pos < parser.input.len {
		match parser.input[parser.pos] {
			` `, `\n`, `\r`, `\t` {
				parser.pos++
			}
			else {
				return
			}
		}
	}
}

fn (mut parser JsonGlobParser) consume(ch u8) bool {
	parser.skip_ws()
	if parser.pos < parser.input.len && parser.input[parser.pos] == ch {
		parser.pos++
		return true
	}
	return false
}

fn (mut parser JsonGlobParser) expect(ch u8) ! {
	parser.skip_ws()
	if parser.pos >= parser.input.len || parser.input[parser.pos] != ch {
		return error('expected JSON byte ${ch.ascii_str()}')
	}
	parser.pos++
}

fn (mut parser JsonGlobParser) parse_string() !string {
	parser.skip_ws()
	if parser.pos >= parser.input.len || parser.input[parser.pos] != `"` {
		return error('expected JSON string')
	}
	parser.pos++
	mut bytes := []u8{}
	for parser.pos < parser.input.len {
		ch := parser.input[parser.pos]
		parser.pos++
		if ch == `"` {
			return bytes.bytestr()
		}
		if ch != `\\` {
			bytes << ch
			continue
		}
		if parser.pos >= parser.input.len {
			return error('unterminated JSON escape')
		}
		esc := parser.input[parser.pos]
		parser.pos++
		match esc {
			`"`, `\\`, `/` {
				bytes << esc
			}
			`b` {
				bytes << u8(0x08)
			}
			`f` {
				bytes << u8(0x0c)
			}
			`n` {
				bytes << `\n`
			}
			`r` {
				bytes << `\r`
			}
			`t` {
				bytes << `\t`
			}
			`u` {
				parser.parse_json_unicode_escape(mut bytes)!
			}
			else {
				return error('invalid JSON escape')
			}
		}
	}
	return error('unterminated JSON string')
}

fn (mut parser JsonGlobParser) parse_json_unicode_escape(mut bytes []u8) ! {
	code := parser.parse_hex4()!
	if code < 0x80 {
		bytes << u8(code)
	} else if code < 0x800 {
		bytes << u8(0xc0 | (code >> 6))
		bytes << u8(0x80 | (code & 0x3f))
	} else {
		bytes << u8(0xe0 | (code >> 12))
		bytes << u8(0x80 | ((code >> 6) & 0x3f))
		bytes << u8(0x80 | (code & 0x3f))
	}
}

fn (mut parser JsonGlobParser) parse_hex4() !u32 {
	if parser.pos + 4 > parser.input.len {
		return error('short JSON unicode escape')
	}
	mut value := u32(0)
	for _ in 0 .. 4 {
		ch := parser.input[parser.pos]
		parser.pos++
		value *= 16
		if ch >= `0` && ch <= `9` {
			value += u32(ch - `0`)
		} else if ch >= `a` && ch <= `f` {
			value += u32(ch - `a` + 10)
		} else if ch >= `A` && ch <= `F` {
			value += u32(ch - `A` + 10)
		} else {
			return error('invalid JSON unicode escape')
		}
	}
	return value
}

fn json_quote(s string) string {
	mut out := []u8{cap: s.len + 2}
	out << `"`
	for ch in s.bytes() {
		match ch {
			`"` {
				out << `\\`
				out << `"`
			}
			`\\` {
				out << `\\`
				out << `\\`
			}
			`\n` {
				out << `\\`
				out << `n`
			}
			`\r` {
				out << `\\`
				out << `r`
			}
			`\t` {
				out << `\\`
				out << `t`
			}
			else {
				if ch < 0x20 {
					hex := '0123456789abcdef'
					out << `\\`
					out << `u`
					out << `0`
					out << `0`
					out << hex[int(ch >> 4)]
					out << hex[int(ch & 0x0f)]
				} else {
					out << ch
				}
			}
		}
	}
	out << `"`
	return out.bytestr()
}
