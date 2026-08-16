module globset

/// The final component of the path, if it is a normal file.
///
/// If the path terminates in `..`, or consists solely of a root of prefix,
/// file_name will return `none`.
fn file_name(path string) ?string {
	if path.len == 0 {
		return none
	}
	last_slash := path.last_index_u8(`/`)
	start := if last_slash < 0 { 0 } else { last_slash + 1 }
	// This is a borrowed view into `path`, just like Rust's `Path::file_name`.
	// Using `substr` here allocates one string for every glob candidate.
	got := unsafe { path.substr_unsafe(start, path.len) }
	if got == '..' {
		return none
	}
	return got
}

/// Return a file extension given a path's file name.
///
/// Note that this does NOT match the semantics of std::path::Path::extension.
/// Namely, the extension includes the `.` and matching is otherwise more
/// liberal. Specifically, the extension is:
///
/// * none, if the file name given is empty;
/// * none, if there is no embedded `.`;
/// * Otherwise, the portion of the file name starting with the final `.`.
///
/// e.g., A file name of `.rs` has an extension `.rs`.
///
/// N.B. This is done to make certain glob match optimizations easier. Namely,
/// a pattern like `*.rs` is obviously trying to match files with a `rs`
/// extension, but it also matches files like `.rs`, which doesn't have an
/// extension according to std::path::Path::extension.
fn file_name_ext(name string) ?string {
	if name.len == 0 {
		return none
	}
	last_dot_at := name.last_index_u8(`.`)
	if last_dot_at < 0 {
		return none
	}
	return unsafe { name.substr_unsafe(last_dot_at, name.len) }
}

/// Normalizes a path to use `/` as a separator everywhere, even on platforms
/// that recognize other characters as separators.
fn normalize_path(path string) string {
	$if windows {
		return path.replace('\\', '/')
	}
	return path
}
