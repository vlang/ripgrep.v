module printer

import time

fn test_base64_basic() {
	assert base64_standard(''.bytes()) == ''
	assert base64_standard('f'.bytes()) == 'Zg=='
	assert base64_standard('fo'.bytes()) == 'Zm8='
	assert base64_standard('foo'.bytes()) == 'Zm9v'
	assert base64_standard('foob'.bytes()) == 'Zm9vYg=='
	assert base64_standard('fooba'.bytes()) == 'Zm9vYmE='
	assert base64_standard('foobar'.bytes()) == 'Zm9vYmFy'
}

fn test_message_pretty_json() {
	msg := Message.begin(Begin{})
	assert msg.to_json_pretty() == '{\n  "type": "begin",\n  "data": {\n    "path": null\n  }\n}'
}

fn test_stats_json_preserves_subsecond_nanoseconds() {
	mut stats := Stats.new()
	stats.add_elapsed(time.second + 234 * time.nanosecond)
	encoded := stats_to_json(stats)
	assert encoded.contains('"secs":1')
	assert encoded.contains('"nanos":234')
	assert encoded.contains('"human":"1.000000s"')
}

fn test_json_quote_uses_standard_short_control_escapes() {
	assert json_quote('\b\f\n\r\t') == r'"\b\f\n\r\t"'
}
