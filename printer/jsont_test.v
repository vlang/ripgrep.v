module printer

fn test_base64_basic() {
	assert base64_standard(''.bytes()) == ''
	assert base64_standard('f'.bytes()) == 'Zg=='
	assert base64_standard('fo'.bytes()) == 'Zm8='
	assert base64_standard('foo'.bytes()) == 'Zm9v'
	assert base64_standard('foob'.bytes()) == 'Zm9vYg=='
	assert base64_standard('fooba'.bytes()) == 'Zm9vYmE='
	assert base64_standard('foobar'.bytes()) == 'Zm9vYmFy'
}
