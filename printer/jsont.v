module printer

import encoding.utf8

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

pub struct Message {
pub:
	kind    MessageKind
	begin   Begin
	end     End
	match_  MatchMessage
	context Context
}

pub fn Message.begin(msg Begin) Message {
	return Message{
		kind:  .begin
		begin: msg
	}
}

pub fn Message.end(msg End) Message {
	return Message{
		kind: .end
		end:  msg
	}
}

pub fn Message.match_(msg MatchMessage) Message {
	return Message{
		kind:   .match_
		match_: msg
	}
}

pub fn Message.context(msg Context) Message {
	return Message{
		kind:    .context
		context: msg
	}
}

pub fn (msg Message) to_json() string {
	return match msg.kind {
		.begin { '{"type":"begin","data":${msg.begin.to_json()}}' }
		.end { '{"type":"end","data":${msg.end.to_json()}}' }
		.match_ { '{"type":"match","data":${msg.match_.to_json()}}' }
		.context { '{"type":"context","data":${msg.context.to_json()}}' }
	}
}

pub struct Begin {
pub:
	path ?string
}

pub fn (msg Begin) to_json() string {
	return '{"path":${path_to_json(msg.path)}}'
}

pub struct End {
pub:
	path          ?string
	binary_offset ?u64
	stats         Stats
}

pub fn (msg End) to_json() string {
	binary := if offset := msg.binary_offset { offset.str() } else { 'null' }
	return '{"path":${path_to_json(msg.path)},"binary_offset":${binary},"stats":${stats_to_json(msg.stats)}}'
}

pub struct MatchMessage {
pub:
	path            ?string
	lines           []u8
	line_number     ?u64
	absolute_offset u64
	submatches      []SubMatch
}

pub fn (msg MatchMessage) to_json() string {
	line_number := if n := msg.line_number { n.str() } else { 'null' }
	return '{"path":${path_to_json(msg.path)},"lines":${data_from_bytes_json(msg.lines)},"line_number":${line_number},"absolute_offset":${msg.absolute_offset},"submatches":${submatches_to_json(msg.submatches)}}'
}

pub struct Context {
pub:
	path            ?string
	lines           []u8
	line_number     ?u64
	absolute_offset u64
	submatches      []SubMatch
}

pub fn (msg Context) to_json() string {
	line_number := if n := msg.line_number { n.str() } else { 'null' }
	return '{"path":${path_to_json(msg.path)},"lines":${data_from_bytes_json(msg.lines)},"line_number":${line_number},"absolute_offset":${msg.absolute_offset},"submatches":${submatches_to_json(msg.submatches)}}'
}

pub struct SubMatch {
pub:
	m           []u8
	replacement ?[]u8
	start       usize
	end         usize
}

pub fn (sm SubMatch) to_json() string {
	mut fields := '"match":${data_from_bytes_json(sm.m)}'
	if replacement := sm.replacement {
		fields += ',"replacement":${data_from_bytes_json(replacement)}'
	}
	fields += ',"start":${sm.start},"end":${sm.end}'
	return '{${fields}}'
}

fn submatches_to_json(submatches []SubMatch) string {
	mut out := '['
	for i, sm in submatches {
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
	if bytes.len == 0 || utf8.validate(&bytes[0], bytes.len) {
		return '{"text":${json_quote(bytes.bytestr())}}'
	}
	return '{"bytes":${json_quote(base64_standard(bytes))}}'
}

fn path_to_json(path ?string) string {
	if p := path {
		return data_from_bytes_json(p.bytes())
	}
	return 'null'
}

fn stats_to_json(stats Stats) string {
	duration := stats.elapsed()
	secs := u64(duration.seconds())
	human := NiceDuration{
		duration: duration
	}.str()
	return '{"elapsed":{"secs":${secs},"nanos":0,"human":${json_quote(human)}},"searches":${stats.searches()},"searches_with_match":${stats.searches_with_match()},"bytes_searched":${stats.bytes_searched()},"bytes_printed":${stats.bytes_printed()},"matched_lines":${stats.matched_lines()},"matches":${stats.matches()}}'
}

fn json_quote(text string) string {
	mut out := '"'
	for byte in text.bytes() {
		match byte {
			`"` { out += '\\"' }
			`\\` { out += '\\\\' }
			`\n` { out += '\\n' }
			`\r` { out += '\\r' }
			`\t` { out += '\\t' }
			else {
				if byte < 0x20 {
					out += '\\u00${hex_digit(byte >> 4)}${hex_digit(byte & 0x0f)}'
				} else {
					out += byte.ascii_str()
				}
			}
		}
	}
	out += '"'
	return out
}

fn hex_digit(n u8) string {
	return if n < 10 { (u8(`0`) + n).ascii_str() } else { (u8(`a`) + n - 10).ascii_str() }
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
	alphabet := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	mut out := ''
	mut i := 0
	for i + 3 <= bytes.len {
		group24 := (usize(bytes[i]) << 16) | (usize(bytes[i + 1]) << 8) | usize(bytes[i + 2])
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
		group8 := usize(bytes[i])
		index1 := (group8 >> 2) & 0b111111
		index2 := (group8 << 4) & 0b111111
		out += alphabet[index1].ascii_str()
		out += alphabet[index2].ascii_str()
		out += '=='
	} else if remaining == 2 {
		group16 := (usize(bytes[i]) << 8) | usize(bytes[i + 1])
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
