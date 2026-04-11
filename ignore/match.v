module ignore

pub enum MatchKind {
	none
	ignore
	whitelist
}

pub struct Match implements IClone {
pub:
	kind   MatchKind = .none
	source string
}

pub fn no_match() Match {
	return Match{}
}

pub fn ignore_match(source string) Match {
	return Match{
		kind:   .ignore
		source: source.to_owned()
	}
}

pub fn whitelist_match(source string) Match {
	return Match{
		kind:   .whitelist
		source: source.to_owned()
	}
}

pub fn (m Match) is_ignore() bool {
	return m.kind == .ignore
}

pub fn (m Match) is_whitelist() bool {
	return m.kind == .whitelist
}

pub fn (m Match) is_none() bool {
	return m.kind == .none
}

pub fn (m Match) or(other Match) Match {
	if m.is_none() {
		return other
	}
	return m
}

pub fn (m Match) str() string {
	if m.source == '' {
		return m.kind.str()
	}
	return '${m.kind.str()}(${m.source})'
}
