module main

import rg

// V-specific root entry point: build the translated ripgrep CLI when compiling
// the repository root.
fn main() {
	rg.main()
}
