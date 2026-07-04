module ignore

import encoding.utf8

/*
The types module provides a way of associating globs on file names to file
types.

This can be used to match specific types of files. For example, among
the default file types provided, the Rust file type is defined to be `*.rs`
with name `rust`. Similarly, the C file type is defined to be `*.{c,h}` with
name `c`.

Note that the set of default types may change over time.
*/

type FileTypeDefRef[^a] = &^a FileTypeDef

/// Glob represents a single glob in a set of file type definitions.
///
/// There may be more than one glob for a particular file type.
///
/// This is used to report information about the highest precedent glob
/// that matched.
///
/// Note that not all matches necessarily correspond to a specific glob.
/// For example, if there are one or more selections and a file path doesn't
/// match any of those selections, then the file path is considered to be
/// ignored.
///
/// The lifetime `^a` refers to the lifetime of the underlying file type
/// definition, which corresponds to the lifetime of the file type matcher.
pub struct TypesGlob[^a] implements IClone {
	kind TypesGlobInner
	def  ?FileTypeDefRef[^a]
}

enum TypesGlobInner {
	unmatched_ignore
	matched
}

fn TypesGlob.unmatched[^a]() TypesGlob[^a] {
	return TypesGlob[^a]{
		kind: .unmatched_ignore
	}
}

fn TypesGlob.matched[^a](def FileTypeDefRef[^a]) TypesGlob[^a] {
	return TypesGlob[^a]{
		kind: .matched
		def:  def
	}
}

/// Return the file type definition that matched, if one exists. A file type
/// definition always exists when a specific definition matches a file
/// path.
pub fn (g TypesGlob[^a]) file_type_def[^a]() ?FileTypeDefRef[^a] {
	return g.def
}

/// A single file type definition.
///
/// File type definitions can be retrieved in aggregate from a file type
/// matcher. File type definitions are also reported when its responsible
/// for a match.
pub struct FileTypeDef implements IClone {
	name  string
	globs []string
}

/// Return the name of this file type.
pub fn (def &^a FileTypeDef) name[^a]() &^a string {
	return &def.name
}

/// Return the globs used to recognize this file type.
pub fn (def &^a FileTypeDef) globs[^a]() &^a []string {
	return &def.globs
}

/// Types is a file type matcher.
pub struct Types implements IClone {
	// All of the file type definitions, sorted lexicographically by name.
	defs []FileTypeDef
	// All of the selections made by the user.
	selections []SelectionDef
	// Whether there is at least one Selection::Select in our selections.
	// When this is true, a Match::None is converted to Match::Ignore.
	has_selected bool
}

enum SelectionKind {
	select
	negate
}

struct SelectionSpec implements IClone {
	kind  SelectionKind
	name  string
}

fn (sel SelectionSpec) is_negated() bool {
	return sel.kind == .negate
}

struct SelectionDef implements IClone {
	kind  SelectionKind
	name  string
	inner FileTypeDef
}

fn (sel SelectionDef) is_negated() bool {
	return sel.kind == .negate
}

fn (sel &^a SelectionDef) name_ref[^a]() &^a string {
	return &sel.name
}

fn (sel &^a SelectionDef) inner_ref[^a]() &^a FileTypeDef {
	return &sel.inner
}

fn FileTypeDef.new(name string) FileTypeDef {
	return FileTypeDef{
		name:  name.to_owned()
		globs: []string{}
	}
}

fn selection_select(name string) SelectionSpec {
	return SelectionSpec{
		kind: .select
		name: name.to_owned()
	}
}

fn selection_negate(name string) SelectionSpec {
	return SelectionSpec{
		kind: .negate
		name: name.to_owned()
	}
}

fn selection_with_def(sel SelectionSpec, def FileTypeDef) SelectionDef {
	return SelectionDef{
		kind:  sel.kind
		name:  sel.name.clone()
		inner: def
	}
}

/// Creates a new file type matcher that never matches any path and
/// contains no file type definitions.
pub fn Types.empty() Types {
	return Types{
		defs:         []FileTypeDef{}
		selections:   []SelectionDef{}
		has_selected: false
	}
}

/// Returns true if and only if this matcher has zero selections.
pub fn (types Types) is_empty() bool {
	return types.selections.len == 0
}

/// Returns the number of selections used in this matcher.
pub fn (types Types) len() int {
	return types.selections.len
}

/// Return the set of current file type definitions.
///
/// Definitions and globs are sorted.
pub fn (types &^a Types) definitions[^a]() &^a []FileTypeDef {
	return &types.defs
}

/// Returns a match for the given path against this file type matcher.
///
/// The path is considered whitelisted if it matches a selected file type.
/// The path is considered ignored if it matches a negated file type.
/// If at least one file type is selected and `path` doesn't match, then
/// the path is also considered ignored.
pub fn (types &^a Types) matched[^a](path string, is_dir bool) Match[TypesGlob[^a]] {
	// File types don't apply to directories, and we can't do anything
	// if our glob set is empty.
	if is_dir || types.selections.len == 0 {
		return Match[TypesGlob[^a]]{}
	}
	// We only want to match against the file name, so extract it.
	// If one doesn't exist, then we can't match it.
	name := file_name(path)
	if name == '' {
		if types.has_selected {
			return Match[TypesGlob[^a]]{
				kind:      .ignore
				value:     TypesGlob[^a]{
					kind: .unmatched_ignore
				}
				has_value: true
			}
		}
		return Match[TypesGlob[^a]]{}
	}
	mut matched_sel := -1
	for isel, selection in types.selections {
		for glob in selection.inner.globs {
			if types_glob_matches(glob, name) {
				matched_sel = isel
			}
		}
	}
	// The highest precedent match is the last one.
	if matched_sel >= 0 {
		sel := &types.selections[matched_sel]
		glob := TypesGlob[^a]{
			kind: .matched
			def:  &sel.inner
		}
		return if sel.is_negated() {
			Match[TypesGlob[^a]]{
				kind:      .ignore
				value:     glob
				has_value: true
			}
		} else {
			Match[TypesGlob[^a]]{
				kind:      .whitelist
				value:     glob
				has_value: true
			}
		}
	}
	if types.has_selected {
		return Match[TypesGlob[^a]]{
			kind:      .ignore
			value:     TypesGlob[^a]{
				kind: .unmatched_ignore
			}
			has_value: true
		}
	}
	return Match[TypesGlob[^a]]{}
}

/// TypesBuilder builds a type matcher from a set of file type definitions and
/// a set of file type selections.
pub struct TypesBuilder {
mut:
	types      map[string]FileTypeDef
	selections []SelectionSpec
}

/// Create a new builder for a file type matcher.
///
/// The builder contains *no* type definitions to start with. A set
/// of default type definitions can be added with `add_defaults`, and
/// additional type definitions can be added with `select` and `negate`.
pub fn TypesBuilder.new() TypesBuilder {
	return TypesBuilder{
		types:      map[string]FileTypeDef{}
		selections: []SelectionSpec{}
	}
}

/// Build the current set of file type definitions *and* selections into
/// a file type matcher.
pub fn (builder TypesBuilder) build() (Types, bool, IgnoreError) {
	defs := builder.definitions()
	has_selected := builder.selections.any(!it.is_negated())
	mut selections := []SelectionDef{cap: builder.selections.len}
	for selection in builder.selections {
		name := selection.name
		def := builder.types[name] or {
			return Types.empty(), true, unrecognized_file_type_error(name)
		}
		selections << selection_with_def(selection, def.clone())
	}
	return Types{
		defs:         defs
		selections:   selections
		has_selected: has_selected
	}, false, IgnoreError{}
}

/// Return the set of current file type definitions.
///
/// Definitions and globs are sorted.
pub fn (builder TypesBuilder) definitions() []FileTypeDef {
	mut defs := []FileTypeDef{}
	for _, def in builder.types {
		mut cloned := def.clone()
		cloned.globs.sort(a < b)
		defs << cloned
	}
	defs.sort(a.name < b.name)
	return defs
}

/// Select the file type given by `name`.
///
/// If `name` is `all`, then all file types currently defined are selected.
pub fn (mut builder TypesBuilder) select(name string) &TypesBuilder {
	if name == 'all' {
		for existing_name, _ in builder.types {
			builder.selections << selection_select(existing_name)
		}
	} else {
		builder.selections << selection_select(name)
	}
	return builder
}

/// Ignore the file type given by `name`.
///
/// If `name` is `all`, then all file types currently defined are negated.
pub fn (mut builder TypesBuilder) negate(name string) &TypesBuilder {
	if name == 'all' {
		for existing_name, _ in builder.types {
			builder.selections << selection_negate(existing_name)
		}
	} else {
		builder.selections << selection_negate(name)
	}
	return builder
}

/// Clear any file type definitions for the type name given.
pub fn (mut builder TypesBuilder) clear(name string) &TypesBuilder {
	builder.types.delete(name)
	return builder
}

/// Add a new file type definition. `name` can be arbitrary and `pat`
/// should be a glob recognizing file paths belonging to the `name` type.
///
/// If `name` is `all` or otherwise contains any character that is not a
/// Unicode letter or number, then an error is returned.
pub fn (mut builder TypesBuilder) add(name string, glob string) (bool, IgnoreError) {
	if !is_valid_file_type_name(name) {
		return true, invalid_definition_error()
	}
	mut def := builder.types[name] or { FileTypeDef.new(name) }
	for expanded in expand_file_type_glob(glob) {
		def.globs << expanded.to_owned()
	}
	builder.types[name] = def
	return false, IgnoreError{}
}

/// Add a new file type definition specified in string form. There are two
/// valid formats:
/// 1. `{name}:{glob}`.  This defines a 'root' definition that associates the
///     given name with the given glob.
/// 2. `{name}:include:{comma-separated list of already defined names}.
///     This defines an 'include' definition that associates the given name
///     with the definitions of the given existing types.
/// Names may not include any characters that are not
/// Unicode letters or numbers.
pub fn (mut builder TypesBuilder) add_def(def string) (bool, IgnoreError) {
	parts := def.split(':')
	match parts.len {
		2 {
			name := parts[0]
			glob := parts[1]
			if name == '' || glob == '' {
				return true, invalid_definition_error()
			}
			return builder.add(name, glob)
		}
		3 {
			name := parts[0]
			types_string := parts[2]
			if name == '' || parts[1] != 'include' || types_string == '' {
				return true, invalid_definition_error()
			}
			type_names := types_string.split(',')
			if type_names.any(it !in builder.types) {
				return true, invalid_definition_error()
			}
			for type_name in type_names {
				globs := builder.types[type_name] or { continue }
				for glob in globs.globs {
					has_err, err := builder.add(name, glob)
					if has_err {
						return true, err
					}
				}
			}
			return false, IgnoreError{}
		}
		else {
			return true, invalid_definition_error()
		}
	}
}

/// Add a set of default file type definitions.
pub fn (mut builder TypesBuilder) add_defaults() &TypesBuilder {
	for def in default_types() {
		for name in def.names {
				for glob in def.globs {
					has_err, err := builder.add(name, glob)
					if has_err {
						panic(ignore_error_str(err))
					}
				}
			}
	}
	return builder
}

fn is_valid_file_type_name(name string) bool {
	if name == 'all' {
		return false
	}
	for ch in name.runes() {
		if !utf8.is_letter(ch) && !utf8.is_number(ch) {
			return false
		}
	}
	return true
}

fn types_glob_matches(glob string, name string) bool {
	return gitignore_glob_match_runes(glob.runes(), 0, name.runes(), 0)
}

// V-specific helper to expand glob alternations because the port does not use
// `globset::GlobBuilder`.
fn expand_file_type_glob(glob string) []string {
	mut expanded := expand_file_type_glob_rec(glob)
	expanded.sort(a < b)
	return expanded
}

fn expand_file_type_glob_rec(glob string) []string {
	open := find_glob_brace_open(glob)
	if open < 0 {
		return [glob.to_owned()]
	}
	close := find_glob_brace_close(glob, open)
	if close < 0 {
		return [glob.to_owned()]
	}
	prefix := glob[..open]
	suffix := glob[close + 1..]
	inner := glob[open + 1..close]
	parts := split_glob_brace_parts(inner)
	if parts.len == 0 {
		return [glob.to_owned()]
	}
	mut expanded := []string{}
	for i := 0; i < parts.len; i++ {
		part := parts[i].clone()
		for item in expand_file_type_glob_rec(prefix + part + suffix) {
			expanded << item
		}
	}
	return expanded
}

fn find_glob_brace_open(glob string) int {
	mut escaped := false
	for i := 0; i < glob.len; i++ {
		ch := glob[i]
		if escaped {
			escaped = false
			continue
		}
		if ch == `\\` {
			escaped = true
			continue
		}
		if ch == `{` {
			return i
		}
	}
	return -1
}

fn find_glob_brace_close(glob string, open int) int {
	mut escaped := false
	mut depth := 0
	for i := open; i < glob.len; i++ {
		ch := glob[i]
		if escaped {
			escaped = false
			continue
		}
		if ch == `\\` {
			escaped = true
			continue
		}
		if ch == `{` {
			depth++
			continue
		}
		if ch == `}` {
			depth--
			if depth == 0 {
				return i
			}
		}
	}
	return -1
}

fn split_glob_brace_parts(glob string) []string {
	mut parts := []string{}
	mut start := 0
	mut escaped := false
	mut depth := 0
	for i := 0; i < glob.len; i++ {
		ch := glob[i]
		if escaped {
			escaped = false
			continue
		}
		if ch == `\\` {
			escaped = true
			continue
		}
		if ch == `{` {
			depth++
			continue
		}
		if ch == `}` {
			depth--
			continue
		}
		if ch == `,` && depth == 0 {
			parts << glob[start..i].to_owned()
			start = i + 1
		}
	}
	parts << glob[start..].to_owned()
	return parts
}
