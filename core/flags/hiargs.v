module flags

import cli
import core
import ignore
import matcher
import os
import pcre2
import printer
import regex
import runtime
import searcher

/*!
Provides the definition of high level arguments from CLI flags.
*/

/// A high level representation of CLI arguments.
///
/// The distinction between low and high level arguments is somewhat arbitrary
/// and wishy washy. The main idea here is that high level arguments generally
/// require all of CLI parsing to be finished. For example, one cannot
/// construct a glob matcher until all of the glob patterns are known.
///
/// So while low level arguments are collected during parsing itself, high
/// level arguments aren't created until parsing has completely finished.
pub struct HiArgs {
	binary                       BinaryDetection
	boundary                     ?BoundaryMode
	buffer                       BufferMode
	byte_offset                  bool
	case                         CaseMode
	color                        ColorChoice
	colors                       printer.ColorSpecs
	column                       bool
	context                      ContextMode
	context_separator            ContextSeparator
	crlf                         bool
	cwd                          string
	dfa_size_limit               ?usize
	encoding                     EncodingMode
	engine                       EngineChoice
	field_context_separator      FieldContextSeparator
	field_match_separator        FieldMatchSeparator
	file_separator               ?[]u8
	fixed_strings                bool
	follow                       bool
	globs                        ignore.Override
	heading                      bool
	hidden                       bool
	hyperlink_config             printer.HyperlinkConfig
	ignore_file_case_insensitive bool
	ignore_file                  []string
	include_zero                 bool
	invert_match                 bool
	is_terminal_stdout           bool
	line_number                  bool
	max_columns                  ?u64
	max_columns_preview          bool
	max_count                    ?u64
	max_depth                    ?usize
	max_filesize                 ?u64
	mmap_choice                  searcher.MmapChoice
	mode                         Mode
	multiline                    bool
	multiline_dotall             bool
	no_ignore_dot                bool
	no_ignore_exclude            bool
	no_ignore_files              bool
	no_ignore_global             bool
	no_ignore_parent             bool
	no_ignore_vcs                bool
	no_require_git               bool
	no_unicode                   bool
	null_data                    bool
	one_file_system              bool
	only_matching                bool
	path_separator               ?u8
	paths                        Paths
	path_terminator              ?u8
	patterns                     Patterns
	pre                          ?string
	pre_globs                    ignore.Override
	quiet                        bool
	quit_after_match             bool
	regex_size_limit             ?usize
	replace                      ?string
	search_zip                   bool
	sort                         ?SortMode
	stats                        ?printer.Stats
	stop_on_nonmatch             bool
	threads                      usize
	trim                         bool
	types                        ignore.Types
	vimgrep                      bool
	with_filename                bool
}

/// Convert low level arguments into high level arguments.
///
/// This process can fail for a variety of reasons. For example, invalid
/// globs or some kind of environment issue.
pub fn HiArgs.from_low_args(mut low LowArgs) !HiArgs {
	// Callers should not be trying to convert low-level arguments when
	// a short-circuiting special mode is present.
	if low.special != none {
		panic('special mode demands short-circuiting')
	}
	// If the sorting mode isn't supported, then we bail loudly. I'm not
	// sure if this is the right thing to do. We could silently "not sort"
	// as well. If we wanted to go that route, then we could just set
	// `low.sort = None` if `supported()` returns an error.
	if sort := low.sort {
		sort.supported()!
	}

	// We modify the mode in-place on `low` so that subsequent conversions
	// see the correct mode.
	if low.mode.kind == .search {
		if low.mode.search == .count_matches && low.invert_match {
			// treat `-v --count-matches` as `-v --count`
			low.mode.search = .count
		} else if low.mode.search == .count && low.only_matching {
			// treat `-o --count` as `--count-matches`
			low.mode.search = .count_matches
		}
	}

	mut state := State.new()!
	patterns := Patterns.from_low_args(mut state, mut low)!
	paths := Paths.from_low_args(mut state, patterns, mut low)!

	binary := BinaryDetection.from_low_args(state, low)
	colors := take_color_specs(mut state, mut low)!
	hyperlink_config := take_hyperlink_config(mut state, mut low)!
	stats_value := stats(low)
	types_value := types(low)!
	globs_value := globs(state, low)!
	pre_globs_value := preprocessor_globs(state, low)!

	color := if low.color == .auto && !state.is_terminal_stdout { ColorChoice.never } else { low.color }
	column := low.column or { low.vimgrep }
	heading := if heading_value := low.heading {
		if heading_value { !low.vimgrep } else { false }
	} else {
		!low.vimgrep && state.is_terminal_stdout
	}
	path_terminator := if low.null { ?u8(`\0`) } else { ?u8(none) }
	quit_after_match := stats_value == none && low.quiet
	threads := if low.sort != none || paths.is_one_file {
		usize(1)
	} else if thread_count := low.threads {
		thread_count
	} else {
		default_thread_count()
	}
	with_filename := low.with_filename or { low.vimgrep || !paths.is_one_file }

	mut file_separator := ?[]u8(none)
	if low.mode.kind == .search && low.mode.search == .standard {
		if heading {
			file_separator = []u8{}
		} else if low.context.kind == .limited {
			before, after := low.context.limited.get()
			if before > 0 || after > 0 {
				file_separator = low.context_separator.into_bytes()
			}
		}
	}

	line_number := low.line_number or {
		if low.quiet {
			false
		} else if low.mode.kind != .search {
			false
		} else {
			match low.mode.search {
				.files_with_matches, .files_without_match, .count, .count_matches {
					false
				}
				.json {
					true
				}
				.standard {
					// A few things can imply counting line numbers. In
					// particular, we generally want to show line numbers by
					// default when printing to a tty for human consumption,
					// except for one interesting case: when we're only
					// searching stdin. This makes pipelines work as expected.
					(state.is_terminal_stdout && !paths.is_only_stdin()) || column || low.vimgrep
				}
			}
		}
	}

	mmap_choice_value := compute_mmap_choice(low.mmap, paths)

	return HiArgs{
		mode:                         low.mode
		patterns:                     patterns
		paths:                        paths
		binary:                       binary
		boundary:                     low.boundary
		buffer:                       low.buffer
		byte_offset:                  low.byte_offset
		case:                         low.case
		color:                        color
		colors:                       colors
		column:                       column
		context:                      low.context
		context_separator:            low.context_separator
		crlf:                         low.crlf
		cwd:                          state.cwd
		dfa_size_limit:               low.dfa_size_limit
		encoding:                     low.encoding
		engine:                       low.engine
		field_context_separator:      low.field_context_separator
		field_match_separator:        low.field_match_separator
		file_separator:               file_separator
		fixed_strings:                low.fixed_strings
		follow:                       low.follow
		heading:                      heading
		hidden:                       low.hidden
		hyperlink_config:             hyperlink_config
		ignore_file:                  low.ignore_file
		ignore_file_case_insensitive: low.ignore_file_case_insensitive
		include_zero:                 low.include_zero
		invert_match:                 low.invert_match
		is_terminal_stdout:           state.is_terminal_stdout
		line_number:                  line_number
		max_columns:                  low.max_columns
		max_columns_preview:          low.max_columns_preview
		max_count:                    low.max_count
		max_depth:                    low.max_depth
		max_filesize:                 low.max_filesize
		mmap_choice:                  mmap_choice_value
		multiline:                    low.multiline
		multiline_dotall:             low.multiline_dotall
		no_ignore_dot:                low.no_ignore_dot
		no_ignore_exclude:            low.no_ignore_exclude
		no_ignore_files:              low.no_ignore_files
		no_ignore_global:             low.no_ignore_global
		no_ignore_parent:             low.no_ignore_parent
		no_ignore_vcs:                low.no_ignore_vcs
		no_require_git:               low.no_require_git
		no_unicode:                   low.no_unicode
		null_data:                    low.null_data
		one_file_system:              low.one_file_system
		only_matching:                low.only_matching
		globs:                        globs_value
		path_separator:               low.path_separator
		path_terminator:              path_terminator
		pre:                          low.pre
		pre_globs:                    pre_globs_value
		quiet:                        low.quiet
		quit_after_match:             quit_after_match
		regex_size_limit:             low.regex_size_limit
		replace:                      low.replace
		search_zip:                   low.search_zip
		sort:                         low.sort
		stats:                        stats_value
		stop_on_nonmatch:             low.stop_on_nonmatch
		threads:                      threads
		trim:                         low.trim
		types:                        types_value
		vimgrep:                      low.vimgrep
		with_filename:                with_filename
	}
}

/// Return a properly configured builder for constructing haystacks.
///
/// The builder can be used to turn a directory entry (from the `ignore`
/// crate) into something that can be searched.
pub fn (args HiArgs) haystack_builder() core.HaystackBuilder {
	mut builder := core.HaystackBuilder.new()
	builder.strip_dot_prefix(args.paths.has_implicit_path)
	return builder
}

/// Return the matcher that should be used for searching using the engine
/// choice made by the user.
///
/// If there was a problem building the matcher (e.g., a syntax error),
/// then this returns an error.
pub fn (args HiArgs) matcher() !core.PatternMatcher {
	match args.engine {
		.default {
			matcher_ := args.matcher_rust() or { return error(suggest_other_engine(err.msg())) }
			return matcher_
		}
		.pcre2 {
			return args.matcher_pcre2()
		}
		.auto {
			rust_err := if matcher_ := args.matcher_rust() {
				return matcher_
			} else {
				err.msg()
			}
			pcre_err := if matcher_ := args.matcher_pcre2() {
				return matcher_
			} else {
				err.msg()
			}
			divider := '~'.repeat(79)
			return error('regex could not be compiled with either the default regex engine or with PCRE2.\n\n' +
				'default regex engine error:\n' + '${divider}\n' + '${rust_err}\n' +
				'${divider}\n\n' + 'PCRE2 regex engine error:\n${pcre_err}')
		}
	}
}

/// Build a matcher using PCRE2.
///
/// If there was a problem building the matcher (such as a regex syntax
/// error), then an error is returned.
///
/// If the `pcre2` feature is not enabled then this always returns an
/// error.
fn (args HiArgs) matcher_pcre2() !core.PatternMatcher {
	mut builder := pcre2.RegexMatcherBuilder.new()
	builder.multi_line(true)
	builder.fixed_strings(args.fixed_strings)
	match args.case {
		.sensitive { builder.caseless(false) }
		.insensitive { builder.caseless(true) }
		.smart { builder.case_smart(true) }
	}
	if boundary := args.boundary {
		match boundary {
			.line { builder.whole_line(true) }
			.word { builder.word(true) }
		}
	}
	$if x64 {
		builder.jit_if_available(true)
		// The PCRE2 docs say that 32KB is the default, and that 1MB
		// should be big enough for anything. But let's crank it to
		// 10MB.
		builder.max_jit_stack_size(10 * (1 << 20))
	}
	if !args.no_unicode {
		builder.utf(true)
		builder.ucp(true)
	}
	if args.multiline {
		builder.dotall(args.multiline_dotall)
	}
	if args.crlf {
		builder.crlf(true)
	}
	m := builder.build_many(args.patterns.patterns)!
	return core.PatternMatcher.pcre2(m)
}

/// Build a matcher using Rust's regex engine.
///
/// If there was a problem building the matcher (such as a regex syntax
/// error), then an error is returned.
fn (args HiArgs) matcher_rust() !core.PatternMatcher {
	mut builder := regex.RegexMatcherBuilder.new()
	builder.multi_line(true)
	builder.unicode(!args.no_unicode)
	builder.octal(false)
	builder.fixed_strings(args.fixed_strings)
	match args.case {
		.sensitive { builder.case_insensitive(false) }
		.insensitive { builder.case_insensitive(true) }
		.smart { builder.case_smart(true) }
	}
	if boundary := args.boundary {
		match boundary {
			.line { builder.whole_line(true) }
			.word { builder.word(true) }
		}
	}
	if args.multiline {
		builder.dot_matches_new_line(args.multiline_dotall)
		if args.crlf {
			builder.crlf(true)
			builder.line_terminator(none)
		}
	} else {
		builder.line_terminator(`\n`)
		builder.dot_matches_new_line(false)
		if args.crlf {
			builder.crlf(true)
		}
		// We don't need to set this in multiline mode since multiline
		// matchers don't use optimizations related to line terminators.
		// Moreover, a multiline regex used with --null-data should
		// be allowed to match NUL bytes explicitly, which this would
		// otherwise forbid.
		if args.null_data {
			builder.line_terminator(`\0`)
		}
	}
	if limit := args.regex_size_limit {
		builder.size_limit(limit)
	}
	if limit := args.dfa_size_limit {
		builder.dfa_size_limit(limit)
	}
	if !args.binary.is_none() {
		builder.ban_byte(`\0`)
	}
	m := builder.build_many(args.patterns.patterns) or {
		return error(suggest_text(suggest_multiline(err.msg())))
	}
	return core.PatternMatcher.rust_regex(m)
}

/// Returns a writer for printing buffers to stdout.
///
/// This is intended to be used from multiple threads. Namely, a buffer
/// writer can create new buffers that are sent to threads. Threads can
/// then independently write to the buffers. Once a unit of work is
/// complete, a buffer can be given to the buffer writer to write to
/// stdout.
pub fn (args HiArgs) buffer_writer() cli.BufferWriter {
	mut wtr := cli.BufferWriter.stdout(args.color.to_cli_color_choice())
	wtr.separator(optional_bytes_clone(args.file_separator))
	return wtr
}

/// Returns true when ripgrep had to guess to search the current working
/// directory. That is, it's true when ripgrep is called without any file
/// paths or directories to search.
///
/// Other than changing how file paths are printed (i.e., without the
/// leading `./`), it's also useful to know for diagnostic reasons. For
/// example, ripgrep will print an error message when nothing is searched
/// since it's possible the ignore rules in play are too aggressive. But
/// this warning is only emitted when ripgrep was called without any
/// explicit file paths since otherwise the warning would likely be too
/// aggressive.
pub fn (args HiArgs) has_implicit_path() bool {
	return args.paths.has_implicit_path
}

/// Returns true if some non-zero number of matches is believed to be
/// possible.
///
/// When this returns false, it is impossible for ripgrep to ever report
/// a match.
pub fn (args HiArgs) matches_possible() bool {
	if args.patterns.patterns.len == 0 && !args.invert_match {
		return false
	}
	if max_count := args.max_count {
		if max_count == 0 {
			return false
		}
	}
	return true
}

/// Returns the "mode" that ripgrep should operate in.
///
/// This is generally useful for determining what action ripgrep should
/// take. The main mode is of course to "search," but there are other
/// non-search modes such as `--type-list` and `--files`.
pub fn (args HiArgs) mode() Mode {
	return args.mode
}

/// Returns a builder for constructing a "path printer."
///
/// This is useful for the `--files` mode in ripgrep, where the printer
/// just needs to emit paths and not need to worry about the functionality
/// of searching.
pub fn (args HiArgs) path_printer_builder() printer.PathPrinterBuilder {
	mut builder := printer.PathPrinterBuilder.new()
	builder.color_specs(args.colors.clone())
	builder.hyperlink(args.hyperlink_config.clone())
	builder.separator(args.path_separator)
	builder.terminator(args.path_terminator or { u8(`\n`) })
	return builder
}

/// Returns a printer for the given search mode.
///
/// This chooses which printer to build (JSON, summary or standard) based
/// on the search mode given.
pub fn (args HiArgs) printer[W](search_mode SearchMode, wtr W) core.Printer[W] {
	summary_kind := if args.quiet {
		match search_mode {
			.files_with_matches, .count, .count_matches, .json, .standard {
				printer.SummaryKind.quiet_with_match
			}
			.files_without_match {
				printer.SummaryKind.quiet_without_match
			}
		}
	} else {
		match search_mode {
			.files_with_matches { printer.SummaryKind.path_with_match }
			.files_without_match { printer.SummaryKind.path_without_match }
			.count { printer.SummaryKind.count }
			.count_matches { printer.SummaryKind.count_matches }
			.json {
				return core.Printer.json(args.printer_json(wtr))
			}
			.standard {
				return core.Printer.standard(args.printer_standard(wtr))
			}
		}
	}
	return core.Printer.summary(args.printer_summary(wtr, summary_kind))
}

/// Builds a JSON printer.
fn (args HiArgs) printer_json[W](wtr W) printer.JSON[W] {
	mut builder := printer.JSONBuilder.new()
	builder.pretty(false)
	builder.always_begin_end(false)
	builder.replacement(args.replacement_bytes())
	return builder.build(wtr)
}

/// Builds a "standard" grep printer where matches are printed as plain
/// text lines.
fn (args HiArgs) printer_standard[W](wtr W) printer.Standard[W] {
	mut builder := printer.StandardBuilder.new()
	builder.byte_offset(args.byte_offset)
	builder.color_specs(args.colors.clone())
	builder.column(args.column)
	builder.heading(args.heading)
	builder.hyperlink(args.hyperlink_config.clone())
	builder.max_columns_preview(args.max_columns_preview)
	builder.max_columns(args.max_columns)
	builder.only_matching(args.only_matching)
	builder.path(args.with_filename)
	builder.path_terminator(args.path_terminator)
	builder.per_match_one_line(true)
	builder.per_match(args.vimgrep)
	builder.replacement(args.replacement_bytes())
	builder.separator_context(args.context_separator.into_bytes())
	builder.separator_field_context(args.field_context_separator.into_bytes())
	builder.separator_field_match(args.field_match_separator.into_bytes())
	builder.separator_path(args.path_separator)
	builder.stats(args.stats != none)
	builder.trim_ascii(args.trim)
	// When doing multi-threaded searching, the buffer writer is
	// responsible for writing separators since it is the only thing that
	// knows whether something has been printed or not. But for the single
	// threaded case, we don't use a buffer writer and thus can let the
	// printer own this.
	if args.threads == 1 {
		builder.separator_search(optional_bytes_clone(args.file_separator))
	}
	return builder.build(wtr)
}

/// Builds a "summary" printer where search results are aggregated on a
/// file-by-file basis.
fn (args HiArgs) printer_summary[W](wtr W, kind printer.SummaryKind) printer.Summary[W] {
	mut builder := printer.SummaryBuilder.new()
	builder.color_specs(args.colors.clone())
	builder.exclude_zero(!args.include_zero)
	builder.hyperlink(args.hyperlink_config.clone())
	builder.kind(kind)
	builder.path(args.with_filename)
	builder.path_terminator(args.path_terminator)
	builder.separator_field(':'.bytes())
	builder.separator_path(args.path_separator)
	builder.stats(args.stats != none)
	return builder.build(wtr)
}

fn (args HiArgs) replacement_bytes() ?[]u8 {
	if replacement := args.replace {
		return replacement.bytes()
	}
	return none
}

fn optional_bytes_clone(value ?[]u8) ?[]u8 {
	if bytes := value {
		return bytes.clone()
	}
	return none
}

fn optional_string_clone(value ?string) ?string {
	if text := value {
		return text.clone()
	}
	return none
}

/// Returns true if ripgrep should operate in "quiet" mode.
///
/// Generally speaking, quiet mode means that ripgrep should not print
/// anything to stdout. There are some exceptions. For example, when the
/// user has provided `--stats`, then ripgrep will print statistics to
/// stdout.
pub fn (args HiArgs) quiet() bool {
	return args.quiet
}

/// Returns true when ripgrep should stop searching after a single match is
/// found.
///
/// This is useful for example when quiet mode is enabled. In that case,
/// users generally can't tell the difference in behavior between a search
/// that finds all matches and a search that only finds one of them. (An
/// exception here is if `--stats` is given, then `quit_after_match` will
/// always return false since the user expects ripgrep to find everything.)
pub fn (args HiArgs) quit_after_match() bool {
	return args.quit_after_match
}

/// Build a worker for executing searches.
///
/// Search results are found using the given matcher and written to the
/// given printer.
pub fn (args HiArgs) search_worker[W](matcher_ core.PatternMatcher, searcher_ searcher.Searcher, printer_ core.Printer[W]) !core.SearchWorker[W] {
	mut builder := core.SearchWorkerBuilder.new()
	builder.preprocessor(optional_string_clone(args.pre))!
	builder.preprocessor_globs(args.pre_globs.clone())
	builder.search_zip(args.search_zip)
	builder.binary_detection_explicit(args.binary.explicit.clone())
	builder.binary_detection_implicit(args.binary.implicit.clone())
	return builder.build(matcher_, searcher_, printer_)
}

/// Build a searcher from the command line parameters.
pub fn (args HiArgs) searcher() !searcher.Searcher {
	line_term := if args.crlf {
		matcher.LineTerminator.crlf()
	} else if args.null_data {
		matcher.LineTerminator.byte(`\0`)
	} else {
		matcher.LineTerminator.byte(`\n`)
	}
	mut builder := searcher.SearcherBuilder.new()
	builder.max_matches(args.max_count)
	builder.line_terminator(line_term)
	builder.invert_match(args.invert_match)
	builder.line_number(args.line_number)
	builder.multi_line(args.multiline)
	builder.memory_map(args.mmap_choice.clone())
	builder.stop_on_nonmatch(args.stop_on_nonmatch)
	match args.context.kind {
		.passthru {
			builder.passthru(true)
		}
		.limited {
			before, after := args.context.limited.get()
			builder.before_context(before)
			builder.after_context(after)
		}
	}
	match args.encoding.kind {
		.auto {}
		.some {
			encoding := searcher.Encoding.new(args.encoding.encoding.label)!
			builder.encoding(encoding)
		}
		.disabled {
			builder.bom_sniffing(false)
		}
	}
	return builder.build()
}

/// Given an iterator of haystacks, sort them if necessary.
///
/// When sorting is necessary, this will collect the entire iterator into
/// memory, sort them and then return a new iterator. When sorting is not
/// necessary, then the iterator given is returned as is without collecting
/// it into memory.
///
/// Once special case is when sorting by path in ascending order has been
/// requested. In this case, the iterator given is returned as is without
/// any additional sorting. This is done because `walk_builder()` will sort
/// the iterator it yields during directory traversal, so no additional
/// sorting is needed.
pub fn (args HiArgs) sort(haystacks []core.Haystack) []core.Haystack {
	sort := args.sort or { return haystacks }
	if sort.kind == .path && !sort.reverse {
		return haystacks
	}
	mut sorted := haystacks.clone()
	if sort.kind == .path {
		sorted.sort_with_compare(fn (a &core.Haystack, b &core.Haystack) int {
			ap := *a.path()
			bp := *b.path()
			if ap < bp {
				return 1
			}
			if ap > bp {
				return -1
			}
			return 0
		})
		return sorted
	}
	sorted.sort_with_compare(fn [sort] (a &core.Haystack, b &core.Haystack) int {
		atime := sort_key_for_haystack(a, sort.kind)
		btime := sort_key_for_haystack(b, sort.kind)
		ordering := compare_optional_time(atime, btime)
		if sort.reverse {
			return -ordering
		}
		return ordering
	})
	return sorted
}

/// Returns a stats object if the user requested that ripgrep keep track
/// of various metrics during a search.
///
/// When this returns `None`, then callers may assume that the user did
/// not request statistics.
pub fn (args HiArgs) stats() ?printer.Stats {
	return args.stats
}

/// Returns a color-enabled writer for stdout.
///
/// The writer returned is also configured to do either line or block
/// buffering, based on either explicit configuration from the user via CLI
/// flags, or automatically based on whether stdout is connected to a tty.
pub fn (args HiArgs) stdout() cli.StandardStream {
	color := args.color.to_cli_color_choice()
	match args.buffer {
		.auto {
			if args.is_terminal_stdout {
				return cli.stdout_buffered_line(color)
			}
			return cli.stdout_buffered_block(color)
		}
		.line { return cli.stdout_buffered_line(color) }
		.block { return cli.stdout_buffered_block(color) }
	}
}

/// Returns the total number of threads ripgrep should use to execute a
/// search.
///
/// This number is the result of reasoning about both heuristics (like
/// the available number of cores) and whether ripgrep's mode supports
/// parallelism. It is intended that this number be used to directly
/// determine how many threads to spawn.
pub fn (args HiArgs) threads() usize {
	return args.threads
}

/// Returns the file type matcher that was built.
///
/// The matcher includes both the default rules and any rules added by the
/// user for this specific invocation.
pub fn (args &^a HiArgs) types[^a]() &^a ignore.Types {
	return &args.types
}

/// Create a new builder for recursive directory traversal.
///
/// The builder returned can be used to start a single threaded or multi
/// threaded directory traversal. For multi threaded traversal, the number
/// of threads configured is equivalent to `HiArgs::threads`.
///
/// If `HiArgs::threads` is equal to `1`, then callers should generally
/// choose to explicitly use single threaded traversal since it won't have
/// the unnecessary overhead of synchronization.
pub fn (args HiArgs) walk_builder() !ignore.WalkBuilder {
	if args.paths.paths.len == 0 {
		return error('expected at least one path')
	}
	mut builder := ignore.WalkBuilder.new(args.paths.paths[0])
	for path in args.paths.paths[1..] {
		builder.add(path)
	}
	if !args.no_ignore_files {
		for path in args.ignore_file {
			has_err, err := builder.add_ignore(path)
			if has_err {
				// V-specific: the translated flags module cannot import the
				// parent `core` module when compiled directly with V2 tests.
				// Preserve the non-fatal behavior here; the message hook will be
				// restored when the crate-level module layout is translated.
				_ = err
			}
		}
	}
	if depth := args.max_depth {
		builder.max_depth(int(depth))
	} else {
		builder.max_depth(-1)
	}
	builder.follow_links(args.follow)
	if filesize := args.max_filesize {
		builder.max_filesize(filesize)
	} else {
		builder.clear_max_filesize()
	}
	builder.threads(int(args.threads))
	builder.same_file_system(args.one_file_system)
	builder.skip_stdout(args.mode.kind == .search)
	builder.overrides(args.globs.clone())
	builder.types(args.types.clone())
	builder.hidden(!args.hidden)
	builder.parents(!args.no_ignore_parent)
	builder.ignore(!args.no_ignore_dot)
	builder.git_global(!args.no_ignore_vcs && !args.no_ignore_global)
	builder.git_ignore(!args.no_ignore_vcs)
	builder.git_exclude(!args.no_ignore_vcs && !args.no_ignore_exclude)
	builder.require_git(!args.no_require_git)
	builder.ignore_case_insensitive(args.ignore_file_case_insensitive)
	builder.current_dir(args.cwd)
	if !args.no_ignore_dot {
		builder.add_custom_ignore_filename('.rgignore')
	}
	// When we want to sort paths lexicographically in ascending order,
	// then we can actually do this during directory traversal itself.
	// Otherwise, sorting is done by collecting all paths, sorting them and
	// then searching them.
	if sort := args.sort {
		if args.threads != 1 {
			panic('sorting implies single threaded')
		}
		if !sort.reverse && sort.kind == .path {
			builder.sort_by_file_name(name_cmp_asc)
		}
	}
	return builder
}

/// State that only needs to be computed once during argument parsing.
///
/// This state is meant to be somewhat generic and shared across multiple
/// low->high argument conversions. The state can even be mutated by various
/// conversions as a way to communicate changes to other conversions. For
/// example, reading patterns might consume from stdin. If we know stdin
/// has been consumed and no other file paths have been given, then we know
/// for sure that we should search the CWD. In this way, a state change
/// when reading the patterns can impact how the file paths are ultimately
/// generated.
struct State {
	/// Whether it's believed that tty is connected to stdout. Note that on
	/// unix systems, this is always correct. On Windows, heuristics are used
	/// by Rust's standard library, particularly for cygwin/MSYS environments.
	is_terminal_stdout bool
	/// Whether stdin has already been consumed. This is useful to know and for
	/// providing good error messages when the user has tried to read from stdin
	/// in two different places. For example, `rg -f - -`.
mut:
	stdin_consumed bool
	/// The current working directory.
	cwd string
}

/// Initialize state to some sensible defaults.
///
/// Note that the state values may change throughout the lifetime of
/// argument parsing.
fn State.new() !State {
	cwd := current_dir()!
	return State{
		is_terminal_stdout: cli.is_tty_stdout()
		stdin_consumed:    false
		cwd:               cwd
	}
}

/// The disjunction of patterns to search for.
///
/// The number of patterns can be empty, e.g., via `-f /dev/null`.
struct Patterns {
	/// The actual patterns to match.
	patterns []string
}

/// Pulls the patterns out of the low arguments.
///
/// This includes collecting patterns from -e/--regexp and -f/--file.
///
/// If the invocation implies that the first positional argument is a
/// pattern (the common case), then the first positional argument is
/// extracted as well.
fn Patterns.from_low_args(mut state State, mut low LowArgs) !Patterns {
	// The first positional is only a pattern when ripgrep is instructed to
	// search and neither -e/--regexp nor -f/--file is given. Basically,
	// the first positional is a pattern only when a pattern hasn't been
	// given in some other way.

	// No search means no patterns. Even if -e/--regexp or -f/--file is
	// given, we know we won't use them so don't bother collecting them.
	if low.mode.kind != .search {
		return Patterns{
			patterns: []string{}
		}
	}
	// If we got nothing from -e/--regexp and -f/--file, then the first
	// positional is a pattern.
	if low.patterns.len == 0 {
		if low.positional.len == 0 {
			return error('ripgrep requires at least one pattern to execute a search')
		}
		pat := low.positional[0].clone()
		low.positional.delete(0)
		return Patterns{
			patterns: [pat]
		}
	}
	// Otherwise, we need to slurp up our patterns from -e/--regexp and
	// -f/--file. We de-duplicate as we go. If we don't de-duplicate,
	// then it can actually lead to major slow downs for sloppy inputs.
	// This might be surprising, and the regex engine will eventually
	// de-duplicate duplicative branches in a single regex (maybe), but
	// not until after it has gone through parsing and some other layers.
	// If there are a lot of duplicates, then that can lead to a sizeable
	// extra cost. It is lamentable that we pay the extra cost here to
	// de-duplicate for a likely uncommon case, but I've seen this have a
	// big impact on real world data.
	mut seen := map[string]bool{}
	mut patterns := []string{cap: low.patterns.len}
	for source in low.patterns {
		match source.kind {
			.regexp {
				add_pattern(mut seen, mut patterns, source.value)
			}
			.file {
				if source.value == '-' {
					if state.stdin_consumed {
						return error('error reading -f/--file from stdin: stdin has already been consumed')
					}
					for pat in cli.patterns_from_stdin()! {
						add_pattern(mut seen, mut patterns, pat)
					}
					state.stdin_consumed = true
				} else {
					for pat in cli.patterns_from_path(source.value)! {
						add_pattern(mut seen, mut patterns, pat)
					}
				}
			}
		}
	}
	low.patterns = []PatternSource{}
	return Patterns{
		patterns: patterns
	}
}

/// The collection of paths we want to search for.
///
/// This guarantees that there is always at least one path.
struct Paths {
	/// The actual paths.
	paths []string
	/// This is true when ripgrep had to guess to search the current working
	/// directory. e.g., When the user just runs `rg foo`. It is odd to need
	/// this, but it subtly changes how the paths are printed. When no explicit
	/// path is given, then ripgrep doesn't prefix each path with `./`. But
	/// otherwise it does! This curious behavior matches what GNU grep does.
	has_implicit_path bool
	/// Set to true if it is known that only a single file descriptor will
	/// be searched.
	is_one_file bool
}

/// Drain the search paths out of the given low arguments.
fn Paths.from_low_args(mut state State, _ Patterns, mut low LowArgs) !Paths {
	// We require a `&Patterns` even though we don't use it to ensure that
	// patterns have already been read from LowArgs. This let's us safely
	// assume that all remaining positional arguments are intended to be
	// file paths.

	mut paths := []string{cap: low.positional.len}
	for path in low.positional {
		if state.stdin_consumed && path == '-' {
			return error('error: attempted to read patterns from stdin while also searching stdin')
		}
		paths << path.clone()
	}
	low.positional = []string{}
	if paths.len > 0 {
		is_one_file := paths.len == 1
			// Note that we specifically use `!paths[0].is_dir()` here
			// instead of `paths[0].is_file()`. Namely, the latter can
			// return `false` even when the path is something resembling
			// a file. So instead, we just consider the path a file as
			// long as we know it isn't a directory.
			//
			// See: https://github.com/BurntSushi/ripgrep/issues/2736
			&& (paths[0] == '-' || !os.is_dir(paths[0]))
		return Paths{
			paths:             paths
			has_implicit_path: false
			is_one_file:       is_one_file
		}
	}
	// N.B. is_readable_stdin is a heuristic! Part of the issue is that a
	// lot of "exec process" APIs will open a stdin pipe even though stdin
	// isn't really being used. ripgrep then thinks it should search stdin
	// and one gets the appearance of it hanging. It's a terrible failure
	// mode, but there really is no good way to mitigate it. It's just a
	// consequence of letting the user type 'rg foo' and "guessing" that
	// they meant to search the CWD.
	is_readable_stdin := cli.is_readable_stdin()
	use_cwd := !is_readable_stdin || state.stdin_consumed || low.mode.kind != .search
	path, is_one_file := if use_cwd { './', false } else { '-', true }
	return Paths{
		paths:             [path]
		has_implicit_path: true
		is_one_file:       is_one_file
	}
}

/// Returns true if ripgrep will only search stdin and nothing else.
fn (paths Paths) is_only_stdin() bool {
	return paths.paths.len == 1 && paths.paths[0] == '-'
}

/// The "binary detection" configuration that ripgrep should use.
///
/// ripgrep actually uses two different binary detection heuristics depending
/// on whether a file is explicitly being searched (e.g., via a CLI argument)
/// or implicitly searched (e.g., via directory traversal). In general, the
/// former can never use a heuristic that lets it "quit" seaching before
/// either getting EOF or finding a match. (Because doing otherwise would be
/// considered a filter, and ripgrep follows the rule that an explicitly given
/// file is always searched.)
struct BinaryDetection {
	explicit searcher.BinaryDetection
	implicit searcher.BinaryDetection
}

/// Determines the correct binary detection mode from low-level arguments.
fn BinaryDetection.from_low_args(_ State, low LowArgs) BinaryDetection {
	disabled := low.binary == .as_text || low.null_data
	convert := low.binary == .search_and_suppress
	explicit := if disabled {
		searcher.BinaryDetection.disabled()
	} else {
		searcher.BinaryDetection.convert(`\0`)
	}
	implicit := if disabled {
		searcher.BinaryDetection.disabled()
	} else if convert {
		searcher.BinaryDetection.convert(`\0`)
	} else {
		searcher.BinaryDetection.quit(`\0`)
	}
	return BinaryDetection{
		explicit: explicit
		implicit: implicit
	}
}

/// Returns true when both implicit and explicit binary detection is
/// disabled.
fn (binary BinaryDetection) is_none() bool {
	return binary.explicit.quit_byte() == none && binary.explicit.convert_byte() == none
		&& binary.implicit.quit_byte() == none && binary.implicit.convert_byte() == none
}

/// Builds the file type matcher from low level arguments.
fn types(low LowArgs) !ignore.Types {
	mut builder := ignore.TypesBuilder.new()
	builder.add_defaults()
	for tychange in low.type_changes {
		match tychange.kind {
			.clear {
				builder.clear(tychange.name)
			}
			.add {
				has_err, err := builder.add_def(tychange.def)
				if has_err {
					return error(err.msg())
				}
			}
			.select {
				builder.select(tychange.name)
			}
			.negate {
				builder.negate(tychange.name)
			}
		}
	}
	types_value, has_err, err := builder.build()
	if has_err {
		return error(err.msg())
	}
	return types_value
}

/// Builds the glob "override" matcher from the CLI `-g/--glob` and `--iglob`
/// flags.
fn globs(state State, low LowArgs) !ignore.Override {
	if low.globs.len == 0 && low.iglobs.len == 0 {
		return ignore.Override.empty()
	}
	mut builder := ignore.OverrideBuilder.new(state.cwd)
	// Make all globs case insensitive with --glob-case-insensitive.
	if low.glob_case_insensitive {
		has_err, err := builder.case_insensitive(true)
		if has_err {
			return error(err.msg())
		}
	}
	for glob in low.globs {
		has_err, err := builder.add(glob)
		if has_err {
			return error(err.msg())
		}
	}
	// This only enables case insensitivity for subsequent globs.
	has_case_err, case_err := builder.case_insensitive(true)
	if has_case_err {
		return error(case_err.msg())
	}
	for glob in low.iglobs {
		has_err, err := builder.add(glob)
		if has_err {
			return error(err.msg())
		}
	}
	overrides, has_err, err := builder.build()
	if has_err {
		return error(err.msg())
	}
	return overrides
}

/// Builds a glob matcher for all of the preprocessor globs (via `--pre-glob`).
fn preprocessor_globs(state State, low LowArgs) !ignore.Override {
	if low.pre_glob.len == 0 {
		return ignore.Override.empty()
	}
	mut builder := ignore.OverrideBuilder.new(state.cwd)
	for glob in low.pre_glob {
		has_err, err := builder.add(glob)
		if has_err {
			return error(err.msg())
		}
	}
	overrides, has_err, err := builder.build()
	if has_err {
		return error(err.msg())
	}
	return overrides
}

/// Determines whether stats should be tracked for this search. If so, a stats
/// object is returned.
fn stats(low LowArgs) ?printer.Stats {
	if low.mode.kind != .search {
		return none
	}
	if low.stats || (low.mode.kind == .search && low.mode.search == .json) {
		return printer.Stats.new()
	}
	return none
}

/// Pulls out any color specs provided by the user and assembles them into one
/// single configuration.
fn take_color_specs(mut state State, mut low LowArgs) !printer.ColorSpecs {
	_ = state
	mut specs := printer.default_color_specs()
	for spec in low.colors {
		specs << printer.parse_user_color_spec(spec.spec)!
	}
	low.colors = []UserColorSpec{}
	return printer.ColorSpecs.new(specs)
}

/// Pulls out the necessary info from the low arguments to build a full
/// hyperlink configuration.
fn take_hyperlink_config(mut state State, mut low LowArgs) !printer.HyperlinkConfig {
	_ = state
	mut env := printer.HyperlinkEnvironment.new()
	if hostname_value := hostname(low.hostname_bin) {
		env.host(hostname_value)
	}
	if wsl_prefix_value := wsl_prefix() {
		env.wsl_prefix(wsl_prefix_value)
	}
	fmt := printer.parse_hyperlink_format(low.hyperlink_format.format)!
	low.hyperlink_format = HyperlinkFormat{}
	return printer.HyperlinkConfig.new(env, fmt)
}

/// Attempts to discover the current working directory.
///
/// This mostly just defers to the standard library, however, such things will
/// fail if ripgrep is in a directory that no longer exists. We attempt some
/// fallback mechanisms, such as querying the PWD environment variable, but
/// otherwise return an error.
fn current_dir() !string {
	cwd := os.getwd()
	if cwd != '' {
		return cwd
	}
	pwd := os.getenv('PWD')
	if pwd != '' {
		return pwd
	}
	return error('failed to get current working directory: did your CWD get deleted?')
}

/// Retrieves the hostname that should be used wherever a hostname is required.
///
/// Currently, this is only used in the hyperlink format.
///
/// This works by first running the given binary program (if present and with
/// no arguments) to get the hostname after trimming leading and trailing
/// whitespace. If that fails for any reason, then it falls back to getting the
/// hostname via platform specific means (e.g., `gethostname` on Unix).
///
/// The purpose of `bin` is to make it possible for end users to override how
/// ripgrep determines the hostname.
fn hostname(bin ?string) ?string {
	if bin_value := bin {
		result := os.execute(bin_value)
		if result.exit_code == 0 {
			hostname_value := result.output.trim_space()
			if hostname_value != '' {
				return hostname_value
			}
		}
	}
	return platform_hostname()
}

/// Attempts to get the hostname by using platform specific routines.
///
/// For example, this will do `gethostname` on Unix and `GetComputerNameExW` on
/// Windows.
fn platform_hostname() ?string {
	hostname_value := cli.hostname() or { return none }
	if hostname_value == '' {
		return none
	}
	return hostname_value
}

/// Returns the value for the `{wslprefix}` variable in a hyperlink format.
///
/// A WSL prefix is a share/network like thing that is meant to permit Windows
/// applications to open files stored within a WSL drive.
///
/// If a WSL distro name is unavailable, not valid UTF-8 or this isn't running
/// in a Unix environment, then this returns None.
///
/// See: <https://learn.microsoft.com/en-us/windows/wsl/filesystems>
fn wsl_prefix() ?string {
	$if !unix {
		return none
	}
	distro := os.getenv('WSL_DISTRO_NAME')
	if distro == '' {
		return none
	}
	return 'wsl' + '$/' + distro
}

fn add_pattern(mut seen map[string]bool, mut patterns []string, pat string) {
	if pat in seen {
		return
	}
	seen[pat] = true
	patterns << pat.clone()
}

fn default_thread_count() usize {
	cpus := runtime.nr_cpus()
	if cpus <= 0 {
		return 1
	}
	if cpus > 12 {
		return 12
	}
	return usize(cpus)
}

fn compute_mmap_choice(mode MmapMode, paths Paths) searcher.MmapChoice {
	maybe := searcher.MmapChoice.auto()
	never := searcher.MmapChoice.never()
	match mode {
		.auto {
			if paths.paths.len <= 10 && paths.paths.all(os.is_file(it)) {
				// If we're only searching a few paths and all of them
				// are files, then memory maps are probably faster.
				return maybe
			}
			return never
		}
		.always_try_mmap {
			return maybe
		}
		.never {
			return never
		}
	}
}

fn (choice ColorChoice) to_cli_color_choice() cli.ColorChoice {
	return match choice {
		.never { cli.ColorChoice.never }
		.auto { cli.ColorChoice.auto }
		.always { cli.ColorChoice.always }
		.ansi { cli.ColorChoice.ansi }
	}
}

fn name_cmp_asc(a string, b string) int {
	if a < b {
		return -1
	}
	if a > b {
		return 1
	}
	return 0
}

fn sort_key_for_haystack(hay &core.Haystack, kind SortModeKind) ?i64 {
	stat := os.stat(*hay.path()) or { return none }
	match kind {
		.path {
			return none
		}
		.last_modified {
			return stat.mtime
		}
		.last_accessed {
			return stat.atime
		}
		.created {
			// V-specific: V's portable `os.Stat` surface exposes status-change
			// time here, not creation time. `SortMode.supported` is where this
			// can be tightened once birth time is available from the local V stdlib.
			return stat.ctime
		}
	}
}

fn compare_optional_time(left ?i64, right ?i64) int {
	if l := left {
		if r := right {
			if l < r {
				return -1
			}
			if l > r {
				return 1
			}
			return 0
		}
		// Things that error should appear later (when ascending).
		return -1
	}
	if _ := right {
		// Things that error should appear later (when ascending).
		return 1
	}
	// When both error, we can't distinguish, so treat as equal.
	return 0
}

/// Possibly suggest another regex engine based on the error message given.
///
/// This inspects an error resulting from building a Rust regex matcher, and
/// if it's believed to correspond to a syntax error that another engine could
/// handle, then add a message to suggest the use of the engine flag.
fn suggest_other_engine(msg string) string {
	if pcre_msg := suggest_pcre2(msg) {
		return pcre_msg
	}
	return msg
}

/// Possibly suggest PCRE2 based on the error message given.
///
/// Inspect an error resulting from building a Rust regex matcher, and if it's
/// believed to correspond to a syntax error that PCRE2 could handle, then
/// add a message to suggest the use of -P/--pcre2.
fn suggest_pcre2(msg string) ?string {
	if !msg.contains('backreferences') && !msg.contains('look-around') {
		return none
	}
	return '${msg}\n\nConsider enabling PCRE2 with the --pcre2 flag, which can handle backreferences\nand look-around.'
}

/// Possibly suggest multiline mode based on the error message given.
///
/// Does a bit of a hacky inspection of the given error message, and if it
/// looks like the user tried to type a literal line terminator then it will
/// return a new error message suggesting the use of -U/--multiline.
fn suggest_multiline(msg string) string {
	if msg.contains('the literal') && msg.contains('not allowed') {
		return '${msg}\n\nConsider enabling multiline mode with the --multiline flag (or -U for short).\nWhen multiline mode is enabled, new line characters can be matched.'
	}
	return msg
}

/// Possibly suggest the `-a/--text` flag.
fn suggest_text(msg string) string {
	if msg.contains('pattern contains "\\0"') {
		return '${msg}\n\nConsider enabling text mode with the --text flag (or -a for short). Otherwise,\nbinary detection is enabled and matching a NUL byte is impossible.'
	}
	return msg
}
