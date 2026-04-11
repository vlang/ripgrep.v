module ignore

pub struct Types implements IClone {}

pub fn Types.empty() Types {
	return Types{}
}

pub fn (t Types) is_empty() bool {
	_ = t
	return true
}

pub fn (t Types) matched(path string, is_dir bool) Match {
	_ = path
	_ = is_dir
	return no_match()
}
