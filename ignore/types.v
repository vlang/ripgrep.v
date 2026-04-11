module ignore

pub struct Types implements IClone {}

pub fn (t Types) clone() Types {
	_ = t
	return Types{}
}

pub fn (t Types) matched(path string, is_dir bool) Match {
	_ = path
	_ = is_dir
	return no_match()
}
