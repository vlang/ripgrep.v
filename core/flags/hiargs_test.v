module flags

import os
import printer

struct HiArgsBufferWriter implements printer.WriteColor {
mut:
	bytes []u8
}

fn (mut w HiArgsBufferWriter) write(buf []u8) !int {
	w.bytes << buf
	return buf.len
}

fn (mut w HiArgsBufferWriter) flush() ! {
	_ = w
}

fn (mut w HiArgsBufferWriter) set_color(spec printer.ColorSpec) ! {
	_ = w
	_ = spec
}

fn (mut w HiArgsBufferWriter) set_hyperlink(link printer.HyperlinkSpec) ! {
	_ = w
	_ = link
}

fn (mut w HiArgsBufferWriter) reset() ! {
	_ = w
}

fn (w HiArgsBufferWriter) supports_color() bool {
	_ = w
	return false
}

fn (w HiArgsBufferWriter) supports_hyperlinks() bool {
	_ = w
	return false
}

fn (w HiArgsBufferWriter) is_synchronous() bool {
	_ = w
	return true
}

fn must_hiargs(mut low LowArgs) HiArgs {
	return HiArgs.from_low_args(mut low) or { panic(err.msg()) }
}

fn test_hiargs_extracts_pattern_and_paths_from_positionals() {
	mut low := default_low_args()
	low.positional = ['needle', 'haystack.txt']

	hi := must_hiargs(mut low)
	assert hi.patterns.patterns == ['needle']
	assert hi.paths.paths == ['haystack.txt']
	assert !hi.has_implicit_path()
	assert hi.paths.is_one_file
	assert !hi.with_filename
}

fn test_hiargs_deduplicates_explicit_patterns() {
	mut low := default_low_args()
	low.patterns = [
		pattern_regexp('foo'),
		pattern_regexp('foo'),
		pattern_regexp('bar'),
	]
	low.positional = ['haystack.txt']

	hi := must_hiargs(mut low)
	assert hi.patterns.patterns == ['foo', 'bar']
	assert hi.paths.paths == ['haystack.txt']
}

fn test_hiargs_rewrites_count_modes() {
	mut inverted := default_low_args()
	inverted.mode = mode_search(.count_matches)
	inverted.invert_match = true
	inverted.patterns = [pattern_regexp('foo')]
	inverted.positional = ['haystack.txt']
	assert must_hiargs(mut inverted).mode() == mode_search(.count)

	mut only_matching := default_low_args()
	only_matching.mode = mode_search(.count)
	only_matching.only_matching = true
	only_matching.patterns = [pattern_regexp('foo')]
	only_matching.positional = ['haystack.txt']
	assert must_hiargs(mut only_matching).mode() == mode_search(.count_matches)
}

fn test_hiargs_json_enables_line_numbers() {
	mut low := default_low_args()
	low.mode = mode_search(.json)
	low.patterns = [pattern_regexp('foo')]
	low.positional = ['haystack.txt']
	assert must_hiargs(mut low).line_number
}

fn test_hiargs_matches_possible() {
	mut low := default_low_args()
	low.mode = mode_files()
	low.positional = ['.']
	assert !must_hiargs(mut low).matches_possible()

	mut zero := default_low_args()
	zero.patterns = [pattern_regexp('foo')]
	zero.positional = ['haystack.txt']
	zero.max_count = 0
	assert !must_hiargs(mut zero).matches_possible()

	mut normal := default_low_args()
	normal.patterns = [pattern_regexp('foo')]
	normal.positional = ['haystack.txt']
	assert must_hiargs(mut normal).matches_possible()
}

fn test_hiargs_binary_detection_modes() {
	mut defaulted := default_low_args()
	defaulted.patterns = [pattern_regexp('foo')]
	defaulted.positional = ['haystack.txt']
	hi := must_hiargs(mut defaulted)
	assert !hi.binary.is_none()
	assert hi.binary.explicit.convert_byte() or { 255 } == u8(0)
	assert hi.binary.implicit.quit_byte() or { 255 } == u8(0)

	mut text := default_low_args()
	text.binary = .as_text
	text.patterns = [pattern_regexp('foo')]
	text.positional = ['haystack.txt']
	assert must_hiargs(mut text).binary.is_none()

	mut null_data := default_low_args()
	null_data.null_data = true
	null_data.patterns = [pattern_regexp('foo')]
	null_data.positional = ['haystack.txt']
	assert must_hiargs(mut null_data).binary.is_none()
}

fn test_hiargs_buffer_writer_returns_configured_buffer() {
	mut low := default_low_args()
	low.patterns = [pattern_regexp('needle')]
	low.positional = ['haystack.txt']
	low.color = .always
	low.context.set_after(1)
	hi := must_hiargs(mut low)
	file_separator := hi.file_separator or { panic('missing file separator') }
	assert file_separator == '--'.bytes()

	wtr := hi.buffer_writer()
	mut buffer := wtr.buffer()
	assert buffer.supports_color()
	buffer.write('needle'.bytes()) or { panic(err.msg()) }
	assert buffer.as_slice() == 'needle'.bytes()
}

fn test_hiargs_builds_search_worker_components() {
	path := os.join_path(os.temp_dir(), 'ripgrep_v_hiargs_worker_${os.getpid()}.txt')
	os.write_file(path, 'hay\nneedle\nstack\n') or { panic(err.msg()) }
	defer {
		os.rm(path) or {}
	}

	mut low := default_low_args()
	low.patterns = [pattern_regexp('needle')]
	low.positional = [path]
	low.stats = true
	hi := must_hiargs(mut low)

	matcher_ := hi.matcher() or { panic(err.msg()) }
	searcher_ := hi.searcher() or { panic(err.msg()) }
	printer_ := hi.printer(.standard, HiArgsBufferWriter{})
	mut worker := hi.search_worker(matcher_, searcher_, printer_) or { panic(err.msg()) }
	result := worker.search_path(path) or { panic(err.msg()) }

	assert result.has_match()
	stats := result.stats() or { panic('missing stats') }
	assert stats.searches() == 1
	assert stats.searches_with_match() == 1
	assert stats.matches() == 1
}
