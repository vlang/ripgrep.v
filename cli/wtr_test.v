module cli

import os
import printer

fn test_buffer_records_plain_bytes_and_clear() {
	wtr := BufferWriter.stdout(.never)
	mut buffer := wtr.buffer()

	n := buffer.write('abc'.bytes()) or { panic(err.msg()) }
	assert n == 3
	assert buffer.as_slice() == 'abc'.bytes()

	buffer.clear()
	assert buffer.is_empty()
	assert buffer.as_slice() == []u8{}
}

fn test_buffer_color_emits_ansi_when_enabled() {
	wtr := BufferWriter.stdout(.always)
	mut buffer := wtr.buffer()
	mut spec := printer.ColorSpec{}
	spec.set_fg(printer.color_red())

	buffer.set_color(spec) or { panic(err.msg()) }
	buffer.write('x'.bytes()) or { panic(err.msg()) }
	buffer.reset() or { panic(err.msg()) }

	assert buffer.as_slice().bytestr() == '\x1b[0m\x1b[31mx\x1b[0m'
}

fn test_buffer_empty_color_spec_resets_when_enabled() {
	wtr := BufferWriter.stdout(.always)
	mut buffer := wtr.buffer()
	spec := printer.ColorSpec{}

	buffer.set_color(spec) or { panic(err.msg()) }
	buffer.write('x'.bytes()) or { panic(err.msg()) }

	assert buffer.as_slice().bytestr() == '\x1b[0mx'
}

fn test_buffer_writer_prints_separator_between_non_empty_buffers() {
	mut pipe := os.pipe() or { panic(err.msg()) }
	defer {
		pipe.close()
	}
	mut wtr := BufferWriter{
		color_choice: .never
		fd:           pipe.write_fd
		separator:    none
		printed:      false
	}
	wtr.separator('--'.bytes())

	empty := wtr.buffer()
	wtr.print(&empty) or { panic(err.msg()) }

	mut one := wtr.buffer()
	one.write('one'.bytes()) or { panic(err.msg()) }
	wtr.print(&one) or { panic(err.msg()) }

	mut two := wtr.buffer()
	two.write('two'.bytes()) or { panic(err.msg()) }
	wtr.print(&two) or { panic(err.msg()) }

	os.fd_close(pipe.write_fd)
	pipe.write_fd = -1
	mut out := []u8{len: 16}
	n := pipe.read(mut out) or { panic(err.msg()) }
	assert out[..n].bytestr() == 'one--two'
}

fn test_buffer_writer_reports_closed_fd_error() {
	mut pipe := os.pipe() or { panic(err.msg()) }
	os.fd_close(pipe.write_fd)
	defer {
		os.fd_close(pipe.read_fd)
	}
	mut wtr := BufferWriter{
		color_choice: .never
		fd:           pipe.write_fd
		separator:    none
		printed:      false
	}
	mut buffer := wtr.buffer()
	buffer.write('data'.bytes()) or { panic(err.msg()) }
	wtr.print(&buffer) or {
		assert err.code() != 0
		assert !is_broken_pipe_error(err)
		return
	}
	panic('expected write to closed fd to fail')
}

fn test_buffer_writer_reports_broken_pipe() {
	$if windows {
		return
	}
	os.signal_ignore(.pipe)
	mut pipe := os.pipe() or { panic(err.msg()) }
	os.fd_close(pipe.read_fd)
	defer {
		os.fd_close(pipe.write_fd)
	}
	mut wtr := BufferWriter{
		color_choice: .never
		fd:           pipe.write_fd
		separator:    none
		printed:      false
	}
	mut buffer := wtr.buffer()
	buffer.write('data'.bytes()) or { panic(err.msg()) }
	wtr.print(&buffer) or {
		assert is_broken_pipe_error(err)
		return
	}
	panic('expected write to broken pipe to fail')
}

fn test_empty_error_is_not_broken_pipe() {
	assert !is_broken_pipe_error(error(''))
}
