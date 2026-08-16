/*
This module benchmarks the glob implementation. For benchmarks on the ripgrep
tool itself, see the benchsuite directory.
*/
module main

import globset

const ext = 'some/a/bigger/path/to/the/crazy/needle.txt'
const ext_pat = '*.txt'

const short = 'some/needle.txt'
const short_pat = 'some/**/needle.txt'

const long = 'some/a/bigger/path/to/the/crazy/needle.txt'
const long_pat = 'some/**/needle.txt'

fn new_glob(pat string) globset.GlobMatcher {
	glob := globset.Glob.new(pat) or { panic(err) }
	return glob.compile_matcher()
}

fn new_reglob(pat string) globset.GlobMatcher {
	glob := globset.Glob.new(pat) or { panic(err) }
	return glob.compile_matcher()
}

fn new_reglob_many(pats []string) globset.GlobSet {
	mut builder := globset.GlobSetBuilder.new()
	for pat in pats {
		builder.add(globset.Glob.new(pat) or { panic(err) })
	}
	return builder.build() or { panic(err) }
}

fn ext_glob(iterations usize) {
	pat := new_glob(ext_pat)
	for _ in 0 .. iterations {
		assert pat.is_match(ext)
	}
}

fn ext_regex(iterations usize) {
	set := new_reglob(ext_pat)
	cand := globset.Candidate.new(&ext)
	for _ in 0 .. iterations {
		assert set.is_match_candidate(&cand)
	}
}

fn short_glob(iterations usize) {
	pat := new_glob(short_pat)
	for _ in 0 .. iterations {
		assert pat.is_match(short)
	}
}

fn short_regex(iterations usize) {
	set := new_reglob(short_pat)
	cand := globset.Candidate.new(&short)
	for _ in 0 .. iterations {
		assert set.is_match_candidate(&cand)
	}
}

fn long_glob(iterations usize) {
	pat := new_glob(long_pat)
	for _ in 0 .. iterations {
		assert pat.is_match(long)
	}
}

fn long_regex(iterations usize) {
	set := new_reglob(long_pat)
	cand := globset.Candidate.new(&long)
	for _ in 0 .. iterations {
		assert set.is_match_candidate(&cand)
	}
}

const many_short_globs = [
	// Taken from a random .gitignore on my system.
	'.*.swp',
	'tags',
	'target',
	'*.lock',
	'tmp',
	'*.csv',
	'*.fst',
	'*-got',
	'*.csv.idx',
	'words',
	'98m*',
	'dict',
	'test',
	'months',
]

const many_short_search = '98m-blah.csv.idx'

fn many_short_glob(iterations usize) {
	mut pats := []globset.GlobMatcher{}
	for pat in many_short_globs {
		pats << new_glob(pat)
	}
	for _ in 0 .. iterations {
		mut count := 0
		for pat in pats {
			if pat.is_match(many_short_search) {
				count++
			}
		}
		assert count == 2
	}
}

fn many_short_regex_set(iterations usize) {
	set := new_reglob_many(many_short_globs)
	for _ in 0 .. iterations {
		assert set.matches(many_short_search).len == 2
	}
}

fn main() {
	ext_glob(1)
	ext_regex(1)
	short_glob(1)
	short_regex(1)
	long_glob(1)
	long_regex(1)
	many_short_glob(1)
	many_short_regex_set(1)
}
