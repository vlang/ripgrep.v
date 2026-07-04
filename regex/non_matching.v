module regex

import matcher

/// Return a confirmed set of non-matching bytes from the given expression.
fn non_matching_bytes(expr &Hir) matcher.ByteSet {
	return expr.non_matching_bytes()
}

struct NonMatchingAnalysis {
	bytes               matcher.ByteSet
	has_haystack_anchor bool
}

struct NonMatchingState {
mut:
	unicode              bool
	dot_matches_new_line bool
}

fn analyze_non_matching_pattern(pattern string, config Config) NonMatchingAnalysis {
	mut set := matcher.ByteSet.full()
	mut has_anchor := false
	mut state := NonMatchingState{
		unicode:              config.unicode
		dot_matches_new_line: config.dot_matches_new_line
	}
	mut i := 0
	for i < pattern.len {
		byte := pattern[i]
		match byte {
			`[` {
				class_set, ok, next := parse_class_set(pattern, i + 1)
				if ok {
					remove_byte_class(mut set, class_set)
					i = next
					continue
				}
				set = matcher.ByteSet.empty()
				i++
			}
			`\\` {
				info := analyze_non_matching_escape(pattern, i)
				if info.has_haystack_anchor {
					has_anchor = true
				}
				if info.any_byte {
					set = matcher.ByteSet.empty()
				} else {
					remove_byte_class(mut set, info.bytes)
				}
				i = info.next
			}
			`.` {
				remove_dot_matching_bytes(mut set, state)
				i++
			}
			`^`, `$` {
				if config.multi_line || config.crlf {
					if config.crlf {
						set.remove(`\r`)
					}
					set.remove(`\n`)
				} else {
					has_anchor = true
					set.remove(`\n`)
				}
				i++
			}
			`(` {
				handled, next := analyze_group_prefix(pattern, i, mut state)
				if handled {
					i = next
				} else {
					i++
				}
			}
			`)`, `|`, `+`, `*`, `?`, `{`, `}` {
				i++
			}
			else {
				set.remove(byte)
				i++
			}
		}
	}
	return NonMatchingAnalysis{
		bytes:               set
		has_haystack_anchor: has_anchor
	}
}

struct NonMatchingEscapeAnalysis {
	bytes               []bool
	next                int
	any_byte            bool
	has_haystack_anchor bool
}

/// Remove any bytes from the given set that can occur in a matched produced by
/// the given expression.
fn analyze_non_matching_escape(pattern string, i int) NonMatchingEscapeAnalysis {
	if i + 1 >= pattern.len {
		return NonMatchingEscapeAnalysis{
			bytes: full_byte_class()
			next:  pattern.len
		}
	}
	next := pattern[i + 1]
	match next {
		`A`, `z` {
			mut set := empty_byte_class()
			set[int(`\n`)] = true
			return NonMatchingEscapeAnalysis{
				bytes:               set
				next:                i + 2
				has_haystack_anchor: true
			}
		}
		`b`, `B` {
			return NonMatchingEscapeAnalysis{
				bytes: empty_byte_class()
				next:  i + 2
			}
		}
		`d`, `D`, `s`, `S`, `w`, `W` {
			set, _, _, ok, next_i := parse_escape_class(pattern, i)
			return NonMatchingEscapeAnalysis{
				bytes:    set
				next:     next_i
				any_byte: !ok
			}
		}
		`p`, `P` {
			mut cursor := i + 2
			if cursor < pattern.len && pattern[cursor] == `{` {
				cursor++
				for cursor < pattern.len && pattern[cursor] != `}` {
					cursor++
				}
				if cursor < pattern.len {
					cursor++
				}
			} else if cursor < pattern.len {
				cursor++
			}
			return NonMatchingEscapeAnalysis{
				bytes:    full_byte_class()
				next:     cursor
				any_byte: true
			}
		}
		else {
			has_byte, byte, next_i := parse_escape_byte(pattern, i)
			if !has_byte {
				return NonMatchingEscapeAnalysis{
					bytes: empty_byte_class()
					next:  next_i
				}
			}
			mut set := empty_byte_class()
			set[int(byte)] = true
			return NonMatchingEscapeAnalysis{
				bytes: set
				next:  next_i
			}
		}
	}
}

fn analyze_group_prefix(pattern string, i int, mut state NonMatchingState) (bool, int) {
	if i + 2 >= pattern.len || pattern[i + 1] != `?` {
		return false, i
	}
	mut cursor := i + 2
	mut negate := false
	for cursor < pattern.len {
		match pattern[cursor] {
			`:` {
				return true, cursor + 1
			}
			`)` {
				return true, cursor + 1
			}
			`-` {
				negate = true
			}
			`s` {
				state.dot_matches_new_line = !negate
			}
			`u` {
				state.unicode = !negate
			}
			`i`, `m`, `R`, `U`, `x` {}
			else {
				return false, i
			}
		}
		cursor++
	}
	return false, i
}

fn remove_dot_matching_bytes(mut set matcher.ByteSet, state NonMatchingState) {
	if state.unicode {
		for i in 0 .. 256 {
			byte := u8(i)
			if is_never_utf8_byte(byte) {
				continue
			}
			if !state.dot_matches_new_line && byte == `\n` {
				continue
			}
			set.remove(byte)
		}
		return
	}
	if state.dot_matches_new_line {
		set = matcher.ByteSet.empty()
		return
	}
	mut only_newline := matcher.ByteSet.empty()
	only_newline.add(`\n`)
	set = intersect_byte_sets(set, only_newline)
}

fn is_never_utf8_byte(byte u8) bool {
	return byte == u8(0xc0) || byte == u8(0xc1) || byte >= u8(0xf5)
}

fn remove_byte_class(mut set matcher.ByteSet, class_set []bool) {
	for i, present in class_set {
		if present {
			set.remove(u8(i))
		}
	}
}
