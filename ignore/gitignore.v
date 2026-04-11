module ignore

import os

pub struct GitPattern {
pub:
	original     string
	actual       string
	is_whitelist bool
	is_only_dir  bool
}

pub struct Gitignore {
pub:
	root     string
	patterns []GitPattern
}

pub fn Gitignore.empty() Gitignore {
	return Gitignore{
		root:     ''.to_owned()
		patterns: []GitPattern{}
	}
}

pub fn (gi Gitignore) path() string {
	return gi.root
}

pub fn (gi Gitignore) is_empty() bool {
	return gi.patterns.len == 0
}

pub fn (gi Gitignore) len() int {
	return gi.patterns.len
}

pub fn (gi Gitignore) num_ignores() int {
	mut count := 0
	for pattern in gi.patterns {
		if !pattern.is_whitelist {
			count++
		}
	}
	return count
}

pub fn (gi Gitignore) num_whitelists() int {
	mut count := 0
	for pattern in gi.patterns {
		if pattern.is_whitelist {
			count++
		}
	}
	return count
}

pub fn (gi Gitignore) matched(path string, is_dir bool) Match {
	if gi.patterns.len == 0 {
		return no_match()
	}
	stripped := strip_prefix(path, gi.root)
	mut last := no_match()
	for pattern in gi.patterns {
		if pattern.is_only_dir && !is_dir {
			continue
		}
		if glob_match(pattern.actual, stripped, is_dir) {
			last = if pattern.is_whitelist {
				whitelist_match(pattern.original)
			} else {
				ignore_match(pattern.original)
			}
		}
	}
	return last
}

pub fn (gi Gitignore) matched_path_or_any_parents(path string, is_dir bool) Match {
	mut stripped := strip_prefix(path, gi.root)
	mut matched := gi.matched(path, is_dir)
	if !matched.is_none() {
		return matched
	}
	for stripped != '' {
		parent := os.dir(stripped)
		if parent == '' || parent == stripped {
			break
		}
		matched = gi.matched(os.join_path(gi.root, parent), true)
		if !matched.is_none() {
			return matched
		}
		stripped = parent
	}
	return no_match()
}

pub struct GitignoreBuilder {
	root string
mut:
	patterns []GitPattern
}

pub fn GitignoreBuilder.new(root string) GitignoreBuilder {
	return GitignoreBuilder{
		root:     normalize_path(root).to_owned()
		patterns: []GitPattern{}
	}
}

pub fn (mut builder GitignoreBuilder) add(path string) (bool, IgnoreError) {
	lines := os.read_lines(path) or {
		return true, io_error(err).with_path(path)
	}
	for line in lines {
		trimmed := line.trim_space()
		if trimmed == '' || trimmed.starts_with('#') {
			continue
		}
		is_whitelist := trimmed.starts_with('!')
		actual0 := if is_whitelist { trimmed[1..] } else { trimmed }
		actual := actual0.trim_space()
		if actual == '' {
			continue
		}
		builder.patterns << GitPattern{
			original:     trimmed.to_owned()
			actual:       actual.to_owned()
			is_whitelist: is_whitelist
			is_only_dir:  actual.ends_with('/')
		}
	}
	return false, IgnoreError{}
}

pub fn (builder GitignoreBuilder) build() (bool, Gitignore, IgnoreError) {
	return false, Gitignore{
		root:     builder.root.clone()
		patterns: builder.patterns.clone()
	}, IgnoreError{}
}

pub fn (builder GitignoreBuilder) build_global() (Gitignore, bool, IgnoreError) {
	return Gitignore.empty(), false, IgnoreError{}
}
