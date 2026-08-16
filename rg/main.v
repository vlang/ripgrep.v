module rg

import cli
import core
import core.flags
import ignore
import printer
import sync
import sync.stdatomic
import time

const parallel_job_queue_capacity = 256

$if !windows {
	#include "@VMODROOT/rg/sigpipe.h"
}

/*!
The main entry point into ripgrep.
*/

// Since Rust no longer uses jemalloc by default, ripgrep will, by default,
// use the system allocator. On Linux, this would normally be glibc's
// allocator, which is pretty good. In particular, ripgrep does not have a
// particularly allocation heavy workload, so there really isn't much
// difference (for ripgrep's purposes) between glibc's allocator and jemalloc.
//
// However, when ripgrep is built with musl, this means ripgrep will use musl's
// allocator, which appears to be substantially worse. (musl's goal is not to
// have the fastest version of everything. Its goal is to be small and amenable
// to static compilation.) Even though ripgrep isn't particularly allocation
// heavy, musl's allocator appears to slow down ripgrep quite a bit. Therefore,
// when building with musl, we use jemalloc.
//
// We don't unconditionally use jemalloc because it can be nice to use the
// system's default allocator by default. Moreover, jemalloc seems to increase
// compilation times by a bit.
//
// Moreover, we only do this on 64-bit systems since jemalloc doesn't support
// i686.
//
// V-specific: this port does not install a Rust-style global allocator.

/// Then, as it was, then again it will be.
pub fn main() {
	ignore_sigpipe()
	code := run(flags.parse()) or {
		if cli.is_broken_pipe_error(err) {
			exit(0)
		}
		core.eprintln_locked(err.msg())
		exit(2)
	}
	exit(code)
}

fn ignore_sigpipe() {
	$if !windows {
		C.rg_ignore_sigpipe()
	}
}

$if !windows {
	fn C.rg_ignore_sigpipe()
}

/// The main entry point for ripgrep.
///
/// The given parse result determines ripgrep's behavior. The parse
/// result should be the result of parsing CLI arguments in a low level
/// representation, and then followed by an attempt to convert them into a
/// higher level representation. The higher level representation has some nicer
/// abstractions, for example, instead of representing the `-g/--glob` flag
/// as a `Vec<String>` (as in the low level representation), the globs are
/// converted into a single matcher.
fn run(result flags.ParseResult[flags.HiArgs]) !int {
	match result.kind {
		.err {
			return error(result.err)
		}
		.special {
			return special(result.special)
		}
		.ok {}
	}

	args := result.value
	mode := args.mode()
	matched := match mode.kind {
		.search {
			if !args.matches_possible() {
				false
			} else if args.threads() == 1 {
				search(&args, mode.search)!
			} else {
				search_parallel(&args, mode.search)!
			}
		}
		.files {
			if args.threads() == 1 {
				files(&args)!
			} else {
				files_parallel(&args)!
			}
		}
		.types {
			return types(&args)
		}
		.generate {
			return generate(mode.generate)
		}
	}

	if matched && (args.quiet() || !core.errored()) {
		return 0
	}
	if core.errored() {
		return 2
	}
	return 1
}

/// The top-level entry point for single-threaded search.
///
/// This recursively steps through the file list (current directory by default)
/// and searches each file sequentially.
fn search(args &flags.HiArgs, mode flags.SearchMode) !bool {
	if args.sort_requires_buffering() {
		return search_sorted(args, mode)
	}
	return search_stream(args, mode)
}

// V-specific: the Rust iterator remains streaming when no sort was requested.
fn search_stream(args &flags.HiArgs, mode flags.SearchMode) !bool {
	started_at := time.now()
	mut stats := args.stats()
	matcher_ := args.matcher()!
	searcher_ := args.searcher()!
	printer_ := args.printer_standard_stream(mode, args.stdout())
	mut searcher := args.search_worker_standard_stream(matcher_, searcher_, printer_)!
	mut visitor := SearchStreamVisitor{
		args:             args
		haystack_builder: args.haystack_builder()
		searcher:         searcher
		stats:            stats
	}
	defer {
		visitor.searcher.printer().get_mut().free()
		visitor.searcher.free()
	}
	mut walk := args.walk_builder()!.build()
	for {
		mut result := walk.next() or { break }
		state := visitor.visit(result)
		result.free()
		if state == .quit {
			break
		}
	}
	stats = visitor.stats
	if args.has_implicit_path() && !visitor.searched {
		eprint_nothing_searched()
	}
	if stats_value := stats {
		mut wtr := visitor.searcher.printer().get_mut()
		print_stats(mode, stats_value, started_at, mut wtr) or {}
	}
	// Rust flushes the buffered stdout writer when it is dropped and ignores
	// any error at that point, so the final flush error is ignored here too.
	visitor.searcher.printer().flush() or {}
	return visitor.matched
}

struct SearchStreamVisitor {
	args             &flags.HiArgs
	haystack_builder core.HaystackBuilder
mut:
	searcher core.SearchWorker[cli.StandardStream]
	stats    ?printer.Stats
	matched  bool
	searched bool
}

fn (mut visitor SearchStreamVisitor) visit(result ignore.WalkResult) ignore.WalkState {
	mut haystack := visitor.haystack_builder.build_from_result(result) or { return .continue_ }
	visitor.searched = true
	search_result := visitor.searcher.search(&haystack) or {
		if cli.is_broken_pipe_error(err) {
			haystack.free_path_cache()
			return .quit
		}
		core.err_message('${*haystack.path()}: ${err.msg()}')
		haystack.free_path_cache()
		return .continue_
	}
	visitor.matched = visitor.matched || search_result.has_match()
	if stats_value := visitor.stats {
		result_stats := search_result.stats() or { panic('stats enabled without search stats') }
		visitor.stats = stats_value + *result_stats
	}
	state := if visitor.matched && visitor.args.quit_after_match() {
		ignore.WalkState.quit
	} else {
		ignore.WalkState.continue_
	}
	haystack.free_path_cache()
	return state
}

// V-specific: Rust's sorting iterator buffers only when sorting was requested.
fn search_sorted(args &flags.HiArgs, mode flags.SearchMode) !bool {
	started_at := time.now()
	haystacks := collect_haystacks(args)!

	mut matched := false
	mut searched := false
	mut stats := args.stats()
	matcher_ := args.matcher()!
	searcher_ := args.searcher()!
	printer_ := args.printer_standard_stream(mode, args.stdout())
	mut searcher := args.search_worker_standard_stream(matcher_, searcher_, printer_)!
	defer {
		searcher.printer().get_mut().free()
		searcher.free()
	}
	for haystack in haystacks {
		searched = true
		search_result := searcher.search(&haystack) or {
			if cli.is_broken_pipe_error(err) {
				break
			}
			core.err_message('${*haystack.path()}: ${err.msg()}')
			continue
		}
		matched = matched || search_result.has_match()
		if stats_value := stats {
			result_stats := search_result.stats() or { panic('stats enabled without search stats') }
			stats = stats_value + *result_stats
		}
		if matched && args.quit_after_match() {
			break
		}
	}
	if args.has_implicit_path() && !searched {
		eprint_nothing_searched()
	}
	if stats_value := stats {
		mut wtr := searcher.printer().get_mut()
		print_stats(mode, stats_value, started_at, mut wtr) or {}
	}
	// Rust flushes the buffered stdout writer when it is dropped and ignores
	// any error at that point, so the final flush error is ignored here too.
	searcher.printer().flush() or {}
	return matched
}

/// The top-level entry point for multi-threaded search.
///
/// The parallelism is itself achieved by the recursive directory traversal.
/// All we need to do is feed it a worker for performing a search on each file.
///
/// Requesting a sorted output from ripgrep (such as with `--sort path`) will
/// automatically disable parallelism and hence sorting is not handled here.
fn search_parallel(args &flags.HiArgs, mode flags.SearchMode) !bool {
	started_at := time.now()
	bufwtr := args.buffer_writer()
	thread_count := parallel_worker_count(args.threads())
	walk := args.walk_builder()!.build_parallel()
	matcher_template := args.matcher()!
	mut workers := []core.SearchWorker[cli.Buffer]{cap: thread_count}
	for _ in 0 .. thread_count {
		matcher_ := matcher_template.clone()
		searcher_ := args.searcher()!
		printer_ := args.printer_buffer(mode, bufwtr.buffer())
		workers << args.search_worker_buffer(matcher_, searcher_, printer_)!
	}
	defer {
		for mut worker in workers {
			worker.printer().get_mut().free()
			worker.free()
		}
		unsafe { workers.free() }
	}
	stats := args.stats()
	mut shared_value := SearchParallelShared{
		output_lock:        sync.new_mutex()
		stats_lock:         sync.new_mutex()
		bufwtr:             bufwtr
		matched:            stdatomic.new_atomic(false)
		searched:           stdatomic.new_atomic(false)
		output_broken_pipe: stdatomic.new_atomic(false)
		stats:              stats or { printer.Stats.new() }
		has_stats:          stats != none
	}
	shared_state := &shared_value
	mut factory := SearchParallelVisitorFactory{
		workers:          &workers
		next_worker:      stdatomic.new_atomic(0)
		haystack_builder: args.haystack_builder()
		state:            shared_state
		quit_after_match: args.quit_after_match()
	}
	walk.run(mut factory)
	matched := shared_state.matched.load()
	if args.has_implicit_path() && !shared_state.searched.load() {
		eprint_nothing_searched()
	}
	if shared_state.has_stats {
		mut wtr := shared_state.bufwtr.buffer()
		print_stats(mode, shared_state.stats, started_at, mut wtr) or {}
		shared_state.bufwtr.print(&wtr) or {}
	}
	return matched
}

struct SearchParallelShared {
	output_lock &sync.Mutex
	stats_lock  &sync.Mutex
	matched             &stdatomic.AtomicVal[bool]
	searched            &stdatomic.AtomicVal[bool]
	output_broken_pipe  &stdatomic.AtomicVal[bool]
	has_stats bool
mut:
	bufwtr cli.BufferWriter
	stats  printer.Stats
}

struct SearchParallelVisitorFactory {
	workers          &[]core.SearchWorker[cli.Buffer]
	next_worker      &stdatomic.AtomicVal[int]
	haystack_builder core.HaystackBuilder
	state            &SearchParallelShared
	quit_after_match bool
}

fn (mut factory SearchParallelVisitorFactory) create() ignore.ParallelVisitor {
	index := factory.next_worker.add(1)
	return SearchParallelVisitor{
		worker:            unsafe { &factory.workers[index] }
		haystack_builder: factory.haystack_builder
		state:             factory.state
		quit_after_match: factory.quit_after_match
	}
}

struct SearchParallelVisitor {
	haystack_builder core.HaystackBuilder
	quit_after_match bool
mut:
	worker &core.SearchWorker[cli.Buffer]
	state  &SearchParallelShared
}

fn (mut visitor SearchParallelVisitor) visit(result ignore.WalkResult) ignore.WalkState {
	mut owned_result := result
	mut haystack := visitor.haystack_builder.build_from_result(result) or {
		owned_result.free()
		return .continue_
	}
	visitor.state.searched.store(true)
	visitor.worker.printer().get_mut().clear()
	search_result := visitor.worker.search(&haystack) or {
		core.err_message('${*haystack.path()}: ${err.msg()}')
		haystack.free_owned()
		return .continue_
	}
	if search_result.has_match() {
		visitor.state.matched.store(true)
	}
	if visitor.state.has_stats {
		visitor.state.stats_lock.lock()
		result_stats := search_result.stats() or { panic('stats enabled without search stats') }
		visitor.state.stats = visitor.state.stats + *result_stats
		visitor.state.stats_lock.unlock()
	}
	visitor.state.output_lock.lock()
	worker_buffer := visitor.worker.printer().get_mut()
	visitor.state.bufwtr.print(worker_buffer) or {
		if cli.is_broken_pipe_error(err) {
			visitor.state.output_broken_pipe.store(true)
		} else {
			core.err_message('${*haystack.path()}: ${err.msg()}')
		}
	}
	visitor.state.output_lock.unlock()
	haystack.free_owned()
	if visitor.state.output_broken_pipe.load()
		|| (visitor.state.matched.load() && visitor.quit_after_match) {
		return .quit
	}
	return .continue_
}

fn (mut visitor SearchParallelVisitor) free() {
	unsafe { free(&visitor) }
}

fn walk_parallel_stream_runner(walk ignore.WalkParallel, events chan ignore.WalkParallelStreamResult, stop &stdatomic.AtomicVal[bool]) bool {
	walk.stream(events, stop)
	return true
}

fn parallel_worker_count(thread_setting usize) int {
	mut count := int(thread_setting)
	if count < 1 {
		count = 1
	}
	return count
}

/// The top-level entry point for file listing without searching.
///
/// This recursively steps through the file list (current directory by default)
/// and prints each path sequentially using a single thread.
fn files(args &flags.HiArgs) !bool {
	if !args.sort_requires_buffering() {
		return files_stream(args)
	}
	haystacks := collect_haystacks(args)!

	mut matched := false
	mut path_printer := args.path_printer_builder().build(args.stdout())
	for haystack in haystacks {
		matched = true
		if args.quit_after_match() {
			break
		}
		path_printer.write(haystack.path()) or {
			if cli.is_broken_pipe_error(err) {
				break
			}
			return err
		}
	}
	// Rust flushes the buffered stdout writer when it is dropped and ignores
	// any error at that point, so the final flush error is ignored here too.
	path_printer.flush() or {}
	return matched
}

/// The top-level entry point for multi-threaded file listing without
/// searching.
///
/// This recursively steps through the file list (current directory by default)
/// and prints each path sequentially using multiple threads.
///
/// Requesting a sorted output from ripgrep (such as with `--sort path`) will
/// automatically disable parallelism and hence sorting is not handled here.
fn files_parallel(args &flags.HiArgs) !bool {
	if args.sort_requires_buffering() {
		return files(args)
	}
	stop := stdatomic.new_atomic(false)
	results := chan FilesParallelResult{cap: parallel_job_queue_capacity}
	walk := args.walk_builder()!.build_parallel()
	producer := spawn files_parallel_producer(walk, args.haystack_builder(),
		args.quit_after_match(), results, stop)

	mut matched := false
	mut output_err := ?IError(none)
	mut path_printer := args.path_printer_builder().build(args.stdout())
	for {
		mut result := <-results
		if result.done {
			break
		}
		matched = matched || result.matched
		if output_err == none && result.has_path {
			path_printer.write(&result.path) or {
				output_err = err
				stop.store(true)
			}
		}
		result.free()
	}
	producer.wait()
	if err := output_err {
		if !cli.is_broken_pipe_error(err) {
			return err
		}
	}
	// Rust flushes the buffered stdout writer when it is dropped and ignores
	// any error at that point, so the final flush error is ignored here too.
	path_printer.flush() or {}
	return matched
}

struct FilesParallelResult {
	done     bool
	matched  bool
	has_path bool
	path     string
}

fn (mut result FilesParallelResult) free() {
	result.path = ''
}

fn files_parallel_producer(walk ignore.WalkParallel, haystack_builder core.HaystackBuilder, quit_after_match bool, results chan FilesParallelResult, stop &stdatomic.AtomicVal[bool]) bool {
	events := chan ignore.WalkParallelStreamResult{cap: parallel_job_queue_capacity}
	stream := spawn walk_parallel_stream_runner(walk, events, stop)
	for {
		mut event := <-events
		if event.done {
			break
		}
		if stop.load() {
			event.result.free()
			continue
		}
		mut haystack := haystack_builder.build_from_result(event.result) or {
			event.result.free()
			continue
		}
		if quit_after_match {
			results <- FilesParallelResult{
				matched: true
			}
			stop.store(true)
			haystack.free_path_cache()
			event.result.free()
			continue
		}
		path := (*haystack.path()).to_owned()
		haystack.free_path_cache()
		event.result.free()
		results <- FilesParallelResult{
			matched:  true
			has_path: true
			path:     path
		}
	}
	stream.wait()
	results <- FilesParallelResult{
		done: true
	}
	return true
}

fn files_stream(args &flags.HiArgs) !bool {
	mut visitor := FilesParallelVisitor{
		args:             args
		haystack_builder: args.haystack_builder()
		path_printer:     args.path_printer_builder().build(args.stdout())
	}
	mut walk := args.walk_builder()!.build()
	for {
		mut result := walk.next() or { break }
		state := visitor.visit(result)
		result.free()
		if state == .quit {
			break
		}
	}
	if err := visitor.err {
		if !cli.is_broken_pipe_error(err) {
			return err
		}
	}
	// Rust flushes the buffered stdout writer when it is dropped and ignores
	// any error at that point, so the final flush error is ignored here too.
	visitor.path_printer.flush() or {}
	return visitor.matched
}

struct FilesParallelVisitor {
	args             &flags.HiArgs
	haystack_builder core.HaystackBuilder
mut:
	path_printer printer.PathPrinter[cli.StandardStream]
	matched      bool
	err          ?IError
}

fn (mut visitor FilesParallelVisitor) visit(result ignore.WalkResult) ignore.WalkState {
	mut haystack := visitor.haystack_builder.build_from_result(result) or { return .continue_ }
	defer {
		haystack.free_path_cache()
	}
	visitor.matched = true
	if visitor.args.quit_after_match() {
		return .quit
	}
	visitor.path_printer.write(haystack.path()) or {
		visitor.err = err
		return .quit
	}
	return .continue_
}

/// The top-level entry point for `--type-list`.
fn types(args &flags.HiArgs) !int {
	mut count := 0
	mut stdout := args.stdout()
	for def in *args.types().definitions() {
		count++
		stdout.write((*def.name()).bytes())!
		stdout.write(': '.bytes())!

		mut first := true
		for glob in *def.globs() {
			if !first {
				stdout.write(', '.bytes())!
			}
			stdout.write(glob.bytes())!
			first = false
		}
		stdout.write('\n'.bytes())!
	}
	stdout.flush()!
	return if count == 0 { 1 } else { 0 }
}

/// Implements ripgrep's "generate" modes.
///
/// These modes correspond to generating some kind of ancillary data related
/// to ripgrep. At present, this includes ripgrep's man page (in roff format)
/// and supported shell completions.
fn generate(mode flags.GenerateMode) !int {
	output := match mode {
		.man { flags.generate_man() }
		.complete_bash { flags.generate_complete_bash() }
		.complete_zsh { flags.generate_complete_zsh() }
		.complete_fish { flags.generate_complete_fish() }
		.complete_powershell { flags.generate_complete_powershell() }
	}

	write_stdout_line(output.trim_right('\n'))!
	return 0
}

/// Implements ripgrep's "special" modes.
///
/// A special mode is one that generally short-circuits most (not all) of
/// ripgrep's initialization logic and skips right to this routine. The
/// special modes essentially consist of printing help and version output. The
/// idea behind the short circuiting is to ensure there is as little as possible
/// (within reason) that would prevent ripgrep from emitting help output.
///
/// For example, part of the initialization logic that is skipped (among
/// other things) is accessing the current working directory. If that fails,
/// ripgrep emits an error. We don't want to emit an error if it fails and
/// the user requested version or help information.
fn special(mode flags.SpecialMode) !int {
	mut exit_code := 0
	output := match mode {
		.help_short {
			flags.generate_help_short()
		}
		.help_long {
			flags.generate_help_long()
		}
		.version_short {
			flags.generate_version_short()
		}
		.version_long {
			flags.generate_version_long()
		}
		.version_pcre2 {
			pcre2_output, available := flags.generate_version_pcre2()
			if !available {
				exit_code = 1
			}
			pcre2_output
		}
	}

	write_stdout_line(output.trim_right('\n'))!
	return exit_code
}

/// Prints a heuristic error messages when nothing is searched.
///
/// This can happen if an applicable ignore file has one or more rules that
/// are too broad and cause ripgrep to ignore everything.
///
/// We only show this error message when the user does *not* provide an
/// explicit path to search. This is because the message can otherwise be
/// noisy, e.g., when it is intended that there is nothing to search.
fn eprint_nothing_searched() {
	core.err_message("No files were searched, which means ripgrep probably applied a filter you didn't expect.\nRunning with --debug will show why files are being skipped.")
}

/// Prints the statistics given to the writer given.
///
/// The search mode given determines whether the stats should be printed in
/// a plain text format or in a JSON format.
///
/// The `started` time should be the time at which ripgrep started working.
///
/// If an error occurs while writing, then writing stops and the error is
/// returned. Note that callers should probably ignore this errror, since
/// whether stats fail to print or not generally shouldn't cause ripgrep to
/// enter into an "error" state. And usually the only way for this to fail is
/// if writing to stdout itself fails.
fn print_stats[W](mode flags.SearchMode, stats printer.Stats, started time.Time, mut wtr W) ! {
	elapsed := time.since(started)
	if mode == .json {
		write_color(mut wtr, stats_json(stats, elapsed).bytes())!
		write_color(mut wtr, '\n'.bytes())!
		return
	}
	search_secs := stats.elapsed().seconds()
	total_secs := elapsed.seconds()
	text := '
${stats.matches()} matches
${stats.matched_lines()} matched lines
${stats.searches_with_match()} files contained matches
${stats.searches()} files searched
${stats.bytes_printed()} bytes printed
${stats.bytes_searched()} bytes searched
${search_secs:0.6f} seconds spent searching
${total_secs:0.6f} seconds total
'
	write_color(mut wtr, text.bytes())!
}

fn collect_haystacks(args &flags.HiArgs) ![]core.Haystack {
	mut visitor := CollectHaystacksVisitor{
		haystack_builder: args.haystack_builder()
	}
	mut walk := args.walk_builder()!.build()
	for {
		result := walk.next() or { break }
		if visitor.visit(result) == .quit {
			break
		}
	}
	return args.sort(visitor.haystacks)
}

struct CollectHaystacksVisitor {
	haystack_builder core.HaystackBuilder
mut:
	haystacks []core.Haystack
}

fn (mut visitor CollectHaystacksVisitor) visit(result ignore.WalkResult) ignore.WalkState {
	if haystack := visitor.haystack_builder.build_from_result(result) {
		visitor.haystacks << haystack
	}
	return .continue_
}

fn write_stdout_line(line string) ! {
	mut stdout := cli.stdout_buffered_block(.never)
	stdout.write(line.bytes())!
	stdout.write('\n'.bytes())!
	stdout.flush()!
}

fn write_color[W](mut wtr W, bytes []u8) ! {
	$if W is printer.WriteColor {
		wtr.write(bytes)!
	} $else {
		_ = bytes
		return error('writer does not implement WriteColor')
	}
}

fn stats_json(stats printer.Stats, elapsed time.Duration) string {
	stats_elapsed := stats.elapsed()
	stats_secs := stats_elapsed.seconds()
	stats_nanos := stats_elapsed.nanoseconds() % 1_000_000_000
	total_secs := elapsed.seconds()
	total_nanos := elapsed.nanoseconds() % 1_000_000_000
	return '{"type":"summary","data":{"stats":{"elapsed":{"secs":${u64(stats_secs)},"nanos":${stats_nanos},"human":"${stats_secs:0.6f}s"},"searches":${stats.searches()},"searches_with_match":${stats.searches_with_match()},"bytes_searched":${stats.bytes_searched()},"bytes_printed":${stats.bytes_printed()},"matched_lines":${stats.matched_lines()},"matches":${stats.matches()}},"elapsed_total":{"secs":${u64(total_secs)},"nanos":${total_nanos},"human":"${total_secs:0.6f}s"}}}'
}
