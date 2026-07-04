module cli

import os
import printer

$if !windows {
	#include <unistd.h>
}

const standard_stream_block_capacity = 32 * 1024

$if !windows {
	fn C.write(fd int, buf voidptr, count int) int
}

pub enum ColorChoice {
	never
	auto
	always
	ansi
}

/// A writer that supports coloring with either line or block buffering.
pub struct StandardStream implements printer.WriteColor {
	color_choice ColorChoice
mut:
	kind   StandardStreamKind
	fd     int
	buffer []u8
}

/// Returns a possibly buffered writer to stdout for the given color choice.
///
/// The writer returned is either line buffered or block buffered. The decision
/// between these two is made automatically based on whether a tty is attached
/// to stdout or not. If a tty is attached, then line buffering is used.
/// Otherwise, block buffering is used. In general, block buffering is more
/// efficient, but may increase the time it takes for the end user to see the
/// first bits of output.
///
/// If you need more fine grained control over the buffering mode, then use one
/// of `stdout_buffered_line` or `stdout_buffered_block`.
///
/// The color choice given is passed along to the underlying writer. To
/// completely disable colors in all cases, use `ColorChoice::Never`.
pub fn stdout(color_choice ColorChoice) StandardStream {
	if is_tty_stdout() {
		return stdout_buffered_line(color_choice)
	}
	return stdout_buffered_block(color_choice)
}

/// Returns a line buffered writer to stdout for the given color choice.
///
/// This writer is useful when printing results directly to a tty such that
/// users see output as soon as it's written. The downside of this approach
/// is that it can be slower, especially when there is a lot of output.
///
/// You might consider using [`stdout`] instead, which chooses the buffering
/// strategy automatically based on whether stdout is connected to a tty.
pub fn stdout_buffered_line(color_choice ColorChoice) StandardStream {
	return StandardStream.new(.line_buffered, color_choice)
}

/// Returns a block buffered writer to stdout for the given color choice.
///
/// This writer is useful when printing results to a file since it amortizes
/// the cost of writing data. The downside of this approach is that it can
/// increase the latency of display output when writing to a tty.
///
/// You might consider using [`stdout`] instead, which chooses the buffering
/// strategy automatically based on whether stdout is connected to a tty.
pub fn stdout_buffered_block(color_choice ColorChoice) StandardStream {
	return StandardStream.new(.block_buffered, color_choice)
}

enum StandardStreamKind {
	line_buffered
	block_buffered
}

fn StandardStream.new(kind StandardStreamKind, color_choice ColorChoice) StandardStream {
	return StandardStream{
		color_choice: color_choice
		kind:         kind
		fd:           1
		buffer:       []u8{}
	}
}

/// A writer that can create independently writable buffers and print them to
/// stdout.
pub struct BufferWriter {
	color_choice ColorChoice
mut:
	fd        int
	separator ?[]u8
	printed   bool
}

/// A buffer that supports color and hyperlink escapes.
pub struct Buffer implements IClone {
	color_choice ColorChoice
mut:
	bytes []u8
}

/// Creates a new buffer writer for stdout.
pub fn BufferWriter.stdout(color_choice ColorChoice) BufferWriter {
	return BufferWriter{
		color_choice: color_choice
		fd:           1
		separator:    none
		printed:      false
	}
}

/// Sets the separator printed between non-empty buffers.
pub fn (mut wtr BufferWriter) separator(separator ?[]u8) {
	if sep := separator {
		wtr.separator = sep.clone()
	} else {
		wtr.separator = none
	}
}

/// Creates a new empty buffer.
pub fn (wtr BufferWriter) buffer() Buffer {
	return Buffer{
		color_choice: wtr.color_choice
		bytes:        []u8{}
	}
}

/// Prints a buffer to stdout.
pub fn (mut wtr BufferWriter) print(buffer &Buffer) ! {
	if buffer.is_empty() {
		return
	}
	if wtr.printed {
		if sep := wtr.separator {
			write_all_fd(wtr.fd, sep)
		}
	}
	chunk := buffer.as_slice()
	write_all_fd(wtr.fd, chunk)
	wtr.printed = true
	flush_stdout()
}

/// Returns the contents of this buffer.
pub fn (buffer Buffer) as_slice() []u8 {
	return buffer.bytes.clone()
}

/// Returns true when this buffer is empty.
pub fn (buffer Buffer) is_empty() bool {
	return buffer.bytes.len == 0
}

/// Clears the contents of this buffer.
pub fn (mut buffer Buffer) clear() {
	buffer.bytes = []u8{}
}

pub fn (mut buffer Buffer) write(buf []u8) !int {
	buffer.bytes << buf
	return buf.len
}

pub fn (mut buffer Buffer) flush() ! {
	_ = buffer
}

pub fn (mut buffer Buffer) set_color(spec printer.ColorSpec) ! {
	if !buffer.supports_color() {
		return
	}
	ansi := ansi_for_color_spec(spec)
	if ansi.len == 0 {
		return
	}
	buffer.bytes << ansi.bytes()
}

pub fn (mut buffer Buffer) set_hyperlink(link printer.HyperlinkSpec) ! {
	if !buffer.supports_hyperlinks() {
		return
	}
	ansi := bytes_for_hyperlink(link)
	if ansi.len == 0 {
		return
	}
	buffer.bytes << ansi
}

pub fn (mut buffer Buffer) reset() ! {
	if !buffer.supports_color() {
		return
	}
	buffer.bytes << '\x1b[0m'.bytes()
}

pub fn (buffer Buffer) supports_color() bool {
	return match buffer.color_choice {
		.never { false }
		.auto { is_tty_stdout() }
		.always, .ansi { true }
	}
}

pub fn (buffer Buffer) supports_hyperlinks() bool {
	return buffer.supports_color()
}

pub fn (buffer Buffer) is_synchronous() bool {
	_ = buffer
	return false
}

fn (mut stream StandardStream) emit(buf []u8) ! {
	if stream.kind == .block_buffered {
		stream.buffer << buf
		if stream.buffer.len >= standard_stream_block_capacity {
			stream.flush()!
		}
		return
	}
	stream.write_direct(buf)!
	if bytes_contain_newline(buf) {
		flush_stdout()
	}
}

fn (mut stream StandardStream) write_direct(buf []u8) ! {
	write_all_fd(stream.fd, buf)
}

fn write_all_fd(fd int, buf []u8) {
	if fd == -1 || buf.len == 0 {
		return
	}
	$if windows {
		os.fd_write(fd, buf.bytestr())
	} $else {
		mut written_total := 0
		for written_total < buf.len {
			ptr := unsafe { &u8(buf.data) + written_total }
			written := int(C.write(fd, ptr, buf.len - written_total))
			if written <= 0 {
				return
			}
			written_total += written
		}
	}
}

fn bytes_contain_newline(buf []u8) bool {
	for b in buf {
		if b == `\n` {
			return true
		}
	}
	return false
}

pub fn (mut stream StandardStream) write(buf []u8) !int {
	stream.emit(buf)!
	return buf.len
}

pub fn (mut stream StandardStream) flush() ! {
	if stream.buffer.len > 0 {
		buffer := stream.buffer.clone()
		stream.buffer = []u8{}
		stream.write_direct(buffer)!
	}
	flush_stdout()
}

pub fn (stream StandardStream) supports_color() bool {
	return match stream.color_choice {
		.never { false }
		.auto { is_tty_stdout() }
		.always, .ansi { true }
	}
}

pub fn (stream StandardStream) supports_hyperlinks() bool {
	return stream.supports_color()
}

pub fn (mut stream StandardStream) set_color(spec printer.ColorSpec) ! {
	if !stream.supports_color() {
		return
	}
	ansi := ansi_for_color_spec(spec)
	if ansi.len == 0 {
		return
	}
	stream.emit(ansi.bytes())!
}

pub fn (mut stream StandardStream) set_hyperlink(link printer.HyperlinkSpec) ! {
	if !stream.supports_hyperlinks() {
		return
	}
	ansi := bytes_for_hyperlink(link)
	if ansi.len == 0 {
		return
	}
	stream.emit(ansi)!
}

pub fn (mut stream StandardStream) reset() ! {
	if !stream.supports_color() {
		return
	}
	stream.emit('\x1b[0m'.bytes())!
}

pub fn (stream StandardStream) is_synchronous() bool {
	return stream.kind == .line_buffered
}

fn ansi_for_color_spec(spec printer.ColorSpec) string {
	mut codes := []string{}
	if bold := spec.bold() {
		codes << if bold { '1' } else { '22' }
	}
	if underline := spec.underline() {
		codes << if underline { '4' } else { '24' }
	}
	if italic := spec.italic() {
		codes << if italic { '3' } else { '23' }
	}
	intense := spec.intense() or { false }
	if fg := spec.fg() {
		codes << ansi_for_color(fg, false, intense)
	}
	if bg := spec.bg() {
		codes << ansi_for_color(bg, true, intense)
	}
	if codes.len == 0 {
		return ''
	}
	return '\x1b[${codes.join(';')}m'
}

fn ansi_for_color(color printer.Color, is_bg bool, intense bool) string {
	base := if is_bg { 40 } else { 30 }
	bright_base := if is_bg { 100 } else { 90 }
	match color.kind {
		.black, .red, .green, .yellow, .blue, .magenta, .cyan, .white {
			offset := match color.kind {
				.black { 0 }
				.red { 1 }
				.green { 2 }
				.yellow { 3 }
				.blue { 4 }
				.magenta { 5 }
				.cyan { 6 }
				.white { 7 }
				else { 0 }
			}

			if intense {
				return (bright_base + offset).str()
			}
			return (base + offset).str()
		}
		.ansi256 {
			prefix := if is_bg { '48' } else { '38' }
			return '${prefix};5;${color.value}'
		}
		.rgb {
			prefix := if is_bg { '48' } else { '38' }
			return '${prefix};2;${color.red};${color.green};${color.blue}'
		}
	}
}

fn bytes_for_hyperlink(link printer.HyperlinkSpec) []u8 {
	mut out := []u8{}
	return match link.kind {
		.open {
			out << '\x1b]8;;'.bytes()
			out << link.url
			out << '\x1b\\'.bytes()
			out
		}
		.close {
			out << '\x1b]8;;\x1b\\'.bytes()
			out
		}
	}
}
