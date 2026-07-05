module integration

struct MessageLine {
	typ  string
	line string
}

/// Decode JSON Lines into a Vec<Message>. If there was an error decoding,
/// this function panics.
fn json_decode(jsonlines string) []MessageLine {
	mut messages := []MessageLine{}
	for line in jsonlines.split_into_lines() {
		if line.len == 0 {
			continue
		}
		messages << MessageLine{
			typ:  line.find_between('"type":"', '"').to_owned()
			line: line.to_owned()
		}
	}
	return messages
}

fn assert_json_contains(line &string, fragment string) {
	if line.contains(fragment) {
		return
	}
	panic('JSON line missing fragment `${fragment}` in `${line}`')
}

fn assert_json_basic_match(msgs []MessageLine, replacement ?string, bytes_printed u64) {
	assert msgs[0].typ == 'begin'
	assert_json_contains(msgs[0].line, '"path":{"text":"sherlock"}')

	assert msgs[1].typ == 'context'
	assert_json_contains(msgs[1].line, '"path":{"text":"sherlock"}')
	assert_json_contains(msgs[1].line, r'"lines":{"text":"Holmeses, success in the province of detective work must always\n"}')
	assert_json_contains(msgs[1].line, '"line_number":2')
	assert_json_contains(msgs[1].line, '"absolute_offset":65')
	assert_json_contains(msgs[1].line, '"submatches":[]')

	assert msgs[2].typ == 'match'
	assert_json_contains(msgs[2].line, '"path":{"text":"sherlock"}')
	assert_json_contains(msgs[2].line, r'"lines":{"text":"be, to a very large extent, the result of luck. Sherlock Holmes\n"}')
	assert_json_contains(msgs[2].line, '"line_number":3')
	assert_json_contains(msgs[2].line, '"absolute_offset":129')
	assert_json_contains(msgs[2].line, '"match":{"text":"Sherlock Holmes"}')
	assert_json_contains(msgs[2].line, '"start":48')
	assert_json_contains(msgs[2].line, '"end":63')
	if replacement_value := replacement {
		assert_json_contains(msgs[2].line, '"replacement":{"text":"${replacement_value}"}')
	}

	assert msgs[3].typ == 'end'
	assert_json_contains(msgs[3].line, '"path":{"text":"sherlock"}')
	assert_json_contains(msgs[3].line, '"binary_offset":null')
	assert msgs[4].typ == 'summary'
	assert_json_contains(msgs[4].line, '"searches_with_match":1')
	assert_json_contains(msgs[4].line, '"bytes_printed":${bytes_printed}')
}

fn test_json_basic() {
	dir, mut cmd := setup('json_basic')
	dir.create('sherlock', sherlock)
	cmd.args(['--json', '-B1', 'Sherlock Holmes', 'sherlock'])
	msgs := json_decode(cmd.stdout())
	assert_json_basic_match(msgs, none, 494)
}

fn test_json_replacement() {
	dir, mut cmd := setup('json_replacement')
	dir.create('sherlock', sherlock)
	cmd.args(['--json', '-B1', 'Sherlock Holmes', '-r', 'John Watson', 'sherlock'])
	msgs := json_decode(cmd.stdout())
	assert_json_basic_match(msgs, 'John Watson', 531)
}

fn test_json_quiet_stats() {
	dir, mut cmd := setup('json_quiet_stats')
	dir.create('sherlock', sherlock)
	cmd.args(['--json', '--quiet', '--stats', 'Sherlock Holmes', 'sherlock'])
	msgs := json_decode(cmd.stdout())
	assert msgs[0].typ == 'summary'
	assert_json_contains(msgs[0].line, '"searches_with_match":1')
	assert_json_contains(msgs[0].line, '"bytes_searched":367')
}

fn test_json_notutf8() {
	$if windows {
		return
	}
	$if macos {
		return
	}
	dir, mut cmd := setup('json_notutf8')
	// This test does not work with PCRE2 because PCRE2 does not support the
	// `u` flag.
	if dir.is_pcre2() {
		return
	}

	name := [u8(`f`), u8(`o`), u8(`o`), u8(0xff), u8(`b`), u8(`a`), u8(`r`)].bytestr()
	contents := [u8(`q`), u8(`u`), u8(`u`), u8(`x`), u8(0xff), u8(`b`), u8(`a`),
		u8(`z`)]

	// APFS does not support creating files with invalid UTF-8 bytes, so just
	// skip the test if we can't create our file. Presumably we don't need this
	// check if we're already skipping it on macOS, but maybe other file
	// systems won't like this test either?
	if !dir.try_create_bytes(name, contents) {
		return
	}
	cmd.args(['--json', r'(?-u)\xFF'])

	msgs := json_decode(cmd.stdout())
	assert msgs[0].typ == 'begin'
	assert_json_contains(msgs[0].line, '"path":{"bytes":"Zm9v/2Jhcg=="}')
	assert msgs[1].typ == 'match'
	assert_json_contains(msgs[1].line, '"path":{"bytes":"Zm9v/2Jhcg=="}')
	assert_json_contains(msgs[1].line, '"lines":{"bytes":"cXV1eP9iYXo="}')
	assert_json_contains(msgs[1].line, '"line_number":1')
	assert_json_contains(msgs[1].line, '"absolute_offset":0')
	assert_json_contains(msgs[1].line, '"match":{"bytes":"/w=="}')
	assert_json_contains(msgs[1].line, '"start":4')
	assert_json_contains(msgs[1].line, '"end":5')
}

fn test_json_notutf8_file() {
	dir, mut cmd := setup('json_notutf8_file')
	dir.create_bytes('foo', [u8(`q`), u8(`u`), u8(`u`), u8(`x`), u8(0xff), u8(`b`),
		u8(`a`), u8(`z`)])
	cmd.args(['--json', r'(?-u)\xFF'])
	msgs := json_decode(cmd.stdout())
	assert msgs[0].typ == 'begin'
	assert_json_contains(msgs[0].line, '"path":{"text":"foo"}')
	assert msgs[1].typ == 'match'
	assert_json_contains(msgs[1].line, '"path":{"text":"foo"}')
	assert_json_contains(msgs[1].line, '"lines":{"bytes":"cXV1eP9iYXo="}')
	assert_json_contains(msgs[1].line, '"line_number":1')
	assert_json_contains(msgs[1].line, '"absolute_offset":0')
	assert_json_contains(msgs[1].line, '"match":{"bytes":"/w=="}')
	assert_json_contains(msgs[1].line, '"start":4')
	assert_json_contains(msgs[1].line, '"end":5')
}

// See: https://github.com/BurntSushi/ripgrep/issues/416
//
// This test in particular checks that our match does _not_ include the `\r`
// even though the '$' may be rewritten as '(?:\r??$)' and could thus include
// `\r` in the match.
fn test_json_crlf() {
	dir, mut cmd := setup('json_crlf')
	dir.create('sherlock', sherlock_crlf)
	cmd.args(['--json', '--crlf', r'Sherlock$', 'sherlock'])
	msgs := json_decode(cmd.stdout())
	assert_json_contains(msgs[1].line, '"match":{"text":"Sherlock"}')
	assert_json_contains(msgs[1].line, '"start":56')
	assert_json_contains(msgs[1].line, '"end":64')
}

// See: https://github.com/BurntSushi/ripgrep/issues/1095
//
// This test checks that we don't drop the \r\n in a matching line when --crlf
// mode is enabled.
fn test_json_r1095_missing_crlf() {
	dir, mut cmd := setup('json_r1095_missing_crlf')
	dir.create('foo', 'test\r\n')

	cmd.args(['--json', 'test'])
	msgs := json_decode(cmd.stdout())
	assert msgs.len == 4
	assert_json_contains(msgs[1].line, r'"lines":{"text":"test\r\n"}')

	cmd.arg('--crlf')
	msgs_crlf := json_decode(cmd.stdout())
	assert msgs_crlf.len == 4
	assert_json_contains(msgs_crlf[1].line, r'"lines":{"text":"test\r\n"}')
}

// See: https://github.com/BurntSushi/ripgrep/issues/1095
//
// This test checks that we don't return empty submatches when matching a `\n`
// in CRLF mode.
fn test_json_r1095_crlf_empty_match() {
	dir, mut cmd := setup('json_r1095_crlf_empty_match')
	dir.create('foo', 'test\r\n\n')

	cmd.args(['-U', '--json', '\n'])
	msgs := json_decode(cmd.stdout())
	assert msgs.len == 4
	assert_json_contains(msgs[1].line, r'"lines":{"text":"test\r\n\n"}')
	assert msgs[1].line.count(r'"match":{"text":"\n"}') == 2

	cmd.arg('--crlf')
	msgs_crlf := json_decode(cmd.stdout())
	assert msgs_crlf.len == 4
	assert_json_contains(msgs_crlf[1].line, r'"lines":{"text":"test\r\n\n"}')
	assert msgs_crlf[1].line.count(r'"match":{"text":"\n"}') == 2
}

// See: https://github.com/BurntSushi/ripgrep/issues/1412
fn test_json_r1412_look_behind_match_missing() {
	dir, mut cmd := setup('json_r1412_look_behind_match_missing')
	// Only PCRE2 supports look-around.
	if !dir.is_pcre2() {
		return
	}

	dir.create('test', 'foo\nbar\n')

	cmd.args(['-U', '--json', r'(?<=foo\n)bar'])
	msgs := json_decode(cmd.stdout())
	assert msgs.len == 4
	assert msgs[1].typ == 'match'
	assert_json_contains(msgs[1].line, '"lines":{"text":"bar\n"}')
	assert msgs[1].line.count('"match":') == 1
}
