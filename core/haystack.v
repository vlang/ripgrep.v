module core

import ignore
import os

/*
Defines a builder for haystacks.

A "haystack" represents something we want to search. It encapsulates the logic
for whether a haystack ought to be searched or not, separate from the standard
ignore rules and other filtering logic.

Effectively, a haystack wraps a directory entry and adds some light application
level logic around it.
*/

/// A builder for constructing things to search over.
pub struct HaystackBuilder implements IClone {
mut:
	strip_dot_prefix bool
}

/// Return a new haystack builder with a default configuration.
pub fn HaystackBuilder.new() HaystackBuilder {
	return HaystackBuilder{
		strip_dot_prefix: false
	}
}

/// Create a new haystack from a possibly missing directory entry.
///
/// If the directory entry isn't present, then the corresponding error is
/// logged if messages have been configured. Otherwise, if the directory
/// entry is deemed searchable, then it is returned as a haystack.
pub fn (builder HaystackBuilder) build_from_result(result ignore.WalkResult) ?Haystack {
	if result.is_error {
		err_message(result.err.msg())
		return none
	}
	return builder.build(result.entry)
}

/// Create a new haystack using this builder's configuration.
///
/// If a directory entry could not be created or should otherwise not be
/// searched, then this returns `None` after emitting any relevant log
/// messages.
fn (builder HaystackBuilder) build(dent ignore.DirEntry) ?Haystack {
	mut hay := Haystack.new(dent, builder.strip_dot_prefix)
	if err := hay.dent.error() {
		ignore_message(err.msg())
	}
	// If this entry was explicitly provided by an end user, then we always
	// want to search it.
	if hay.is_explicit() {
		return hay
	}
	// At this point, we only want to search something if it's explicitly a
	// file. This omits symlinks. (If ripgrep was configured to follow
	// symlinks, then they have already been followed by the directory
	// traversal.)
	if hay.is_file() {
		return hay
	}
	// We got nothing. Emit a debug message, but only if this isn't a
	// directory. Otherwise, emitting messages for directories is just
	// noisy.
	if !hay.is_dir() {
		debug_message('rg::haystack', '${*hay.path()}: ignored because it is not a file')
	}
	hay.free_path_cache()
	return none
}

/// When enabled, if the haystack's file path starts with `./` then it is
/// stripped.
///
/// This is useful when implicitly searching the current working directory.
pub fn (mut builder HaystackBuilder) strip_dot_prefix(yes bool) &HaystackBuilder {
	builder.strip_dot_prefix = yes
	return &builder
}

/// A haystack is a thing we want to search.
///
/// Generally, a haystack is either a file or stdin.
pub struct Haystack implements IClone {
mut:
	dent             ignore.DirEntry
	strip_dot_prefix bool
	// V-specific owned byte-string path cache so `path` can return a stable
	// borrow even when the `./` byte prefix is stripped.
	path_value string
}

fn Haystack.new(dent ignore.DirEntry, strip_dot_prefix bool) Haystack {
	return Haystack{
		path_value:       haystack_path_value(&dent, strip_dot_prefix)
		dent:             dent
		strip_dot_prefix: strip_dot_prefix
	}
}

fn haystack_path_value(dent &ignore.DirEntry, strip_dot_prefix bool) string {
	path := *dent.path()
	if strip_dot_prefix && path.starts_with('./') {
		return path[2..].to_owned()
	}
	return path.to_owned()
}

/// Return the file path corresponding to this haystack.
///
/// If this haystack corresponds to stdin, then a special `<stdin>` path
/// is returned instead.
pub fn (hay &^a Haystack) path[^a]() &^a string {
	return &hay.path_value
}

// V-specific: releases the path cache while leaving the borrowed walk entry
// owned by the caller's WalkResult.
pub fn (mut hay Haystack) free_path_cache() {
	// Assigning '' auto-drops (frees) the old owned path once under v3 ownership;
	// a manual `.free()` first would double-free.
	hay.path_value = ''
}

// V-specific: release a haystack that received ownership of a walk entry,
// as in the parallel search job queue.
pub fn (mut hay Haystack) free_owned() {
	hay.dent.free()
	hay.free_path_cache()
}

/// Returns true if and only if this entry corresponds to stdin.
pub fn (hay &Haystack) is_stdin() bool {
	return hay.dent.is_stdin()
}

/// Returns true if and only if this entry corresponds to a haystack to
/// search that was explicitly supplied by an end user.
///
/// Generally, this corresponds to either stdin or an explicit file path
/// argument. e.g., in `rg foo some-file ./some-dir/`, `some-file` is
/// an explicit haystack, but, e.g., `./some-dir/some-other-file` is not.
///
/// However, note that ripgrep does not see through shell globbing. e.g.,
/// in `rg foo ./some-dir/*`, `./some-dir/some-other-file` will be treated
/// as an explicit haystack.
pub fn (hay &Haystack) is_explicit() bool {
	// stdin is obvious. When an entry has a depth of 0, that means it
	// was explicitly provided to our directory iterator, which means it
	// was in turn explicitly provided by the end user. The !is_dir check
	// means that we want to search files even if their symlinks, again,
	// because they were explicitly provided. (And we never want to try
	// to search a directory.)
	return hay.is_stdin() || (hay.dent.depth() == 0 && !hay.is_dir())
}

/// Returns true if and only if this haystack points to a directory after
/// following symbolic links.
fn (hay &Haystack) is_dir() bool {
	ft := hay.dent.file_type() or { return false }
	if ft == .directory {
		return true
	}
	// If this is a symlink, then we want to follow it to determine
	// whether it's a directory or not.
	return hay.dent.path_is_symlink() && os.is_dir(*hay.dent.path())
}

/// Returns true if and only if this haystack points to a file.
fn (hay &Haystack) is_file() bool {
	ft := hay.dent.file_type() or { return false }
	return ft == .regular
}
