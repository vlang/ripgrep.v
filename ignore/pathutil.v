module ignore

import os

fn normalize_path(path string) string {
	if path == '' {
		return ''
	}
	return os.norm_path(path)
}

fn strip_prefix(path string, prefix string) string {
	npath := normalize_path(path)
	nprefix := normalize_path(prefix)
	if nprefix == '' {
		return npath
	}
	if npath == nprefix {
		return ''
	}
	prefix_with_sep := nprefix + os.path_separator.str()
	if npath.starts_with(prefix_with_sep) {
		return npath[prefix_with_sep.len..]
	}
	return npath
}

fn file_name(path string) string {
	return os.file_name(path)
}

fn is_hidden(path string) bool {
	if path == '' {
		return false
	}
	for part in normalize_path(path).split(os.path_separator.str()) {
		if part.len > 1 && part.starts_with('.') && part != '.' && part != '..' {
			return true
		}
	}
	return false
}

fn path_components(path string) []string {
	if path == '' {
		return []string{}
	}
	return normalize_path(path).split(os.path_separator.str())
}

fn matches_basename_or_segment(pattern string, path string, is_dir bool) bool {
	pat := pattern.trim_space()
	if pat == '' {
		return false
	}
	mut target := strip_prefix(path, '')
	if pat.ends_with('/') && !is_dir {
		return false
	}
	if pat.ends_with('/') {
		target = target.trim_right('/')
	}
	base := file_name(target)
	raw_pat := pat.trim_right('/')
	if raw_pat.contains(os.path_separator.str()) {
		return target == raw_pat || target.ends_with(os.path_separator.str() + raw_pat)
	}
	if base == raw_pat {
		return true
	}
	for part in path_components(target) {
		if part == raw_pat {
			return true
		}
	}
	return false
}

fn glob_match(pattern string, path string, is_dir bool) bool {
	pat := pattern.trim_space()
	if pat == '' {
		return false
	}
	if !pat.contains('*') {
		return matches_basename_or_segment(pat, path, is_dir)
	}
	mut candidate := strip_prefix(path, '')
	if pat.ends_with('/') && !is_dir {
		return false
	}
	if pat.ends_with('/') {
		candidate = candidate.trim_right('/')
	}
	needle := pat.trim_right('/')
	if needle == '*' {
		return true
	}
	parts := needle.split('*')
	mut idx := 0
	if !needle.starts_with('*') {
		first := parts[0]
		if !candidate.starts_with(first) {
			base := file_name(candidate)
			if !base.starts_with(first) {
				return false
			}
			candidate = base
		}
		idx = first.len
	}
	for i, part in parts {
		if part == '' {
			continue
		}
		pos := candidate[idx..].index(part) or { return false }
		idx += pos + part.len
		if i == parts.len - 1 && !needle.ends_with('*') && !candidate.ends_with(part) {
			return false
		}
	}
	return true
}

fn ancestor_dirs(path string) []string {
	mut dirs := []string{}
	mut current := normalize_path(path)
	for current != '' {
		parent := os.dir(current)
		if parent == '' || parent == current {
			break
		}
		dirs << parent.to_owned()
		current = parent
	}
	dirs.reverse_in_place()
	return dirs
}
