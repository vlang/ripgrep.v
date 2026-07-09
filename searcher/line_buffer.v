module searcher

import io

$if !windows {
	#include <string.h>
	fn C.memchr(s voidptr, c int, n u64) voidptr
}

/// The default buffer capacity that we use for the line buffer.
pub const default_buffer_capacity = 64 * (1 << 10) // 64 KB

enum BufferAllocationKind {
	eager
	error
}

/// The behavior of a searcher in the face of long lines and big contexts.
///
/// When searching data incrementally using a fixed size buffer, this controls
/// the amount of *additional* memory to allocate beyond the size of the buffer
/// to accommodate lines (which may include the lines in a context window, when
/// enabled) that do not fit in the buffer.
///
/// The default is to eagerly allocate without a limit.
struct BufferAllocation implements IClone {
	kind       BufferAllocationKind
	additional usize
}

/// Attempt to expand the size of the buffer until either at least the next
/// line fits into memory or until all available memory is exhausted.
///
/// This is the default.
fn BufferAllocation.eager() BufferAllocation {
	return BufferAllocation{
		kind: .eager
	}
}

/// Limit the amount of additional memory allocated to the given size. If
/// a line is found that requires more memory than is allowed here, then
/// stop reading and return an error.
fn BufferAllocation.error(additional usize) BufferAllocation {
	return BufferAllocation{
		kind:       .error
		additional: additional
	}
}

/// Create a new error to be used when a configured allocation limit has been
/// reached.
fn alloc_error(limit usize) IError {
	return error('configured allocation limit (${limit}) exceeded')
}

/// Returns true if and only if the detection heuristic demands that
/// the line buffer stop read data once binary data is observed.
fn (d BinaryDetection) is_quit() bool {
	return d.kind == .quit
}

struct LineBufferConfig implements IClone {
	/// The number of bytes to attempt to read at a time.
	capacity usize
	/// The line terminator.
	lineterm u8
	/// The behavior for handling long lines.
	buffer_alloc BufferAllocation
	/// When set, the presence of the given byte indicates binary content.
	binary BinaryDetection
}

/// A builder for constructing line buffers.
struct LineBufferBuilder implements IClone {
mut:
	config LineBufferConfig
}

/// Create a new builder for a buffer.
fn LineBufferBuilder.new() LineBufferBuilder {
	return LineBufferBuilder{
		config: LineBufferConfig{
			capacity:     usize(default_buffer_capacity)
			lineterm:     `\n`
			buffer_alloc: BufferAllocation{
				kind: .eager
			}
		}
	}
}

/// Create a new line buffer from this builder's configuration.
fn (builder LineBufferBuilder) build() LineBuffer {
	return LineBuffer{
		config: builder.config
		buf:    []u8{len: int(builder.config.capacity)}
	}
}

/// Set the default capacity to use for a buffer.
///
/// In general, the capacity of a buffer corresponds to the amount of data
/// to hold in memory, and the size of the reads to make to the underlying
/// reader.
///
/// This is set to a reasonable default and probably shouldn't be changed
/// unless there's a specific reason to do so.
fn (mut builder LineBufferBuilder) capacity(capacity usize) &LineBufferBuilder {
	builder.config.capacity = capacity
	return builder
}

/// Set the line terminator for the buffer.
///
/// Every buffer has a line terminator, and this line terminator is used
/// to determine how to roll the buffer forward. For example, when a read
/// to the buffer's underlying reader occurs, the end of the data that is
/// read is likely to correspond to an incomplete line. As a line buffer,
/// callers should not access this data since it is incomplete. The line
/// terminator is how the line buffer determines the part of the read that
/// is incomplete.
///
/// By default, this is set to `b'\n'`.
fn (mut builder LineBufferBuilder) line_terminator(lineterm u8) &LineBufferBuilder {
	builder.config.lineterm = lineterm
	return builder
}

/// Set the maximum amount of additional memory to allocate for long lines.
///
/// In order to enable line oriented search, a fundamental requirement is
/// that, at a minimum, each line must be able to fit into memory. This
/// setting controls how big that line is allowed to be. By default, this
/// is set to `BufferAllocation::Eager`, which means a line buffer will
/// attempt to allocate as much memory as possible to fit a line, and will
/// only be limited by available memory.
///
/// Note that this setting only applies to the amount of *additional*
/// memory to allocate, beyond the capacity of the buffer. That means that
/// a value of `0` is sensible, and in particular, will guarantee that a
/// line buffer will never allocate additional memory beyond its initial
/// capacity.
fn (mut builder LineBufferBuilder) buffer_alloc(behavior BufferAllocation) &LineBufferBuilder {
	builder.config.buffer_alloc = behavior
	return builder
}

/// Whether to enable binary detection or not. Depending on the setting,
/// this can either cause the line buffer to report EOF early or it can
/// cause the line buffer to clean the data.
///
/// By default, this is disabled. In general, binary detection should be
/// viewed as an imperfect heuristic.
fn (mut builder LineBufferBuilder) binary_detection(detection BinaryDetection) &LineBufferBuilder {
	builder.config.binary = detection
	return builder
}

/// A line buffer reader efficiently reads a line oriented buffer from an
/// arbitrary reader.
// V-specific: dynamic `io.Reader` values with mutable receivers are borrowed
// here because storing one by value can leave the interface pointing at a
// dead stack temporary.
struct LineBufferReader[^r, ^b] {
mut:
	rdr         &^r io.Reader
	line_buffer &^b LineBuffer
}

/// Create a new buffered reader that reads from `rdr` and uses the given
/// `line_buffer` as an intermediate buffer.
///
/// This does not change the binary detection behavior of the given line
/// buffer.
fn LineBufferReader.new[^r, ^b](rdr &^r io.Reader, line_buffer &^b LineBuffer) LineBufferReader[^r, ^b] {
	line_buffer.pos = 0
	line_buffer.last_lineterm = 0
	line_buffer.end = 0
	line_buffer.absolute_byte_offset_ = 0
	line_buffer.binary_byte_offset_ = none
	return LineBufferReader[^r, ^b]{
		rdr:         rdr
		line_buffer: line_buffer
	}
}

/// The absolute byte offset which corresponds to the starting offsets
/// of the data returned by `buffer` relative to the beginning of the
/// underlying reader's contents. As such, this offset does not generally
/// correspond to an offset in memory. It is typically used for reporting
/// purposes. It can also be used for counting the number of bytes that
/// have been searched.
fn (rdr LineBufferReader[^r, ^b]) absolute_byte_offset[^r, ^b]() u64 {
	return rdr.line_buffer.absolute_byte_offset()
}

/// If binary data was detected, then this returns the absolute byte offset
/// at which binary data was initially found.
fn (rdr LineBufferReader[^r, ^b]) binary_byte_offset[^r, ^b]() ?u64 {
	return rdr.line_buffer.binary_byte_offset()
}

/// Fill the contents of this buffer by discarding the part of the buffer
/// that has been consumed. The free space created by discarding the
/// consumed part of the buffer is then filled with new data from the
/// reader.
///
/// If EOF is reached, then `false` is returned. Otherwise, `true` is
/// returned. (Note that if this line buffer's binary detection is set to
/// `Quit`, then the presence of binary data will cause this buffer to
/// behave as if it had seen EOF at the first occurrence of binary data.)
///
/// This forwards any errors returned by the underlying reader, and will
/// also return an error if the buffer must be expanded past its allocation
/// limit, as governed by the buffer allocation strategy.
fn (mut rdr LineBufferReader[^r, ^b]) fill[^r, ^b]() !bool {
	return rdr.line_buffer.fill(mut rdr.rdr)!
}

/// Return the contents of this buffer.
fn (rdr LineBufferReader[^r, ^b]) buffer[^r, ^b]() []u8 {
	return rdr.line_buffer.buffer()
}

/// Consume the number of bytes provided. This must be less than or equal
/// to the number of bytes returned by `buffer`.
fn (mut rdr LineBufferReader[^r, ^b]) consume[^r, ^b](amt usize) {
	rdr.line_buffer.consume(amt)
}

/// Consumes the remainder of the buffer. Subsequent calls to `buffer` are
/// guaranteed to return an empty slice until the buffer is refilled.
///
/// This is a convenience function for `consume(buffer.len())`.
fn (mut rdr LineBufferReader[^r, ^b]) consume_all[^r, ^b]() {
	rdr.line_buffer.consume_all()
}

/// A line buffer manages a (typically fixed) buffer for holding lines.
///
/// Callers should create line buffers sparingly and reuse them when possible.
/// Line buffers cannot be used directly, but instead must be used via the
/// LineBufferReader.
struct LineBuffer implements IClone {
	/// The configuration of this buffer.
	config LineBufferConfig
mut:
	/// The primary buffer with which to hold data.
	buf []u8
	/// The current position of this buffer. This is always a valid sliceable
	/// index into `buf`, and its maximum value is the length of `buf`.
	pos usize
	/// The end position of searchable content in this buffer. This is either
	/// set to just after the final line terminator in the buffer, or to just
	/// after the end of the last byte emitted by the reader when the reader
	/// has been exhausted.
	last_lineterm usize
	/// The end position of the buffer. This is always greater than or equal to
	/// last_lineterm. The bytes between last_lineterm and end, if any, always
	/// correspond to a partial line.
	end usize
	/// The absolute byte offset corresponding to `pos`. This is most typically
	/// not a valid index into addressable memory, but rather, an offset that
	/// is relative to all data that passes through a line buffer (since
	/// construction or since the last time `clear` was called).
	///
	/// When the line buffer reaches EOF, this is set to the position just
	/// after the last byte read from the underlying reader. That is, it
	/// becomes the total count of bytes that have been read.
	absolute_byte_offset_ u64
	/// If binary data was found, this records the absolute byte offset at
	/// which it was first detected.
	binary_byte_offset_ ?u64
}

/// Set the binary detection method used on this line buffer.
///
/// This permits dynamically changing the binary detection strategy on an
/// existing line buffer without needing to create a new one.
fn (mut lb LineBuffer) set_binary_detection(binary BinaryDetection) {
	lb.config.binary = binary
}

/// Reset this buffer, such that it can be used with a new reader.
fn (mut lb LineBuffer) clear() {
	lb.pos = 0
	lb.last_lineterm = 0
	lb.end = 0
	lb.absolute_byte_offset_ = 0
	lb.binary_byte_offset_ = none
}

/// The absolute byte offset which corresponds to the starting offsets
/// of the data returned by `buffer` relative to the beginning of the
/// reader's contents. As such, this offset does not generally correspond
/// to an offset in memory. It is typically used for reporting purposes,
/// particularly in error messages.
///
/// This is reset to `0` when `clear` is called.
fn (lb LineBuffer) absolute_byte_offset() u64 {
	return lb.absolute_byte_offset_
}

/// If binary data was detected, then this returns the absolute byte offset
/// at which binary data was initially found.
fn (lb LineBuffer) binary_byte_offset() ?u64 {
	return lb.binary_byte_offset_
}

/// Return the contents of this buffer.
fn (lb LineBuffer) buffer() []u8 {
	return lb.buf[lb.pos..lb.last_lineterm]
}

/// Consume the number of bytes provided. This must be less than or equal
/// to the number of bytes returned by `buffer`.
fn (mut lb LineBuffer) consume(amt usize) {
	assert amt <= usize(lb.buffer().len)
	lb.pos += amt
	lb.absolute_byte_offset_ += u64(amt)
}

/// Consumes the remainder of the buffer. Subsequent calls to `buffer` are
/// guaranteed to return an empty slice until the buffer is refilled.
///
/// This is a convenience function for `consume(buffer.len())`.
fn (mut lb LineBuffer) consume_all() {
	amt := usize(lb.buffer().len)
	lb.consume(amt)
}

/// Fill the contents of this buffer by discarding the part of the buffer
/// that has been consumed. The free space created by discarding the
/// consumed part of the buffer is then filled with new data from the given
/// reader.
///
/// Callers should provide the same reader to this line buffer in
/// subsequent calls to fill. A different reader can only be used
/// immediately following a call to `clear`.
///
/// If EOF is reached, then `false` is returned. Otherwise, `true` is
/// returned. (Note that if this line buffer's binary detection is set to
/// `Quit`, then the presence of binary data will cause this buffer to
/// behave as if it had seen EOF.)
///
/// This forwards any errors returned by `rdr`, and will also return an
/// error if the buffer must be expanded past its allocation limit, as
/// governed by the buffer allocation strategy.
fn (mut lb LineBuffer) fill(mut rdr &io.Reader) !bool {
	if lb.config.binary.is_quit() && lb.binary_byte_offset_ != none {
		return lb.buffer().len != 0
	}
	lb.roll()
	assert lb.pos == 0
	for {
		lb.ensure_capacity()!
		oldend := lb.end
		mut free := lb.buf[lb.end..]
		nread := rdr.read(mut free) or {
			if is_reader_eof(err) {
				0
			} else {
				return err
			}
		}
		if nread == 0 {
			lb.last_lineterm = lb.end
			return lb.buffer().len != 0
		}
		lb.end += usize(nread)
		mut newbytes := lb.buf[oldend..lb.end]
		if binary_byte := lb.config.binary.quit_byte() {
			if i := find_byte(newbytes, binary_byte) {
				absolute_offset := lb.absolute_byte_offset_ + u64(oldend + i)
				lb.end = oldend + i
				lb.last_lineterm = lb.end
				lb.binary_byte_offset_ = absolute_offset
				return lb.pos < lb.end
			}
		} else if binary_byte := lb.config.binary.convert_byte() {
			if i := find_byte(newbytes, binary_byte) {
				absolute_offset := lb.absolute_byte_offset_ + u64(oldend + i)
				replace_bytes(mut newbytes, binary_byte, lb.config.lineterm)
				if lb.binary_byte_offset_ == none {
					lb.binary_byte_offset_ = absolute_offset
				}
			}
		}
		if i := rfind_byte(newbytes, lb.config.lineterm) {
			lb.last_lineterm = oldend + i + 1
			return true
		}
	}
	return false
}

/// Roll the unconsumed parts of the buffer to the front.
///
/// This operation is idempotent.
///
/// After rolling, `last_lineterm` and `end` point to the same location,
/// and `pos` is always set to `0`.
fn (mut lb LineBuffer) roll() {
	if lb.pos == lb.end {
		lb.pos = 0
		lb.last_lineterm = 0
		lb.end = 0
		return
	}
	roll_len := lb.end - lb.pos
	mut i := usize(0)
	for i < roll_len {
		lb.buf[i] = lb.buf[lb.pos + i]
		i++
	}
	lb.pos = 0
	lb.last_lineterm = roll_len
	lb.end = roll_len
}

/// Ensures that the internal buffer has a non-zero amount of free space
/// in which to read more data. If there is no free space, then more is
/// allocated. If the allocation must exceed the configured limit, then
/// this returns an error.
fn (mut lb LineBuffer) ensure_capacity() ! {
	if lb.end < usize(lb.buf.len) {
		return
	}
	len := usize_max(1, usize(lb.buf.len))
	additional := match lb.config.buffer_alloc.kind {
		.eager {
			len * 2
		}
		.error {
			used := usize(lb.buf.len) - lb.config.capacity
			remaining := if lb.config.buffer_alloc.additional > used {
				lb.config.buffer_alloc.additional - used
			} else {
				usize(0)
			}
			n := usize_min(len * 2, remaining)
			if n == 0 {
				return alloc_error(lb.config.capacity + lb.config.buffer_alloc.additional)
			}
			n
		}
	}
	assert additional > 0
	newlen := usize(lb.buf.len) + additional
	lb.buf << []u8{len: int(additional)}
	assert usize(lb.buf.len) == newlen
	assert lb.end < usize(lb.buf.len)
}

/// Replaces `src` with `replacement` in bytes, and return the offset of the
/// first replacement, if one exists.
fn replace_bytes(mut bytes []u8, src u8, replacement u8) ?usize {
	if src == replacement {
		return none
	}
	mut first_pos := usize(0)
	mut has_first := false
	for i in 0 .. bytes.len {
		if bytes[i] == src {
			if !has_first {
				first_pos = usize(i)
				has_first = true
			}
			bytes[i] = replacement
		}
	}
	if has_first {
		return first_pos
	}
	return none
}

fn find_byte(bytes []u8, byte u8) ?usize {
	if bytes.len == 0 {
		return none
	}
	$if !windows {
		unsafe {
			base := voidptr(bytes.data)
			found := C.memchr(base, int(byte), u64(bytes.len))
			if isnil(found) {
				return none
			}
			return usize(found) - usize(base)
		}
	}
	for i, got in bytes {
		if got == byte {
			return usize(i)
		}
	}
	return none
}

fn rfind_byte(bytes []u8, byte u8) ?usize {
	mut i := bytes.len
	for i > 0 {
		i--
		if bytes[i] == byte {
			return usize(i)
		}
	}
	return none
}

fn usize_min(a usize, b usize) usize {
	return if a < b { a } else { b }
}

fn usize_max(a usize, b usize) usize {
	return if a > b { a } else { b }
}
