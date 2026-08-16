module main

import ignore
import os
import sync.stdatomic

enum DirEntryKind {
	walkdir
	ignore
}

struct DirEntry implements IClone {
	kind          DirEntryKind
	walkdir_path  string
	ignore_entry ignore.DirEntry
}

fn DirEntry.walkdir(path string) DirEntry {
	return DirEntry{
		kind:         .walkdir
		walkdir_path: path.to_owned()
	}
}

fn DirEntry.ignore(entry ignore.DirEntry) DirEntry {
	return DirEntry{
		kind:         .ignore
		ignore_entry: entry
	}
}

fn (entry &^a DirEntry) path[^a]() &^a string {
	return match entry.kind {
		.walkdir { &entry.walkdir_path }
		.ignore { entry.ignore_entry.path() }
	}
}

fn stdout_writer(entries chan DirEntry) bool {
	for {
		entry := <-entries or { break }
		println(*entry.path())
	}
	return true
}

fn walkdir_paths(root string) ![]string {
	mut paths := []string{}
	mut pending := [root.to_owned()]
	for pending.len > 0 {
		path := pending.pop()
		paths << path.clone()
		if !os.is_dir(path.clone()) || os.is_link(path.clone()) {
			continue
		}
		children := os.ls(path.clone())!
		for i := children.len - 1; i >= 0; i-- {
			pending << os.join_path(path.clone(), children[i].clone())
		}
	}
	return paths
}

fn walk_parallel_stream_runner(walk ignore.WalkParallel, events chan ignore.WalkParallelStreamResult, stop &stdatomic.AtomicVal[bool]) bool {
	walk.stream(events, stop)
	return true
}

fn main() {
	if os.args.len < 2 {
		panic('missing path')
	}
	mut path := os.args[1].clone()
	mut parallel := false
	mut simple := false
	if path == 'parallel' {
		if os.args.len < 3 {
			panic('missing path')
		}
		path = os.args[2].clone()
		parallel = true
	} else if path == 'walkdir' {
		if os.args.len < 3 {
			panic('missing path')
		}
		path = os.args[2].clone()
		simple = true
	}

	mut entries := chan DirEntry{cap: 100}
	stdout_thread := spawn stdout_writer(entries)
	if parallel {
		mut builder := ignore.WalkBuilder.new(path)
		builder.threads(6)
		stop := stdatomic.new_atomic(false)
		events := chan ignore.WalkParallelStreamResult{cap: 100}
		stream_thread := spawn walk_parallel_stream_runner(builder.build_parallel(), events,
			stop)
		for {
			event := <-events
			if event.done {
				break
			}
			if event.result.is_error {
				panic(event.result.err.msg())
			}
			entries <- DirEntry.ignore(event.result.entry.clone())
		}
		stream_thread.wait()
		unsafe { free(stop) }
	} else if simple {
		paths := walkdir_paths(path) or { panic(err) }
		for entry_path in paths {
			entries <- DirEntry.walkdir(entry_path)
		}
	} else {
		mut walker := ignore.WalkBuilder.new(path.clone()).build()
		for {
			result := walker.next() or { break }
			if result.is_error {
				panic(result.err.msg())
			}
			entries <- DirEntry.ignore(result.entry.clone())
		}
	}
	entries.close()
	stdout_thread.wait()
}
