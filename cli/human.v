module cli

import strconv

enum ParseSizeErrorKind {
	invalid_format
	invalid_int
	overflow
}

/// An error that occurs when parsing a human readable size description.
///
/// This error provides an end user friendly message describing why the
/// description couldn't be parsed and what the expected format is.
pub struct ParseSizeError implements IClone {
	original  string
	kind      ParseSizeErrorKind
	int_error string
}

fn parse_size_error_format(original string) ParseSizeError {
	return ParseSizeError{
		original: original.to_owned()
		kind:     .invalid_format
	}
}

fn parse_size_error_int(original string, err IError) ParseSizeError {
	return ParseSizeError{
		original:  original.to_owned()
		kind:      .invalid_int
		int_error: err.msg().to_owned()
	}
}

fn parse_size_error_overflow(original string) ParseSizeError {
	return ParseSizeError{
		original: original.to_owned()
		kind:     .overflow
	}
}

pub fn (err ParseSizeError) msg() string {
	return match err.kind {
		.invalid_format {
			"invalid format for size '${err.original}', which should be a non-empty sequence of digits followed by an optional 'K', 'M' or 'G' suffix"
		}
		.invalid_int {
			"invalid integer found in size '${err.original}': ${err.int_error}"
		}
		.overflow {
			"size too big in '${err.original}'"
		}
	}
}

pub fn (err ParseSizeError) code() int {
	return 0
}

pub fn (err ParseSizeError) str() string {
	return err.msg()
}

/// Parse a human readable size like `2M` into a corresponding number of bytes.
///
/// Supported size suffixes are `K` (for kilobyte), `M` (for megabyte) and `G`
/// (for gigabyte). If a size suffix is missing, then the size is interpreted
/// as bytes. If the size is too big to fit into a `u64`, then this returns an
/// error.
///
/// Additional suffixes may be added over time.
pub fn parse_human_readable_size(size string) !u64 {
	mut digits_end := 0
	for digits_end < size.len && size[digits_end].is_digit() {
		digits_end++
	}
	digits := size[..digits_end]
	if digits.len == 0 {
		return parse_size_error_format(size)
	}
	value := strconv.atou64(digits) or { return parse_size_error_int(size, err) }

	suffix := size[digits_end..]
	if suffix.len == 0 {
		return value
	}
	multiplier := match suffix {
		'K' { u64(1) << 10 }
		'M' { u64(1) << 20 }
		'G' { u64(1) << 30 }
		else { return parse_size_error_format(size) }
	}
	if value > max_u64 / multiplier {
		return parse_size_error_overflow(size)
	}
	return value * multiplier
}
