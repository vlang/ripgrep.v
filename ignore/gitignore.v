module ignore

import os

pub struct Glob implements IClone {
pub:
	from             ?string
	original         string
	actual           string
	is_whitelist     bool
	is_only_dir      bool
	is_anchored      bool
	case_insensitive bool
}

pub fn (g Glob) has_doublestar_prefix() bool {
	return g.actual.starts_with('**/') || g.actual == '**'
}

pub struct Gitignore implements IClone {
pub:
	root           string
	globs          []Glob
	num_ignores_   u64
	num_whitelists_ u64
}

pub fn Gitignore.new(gitignore_path string) (Gitignore, bool, IgnoreError) {
	parent := os.dir(gitignore_path)
	mut builder := GitignoreBuilder.new(if parent == '' { os.path_separator.str() } else { parent })
	mut errs := PartialErrorBuilder{}
	add_has_err, add_err := builder.add(gitignore_path)
	errs.maybe_push(add_has_err, add_err)
	gi, build_has_err, build_err := builder.build()
	errs.maybe_push(build_has_err, build_err)
	final_has_err, final_err := errs.into_error_option()
	return gi, final_has_err, final_err
}

pub fn Gitignore.empty() Gitignore {
	return Gitignore{
		root:            ''.to_owned()
		globs:           []Glob{}
		num_ignores_:    0
		num_whitelists_: 0
	}
}

pub fn (gi Gitignore) path() string {
	return gi.root
}

pub fn (gi Gitignore) is_empty() bool {
	return gi.globs.len == 0
}

pub fn (gi Gitignore) len() int {
	return gi.globs.len
}

pub fn (gi Gitignore) num_ignores() u64 {
	return gi.num_ignores_
}

pub fn (gi Gitignore) num_whitelists() u64 {
	return gi.num_whitelists_
}

pub fn (gi Gitignore) matched(path string, is_dir bool) Match {
	if gi.is_empty() {
		return no_match()
	}
	return gi.matched_stripped(gi.strip(path), is_dir)
}

pub fn (gi Gitignore) matched_path_or_any_parents(path string, is_dir bool) Match {
	if gi.is_empty() {
		return no_match()
	}
	mut stripped := gi.strip(path)
	mut matched := gi.matched_stripped(stripped, is_dir)
	if !matched.is_none() {
		return matched
	}
	for stripped != '' {
		parent := os.dir(stripped)
		if parent == '' || parent == stripped {
			break
		}
		matched = gi.matched_stripped(parent, true)
		if !matched.is_none() {
			return matched
		}
		stripped = parent
	}
	return no_match()
}

fn (gi Gitignore) matched_stripped(path string, is_dir bool) Match {
	if gi.is_empty() {
		return no_match()
	}
	mut last := no_match()
	for glob in gi.globs {
		if gitignore_glob_matches(glob, path, is_dir) {
			last = if glob.is_whitelist {
				whitelist_match(glob.original)
			} else {
				ignore_match(glob.original)
			}
		}
	}
	return last
}

fn (gi Gitignore) strip(path string) string {
	stripped := strip_prefix(path, gi.root)
	if stripped == '' {
		return ''
	}
	return stripped
}

pub struct GitignoreBuilder {
	root string
mut:
	globs             []Glob
	case_insensitive_ bool
	errs              PartialErrorBuilder
}

pub fn GitignoreBuilder.new(root string) GitignoreBuilder {
	return GitignoreBuilder{
		root:              normalize_path(root).to_owned()
		globs:             []Glob{}
		case_insensitive_: false
		errs:              PartialErrorBuilder{}
	}
}

pub fn (mut builder GitignoreBuilder) case_insensitive(yes bool) (bool, IgnoreError) {
	builder.case_insensitive_ = yes
	return false, IgnoreError{}
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
		mut actual := if is_whitelist { trimmed[1..] } else { trimmed }
		actual = actual.trim_space()
		if actual == '' {
			continue
		}
		if invalid_glob(actual) {
			builder.errs.push(glob_error(actual, 'unsupported glob syntax'))
			continue
		}
		is_only_dir := actual.ends_with('/')
		is_anchored := actual.starts_with('/')
		actual = actual.trim_right('/')
		if is_anchored {
			actual = actual[1..]
		}
		if actual == '' {
			continue
		}
		builder.globs << Glob{
			from:             path.to_owned()
			original:         trimmed.to_owned()
			actual:           if builder.case_insensitive_ { actual.to_lower() } else { actual.to_owned() }
			is_whitelist:     is_whitelist
			is_only_dir:      is_only_dir
			is_anchored:      is_anchored
			case_insensitive: builder.case_insensitive_
		}
	}
	return false, IgnoreError{}
}

pub fn (mut builder GitignoreBuilder) build() (Gitignore, bool, IgnoreError) {
	mut num_ignores := u64(0)
	mut num_whitelists := u64(0)
	for glob in builder.globs {
		if glob.is_whitelist {
			num_whitelists++
		} else {
			num_ignores++
		}
	}
	has_err, err := builder.errs.into_error_option()
	return Gitignore{
		root:            builder.root.clone()
		globs:           builder.globs.clone()
		num_ignores_:    num_ignores
		num_whitelists_: num_whitelists
	}, has_err, err
}

pub fn (mut builder GitignoreBuilder) build_global() (Gitignore, bool, IgnoreError) {
	return Gitignore.empty(), false, IgnoreError{}
}

fn invalid_glob(glob string) bool {
	return glob.contains('{') || glob.contains('}')
}

fn gitignore_glob_matches(glob Glob, path string, is_dir bool) bool {
	if glob.is_only_dir && !is_dir {
		return false
	}
	mut candidate := normalize_path(path)
	mut actual := glob.actual
	if glob.case_insensitive {
		candidate = candidate.to_lower()
		actual = actual.to_lower()
	}
	if glob.is_anchored {
		return anchored_glob_match(actual, candidate, is_dir)
	}
	return glob_match(actual, candidate, is_dir)
}

fn anchored_glob_match(pattern string, path string, is_dir bool) bool {
	if pattern == '' {
		return false
	}
	mut candidate := normalize_path(path)
	if pattern.ends_with('/') && !is_dir {
		return false
	}
	if pattern.ends_with('/') {
		candidate = candidate.trim_right('/')
	}
	if !pattern.contains('*') {
		return candidate == pattern || candidate.starts_with(pattern + os.path_separator.str())
	}
	return glob_match(pattern, candidate, is_dir) && (candidate.starts_with(pattern.all_before('*'))
		|| pattern.starts_with('*'))
}
