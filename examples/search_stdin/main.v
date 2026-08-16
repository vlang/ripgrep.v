module main

import os
import regex
import searcher

fn main() {
	example() or {
		eprintln(err.msg())
		exit(1)
	}
}

fn example() ! {
	if os.args.len < 2 {
		return error('Usage: search-stdin <pattern>')
	}
	pattern := os.args[1]
	matcher_ := regex.RegexMatcher.new(pattern)!
	matcher_ref := regex.RegexMatcherRef.new(&matcher_)
	mut searcher_ := searcher.Searcher.new()
	mut stdin := os.stdin()
	mut sink := searcher.UTF8.new(fn (line_number u64, line string) !bool {
		print('${line_number}:${line}')
		return true
	})
	searcher_.search_reader(matcher_ref, mut stdin, sink)!
}
