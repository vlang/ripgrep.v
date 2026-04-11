module ignore

pub struct Override {}

pub fn (o Override) matched(path string, is_dir bool) Match {
	_ = path
	_ = is_dir
	return no_match()
}
