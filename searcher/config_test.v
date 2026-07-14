module searcher

import matcher

fn assert_no_u64_config(got ?u64) {
	if _ := got {
		assert false
	}
}

fn assert_no_encoding(got ?Encoding) {
	if _ := got {
		assert false
	}
}

fn test_searcher_new_defaults() {
	searcher := Searcher.new()
	assert searcher.line_terminator() == matcher.LineTerminator.default()
	assert searcher.binary_detection().quit_byte() == none
	assert !searcher.invert_match()
	assert searcher.line_number()
	assert !searcher.multi_line()
	assert !searcher.stop_on_nonmatch()
	assert searcher.after_context() == 0
	assert searcher.before_context() == 0
	assert !searcher.passthru()
	assert_no_u64_config(searcher.max_matches())
	assert_no_encoding(searcher.config.encoding)
	assert !searcher.config.mmap.is_enabled()
}

fn test_searcher_builder_sets_config() {
	mut builder := SearcherBuilder.new()
	builder.line_terminator(matcher.LineTerminator.byte(`\x00`))
	builder.invert_match(true)
	builder.line_number(false)
	builder.multi_line(true)
	builder.after_context(2)
	builder.before_context(3)
	builder.binary_detection(BinaryDetection.quit(0))
	builder.memory_map(MmapChoice.auto())
	builder.bom_sniffing(false)
	builder.stop_on_nonmatch(true)
	builder.max_matches(u64(7))
	searcher := builder.build()

	assert searcher.line_terminator() == matcher.LineTerminator.byte(`\x00`)
	assert searcher.invert_match()
	assert !searcher.line_number()
	assert searcher.multi_line()
	assert searcher.after_context() == 2
	assert searcher.before_context() == 3
	assert searcher.binary_detection().quit_byte() or { 255 } == 0
	assert searcher.config.mmap.is_enabled()
	assert !searcher.config.bom_sniffing
	assert searcher.stop_on_nonmatch()
	assert searcher.max_matches() or { 0 } == 7
}

fn test_searcher_builder_passthru_clears_context() {
	mut builder := SearcherBuilder.new()
	builder.after_context(10)
	builder.before_context(20)
	builder.passthru(true)
	searcher := builder.build()

	assert searcher.passthru()
	assert searcher.after_context() == 0
	assert searcher.before_context() == 0
	assert searcher.config.max_context() == 0
}

fn test_searcher_builder_sets_and_clears_encoding() {
	encoding := Encoding.new('utf-16')!
	mut builder := SearcherBuilder.new()
	builder.encoding(encoding)
	searcher := builder.build()

	got := searcher.config.encoding or { panic('missing encoding') }
	assert got.label == 'UTF-16LE'

	builder.encoding(none)
	still_owned := searcher.config.encoding or { panic('built searcher lost its encoding') }
	assert still_owned.label == 'UTF-16LE'
	cleared := builder.build()
	assert_no_encoding(cleared.config.encoding)
}

fn test_searcher_encoding_normalizes_labels() {
	assert (Encoding.new('utf8')!).label == 'UTF-8'
	assert (Encoding.new(' UTF-8 ')!).label == 'UTF-8'
	assert (Encoding.new('latin1')!).label == 'windows-1252'
	assert (Encoding.new('us-ascii')!).label == 'windows-1252'
	assert (Encoding.new('unicodefffe')!).label == 'UTF-16BE'
	assert (Encoding.new('ucs-2')!).label == 'UTF-16LE'
	assert (Encoding.new('cp1251')!).label == 'windows-1251'
	assert (Encoding.new('latin5')!).label == 'windows-1254'
	assert (Encoding.new('tis-620')!).label == 'windows-874'
	assert (Encoding.new('x-mac-roman')!).label == 'macintosh'
	assert (Encoding.new('x-mac-ukrainian')!).label == 'x-mac-cyrillic'
	assert (Encoding.new('x-user-defined')!).label == 'x-user-defined'
}

fn test_searcher_encoding_rejects_non_encoding_rs_labels() {
	for label in ['utf16le', 'utf16be', 'utf-32', 'utf-32le', 'utf32be', 'eucjp', 'replacement'] {
		if _ := Encoding.new(label) {
			panic('encoding_rs rejects label ${label}')
		}
	}
	for replacement_label in ['hz-gb-2312', 'iso-2022-cn', 'iso-2022-cn-ext', 'iso-2022-kr',
		'csiso2022kr'] {
		if _ := Encoding.new(replacement_label) {
			panic('for_label_no_replacement rejects label ${replacement_label}')
		}
	}
	if _ := Encoding.new('\u00a0utf-8\u00a0') {
		panic('encoding_rs trims ASCII whitespace only')
	}
	assert (Encoding.new('\fUTF-8\r')!).label == 'UTF-8'
}

fn test_searcher_encoding_rejects_unknown_label() {
	Encoding.new('not-an-encoding') or {
		assert err.msg() == 'grep config error: unknown encoding: not-an-encoding'
		return
	}
	assert false
}

fn test_searcher_unknown_encoding_error_replaces_invalid_utf8() {
	err := ConfigError.unknown_encoding([u8(0xff), `x`])
	assert err.msg() == 'grep config error: unknown encoding: �x'
}

fn test_searcher_builder_heap_limit_configures_line_buffer() {
	mut builder := SearcherBuilder.new()
	builder.heap_limit(usize(12))
	builder.binary_detection(BinaryDetection.convert(0))
	searcher := builder.build()

	assert searcher.line_buffer.config.capacity == 12
	assert searcher.line_buffer.config.buffer_alloc.kind == .error
	assert searcher.line_buffer.config.buffer_alloc.additional == 0
	assert searcher.line_buffer.config.binary.convert_byte() or { 255 } == 0
}
