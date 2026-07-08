module rg

import cli
import core
import core.flags
import ignore
import printer
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
	args.walk_builder()!.build_parallel().run(mut visitor)
	if err := visitor.err {
		return err
	}
	stats = visitor.stats
	if args.has_implicit_path() && !visitor.searched {
		eprint_nothing_searched()
	}
	if stats_value := stats {
		mut wtr := visitor.searcher.printer().get_mut()
		print_stats(mode, stats_value, started_at, mut wtr)!
	}
	visitor.searcher.printer().flush()!
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
	err      ?IError
}

fn (mut visitor SearchStreamVisitor) visit(result ignore.WalkResult) ignore.WalkState {
	haystack := visitor.haystack_builder.build_from_result(result) or { return .continue_ }
	visitor.searched = true
	search_result := visitor.searcher.search(&haystack) or {
		if cli.is_broken_pipe_error(err) {
			visitor.err = err
			return .quit
		}
		core.err_message('${*haystack.path()}: ${err.msg()}')
		return .continue_
	}
	visitor.matched = visitor.matched || search_result.has_match()
	if stats_value := visitor.stats {
		if result_stats := search_result.stats() {
			visitor.stats = stats_value + *result_stats
		}
	}
	if visitor.matched && visitor.args.quit_after_match() {
		return .quit
	}
	return .continue_
}

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
	for haystack in haystacks {
		searched = true
		search_result := searcher.search(&haystack) or {
			if cli.is_broken_pipe_error(err) {
				return err
			}
			core.err_message('${*haystack.path()}: ${err.msg()}')
			continue
		}
		matched = matched || search_result.has_match()
		if stats_value := stats {
			if result_stats := search_result.stats() {
				stats = stats_value + *result_stats
			}
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
		print_stats(mode, stats_value, started_at, mut wtr)!
	}
	searcher.printer().flush()!
	return matched
}

/// The top-level entry point for search when multiple threads were requested.
///
/// The parallelism is itself achieved by feeding haystacks from traversal to
/// search workers. This preserves the existing streaming path for modes that
/// need early global termination.
fn search_parallel(args &flags.HiArgs, mode flags.SearchMode) !bool {
	started_at := time.now()
	mut bufwtr := args.buffer_writer()
	if args.quit_after_match() {
		return search(args, mode)
	}

	thread_count := parallel_worker_count(args.threads())
	mut separator := []u8{}
	mut has_separator := false
	if sep := args.file_separator_bytes() {
		separator = sep
		has_separator = true
	}
	walk := args.walk_builder()!.build_parallel()
	mut workers := []core.SearchWorker[cli.Buffer]{cap: thread_count}
	for _ in 0 .. thread_count {
		matcher_ := args.matcher()!
		searcher_ := args.searcher()!
		printer_ := args.printer_buffer(mode, bufwtr.buffer())
		workers << args.search_worker_buffer(matcher_, searcher_, printer_)!
	}
	jobs := chan SearchParallelJob{cap: parallel_job_queue_capacity}
	results := chan SearchParallelChunkResult{cap: thread_count}
	mut threads := []thread bool{}
	for worker_index in 0 .. thread_count {
		worker := workers[worker_index]
		threads << spawn search_parallel_worker(worker, jobs, results, args.stats() != none,
			separator.clone(), has_separator, worker_index)
	}
	producer := spawn search_parallel_producer(walk, args.haystack_builder(), jobs, thread_count)

	mut matched := false
	mut stats := args.stats()
	for _ in 0 .. thread_count {
		result := <-results
		matched = matched || result.matched
		for message in result.errors {
			core.err_message(message)
		}
		bufwtr.print(&result.buffer)!
		if stats_value := stats {
			if result_stats := result.stats {
				stats = stats_value + result_stats
			}
		}
	}
	producer_result := producer.wait()
	for thread in threads {
		thread.wait()
	}
	if args.has_implicit_path() && producer_result.haystack_count == 0 {
		eprint_nothing_searched()
	}
	if stats_value := stats {
		mut wtr := bufwtr.buffer()
		print_stats(mode, stats_value, started_at, mut wtr)!
		bufwtr.print(&wtr)!
	}
	return matched
}

struct SearchParallelJob {
	stop     bool
	haystack core.Haystack
}

struct SearchParallelProducerResult {
	haystack_count int
}

struct SearchParallelQueueVisitor {
	haystack_builder core.HaystackBuilder
	jobs             chan SearchParallelJob
mut:
	haystack_count int
}

fn (mut visitor SearchParallelQueueVisitor) visit(result ignore.WalkResult) ignore.WalkState {
	if haystack := visitor.haystack_builder.build_from_result(result) {
		visitor.jobs <- SearchParallelJob{
			haystack: haystack
		}
		visitor.haystack_count++
	}
	return .continue_
}

struct SearchParallelChunkResult {
	index    int
	matched  bool
	searched bool
	stats    ?printer.Stats
	buffer   cli.Buffer
	errors   []string
}

fn search_parallel_producer(walk ignore.WalkParallel, haystack_builder core.HaystackBuilder, jobs chan SearchParallelJob, stop_count int) SearchParallelProducerResult {
	mut visitor := SearchParallelQueueVisitor{
		haystack_builder: haystack_builder
		jobs:             jobs
	}
	walk.run(mut visitor)
	for _ in 0 .. stop_count {
		jobs <- SearchParallelJob{
			stop: true
		}
	}
	return SearchParallelProducerResult{
		haystack_count: visitor.haystack_count
	}
}

fn search_parallel_worker(searcher_in core.SearchWorker[cli.Buffer], jobs chan SearchParallelJob, results chan SearchParallelChunkResult, stats_enabled bool, separator []u8, has_separator bool, index int) bool {
	mut searcher := searcher_in
	mut chunk_buffer := searcher.printer().get_mut().take()
	mut printed := false
	mut result := SearchParallelChunkResult{
		index:    index
		matched:  false
		searched: false
		stats:    if stats_enabled {
			?printer.Stats(printer.Stats.new())
		} else {
			?printer.Stats(none)
		}
		buffer:   chunk_buffer
		errors:   []string{}
	}
	for {
		job := <-jobs
		if job.stop {
			break
		}
		haystack := job.haystack
		result.searched = true
		searcher.printer().get_mut().clear()
		search_result := searcher.search(&haystack) or {
			result.errors << '${*haystack.path()}: ${err.msg()}'
			continue
		}
		if search_result.has_match() {
			result.matched = true
		}
		if stats_value := result.stats {
			if result_stats := search_result.stats() {
				result.stats = stats_value + *result_stats
			}
		}
		file_buffer := searcher.printer().get_mut().take()
		if !file_buffer.is_empty() {
			if printed && has_separator {
				result.buffer.write(separator) or {}
			}
			result.buffer.append_buffer(&file_buffer)
			printed = true
		}
	}
	searcher.printer().flush() or {}
	results <- result
	return true
}

fn parallel_worker_count(thread_setting usize) int {
	mut count := int(thread_setting)
	if count < 1 {
		count = 1
	}
	if count > 4 {
		count = 4
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
		path_printer.write(haystack.path())!
	}
	path_printer.flush()!
	return matched
}

/// The top-level entry point for file listing when multiple threads were
/// requested.
///
/// V-specific: real parallel traversal is not translated yet, so this falls
/// back to the sequential file listing path.
fn files_parallel(args &flags.HiArgs) !bool {
	// V-specific: see `search_parallel`.
	return files(args)
}

fn files_stream(args &flags.HiArgs) !bool {
	mut visitor := FilesParallelVisitor{
		args:             args
		strip_dot_prefix: args.has_implicit_path()
		path_printer:     args.path_printer_builder().build(args.stdout())
	}
	args.walk_builder()!.build_parallel().run(mut visitor)
	if err := visitor.err {
		return err
	}
	visitor.path_printer.flush()!
	return visitor.matched
}

struct FilesParallelVisitor {
	args             &flags.HiArgs
	strip_dot_prefix bool
mut:
	path_printer printer.PathPrinter[cli.StandardStream]
	matched      bool
	err          ?IError
}

fn (mut visitor FilesParallelVisitor) visit(result ignore.WalkResult) ignore.WalkState {
	if result.is_error {
		core.err_message(result.err.msg())
		return .continue_
	}
	dent := result.entry
	if err := dent.error() {
		core.ignore_message(err.msg())
	}
	if !files_should_print(&dent) {
		return .continue_
	}
	visitor.matched = true
	if visitor.args.quit_after_match() {
		return .quit
	}
	visitor.write_path(&dent) or {
		visitor.err = err
		return .quit
	}
	return .continue_
}

fn (mut visitor FilesParallelVisitor) write_path(dent &ignore.DirEntry) ! {
	path := *dent.path()
	if visitor.strip_dot_prefix && path.starts_with('./') {
		path_value := path[2..].to_owned()
		visitor.path_printer.write(&path_value)!
		return
	}
	visitor.path_printer.write(dent.path())!
}

fn files_should_print(dent &ignore.DirEntry) bool {
	if dent.is_stdin() {
		return true
	}
	if dent.depth() == 0 && !dent.is_dir() {
		return true
	}
	ft := dent.file_type() or { return false }
	return ft == .file
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
	text := '
${stats.matches()} matches
${stats.matched_lines()} matched lines
${stats.searches_with_match()} files contained matches
${stats.searches()} files searched
${stats.bytes_printed()} bytes printed
${stats.bytes_searched()} bytes searched
${stats.elapsed().seconds():0.6f} seconds spent searching
${elapsed.seconds():0.6f} seconds total
'
	write_color(mut wtr, text.bytes())!
}

fn collect_haystacks(args &flags.HiArgs) ![]core.Haystack {
	mut visitor := CollectHaystacksVisitor{
		haystack_builder: args.haystack_builder()
	}
	args.walk_builder()!.build_parallel().run(mut visitor)
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
	return '{"type":"summary","data":{"stats":{"elapsed":{"secs":${u64(stats_elapsed.seconds())},"nanos":${stats_elapsed.nanoseconds() % 1_000_000_000},"human":"${stats_elapsed.seconds():0.6f}s"},"searches":${stats.searches()},"searches_with_match":${stats.searches_with_match()},"bytes_searched":${stats.bytes_searched()},"bytes_printed":${stats.bytes_printed()},"matched_lines":${stats.matched_lines()},"matches":${stats.matches()}},"elapsed_total":{"secs":${u64(elapsed.seconds())},"nanos":${elapsed.nanoseconds() % 1_000_000_000},"human":"${elapsed.seconds():0.6f}s"}}}'
}
