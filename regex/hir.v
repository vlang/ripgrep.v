module regex

import matcher

enum HirKind {
	raw
	empty
	look
	literal
	concat
	alternation
}

enum HirLook {
	start
	end
	start_lf
	end_lf
	start_crlf
	end_crlf
	word_start_half_ascii
	word_end_half_ascii
	word_start_half_unicode
	word_end_half_unicode
}

struct HirProperties implements IClone {
mut:
	non_matching_bytes     matcher.ByteSet
	has_haystack_anchor    bool
	is_alternation_literal bool
}

/// A translated regular expression HIR expression.
///
/// This is the local counterpart to `regex_syntax::hir::Hir` for the subset of
/// HIR operations currently needed by the translated matcher configuration.
pub struct Hir implements IClone {
	kind     HirKind
	pattern  string
	literal  string
	look     HirLook
	children []Hir
	props    HirProperties
}

fn Hir.from_pattern(pattern string, config Config) Hir {
	props := analyze_pattern(pattern, config)
	return Hir{
		kind:    .raw
		pattern: pattern.to_owned()
		props:   props
	}
}

fn Hir.from_fixed_literals(patterns []string) Hir {
	mut alts := []Hir{cap: patterns.len}
	for p in patterns {
		alts << Hir.literal(p)
	}
	return Hir.alternation(alts)
}

fn Hir.empty() Hir {
	return Hir{
		kind:  .empty
		props: HirProperties{
			non_matching_bytes: matcher.ByteSet.full()
		}
	}
}

fn Hir.look(look HirLook) Hir {
	mut set := matcher.ByteSet.full()
	match look {
		.start, .end, .start_lf, .end_lf {
			set.remove(`\n`)
		}
		.start_crlf, .end_crlf {
			set.remove(`\r`)
			set.remove(`\n`)
		}
		else {}
	}
	return Hir{
		kind: .look
		look: look
		props: HirProperties{
			non_matching_bytes:  set
			has_haystack_anchor: look == .start || look == .end
		}
	}
}

fn Hir.literal(literal string) Hir {
	mut set := matcher.ByteSet.full()
	for byte in literal.bytes() {
		set.remove(byte)
	}
	return Hir{
		kind:    .literal
		literal: literal.to_owned()
		props:   HirProperties{
			non_matching_bytes:     set
			is_alternation_literal: true
		}
	}
}

fn Hir.concat(children []Hir) Hir {
	if children.len == 0 {
		return Hir.empty()
	}
	return Hir{
		kind:     .concat
		children: clone_hir_children(children)
		props:    combine_hir_properties(children, false)
	}
}

fn Hir.alternation(children []Hir) Hir {
	if children.len == 0 {
		return Hir.empty()
	}
	return Hir{
		kind:     .alternation
		children: clone_hir_children(children)
		props:    combine_hir_properties(children, true)
	}
}

fn (hir Hir) clone() Hir {
	return Hir{
		kind:     hir.kind
		pattern:  hir.pattern.clone()
		literal:  hir.literal.clone()
		look:     hir.look
		children: clone_hir_children(hir.children)
		props:    hir.props.clone()
	}
}

fn (props HirProperties) clone() HirProperties {
	return HirProperties{
		non_matching_bytes:     clone_byte_set(props.non_matching_bytes)
		has_haystack_anchor:    props.has_haystack_anchor
		is_alternation_literal: props.is_alternation_literal
	}
}

fn clone_hir_children(children []Hir) []Hir {
	mut cloned := []Hir{cap: children.len}
	for child in children {
		cloned << child.clone()
	}
	return cloned
}

fn combine_hir_properties(children []Hir, alternation bool) HirProperties {
	mut set := matcher.ByteSet.full()
	mut has_anchor := false
	mut all_literals := children.len > 0
	for child in children {
		set = intersect_byte_sets(set, child.props.non_matching_bytes)
		has_anchor = has_anchor || child.props.has_haystack_anchor
		all_literals = all_literals && child.props.is_alternation_literal
	}
	return HirProperties{
		non_matching_bytes:     set
		has_haystack_anchor:    has_anchor
		is_alternation_literal: alternation && all_literals
	}
}

fn (hir &Hir) to_regex() string {
	return match hir.kind {
		.raw {
			hir.pattern
		}
		.empty {
			''
		}
		.look {
			hir.look.to_regex()
		}
		.literal {
			escape_regex(hir.literal)
		}
		.concat {
			mut out := []u8{}
			for child in hir.children {
				if child.kind == .alternation {
					out << '(?:'.bytes()
					out << child.to_regex().bytes()
					out << `)`
				} else {
					out << child.to_regex().bytes()
				}
			}
			out.bytestr()
		}
		.alternation {
			mut alts := []string{cap: hir.children.len}
			for child in hir.children {
				alts << child.to_regex()
			}
			alts.join('|')
		}
	}
}

fn (look HirLook) to_regex() string {
	return match look {
		.start { r'\A' }
		.end { r'\z' }
		.start_lf { r'(?m:^)' }
		.end_lf { r'(?m:$)' }
		.start_crlf { r'(?m:^)' }
		.end_crlf { r'\x0D?$' }
		.word_start_half_ascii { r'(?<![A-Za-z0-9_])' }
		.word_end_half_ascii { r'(?![A-Za-z0-9_])' }
		.word_start_half_unicode { r'(?<![A-Za-z0-9_])' }
		.word_end_half_unicode { r'(?![A-Za-z0-9_])' }
	}
}

fn (hir &Hir) non_matching_bytes() matcher.ByteSet {
	return clone_byte_set(hir.props.non_matching_bytes)
}

fn (hir &Hir) contains_haystack_anchor() bool {
	return hir.props.has_haystack_anchor
}

fn (hir &Hir) is_alternation_literal() bool {
	if hir.kind == .literal {
		return true
	}
	if hir.kind == .alternation {
		if hir.children.len == 0 {
			return false
		}
		for child in hir.children {
			if !child.is_alternation_literal() {
				return false
			}
		}
		return true
	}
	return hir.props.is_alternation_literal
}

fn (hir Hir) into_whole_line(config Config) Hir {
	return Hir.concat([
		Hir.look(line_anchor_start(config)),
		hir,
		Hir.look(line_anchor_end(config)),
	])
}

fn (hir Hir) into_word(config Config) Hir {
	start := if config.unicode {
		HirLook.word_start_half_unicode
	} else {
		HirLook.word_start_half_ascii
	}
	end := if config.unicode {
		HirLook.word_end_half_unicode
	} else {
		HirLook.word_end_half_ascii
	}
	return Hir.concat([Hir.look(start), hir, Hir.look(end)])
}

fn line_anchor_start(config Config) HirLook {
	if config.crlf {
		return .start_crlf
	}
	return .start_lf
}

fn line_anchor_end(config Config) HirLook {
	if config.crlf {
		return .end_crlf
	}
	return .end_lf
}

fn analyze_pattern(pattern string, config Config) HirProperties {
	analysis := analyze_non_matching_pattern(pattern, config)
	return HirProperties{
		non_matching_bytes:  analysis.bytes
		has_haystack_anchor: analysis.has_haystack_anchor
	}
}

fn clone_byte_set(set matcher.ByteSet) matcher.ByteSet {
	mut cloned := matcher.ByteSet.empty()
	for i in 0 .. 256 {
		byte := u8(i)
		if set.contains(byte) {
			cloned.add(byte)
		}
	}
	return cloned
}

fn intersect_byte_sets(left matcher.ByteSet, right matcher.ByteSet) matcher.ByteSet {
	mut out := matcher.ByteSet.empty()
	for i in 0 .. 256 {
		byte := u8(i)
		if left.contains(byte) && right.contains(byte) {
			out.add(byte)
		}
	}
	return out
}
