module ignore

/// The result of a glob match.
///
/// The type parameter `T` typically refers to a type that provides more
/// information about a particular match. For example, it might identify
/// the specific gitignore file and the specific glob pattern that caused
/// the match.
pub enum MatchKind {
	none
	ignore
	whitelist
}

pub struct Match[T] {
	kind      MatchKind = .none
	value     T
	has_value bool
}

/// Returns true if the match result didn't match any globs.
pub fn (m Match[T]) is_none() bool {
	return m.kind == .none
}

/// Returns true if the match result implies the path should be ignored.
pub fn (m Match[T]) is_ignore() bool {
	return m.kind == .ignore
}

/// Returns true if the match result implies the path should be
/// whitelisted.
pub fn (m Match[T]) is_whitelist() bool {
	return m.kind == .whitelist
}

/// Inverts the match so that `Ignore` becomes `Whitelist` and
/// `Whitelist` becomes `Ignore`. A non-match remains the same.
pub fn (m Match[T]) invert[T]() Match[T] {
	match m.kind {
		.none {
			return Match[T]{}
		}
		.ignore {
			if m.has_value {
				return Match[T]{
					kind:      .whitelist
					value:     m.value
					has_value: true
				}
			}
		}
		.whitelist {
			if m.has_value {
				return Match[T]{
					kind:      .ignore
					value:     m.value
					has_value: true
				}
			}
		}
	}
	return Match[T]{}
}

/// Return the value inside this match if it exists.
pub fn (m Match[T]) inner[T]() ?T {
	if !m.has_value {
		return none
	}
	return m.value
}

/// Return the match if it is not none. Otherwise, return other.
pub fn (m Match[T]) or[T](other Match[T]) Match[T] {
	if m.is_none() {
		return other
	}
	return m
}

pub fn (m Match[T]) str[T]() string {
	return m.kind.str()
}
