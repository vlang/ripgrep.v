module ignore

pub struct TypesGlob[^a] {}

pub struct Types implements IClone {}

pub fn Types.empty() Types {
	return Types{}
}

pub fn (t Types) is_empty() bool {
	_ = t
	return true
}

pub fn (t &^a Types) matched[^a](path string, is_dir bool) Match[TypesGlob[^a]] {
	_ = path
	_ = is_dir
	return Match[TypesGlob[^a]]{}
}
