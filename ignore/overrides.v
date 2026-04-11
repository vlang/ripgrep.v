module ignore

pub struct Override implements IClone {}

pub fn Override.empty() Override {
	return Override{}
}

pub fn (o Override) is_empty() bool {
	_ = o
	return true
}

pub fn (o Override) matched(path string, is_dir bool) Match {
	_ = path
	_ = is_dir
	return no_match()
}
