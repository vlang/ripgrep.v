module matcher

interface IClone {}

/*
This crate provides an interface for regular expressions, with a focus on line
oriented search. The purpose of this crate is to provide a low level matching
interface that permits any kind of substring or regex implementation to power
the search routines provided by the `grep-searcher` crate.

The primary thing provided by this crate is the `Matcher` interface. The
interface defines an abstract interface for text search. It is robust enough to
support everything from basic substring search all the way to arbitrarily
complex regular expression implementations without sacrificing performance.

A key design decision made in this crate is the use of internal iteration, or
otherwise known as the "push" model of searching. In this paradigm,
implementations of the `Matcher` interface will drive search and execute
callbacks provided by the caller when a match is found. This is in contrast to
the usual style of external iteration (the "pull" model) found throughout the
Rust ecosystem. There are two primary reasons why internal iteration was
chosen:

* Some search implementations may themselves require internal iteration.
  Converting an internal iterator to an external iterator can be non-trivial
  and sometimes even practically impossible.
* Rust's type system isn't quite expressive enough to write a generic interface
  using external iteration without giving something else up (namely, ease of
  use and/or performance).

In other words, internal iteration was chosen because it is the lowest common
denominator and because it is probably the least bad way of expressing the
interface in today's Rust. As a result, this interface isn't specifically
intended for everyday use, although, you might find it to be a happy price to
pay if you want to write code that is generic over multiple different regex
implementations.
*/

/// The type of a match.
///
/// The type of a match is a possibly empty range pointing to a contiguous
/// block of addressable memory.
///
/// Every `Match` is guaranteed to satisfy the invariant that `start <= end`.
///
/// # Indexing
///
/// This type is structurally identical to `std::ops::Range<usize>`, but
/// is a bit more ergonomic for dealing with match indices. In particular,
/// this type implements `Copy` and provides methods for building new `Match`
/// values based on old `Match` values. Finally, the invariant that `start`
/// is always less than or equal to `end` is enforced.
///
/// A `Match` can be used to slice a `&[u8]`, `&mut [u8]` or `&str` using
/// range notation in Rust.
pub struct Match implements IClone {
	start usize
	end   usize
}

/// Create a new match.
///
/// # Panics
///
/// This function panics if `start > end`.
pub fn Match.new(start usize, end usize) Match {
	if start > end {
		panic('${start} is not <= ${end}')
	}
	return Match{
		start: start
		end:   end
	}
}

/// Creates a zero width match at the given offset.
pub fn Match.zero(offset usize) Match {
	return Match{
		start: offset
		end:   offset
	}
}

/// Return the start offset of this match.
pub fn (m Match) start() usize {
	return m.start
}

/// Return the end offset of this match.
pub fn (m Match) end() usize {
	return m.end
}

/// Return a new match with the start offset replaced with the given
/// value.
///
/// # Panics
///
/// This method panics if `start > self.end`.
pub fn (m Match) with_start(start usize) Match {
	if start > m.end {
		panic('${start} is not <= ${m.end}')
	}
	return Match{
		start: start
		end:   m.end
	}
}

/// Return a new match with the end offset replaced with the given
/// value.
///
/// # Panics
///
/// This method panics if `self.start > end`.
pub fn (m Match) with_end(end usize) Match {
	if m.start > end {
		panic('${m.start} is not <= ${end}')
	}
	return Match{
		start: m.start
		end:   end
	}
}

/// Offset this match by the given amount and return a new match.
///
/// This adds the given offset to the start and end of this match, and
/// returns the resulting match.
///
/// # Panics
///
/// This panics if adding the given amount to either the start or end
/// offset would result in an overflow.
pub fn (m Match) offset(amount usize) Match {
	new_start := m.start + amount
	if new_start < m.start {
		panic('Match.offset overflow at start')
	}
	new_end := m.end + amount
	if new_end < m.end {
		panic('Match.offset overflow at end')
	}
	return Match{
		start: new_start
		end:   new_end
	}
}

/// Returns the number of bytes in this match.
pub fn (m Match) len() usize {
	return m.end - m.start
}

/// Returns true if and only if this match is empty.
pub fn (m Match) is_empty() bool {
	return m.len() == 0
}

/// A line terminator.
///
/// A line terminator represents the end of a line. Generally, every line is
/// either "terminated" by the end of a stream or a specific byte (or sequence
/// of bytes).
///
/// Generally, a line terminator is a single byte, specifically, `\n`, on
/// Unix-like systems. On Windows, a line terminator is `\r\n` (referred to
/// as `CRLF` for `Carriage Return; Line Feed`).
///
/// The default line terminator is `\n` on all platforms.
pub struct LineTerminator implements IClone {
	kind LineTerminatorImp = .byte
	byte u8               = `\n`
}

enum LineTerminatorImp {
	/// Any single byte representing a line terminator.
	byte
	/// A line terminator represented by `\r\n`.
	///
	/// When this option is used, consumers may generally treat a lone `\n` as
	/// a line terminator in addition to `\r\n`.
	crlf
}

/// Return a new single-byte line terminator. Any byte is valid.
pub fn LineTerminator.byte(byte u8) LineTerminator {
	return LineTerminator{
		kind: .byte
		byte: byte
	}
}

/// Return a new line terminator represented by `\r\n`.
///
/// When this option is used, consumers may generally treat a lone `\n` as
/// a line terminator in addition to `\r\n`.
pub fn LineTerminator.crlf() LineTerminator {
	return LineTerminator{
		kind: .crlf
		byte: `\n`
	}
}

/// Return the default line terminator.
pub fn LineTerminator.default() LineTerminator {
	return LineTerminator.byte(`\n`)
}

/// Returns true if and only if this line terminator is CRLF.
pub fn (line_term LineTerminator) is_crlf() bool {
	return line_term.kind == .crlf
}

pub fn (line_term LineTerminator) equals(other LineTerminator) bool {
	return line_term.kind == other.kind && line_term.byte == other.byte
}

/// Returns this line terminator as a single byte.
///
/// If the line terminator is CRLF, then this returns `\n`. This is
/// useful for routines that, for example, find line boundaries by treating
/// `\n` as a line terminator even when it isn't preceded by `\r`.
pub fn (line_term LineTerminator) as_byte() u8 {
	return if line_term.kind == .byte {
		line_term.byte
	} else {
		u8(`\n`)
	}
}

/// Returns this line terminator as a sequence of bytes.
///
/// This returns a singleton sequence for all line terminators except for
/// `CRLF`, in which case, it returns `\r\n`.
///
/// The slice returned is guaranteed to have length at least `1`.
///
/// This port returns an owned `[]u8` because V does not expose Rust's borrowed
/// slice shape for this constant data.
pub fn (line_term LineTerminator) as_bytes() []u8 {
	return if line_term.kind == .byte {
		[]u8{len: 1, init: line_term.byte}
	} else {
		[u8(`\r`), `\n`]
	}
}

/// Returns true if and only if the given slice ends with this line
/// terminator.
///
/// If this line terminator is `CRLF`, then this only checks whether the
/// last byte is `\n`.
pub fn (line_term LineTerminator) is_suffix(slice []u8) bool {
	return slice.len > 0 && slice[slice.len - 1] == line_term.as_byte()
}

struct BitSet implements IClone {
mut:
	bits [4]u64
}

/// A set of bytes.
///
/// In this crate, byte sets are used to express bytes that can never appear
/// anywhere in a match for a particular implementation of the `Matcher`
/// interface. Specifically, if such a set can be determined, then it's
/// possible for callers to perform additional operations on the basis that
/// certain bytes may never match.
///
/// For example, if a search is configured to possibly produce results that
/// span multiple lines but a caller provided pattern can never match across
/// multiple lines, then it may make sense to divert to more optimized line
/// oriented routines that don't need to handle the multi-line match case.
pub struct ByteSet implements IClone {
mut:
	bits BitSet
}

/// Create an empty set of bytes.
pub fn ByteSet.empty() ByteSet {
	return ByteSet{
		bits: BitSet{}
	}
}

/// Create a full set of bytes such that every possible byte is in the set
/// returned.
pub fn ByteSet.full() ByteSet {
	return ByteSet{
		bits: BitSet{
			bits: [u64(0xffffffffffffffff), 0xffffffffffffffff, 0xffffffffffffffff,
				0xffffffffffffffff]!
		}
	}
}

/// Add a byte to this set.
///
/// If the given byte already belongs to this set, then this is a no-op.
pub fn (mut set ByteSet) add(byte u8) {
	bucket := usize(byte / 64)
	bit := u32(byte % 64)
	set.bits.bits[bucket] |= u64(1) << bit
}

/// Add an inclusive range of bytes.
pub fn (mut set ByteSet) add_all(start u8, end u8) {
	if start > end {
		return
	}
	mut byte := start
	for {
		set.add(byte)
		if byte == end {
			break
		}
		byte++
	}
}

/// Remove a byte from this set.
///
/// If the given byte is not in this set, then this is a no-op.
pub fn (mut set ByteSet) remove(byte u8) {
	bucket := usize(byte / 64)
	bit := u32(byte % 64)
	set.bits.bits[bucket] &= ~(u64(1) << bit)
}

/// Remove an inclusive range of bytes.
pub fn (mut set ByteSet) remove_all(start u8, end u8) {
	if start > end {
		return
	}
	mut byte := start
	for {
		set.remove(byte)
		if byte == end {
			break
		}
		byte++
	}
}

/// Return true if and only if the given byte is in this set.
@[markused]
pub fn (set ByteSet) contains(byte u8) bool {
	bucket := usize(byte / 64)
	bit := u32(byte % 64)
	return (set.bits.bits[bucket] & (u64(1) << bit)) > 0
}

@[markused]
pub fn byte_set_contains(set &ByteSet, byte u8) bool {
	bucket := usize(byte / 64)
	bit := u32(byte % 64)
	return (set.bits.bits[bucket] & (u64(1) << bit)) > 0
}

/// A interface that describes implementations of capturing groups.
///
/// When a matcher supports capturing group extraction, then it is the
/// matcher's responsibility to provide an implementation of this interface.
///
/// Principally, this interface provides a way to access capturing groups
/// in a uniform way that does not require any specific representation.
/// Namely, different matcher implementations may require different in-memory
/// representations of capturing groups. This interface permits matchers to
/// maintain their specific in-memory representation.
///
/// Note that this interface explicitly does not provide a way to construct a
/// new capture value. Instead, it is the responsibility of a `Matcher` to
/// build one, which might require knowledge of the matcher's internal
/// implementation details.
pub interface Captures {
	/// Return the total number of capturing groups. This includes capturing
	/// groups that have not matched anything.
	len() usize
	/// Return the capturing group match at the given index. If no match of
	/// that capturing group exists, then this returns `none`.
	///
	/// When a matcher reports a match with capturing groups, then the first
	/// capturing group (at index `0`) must always correspond to the offsets
	/// for the overall match.
	get(i usize) ?Match
}

/// Return the overall match for the capture.
///
/// This returns the match for index `0`. That is it is equivalent to
/// `get(0).unwrap()`
pub fn (caps Captures) as_match() Match {
	return caps.get(0) or { panic('captures missing overall match at index 0') }
}

/// Returns true if and only if these captures are empty. This occurs
/// when `len` is `0`.
///
/// Note that capturing groups that have non-zero length but otherwise
/// contain no matching groups are not empty.
pub fn (caps Captures) is_empty() bool {
	return caps.len() == 0
}

/// Expands all instances of `$name` in `replacement` to the corresponding
/// capture group `name`, and writes them to the `dst` buffer given.
///
/// (Note: If you're looking for a convenient way to perform replacements
/// with interpolation, then you'll want to use the `replace_with_captures`
/// function in this module.)
///
/// `name` may be an integer corresponding to the index of the
/// capture group (counted by order of opening parenthesis where `0` is the
/// entire match) or it can be a name (consisting of letters, digits or
/// underscores) corresponding to a named capture group.
///
/// A `name` is translated to a capture group index via the given
/// `name_to_index` function. If `name` isn't a valid capture group
/// (whether the name doesn't exist or isn't a valid index), then it is
/// replaced with the empty string.
///
/// The longest possible name is used. e.g., `$1a` looks up the capture
/// group named `1a` and not the capture group at index `1`. To exert
/// more precise control over the name, use braces, e.g., `${1}a`. In all
/// cases, capture group names are limited to ASCII letters, numbers and
/// underscores.
///
/// To write a literal `$` use `$$`.
///
/// Note that the capture group match indices are resolved by slicing
/// the given `haystack`. Generally, this means that `haystack` should be
/// the same slice that was searched to get the current capture group
/// matches.
pub fn (caps Captures) interpolate(name_to_index fn (string) ?usize, haystack []u8, replacement []u8, mut dst []u8) {
	interpolate(replacement, fn [caps, haystack] (i usize, mut dst []u8) {
		range := caps.get(i) or {
			return
		}
		for byte in haystack[range.start()..range.end()] {
			dst << byte
		}
	}, name_to_index, mut dst)
}

/// NoCaptures provides an always-empty implementation of the `Captures`
/// interface.
///
/// This type is useful for implementations of `Matcher` that don't support
/// capturing groups.
pub struct NoCaptures implements IClone {}

/// Create an empty set of capturing groups.
pub fn NoCaptures.new() NoCaptures {
	return NoCaptures{}
}

pub fn (caps NoCaptures) len() usize {
	_ = caps
	return 0
}

pub fn (caps NoCaptures) get(i usize) ?Match {
	_ = caps
	_ = i
	return none
}

/// NoError provides an error type for matchers that never produce errors.
///
/// This error type implements the `std::error::Error` and `std::fmt::Display`
/// traits for use in matcher implementations that can never produce errors.
///
/// The `std::fmt::Debug` and `std::fmt::Display` impls for this type panics.
pub struct NoError {}

pub fn (err NoError) msg() string {
	_ = err
	panic('BUG for NoError: an impossible error occurred')
}

pub fn (err NoError) code() int {
	_ = err
	panic('BUG for NoError: an impossible error occurred')
}

enum LineMatchKindTag {
	confirmed
	candidate
}

/// The type of match for a line oriented matcher.
///
/// V enums do not carry payloads, so this port uses an explicit tagged
/// representation for the position associated with each variant.
pub struct LineMatchKind implements IClone {
	kind LineMatchKindTag
	pos  usize
}

/// A position inside a line that is known to contain a match.
///
/// This position can be anywhere in the line. It does not need to point
/// at the location of the match.
pub fn LineMatchKind.confirmed(pos usize) LineMatchKind {
	return LineMatchKind{
		kind: .confirmed
		pos:  pos
	}
}

/// A position inside a line that may contain a match, and must be searched
/// for verification.
///
/// This position can be anywhere in the line. It does not need to point
/// at the location of the match.
pub fn LineMatchKind.candidate(pos usize) LineMatchKind {
	return LineMatchKind{
		kind: .candidate
		pos:  pos
	}
}

pub fn (kind LineMatchKind) is_confirmed() bool {
	return kind.kind == .confirmed
}

pub fn (kind LineMatchKind) is_candidate() bool {
	return kind.kind == .candidate
}

pub fn (kind LineMatchKind) position() usize {
	return kind.pos
}

// V does not support spelling Rust's `Result<Option<T>>` shape directly.
// Fallible matcher methods keep `!` for errors and use these explicit
// optional success wrappers for the few result shapes needed by this module.
pub struct FallibleMatch {
	has_value bool
	value     Match
}

pub fn FallibleMatch.some(value Match) FallibleMatch {
	return FallibleMatch{
		has_value: true
		value:     value
	}
}

pub fn FallibleMatch.absent() FallibleMatch {
	return FallibleMatch{}
}

pub fn (opt FallibleMatch) is_some() bool {
	return opt.has_value
}

pub fn (opt FallibleMatch) is_none() bool {
	return !opt.has_value
}

pub fn (opt FallibleMatch) get() ?Match {
	if !opt.has_value {
		return none
	}
	return opt.value
}

pub struct FallibleLineMatchKind {
	has_value bool
	value     LineMatchKind
}

pub fn FallibleLineMatchKind.some(value LineMatchKind) FallibleLineMatchKind {
	return FallibleLineMatchKind{
		has_value: true
		value:     value
	}
}

pub fn FallibleLineMatchKind.absent() FallibleLineMatchKind {
	return FallibleLineMatchKind{}
}

pub fn (opt FallibleLineMatchKind) get() ?LineMatchKind {
	if !opt.has_value {
		return none
	}
	return opt.value
}

pub struct FallibleUsize {
	has_value bool
	value     usize
}

pub fn FallibleUsize.some(value usize) FallibleUsize {
	return FallibleUsize{
		has_value: true
		value:     value
	}
}

pub fn FallibleUsize.absent() FallibleUsize {
	return FallibleUsize{}
}

pub fn (opt FallibleUsize) get() ?usize {
	if !opt.has_value {
		return none
	}
	return opt.value
}

/// A matcher defines an interface for regular expression implementations.
///
/// While this interface is large, there are only two required methods that
/// implementors must provide in the Rust trait: `find_at` and `new_captures`.
/// If captures aren't supported by your implementation, then `new_captures`
/// can be implemented with `NoCaptures.new()`. If your implementation does
/// support capture groups, then you should also implement the other capture
/// related methods, as dictated by the documentation. Crucially, this includes
/// `captures_at`.
///
/// The rest of the methods on the Rust trait provide default implementations
/// on top of `find_at` and `new_captures`. V interfaces do not support
/// Rust-style default trait methods, so this port exposes those routines as
/// generic module functions below.
pub interface Matcher {
	/// Returns the start and end byte range of the first match in `haystack`
	/// after `at`, where the byte offsets are relative to that start of
	/// `haystack` (and not `at`). If no match exists, then `none` is returned.
	///
	/// The text encoding of `haystack` is not strictly specified. Matchers are
	/// advised to assume UTF-8, or at worst, some ASCII compatible encoding.
	///
	/// The significance of the starting point is that it takes the surrounding
	/// context into consideration. For example, the `\A` anchor can only
	/// match when `at == 0`.
	find_at(haystack &[]u8, at usize) !FallibleMatch
	/// Returns an end location of the first match in `haystack` starting at
	/// the given position. If no match exists, then `none` is returned.
	///
	/// Note that the end location reported by this method may be less than the
	/// same end location reported by `find`. For example, running `find` with
	/// the pattern `a+` on the haystack `aaa` should report a range of `[0,
	/// 3)`, but `shortest_match` may report `1` as the ending location since
	/// that is the place at which a match is guaranteed to occur.
	///
	/// This method should never report false positives or false negatives. The
	/// point of this method is that some implementors may be able to provide
	/// a faster implementation of this than what `find` does.
	///
	/// By default, this method is implemented by calling `find_at`.
	///
	/// The significance of the starting point is that it takes the surrounding
	/// context into consideration. For example, the `\A` anchor can only
	/// match when `at == 0`.
	shortest_match_at(haystack &[]u8, at usize) !FallibleUsize
	/// Creates an empty group of captures suitable for use with the capturing
	/// APIs of this interface.
	///
	/// Implementations that don't support capturing groups should use
	/// the `NoCaptures` type and implement this method by calling
	/// `NoCaptures.new()`.
	new_captures() !NoCaptures
	/// Returns the total number of capturing groups in this matcher.
	///
	/// If a matcher supports capturing groups, then this value must always be
	/// at least 1, where the first capturing group always corresponds to the
	/// overall match.
	///
	/// If a matcher does not support capturing groups, then this should
	/// always return 0.
	///
	/// By default, capturing groups are not supported, so this always
	/// returns 0.
	capture_count() usize
	/// Maps the given capture group name to its corresponding capture group
	/// index, if one exists. If one does not exist, then `none` is returned.
	///
	/// If the given capture group name maps to multiple indices, then it is
	/// not specified which one is returned. However, it is guaranteed that
	/// one of them is returned.
	///
	/// By default, capturing groups are not supported, so this always returns
	/// `none`.
	capture_index(name string) ?usize
	/// Populates the first set of capture group matches from `haystack`
	/// into `caps` after `at`, where the byte offsets in each capturing
	/// group are relative to the start of `haystack` (and not `at`). If no
	/// match exists, then `false` is returned and the contents of the given
	/// capturing groups are unspecified.
	///
	/// The text encoding of `haystack` is not strictly specified. Matchers are
	/// advised to assume UTF-8, or at worst, some ASCII compatible encoding.
	///
	/// The significance of the starting point is that it takes the surrounding
	/// context into consideration. For example, the `\A` anchor can only
	/// match when `at == 0`.
	///
	/// By default, capturing groups aren't supported, and this implementation
	/// will always behave as if a match were impossible.
	///
	/// Implementors that provide support for capturing groups must guarantee
	/// that when a match occurs, the first capture match (at index `0`) is
	/// always set to the overall match offsets.
	///
	/// Note that if implementors seek to support capturing groups, then they
	/// should implement this method. Other methods that match based on
	/// captures will then work automatically.
	captures_at(haystack &[]u8, at usize, mut caps NoCaptures) !bool
	/// If available, return a set of bytes that will never appear in a match
	/// produced by an implementation.
	///
	/// Specifically, if such a set can be determined, then it's possible for
	/// callers to perform additional operations on the basis that certain
	/// bytes may never match.
	///
	/// For example, if a search is configured to possibly produce results
	/// that span multiple lines but a caller provided pattern can never
	/// match across multiple lines, then it may make sense to divert to
	/// more optimized line oriented routines that don't need to handle the
	/// multi-line match case.
	///
	/// Implementations that produce this set must never report false
	/// positives, but may produce false negatives. That is, is a byte is in
	/// this set then it must be guaranteed that it is never in a match. But,
	/// if a byte is not in this set, then callers cannot assume that a match
	/// exists with that byte.
	///
	/// By default, this returns `none`.
	non_matching_bytes[^a]() ?&^a ByteSet
	/// If this matcher was compiled as a line oriented matcher, then this
	/// method returns the line terminator if and only if the line terminator
	/// never appears in any match produced by this matcher. If this wasn't
	/// compiled as a line oriented matcher, or if the aforementioned guarantee
	/// cannot be made, then this must return `none`, which is the default.
	/// It is **never wrong** to return `none`, but returning a line terminator
	/// when it can appear in a match results in unspecified behavior.
	///
	/// The line terminator is typically `b'\n'`, but can be any single byte or
	/// `CRLF`.
	///
	/// By default, this returns `none`.
	line_terminator() ?LineTerminator
	/// Return one of the following: a confirmed line match, a candidate line
	/// match (which may be a false positive) or no match at all (which **must
	/// not** be a false negative). When reporting a confirmed or candidate
	/// match, the position returned can be any position in the line.
	///
	/// By default, this never returns a candidate match, and always either
	/// returns a confirmed match or no match at all.
	///
	/// When a matcher can match spans over multiple lines, then the behavior
	/// of this method is unspecified. Namely, use of this method only
	/// makes sense in a context where the caller is looking for the next
	/// matching line. That is, callers should only use this method when
	/// `line_terminator` does not return `none`.
	///
	/// # Design rationale
	///
	/// A line matcher is, fundamentally, a normal matcher with the addition
	/// of one optional method: finding a line. By default, this routine
	/// is implemented via the matcher's `shortest_match` method, which
	/// always yields either no match or a `LineMatchKind.confirmed`. However,
	/// implementors may provide a routine for this that can return candidate
	/// lines that need subsequent verification to be confirmed as a match.
	/// This can be useful in cases where it may be quicker to find candidate
	/// lines via some other means instead of relying on the more general
	/// implementations for `find` and `shortest_match`.
	///
	/// For example, consider the regex `\w+foo\s+`. Both `find` and
	/// `shortest_match` must consider the entire regex, including the `\w+`
	/// and `\s+`, while searching. However, this method could look for lines
	/// containing `foo` and return them as candidates. Finding `foo` might
	/// be implemented as a highly optimized substring search routine (like
	/// `memmem`), which is likely to be faster than whatever more generalized
	/// routine is required for resolving `\w+foo\s+`. The caller is then
	/// responsible for confirming whether a match exists or not.
	///
	/// Note that while this method may report false positives, it must never
	/// report false negatives. That is, it can never skip over lines that
	/// contain a match.
	find_candidate_line(haystack &[]u8) !FallibleLineMatchKind
}

/// V-specific helper interface for Rust trait default methods that only need
/// `Matcher::find_at`.
pub interface MatchFinder {
	find_at(haystack &[]u8, at usize) !FallibleMatch
}

/// V-specific helper interface for Rust trait default methods that only need
/// `Matcher::captures_at`.
pub interface CaptureFinder[T] {
	captures_at(haystack &[]u8, at usize, mut caps T) !bool
}

/// By default, capturing groups are not supported, so this always
/// returns 0.
pub fn default_capture_count() usize {
	return 0
}

/// By default, capturing groups are not supported, so this always returns
/// `none`.
pub fn default_capture_index(name string) ?usize {
	_ = name
	return none
}

/// By default, capturing groups aren't supported, and this implementation
/// will always behave as if a match were impossible.
pub fn default_captures_at[T](haystack &[]u8, at usize, mut caps T) !bool {
	_ = haystack
	_ = at
	_ = caps
	return false
}

/// By default, this returns `none`.
pub fn default_non_matching_bytes() ?&ByteSet {
	return none
}

/// By default, this returns `none`.
pub fn default_line_terminator() ?LineTerminator {
	return none
}

/// By default, this never returns a candidate match, and always either
/// returns a confirmed match or no match at all.
pub fn default_find_candidate_line(matcher_ &MatchFinder, haystack &[]u8) !FallibleLineMatchKind {
	maybe_mat := matcher_.find_at(haystack, 0)!
	if !maybe_mat.has_value {
		return FallibleLineMatchKind.absent()
	}
	return FallibleLineMatchKind.some(LineMatchKind.confirmed(maybe_mat.value.end()))
}

/// Returns the start and end byte range of the first match in `haystack`.
/// If no match exists, then `none` is returned.
pub fn find(matcher_ &MatchFinder, haystack &[]u8) !FallibleMatch {
	return matcher_.find_at(haystack, 0)!
}

/// Executes the given function over successive non-overlapping matches
/// in `haystack`. If no match exists, then the given function is never
/// called. If the function returns `false`, then iteration stops.
pub fn find_iter(matcher_ &MatchFinder, haystack &[]u8, matched fn (Match) bool) ! {
	find_iter_at(matcher_, haystack, 0, matched)!
}

/// Executes the given function over successive non-overlapping matches
/// in `haystack`. If no match exists, then the given function is never
/// called. If the function returns `false`, then iteration stops.
///
/// The significance of the starting point is that it takes the surrounding
/// context into consideration. For example, the `\A` anchor can only
/// match when `at == 0`.
pub fn find_iter_at(matcher_ &MatchFinder, haystack &[]u8, at usize, matched fn (Match) bool) ! {
	try_find_iter_at(matcher_, haystack, at, fn [matched] (mat Match) !bool {
		return matched(mat)
	})!
}

/// Executes the given function over successive non-overlapping matches
/// in `haystack`. If no match exists, then the given function is never
/// called. If the function returns `false`, then iteration stops.
/// Similarly, if the function returns an error then iteration stops and
/// the error is yielded.
///
/// In this port, callback errors and matcher errors share V's `!` channel.
pub fn try_find_iter(matcher_ &MatchFinder, haystack &[]u8, matched fn (Match) !bool) ! {
	try_find_iter_at(matcher_, haystack, 0, matched)!
}

/// Executes the given function over successive non-overlapping matches
/// in `haystack`. If no match exists, then the given function is never
/// called. If the function returns `false`, then iteration stops.
/// Similarly, if the function returns an error then iteration stops and
/// the error is yielded.
///
/// The significance of the starting point is that it takes the surrounding
/// context into consideration. For example, the `\A` anchor can only
/// match when `at == 0`.
///
/// In this port, callback errors and matcher errors share V's `!` channel.
pub fn try_find_iter_at(matcher_ &MatchFinder, haystack &[]u8, at usize, matched fn (Match) !bool) ! {
	mut last_end := at
	mut has_last_match := false
	mut last_match_end := usize(0)
	for {
		if last_end > haystack.len {
			return
		}
		maybe_mat := matcher_.find_at(haystack, last_end)!
		if !maybe_mat.has_value {
			return
		}
		mat := maybe_mat.value
		if mat.start() == mat.end() {
			// This is an empty match. To ensure we make progress, start
			// the next search at the smallest possible starting position
			// of the next match following this one.
			last_end = mat.end() + 1
			// Don't accept empty matches immediately following a match.
			// Just move on to the next match.
			if has_last_match && mat.end() == last_match_end {
				continue
			}
		} else {
			last_end = mat.end()
		}
		has_last_match = true
		last_match_end = mat.end()
		if !matched(mat)! {
			return
		}
	}
}

/// Populates the first set of capture group matches from `haystack` into
/// `caps`. If no match exists, then `false` is returned.
pub fn captures[T](matcher_ &CaptureFinder[T], haystack &[]u8, mut caps T) !bool {
	return matcher_.captures_at(haystack, 0, mut caps)
}

/// Executes the given function over successive non-overlapping matches
/// in `haystack` with capture groups extracted from each match. If no
/// match exists, then the given function is never called. If the function
/// returns `false`, then iteration stops.
pub fn captures_iter[T](matcher_ &CaptureFinder[T], haystack &[]u8, mut caps T, matched fn (&T) bool) ! {
	captures_iter_at(matcher_, haystack, 0, mut caps, matched)!
}

/// Executes the given function over successive non-overlapping matches
/// in `haystack` with capture groups extracted from each match. If no
/// match exists, then the given function is never called. If the function
/// returns `false`, then iteration stops.
///
/// The significance of the starting point is that it takes the surrounding
/// context into consideration. For example, the `\A` anchor can only
/// match when `at == 0`.
pub fn captures_iter_at[T](matcher_ &CaptureFinder[T], haystack &[]u8, at usize, mut caps T, matched fn (&T) bool) ! {
	try_captures_iter_at(matcher_, haystack, at, mut caps, fn [matched] (caps &T) !bool {
		return matched(caps)
	})!
}

/// Executes the given function over successive non-overlapping matches
/// in `haystack` with capture groups extracted from each match. If no
/// match exists, then the given function is never called. If the function
/// returns `false`, then iteration stops. Similarly, if the function
/// returns an error then iteration stops and the error is yielded.
///
/// In this port, callback errors and matcher errors share V's `!` channel.
pub fn try_captures_iter[T](matcher_ &CaptureFinder[T], haystack &[]u8, mut caps T, matched fn (&T) !bool) ! {
	try_captures_iter_at(matcher_, haystack, 0, mut caps, matched)!
}

/// Executes the given function over successive non-overlapping matches
/// in `haystack` with capture groups extracted from each match. If no
/// match exists, then the given function is never called. If the function
/// returns `false`, then iteration stops. Similarly, if the function
/// returns an error then iteration stops and the error is yielded.
///
/// The significance of the starting point is that it takes the surrounding
/// context into consideration. For example, the `\A` anchor can only
/// match when `at == 0`.
///
/// In this port, callback errors and matcher errors share V's `!` channel.
pub fn try_captures_iter_at[T](matcher_ &CaptureFinder[T], haystack &[]u8, at usize, mut caps T, matched fn (&T) !bool) ! {
	mut last_end := at
	mut has_last_match := false
	mut last_match_end := usize(0)
	for {
		if last_end > haystack.len {
			return
		}
		if !matcher_.captures_at(haystack, last_end, mut caps)! {
			return
		}
		mat := capture_match_or_panic(caps, 0)
		if mat.start() == mat.end() {
			// This is an empty match. To ensure we make progress, start
			// the next search at the smallest possible starting position
			// of the next match following this one.
			last_end = mat.end() + 1
			// Don't accept empty matches immediately following a match.
			// Just move on to the next match.
			if has_last_match && mat.end() == last_match_end {
				continue
			}
		} else {
			last_end = mat.end()
		}
		has_last_match = true
		last_match_end = mat.end()
		if !matched(&caps)! {
			return
		}
	}
}

/// Replaces every match in the given haystack with the result of calling
/// `append`. `append` is given the start and end of a match, along with
/// a handle to the `dst` buffer provided.
///
/// If the given `append` function returns `false`, then replacement stops.
pub fn replace(matcher_ &MatchFinder, haystack &[]u8, mut dst []u8, append fn (Match, mut []u8) bool) ! {
	mut last_match := usize(0)
	// V mutable closure captures own a copy, so use an explicit reference for
	// Rust's `&mut last_match` capture.
	last_match_ptr := &last_match
	find_iter(matcher_, haystack, fn [haystack, mut dst, append, last_match_ptr] (mat Match) bool {
		unsafe {
			append_slice(mut dst, haystack[*last_match_ptr..mat.start()])
			*last_match_ptr = mat.end()
		}
		return append(mat, mut dst)
	})!
	unsafe {
		append_slice(mut dst, haystack[*last_match_ptr..])
	}
}

/// Replaces every match in the given haystack with the result of calling
/// `append` with the matching capture groups.
///
/// If the given `append` function returns `false`, then replacement stops.
pub fn replace_with_captures[T](matcher_ &CaptureFinder[T], haystack &[]u8, mut caps T, mut dst []u8, append fn (&T, mut []u8) bool) ! {
	replace_with_captures_at(matcher_, haystack, 0, mut caps, mut dst, append)!
}

/// Replaces every match in the given haystack with the result of calling
/// `append` with the matching capture groups.
///
/// If the given `append` function returns `false`, then replacement stops.
///
/// The significance of the starting point is that it takes the surrounding
/// context into consideration. For example, the `\A` anchor can only
/// match when `at == 0`.
pub fn replace_with_captures_at[T](matcher_ &CaptureFinder[T], haystack &[]u8, at usize, mut caps T, mut dst []u8, append fn (&T, mut []u8) bool) ! {
	mut last_match := at
	// V mutable closure captures own a copy, so use an explicit reference for
	// Rust's `&mut last_match` capture.
	last_match_ptr := &last_match
	captures_iter_at(matcher_, haystack, at, mut caps, fn [haystack, mut dst, append, last_match_ptr] (caps &T) bool {
		mat := capture_match_or_panic(caps, 0)
		unsafe {
			append_slice(mut dst, haystack[*last_match_ptr..mat.start()])
			*last_match_ptr = mat.end()
		}
		return append(caps, mut dst)
	})!
	unsafe {
		append_slice(mut dst, haystack[*last_match_ptr..])
	}
}

fn missing_overall_capture_match() Match {
	panic('captures missing overall match at index 0')
}

fn capture_match_or_panic(caps Captures, i usize) Match {
	return caps.get(i) or { missing_overall_capture_match() }
}

fn append_slice(mut dst []u8, bytes []u8) {
	for byte in bytes {
		dst << byte
	}
}

/// Returns true if and only if the matcher matches the given haystack.
///
/// By default, this method is implemented by calling `shortest_match`.
pub fn is_match(matcher_ &MatchFinder, haystack &[]u8) !bool {
	return is_match_at(matcher_, haystack, 0)
}

/// Returns true if and only if the matcher matches the given haystack
/// starting at the given position.
///
/// By default, this method is implemented by calling `shortest_match_at`.
///
/// The significance of the starting point is that it takes the surrounding
/// context into consideration. For example, the `\A` anchor can only
/// match when `at == 0`.
pub fn is_match_at(matcher_ &MatchFinder, haystack &[]u8, at usize) !bool {
	return shortest_match_at(matcher_, haystack, at)!.has_value
}

/// Returns an end location of the first match in `haystack`. If no match
/// exists, then `none` is returned.
///
/// Note that the end location reported by this method may be less than the
/// same end location reported by `find`. For example, running `find` with
/// the pattern `a+` on the haystack `aaa` should report a range of `[0,
/// 3)`, but `shortest_match` may report `1` as the ending location since
/// that is the place at which a match is guaranteed to occur.
///
/// This method should never report false positives or false negatives. The
/// point of this method is that some implementors may be able to provide
/// a faster implementation of this than what `find` does.
///
/// By default, this method is implemented by calling `find`.
pub fn shortest_match(matcher_ &MatchFinder, haystack &[]u8) !FallibleUsize {
	// V-specific: inline `shortest_match_at(..., 0)` to avoid V2 missing a
	// nested generic specialization for the default helper path.
	maybe_mat := matcher_.find_at(haystack, 0)!
	if !maybe_mat.has_value {
		return FallibleUsize.absent()
	}
	return FallibleUsize.some(maybe_mat.value.end())
}

/// Returns an end location of the first match in `haystack` starting at
/// the given position. If no match exists, then `none` is returned.
///
/// Note that the end location reported by this method may be less than the
/// same end location reported by `find`. For example, running `find` with
/// the pattern `a+` on the haystack `aaa` should report a range of `[0,
/// 3)`, but `shortest_match` may report `1` as the ending location since
/// that is the place at which a match is guaranteed to occur.
///
/// This method should never report false positives or false negatives. The
/// point of this method is that some implementors may be able to provide
/// a faster implementation of this than what `find` does.
///
/// By default, this method is implemented by calling `find_at`.
///
/// The significance of the starting point is that it takes the surrounding
/// context into consideration. For example, the `\A` anchor can only
/// match when `at == 0`.
pub fn shortest_match_at(matcher_ &MatchFinder, haystack &[]u8, at usize) !FallibleUsize {
	maybe_mat := matcher_.find_at(haystack, at)!
	if !maybe_mat.has_value {
		return FallibleUsize.absent()
	}
	return FallibleUsize.some(maybe_mat.value.end())
}
