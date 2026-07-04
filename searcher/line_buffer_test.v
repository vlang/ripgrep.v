module searcher

import io

const sherlock = 'For the Doctor Watsons of this world, as opposed to the Sherlock\nHolmeses, success in the province of detective work must always\nbe, to a very large extent, the result of luck. Sherlock Holmes\ncan extract a clew from a wisp of straw or a flake of cigar ash;\nbut Doctor Watson has to have it taken out for him and dusted,\nand exhibited clearly, with a label attached.'

struct ByteSliceReader {
mut:
	bytes []u8
	pos   int
}

fn ByteSliceReader.new(slice string) ByteSliceReader {
	return ByteSliceReader{
		bytes: slice.bytes()
	}
}

fn (mut rdr ByteSliceReader) read(mut buf []u8) !int {
	if rdr.pos >= rdr.bytes.len {
		return io.Eof{}
	}
	nread := copy(mut buf, rdr.bytes[rdr.pos..])
	rdr.pos += nread
	return nread
}

fn assert_replace(slice string, src u8, replacement u8, expected string, expected_pos ?usize) {
	mut dst := slice.bytes()
	pos := replace_bytes(mut dst, src, replacement)
	assert dst.bytestr() == expected
	assert_optional_usize(pos, expected_pos)
}

fn assert_optional_usize(got ?usize, expected ?usize) {
	if expected_value := expected {
		got_value := got or {
			assert false
			return
		}

		assert got_value == expected_value
	} else {
		if _ := got {
			assert false
		}
	}
}

fn assert_no_u64(got ?u64) {
	if _ := got {
		assert false
	}
}

fn assert_some_u64(got ?u64, expected u64) {
	got_value := got or {
		assert false
		return
	}

	assert got_value == expected
}

fn test_replace() {
	assert_replace('', `b`, `z`, '', none)
	assert_replace('a', `a`, `a`, 'a', none)
	assert_replace('a', `b`, `z`, 'a', none)
	assert_replace('abc', `b`, `z`, 'azc', usize(1))
	assert_replace('abb', `b`, `z`, 'azz', usize(1))
	assert_replace('aba', `a`, `z`, 'zbz', usize(0))
	assert_replace('bbb', `b`, `z`, 'zzz', usize(0))
	assert_replace('bac', `b`, `z`, 'zac', usize(0))
}

fn test_buffer_basics1() {
	bytes := 'homer\nlisa\nmaggie'
	mut linebuf := LineBufferBuilder.new().build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert rdr.buffer().len == 0

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == 'homer\nlisa\n'
	assert rdr.absolute_byte_offset() == 0
	rdr.consume(5)
	assert rdr.absolute_byte_offset() == 5
	rdr.consume_all()
	assert rdr.absolute_byte_offset() == 11

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == 'maggie'
	rdr.consume_all()

	assert !rdr.fill()!
	assert rdr.absolute_byte_offset() == u64(bytes.len)
	assert_no_u64(rdr.binary_byte_offset())
}

fn test_buffer_basics2() {
	bytes := 'homer\nlisa\nmaggie\n'
	mut linebuf := LineBufferBuilder.new().build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == 'homer\nlisa\nmaggie\n'
	rdr.consume_all()

	assert !rdr.fill()!
	assert rdr.absolute_byte_offset() == u64(bytes.len)
	assert_no_u64(rdr.binary_byte_offset())
}

fn test_buffer_basics3() {
	bytes := '\n'
	mut linebuf := LineBufferBuilder.new().build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == '\n'
	rdr.consume_all()

	assert !rdr.fill()!
	assert rdr.absolute_byte_offset() == u64(bytes.len)
	assert_no_u64(rdr.binary_byte_offset())
}

fn test_buffer_basics4() {
	bytes := '\n\n'
	mut linebuf := LineBufferBuilder.new().build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == '\n\n'
	rdr.consume_all()

	assert !rdr.fill()!
	assert rdr.absolute_byte_offset() == u64(bytes.len)
	assert_no_u64(rdr.binary_byte_offset())
}

fn test_buffer_empty() {
	bytes := ''
	mut linebuf := LineBufferBuilder.new().build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert !rdr.fill()!
	assert rdr.absolute_byte_offset() == u64(bytes.len)
	assert_no_u64(rdr.binary_byte_offset())
}

fn test_buffer_zero_capacity() {
	bytes := 'homer\nlisa\nmaggie'
	mut builder := LineBufferBuilder.new()
	builder.capacity(0)
	mut linebuf := builder.build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	for rdr.fill()! {
		rdr.consume_all()
	}
	assert rdr.absolute_byte_offset() == u64(bytes.len)
	assert_no_u64(rdr.binary_byte_offset())
}

fn test_buffer_small_capacity() {
	bytes := 'homer\nlisa\nmaggie'
	mut builder := LineBufferBuilder.new()
	builder.capacity(1)
	mut linebuf := builder.build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	mut got := []u8{}
	for rdr.fill()! {
		got << rdr.buffer()
		rdr.consume_all()
	}
	assert bytes == got.bytestr()
	assert rdr.absolute_byte_offset() == u64(bytes.len)
	assert_no_u64(rdr.binary_byte_offset())
}

fn test_buffer_limited_capacity1() {
	bytes := 'homer\nlisa\nmaggie'
	mut builder := LineBufferBuilder.new()
	builder.capacity(1)
	builder.buffer_alloc(BufferAllocation.error(5))
	mut linebuf := builder.build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == 'homer\n'
	rdr.consume_all()

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == 'lisa\n'
	rdr.consume_all()

	if _ := rdr.fill() {
		assert false
	}

	assert rdr.buffer().bytestr() == 'm'
	rdr.consume_all()

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == 'aggie'
	rdr.consume_all()

	assert !rdr.fill()!
}

fn test_buffer_limited_capacity2() {
	bytes := 'homer\nlisa\nmaggie'
	mut builder := LineBufferBuilder.new()
	builder.capacity(1)
	builder.buffer_alloc(BufferAllocation.error(6))
	mut linebuf := builder.build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == 'homer\n'
	rdr.consume_all()

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == 'lisa\n'
	rdr.consume_all()

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == 'maggie'
	rdr.consume_all()

	assert !rdr.fill()!
}

fn test_buffer_limited_capacity3() {
	bytes := 'homer\nlisa\nmaggie'
	mut builder := LineBufferBuilder.new()
	builder.capacity(1)
	builder.buffer_alloc(BufferAllocation.error(0))
	mut linebuf := builder.build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	if _ := rdr.fill() {
		assert false
	}
	assert rdr.buffer().bytestr() == ''
}

fn test_buffer_binary_none() {
	bytes := 'homer\nli\x00sa\nmaggie\n'
	mut linebuf := LineBufferBuilder.new().build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert rdr.buffer().len == 0

	assert rdr.fill()!
	got := rdr.buffer()
	expected := bytes.bytes()
	assert got == expected
	rdr.consume_all()

	assert !rdr.fill()!
	assert rdr.absolute_byte_offset() == u64(bytes.len)
	assert_no_u64(rdr.binary_byte_offset())
}

fn test_buffer_binary_quit1() {
	bytes := 'homer\nli\x00sa\nmaggie\n'
	mut builder := LineBufferBuilder.new()
	builder.binary_detection(BinaryDetection.quit(0))
	mut linebuf := builder.build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert rdr.buffer().len == 0

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == 'homer\nli'
	rdr.consume_all()

	assert !rdr.fill()!
	assert rdr.absolute_byte_offset() == 8
	assert_some_u64(rdr.binary_byte_offset(), 8)
}

fn test_buffer_binary_quit2() {
	bytes := '\x00homer\nlisa\nmaggie\n'
	mut builder := LineBufferBuilder.new()
	builder.binary_detection(BinaryDetection.quit(0))
	mut linebuf := builder.build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert !rdr.fill()!
	assert rdr.buffer().bytestr() == ''
	assert rdr.absolute_byte_offset() == 0
	assert_some_u64(rdr.binary_byte_offset(), 0)
}

fn test_buffer_binary_quit3() {
	bytes := 'homer\nlisa\nmaggie\n\x00'
	mut builder := LineBufferBuilder.new()
	builder.binary_detection(BinaryDetection.quit(0))
	mut linebuf := builder.build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert rdr.buffer().len == 0

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == 'homer\nlisa\nmaggie\n'
	rdr.consume_all()

	assert !rdr.fill()!
	assert rdr.absolute_byte_offset() == u64(bytes.len - 1)
	assert_some_u64(rdr.binary_byte_offset(), u64(bytes.len - 1))
}

fn test_buffer_binary_quit4() {
	bytes := 'homer\nlisa\nmaggie\x00\n'
	mut builder := LineBufferBuilder.new()
	builder.binary_detection(BinaryDetection.quit(0))
	mut linebuf := builder.build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert rdr.buffer().len == 0

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == 'homer\nlisa\nmaggie'
	rdr.consume_all()

	assert !rdr.fill()!
	assert rdr.absolute_byte_offset() == u64(bytes.len - 2)
	assert_some_u64(rdr.binary_byte_offset(), u64(bytes.len - 2))
}

fn test_buffer_binary_quit5() {
	mut builder := LineBufferBuilder.new()
	builder.binary_detection(BinaryDetection.quit(`u`))
	mut linebuf := builder.build()
	mut source := ByteSliceReader.new(sherlock)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert rdr.buffer().len == 0

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == 'For the Doctor Watsons of this world, as opposed to the Sherlock\nHolmeses, s'
	rdr.consume_all()

	assert !rdr.fill()!
	assert rdr.absolute_byte_offset() == 76
	assert_some_u64(rdr.binary_byte_offset(), 76)
	assert sherlock.bytes()[76] == `u`
}

fn test_buffer_binary_convert1() {
	bytes := 'homer\nli\x00sa\nmaggie\n'
	mut builder := LineBufferBuilder.new()
	builder.binary_detection(BinaryDetection.convert(0))
	mut linebuf := builder.build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert rdr.buffer().len == 0

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == 'homer\nli\nsa\nmaggie\n'
	rdr.consume_all()

	assert !rdr.fill()!
	assert rdr.absolute_byte_offset() == u64(bytes.len)
	assert_some_u64(rdr.binary_byte_offset(), 8)
}

fn test_buffer_binary_convert2() {
	bytes := '\x00homer\nlisa\nmaggie\n'
	mut builder := LineBufferBuilder.new()
	builder.binary_detection(BinaryDetection.convert(0))
	mut linebuf := builder.build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert rdr.buffer().len == 0

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == '\nhomer\nlisa\nmaggie\n'
	rdr.consume_all()

	assert !rdr.fill()!
	assert rdr.absolute_byte_offset() == u64(bytes.len)
	assert_some_u64(rdr.binary_byte_offset(), 0)
}

fn test_buffer_binary_convert3() {
	bytes := 'homer\nlisa\nmaggie\n\x00'
	mut builder := LineBufferBuilder.new()
	builder.binary_detection(BinaryDetection.convert(0))
	mut linebuf := builder.build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert rdr.buffer().len == 0

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == 'homer\nlisa\nmaggie\n\n'
	rdr.consume_all()

	assert !rdr.fill()!
	assert rdr.absolute_byte_offset() == u64(bytes.len)
	assert_some_u64(rdr.binary_byte_offset(), u64(bytes.len - 1))
}

fn test_buffer_binary_convert4() {
	bytes := 'homer\nlisa\nmaggie\x00\n'
	mut builder := LineBufferBuilder.new()
	builder.binary_detection(BinaryDetection.convert(0))
	mut linebuf := builder.build()
	mut source := ByteSliceReader.new(bytes)
	mut rdr := LineBufferReader.new(&source, &linebuf)

	assert rdr.buffer().len == 0

	assert rdr.fill()!
	assert rdr.buffer().bytestr() == 'homer\nlisa\nmaggie\n\n'
	rdr.consume_all()

	assert !rdr.fill()!
	assert rdr.absolute_byte_offset() == u64(bytes.len)
	assert_some_u64(rdr.binary_byte_offset(), u64(bytes.len - 2))
}
