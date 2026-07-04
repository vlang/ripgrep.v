module grep

/*
ripgrep, as a library.

This library is intended to provide a high level facade to the crates that
make up ripgrep's core searching routines. However, there is no high level
documentation available yet guiding users on how to fit all of the pieces
together.

Every public API item in the constituent crates is documented, but examples
are sparse.

A cookbook and a guide are planned.

V-specific: Rust re-exports sub-crates from this facade crate. V modules are
imported directly, so this module preserves the crate documentation surface.
*/

pub const has_library_facade = true
