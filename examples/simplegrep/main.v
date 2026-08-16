module main

import cli
import os
import printer
import regex
import searcher

fn main() {
	try_main() or {
		eprintln(err.msg())
		exit(1)
	}
}

fn try_main() ! {
	mut args := os.args.clone()
	if args.len < 2 {
		return error('Usage: simplegrep <pattern> [<path> ...]')
	}
	if args.len == 2 {
		args << './'.to_owned()
	}
	pattern := cli.pattern_from_os(args[1].clone())!
	search(pattern, args[2..])!
}

fn search(pattern string, paths []string) ! {
	matcher_ := regex.RegexMatcher.new_line_matcher(pattern)!
	mut searcher_builder := searcher.SearcherBuilder.new()
	searcher_builder.binary_detection(searcher.BinaryDetection.quit(u8(0)))
	searcher_builder.line_number(false)
	mut searcher_ := searcher_builder.build()
	mut printer_builder := printer.StandardBuilder.new()
	printer_builder.color_specs(printer.ColorSpecs.default_with_color())
	mut printer_ := printer_builder.build(cli.stdout(.auto))

	for root in paths {
		mut candidates := if os.is_file(root.clone()) {
			[root.to_owned()]
		} else {
			os.walk_ext(root.clone(), '', hidden: true)
		}
		for path in candidates {
			if !os.is_file(path.clone()) {
				continue
			}
			printer_matcher := printer.PrinterMatcher.rust_regex(&matcher_)
			mut sink := printer_.sink_with_path(printer_matcher, &path)
			matcher_ref := regex.RegexMatcherRef.new(&matcher_)
			searcher_.search_path(matcher_ref, &path, sink) or {
				eprintln('${path}: ${err.msg()}')
				continue
			}
		}
		unsafe { candidates.free() }
	}
	printer_.flush()!
}
