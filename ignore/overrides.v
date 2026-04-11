module ignore

pub struct OverrideGlob[^a] {}

pub struct Override implements IClone {}

pub fn Override.empty() Override {
	return Override{}
}

pub fn (o Override) is_empty() bool {
	_ = o
	return true
}

pub fn (o &^a Override) matched[^a](path string, is_dir bool) Match[OverrideGlob[^a]] {
	_ = path
	_ = is_dir
	return Match[OverrideGlob[^a]]{}
}
