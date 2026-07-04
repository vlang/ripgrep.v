module core

import os
import printer
import regex
import searcher

struct BufferWriter implements printer.WriteColor {
mut:
	bytes []u8
}

fn (mut w BufferWriter) write(buf []u8) !int {
	w.bytes << buf
	return buf.len
}

fn (mut w BufferWriter) flush() ! {
	_ = w
}

fn (mut w BufferWriter) set_color(spec printer.ColorSpec) ! {
	_ = w
	_ = spec
}

fn (mut w BufferWriter) set_hyperlink(link printer.HyperlinkSpec) ! {
	_ = w
	_ = link
}

fn (mut w BufferWriter) reset() ! {
	_ = w
}

fn (w BufferWriter) supports_color() bool {
	_ = w
	return false
}

fn (w BufferWriter) supports_hyperlinks() bool {
	_ = w
	return false
}

fn (w BufferWriter) is_synchronous() bool {
	_ = w
	return true
}

fn test_search_worker_search_path_standard() {
	path := os.join_path(os.temp_dir(), 'ripgrep_v_search_worker_${os.getpid()}.txt')
	os.write_file(path, 'hay\nneedle\nstack\n') or { panic(err) }
	defer {
		os.rm(path) or {}
	}
	matcher_ := regex.RegexMatcher.new('needle') or { panic(err) }
	mut standard_builder := printer.StandardBuilder.new()
	standard_builder.stats(true)
	standard := standard_builder.build(BufferWriter{})
	printer_ := Printer.standard(standard)
	builder := SearchWorkerBuilder.new()
	mut worker := builder.build(PatternMatcher.rust_regex(matcher_), searcher.Searcher.new(), printer_)
	result := worker.search_path(path) or { panic(err) }
	assert result.has_match()
	wtr := worker.printer().get_mut()
	assert wtr.bytes.bytestr().index('needle') != none
	stats := result.stats() or { panic('missing stats') }
	assert stats.searches() == 1
	assert stats.searches_with_match() == 1

	plain_matcher := regex.RegexMatcher.new('needle') or { panic(err) }
	plain_standard := printer.StandardBuilder.new().build(BufferWriter{})
	plain_printer := Printer.standard(plain_standard)
	mut plain_worker := builder.build(PatternMatcher.rust_regex(plain_matcher), searcher.Searcher.new(),
		plain_printer)
	plain_result := plain_worker.search_path(path) or { panic(err) }
	assert plain_result.has_match()
	plain_wtr := plain_worker.printer().get_mut()
	assert plain_wtr.bytes.bytestr().index('needle') != none

	summary_matcher := regex.RegexMatcher.new('needle') or { panic(err) }
	summary_printer := Printer.summary(printer.Summary.new(BufferWriter{}))
	mut summary_worker := builder.build(PatternMatcher.rust_regex(summary_matcher), searcher.Searcher.new(),
		summary_printer)
	summary_result := summary_worker.search_path(path) or { panic(err) }
	assert summary_result.has_match()

	json_matcher := regex.RegexMatcher.new('needle') or { panic(err) }
	json_printer := Printer.json(printer.JSON.new(BufferWriter{}))
	mut json_worker := builder.build(PatternMatcher.rust_regex(json_matcher), searcher.Searcher.new(),
		json_printer)
	json_result := json_worker.search_path(path) or { panic(err) }
	assert json_result.has_match()
}
