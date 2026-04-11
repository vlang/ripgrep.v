module ignore

pub struct Types {}

pub fn (t Types) matched(path string, is_dir bool) Match {
	_ = path
	_ = is_dir
	return no_match()
}
