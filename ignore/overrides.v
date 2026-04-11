module ignore

pub struct Override implements IClone {}

pub fn (o Override) matched(path string, is_dir bool) Match {
	_ = path
	_ = is_dir
	return no_match()
}
