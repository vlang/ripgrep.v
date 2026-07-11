module main

import os
import searcher

fn main() {
	if os.args.len != 3 {
		eprintln('usage: encoding_differential_harness encoding input')
		exit(2)
	}
	input := os.read_bytes(os.args[2]) or {
		eprintln(err.msg())
		exit(2)
	}
	decoded := searcher.differential_decode(os.args[1], input) or {
		eprintln(err.msg())
		exit(2)
	}
	mut stdout := os.stdout()
	stdout.write(decoded) or {
		eprintln(err.msg())
		exit(2)
	}
}
