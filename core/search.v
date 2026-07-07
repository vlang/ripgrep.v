module core

import cli
import ignore
import io
import os
import pcre2
import printer
import regex
import searcher

/*
Defines a very high level "search worker" abstraction.

A search worker manages the high level interaction points between the matcher
(i.e., which regex engine is used), the searcher (i.e., how data is actually
read and matched using the regex engine) and the printer. For example, the
search worker is where things like preprocessors or decompression happens.
*/

/// The configuration for the search worker.
///
/// Among a few other things, the configuration primarily controls the way we
/// show search results to users at a very high level.
struct SearchConfig implements IClone {
mut:
	preprocessor       ?string
	preprocessor_globs ignore.Override
	search_zip         bool
	binary_implicit    searcher.BinaryDetection
	binary_explicit    searcher.BinaryDetection
}

fn SearchConfig.default() SearchConfig {
	return SearchConfig{
		preprocessor:       none
		preprocessor_globs: ignore.Override.empty()
		search_zip:         false
		binary_implicit:    searcher.BinaryDetection.disabled()
		binary_explicit:    searcher.BinaryDetection.disabled()
	}
}

fn (config SearchConfig) clone() SearchConfig {
	mut preprocessor := ?string(none)
	if value := config.preprocessor {
		preprocessor = value.clone()
	}
	return SearchConfig{
		preprocessor:       preprocessor
		preprocessor_globs: config.preprocessor_globs.clone()
		search_zip:         config.search_zip
		binary_implicit:    config.binary_implicit.clone()
		binary_explicit:    config.binary_explicit.clone()
	}
}

/// A builder for configuring and constructing a search worker.
pub struct SearchWorkerBuilder implements IClone {
mut:
	config          SearchConfig
	command_builder cli.CommandReaderBuilder
}

pub fn SearchWorkerBuilder.default() SearchWorkerBuilder {
	return SearchWorkerBuilder.new()
}

/// Create a new builder for configuring and constructing a search worker.
pub fn SearchWorkerBuilder.new() SearchWorkerBuilder {
	mut command_builder := cli.CommandReaderBuilder.new()
	command_builder.async_stderr(true)
	return SearchWorkerBuilder{
		config:          SearchConfig.default()
		command_builder: command_builder
	}
}

/// Create a new search worker using the given searcher, matcher and
/// printer.
pub fn (builder SearchWorkerBuilder) build[W](matcher_ PatternMatcher, searcher_ searcher.Searcher, printer_ Printer[W]) SearchWorker[W] {
	config := builder.config.clone()
	mut decomp_builder := ?cli.DecompressionReaderBuilder(none)
	if config.search_zip {
		mut builder_ := cli.new_decompression_reader_builder()
		builder_.async_stderr(true)
		decomp_builder = builder_
	}
	return SearchWorker[W]{
		config:          config
		command_builder: builder.command_builder.clone()
		decomp_builder:  decomp_builder
		matcher:         matcher_
		searcher:        searcher_
		printer:         printer_
	}
}

/// V-specific concrete stdout search worker builder.
///
/// The current ownership frontend does not reliably emit the
/// `SearchWorkerBuilder.build[cli.StandardStream]` specialization used by the
/// root CLI, so this keeps the translated build logic available for that
/// concrete writer.
pub fn (builder SearchWorkerBuilder) build_standard_stream(matcher_ PatternMatcher, searcher_ searcher.Searcher, printer_ Printer[cli.StandardStream]) SearchWorker[cli.StandardStream] {
	config := builder.config.clone()
	mut decomp_builder := ?cli.DecompressionReaderBuilder(none)
	if config.search_zip {
		mut builder_ := cli.new_decompression_reader_builder()
		builder_.async_stderr(true)
		decomp_builder = builder_
	}
	return SearchWorker[cli.StandardStream]{
		config:          config
		command_builder: builder.command_builder.clone()
		decomp_builder:  decomp_builder
		matcher:         matcher_
		searcher:        searcher_
		printer:         printer_
	}
}

/// V-specific concrete buffer search worker builder.
///
/// See `build_standard_stream`.
pub fn (builder SearchWorkerBuilder) build_buffer(matcher_ PatternMatcher, searcher_ searcher.Searcher, printer_ Printer[cli.Buffer]) SearchWorker[cli.Buffer] {
	config := builder.config.clone()
	mut decomp_builder := ?cli.DecompressionReaderBuilder(none)
	if config.search_zip {
		mut builder_ := cli.new_decompression_reader_builder()
		builder_.async_stderr(true)
		decomp_builder = builder_
	}
	return SearchWorker[cli.Buffer]{
		config:          config
		command_builder: builder.command_builder.clone()
		decomp_builder:  decomp_builder
		matcher:         matcher_
		searcher:        searcher_
		printer:         printer_
	}
}

/// Set the path to a preprocessor command.
///
/// When this is set, instead of searching files directly, the given
/// command will be run with the file path as the first argument, and the
/// output of that command will be searched instead.
pub fn (mut builder SearchWorkerBuilder) preprocessor(cmd ?string) !&SearchWorkerBuilder {
	if prog := cmd {
		bin := cli.resolve_binary(prog)!
		builder.config.preprocessor = bin
	} else {
		builder.config.preprocessor = none
	}
	return &builder
}

/// Set the globs for determining which files should be run through the
/// preprocessor. By default, with no globs and a preprocessor specified,
/// every file is run through the preprocessor.
pub fn (mut builder SearchWorkerBuilder) preprocessor_globs(globs ignore.Override) &SearchWorkerBuilder {
	builder.config.preprocessor_globs = globs
	return &builder
}

/// Enable the decompression and searching of common compressed files.
///
/// When enabled, if a particular file path is recognized as a compressed
/// file, then it is decompressed before searching.
///
/// Note that if a preprocessor command is set, then it overrides this
/// setting.
pub fn (mut builder SearchWorkerBuilder) search_zip(yes bool) &SearchWorkerBuilder {
	builder.config.search_zip = yes
	return &builder
}

/// Set the binary detection that should be used when searching files
/// found via a recursive directory search.
///
/// Generally, this binary detection may be
/// `grep::searcher::BinaryDetection::quit` if we want to skip binary files
/// completely.
///
/// By default, no binary detection is performed.
pub fn (mut builder SearchWorkerBuilder) binary_detection_implicit(detection searcher.BinaryDetection) &SearchWorkerBuilder {
	builder.config.binary_implicit = detection
	return &builder
}

/// Set the binary detection that should be used when searching files
/// explicitly supplied by an end user.
///
/// Generally, this binary detection should NOT be
/// `grep::searcher::BinaryDetection::quit`, since we never want to
/// automatically filter files supplied by the end user.
///
/// By default, no binary detection is performed.
pub fn (mut builder SearchWorkerBuilder) binary_detection_explicit(detection searcher.BinaryDetection) &SearchWorkerBuilder {
	builder.config.binary_explicit = detection
	return &builder
}

/// The result of executing a search.
///
/// Generally speaking, the "result" of a search is sent to a printer, which
/// writes results to an underlying writer such as stdout or a file. However,
/// every search also has some aggregate statistics or meta data that may be
/// useful to higher level routines.
pub struct SearchResult implements IClone {
	has_match bool
	stats     ?printer.Stats
}

/// Whether the search found a match or not.
pub fn (result SearchResult) has_match() bool {
	return result.has_match
}

/// Return aggregate search statistics for a single search, if available.
///
/// It can be expensive to compute statistics, so these are only present
/// if explicitly enabled in the printer provided by the caller.
pub fn (result &^a SearchResult) stats[^a]() ?&^a printer.Stats {
	if result.stats != none {
		return unsafe { &result.stats? }
	}
	return none
}

/// The pattern matcher used by a search worker.
///
/// V-specific: V2 generic sum type payload codegen is not complete enough for
/// the Rust enum shape here, so this port uses an explicit tagged
/// representation.
pub struct PatternMatcher implements IClone {
	kind  PatternMatcherKind
	regex regex.RegexMatcher
	pcre2 pcre2.RegexMatcher
}

pub fn PatternMatcher.rust_regex(matcher_ regex.RegexMatcher) PatternMatcher {
	return PatternMatcher{
		kind:  .rust_regex
		regex: matcher_
	}
}

pub fn PatternMatcher.pcre2(matcher_ pcre2.RegexMatcher) PatternMatcher {
	return PatternMatcher{
		kind:  .pcre2
		pcre2: matcher_
	}
}

enum PatternMatcherKind {
	rust_regex
	pcre2
}

enum PrinterKind {
	standard
	summary
	json
}

/// The printer used by a search worker.
///
/// The `W` type parameter refers to the type of the underlying writer.
///
/// V-specific: V2 generic sum type payload codegen is not complete enough for
/// the Rust enum shape here, so this port uses an explicit tagged
/// representation.
pub struct Printer[W] implements IClone {
	kind PrinterKind
mut:
	standard printer.Standard[W]
	summary  printer.Summary[W]
	json     printer.JSON[W]
}

/// Use the standard printer, which supports the classic grep-like format.
pub fn Printer.standard[W](standard printer.Standard[W]) Printer[W] {
	return Printer[W]{
		kind:     .standard
		standard: standard
	}
}

/// Use the summary printer, which supports aggregate displays of search
/// results.
pub fn Printer.summary[W](summary printer.Summary[W]) Printer[W] {
	return Printer[W]{
		kind:    .summary
		summary: summary
	}
}

/// A JSON printer, which emits results in the JSON Lines format.
pub fn Printer.json[W](json printer.JSON[W]) Printer[W] {
	return Printer[W]{
		kind: .json
		json: json
	}
}

/// Return a mutable reference to the underlying printer's writer.
pub fn (mut p Printer[W]) get_mut() &W {
	return match p.kind {
		.standard { p.standard.get_mut() }
		.summary { p.summary.get_mut() }
		.json { p.json.get_mut() }
	}
}

/// Flush the underlying printer writer.
pub fn (mut p Printer[W]) flush() ! {
	match p.kind {
		.standard { p.standard.flush()! }
		.summary { p.summary.flush()! }
		.json { p.json.flush()! }
	}
}

/// A worker for executing searches.
///
/// It is intended for a single worker to execute many searches, and is
/// generally intended to be used from a single thread. When searching using
/// multiple threads, it is better to create a new worker for each thread.
pub struct SearchWorker[W] implements IClone {
mut:
	config          SearchConfig
	command_builder cli.CommandReaderBuilder
	/// This is `None` when `search_zip` is not enabled, since in this case it
	/// can never be used. We do this because building the reader can sometimes
	/// do non-trivial work (like resolving the paths of decompression binaries
	/// on Windows).
	decomp_builder ?cli.DecompressionReaderBuilder
	matcher        PatternMatcher
	searcher       searcher.Searcher
	printer        Printer[W]
}

/// Execute a search over the given haystack.
pub fn (mut worker SearchWorker[W]) search(haystack &Haystack) !SearchResult {
	bin := if haystack.is_explicit() {
		worker.config.binary_explicit.clone()
	} else {
		worker.config.binary_implicit.clone()
	}
	path := (*haystack.path()).to_owned()
	worker.searcher.set_binary_detection(bin)
	if haystack.is_stdin() {
		mut stdin := os.stdin()
		return worker.search_reader(path.clone(), mut stdin)
	}
	if worker.should_preprocess(path.clone()) {
		return worker.search_preprocessor(path.clone())
	}
	if worker.should_decompress(path.clone()) {
		return worker.search_decompress(path.clone())
	}
	return worker.search_path(path)
}

/// Return a mutable reference to the underlying printer.
pub fn (mut worker SearchWorker[W]) printer() &Printer[W] {
	return &worker.printer
}

/// Returns true if and only if the given file path should be
/// decompressed before searching.
fn (worker SearchWorker[W]) should_decompress(path string) bool {
	if decomp_builder := worker.decomp_builder {
		return decomp_builder.get_matcher().has_command(path)
	}
	return false
}

/// Returns true if and only if the given file path should be run through
/// the preprocessor.
fn (worker SearchWorker[W]) should_preprocess(path string) bool {
	if worker.config.preprocessor == none {
		return false
	}
	if worker.config.preprocessor_globs.is_empty() {
		return true
	}
	return !worker.config.preprocessor_globs.matched(path, false).is_ignore()
}

/// Search the given file path by first asking the preprocessor for the
/// data to search instead of opening the path directly.
fn (mut worker SearchWorker[W]) search_preprocessor(path string) !SearchResult {
	bin := worker.config.preprocessor or { return worker.search_path(path) }
	mut cmd := cli.Command.new(bin)
	cmd.arg(path.clone())
	mut rdr := worker.command_builder.build(cmd) or {
		return error("preprocessor command could not start: '${bin} ${path}': ${err.msg()}")
	}
	result := worker.search_reader(path.clone(), mut rdr) or {
		return error("preprocessor command failed: '${bin} ${path}': ${err.msg()}")
	}
	rdr.close()!
	return result
}

/// Attempt to decompress the data at the given file path and search the
/// result. If the given file path isn't recognized as a compressed file,
/// then search it without doing any decompression.
fn (mut worker SearchWorker[W]) search_decompress(path string) !SearchResult {
	decomp_builder := worker.decomp_builder or { return worker.search_path(path) }
	mut rdr := decomp_builder.build(path.clone())!
	result := worker.search_reader(path.clone(), mut rdr)!
	rdr.close()!
	return result
}

	/// Search the contents of the given file path.
	pub fn (mut worker SearchWorker[W]) search_path(path string) !SearchResult {
		return match worker.matcher.kind {
			.rust_regex {
				worker.search_path_with_regex_matcher(worker.matcher.regex.clone(),
					printer.PrinterMatcher.rust_regex(worker.matcher.regex.clone()), path.clone())
			}
			.pcre2 {
				worker.search_path_with_pcre2_matcher(worker.matcher.pcre2.clone(),
					printer.PrinterMatcher.pcre2(worker.matcher.pcre2.clone()), path.clone())
			}
		}
	}

	/// Executes a search on the given reader, which may or may not correspond
	/// directly to the contents of the given file path. Instead, the reader
	/// may actually cause something else to be searched (for example, when
	/// a preprocessor is set or when decompression is enabled). In those
	/// cases, the file path is used for visual purposes only.
	///
	/// Generally speaking, this method should only be used when there is no
	/// other choice. Searching via `search_path` provides more opportunities
	/// for optimizations (such as memory maps).
	pub fn (mut worker SearchWorker[W]) search_reader(path string, mut rdr io.Reader) !SearchResult {
		return match worker.matcher.kind {
			.rust_regex {
				worker.search_reader_with_regex_matcher(worker.matcher.regex.clone(),
					printer.PrinterMatcher.rust_regex(worker.matcher.regex.clone()), path.clone(), mut rdr)
			}
			.pcre2 {
				worker.search_reader_with_pcre2_matcher(worker.matcher.pcre2.clone(),
					printer.PrinterMatcher.pcre2(worker.matcher.pcre2.clone()), path.clone(), mut rdr)
			}
		}
	}

	/// Search the contents of the given file path using the given matcher,
	/// searcher and printer.
	fn (mut worker SearchWorker[W]) search_path_with_regex_matcher(matcher_ regex.RegexMatcher, printer_matcher printer.PrinterMatcher, path string) !SearchResult {
		return match worker.printer.kind {
			.standard {
				mut sink := worker.printer.standard.sink_with_path(printer_matcher.clone(), &path)
				worker.searcher.search_path(matcher_, path.clone(), &sink)!
				SearchResult{
					has_match: sink.has_match()
					stats:     stats_clone(sink.stats())
				}
			}
			.summary {
				mut sink := worker.printer.summary.sink_with_path(printer_matcher.clone(), &path)
				worker.searcher.search_path(matcher_, path.clone(), &sink)!
				SearchResult{
					has_match: sink.has_match()
					stats:     stats_clone((&sink).stats())
				}
			}
			.json {
				mut sink := worker.printer.json.sink_with_path(printer_matcher.clone(), &path)
				worker.searcher.search_path(matcher_, path.clone(), &sink)!
				SearchResult{
					has_match: sink.has_match()
					stats:     (&sink).stats().clone()
				}
			}
		}
	}

	fn (mut worker SearchWorker[W]) search_path_with_pcre2_matcher(matcher_ pcre2.RegexMatcher, printer_matcher printer.PrinterMatcher, path string) !SearchResult {
		return match worker.printer.kind {
			.standard {
				mut sink := worker.printer.standard.sink_with_path(printer_matcher.clone(), &path)
				worker.searcher.search_path(matcher_, path.clone(), &sink)!
				SearchResult{
					has_match: sink.has_match()
					stats:     stats_clone(sink.stats())
				}
			}
			.summary {
				mut sink := worker.printer.summary.sink_with_path(printer_matcher.clone(), &path)
				worker.searcher.search_path(matcher_, path.clone(), &sink)!
				SearchResult{
					has_match: sink.has_match()
					stats:     stats_clone((&sink).stats())
				}
			}
			.json {
				mut sink := worker.printer.json.sink_with_path(printer_matcher.clone(), &path)
				worker.searcher.search_path(matcher_, path.clone(), &sink)!
				SearchResult{
					has_match: sink.has_match()
					stats:     (&sink).stats().clone()
				}
			}
		}
	}

	/// Search the contents of the given reader using the given matcher, searcher
	/// and printer.
	fn (mut worker SearchWorker[W]) search_reader_with_regex_matcher(matcher_ regex.RegexMatcher, printer_matcher printer.PrinterMatcher, path string, mut rdr io.Reader) !SearchResult {
		return match worker.printer.kind {
			.standard {
				mut sink := worker.printer.standard.sink_with_path(printer_matcher.clone(), &path)
				worker.searcher.search_reader(matcher_, mut rdr, &sink)!
				SearchResult{
					has_match: sink.has_match()
					stats:     stats_clone(sink.stats())
				}
			}
			.summary {
				mut sink := worker.printer.summary.sink_with_path(printer_matcher.clone(), &path)
				worker.searcher.search_reader(matcher_, mut rdr, &sink)!
				SearchResult{
					has_match: sink.has_match()
					stats:     stats_clone((&sink).stats())
				}
			}
			.json {
				mut sink := worker.printer.json.sink_with_path(printer_matcher.clone(), &path)
				worker.searcher.search_reader(matcher_, mut rdr, &sink)!
				SearchResult{
					has_match: sink.has_match()
					stats:     (&sink).stats().clone()
				}
			}
		}
	}

	fn (mut worker SearchWorker[W]) search_reader_with_pcre2_matcher(matcher_ pcre2.RegexMatcher, printer_matcher printer.PrinterMatcher, path string, mut rdr io.Reader) !SearchResult {
		return match worker.printer.kind {
			.standard {
				mut sink := worker.printer.standard.sink_with_path(printer_matcher.clone(), &path)
				worker.searcher.search_reader(matcher_, mut rdr, &sink)!
				SearchResult{
					has_match: sink.has_match()
					stats:     stats_clone(sink.stats())
				}
			}
			.summary {
				mut sink := worker.printer.summary.sink_with_path(printer_matcher.clone(), &path)
				worker.searcher.search_reader(matcher_, mut rdr, &sink)!
				SearchResult{
					has_match: sink.has_match()
					stats:     stats_clone((&sink).stats())
				}
			}
			.json {
				mut sink := worker.printer.json.sink_with_path(printer_matcher.clone(), &path)
				worker.searcher.search_reader(matcher_, mut rdr, &sink)!
				SearchResult{
					has_match: sink.has_match()
					stats:     (&sink).stats().clone()
				}
			}
		}
	}
fn stats_clone(stats ?&printer.Stats) ?printer.Stats {
	if value := stats {
		return value.clone()
	}
	return none
}
