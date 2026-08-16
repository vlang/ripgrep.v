module printer

import matcher
import regex
import searcher

fn test_custom_decimal_format() {
	ints := [u64(0), 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 100, 123, 18446744073709551615]
	for n in ints {
		assert n.str() == DecimalFormatter.new(n).as_bytes().bytestr()
	}
}

fn test_trim_ascii_prefix_stops_at_crlf_bytes() {
	line_term := matcher.LineTerminator.crlf()
	assert trim_ascii_prefix(line_term, '\r\n'.bytes(), matcher.Match.new(0, 2)) == matcher.Match.new(0,
		2)
	assert trim_ascii_prefix(line_term, ' \r\n'.bytes(), matcher.Match.new(0, 3)) == matcher.Match.new(1,
		3)
}

fn test_replacer_returns_borrowed_replacement() {
	regex_matcher := regex.RegexMatcher.new(r'Doctor (\w+)')!
	matcher_ := PrinterMatcher.rust_regex(&regex_matcher)
	searcher_ := searcher.Searcher.new()
	haystack := 'Doctor Watson\n'.bytes()
	mut replacer := Replacer.new()
	replacer.replace_all(&searcher_, &matcher_, haystack, matcher.Match.new(0, haystack.len),
		r'doctah $1 MD'.bytes())!
	{
		replacement := replacer.replacement() or { panic('missing replacement') }
		assert replacement.bytes.bytestr() == 'doctah Watson MD\n'
		assert replacement.matches == [matcher.Match.new(0, 16)]
	}
	replacer.clear()
	assert replacer.replacement() == none
}
