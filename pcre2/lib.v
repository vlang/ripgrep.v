module pcre2

/*
An implementation of `grep-matcher`'s `Matcher` trait for
[PCRE2](https://www.pcre.org/).
*/

pub const version = 'unavailable'

pub fn is_jit_available() bool {
	return false
}
