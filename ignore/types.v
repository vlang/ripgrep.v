module ignore

import encoding.utf8
import globset

/*
The types module provides a way of associating globs on file names to file
types.

This can be used to match specific types of files. For example, among
the default file types provided, the Rust file type is defined to be `*.rs`
with name `rust`. Similarly, the C file type is defined to be `*.{c,h}` with
name `c`.

Note that the set of default types may change over time.

# Example

This shows how to create and use a simple file type matcher using the default
file types defined in this crate.

```v
mut builder := TypesBuilder.new()
builder.add_defaults()
builder.select('rust')
matcher_, has_err, _ := builder.build()
assert !has_err

assert matcher_.matched('foo.rs', false).is_whitelist()
assert matcher_.matched('foo.c', false).is_ignore()
```

# Example: negation

This is like the previous example, but shows how negating a file type works.
That is, this will let us match file paths that *don't* correspond to a
particular file type.

```v
mut builder := TypesBuilder.new()
builder.add_defaults()
builder.negate('c')
matcher_, has_err, _ := builder.build()
assert !has_err

assert matcher_.matched('foo.rs', false).is_none()
assert matcher_.matched('foo.c', false).is_ignore()
```

# Example: custom file type definitions

This shows how to extend this library default file type definitions with
your own.

```v
mut builder := TypesBuilder.new()
builder.add_defaults()
builder.add('foo', '*.foo')
// Another way of adding a file type definition.
// This is useful when accepting input from an end user.
builder.add_def('bar:*.bar')
// Note: we only select `foo`, not `bar`.
builder.select('foo')
matcher_, has_err, _ := builder.build()
assert !has_err

assert matcher_.matched('x.foo', false).is_whitelist()
// This is ignored because we only selected the `foo` file type.
assert matcher_.matched('x.bar', false).is_ignore()
```

We can also add file type definitions based on other definitions.

```v
mut builder := TypesBuilder.new()
builder.add_defaults()
builder.add('foo', '*.foo')
builder.add_def('bar:include:foo,cpp')
builder.select('bar')
matcher_, has_err, _ := builder.build()
assert !has_err

assert matcher_.matched('x.foo', false).is_whitelist()
assert matcher_.matched('y.cpp', false).is_whitelist()
```
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
///
/// V-specific type name: Rust uses `Glob`, but that name is already used by
/// the translated gitignore matcher in this module.
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
pub fn (g &TypesGlob[^a]) file_type_def[^a]() ?FileTypeDefRef[^a] {
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
	/// All of the file type definitions, sorted lexicographically by name.
	defs []FileTypeDef
	/// All of the selections made by the user.
	selections []SelectionDef
	/// Whether there is at least one Selection::Select in our selections.
	/// When this is true, a Match::None is converted to Match::Ignore.
	has_selected bool
	/// A mapping from glob index in the set to two indices. The first is an
	/// index into `selections` and the second is an index into the
	/// corresponding file type definition's list of globs.
	glob_to_selection []GlobSelectionIndex
	/// The set of all glob selections, used for actual matching.
	set globset.GlobSet
}

// V-specific representation of Rust's `(usize, usize)` mapping entry.
struct GlobSelectionIndex implements IClone {
	selection usize
	glob      usize
}

enum SelectionKind {
	select
	negate
}

struct SelectionSpec implements IClone {
	kind  SelectionKind
	name  string
}

fn (sel &SelectionSpec) is_negated() bool {
	return sel.kind == .negate
}

struct SelectionDef implements IClone {
	kind  SelectionKind
	name  string
	inner FileTypeDef
}

fn (sel &SelectionDef) is_negated() bool {
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
		name:  sel.name
		inner: def
	}
}

/// Creates a new file type matcher that never matches any path and
/// contains no file type definitions.
pub fn Types.empty() Types {
	return Types{
		defs:              []FileTypeDef{}
		selections:        []SelectionDef{}
		has_selected:      false
		glob_to_selection: []GlobSelectionIndex{}
		set:               globset.GlobSet.empty()
	}
}

/// Returns true if and only if this matcher has zero selections.
pub fn (types &Types) is_empty() bool {
	return types.selections.len == 0
}

/// Returns the number of selections used in this matcher.
pub fn (types &Types) len() usize {
	return usize(types.selections.len)
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
	if is_dir || types.set.is_empty() {
		return Match[TypesGlob[^a]]{}
	}
	// We only want to match against the file name, so extract it.
	// If one doesn't exist, then we can't match it.
	name := file_name(path)
	if name == '' {
		if types.has_selected {
			return Match[TypesGlob[^a]]{
				kind:      .ignore
				value:     TypesGlob.unmatched()
				has_value: true
			}
		}
		return Match[TypesGlob[^a]]{}
	}
	// Temporary storage for globs that match. Rust amortizes this allocation
	// with `regex_automata::Pool`; V has no corresponding reusable pool.
	matches := types.set.matches(name)
	// The highest precedent match is the last one.
	if matches.len > 0 {
		i := matches[matches.len - 1]
		mapping := types.glob_to_selection[int(i)]
		sel := &types.selections[int(mapping.selection)]
		glob := TypesGlob.matched(sel.inner_ref())
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
			value:     TypesGlob.unmatched()
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
pub fn (builder &TypesBuilder) build() (Types, bool, IgnoreError) {
	defs := builder.definitions()
	has_selected := builder.selections.any(!it.is_negated())
	mut selections := []SelectionDef{cap: builder.selections.len}
	mut glob_to_selection := []GlobSelectionIndex{}
	mut build_set := globset.GlobSetBuilder.new()
	for isel, selection in builder.selections {
		name := selection.name
		def := builder.types[name] or {
			return Types.empty(), true, unrecognized_file_type_error(name)
		}
		for iglob, glob in def.globs {
			mut glob_builder := globset.GlobBuilder.new(&glob)
			glob_builder.literal_separator(true)
			parsed := glob_builder.build() or {
				glob_err := err as globset.GlobError
				return Types.empty(), true, glob_error(glob, (*glob_err.kind()).str())
			}
			build_set.add(parsed)
			glob_to_selection << GlobSelectionIndex{
				selection: usize(isel)
				glob:      usize(iglob)
			}
		}
		selections << selection_with_def(selection.clone(), def.clone())
	}
	set := build_set.build() or { return Types.empty(), true, glob_error('', err.msg()) }
	return Types{
		defs:              defs
		selections:        selections
		has_selected:      has_selected
		glob_to_selection: glob_to_selection
		set:               set
	}, false, IgnoreError{}
}

/// Return the set of current file type definitions.
///
/// Definitions and globs are sorted.
pub fn (builder &TypesBuilder) definitions() []FileTypeDef {
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
	def.globs << glob.to_owned()
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
