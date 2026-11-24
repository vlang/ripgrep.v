module printer

import encoding.utf8
import strings
import time

// This module defines the types we use for JSON serialization. We specifically
// omit deserialization, partially because there isn't a clear use case for
// them at this time, but also because deserialization will complicate things.
// Namely, the types below are designed in a way that permits JSON
// serialization with little or no allocation. Allocation is often quite
// convenient for deserialization however, so these types would become a bit
// more complex.

pub enum MessageKind {
	begin
	end
	match_
	context
}

const empty_json_bytes = []u8{}

pub struct Message[^p, ^b] {
pub:
	kind    MessageKind
	begin   Begin[^p]
	end     End[^p]
	match_  MatchMessage[^p, ^b]
	context Context[^p, ^b]
}

pub fn Message.begin[^p, ^b](msg Begin[^p]) Message[^p, ^b] {
	return Message[^p, ^b]{
		kind:  .begin
		begin: msg
	}
}

pub fn Message.end[^p, ^b](msg End[^p]) Message[^p, ^b] {
	return Message[^p, ^b]{
		kind: .end
		end:  msg
	}
}

pub fn Message.match_[^p, ^b](msg MatchMessage[^p, ^b]) Message[^p, ^b] {
	return Message[^p, ^b]{
		kind:   .match_
		match_: msg
	}
}

pub fn Message.context[^p, ^b](msg Context[^p, ^b]) Message[^p, ^b] {
	return Message[^p, ^b]{
		kind:    .context
		context: msg
	}
}

pub fn (msg &Message[^p, ^b]) to_json[^p, ^b]() string {
	return match msg.kind {
		.begin { '{"type":"begin","data":${msg.begin.to_json()}}' }
		.end { '{"type":"end","data":${msg.end.to_json()}}' }
		.match_ { '{"type":"match","data":${msg.match_.to_json()}}' }
		.context { '{"type":"context","data":${msg.context.to_json()}}' }
	}
}

// V-specific: the translated JSON printer serializes its wire types directly,
// so pretty formatting is applied to the compact encoding here.
pub fn (msg &Message[^p, ^b]) to_json_pretty[^p, ^b]() string {
	compact := msg.to_json()
	mut out := []u8{cap: compact.len + 64}
	mut empty := []bool{}
	mut depth := 0
	mut in_string := false
	mut escaped := false
	for i, byte in compact.bytes() {
		if in_string {
			out << byte
			if escaped {
				escaped = false
			} else if byte == `\\` {
				escaped = true
			} else if byte == `"` {
				in_string = false
			}
			continue
		}
		match byte {
			`"` {
				in_string = true
				out << byte
			}
			`{`, `[` {
				out << byte
				closing := if byte == `{` { u8(`}`) } else { u8(`]`) }
				is_empty := i + 1 < compact.len && compact[i + 1] == closing
				empty << is_empty
				if !is_empty {
					depth++
					json_pretty_newline(mut out, depth)
				}
			}
			`}`, `]` {
				is_empty := empty[empty.len - 1]
				empty.delete(empty.len - 1)
				if !is_empty {
					depth--
					json_pretty_newline(mut out, depth)
				}
				out << byte
			}
			`,` {
				out << byte
				json_pretty_newline(mut out, depth)
			}
			`:` {
				out << byte
				out << u8(` `)
			}
			else {
				out << byte
			}
		}
	}
	return out.bytestr()
}

fn json_pretty_newline(mut out []u8, depth int) {
	out << u8(`\n`)
	for _ in 0 .. depth * 2 {
		out << u8(` `)
	}
}

pub struct Begin[^p] {
pub:
	path ?&^p string
}

pub fn (msg &Begin[^p]) to_json[^p]() string {
	return '{"path":${path_to_json(msg.path)}}'
}

pub struct End[^p] {
pub:
	path          ?&^p string
	binary_offset ?u64
	stats         Stats
}

pub fn (msg &End[^p]) to_json[^p]() string {
	binary := if offset := msg.binary_offset { offset.str() } else { 'null' }
	return '{"path":${path_to_json(msg.path)},"binary_offset":${binary},"stats":${stats_to_json(msg.stats)}}'
}

pub struct MatchMessage[^p, ^b] {
pub:
	path            ?&^p string
	lines           &^b []u8 = &empty_json_bytes
	line_number     ?u64
	absolute_offset u64
	submatches      []SubMatch[^b]
}

pub fn (msg &MatchMessage[^p, ^b]) to_json[^p, ^b]() string {
	line_number := if n := msg.line_number { n.str() } else { 'null' }
	return '{"path":${path_to_json(msg.path)},"lines":${data_from_buffer_json(msg.lines)},"line_number":${line_number},"absolute_offset":${msg.absolute_offset},"submatches":${submatches_to_json(&msg.submatches)}}'
}

pub struct Context[^p, ^b] {
pub:
	path            ?&^p string
	lines           &^b []u8 = &empty_json_bytes
	line_number     ?u64
	absolute_offset u64
	submatches      []SubMatch[^b]
}

pub fn (msg &Context[^p, ^b]) to_json[^p, ^b]() string {
	line_number := if n := msg.line_number { n.str() } else { 'null' }
	return '{"path":${path_to_json(msg.path)},"lines":${data_from_buffer_json(msg.lines)},"line_number":${line_number},"absolute_offset":${msg.absolute_offset},"submatches":${submatches_to_json(&msg.submatches)}}'
}

// JsonBytes keeps the byte range inline and borrows its backing storage.
pub struct JsonBytes[^b] {
	buffer &^b []u8
	start  uint
	end    uint
}

fn (bytes &JsonBytes[^b]) to_json[^b]() string {
	// The source buffer stays borrowed throughout serialization of the range.
	view := unsafe { (*bytes.buffer)[bytes.start..bytes.end] }
	return data_from_buffer_json(&view)
}

pub struct SubMatch[^b] {
pub:
	m           JsonBytes[^b]
	replacement ?JsonBytes[^b]
	start       uint
	end         uint
}

pub fn (sm &SubMatch[^b]) to_json[^b]() string {
	mut fields := '"match":${sm.m.to_json()}'
	if replacement := sm.replacement {
		fields += ',"replacement":${replacement.to_json()}'
	}
	fields += ',"start":${sm.start},"end":${sm.end}'
	return '{${fields}}'
}

fn submatches_to_json[^b](submatches &[]SubMatch[^b]) string {
	mut out := '['
	for i in 0 .. submatches.len {
		sm := &(*submatches)[i]
		if i > 0 {
			out += ','
		}
		out += sm.to_json()
	}
	out += ']'
	return out
}

/// Data represents things that look like strings, but may actually not be
/// valid UTF-8. To handle this, `Data` is serialized as an object with one
/// of two keys: `text` (for valid UTF-8) or `bytes` (for invalid UTF-8).
///
/// The happy path is valid UTF-8, which streams right through as-is, since
/// it is natively supported by JSON. When invalid UTF-8 is found, then it is
/// represented as arbitrary bytes and base64 encoded.
pub fn data_from_bytes_json(bytes []u8) string {
	return data_from_buffer_json(&bytes)
}

fn data_from_buffer_json(bytes &[]u8) string {
	if bytes.len == 0 {
		return '{"text":""}'
	}
	data := &(*bytes)[0]
	if utf8.validate(data, bytes.len) {
		return '{"text":${json_quote_buffer(data, bytes.len)}}'
	}
	return '{"bytes":${json_quote(encode_base64(bytes))}}'
}

fn path_to_json[^p](path ?&^p string) string {
	if p := path {
		if p.len == 0 || utf8.validate(p.str, p.len) {
			return '{"text":${json_quote_buffer(p.str, p.len)}}'
		}
		return data_from_bytes_json(p.bytes())
	}
	return 'null'
}

fn stats_to_json(stats Stats) string {
	duration := stats.elapsed()
	secs := u64(duration / time.second)
	nanos := u32(duration % time.second)
	human := NiceDuration{
		duration: duration
	}.str()
	return '{"elapsed":{"secs":${secs},"nanos":${nanos},"human":${json_quote(human)}},"searches":${stats.searches()},"searches_with_match":${stats.searches_with_match()},"bytes_searched":${stats.bytes_searched()},"bytes_printed":${stats.bytes_printed()},"matched_lines":${stats.matched_lines()},"matches":${stats.matches()}}'
}

fn json_quote(text string) string {
	return json_quote_buffer(text.str, text.len)
}

fn json_quote_buffer(bytes &u8, len int) string {
	mut out := strings.new_builder(len + 2)
	out.write_u8(`"`)
	for i in 0 .. len {
		// The caller keeps these len bytes alive throughout encoding.
		byte := unsafe { bytes[i] }
		match byte {
			`"` {
				out.write_string('\\"')
			}
			`\\` {
				out.write_string('\\\\')
			}
			`\b` {
				out.write_string('\\b')
			}
			`\f` {
				out.write_string('\\f')
			}
			`\n` {
				out.write_string('\\n')
			}
			`\r` {
				out.write_string('\\r')
			}
			`\t` {
				out.write_string('\\t')
			}
			else {
				if byte < 0x20 {
					out.write_string('\\u00')
					out.write_u8(hex_digit(byte >> 4))
					out.write_u8(hex_digit(byte & 0x0f))
				} else {
					out.write_u8(byte)
				}
			}
		}
	}
	out.write_u8(`"`)
	return out.str()
}

fn hex_digit(n u8) u8 {
	return if n < 10 { `0` + n } else { `a` + n - 10 }
}

/// Implements "standard" base64 encoding as described in RFC 3548[1].
///
/// We roll our own here instead of bringing in something heavier weight like
/// the `base64` crate. In particular, we really don't care about perf much
/// here, since this is only used for data or file paths that are not valid
/// UTF-8.
///
/// [1]: https://tools.ietf.org/html/rfc3548#section-3
pub fn base64_standard(bytes []u8) string {
	return encode_base64(&bytes)
}

fn encode_base64(bytes &[]u8) string {
	alphabet := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	mut out := ''
	mut i := 0
	for i + 3 <= bytes.len {
		group24 := (uint((*bytes)[i]) << 16) | (uint((*bytes)[i + 1]) << 8) | uint((*bytes)[i + 2])
		index1 := (group24 >> 18) & 0b111111
		index2 := (group24 >> 12) & 0b111111
		index3 := (group24 >> 6) & 0b111111
		index4 := group24 & 0b111111
		out += alphabet[index1].ascii_str()
		out += alphabet[index2].ascii_str()
		out += alphabet[index3].ascii_str()
		out += alphabet[index4].ascii_str()
		i += 3
	}
	remaining := bytes.len - i
	if remaining == 1 {
		group8 := uint((*bytes)[i])
		index1 := (group8 >> 2) & 0b111111
		index2 := (group8 << 4) & 0b111111
		out += alphabet[index1].ascii_str()
		out += alphabet[index2].ascii_str()
		out += '=='
	} else if remaining == 2 {
		group16 := (uint((*bytes)[i]) << 8) | uint((*bytes)[i + 1])
		index1 := (group16 >> 10) & 0b111111
		index2 := (group16 >> 4) & 0b111111
		index3 := (group16 << 2) & 0b111111
		out += alphabet[index1].ascii_str()
		out += alphabet[index2].ascii_str()
		out += alphabet[index3].ascii_str()
		out += '='
	}
	return out
}
