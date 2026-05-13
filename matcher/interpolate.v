module matcher

/// Interpolate capture references in `replacement` and write the interpolation
/// result to `dst`. References in `replacement` take the form of $N or $name,
/// where `N` is a capture group index and `name` is a capture group name. The
/// function provided, `name_to_index`, maps capture group names to indices.
///
/// The `append` function given is responsible for writing the replacement
/// to the `dst` buffer. That is, it is called with the capture group index
/// of a capture group reference and is expected to resolve the index to its
/// corresponding matched text. If no such match exists, then `append` should
/// not write anything to its given buffer.
pub fn interpolate(replacement []u8, append fn (usize, mut []u8), name_to_index fn (string) ?usize, mut dst []u8) {
	mut replacement_bytes := replacement.clone()
	for replacement_bytes.len > 0 {
		index := find_byte(replacement_bytes, `$`) or { break }
		dst << replacement_bytes[..index]
		replacement_bytes = replacement_bytes[index..].clone()
		if replacement_bytes.len > 1 && replacement_bytes[1] == `$` {
			dst << [u8(`$`)]
			replacement_bytes = replacement_bytes[2..].clone()
			continue
		}
		cap_ref := find_cap_ref(replacement_bytes) or {
			dst << [u8(`$`)]
			replacement_bytes = replacement_bytes[1..].clone()
			continue
		}
		replacement_bytes = replacement_bytes[cap_ref.end..].clone()
		match cap_ref.kind {
			.number {
				append(cap_ref.number, mut dst)
		}
		.named {
			if cap_index := name_to_index(cap_ref.name) {
				append(cap_index, mut dst)
			}
		}
	}
	}
	dst << replacement_bytes
}

/// `CaptureRef` represents a reference to a capture group inside some text.
/// The reference is either a capture group name or a number.
///
/// It is also tagged with the position in the text immediately proceeding the
/// capture reference.
struct CaptureRef {
	kind   CaptureRefKind
	name   string
	number usize
	end    usize
}

/// A reference to a capture group in some text.
///
/// e.g., `$2`, `$foo`, `${foo}`.
enum CaptureRefKind {
	named
	number
}

fn CaptureRef.named(name string, end usize) CaptureRef {
	return CaptureRef{
		kind: .named
		name: name.clone()
		end:  end
	}
}

fn CaptureRef.numbered(number usize, end usize) CaptureRef {
	return CaptureRef{
		kind:   .number
		number: number
		end:    end
	}
}

/// Parses a possible reference to a capture group name in the given text,
/// starting at the beginning of `replacement`.
///
/// If no such valid reference could be found, none is returned.
fn find_cap_ref(replacement []u8) ?CaptureRef {
	mut i := usize(0)
	if replacement.len <= 1 || replacement[0] != `$` {
		return none
	}
	mut brace := false
	i++
	if replacement[i] == `{` {
		brace = true
		i++
	}
	mut cap_end := i
	for cap_end < replacement.len && is_valid_cap_letter(replacement[cap_end]) {
		cap_end++
	}
	if cap_end == i {
		return none
	}
	cap := replacement[i..cap_end].bytestr()
	if brace {
		if cap_end >= replacement.len || replacement[cap_end] != `}` {
			return none
		}
		cap_end++
	}
	if number := parse_capture_number(cap) {
		return CaptureRef.numbered(number, cap_end)
	}
	return CaptureRef.named(cap, cap_end)
}

/// Returns true if and only if the given byte is allowed in a capture name.
fn is_valid_cap_letter(byte u8) bool {
	return match byte {
		`0`...`9`, `a`...`z`, `A`...`Z`, `_` { true }
		else { false }
	}
}

fn find_byte(bytes []u8, needle u8) ?usize {
	for i, byte in bytes {
		if byte == needle {
			return usize(i)
		}
	}
	return none
}

fn parse_capture_number(cap string) ?usize {
	if cap.len == 0 {
		return none
	}
	mut number := usize(0)
	for byte in cap.bytes() {
		if byte < `0` || byte > `9` {
			return none
		}
		number = number * 10 + usize(byte - `0`)
	}
	return number
}
