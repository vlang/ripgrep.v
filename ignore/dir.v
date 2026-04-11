module ignore

import os

struct IgnoreOptions implements IClone {
mut:
	hidden                  bool = true
	ignore                  bool = true
	parents                 bool = true
	git_global              bool = true
	git_ignore              bool = true
	git_exclude             bool = true
	ignore_case_insensitive bool
	require_git             bool
}

struct IgnoreLayer implements IClone {
mut:
	path               string
	absolute_parent    bool
	has_git            bool
	custom_ignore      Gitignore
	ignore_matcher     Gitignore
	git_ignore_matcher Gitignore
	git_exclude_matcher Gitignore
}

pub struct Ignore implements IClone {
pub mut:
	layers                     []IgnoreLayer
	overrides                  Override
	types                      Types
	explicit_ignores           []Gitignore
	custom_ignore_filenames    []string
	global_gitignore           Gitignore
	global_gitignores_relative_to string
	opts                       IgnoreOptions
}

pub fn (ig Ignore) path() string {
	if ig.layers.len == 0 {
		return ''
	}
	return ig.layers[ig.layers.len - 1].path
}

pub fn (ig Ignore) is_root() bool {
	return ig.layers.len == 0
}

pub fn (ig Ignore) is_absolute_parent() bool {
	if ig.layers.len == 0 {
		return false
	}
	return ig.layers[ig.layers.len - 1].absolute_parent
}

pub fn (ig Ignore) parent() (bool, Ignore) {
	if ig.layers.len == 0 {
		return false, ig
	}
	mut cloned := ig
	cloned.layers = cloned.layers[..cloned.layers.len - 1].clone()
	return true, cloned
}

pub fn (ig Ignore) add_parents(path string) (Ignore, bool, IgnoreError) {
	if !ig.opts.parents && !ig.opts.git_ignore && !ig.opts.git_exclude && !ig.opts.git_global {
		return ig, false, IgnoreError{}
	}
	real := os.real_path(path)
	if real == '' {
		return ig, false, IgnoreError{}
	}
	mut errs := PartialErrorBuilder{}
	mut current := ig
	for parent in ancestor_dirs(real) {
		mut next, has_err, err := current.add_child(parent)
		if next.layers.len > 0 {
			next.layers[next.layers.len - 1].absolute_parent = true
		}
		errs.maybe_push(has_err, err)
		current = next
	}
	has_err, err := errs.into_error_option()
	return current, has_err, err
}

pub fn (ig Ignore) add_child(dir string) (Ignore, bool, IgnoreError) {
	layer, has_err, err := ig.build_layer(dir)
	mut cloned := ig
	cloned.layers << layer
	return cloned, has_err, err
}

fn (ig Ignore) build_layer(dir string) (IgnoreLayer, bool, IgnoreError) {
	mut errs := PartialErrorBuilder{}
	mut layer := IgnoreLayer{
		path:                normalize_path(dir).to_owned()
		absolute_parent:     false
		has_git:             os.is_dir(os.join_path(dir, '.git')) || os.is_dir(os.join_path(dir, '.jj'))
		custom_ignore:       Gitignore.empty()
		ignore_matcher:      Gitignore.empty()
		git_ignore_matcher:  Gitignore.empty()
		git_exclude_matcher: Gitignore.empty()
	}
	if ig.opts.ignore {
		mut builder := GitignoreBuilder.new(dir)
		has_err, err := builder.add(os.join_path(dir, '.ignore'))
		errs.maybe_push_ignore_io(has_err, err)
		_, matcher, _ := builder.build()
		layer.ignore_matcher = matcher
	}
	if ig.opts.git_ignore {
		mut builder := GitignoreBuilder.new(dir)
		has_err, err := builder.add(os.join_path(dir, '.gitignore'))
		errs.maybe_push_ignore_io(has_err, err)
		_, matcher, _ := builder.build()
		layer.git_ignore_matcher = matcher
	}
	if ig.opts.git_exclude {
		mut builder := GitignoreBuilder.new(dir)
		has_err, err := builder.add(os.join_path(dir, '.git/info/exclude'))
		errs.maybe_push_ignore_io(has_err, err)
		_, matcher, _ := builder.build()
		layer.git_exclude_matcher = matcher
	}
	if ig.custom_ignore_filenames.len > 0 {
		mut builder := GitignoreBuilder.new(dir)
		for name in ig.custom_ignore_filenames {
			has_err, err := builder.add(os.join_path(dir, name))
			errs.maybe_push_ignore_io(has_err, err)
		}
		_, matcher, _ := builder.build()
		layer.custom_ignore = matcher
	}
	has_err, err := errs.into_error_option()
	return layer, has_err, err
}

pub fn (ig Ignore) matched_dir_entry(dent DirEntry) Match {
	path := dent.path()
	is_dir := dent.is_dir()
	override_match := ig.overrides.matched(path, is_dir)
	if !override_match.is_none() {
		return override_match
	}
	for i := ig.layers.len - 1; i >= 0; i-- {
		layer := ig.layers[i]
		for matcher in [layer.custom_ignore, layer.ignore_matcher, layer.git_ignore_matcher, layer.git_exclude_matcher] {
			matched := matcher.matched(path, is_dir)
			if !matched.is_none() {
				return matched
			}
		}
	}
	if !is_dir {
		type_match := ig.types.matched(path, false)
		if !type_match.is_none() {
			return type_match
		}
	}
	if ig.opts.hidden && is_hidden(path) {
		return ignore_match('hidden')
	}
	for matcher in ig.explicit_ignores {
		matched := matcher.matched(path, is_dir)
		if !matched.is_none() {
			return matched
		}
	}
	global_match := ig.global_gitignore.matched(path, is_dir)
	if !global_match.is_none() {
		return global_match
	}
	return no_match()
}

pub struct IgnoreBuilder implements IClone {
mut:
	opts                         IgnoreOptions
	overrides                    Override
	types                        Types
	explicit_ignores             []Gitignore
	custom_ignore_filenames      []string
	current_dir_value            string
}

pub fn IgnoreBuilder.new() IgnoreBuilder {
	return IgnoreBuilder{
		opts:                    IgnoreOptions{}
		explicit_ignores:        []Gitignore{}
		custom_ignore_filenames: []string{}
		current_dir_value:       ''.to_owned()
	}
}

pub fn (mut builder IgnoreBuilder) add_ignore(gi Gitignore) {
	builder.explicit_ignores << gi
}

pub fn (mut builder IgnoreBuilder) add_custom_ignore_filename(file_name string) {
	builder.custom_ignore_filenames << file_name.to_owned()
}

pub fn (mut builder IgnoreBuilder) overrides(overrides Override) {
	builder.overrides = overrides
}

pub fn (mut builder IgnoreBuilder) types(types Types) {
	builder.types = types
}

pub fn (mut builder IgnoreBuilder) hidden(yes bool) {
	builder.opts.hidden = yes
}

pub fn (mut builder IgnoreBuilder) parents(yes bool) {
	builder.opts.parents = yes
}

pub fn (mut builder IgnoreBuilder) ignore(yes bool) {
	builder.opts.ignore = yes
}

pub fn (mut builder IgnoreBuilder) git_global(yes bool) {
	builder.opts.git_global = yes
}

pub fn (mut builder IgnoreBuilder) git_ignore(yes bool) {
	builder.opts.git_ignore = yes
}

pub fn (mut builder IgnoreBuilder) git_exclude(yes bool) {
	builder.opts.git_exclude = yes
}

pub fn (mut builder IgnoreBuilder) require_git(yes bool) {
	builder.opts.require_git = yes
}

pub fn (mut builder IgnoreBuilder) ignore_case_insensitive(yes bool) {
	builder.opts.ignore_case_insensitive = yes
}

pub fn (mut builder IgnoreBuilder) current_dir(cwd string) {
	builder.current_dir_value = cwd.to_owned()
}

pub fn (builder IgnoreBuilder) build() Ignore {
	return builder.build_with_cwd(builder.current_dir_value)
}

pub fn (builder IgnoreBuilder) build_with_cwd(cwd string) Ignore {
	return Ignore{
		layers:                        []IgnoreLayer{}
		overrides:                     builder.overrides
		types:                         builder.types
		explicit_ignores:              builder.explicit_ignores.clone()
		custom_ignore_filenames:       builder.custom_ignore_filenames.clone()
		global_gitignore:              Gitignore.empty()
		global_gitignores_relative_to: cwd.to_owned()
		opts:                          builder.opts
	}
}
