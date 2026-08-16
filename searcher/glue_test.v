module searcher

import io
import matcher
import regex
import regex.meta as regex_meta
import strings

const glue_sherlock = 'For the Doctor Watsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
be, to a very large extent, the result of luck. Sherlock Holmes
can extract a clew from a wisp of straw or a flake of cigar ash;
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.'

const glue_code = 'extern crate snap;

use std::io;

fn main() {
    let stdin = io::stdin();
    let stdout = io::stdout();

    // Wrap the stdin reader in a Snappy reader.
    let mut rdr = snap::Reader::new(stdin.lock());
    let mut wtr = stdout.lock();
    io::copy(&mut rdr, &mut wtr).expect("I/O operation failed");
}
'

struct GlueByteSliceReader {
mut:
	bytes []u8
	pos   int
}

fn GlueByteSliceReader.new(slice string) GlueByteSliceReader {
	return GlueByteSliceReader{
		bytes: slice.bytes()
	}
}

fn (mut rdr GlueByteSliceReader) read(mut buf []u8) !int {
	if rdr.pos >= rdr.bytes.len {
		return io.Eof{}
	}
	nread := copy(mut buf, rdr.bytes[rdr.pos..])
	rdr.pos += nread
	return nread
}

/// A simple regex matcher.
///
/// This supports setting the matcher's line terminator configuration directly,
/// which we use for testing purposes. That is, the caller explicitly
/// determines whether the line terminator optimization is enabled. (In reality
/// this optimization is detected automatically by inspecting and possibly
/// modifying the regex itself.)
struct RegexMatcher implements IClone, Drop {
	regex regex.RegexMatcher
mut:
	line_term               ?matcher.LineTerminator
	every_line_is_candidate bool
}

// V-specific: the translated regex matcher explicitly releases its owned
// matcher because that dependency implements `Drop`.
fn (mut m RegexMatcher) drop() {
	m.regex.drop()
}

/// Create a new regex matcher.
fn RegexMatcher.new(pattern string) RegexMatcher {
	mut builder := regex.RegexMatcherBuilder.new()
	builder.multi_line(true) // permits ^ and $ to match at \n boundaries
	regex_ := builder.build(pattern) or { panic(err) }
	return RegexMatcher{
		regex:                   regex_
		line_term:               none
		every_line_is_candidate: false
	}
}

/// Forcefully set the line terminator of this matcher.
///
/// By default, this matcher has no line terminator set.
fn (mut m RegexMatcher) set_line_term(line_term ?matcher.LineTerminator) &RegexMatcher {
	m.line_term = line_term
	return m
}

/// Whether to return every line as a candidate or not.
///
/// This forces searchers to handle the case of reporting a false positive.
fn (mut m RegexMatcher) every_line_is_candidate(yes bool) &RegexMatcher {
	m.every_line_is_candidate = yes
	return m
}

fn (m &RegexMatcher) find_at(haystack &[]u8, at usize) !matcher.FallibleMatch {
	return m.regex.find_at(haystack, at)!
}

fn (m &RegexMatcher) shortest_match_at(haystack &[]u8, at usize) !matcher.FallibleUsize {
	return m.regex.shortest_match_at(haystack, at)!
}

fn (m &RegexMatcher) new_captures() !matcher.NoCaptures {
	_ = m
	return matcher.NoCaptures.new()
}

fn (m &RegexMatcher) capture_count() usize {
	_ = m
	return 0
}

fn (m &RegexMatcher) capture_index(name string) ?usize {
	_ = m
	_ = name
	return none
}

fn (m &RegexMatcher) captures_at(haystack &[]u8, at usize, mut caps matcher.NoCaptures) !bool {
	_ = m
	_ = haystack
	_ = at
	_ = caps
	return false
}

fn (m &^a RegexMatcher) non_matching_bytes[^a]() ?&^a matcher.ByteSet {
	_ = m
	return none
}

fn (m &RegexMatcher) line_terminator() ?matcher.LineTerminator {
	return m.line_term
}

fn (m &RegexMatcher) find_candidate_line(haystack &[]u8) !matcher.FallibleLineMatchKind {
	if m.every_line_is_candidate {
		line_term := m.line_term or { panic('line terminator required') }
		if haystack.len == 0 {
			return matcher.FallibleLineMatchKind.absent()
		}
		// Make it interesting and return the last byte in the current
		// line.
		mut i := 0
		for i < haystack.len {
			if haystack[i] == line_term.as_byte() {
				return matcher.FallibleLineMatchKind.some(matcher.LineMatchKind.candidate(usize(i)))
			}
			i++
		}
		return matcher.FallibleLineMatchKind.some(matcher.LineMatchKind.candidate(usize(haystack.len - 1)))
	}
	maybe_mat := m.regex.find_at(haystack, 0)!
	if mat := maybe_mat.get() {
		return matcher.FallibleLineMatchKind.some(matcher.LineMatchKind.confirmed(mat.end()))
	}
	return matcher.FallibleLineMatchKind.absent()
}

/// An implementation of Sink that prints all available information.
///
/// This is useful for tests because it lets us easily confirm whether data
/// is being passed to Sink correctly.
struct KitchenSink implements IClone {
mut:
	bytes []u8
}

/// Create a new implementation of Sink that includes everything in the
/// kitchen.
fn KitchenSink.new() KitchenSink {
	return KitchenSink{
		bytes: []u8{}
	}
}

/// Return the data written to this sink.
fn (sink &^a KitchenSink) as_bytes[^a]() &^a []u8 {
	return &sink.bytes
}

fn (mut sink KitchenSink) write_str(s string) {
	sink.bytes << s.bytes()
}

fn (mut sink KitchenSink) matched[^b](searcher_ &Searcher, mat &SinkMatch[^b]) !bool {
	_ = searcher_
	assert mat.bytes().len > 0
	assert mat.lines().count() >= 1

	mut line_number := mat.line_number()
	mut byte_offset := mat.absolute_byte_offset()
	bytes := mat.bytes()
	mut step := LineStep.new(mat.line_term_.as_byte(), 0, bytes.len)
	for {
		start, end := step.next(bytes) or { break }
		if n := line_number {
			sink.write_str('${n}:')
			line_number = n + 1
		}
		sink.write_str('${byte_offset}:')
		byte_offset += u64(end - start)
		sink.bytes << bytes[start..end]
	}
	return true
}

fn (mut sink KitchenSink) context[^b](searcher_ &Searcher, ctx &SinkContext[^b]) !bool {
	_ = searcher_
	assert ctx.bytes().len > 0
	assert ctx.lines().count() == 1

	if line_number := ctx.line_number() {
		sink.write_str('${line_number}-')
	}
	sink.write_str('${ctx.absolute_byte_offset()}-')
	sink.bytes << ctx.bytes()
	return true
}

fn (mut sink KitchenSink) context_break(searcher_ &Searcher) !bool {
	_ = searcher_
	sink.write_str('--\n')
	return true
}

// V-specific implementations of the source `Sink` defaults required by V's
// sink interface.
fn (mut sink KitchenSink) binary_data(searcher_ &Searcher, binary_byte_offset u64) !bool {
	_ = searcher_
	_ = binary_byte_offset
	return true
}

fn (mut sink KitchenSink) begin(searcher_ &Searcher) !bool {
	_ = searcher_
	return true
}

fn (mut sink KitchenSink) finish(searcher_ &Searcher, sink_finish &SinkFinish) ! {
	_ = searcher_
	sink.write_str('\n')
	sink.write_str('byte count:${sink_finish.byte_count()}\n')
	if offset := sink_finish.binary_byte_offset() {
		sink.write_str('binary offset:${offset}\n')
	}
}

/// A type for expressing tests on a searcher.
///
/// The searcher code has a lot of different code paths, mostly for the
/// purposes of optimizing a bunch of different use cases. The intent of the
/// searcher is to pick the best code path based on the configuration, which
/// means there is no obviously direct way to ask that a specific code path
/// be exercised. Thus, the purpose of this tester is to explicitly check as
/// many code paths that make sense.
///
/// The tester works by assuming you want to test all pertinent code paths.
/// These can be trimmed down as necessary via the various builder methods.
struct SearcherTester {
	mut:
	haystack                        string
	pattern                         string
	filter                          ?regex_meta.Regex
	print_labels                    bool
	expected_no_line_number         ?string
	expected_with_line_number       ?string
	expected_slice_no_line_number   ?string
	expected_slice_with_line_number ?string
	by_line         bool
	multi_line      bool
	invert_match    bool
	line_number     bool
	binary          BinaryDetection
	auto_heap_limit bool
	after_context   usize
	before_context  usize
	passthru        bool
}

/// Create a new tester for testing searchers.
fn SearcherTester.new(haystack string, pattern string) SearcherTester {
	return SearcherTester{
		haystack:        haystack.to_owned()
		pattern:         pattern.to_owned()
		filter:          none
		print_labels:    false
		by_line:         true
		multi_line:      true
		invert_match:    false
		line_number:     true
		binary:          BinaryDetection.disabled()
		auto_heap_limit: true
		after_context:   0
		before_context:  0
		passthru:        false
	}
}

/// Execute the test. If the test succeeds, then this returns successfully.
/// If the test fails, then it panics with an informative message.
fn (tester &SearcherTester) test() {
	// Check for configuration errors.
	if tester.expected_no_line_number == none {
		panic("an 'expected' string with NO line numbers must be given")
	}
	if tester.line_number && tester.expected_with_line_number == none {
		panic("an 'expected' string with line numbers must be given, or disable testing with line numbers")
	}

	configs := tester.configs()
	if configs.len == 0 {
		panic('test configuration resulted in nothing being tested')
	}
	if tester.print_labels {
		for config in configs {
			labels := ['reader-${config.label}', 'slice-${config.label}']
			for label in labels {
				if tester.include(label.clone()) {
					println(label)
				} else {
					println('${label} (ignored)')
				}
			}
		}
	}
	for config in configs {
		label_reader := 'reader-${config.label}'
		if tester.include(label_reader) {
			got_reader := config.search_reader(tester.haystack)
			glue_assert_eq_printed(config.expected_reader, got_reader, label_reader)
		}

		label_slice := 'slice-${config.label}'
		if tester.include(label_slice) {
			got_slice := config.search_slice(tester.haystack)
			glue_assert_eq_printed(config.expected_slice, got_slice, label_slice)
		}
	}
}

/// Set a regex pattern to filter the tests that are run.
///
/// By default, no filter is present. When a filter is set, only test
/// configurations with a label matching the given pattern will be run.
///
/// This is often useful when debugging tests, e.g., when you want to do
/// printf debugging and only want one particular test configuration to
/// execute.
fn (mut tester SearcherTester) filter(pattern string) &SearcherTester {
	tester.filter = regex_meta.compile(pattern) or { panic(err) }
	return tester
}

/// When set, the labels for all test configurations are printed before
/// executing any test.
///
/// Note that in order to see these in tests that aren't failing, you'll
/// want to use `cargo test -- --nocapture`.
fn (mut tester SearcherTester) print_labels(yes bool) &SearcherTester {
	tester.print_labels = yes
	return tester
}

/// Set the expected search results, without line numbers.
fn (mut tester SearcherTester) expected_no_line_number(exp string) &SearcherTester {
	tester.expected_no_line_number = exp.to_owned()
	return tester
}

/// Set the expected search results, with line numbers.
fn (mut tester SearcherTester) expected_with_line_number(exp string) &SearcherTester {
	tester.expected_with_line_number = exp.to_owned()
	return tester
}

/// Set the expected search results, without line numbers, when performing
/// a search on a slice. When not present, `expected_no_line_number` is
/// used instead.
fn (mut tester SearcherTester) expected_slice_no_line_number(exp string) &SearcherTester {
	tester.expected_slice_no_line_number = exp.to_owned()
	return tester
}

/// Set the expected search results, with line numbers, when performing a
/// search on a slice. When not present, `expected_with_line_number` is
/// used instead.
fn (mut tester SearcherTester) expected_slice_with_line_number(exp string) &SearcherTester {
	tester.expected_slice_with_line_number = exp.to_owned()
	return tester
}

/// Whether to test search with line numbers or not.
///
/// This is enabled by default. When enabled, the string that is expected
/// when line numbers are present must be provided. Otherwise, the expected
/// string isn't required.
fn (mut tester SearcherTester) line_number(yes bool) &SearcherTester {
	tester.line_number = yes
	return tester
}

/// Whether to test search using the line-by-line searcher or not.
///
/// By default, this is enabled.
fn (mut tester SearcherTester) by_line(yes bool) &SearcherTester {
	tester.by_line = yes
	return tester
}

/// Whether to test search using the multi line searcher or not.
///
/// By default, this is enabled.
fn (mut tester SearcherTester) multi_line(yes bool) &SearcherTester {
	tester.multi_line = yes
	return tester
}

/// Whether to perform an inverted search or not.
///
/// By default, this is disabled.
fn (mut tester SearcherTester) invert_match(yes bool) &SearcherTester {
	tester.invert_match = yes
	return tester
}

/// Whether to enable binary detection on all searches.
///
/// By default, this is disabled.
fn (mut tester SearcherTester) binary_detection(detection BinaryDetection) &SearcherTester {
	tester.binary = detection
	return tester
}

/// Whether to automatically attempt to test the heap limit setting or not.
///
/// By default, one of the test configurations includes setting the heap
/// limit to its minimal value for normal operation, which checks that
/// everything works even at the extremes. However, in some cases, the heap
/// limit can (expectedly) alter the output slightly. For example, it can
/// impact the number of bytes searched when performing binary detection.
/// For convenience, it can be useful to disable the automatic heap limit
/// test.
fn (mut tester SearcherTester) auto_heap_limit(yes bool) &SearcherTester {
	tester.auto_heap_limit = yes
	return tester
}

/// Set the number of lines to include in the "after" context.
///
/// The default is `0`, which is equivalent to not printing any context.
fn (mut tester SearcherTester) after_context(lines usize) &SearcherTester {
	tester.after_context = lines
	return tester
}

/// Set the number of lines to include in the "before" context.
///
/// The default is `0`, which is equivalent to not printing any context.
fn (mut tester SearcherTester) before_context(lines usize) &SearcherTester {
	tester.before_context = lines
	return tester
}

/// Whether to enable the "passthru" feature or not.
///
/// When passthru is enabled, it effectively treats all non-matching lines
/// as contextual lines. In other words, enabling this is akin to
/// requesting an unbounded number of before and after contextual lines.
///
/// This is disabled by default.
fn (mut tester SearcherTester) passthru(yes bool) &SearcherTester {
	tester.passthru = yes
	return tester
}

/// Return the minimum size of a buffer required for a successful search.
///
/// Generally, this corresponds to the maximum length of a line (including
/// its terminator), but if context settings are enabled, then this must
/// include the sum of the longest N lines.
///
/// Note that this must account for whether the test is using multi line
/// search or not, since multi line search requires being able to fit the
/// entire haystack into memory.
fn (tester &SearcherTester) minimal_heap_limit(multi_line bool) usize {
	if multi_line {
		return usize(1 + tester.haystack.len)
	}
	lines := testutil_string_lines(tester.haystack)
	if tester.before_context == 0 && tester.after_context == 0 {
		mut max_len := 0
		for line in lines {
			if line.len > max_len {
				max_len = line.len
			}
		}
		return usize(1 + max_len)
	}
	mut lens := []int{}
	for line in lines {
		lens << line.len
	}
	lens.sort(a > b)
	context_count := if tester.passthru {
		lines.len
	} else {
		// Why do we add 2 here? Well, we need to add 1 in order to
		// have room to search at least one line. We add another
		// because the implementation will occasionally include
		// an additional line when handling the context. There's
		// no particularly good reason, other than keeping the
		// implementation simple.
		2 + int(tester.before_context) + int(tester.after_context)
	}
	mut sum := 0
	mut i := 0
	// We add 1 to each line since `str::lines` doesn't include the
	// line terminator.
	for i < context_count && i < lens.len {
		sum += lens[i] + 1
		i++
	}
	return usize(sum)
}

/// Returns true if and only if the given label should be included as part
/// of executing `test`.
///
/// Inclusion is determined by the filter specified. If no filter has been
/// given, then this always returns `true`.
fn (tester &SearcherTester) include(label string) bool {
	if tester.filter == none {
		return true
	}
	filter := unsafe { &tester.filter? }
	return filter.find(label) != none
}

// V-specific equivalent of Rust's `str::lines`, which recognizes `\n` and
// `\r\n` terminators but does not treat a bare `\r` as a line boundary.
fn testutil_string_lines(text string) []string {
	if text == '' {
		return []string{}
	}
	mut lines := text.split('\n')
	ends_with_line_feed := text.ends_with('\n')
	if ends_with_line_feed {
		lines.pop()
	}
	for i, line in lines {
		if (i + 1 < lines.len || ends_with_line_feed) && line.ends_with('\r') {
			lines[i] = line[..line.len - 1]
		}
	}
	return lines
}

/// Configs generates a set of all search configurations that should be
/// tested. The configs generated are based on the configuration in this
/// builder.
fn (tester &SearcherTester) configs() []TesterConfig {
	mut configs := []TesterConfig{}
	matcher_base := RegexMatcher.new(tester.pattern)
	mut builder_base := SearcherBuilder.new()
	builder_base.line_number(false)
	builder_base.invert_match(tester.invert_match)
	builder_base.binary_detection(tester.binary.clone())
	builder_base.after_context(tester.after_context)
	builder_base.before_context(tester.before_context)
	builder_base.passthru(tester.passthru)

	if tester.by_line {
		mut matcher_ := matcher_base.clone()
		mut builder := builder_base.clone()
		expected_reader := tester.expected_no_line_number or { panic('missing expected output') }
		expected_slice := tester.expected_slice_no_line_number or { expected_reader.clone() }
		configs << TesterConfig{
			label:           'byline-noterm-nonumber'.to_owned()
			expected_reader: expected_reader.clone()
			expected_slice:  expected_slice.clone()
			builder:         builder.clone()
			matcher_:        matcher_.clone()
		}
		if tester.auto_heap_limit {
			builder.heap_limit(tester.minimal_heap_limit(false))
			configs << TesterConfig{
				label:           'byline-noterm-nonumber-heaplimit'.to_owned()
				expected_reader: expected_reader.clone()
				expected_slice:  expected_slice.clone()
				builder:         builder.clone()
				matcher_:        matcher_.clone()
			}
			builder.heap_limit(none)
		}
		matcher_.set_line_term(matcher.LineTerminator.byte(`\n`))
		configs << TesterConfig{
			label:           'byline-term-nonumber'.to_owned()
			expected_reader: expected_reader.clone()
			expected_slice:  expected_slice.clone()
			builder:         builder.clone()
			matcher_:        matcher_.clone()
		}
		matcher_.every_line_is_candidate(true)
		configs << TesterConfig{
			label:           'byline-term-nonumber-candidates'.to_owned()
			expected_reader: expected_reader.clone()
			expected_slice:  expected_slice.clone()
			builder:         builder.clone()
			matcher_:        matcher_.clone()
		}
	}
	if tester.by_line && tester.line_number {
		mut matcher_ := matcher_base.clone()
		mut builder := builder_base.clone()
		expected_reader := tester.expected_with_line_number or { panic('missing line-number expected output') }
		expected_slice := tester.expected_slice_with_line_number or { expected_reader.clone() }
		builder.line_number(true)
		configs << TesterConfig{
			label:           'byline-noterm-number'.to_owned()
			expected_reader: expected_reader.clone()
			expected_slice:  expected_slice.clone()
			builder:         builder.clone()
			matcher_:        matcher_.clone()
		}
		matcher_.set_line_term(matcher.LineTerminator.byte(`\n`))
		configs << TesterConfig{
			label:           'byline-term-number'.to_owned()
			expected_reader: expected_reader.clone()
			expected_slice:  expected_slice.clone()
			builder:         builder.clone()
			matcher_:        matcher_.clone()
		}
		matcher_.every_line_is_candidate(true)
		configs << TesterConfig{
			label:           'byline-term-number-candidates'.to_owned()
			expected_reader: expected_reader.clone()
			expected_slice:  expected_slice.clone()
			builder:         builder.clone()
			matcher_:        matcher_.clone()
		}
	}
	if tester.multi_line {
		mut builder := builder_base.clone()
		expected_no_line := tester.expected_no_line_number or { panic('missing expected output') }
		expected_slice := tester.expected_slice_no_line_number or { expected_no_line.clone() }
		builder.multi_line(true)
		configs << TesterConfig{
			label:           'multiline-nonumber'.to_owned()
			expected_reader: expected_slice.clone()
			expected_slice:  expected_slice.clone()
			builder:         builder.clone()
			matcher_:        matcher_base.clone()
		}
		if tester.auto_heap_limit {
			builder.heap_limit(tester.minimal_heap_limit(true))
			configs << TesterConfig{
				label:           'multiline-nonumber-heaplimit'.to_owned()
				expected_reader: expected_slice.clone()
				expected_slice:  expected_slice.clone()
				builder:         builder.clone()
				matcher_:        matcher_base.clone()
			}
			builder.heap_limit(none)
		}
	}
	if tester.multi_line && tester.line_number {
		mut builder := builder_base.clone()
		expected_line := tester.expected_with_line_number or { panic('missing line-number expected output') }
		expected_slice := tester.expected_slice_with_line_number or { expected_line.clone() }
		builder.multi_line(true)
		builder.line_number(true)
		configs << TesterConfig{
			label:           'multiline-number'.to_owned()
			expected_reader: expected_slice.clone()
			expected_slice:  expected_slice.clone()
			builder:         builder.clone()
			matcher_:        matcher_base.clone()
		}
		builder.heap_limit(tester.minimal_heap_limit(true))
		configs << TesterConfig{
			label:           'multiline-number-heaplimit'.to_owned()
			expected_reader: expected_slice.clone()
			expected_slice:  expected_slice.clone()
			builder:         builder.clone()
			matcher_:        matcher_base.clone()
		}
		builder.heap_limit(none)
	}
	return configs
}

struct TesterConfig implements IClone {
	label           string
	expected_reader string
	expected_slice  string
	builder         SearcherBuilder
	matcher_        RegexMatcher
}

/// Execute a search using a reader. This exercises the incremental search
/// strategy, where the entire contents of the corpus aren't necessarily
/// in memory at once.
fn (config &TesterConfig) search_reader(haystack string) string {
	mut sink := KitchenSink.new()
	mut builder := config.builder.clone()
	mut searcher_ := builder.build()
	mut rdr := GlueByteSliceReader.new(haystack)
	matcher_ := config.matcher_.clone()
	searcher_.search_reader(matcher_, mut rdr, &sink) or {
		panic("error running 'reader-${config.label}': ${err.msg()}")
	}
	return (*sink.as_bytes()).bytestr()
}

/// Execute a search using a slice. This exercises the search routines that
/// have the entire contents of the corpus in memory at one time.
fn (config &TesterConfig) search_slice(haystack string) string {
	mut sink := KitchenSink.new()
	mut builder := config.builder.clone()
	mut searcher_ := builder.build()
	matcher_ := config.matcher_.clone()
	searcher_.search_slice(matcher_, haystack.bytes(), &sink) or {
		panic("error running 'slice-${config.label}': ${err.msg()}")
	}
	return (*sink.as_bytes()).bytestr()
}

fn glue_assert_eq_printed(expected string, got string, label string) {
	if got != expected {
		panic('${label}\nexpected:\n${expected}\n\ngot:\n${got}')
	}
}

fn glue_assert_match(got matcher.FallibleMatch, expected matcher.Match) {
	mat := got.get() or { panic('expected match') }
	assert mat.start() == expected.start()
	assert mat.end() == expected.end()
}

fn glue_assert_no_match(got matcher.FallibleMatch) {
	if _ := got.get() {
		assert false
	}
}

fn glue_m(start usize, end usize) matcher.Match {
	return matcher.Match.new(start, end)
}

fn glue_big_haystack() string {
	repeats := 4 * (default_buffer_capacity + 7)
	mut builder := strings.new_builder(4 + int(repeats * 4))
	builder.write_string('a\n')
	for _ in 0 .. repeats {
		builder.write_string('zzz\n')
	}
	builder.write_string('a\n')
	return builder.str()
}

fn glue_binary3_haystack() string {
	mut builder := strings.new_builder(int(2 + default_buffer_capacity * 4 + 14))
	builder.write_string('a\n')
	for _ in 0 .. default_buffer_capacity {
		builder.write_string('zzz\n')
	}
	builder.write_string('a\n')
	builder.write_string('zzz\n')
	builder.write_string('a\x00a\n')
	builder.write_string('zzz\n')
	builder.write_string('a\n')
	return builder.str()
}

fn glue_binary4_haystack() string {
	mut builder := strings.new_builder(int(2 + default_buffer_capacity * 4 + 12))
	builder.write_string('a\n')
	for _ in 0 .. default_buffer_capacity {
		builder.write_string('zzz\n')
	}
	builder.write_string('a\n')
	builder.write_string('b\x00b\n')
	builder.write_string('a\x00a\n')
	builder.write_string('a\n')
	return builder.str()
}

fn test_glue_basic1() {
	exp := '0:For the Doctor Watsons of this world, as opposed to the Sherlock
129:be, to a very large extent, the result of luck. Sherlock Holmes

byte count:366
'
	mut tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	tester.line_number(false)
	tester.expected_no_line_number(exp)
	tester.test()
}

fn test_searcher_testutil_empty_line1() {
	haystack := ''.bytes()
	matcher_ := RegexMatcher.new(r'^$')

	glue_assert_match(matcher_.find_at(haystack, 0)!, glue_m(0, 0))
}

fn test_searcher_testutil_empty_line2() {
	haystack := '\n'.bytes()
	matcher_ := RegexMatcher.new(r'^$')

	glue_assert_match(matcher_.find_at(haystack, 0)!, glue_m(0, 0))
	glue_assert_match(matcher_.find_at(haystack, 1)!, glue_m(1, 1))
}

fn test_searcher_testutil_empty_line3() {
	haystack := '\n\n'.bytes()
	matcher_ := RegexMatcher.new(r'^$')

	glue_assert_match(matcher_.find_at(haystack, 0)!, glue_m(0, 0))
	glue_assert_match(matcher_.find_at(haystack, 1)!, glue_m(1, 1))
	glue_assert_match(matcher_.find_at(haystack, 2)!, glue_m(2, 2))
}

fn test_searcher_testutil_empty_line4() {
	haystack := 'a\n\nb\n'.bytes()
	matcher_ := RegexMatcher.new(r'^$')

	glue_assert_match(matcher_.find_at(haystack, 0)!, glue_m(2, 2))
	glue_assert_match(matcher_.find_at(haystack, 1)!, glue_m(2, 2))
	glue_assert_match(matcher_.find_at(haystack, 2)!, glue_m(2, 2))
	glue_assert_match(matcher_.find_at(haystack, 3)!, glue_m(5, 5))
	glue_assert_match(matcher_.find_at(haystack, 4)!, glue_m(5, 5))
	glue_assert_match(matcher_.find_at(haystack, 5)!, glue_m(5, 5))
}

fn test_searcher_testutil_empty_line5() {
	haystack := 'a\n\nb\nc'.bytes()
	matcher_ := RegexMatcher.new(r'^$')

	glue_assert_match(matcher_.find_at(haystack, 0)!, glue_m(2, 2))
	glue_assert_match(matcher_.find_at(haystack, 1)!, glue_m(2, 2))
	glue_assert_match(matcher_.find_at(haystack, 2)!, glue_m(2, 2))
	glue_assert_no_match(matcher_.find_at(haystack, 3)!)
	glue_assert_no_match(matcher_.find_at(haystack, 4)!)
	glue_assert_no_match(matcher_.find_at(haystack, 5)!)
	glue_assert_no_match(matcher_.find_at(haystack, 6)!)
}

fn test_searcher_testutil_empty_line6() {
	haystack := 'a\n'.bytes()
	matcher_ := RegexMatcher.new(r'^$')

	glue_assert_match(matcher_.find_at(haystack, 0)!, glue_m(2, 2))
	glue_assert_match(matcher_.find_at(haystack, 1)!, glue_m(2, 2))
	glue_assert_match(matcher_.find_at(haystack, 2)!, glue_m(2, 2))
}

fn test_searcher_testutil_filter_and_print_labels_configuration() {
	mut tester := SearcherTester.new('haystack', 'pattern')
	assert tester.include('reader-byline-noterm-nonumber')
	tester.filter(r'^reader-byline-noterm-nonumber$')
	assert tester.include('reader-byline-noterm-nonumber')
	assert !tester.include('slice-byline-noterm-nonumber')
	tester.print_labels(true)
	assert tester.print_labels
}

fn test_searcher_testutil_uses_rust_line_boundaries_for_heap_limits() {
	assert testutil_string_lines('a\r') == ['a\r']
	assert testutil_string_lines('a\r\nb\r') == ['a', 'b\r']
	tester := SearcherTester.new('a\r', 'a')
	assert tester.minimal_heap_limit(false) == 3
}

fn test_glue_basic2() {
	exp := '\nbyte count:366\n'
	mut tester := SearcherTester.new(glue_sherlock, 'NADA')
	tester.line_number(false)
	tester.expected_no_line_number(exp)
	tester.test()
}

fn test_glue_basic3() {
	exp := '0:For the Doctor Watsons of this world, as opposed to the Sherlock
65:Holmeses, success in the province of detective work must always
129:be, to a very large extent, the result of luck. Sherlock Holmes
193:can extract a clew from a wisp of straw or a flake of cigar ash;
258:but Doctor Watson has to have it taken out for him and dusted,
321:and exhibited clearly, with a label attached.
byte count:366
'
	mut tester := SearcherTester.new(glue_sherlock, 'a')
	tester.line_number(false)
	tester.expected_no_line_number(exp)
	tester.test()
}

fn test_glue_basic4() {
	haystack := 'a
b

c


d
'
	byte_count := haystack.len
	exp := '0:a\n\nbyte count:${byte_count}\n'
	mut tester := SearcherTester.new(haystack, 'a')
	tester.line_number(false)
	tester.expected_no_line_number(exp)
	tester.test()
}

fn test_glue_invert1() {
	exp := '65:Holmeses, success in the province of detective work must always
193:can extract a clew from a wisp of straw or a flake of cigar ash;
258:but Doctor Watson has to have it taken out for him and dusted,
321:and exhibited clearly, with a label attached.
byte count:366
'
	mut tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	tester.line_number(false)
	tester.invert_match(true)
	tester.expected_no_line_number(exp)
	tester.test()
}

fn test_glue_line_number1() {
	exp := '0:For the Doctor Watsons of this world, as opposed to the Sherlock
129:be, to a very large extent, the result of luck. Sherlock Holmes

byte count:366
'
	exp_line := '1:0:For the Doctor Watsons of this world, as opposed to the Sherlock
3:129:be, to a very large extent, the result of luck. Sherlock Holmes

byte count:366
'
	mut tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_line)
	tester.test()
}

fn test_glue_line_number_invert1() {
	exp := '65:Holmeses, success in the province of detective work must always
193:can extract a clew from a wisp of straw or a flake of cigar ash;
258:but Doctor Watson has to have it taken out for him and dusted,
321:and exhibited clearly, with a label attached.
byte count:366
'
	exp_line := '2:65:Holmeses, success in the province of detective work must always
4:193:can extract a clew from a wisp of straw or a flake of cigar ash;
5:258:but Doctor Watson has to have it taken out for him and dusted,
6:321:and exhibited clearly, with a label attached.
byte count:366
'
	mut tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	tester.invert_match(true)
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_line)
	tester.test()
}

fn test_glue_multi_line_overlap1() {
	haystack := 'xxx\nabc\ndefxxxabc\ndefxxx\nxxx'
	byte_count := haystack.len
	exp := '4:abc\n8:defxxxabc\n18:defxxx\n\nbyte count:${byte_count}\n'
	mut tester := SearcherTester.new(haystack, 'abc\ndef')
	tester.by_line(false)
	tester.line_number(false)
	tester.expected_no_line_number(exp)
	tester.test()
}

fn test_glue_multi_line_overlap2() {
	haystack := 'xxx\nabc\ndefabc\ndefxxx\nxxx'
	byte_count := haystack.len
	exp := '4:abc\n8:defabc\n15:defxxx\n\nbyte count:${byte_count}\n'
	mut tester := SearcherTester.new(haystack, 'abc\ndef')
	tester.by_line(false)
	tester.line_number(false)
	tester.expected_no_line_number(exp)
	tester.test()
}

fn test_glue_empty_line1() {
	exp := '\nbyte count:0\n'
	mut tester := SearcherTester.new('', r'^$')
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp)
	tester.test()
}

fn test_glue_empty_line2() {
	exp := '0:\n\nbyte count:1\n'
	exp_line := '1:0:\n\nbyte count:1\n'

	mut tester := SearcherTester.new('\n', r'^$')
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_line)
	tester.test()
}

fn test_glue_empty_line3() {
	exp := '0:\n1:\n\nbyte count:2\n'
	exp_line := '1:0:\n2:1:\n\nbyte count:2\n'

	mut tester := SearcherTester.new('\n\n', r'^$')
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_line)
	tester.test()
}

fn test_glue_empty_line4() {
	// See: https://github.com/BurntSushi/ripgrep/issues/441
	haystack := 'a
b

c


d
'
	byte_count := haystack.len
	exp := '4:\n7:\n8:\n\nbyte count:${byte_count}\n'
	exp_line := '3:4:\n5:7:\n6:8:\n\nbyte count:${byte_count}\n'

	mut tester := SearcherTester.new(haystack, r'^$')
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_line)
	tester.test()
}

fn test_glue_empty_line5() {
	// See: https://github.com/BurntSushi/ripgrep/issues/441
	// This is like empty_line4, but lacks the trailing line terminator.
	haystack := 'a
b

c


d'
	byte_count := haystack.len
	exp := '4:\n7:\n8:\n\nbyte count:${byte_count}\n'
	exp_line := '3:4:\n5:7:\n6:8:\n\nbyte count:${byte_count}\n'

	mut tester := SearcherTester.new(haystack, r'^$')
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_line)
	tester.test()
}

fn test_glue_empty_line6() {
	// See: https://github.com/BurntSushi/ripgrep/issues/441
	// This is like empty_line4, but includes an empty line at the end.
	haystack := 'a
b

c


d

'
	byte_count := haystack.len
	exp := '4:\n7:\n8:\n11:\n\nbyte count:${byte_count}\n'
	exp_line := '3:4:\n5:7:\n6:8:\n8:11:\n\nbyte count:${byte_count}\n'

	mut tester := SearcherTester.new(haystack, r'^$')
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_line)
	tester.test()
}

fn test_glue_big1() {
	haystack := glue_big_haystack()

	byte_count := haystack.len
	exp := '0:a\n1048690:a\n\nbyte count:${byte_count}\n'

	mut tester := SearcherTester.new(haystack, 'a')
	tester.line_number(false)
	tester.expected_no_line_number(exp)
	tester.test()
}

fn test_glue_big_error_one_line() {
	haystack := glue_big_haystack()

	matcher_ := RegexMatcher.new('a')
	mut sink := KitchenSink.new()
	mut builder := SearcherBuilder.new()
	builder.heap_limit(usize(3)) // max line length is 4, one byte short
	mut searcher_ := builder.build()
	mut rdr := GlueByteSliceReader.new(haystack)
	searcher_.search_reader(matcher_, mut rdr, &sink) or { return }
	assert false
}

fn test_glue_big_error_multi_line() {
	haystack := glue_big_haystack()

	matcher_ := RegexMatcher.new('a')
	mut sink := KitchenSink.new()
	mut builder := SearcherBuilder.new()
	builder.multi_line(true)
	builder.heap_limit(usize(haystack.len)) // actually need one more byte
	mut searcher_ := builder.build()
	mut rdr := GlueByteSliceReader.new(haystack)
	searcher_.search_reader(matcher_, mut rdr, &sink) or { return }
	assert false
}

fn test_glue_binary1() {
	haystack := '\x00a'
	exp := '\nbyte count:0\nbinary offset:0\n'

	mut tester := SearcherTester.new(haystack, 'a')
	tester.binary_detection(BinaryDetection.quit(u8(0)))
	tester.line_number(false)
	tester.expected_no_line_number(exp)
	tester.test()
}

fn test_glue_binary2() {
	haystack := 'a\x00'
	exp := '\nbyte count:0\nbinary offset:1\n'

	mut tester := SearcherTester.new(haystack, 'a')
	tester.binary_detection(BinaryDetection.quit(u8(0)))
	tester.line_number(false)
	tester.expected_no_line_number(exp)
	tester.test()
}

fn test_glue_binary3() {
	haystack := glue_binary3_haystack()

	// The line buffered searcher has slightly different semantics here.
	// Namely, it will *always* detect binary data in the current buffer
	// before searching it. Thus, the total number of bytes searched is
	// smaller than below.
	exp := '0:a\n\nbyte count:262146\nbinary offset:262153\n'
	// In contrast, the slice readers (for multi line as well) will only
	// look for binary data in the initial chunk of bytes. After that
	// point, it only looks for binary data in matches. Note though that
	// the binary offset remains the same. (See the binary4 test for a case
	// where the offset is explicitly different.)
	exp_slice := '0:a\n262146:a\n\nbyte count:262153\nbinary offset:262153\n'

	mut tester := SearcherTester.new(haystack, 'a')
	tester.binary_detection(BinaryDetection.quit(u8(0)))
	tester.line_number(false)
	tester.auto_heap_limit(false)
	tester.expected_no_line_number(exp)
	tester.expected_slice_no_line_number(exp_slice)
	tester.test()
}

fn test_glue_binary4() {
	mut haystack := glue_binary4_haystack()
	// The Read searcher will detect binary data here, but since this is
	// beyond the initial buffer size and doesn't otherwise contain a
	// match, the Slice reader won't detect the binary data until the next
	// line (which is a match).

	exp := '0:a\n\nbyte count:262146\nbinary offset:262149\n'
	// The binary offset for the Slice readers corresponds to the binary
	// data in `a\x00a\n` since the first line with binary data
	// (`b\x00b\n`) isn't part of a match, and is therefore undetected.
	exp_slice := '0:a\n262146:a\n\nbyte count:262153\nbinary offset:262153\n'

	mut tester := SearcherTester.new(haystack, 'a')
	tester.binary_detection(BinaryDetection.quit(u8(0)))
	tester.line_number(false)
	tester.auto_heap_limit(false)
	tester.expected_no_line_number(exp)
	tester.expected_slice_no_line_number(exp_slice)
	tester.test()
}

fn test_glue_passthru_sherlock1() {
	exp := '0:For the Doctor Watsons of this world, as opposed to the Sherlock
65-Holmeses, success in the province of detective work must always
129:be, to a very large extent, the result of luck. Sherlock Holmes
193-can extract a clew from a wisp of straw or a flake of cigar ash;
258-but Doctor Watson has to have it taken out for him and dusted,
321-and exhibited clearly, with a label attached.
byte count:366
'
	mut tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	tester.passthru(true)
	tester.line_number(false)
	tester.expected_no_line_number(exp)
	tester.test()
}

fn test_glue_passthru_sherlock_invert1() {
	exp := '0-For the Doctor Watsons of this world, as opposed to the Sherlock
65:Holmeses, success in the province of detective work must always
129-be, to a very large extent, the result of luck. Sherlock Holmes
193:can extract a clew from a wisp of straw or a flake of cigar ash;
258:but Doctor Watson has to have it taken out for him and dusted,
321:and exhibited clearly, with a label attached.
byte count:366
'
	mut tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	tester.passthru(true)
	tester.line_number(false)
	tester.invert_match(true)
	tester.expected_no_line_number(exp)
	tester.test()
}

fn test_glue_context_sherlock1() {
	exp := '0:For the Doctor Watsons of this world, as opposed to the Sherlock
65-Holmeses, success in the province of detective work must always
129:be, to a very large extent, the result of luck. Sherlock Holmes
193-can extract a clew from a wisp of straw or a flake of cigar ash;

byte count:366
'
	exp_lines := '1:0:For the Doctor Watsons of this world, as opposed to the Sherlock
2-65-Holmeses, success in the province of detective work must always
3:129:be, to a very large extent, the result of luck. Sherlock Holmes
4-193-can extract a clew from a wisp of straw or a flake of cigar ash;

byte count:366
'
	// before and after + line numbers
	mut tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	tester.after_context(1)
	tester.before_context(1)
	tester.line_number(true)
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_lines)
	tester.test()

	// after
	mut after_tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	after_tester.after_context(1)
	after_tester.line_number(false)
	after_tester.expected_no_line_number(exp)
	after_tester.test()

	// before
	before_exp := '0:For the Doctor Watsons of this world, as opposed to the Sherlock
65-Holmeses, success in the province of detective work must always
129:be, to a very large extent, the result of luck. Sherlock Holmes

byte count:366
'
	mut before_tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	before_tester.before_context(1)
	before_tester.line_number(false)
	before_tester.expected_no_line_number(before_exp)
	before_tester.test()
}

fn test_glue_context_sherlock_invert1() {
	exp := '0-For the Doctor Watsons of this world, as opposed to the Sherlock
65:Holmeses, success in the province of detective work must always
129-be, to a very large extent, the result of luck. Sherlock Holmes
193:can extract a clew from a wisp of straw or a flake of cigar ash;
258:but Doctor Watson has to have it taken out for him and dusted,
321:and exhibited clearly, with a label attached.
byte count:366
'
	exp_lines := '1-0-For the Doctor Watsons of this world, as opposed to the Sherlock
2:65:Holmeses, success in the province of detective work must always
3-129-be, to a very large extent, the result of luck. Sherlock Holmes
4:193:can extract a clew from a wisp of straw or a flake of cigar ash;
5:258:but Doctor Watson has to have it taken out for him and dusted,
6:321:and exhibited clearly, with a label attached.
byte count:366
'
	// before and after + line numbers
	mut tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	tester.after_context(1)
	tester.before_context(1)
	tester.line_number(true)
	tester.invert_match(true)
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_lines)
	tester.test()

	// before
	mut before_tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	before_tester.before_context(1)
	before_tester.line_number(false)
	before_tester.invert_match(true)
	before_tester.expected_no_line_number(exp)
	before_tester.test()

	// after
	after_exp := '65:Holmeses, success in the province of detective work must always
129-be, to a very large extent, the result of luck. Sherlock Holmes
193:can extract a clew from a wisp of straw or a flake of cigar ash;
258:but Doctor Watson has to have it taken out for him and dusted,
321:and exhibited clearly, with a label attached.
byte count:366
'
	mut after_tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	after_tester.after_context(1)
	after_tester.line_number(false)
	after_tester.invert_match(true)
	after_tester.expected_no_line_number(after_exp)
	after_tester.test()
}

fn test_glue_context_sherlock2() {
	exp := '65-Holmeses, success in the province of detective work must always
129:be, to a very large extent, the result of luck. Sherlock Holmes
193:can extract a clew from a wisp of straw or a flake of cigar ash;
258-but Doctor Watson has to have it taken out for him and dusted,
321:and exhibited clearly, with a label attached.
byte count:366
'
	exp_lines := '2-65-Holmeses, success in the province of detective work must always
3:129:be, to a very large extent, the result of luck. Sherlock Holmes
4:193:can extract a clew from a wisp of straw or a flake of cigar ash;
5-258-but Doctor Watson has to have it taken out for him and dusted,
6:321:and exhibited clearly, with a label attached.
byte count:366
'
	// before + after + line numbers
	mut tester := SearcherTester.new(glue_sherlock, ' a ')
	tester.after_context(1)
	tester.before_context(1)
	tester.line_number(true)
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_lines)
	tester.test()

	// before
	mut before_tester := SearcherTester.new(glue_sherlock, ' a ')
	before_tester.before_context(1)
	before_tester.line_number(false)
	before_tester.expected_no_line_number(exp)
	before_tester.test()

	// after
	after_exp := '129:be, to a very large extent, the result of luck. Sherlock Holmes
193:can extract a clew from a wisp of straw or a flake of cigar ash;
258-but Doctor Watson has to have it taken out for him and dusted,
321:and exhibited clearly, with a label attached.
byte count:366
'
	mut after_tester := SearcherTester.new(glue_sherlock, ' a ')
	after_tester.after_context(1)
	after_tester.line_number(false)
	after_tester.expected_no_line_number(after_exp)
	after_tester.test()
}

fn test_glue_context_sherlock_invert2() {
	exp := '0:For the Doctor Watsons of this world, as opposed to the Sherlock
65:Holmeses, success in the province of detective work must always
129-be, to a very large extent, the result of luck. Sherlock Holmes
193-can extract a clew from a wisp of straw or a flake of cigar ash;
258:but Doctor Watson has to have it taken out for him and dusted,
321-and exhibited clearly, with a label attached.
byte count:366
'
	exp_lines := '1:0:For the Doctor Watsons of this world, as opposed to the Sherlock
2:65:Holmeses, success in the province of detective work must always
3-129-be, to a very large extent, the result of luck. Sherlock Holmes
4-193-can extract a clew from a wisp of straw or a flake of cigar ash;
5:258:but Doctor Watson has to have it taken out for him and dusted,
6-321-and exhibited clearly, with a label attached.
byte count:366
'
	// before + after + line numbers
	mut tester := SearcherTester.new(glue_sherlock, ' a ')
	tester.after_context(1)
	tester.before_context(1)
	tester.line_number(true)
	tester.invert_match(true)
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_lines)
	tester.test()

	// before
	before_exp := '0:For the Doctor Watsons of this world, as opposed to the Sherlock
65:Holmeses, success in the province of detective work must always
--
193-can extract a clew from a wisp of straw or a flake of cigar ash;
258:but Doctor Watson has to have it taken out for him and dusted,

byte count:366
'
	mut before_tester := SearcherTester.new(glue_sherlock, ' a ')
	before_tester.before_context(1)
	before_tester.line_number(false)
	before_tester.invert_match(true)
	before_tester.expected_no_line_number(before_exp)
	before_tester.test()

	// after
	after_exp := '0:For the Doctor Watsons of this world, as opposed to the Sherlock
65:Holmeses, success in the province of detective work must always
129-be, to a very large extent, the result of luck. Sherlock Holmes
--
258:but Doctor Watson has to have it taken out for him and dusted,
321-and exhibited clearly, with a label attached.
byte count:366
'
	mut after_tester := SearcherTester.new(glue_sherlock, ' a ')
	after_tester.after_context(1)
	after_tester.line_number(false)
	after_tester.invert_match(true)
	after_tester.expected_no_line_number(after_exp)
	after_tester.test()
}

fn test_glue_context_sherlock3() {
	exp := '0:For the Doctor Watsons of this world, as opposed to the Sherlock
65-Holmeses, success in the province of detective work must always
129:be, to a very large extent, the result of luck. Sherlock Holmes
193-can extract a clew from a wisp of straw or a flake of cigar ash;
258-but Doctor Watson has to have it taken out for him and dusted,

byte count:366
'
	exp_lines := '1:0:For the Doctor Watsons of this world, as opposed to the Sherlock
2-65-Holmeses, success in the province of detective work must always
3:129:be, to a very large extent, the result of luck. Sherlock Holmes
4-193-can extract a clew from a wisp of straw or a flake of cigar ash;
5-258-but Doctor Watson has to have it taken out for him and dusted,

byte count:366
'
	// before and after + line numbers
	mut tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	tester.after_context(2)
	tester.before_context(2)
	tester.line_number(true)
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_lines)
	tester.test()

	// after
	mut after_tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	after_tester.after_context(2)
	after_tester.line_number(false)
	after_tester.expected_no_line_number(exp)
	after_tester.test()

	// before
	before_exp := '0:For the Doctor Watsons of this world, as opposed to the Sherlock
65-Holmeses, success in the province of detective work must always
129:be, to a very large extent, the result of luck. Sherlock Holmes

byte count:366
'
	mut before_tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	before_tester.before_context(2)
	before_tester.line_number(false)
	before_tester.expected_no_line_number(before_exp)
	before_tester.test()
}

fn test_glue_context_sherlock4() {
	exp := '129-be, to a very large extent, the result of luck. Sherlock Holmes
193-can extract a clew from a wisp of straw or a flake of cigar ash;
258:but Doctor Watson has to have it taken out for him and dusted,
321-and exhibited clearly, with a label attached.
byte count:366
'
	exp_lines := '3-129-be, to a very large extent, the result of luck. Sherlock Holmes
4-193-can extract a clew from a wisp of straw or a flake of cigar ash;
5:258:but Doctor Watson has to have it taken out for him and dusted,
6-321-and exhibited clearly, with a label attached.
byte count:366
'
	// before and after + line numbers
	mut tester := SearcherTester.new(glue_sherlock, 'dusted')
	tester.after_context(2)
	tester.before_context(2)
	tester.line_number(true)
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_lines)
	tester.test()

	// after
	after_exp := '258:but Doctor Watson has to have it taken out for him and dusted,
321-and exhibited clearly, with a label attached.
byte count:366
'
	mut after_tester := SearcherTester.new(glue_sherlock, 'dusted')
	after_tester.after_context(2)
	after_tester.line_number(false)
	after_tester.expected_no_line_number(after_exp)
	after_tester.test()

	// before
	before_exp := '129-be, to a very large extent, the result of luck. Sherlock Holmes
193-can extract a clew from a wisp of straw or a flake of cigar ash;
258:but Doctor Watson has to have it taken out for him and dusted,

byte count:366
'
	mut before_tester := SearcherTester.new(glue_sherlock, 'dusted')
	before_tester.before_context(2)
	before_tester.line_number(false)
	before_tester.expected_no_line_number(before_exp)
	before_tester.test()
}

fn test_glue_context_sherlock5() {
	exp := '0-For the Doctor Watsons of this world, as opposed to the Sherlock
65:Holmeses, success in the province of detective work must always
129-be, to a very large extent, the result of luck. Sherlock Holmes
193-can extract a clew from a wisp of straw or a flake of cigar ash;
258-but Doctor Watson has to have it taken out for him and dusted,
321:and exhibited clearly, with a label attached.
byte count:366
'
	exp_lines := '1-0-For the Doctor Watsons of this world, as opposed to the Sherlock
2:65:Holmeses, success in the province of detective work must always
3-129-be, to a very large extent, the result of luck. Sherlock Holmes
4-193-can extract a clew from a wisp of straw or a flake of cigar ash;
5-258-but Doctor Watson has to have it taken out for him and dusted,
6:321:and exhibited clearly, with a label attached.
byte count:366
'
	// before and after + line numbers
	mut tester := SearcherTester.new(glue_sherlock, 'success|attached')
	tester.after_context(2)
	tester.before_context(2)
	tester.line_number(true)
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_lines)
	tester.test()

	// after
	after_exp := '65:Holmeses, success in the province of detective work must always
129-be, to a very large extent, the result of luck. Sherlock Holmes
193-can extract a clew from a wisp of straw or a flake of cigar ash;
--
321:and exhibited clearly, with a label attached.
byte count:366
'
	mut after_tester := SearcherTester.new(glue_sherlock, 'success|attached')
	after_tester.after_context(2)
	after_tester.line_number(false)
	after_tester.expected_no_line_number(after_exp)
	after_tester.test()

	// before
	before_exp := '0-For the Doctor Watsons of this world, as opposed to the Sherlock
65:Holmeses, success in the province of detective work must always
--
193-can extract a clew from a wisp of straw or a flake of cigar ash;
258-but Doctor Watson has to have it taken out for him and dusted,
321:and exhibited clearly, with a label attached.
byte count:366
'
	mut before_tester := SearcherTester.new(glue_sherlock, 'success|attached')
	before_tester.before_context(2)
	before_tester.line_number(false)
	before_tester.expected_no_line_number(before_exp)
	before_tester.test()
}

fn test_glue_context_sherlock6() {
	exp := '0:For the Doctor Watsons of this world, as opposed to the Sherlock
65-Holmeses, success in the province of detective work must always
129:be, to a very large extent, the result of luck. Sherlock Holmes
193-can extract a clew from a wisp of straw or a flake of cigar ash;
258-but Doctor Watson has to have it taken out for him and dusted,
321-and exhibited clearly, with a label attached.
byte count:366
'
	exp_lines := '1:0:For the Doctor Watsons of this world, as opposed to the Sherlock
2-65-Holmeses, success in the province of detective work must always
3:129:be, to a very large extent, the result of luck. Sherlock Holmes
4-193-can extract a clew from a wisp of straw or a flake of cigar ash;
5-258-but Doctor Watson has to have it taken out for him and dusted,
6-321-and exhibited clearly, with a label attached.
byte count:366
'
	// before and after + line numbers
	mut tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	tester.after_context(3)
	tester.before_context(3)
	tester.line_number(true)
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_lines)
	tester.test()

	// after
	mut after_tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	after_tester.after_context(3)
	after_tester.line_number(false)
	after_tester.expected_no_line_number(exp)
	after_tester.test()

	// before
	before_exp := '0:For the Doctor Watsons of this world, as opposed to the Sherlock
65-Holmeses, success in the province of detective work must always
129:be, to a very large extent, the result of luck. Sherlock Holmes

byte count:366
'
	mut before_tester := SearcherTester.new(glue_sherlock, 'Sherlock')
	before_tester.before_context(3)
	before_tester.line_number(false)
	before_tester.expected_no_line_number(before_exp)
	before_tester.test()
}

fn test_glue_context_code1() {
	// before and after
	exp := '33-
34-fn main() {
46:    let stdin = io::stdin();
75-    let stdout = io::stdout();
106-
107:    // Wrap the stdin reader in a Snappy reader.
156:    let mut rdr = snap::Reader::new(stdin.lock());
207-    let mut wtr = stdout.lock();
240-    io::copy(&mut rdr, &mut wtr).expect("I/O operation failed");

byte count:307
'
	exp_lines := '4-33-
5-34-fn main() {
6:46:    let stdin = io::stdin();
7-75-    let stdout = io::stdout();
8-106-
9:107:    // Wrap the stdin reader in a Snappy reader.
10:156:    let mut rdr = snap::Reader::new(stdin.lock());
11-207-    let mut wtr = stdout.lock();
12-240-    io::copy(&mut rdr, &mut wtr).expect("I/O operation failed");

byte count:307
'
	// before and after + line numbers
	mut tester := SearcherTester.new(glue_code, 'stdin')
	tester.after_context(2)
	tester.before_context(2)
	tester.line_number(true)
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_lines)
	tester.test()

	// after
	after_exp := '46:    let stdin = io::stdin();
75-    let stdout = io::stdout();
106-
107:    // Wrap the stdin reader in a Snappy reader.
156:    let mut rdr = snap::Reader::new(stdin.lock());
207-    let mut wtr = stdout.lock();
240-    io::copy(&mut rdr, &mut wtr).expect("I/O operation failed");

byte count:307
'
	mut after_tester := SearcherTester.new(glue_code, 'stdin')
	after_tester.after_context(2)
	after_tester.line_number(false)
	after_tester.expected_no_line_number(after_exp)
	after_tester.test()

	// before
	before_exp := '33-
34-fn main() {
46:    let stdin = io::stdin();
75-    let stdout = io::stdout();
106-
107:    // Wrap the stdin reader in a Snappy reader.
156:    let mut rdr = snap::Reader::new(stdin.lock());

byte count:307
'
	mut before_tester := SearcherTester.new(glue_code, 'stdin')
	before_tester.before_context(2)
	before_tester.line_number(false)
	before_tester.expected_no_line_number(before_exp)
	before_tester.test()
}

fn test_glue_context_code2() {
	exp := '34-fn main() {
46-    let stdin = io::stdin();
75:    let stdout = io::stdout();
106-
107-    // Wrap the stdin reader in a Snappy reader.
156-    let mut rdr = snap::Reader::new(stdin.lock());
207:    let mut wtr = stdout.lock();
240-    io::copy(&mut rdr, &mut wtr).expect("I/O operation failed");
305-}

byte count:307
'
	exp_lines := '5-34-fn main() {
6-46-    let stdin = io::stdin();
7:75:    let stdout = io::stdout();
8-106-
9-107-    // Wrap the stdin reader in a Snappy reader.
10-156-    let mut rdr = snap::Reader::new(stdin.lock());
11:207:    let mut wtr = stdout.lock();
12-240-    io::copy(&mut rdr, &mut wtr).expect("I/O operation failed");
13-305-}

byte count:307
'
	// before and after + line numbers
	mut tester := SearcherTester.new(glue_code, 'stdout')
	tester.after_context(2)
	tester.before_context(2)
	tester.line_number(true)
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_lines)
	tester.test()

	// after
	after_exp := '75:    let stdout = io::stdout();
106-
107-    // Wrap the stdin reader in a Snappy reader.
--
207:    let mut wtr = stdout.lock();
240-    io::copy(&mut rdr, &mut wtr).expect("I/O operation failed");
305-}

byte count:307
'
	mut after_tester := SearcherTester.new(glue_code, 'stdout')
	after_tester.after_context(2)
	after_tester.line_number(false)
	after_tester.expected_no_line_number(after_exp)
	after_tester.test()

	// before
	before_exp := '34-fn main() {
46-    let stdin = io::stdin();
75:    let stdout = io::stdout();
--
107-    // Wrap the stdin reader in a Snappy reader.
156-    let mut rdr = snap::Reader::new(stdin.lock());
207:    let mut wtr = stdout.lock();

byte count:307
'
	mut before_tester := SearcherTester.new(glue_code, 'stdout')
	before_tester.before_context(2)
	before_tester.line_number(false)
	before_tester.expected_no_line_number(before_exp)
	before_tester.test()
}

fn test_glue_context_code3() {
	exp := '20-use std::io;
33-
34:fn main() {
46-    let stdin = io::stdin();
75-    let stdout = io::stdout();
106-
107-    // Wrap the stdin reader in a Snappy reader.
156:    let mut rdr = snap::Reader::new(stdin.lock());
207-    let mut wtr = stdout.lock();
240-    io::copy(&mut rdr, &mut wtr).expect("I/O operation failed");

byte count:307
'
	exp_lines := '3-20-use std::io;
4-33-
5:34:fn main() {
6-46-    let stdin = io::stdin();
7-75-    let stdout = io::stdout();
8-106-
9-107-    // Wrap the stdin reader in a Snappy reader.
10:156:    let mut rdr = snap::Reader::new(stdin.lock());
11-207-    let mut wtr = stdout.lock();
12-240-    io::copy(&mut rdr, &mut wtr).expect("I/O operation failed");

byte count:307
'
	// before and after + line numbers
	mut tester := SearcherTester.new(glue_code, 'fn main|let mut rdr')
	tester.after_context(2)
	tester.before_context(2)
	tester.line_number(true)
	tester.expected_no_line_number(exp)
	tester.expected_with_line_number(exp_lines)
	tester.test()

	// after
	after_exp := '34:fn main() {
46-    let stdin = io::stdin();
75-    let stdout = io::stdout();
--
156:    let mut rdr = snap::Reader::new(stdin.lock());
207-    let mut wtr = stdout.lock();
240-    io::copy(&mut rdr, &mut wtr).expect("I/O operation failed");

byte count:307
'
	mut after_tester := SearcherTester.new(glue_code, 'fn main|let mut rdr')
	after_tester.after_context(2)
	after_tester.line_number(false)
	after_tester.expected_no_line_number(after_exp)
	after_tester.test()

	// before
	before_exp := '20-use std::io;
33-
34:fn main() {
--
106-
107-    // Wrap the stdin reader in a Snappy reader.
156:    let mut rdr = snap::Reader::new(stdin.lock());

byte count:307
'
	mut before_tester := SearcherTester.new(glue_code, 'fn main|let mut rdr')
	before_tester.before_context(2)
	before_tester.line_number(false)
	before_tester.expected_no_line_number(before_exp)
	before_tester.test()
}

fn test_glue_scratch() {
	haystack := 'For the Doctor Wat\xFFsons of this world, as opposed to the Sherlock
Holmeses, success in the province of detective work must always
be, to a very large extent, the result of luck. Sherlock Holmes
can extract a clew from a wisp of straw or a flake of cigar ash;
but Doctor Watson has to have it taken out for him and dusted,
and exhibited clearly, with a label attached.    '

	matcher_ := RegexMatcher.new('Sherlock')
	mut builder := SearcherBuilder.new()
	builder.line_number(true)
	mut searcher_ := builder.build()
	mut rdr := GlueByteSliceReader.new(haystack)
	mut sink := Lossy.new(fn (n u64, line string) !bool {
		print('${n}:${line}')
		return true
	})
	searcher_.search_reader(matcher_, mut rdr, &sink)!
}

// See: https://github.com/BurntSushi/ripgrep/issues/2260
fn test_glue_regression_2260() {
	mut matcher_builder := regex.RegexMatcherBuilder.new()
	matcher_builder.line_terminator(`\n`)
	matcher_ := matcher_builder.build(r'^\w+$') or { panic(err) }
	matcher_ref := regex.RegexMatcherRef.new(&matcher_)
	mut builder := SearcherBuilder.new()
	builder.line_number(true)
	mut searcher_ := builder.build()

	mut matched := false
	matched_ptr := &matched
	mut sink := UTF8.new(fn [matched_ptr] (_ u64, _ string) !bool {
		unsafe {
			*matched_ptr = true
		}
		return true
	})
	searcher_.search_slice(matcher_ref, 'GATC\n'.bytes(), &sink)!
	assert matched
}
