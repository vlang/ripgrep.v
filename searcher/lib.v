module searcher

import encoding.iconv
import encoding.utf8.validate
import io
import log
import matcher
import os

#include "encoding_multibyte_tables.h"
fn C.rg_index_big5_lookup(pointer int) u32
fn C.rg_index_euc_kr_lookup(pointer int) u32
fn C.rg_index_gb18030_lookup(pointer int) u32
fn C.rg_index_jis0208_lookup(pointer int) u32
fn C.rg_index_jis0212_lookup(pointer int) u32
fn C.rg_gb18030_range_lookup(pointer u32) u32

$if !windows {
	#flag @VMODROOT/searcher/iconv_shim.c
	#include <sys/mman.h>
	#include <unistd.h>
	#include <iconv.h>
	#include <errno.h>
	#include "iconv_shim.h"
	#flag darwin -liconv
	#flag freebsd -L/usr/local/lib -liconv
	#flag openbsd -L/usr/local/lib -liconv
	#flag termux -L/data/data/com.termux/files/usr/lib -liconv
	fn C.mmap(addr voidptr, len u64, prot i32, flags i32, fd i32, offset i64) voidptr
	fn C.munmap(addr voidptr, len u64) i32
	fn C.pread(fd i32, buf voidptr, count u64, offset i64) isize
	fn C.iconv_open(tocode charptr, fromcode charptr) voidptr
	fn C.iconv_close(cd voidptr) i32
	fn C.iconv(cd voidptr, inbuf &charptr, inbytesleft &usize, outbuf &charptr, outbytesleft &usize) usize
	fn C.rg_iconv_error_illegal_sequence() int
	fn C.rg_iconv_error_incomplete_sequence() int
	fn C.rg_iconv_error_output_full() int
}

interface IClone {}

fn is_reader_eof(err IError) bool {
	return err is io.Eof || err is os.Eof
}

/*
This module provides an implementation of line oriented search, with optional
support for multi-line search.

# Brief overview

The principle type in this module is a `Searcher`, which can be configured
and built by a `SearcherBuilder`. A `Searcher` is responsible for reading
bytes from a source (e.g., a file), executing a search of those bytes using
a `Matcher` (e.g., a regex) and then reporting the results of that search to
a `Sink` (e.g., stdout). The `Searcher` itself is principally responsible
for managing the consumption of bytes from a source and applying a `Matcher`
over those bytes in an efficient way. The `Searcher` is also responsible for
inverting a search, counting lines, reporting contextual lines, detecting
binary data and even deciding whether or not to use memory maps.

A `Matcher` is an interface for describing the lowest levels of pattern search
in a generic way. The interface itself is very similar to the interface of a
regular expression.

Finally, a `Sink` describes how callers receive search results producer by a
`Searcher`. This includes routines that are called at the beginning and end of
a search, in addition to routines that are called when matching or contextual
lines are found by the `Searcher`. Implementations of `Sink` can be trivially
simple, or extraordinarily complex, such as the `Standard` printer found in
the `grep-printer` module, which effectively implements grep-like output.
*/

enum BinaryDetectionKind {
	none
	quit
	convert
}

/// The behavior of binary detection while searching.
///
/// Binary detection is the process of _heuristically_ identifying whether a
/// given chunk of data is binary or not, and then taking an action based on
/// the result of that heuristic. The motivation behind detecting binary data
/// is that binary data often indicates data that is undesirable to search
/// using textual patterns. Of course, there are many cases in which this isn't
/// true, which is why binary detection is disabled by default.
///
/// Unfortunately, binary detection works differently depending on the type of
/// search being executed:
///
/// 1. When performing a search using a fixed size buffer, binary detection is
///    applied to the buffer's contents as it is filled. Binary detection must
///    be applied to the buffer directly because binary files may not contain
///    line terminators, which could result in exorbitant memory usage.
/// 2. When performing a search using memory maps or by reading data off the
///    heap, then binary detection is only guaranteed to be applied to the
///    parts corresponding to a match. When `Quit` is enabled, then the first
///    few KB of the data are searched for binary data.
pub struct BinaryDetection implements IClone {
	kind BinaryDetectionKind
	byte u8
}

/// No binary detection is performed. Data reported by the searcher may
/// contain arbitrary bytes.
///
/// This is the default.
///
/// V-specific: Rust calls this constructor `none`, but `none` is the V
/// optional sentinel.
pub fn BinaryDetection.disabled() BinaryDetection {
	return BinaryDetection{
		kind: .none
	}
}

/// Binary detection is performed by looking for the given byte.
///
/// When searching is performed using a fixed size buffer, then the
/// contents of that buffer are always searched for the presence of this
/// byte. If it is found, then the underlying data is considered binary
/// and the search stops as if it reached EOF.
///
/// When searching is performed with the entire contents mapped into
/// memory, then binary detection is more conservative. Namely, only a
/// fixed sized region at the beginning of the contents are detected for
/// binary data. As a compromise, any subsequent matching (or context)
/// lines are also searched for binary data. If binary data is detected at
/// any point, then the search stops as if it reached EOF.
pub fn BinaryDetection.quit(byte u8) BinaryDetection {
	return BinaryDetection{
		kind: .quit
		byte: byte
	}
}

/// Binary detection is performed by looking for the given byte, and
/// replacing it with the line terminator configured on the searcher.
/// (If the searcher is configured to use `CRLF` as the line terminator,
/// then this byte is replaced by just `LF`.)
///
/// When searching is performed using a fixed size buffer, then the
/// contents of that buffer are always searched for the presence of this
/// byte and replaced with the line terminator. In effect, the caller is
/// guaranteed to never observe this byte while searching.
///
/// When searching is performed with the entire contents mapped into
/// memory, then this setting has no effect and is ignored.
pub fn BinaryDetection.convert(byte u8) BinaryDetection {
	return BinaryDetection{
		kind: .convert
		byte: byte
	}
}

/// If this binary detection uses the "quit" strategy, then this returns
/// the byte that will cause a search to quit. In any other case, this
/// returns `None`.
pub fn (d BinaryDetection) quit_byte() ?u8 {
	if d.kind == .quit {
		return d.byte
	}
	return none
}

/// If this binary detection uses the "convert" strategy, then this returns
/// the byte that will be replaced by the line terminator. In any other
/// case, this returns `None`.
pub fn (d BinaryDetection) convert_byte() ?u8 {
	if d.kind == .convert {
		return d.byte
	}
	return none
}

enum MmapChoiceKind {
	auto
	never
}

/// Controls the strategy used for determining when to use memory maps.
///
/// If a searcher is called in circumstances where it is possible to use memory
/// maps, and memory maps are enabled, then it will attempt to do so if it
/// believes it will make the search faster.
///
/// By default, memory maps are disabled.
pub struct MmapChoice implements IClone {
	kind MmapChoiceKind
}

/// Use memory maps when they are believed to be advantageous.
///
/// The heuristics used to determine whether to use a memory map or not
/// may depend on many things, including but not limited to, file size
/// and platform.
///
/// If memory maps are unavailable or cannot be used for a specific input,
/// then normal OS read calls are used instead.
///
/// # Safety
///
/// This constructor is not safe because there is no obvious way to
/// encapsulate the safety of file backed memory maps on all platforms
/// without simultaneously negating some or all of their benefits.
///
/// The specific contract the caller is required to uphold isn't precise,
/// but it basically amounts to something like, "the caller guarantees that
/// the underlying file won't be mutated." This, of course, isn't feasible
/// in many environments. However, command line tools may still decide to
/// take the risk of, say, a `SIGBUS` occurring while attempting to read a
/// memory map.
pub fn MmapChoice.auto() MmapChoice {
	return MmapChoice{
		kind: .auto
	}
}

/// Never use memory maps, no matter what. This is the default.
pub fn MmapChoice.never() MmapChoice {
	return MmapChoice{
		kind: .never
	}
}

/// Whether this strategy may employ memory maps or not.
fn (choice MmapChoice) is_enabled() bool {
	return choice.kind == .auto
}

struct Mmap {
	data &u8 = unsafe { nil }
	len  usize
}

fn (m Mmap) bytes() []u8 {
	if m.len == 0 || isnil(m.data) {
		return []u8{}
	}
	return unsafe { m.data.vbytes(int(m.len)) }
}

fn (m Mmap) unmap() {
	if m.len == 0 || isnil(m.data) {
		return
	}
	$if !windows {
		unsafe {
			C.munmap(m.data, u64(m.len))
		}
	}
}

/// Return a memory map if memory maps are enabled and if creating a
/// memory from the given file succeeded and if memory maps are believed
/// to be advantageous for performance.
///
/// If this does attempt to open a memory map and it fails, then `None`
/// is returned and the corresponding error (along with the file path, if
/// present) is logged at the debug level.
///
/// V-specific: the translated searcher does not have logging wired in yet,
/// so failed memory map attempts currently fall back silently.
fn (choice MmapChoice) open(mut file os.File, path string, has_path bool) ?Mmap {
	if !choice.is_enabled() {
		return none
	}
	$if macos {
		// I guess memory maps on macOS aren't great. Should re-evaluate.
		return none
	} $else $if windows {
		return none
	} $else {
		size := mmap_file_size(mut file, path, has_path) or { return none }
		if size == 0 {
			return none
		}
		data := &u8(C.mmap(C.NULL, u64(size), C.PROT_READ, C.MAP_PRIVATE, file.fd,
			i64(0)))
		if data == &u8(C.MAP_FAILED) || isnil(data) {
			return none
		}
		return Mmap{
			data: data
			len:  size
		}
	}
}

fn mmap_file_size(mut file os.File, path string, has_path bool) ?usize {
	if has_path {
		return usize(os.file_size(path))
	}
	pos := file.tell() or { return none }
	file.seek(0, .end) or {
		file.seek(pos, .start) or {}
		return none
	}
	end := file.tell() or {
		file.seek(pos, .start) or {}
		return none
	}
	file.seek(pos, .start) or { return none }
	if end <= 0 {
		return usize(0)
	}
	return usize(end)
}

/// An encoding to use when searching.
///
/// An encoding can be used to configure a [`SearcherBuilder`] to transcode
/// source data from an encoding to UTF-8 before searching.
///
/// An `Encoding` will always be cheap to clone.
pub struct Encoding implements IClone {
	label      string
	kind       EncodingKind
	iconv_name string
}

enum EncodingKind {
	utf8
	utf16le
	utf16be
	windows1252
	shiftjis
	eucjp
	xuserdefined
	iconv
}

/// Create a new encoding for the specified label.
///
/// The encoding label provided is mapped to an encoding via the set of
/// available choices specified in the
/// [Encoding Standard](https://encoding.spec.whatwg.org/#concept-encoding-get).
/// If the given label does not correspond to a valid encoding, then this
/// returns an error.
pub fn Encoding.new(label string) !Encoding {
	normalized := normalize_encoding_label(label)
	kind, canonical, iconv_name := encoding_for_label(normalized) or {
		return ConfigError.unknown_encoding(label.bytes())
	}
	return Encoding{
		label:      canonical.to_owned()
		kind:       kind
		iconv_name: iconv_name.to_owned()
	}
}

fn normalize_encoding_label(label string) string {
	bytes := label.bytes()
	mut start := 0
	mut end := bytes.len
	for start < end && is_encoding_label_space(bytes[start]) {
		start++
	}
	for end > start && is_encoding_label_space(bytes[end - 1]) {
		end--
	}
	mut normalized := []u8{cap: end - start}
	for byte in bytes[start..end] {
		normalized << if byte >= `A` && byte <= `Z` { byte + 32 } else { byte }
	}
	return normalized.bytestr()
}

fn is_encoding_label_space(byte u8) bool {
	return byte in [`\t`, `\n`, `\f`, `\r`, ` `]
}

fn encoding_for_label(label string) ?(EncodingKind, string, string) {
	match label {
		'unicode-1-1-utf-8', 'unicode11utf8', 'unicode20utf8', 'utf-8', 'utf8', 'x-unicode20utf8' {
			return EncodingKind.utf8, 'UTF-8', ''
		}
		'csunicode', 'iso-10646-ucs-2', 'ucs-2', 'unicode', 'unicodefeff', 'utf-16', 'utf-16le' {
			return EncodingKind.utf16le, 'UTF-16LE', ''
		}
		'unicodefffe', 'utf-16be' {
			return EncodingKind.utf16be, 'UTF-16BE', ''
		}
		'ansi_x3.4-1968', 'ascii', 'cp1252', 'cp819', 'csisolatin1', 'ibm819', 'iso-8859-1', 'iso-ir-100', 'iso8859-1', 'iso88591', 'iso_8859-1', 'iso_8859-1:1987', 'l1', 'latin1', 'us-ascii', 'windows-1252', 'x-cp1252' {
			return EncodingKind.windows1252, 'windows-1252', ''
		}
		'csshiftjis', 'ms932', 'ms_kanji', 'shift-jis', 'shift_jis', 'sjis', 'windows-31j', 'x-sjis' {
			return EncodingKind.shiftjis, 'Shift_JIS', ''
		}
		'cseucpkdfmtjapanese', 'euc-jp', 'x-euc-jp' {
			return EncodingKind.eucjp, 'EUC-JP', ''
		}
		'x-user-defined' {
			return EncodingKind.xuserdefined, 'x-user-defined', ''
		}
		else {
			return iconv_encoding_for_label(label)
		}
	}
}

fn iconv_encoding_for_label(label string) ?(EncodingKind, string, string) {
	match label {
		'866', 'cp866', 'csibm866', 'ibm866' {
			return EncodingKind.iconv, 'IBM866', 'IBM866'
		}
		'cp1250', 'windows-1250', 'x-cp1250' {
			return EncodingKind.iconv, 'windows-1250', 'WINDOWS-1250'
		}
		'cp1251', 'windows-1251', 'x-cp1251' {
			return EncodingKind.iconv, 'windows-1251', 'WINDOWS-1251'
		}
		'cp1253', 'windows-1253', 'x-cp1253' {
			return EncodingKind.iconv, 'windows-1253', 'WINDOWS-1253'
		}
		'cp1254', 'csisolatin5', 'iso-8859-9', 'iso-ir-148', 'iso8859-9', 'iso88599', 'iso_8859-9', 'iso_8859-9:1989', 'l5', 'latin5', 'windows-1254', 'x-cp1254' {
			return EncodingKind.iconv, 'windows-1254', 'WINDOWS-1254'
		}
		'cp1255', 'windows-1255', 'x-cp1255' {
			return EncodingKind.iconv, 'windows-1255', 'WINDOWS-1255'
		}
		'cp1256', 'windows-1256', 'x-cp1256' {
			return EncodingKind.iconv, 'windows-1256', 'WINDOWS-1256'
		}
		'cp1257', 'windows-1257', 'x-cp1257' {
			return EncodingKind.iconv, 'windows-1257', 'WINDOWS-1257'
		}
		'cp1258', 'windows-1258', 'x-cp1258' {
			return EncodingKind.iconv, 'windows-1258', 'WINDOWS-1258'
		}
		'csisolatin2', 'iso-8859-2', 'iso-ir-101', 'iso8859-2', 'iso88592', 'iso_8859-2', 'iso_8859-2:1987', 'l2', 'latin2' {
			return EncodingKind.iconv, 'ISO-8859-2', 'ISO-8859-2'
		}
		'csisolatin3', 'iso-8859-3', 'iso-ir-109', 'iso8859-3', 'iso88593', 'iso_8859-3', 'iso_8859-3:1988', 'l3', 'latin3' {
			return EncodingKind.iconv, 'ISO-8859-3', 'ISO-8859-3'
		}
		'csisolatin4', 'iso-8859-4', 'iso-ir-110', 'iso8859-4', 'iso88594', 'iso_8859-4', 'iso_8859-4:1988', 'l4', 'latin4' {
			return EncodingKind.iconv, 'ISO-8859-4', 'ISO-8859-4'
		}
		'csisolatincyrillic', 'cyrillic', 'iso-8859-5', 'iso-ir-144', 'iso8859-5', 'iso88595', 'iso_8859-5', 'iso_8859-5:1988' {
			return EncodingKind.iconv, 'ISO-8859-5', 'ISO-8859-5'
		}
		'arabic', 'asmo-708', 'csiso88596e', 'csiso88596i', 'csisolatinarabic', 'ecma-114', 'iso-8859-6', 'iso-8859-6-e', 'iso-8859-6-i', 'iso-ir-127', 'iso8859-6', 'iso88596', 'iso_8859-6', 'iso_8859-6:1987' {
			return EncodingKind.iconv, 'ISO-8859-6', 'ISO-8859-6'
		}
		'csisolatingreek', 'ecma-118', 'elot_928', 'greek', 'greek8', 'iso-8859-7', 'iso-ir-126', 'iso8859-7', 'iso88597', 'iso_8859-7', 'iso_8859-7:1987', 'sun_eu_greek' {
			return EncodingKind.iconv, 'ISO-8859-7', 'ISO-8859-7'
		}
		'csiso88598e', 'csisolatinhebrew', 'hebrew', 'iso-8859-8', 'iso-8859-8-e', 'iso-ir-138', 'iso8859-8', 'iso88598', 'iso_8859-8', 'iso_8859-8:1988', 'visual' {
			return EncodingKind.iconv, 'ISO-8859-8', 'ISO-8859-8'
		}
		'csiso88598i', 'iso-8859-8-i', 'logical' {
			return EncodingKind.iconv, 'ISO-8859-8-I', 'ISO-8859-8'
		}
		'csisolatin6', 'iso-8859-10', 'iso-ir-157', 'iso8859-10', 'iso885910', 'l6', 'latin6' {
			return EncodingKind.iconv, 'ISO-8859-10', 'ISO-8859-10'
		}
		'dos-874', 'iso-8859-11', 'iso8859-11', 'iso885911', 'tis-620', 'windows-874' {
			return EncodingKind.iconv, 'windows-874', 'WINDOWS-874'
		}
		'iso-8859-13', 'iso8859-13', 'iso885913' {
			return EncodingKind.iconv, 'ISO-8859-13', 'ISO-8859-13'
		}
		'iso-8859-14', 'iso8859-14', 'iso885914' {
			return EncodingKind.iconv, 'ISO-8859-14', 'ISO-8859-14'
		}
		'csisolatin9', 'iso-8859-15', 'iso8859-15', 'iso885915', 'iso_8859-15', 'l9' {
			return EncodingKind.iconv, 'ISO-8859-15', 'ISO-8859-15'
		}
		'iso-8859-16' {
			return EncodingKind.iconv, 'ISO-8859-16', 'ISO-8859-16'
		}
		'cskoi8r', 'koi', 'koi8', 'koi8-r', 'koi8_r' {
			return EncodingKind.iconv, 'KOI8-R', 'KOI8-R'
		}
		'koi8-ru', 'koi8-u' {
			return EncodingKind.iconv, 'KOI8-U', 'KOI8-U'
		}
		'csmacintosh', 'mac', 'macintosh', 'x-mac-roman' {
			return EncodingKind.iconv, 'macintosh', 'MACINTOSH'
		}
		'x-mac-cyrillic', 'x-mac-ukrainian' {
			return EncodingKind.iconv, 'x-mac-cyrillic', 'MAC-CYRILLIC'
		}
		'big5', 'big5-hkscs', 'cn-big5', 'csbig5', 'x-x-big5' {
			return EncodingKind.iconv, 'Big5', 'BIG5'
		}
		'chinese', 'csgb2312', 'csiso58gb231280', 'gb2312', 'gb_2312', 'gb_2312-80', 'gbk', 'iso-ir-58', 'x-gbk' {
			return EncodingKind.iconv, 'GBK', 'GBK'
		}
		'gb18030' {
			return EncodingKind.iconv, 'gb18030', 'GB18030'
		}
		'cseuckr', 'csksc56011987', 'euc-kr', 'iso-ir-149', 'korean', 'ks_c_5601-1987', 'ks_c_5601-1989', 'ksc5601', 'ksc_5601', 'windows-949' {
			return EncodingKind.iconv, 'EUC-KR', 'EUC-KR'
		}
		'csiso2022jp', 'iso-2022-jp' {
			return EncodingKind.iconv, 'ISO-2022-JP', 'ISO-2022-JP'
		}
		else {
			return none
		}
	}
}

/// The internal configuration of a searcher. This is shared among several
/// search related types, but is only ever written to by the SearcherBuilder.
pub struct Config implements IClone {
	/// The line terminator to use.
	line_term matcher.LineTerminator
	/// Whether to invert matching.
	invert_match bool
	/// The number of lines after a match to include.
	after_context usize
	/// The number of lines before a match to include.
	before_context usize
	/// Whether to enable unbounded context or not.
	passthru bool
	/// Whether to count line numbers.
	line_number bool
	/// The maximum amount of heap memory to use.
	///
	/// When not given, no explicit limit is enforced. When set to `0`, then
	/// only the memory map search strategy is available.
	heap_limit ?usize
	/// The memory map strategy.
	mmap MmapChoice
	/// The binary data detection strategy.
	binary BinaryDetection
	/// Whether to enable matching across multiple lines.
	multi_line bool
	/// An encoding that, when present, causes the searcher to transcode all
	/// input from the encoding to UTF-8.
	encoding ?Encoding
	/// Whether to do automatic transcoding based on a BOM or not.
	bom_sniffing bool
	/// Whether to stop searching when a non-matching line is found after a
	/// matching line.
	stop_on_nonmatch bool
	/// The maximum number of matches this searcher should emit.
	max_matches ?u64
}

fn Config.default() Config {
	return Config{
		line_term:    matcher.LineTerminator.default()
		line_number:  true
		mmap:         MmapChoice{
			kind: .never
		}
		bom_sniffing: true
		heap_limit:   none
		max_matches:  none
	}
}

enum ConfigErrorKind {
	search_unavailable
	mismatched_line_terminators
	unknown_encoding
}

/// An error that can occur when building a searcher.
///
/// This error occurs when a non-sensical configuration is present when trying
/// to construct a `Searcher` from a `SearcherBuilder`.
pub struct ConfigError implements IClone {
	kind ConfigErrorKind
	/// The matcher's line terminator.
	matcher_line_term matcher.LineTerminator
	/// The searcher's line terminator.
	searcher_line_term matcher.LineTerminator
	/// The provided encoding label that could not be found.
	label []u8
}

/// Indicates that the heap limit configuration prevents all possible
/// search strategies from being used. For example, if the heap limit is
/// set to 0 and memory map searching is disabled or unavailable.
pub fn ConfigError.search_unavailable() ConfigError {
	return ConfigError{
		kind: .search_unavailable
	}
}

/// Occurs when a matcher reports a line terminator that is different than
/// the one configured in the searcher.
pub fn ConfigError.mismatched_line_terminators(matcher_line_term matcher.LineTerminator, searcher_line_term matcher.LineTerminator) ConfigError {
	return ConfigError{
		kind:               .mismatched_line_terminators
		matcher_line_term:  matcher_line_term
		searcher_line_term: searcher_line_term
	}
}

/// Occurs when no encoding could be found for a particular label.
pub fn ConfigError.unknown_encoding(label []u8) ConfigError {
	return ConfigError{
		kind:  .unknown_encoding
		label: label.clone()
	}
}

// V-specific: `msg` formats this configuration error for `IError`.
pub fn (err ConfigError) msg() string {
	return match err.kind {
		.search_unavailable {
			'grep config error: no available searchers'
		}
		.mismatched_line_terminators {
			'grep config error: mismatched line terminators, matcher has ${err.matcher_line_term} but searcher has ${err.searcher_line_term}'
		}
		.unknown_encoding {
			'grep config error: unknown encoding: ${lossy_utf8_string(err.label)}'
		}
	}
}

// V-specific: configuration errors do not use distinct V error codes.
pub fn (err ConfigError) code() int {
	_ = err
	return 0
}

/// Return the maximal amount of lines needed to fulfill this configuration's
/// context.
///
/// If this returns `0`, then no context is ever needed.
fn (config &Config) max_context() usize {
	return if config.before_context > config.after_context {
		config.before_context
	} else {
		config.after_context
	}
}

/// Build a line buffer from this configuration.
fn (config &Config) line_buffer() LineBuffer {
	mut builder := LineBufferBuilder.new()
	builder.line_terminator(config.line_term.as_byte())
	builder.binary_detection(config.binary)
	if limit := config.heap_limit {
		if limit <= usize(default_buffer_capacity) {
			builder.capacity(limit)
			builder.buffer_alloc(BufferAllocation{
				kind: .error
			})
		} else {
			builder.capacity(usize(default_buffer_capacity))
			builder.buffer_alloc(BufferAllocation{
				kind:       .error
				additional: limit - usize(default_buffer_capacity)
			})
		}
	}
	return builder.build()
}

/// A builder for configuring a searcher.
///
/// A search builder permits specifying the configuration of a searcher,
/// including options like whether to invert the search or to enable multi
/// line search.
///
/// Once a searcher has been built, it is beneficial to reuse that searcher
/// for multiple searches, if possible.
pub struct SearcherBuilder implements IClone {
mut:
	config Config
}

/// Create a new searcher builder with a default configuration.
pub fn SearcherBuilder.new() SearcherBuilder {
	return SearcherBuilder{
		config: Config.default()
	}
}

/// Build a searcher with the given matcher.
pub fn (builder &SearcherBuilder) build() Searcher {
	mut config := builder.config.clone()
	if config.passthru {
		config.before_context = 0
		config.after_context = 0
	}
	line_buffer := config.line_buffer()
	return Searcher{
		config:            config
		line_buffer:       line_buffer
		multi_line_buffer: []u8{}
	}
}

/// Set the line terminator that is used by the searcher.
///
/// When using a searcher, if the matcher provided has a line terminator
/// set, then it must be the same as this one. If they aren't, building
/// a searcher will return an error.
///
/// By default, this is set to `b'\n'`.
pub fn (mut builder SearcherBuilder) line_terminator(line_term matcher.LineTerminator) &SearcherBuilder {
	builder.config.line_term = line_term
	return builder
}

/// Whether to invert matching, whereby lines that don't match are reported
/// instead of reporting lines that do match.
///
/// By default, this is disabled.
pub fn (mut builder SearcherBuilder) invert_match(yes bool) &SearcherBuilder {
	builder.config.invert_match = yes
	return builder
}

/// Whether to count and include line numbers with matching lines.
///
/// This is enabled by default. There is a small performance penalty
/// associated with computing line numbers, so this can be disabled when
/// this isn't desirable.
pub fn (mut builder SearcherBuilder) line_number(yes bool) &SearcherBuilder {
	builder.config.line_number = yes
	return builder
}

/// Whether to enable multi line search or not.
///
/// When multi line search is enabled, matches *may* match across multiple
/// lines. Conversely, when multi line search is disabled, it is impossible
/// for any match to span more than one line.
///
/// **Warning:** multi line search requires having the entire contents to
/// search mapped in memory at once. When searching files, memory maps
/// will be used if possible and if they are enabled, which avoids using
/// your program's heap. However, if memory maps cannot be used (e.g.,
/// for searching streams like `stdin` or if transcoding is necessary),
/// then the entire contents of the stream are read on to the heap before
/// starting the search.
///
/// This is disabled by default.
pub fn (mut builder SearcherBuilder) multi_line(yes bool) &SearcherBuilder {
	builder.config.multi_line = yes
	return builder
}

/// Whether to include a fixed number of lines after every match.
///
/// When this is set to a non-zero number, then the searcher will report
/// `line_count` contextual lines after every match.
///
/// This is set to `0` by default.
pub fn (mut builder SearcherBuilder) after_context(line_count usize) &SearcherBuilder {
	builder.config.after_context = line_count
	return builder
}

/// Whether to include a fixed number of lines before every match.
///
/// When this is set to a non-zero number, then the searcher will report
/// `line_count` contextual lines before every match.
///
/// This is set to `0` by default.
pub fn (mut builder SearcherBuilder) before_context(line_count usize) &SearcherBuilder {
	builder.config.before_context = line_count
	return builder
}

/// Whether to enable the "passthru" feature or not.
///
/// When passthru is enabled, it effectively treats all non-matching lines
/// as contextual lines. In other words, enabling this is akin to
/// requesting an unbounded number of before and after contextual lines.
///
/// When passthru mode is enabled, any `before_context` or `after_context`
/// settings are ignored by setting them to `0`.
///
/// This is disabled by default.
pub fn (mut builder SearcherBuilder) passthru(yes bool) &SearcherBuilder {
	builder.config.passthru = yes
	return builder
}

/// Set an approximate limit on the amount of heap space used by a searcher.
///
/// The heap limit is enforced in two scenarios:
///
/// * When searching using a fixed size buffer, the heap limit controls
///   how big this buffer is allowed to be. Assuming contexts are disabled,
///   the minimum size of this buffer is the length (in bytes) of the
///   largest single line in the contents being searched. If any line
///   exceeds the heap limit, then an error will be returned.
/// * When performing a multi line search, a fixed size buffer cannot be
///   used. Thus, the only choices are to read the entire contents on to
///   the heap, or use memory maps. In the former case, the heap limit set
///   here is enforced.
///
/// If a heap limit is set to `0`, then no heap space is used. If there are
/// no alternative strategies available for searching without heap space
/// (e.g., memory maps are disabled), then the searcher wil return an error
/// immediately.
///
/// By default, no limit is set.
pub fn (mut builder SearcherBuilder) heap_limit(bytes ?usize) &SearcherBuilder {
	builder.config.heap_limit = bytes
	return builder
}

/// Set the strategy to employ use of memory maps.
///
/// Currently, there are only two strategies that can be employed:
///
/// * **Automatic** - A searcher will use heuristics, including but not
///   limited to file size and platform, to determine whether to use memory
///   maps or not.
/// * **Never** - Memory maps will never be used. If multi line search is
///   enabled, then the entire contents will be read on to the heap before
///   searching begins.
///
/// The default behavior is **never**. Generally speaking, and perhaps
/// against conventional wisdom, memory maps don't necessarily enable
/// faster searching. For example, depending on the platform, using memory
/// maps while searching a large directory can actually be quite a bit
/// slower than using normal read calls because of the overhead of managing
/// the memory maps.
///
/// Memory maps can be faster in some cases however. On some platforms,
/// when searching a very large file that *is already in memory*, it can
/// be slightly faster to search it as a memory map instead of using
/// normal read calls.
///
/// Finally, memory maps have a somewhat complicated safety story in Rust.
/// If you aren't sure whether enabling memory maps is worth it, then just
/// don't bother with it.
///
/// **WARNING**: If your process is searching a file backed memory map
/// at the same time that file is truncated, then it's possible for the
/// process to terminate with a bus error.
pub fn (mut builder SearcherBuilder) memory_map(strategy MmapChoice) &SearcherBuilder {
	builder.config.mmap = strategy
	return builder
}

/// Set the binary detection strategy.
///
/// The binary detection strategy determines not only how the searcher
/// detects binary data, but how it responds to the presence of binary
/// data. See the [`BinaryDetection`] type for more information.
///
/// By default, binary detection is disabled.
pub fn (mut builder SearcherBuilder) binary_detection(detection BinaryDetection) &SearcherBuilder {
	builder.config.binary = detection
	return builder
}

/// Set the encoding used to read the source data before searching.
///
/// When an encoding is provided, then the source data is _unconditionally_
/// transcoded using the encoding, unless a BOM is present. If a BOM is
/// present, then the encoding indicated by the BOM is used instead. If the
/// transcoding process encounters an error, then bytes are replaced with
/// the Unicode replacement codepoint.
///
/// When no encoding is specified (the default), then BOM sniffing is
/// used (if it's enabled, which it is, by default) to determine whether
/// the source data is UTF-8 or UTF-16, and transcoding will be performed
/// automatically. If no BOM could be found, then the source data is
/// searched _as if_ it were UTF-8. However, so long as the source data is
/// at least ASCII compatible, then it is possible for a search to produce
/// useful results.
pub fn (mut builder SearcherBuilder) encoding(encoding ?Encoding) &SearcherBuilder {
	builder.config.encoding = encoding
	return builder
}

/// Enable automatic transcoding based on BOM sniffing.
///
/// When this is enabled and an explicit encoding is not set, then this
/// searcher will try to detect the encoding of the bytes being searched
/// by sniffing its byte-order mark (BOM). In particular, when this is
/// enabled, UTF-16 encoded files will be searched seamlessly.
///
/// When this is disabled and if an explicit encoding is not set, then
/// the bytes from the source stream will be passed through unchanged,
/// including its BOM, if one is present.
///
/// This is enabled by default.
pub fn (mut builder SearcherBuilder) bom_sniffing(yes bool) &SearcherBuilder {
	builder.config.bom_sniffing = yes
	return builder
}

/// Stop searching a file when a non-matching line is found after a
/// matching line.
///
/// This is useful for searching sorted files where it is expected that all
/// the matches will be on adjacent lines.
pub fn (mut builder SearcherBuilder) stop_on_nonmatch(stop_on_nonmatch bool) &SearcherBuilder {
	builder.config.stop_on_nonmatch = stop_on_nonmatch
	return builder
}

/// Sets the maximum number of matches that should be emitted by this
/// searcher.
///
/// If multi line search is enabled and a match spans multiple lines, then
/// that match is counted exactly once for the purposes of enforcing this
/// limit, regardless of how many lines it spans.
///
/// Note that `0` is a legal value. This will cause the searcher to
/// immediately quick without searching anything.
///
/// By default, no limit is set.
pub fn (mut builder SearcherBuilder) max_matches(limit ?u64) &SearcherBuilder {
	builder.config.max_matches = limit
	return builder
}

/// A searcher executes searches over a haystack and writes results to a caller
/// provided sink.
///
/// Matches are detected via implementations of the `Matcher` trait, which must
/// be provided by the caller when executing a search.
///
/// When possible, a searcher should be reused.
pub struct Searcher implements IClone {
mut:
	/// The configuration for this searcher.
	///
	/// We make most of these settings available to users of `Searcher` via
	/// public API methods, which can be queried in implementations of `Sink`
	/// if necessary.
	config            Config
	// V-specific: Rust stores `decode_builder` and `decode_buffer` fields here.
	// This port performs transcoding through `TranscodingReader` and
	// `decode_slice` helpers instead.
	/// A line buffer for use in line oriented searching.
	line_buffer       LineBuffer
	/// A buffer in which to store the contents of a reader when performing a
	/// multi line search. In particular, multi line searches cannot be
	/// performed incrementally, and need the entire haystack in memory at
	/// once.
	multi_line_buffer []u8
}

/// Create a new searcher with a default configuration.
///
/// To configure the searcher (e.g., invert matching, enable memory maps,
/// enable contexts, etc.), use the [`SearcherBuilder`].
pub fn Searcher.new() Searcher {
	return SearcherBuilder.new().build()
}

// V-specific: release reusable search buffers when a worker is retired.
pub fn (mut s Searcher) free() {
	unsafe {
		s.line_buffer.buf.free()
		s.multi_line_buffer.free()
	}
	s.line_buffer.buf = []u8{}
	s.multi_line_buffer = []u8{}
}

// V-specific: adapt a borrowed byte slice to `io.Reader` for transcoding.
struct SearchSliceReader[^a] {
	bytes &^a []u8
mut:
	pos int
}

fn SearchSliceReader.new[^a](slice &^a []u8) SearchSliceReader[^a] {
	return SearchSliceReader[^a]{
		bytes: slice
	}
}

fn (mut rdr SearchSliceReader[^a]) read[^a](mut buf []u8) !int {
	if rdr.pos >= rdr.bytes.len {
		return io.Eof{}
	}
	nread := copy(mut buf, rdr.bytes[rdr.pos..])
	rdr.pos += nread
	return nread
}

/// Execute a search over the file with the given path and write the
/// results to the given sink.
///
/// If memory maps are enabled and the searcher heuristically believes
/// memory maps will help the search run faster, then this will use
/// memory maps. For this reason, callers should prefer using this method
/// or `search_file` over the more generic `search_reader` when possible.
pub fn (mut s Searcher) search_path[^p](matcher_ &matcher.Matcher, path &^p string, write_to Sink) ! {
	mut file := os.open(*path) or { return err }
	defer {
		file.close()
	}
	s.search_file_maybe_path(matcher_, mut file, *path, true, write_to)!
}

/// Execute a search over a file and write the results to the given sink.
///
/// If memory maps are enabled and the searcher heuristically believes
/// memory maps will help the search run faster, then this will use
/// memory maps. For this reason, callers should prefer using this method
/// or `search_path` over the more generic `search_reader` when possible.
pub fn (mut s Searcher) search_file(matcher_ &matcher.Matcher, mut file os.File, write_to Sink) ! {
	s.search_file_maybe_path(matcher_, mut file, '', false, write_to)!
}

fn (mut s Searcher) search_file_maybe_path(matcher_ &matcher.Matcher, mut file os.File, path string, has_path bool, write_to Sink) ! {
	$if !macos {
		if mmap := s.config.mmap.open(mut file, path, has_path) {
			defer {
				mmap.unmap()
			}
			return s.search_slice(matcher_, mmap.bytes(), write_to)
		}
	}
	s.check_config(matcher_)!
	mut needs_transcoding := false
	if !s.multi_line_with_matcher(matcher_) {
		needs_transcoding = file_needs_transcoding(&s.config, mut file, path, has_path)
	}
	if s.multi_line_with_matcher(matcher_) {
		s.fill_multi_line_buffer_from_file(mut file, path, has_path)!
			mut search := MultiLine.new(s, matcher_ref_value(matcher_), &s.multi_line_buffer,
				sink_ref_value(&write_to))
		search.run()!
	} else if needs_transcoding {
		mut decoded := TranscodingReader.new(&file, &s.config)
		defer {
			decoded.close()
		}
		mut rdr := LineBufferReader.new(&decoded, &s.line_buffer)
			mut search := ReadByLine.new(s, matcher_ref_value(matcher_), rdr,
				sink_ref_value(&write_to))
		search.run()!
	} else {
		mut rdr := LineBufferReader.new(&file, &s.line_buffer)
			mut search := ReadByLine.new(s, matcher_ref_value(matcher_), rdr, sink_ref_value(&write_to))
		search.run()!
	}
}

/// Execute a search over any implementation of `std::io::Read` and write
/// the results to the given sink.
///
/// When possible, this implementation will search the reader incrementally
/// without reading it into memory. In some cases---for example, if multi
/// line search is enabled---an incremental search isn't possible and the
/// given reader is consumed completely and placed on the heap before
/// searching begins. For this reason, when multi line search is enabled,
/// one should try to use higher level APIs (e.g., searching by file or
/// file path) so that memory maps can be used if they are available and
/// enabled.
pub fn (mut s Searcher) search_reader(matcher_ &matcher.Matcher, mut read_from io.Reader, write_to Sink) ! {
	s.check_config(matcher_)!

	if s.multi_line_with_matcher(matcher_) {
		s.fill_multi_line_buffer_from_reader(mut read_from)!
			mut search := MultiLine.new(s, matcher_ref_value(matcher_), &s.multi_line_buffer,
				sink_ref_value(&write_to))
		search.run()!
	} else if s.config.encoding != none || s.config.bom_sniffing {
		mut decoded := TranscodingReader.new(&read_from, &s.config)
		defer {
			decoded.close()
		}
		mut rdr := LineBufferReader.new(&decoded, &s.line_buffer)
			mut search := ReadByLine.new(s, matcher_ref_value(matcher_), rdr, sink_ref_value(&write_to))
		search.run()!
	} else {
		mut rdr := LineBufferReader.new(&read_from, &s.line_buffer)
			mut search := ReadByLine.new(s, matcher_ref_value(matcher_), rdr, sink_ref_value(&write_to))
		search.run()!
	}
}

/// Execute a search over the given slice and write the results to the
/// given sink.
pub fn (mut s Searcher) search_slice(matcher_ &matcher.Matcher, slice []u8, write_to Sink) ! {
	s.check_config(matcher_)!

	// We can search the slice directly, unless we need to do transcoding.
	if s.slice_needs_transcoding(slice) {
		mut read_from := SearchSliceReader.new(&slice)
		return s.search_reader(matcher_, mut read_from, write_to)
	}
	if s.multi_line_with_matcher(matcher_) {
			mut search := MultiLine.new(s, matcher_ref_value(matcher_), &slice, sink_ref_value(&write_to))
		search.run()!
	} else {
			mut search := SliceByLine.new(s, matcher_ref_value(matcher_), &slice,
				sink_ref_value(&write_to))
		search.run()!
	}
}

/// Check that the searcher's configuration and the matcher are consistent
/// with each other.
fn (s &Searcher) check_config(matcher_ &matcher.Matcher) ! {
	if limit := s.config.heap_limit {
		if limit == 0 && !s.config.mmap.is_enabled() {
			return ConfigError.search_unavailable()
		}
	}
	matcher_line_term := matcher_.line_terminator() or {
		return
	}
	if !matcher_line_term.equals(s.config.line_term) {
		return ConfigError.mismatched_line_terminators(matcher_line_term, s.config.line_term)
	}
}

/// Returns true if and only if the given slice needs to be transcoded.
fn (s &Searcher) slice_needs_transcoding(slice []u8) bool {
	return s.config.encoding != none || (s.config.bom_sniffing && slice_has_bom(slice))
}

fn file_needs_transcoding(config &Config, mut file os.File, path string, has_path bool) bool {
	if config.encoding != none {
		return true
	}
	if !config.bom_sniffing {
		return false
	}
	$if !windows {
		if has_path {
			return file_has_bom_at(mut file, i64(0))
		}
	}
	if has_path {
		return file_has_bom_at_current(mut file)
	}
	return file_has_bom_at_current(mut file)
}

fn file_has_bom(mut file os.File) bool {
	mut prefix := []u8{len: 3}
	defer { unsafe { prefix.free() } }
	nread := file.read(mut prefix) or { return false }
	return slice_has_bom(prefix[..nread])
}

fn file_has_bom_at_current(mut file os.File) bool {
	pos := file.tell() or { return false }
	return file_has_bom_at(mut file, i64(pos))
}

fn file_has_bom_at(mut file os.File, pos i64) bool {
	$if windows {
		current := file.tell() or { return false }
		file.seek(pos, .start) or { return false }
		mut prefix := []u8{len: 3}
		defer { unsafe { prefix.free() } }
		nread := file.read(mut prefix) or {
			file.seek(current, .start) or {}
			return false
		}
		file.seek(current, .start) or {}
		return slice_has_bom(prefix[..nread])
	} $else {
		mut prefix := []u8{len: 3}
		defer { unsafe { prefix.free() } }
		nread := C.pread(file.fd, prefix.data, u64(prefix.len), pos)
		if nread <= 0 {
			return false
		}
		return slice_has_bom(prefix[..int(nread)])
	}
}

fn (s &Searcher) transcode_slice(slice []u8) ![]u8 {
	return transcode_slice_with_config(&s.config, slice)
}

fn transcode_slice_with_config(config &Config, slice []u8) ![]u8 {
	if config.bom_sniffing {
		if slice_has_utf8_bom(slice) {
			return decode_utf8_lossy(slice[3..], true).bytes
		}
		if slice_has_utf16le_bom(slice) {
			return decode_utf16(slice[2..], false)
		}
		if slice_has_utf16be_bom(slice) {
			return decode_utf16(slice[2..], true)
		}
	}
	if encoding := config.encoding {
		match encoding.kind {
			.utf8 {
				return decode_utf8_lossy(slice, true).bytes
			}
			.utf16le {
				return decode_utf16(slice, false)
			}
			.utf16be {
				return decode_utf16(slice, true)
			}
			.windows1252 {
				return decode_windows1252(slice)
			}
			.shiftjis {
				return decode_iconv(slice, 'SHIFT_JIS')
			}
			.eucjp {
				return decode_iconv(slice, 'EUC-JP')
			}
			.xuserdefined {
				return decode_x_user_defined(slice)
			}
			.iconv {
				return decode_iconv(slice, encoding.iconv_name)
			}
		}
	}
	return slice.clone()
}

fn decode_iconv(slice []u8, label string) ![]u8 {
	if decoded := decode_encoding_single_byte(slice, label) {
		return decoded
	}
	$if windows {
		decoded := iconv.encoding_to_vstring(slice, label)!
		return decoded.bytes()
	} $else {
		mut stream := IconvStream.new(label)!
		defer {
			stream.close()
		}
		return stream.convert(slice, true)!.bytes
	}
}

struct TranscodingReader[^r] {
mut:
	rdr         &^r io.Reader
	config      Config
	initialized bool
	pending     []u8
	pending_pos int
	passthrough bool
	streaming   bool
	stream_kind EncodingKind
	iconv_streaming bool
	iconv_stream IconvStream
	raw_tail    []u8
	finished    bool
}

fn TranscodingReader.new[^r](rdr &^r io.Reader, config &Config) TranscodingReader[^r] {
	return TranscodingReader[^r]{
		rdr:    rdr
		config: config.clone()
	}
}

fn (mut rdr TranscodingReader[^r]) read[^r](mut buf []u8) !int {
	if !rdr.initialized {
		rdr.initialize()!
	}
	if rdr.pending_pos < rdr.pending.len {
		nread := copy(mut buf, rdr.pending[rdr.pending_pos..])
		rdr.pending_pos += nread
		return nread
	}
	if rdr.passthrough {
		return reader_ref_read(mut rdr.rdr, mut buf)!
	}
	if rdr.streaming {
		return rdr.read_streaming(mut buf)!
	}
	if rdr.iconv_streaming {
		return rdr.read_iconv_streaming(mut buf)!
	}
	return io.Eof{}
}

fn (mut rdr TranscodingReader[^r]) close[^r]() {
	if rdr.iconv_streaming {
		rdr.iconv_stream.close()
		rdr.iconv_streaming = false
	}
}

fn (mut rdr TranscodingReader[^r]) initialize[^r]() ! {
	rdr.initialized = true
	if rdr.config.encoding != none {
		encoding := rdr.config.encoding or { return }
		mut prefix := []u8{}
		if rdr.config.bom_sniffing {
			prefix = rdr.read_prefix(3)!
			if slice_has_utf16le_bom(prefix) {
				rdr.start_streaming(.utf16le, prefix[2..])
				return
			}
			if slice_has_utf16be_bom(prefix) {
				rdr.start_streaming(.utf16be, prefix[2..])
				return
			}
			if slice_has_utf8_bom(prefix) {
				rdr.start_streaming(.utf8, prefix[3..])
				return
			}
		}
		match encoding.kind {
			.utf8 {
				rdr.start_streaming(.utf8, prefix)
			}
			.utf16le, .utf16be, .windows1252, .xuserdefined {
				rdr.start_streaming(encoding.kind, prefix)
			}
			.shiftjis {
				rdr.start_iconv_streaming('SHIFT_JIS', prefix)!
			}
			.eucjp {
				rdr.start_iconv_streaming('EUC-JP', prefix)!
			}
			.iconv {
				rdr.start_iconv_streaming(encoding.iconv_name, prefix)!
			}
			else {
				mut raw := prefix.clone()
				read_to_end(mut rdr.rdr, mut raw)!
				rdr.pending = transcode_slice_with_config(&rdr.config, raw)!
			}
		}
		return
	}
	if !rdr.config.bom_sniffing {
		rdr.passthrough = true
		return
	}
	got := rdr.read_prefix(3)!
	if slice_has_utf16le_bom(got) {
		rdr.start_streaming(.utf16le, got[2..])
		return
	}
	if slice_has_utf16be_bom(got) {
		rdr.start_streaming(.utf16be, got[2..])
		return
	}
	if slice_has_utf8_bom(got) {
		rdr.start_streaming(.utf8, got[3..])
		return
	}
	rdr.pending = got.clone()
	rdr.passthrough = true
}

fn (mut rdr TranscodingReader[^r]) read_prefix[^r](n int) ![]u8 {
	mut prefix := []u8{len: n}
	mut nread_total := 0
	for nread_total < prefix.len {
		nread := reader_ref_read(mut rdr.rdr, mut prefix[nread_total..]) or {
			if is_reader_eof(err) {
				break
			}
			return err
		}
		if nread == 0 {
			break
		}
		nread_total += nread
	}
	return prefix[..nread_total].clone()
}

fn (mut rdr TranscodingReader[^r]) start_streaming(kind EncodingKind, initial []u8) {
	rdr.streaming = true
	rdr.stream_kind = kind
	rdr.raw_tail = initial.clone()
}

fn (mut rdr TranscodingReader[^r]) start_iconv_streaming[^r](label string, initial []u8) ! {
	rdr.iconv_stream = IconvStream.new(label)!
	rdr.iconv_streaming = true
	rdr.raw_tail = initial.clone()
}

fn (mut rdr TranscodingReader[^r]) read_streaming[^r](mut buf []u8) !int {
	for rdr.pending_pos >= rdr.pending.len {
		rdr.pending = []u8{}
		rdr.pending_pos = 0
		if rdr.finished {
			return io.Eof{}
		}
		mut raw := rdr.raw_tail.clone()
		rdr.raw_tail = []u8{}
		mut scratch := []u8{len: 8 * (1 << 10)}
		nread := reader_ref_read(mut rdr.rdr, mut scratch) or {
			if is_reader_eof(err) {
				rdr.finished = true
				if raw.len == 0 {
					return io.Eof{}
				}
				rdr.pending = rdr.decode_stream_chunk(raw, true)
				continue
			}
			return err
		}
		if nread == 0 {
			rdr.finished = true
			if raw.len == 0 {
				return io.Eof{}
			}
			rdr.pending = rdr.decode_stream_chunk(raw, true)
			continue
		}
		raw << scratch[..nread]
		rdr.pending = rdr.decode_stream_chunk(raw, false)
	}
	ncopy := copy(mut buf, rdr.pending[rdr.pending_pos..])
	rdr.pending_pos += ncopy
	return ncopy
}

fn (mut rdr TranscodingReader[^r]) decode_stream_chunk(raw []u8, final bool) []u8 {
	match rdr.stream_kind {
		.utf8 {
			decoded := decode_utf8_lossy(raw, final)
			rdr.raw_tail = decoded.tail
			return decoded.bytes
		}
		.windows1252 {
			return decode_windows1252(raw)
		}
		.xuserdefined {
			return decode_x_user_defined(raw)
		}
		.utf16le {
			usable := rdr.utf16_stream_usable_len(raw, false, final)
			return decode_utf16(raw[..usable], false)
		}
		.utf16be {
			usable := rdr.utf16_stream_usable_len(raw, true, final)
			return decode_utf16(raw[..usable], true)
		}
		else {
			return raw.clone()
		}
	}
}

// A streaming UTF-16 decoder must retain both an incomplete code unit and a
// complete high surrogate until the following chunk supplies its low surrogate.
fn (mut rdr TranscodingReader[^r]) utf16_stream_usable_len(raw []u8, big_endian bool, final bool) int {
	if final {
		return raw.len
	}
	mut usable := raw.len - (raw.len % 2)
	if usable >= 2 {
		last := if big_endian {
			u16(raw[usable - 2]) << 8 | u16(raw[usable - 1])
		} else {
			u16(raw[usable - 1]) << 8 | u16(raw[usable - 2])
		}
		if last >= 0xd800 && last <= 0xdbff {
			usable -= 2
		}
	}
	if usable < raw.len {
		rdr.raw_tail = raw[usable..].clone()
	}
	return usable
}

fn (mut rdr TranscodingReader[^r]) stream_usable_len(raw []u8, unit int, final bool) int {
	if final {
		return raw.len
	}
	usable := raw.len - (raw.len % unit)
	if usable < raw.len {
		rdr.raw_tail = raw[usable..].clone()
	}
	return usable
}

fn (mut rdr TranscodingReader[^r]) read_iconv_streaming[^r](mut buf []u8) !int {
	for rdr.pending_pos >= rdr.pending.len {
		rdr.pending = []u8{}
		rdr.pending_pos = 0
		if rdr.finished {
			return io.Eof{}
		}
		mut raw := rdr.raw_tail.clone()
		rdr.raw_tail = []u8{}
		mut scratch := []u8{len: 8 * (1 << 10)}
		nread := reader_ref_read(mut rdr.rdr, mut scratch) or {
			if is_reader_eof(err) {
				rdr.finished = true
				if raw.len == 0 {
					return io.Eof{}
				}
				converted := rdr.iconv_stream.convert(raw, true)!
				rdr.pending = converted.bytes
				continue
			}
			return err
		}
		if nread == 0 {
			rdr.finished = true
			if raw.len == 0 {
				return io.Eof{}
			}
			converted := rdr.iconv_stream.convert(raw, true)!
			rdr.pending = converted.bytes
			continue
		}
		raw << scratch[..nread]
		converted := rdr.iconv_stream.convert(raw, false)!
		rdr.pending = converted.bytes
		rdr.raw_tail = converted.tail
	}
	ncopy := copy(mut buf, rdr.pending[rdr.pending_pos..])
	rdr.pending_pos += ncopy
	return ncopy
}

struct IconvConvertResult {
	bytes []u8
	tail  []u8
}

struct IconvStream {
mut:
	cd                   voidptr = unsafe { nil }
	active               bool
	single_byte_table    int = -1
	exact_multibyte_kind int
	windows_label        string
	windows_iso2022_mode int
	iso2022_state        int
	iso2022_output_state int
	iso2022_output_flag  bool
}

fn IconvStream.new(label string) !IconvStream {
	table_id := encoding_single_byte_table_id(label)
	if table_id >= 0 {
		return IconvStream{
			active:            true
			single_byte_table: table_id
		}
	}
	exact_kind := exact_multibyte_encoding_kind(label)
	if exact_kind > 0 {
		return IconvStream{
			active:               true
			exact_multibyte_kind: exact_kind
		}
	}
	$if windows {
		// The Windows iconv adapter is one-shot, so retain the encoding and
		// explicitly preserve multibyte boundaries and ISO-2022-JP state.
		return IconvStream{
			active:        true
			windows_label: label.to_owned()
		}
	} $else {
		mut src_encoding := normalize_iconv_encoding(label)
		dst_encoding := 'UTF-8'
		cd := C.iconv_open(charptr(dst_encoding.str), charptr(src_encoding.str))
		if isize(cd) == -1 {
			return error('platform can\'t convert from ${src_encoding} to ${dst_encoding}')
		}
		return IconvStream{
			cd:     cd
			active: true
		}
	}
}

fn normalize_iconv_encoding(label string) string {
	mut encoding_name := label.to_upper()
	match encoding_name {
		'UTF16LE' { encoding_name = 'UTF-16LE' }
		'UTF16BE' { encoding_name = 'UTF-16BE' }
		'UTF32LE' { encoding_name = 'UTF-32LE' }
		'UTF32BE' { encoding_name = 'UTF-32BE' }
		else {}
	}
	if encoding_name == 'LOCAL' {
		$if windows {
			encoding_name = 'ANSI'
		} $else {
			encoding_name = 'UTF-8'
		}
	}
	return encoding_name
}

fn (mut stream IconvStream) close() {
	$if !windows {
		if stream.active && !isnil(stream.cd) {
			C.iconv_close(stream.cd)
		}
	}
	stream.cd = unsafe { nil }
	stream.active = false
}

fn (mut stream IconvStream) convert(input []u8, final bool) !IconvConvertResult {
	if stream.single_byte_table >= 0 {
		return IconvConvertResult{
			bytes: decode_encoding_single_byte_table(input, stream.single_byte_table)
			tail:  []u8{}
		}
	}
	if stream.exact_multibyte_kind > 0 {
		return stream.decode_exact_multibyte(input, final)
	}
	$if windows {
		if !stream.active {
			return error('iconv stream is closed')
		}
		return stream.convert_windows(input, final)
	} $else {
		if !stream.active || isnil(stream.cd) {
			return error('iconv stream is closed')
		}
		mut out_len := input.len * 4
		if out_len < 64 {
			out_len = 64
		}
		mut out := []u8{len: out_len}
		mut src_ptr := charptr(input.data)
		mut src_left := usize(input.len)
		mut written_total := 0
		for {
			if written_total >= out.len {
				out << []u8{len: 8 * (1 << 10)}
			}
			mut dst_ptr := unsafe { charptr(voidptr(usize(out.data) + usize(written_total))) }
			mut dst_left := usize(out.len - written_total)
			res := C.iconv(stream.cd, &src_ptr, &src_left, &dst_ptr, &dst_left)
			written_total = out.len - int(dst_left)
			if res != usize(-1) {
				out.trim(written_total)
				return IconvConvertResult{
					bytes: out
					tail:  []u8{}
				}
			}
			c_errno := int(C.errno)
			if c_errno == C.rg_iconv_error_output_full() {
				if written_total >= out.len {
					out << []u8{len: 8 * (1 << 10)}
				}
				continue
			}
			if c_errno == C.rg_iconv_error_incomplete_sequence() && !final {
				consumed := input.len - int(src_left)
				out.trim(written_total)
				return IconvConvertResult{
					bytes: out
					tail:  input[consumed..].clone()
				}
			}
			if c_errno == C.rg_iconv_error_illegal_sequence()
				|| (c_errno == C.rg_iconv_error_incomplete_sequence() && final) {
				if src_left == 0 {
					out.trim(written_total)
					return IconvConvertResult{
						bytes: out
						tail:  []u8{}
					}
				}
				if out.len - written_total < 3 {
					out << []u8{len: 8 * (1 << 10)}
				}
				out[written_total] = 0xef
				out[written_total + 1] = 0xbf
				out[written_total + 2] = 0xbd
				written_total += 3
				consume := if c_errno == C.rg_iconv_error_incomplete_sequence() {
					int(src_left)
				} else {
					1
				}
				src_ptr = unsafe { charptr(voidptr(usize(src_ptr) + usize(consume))) }
				src_left -= usize(consume)
				continue
			}
			msg := if c_errno == 0 { 'unknown iconv failure' } else { os.posix_get_error_msg(c_errno) }
			return error('convert encoding string fail: ${msg}')
		}
		return IconvConvertResult{}
	}
}

const exact_multibyte_shift_jis = 1
const exact_multibyte_euc_jp = 2
const exact_multibyte_big5 = 3
const exact_multibyte_gbk = 4
const exact_multibyte_gb18030 = 5
const exact_multibyte_euc_kr = 6
const exact_multibyte_iso2022_jp = 7

const iso2022_ascii = 0
const iso2022_roman = 1
const iso2022_katakana = 2
const iso2022_lead = 3
const iso2022_trail = 4
const iso2022_escape_start = 5
const iso2022_escape = 6

fn exact_multibyte_encoding_kind(label string) int {
	return match label.to_upper() {
		'SHIFT_JIS' { exact_multibyte_shift_jis }
		'EUC-JP' { exact_multibyte_euc_jp }
		'BIG5' { exact_multibyte_big5 }
		'GBK' { exact_multibyte_gbk }
		'GB18030' { exact_multibyte_gb18030 }
		'EUC-KR' { exact_multibyte_euc_kr }
		'ISO-2022-JP' { exact_multibyte_iso2022_jp }
		else { 0 }
	}
}

fn (mut stream IconvStream) decode_exact_multibyte(input []u8, final bool) !IconvConvertResult {
	return match stream.exact_multibyte_kind {
		exact_multibyte_shift_jis { decode_shift_jis_exact(input, final) }
		exact_multibyte_euc_jp { decode_euc_jp_exact(input, final) }
		exact_multibyte_big5 { decode_big5_exact(input, final) }
		exact_multibyte_gbk, exact_multibyte_gb18030 { decode_gb18030_exact(input, final) }
		exact_multibyte_euc_kr { decode_euc_kr_exact(input, final) }
		exact_multibyte_iso2022_jp { stream.decode_iso2022_jp_exact(input, final) }
		else { return error('unknown exact multibyte decoder') }
	}
}

fn incomplete_multibyte_result(mut out []u8, input []u8, at int, final bool) IconvConvertResult {
	if final {
		append_utf8(mut out, u32(0xfffd))
		return IconvConvertResult{
			bytes: out
			tail:  []u8{}
		}
	}
	return IconvConvertResult{
		bytes: out
		tail:  input[at..].clone()
	}
}

fn decode_shift_jis_exact(input []u8, final bool) IconvConvertResult {
	mut out := []u8{cap: input.len}
	mut i := 0
	for i < input.len {
		first := input[i]
		if first < 0x80 || first == 0x80 {
			append_utf8(mut out, u32(first))
			i++
			continue
		}
		if first >= 0xa1 && first <= 0xdf {
			append_utf8(mut out, u32(0xff61) + u32(first - 0xa1))
			i++
			continue
		}
		if !((first >= 0x81 && first <= 0x9f) || (first >= 0xe0 && first <= 0xfc)) {
			append_utf8(mut out, u32(0xfffd))
			i++
			continue
		}
		if i + 1 >= input.len {
			return incomplete_multibyte_result(mut out, input, i, final)
		}
		second := input[i + 1]
		valid_trail := (second >= 0x40 && second <= 0x7e)
			|| (second >= 0x80 && second <= 0xfc)
		mut codepoint := u32(0)
		if valid_trail {
			lead_offset := if first <= 0x9f { 0x81 } else { 0xc1 }
			trail_offset := if second <= 0x7e { 0x40 } else { 0x41 }
			pointer := (int(first) - lead_offset) * 188 + int(second) - trail_offset
			codepoint = C.rg_index_jis0208_lookup(pointer)
			if codepoint == 0 && pointer >= 8836 && pointer <= 10715 {
				codepoint = u32(0xe000 + pointer - 8836)
			}
		}
		if codepoint != 0 {
			append_utf8(mut out, codepoint)
			i += 2
		} else {
			append_utf8(mut out, u32(0xfffd))
			i += if second < 0x80 { 1 } else { 2 }
		}
	}
	return IconvConvertResult{out, []u8{}}
}

fn decode_euc_jp_exact(input []u8, final bool) IconvConvertResult {
	mut out := []u8{cap: input.len}
	mut i := 0
	for i < input.len {
		first := input[i]
		if first < 0x80 {
			append_utf8(mut out, u32(first))
			i++
			continue
		}
		if first >= 0xa1 && first <= 0xfe {
			if i + 1 >= input.len {
				return incomplete_multibyte_result(mut out, input, i, final)
			}
			second := input[i + 1]
			mut codepoint := u32(0)
			if second >= 0xa1 && second <= 0xfe {
				pointer := (int(first) - 0xa1) * 94 + int(second) - 0xa1
				codepoint = C.rg_index_jis0208_lookup(pointer)
			}
			if codepoint != 0 {
				append_utf8(mut out, codepoint)
				i += 2
			} else {
				append_utf8(mut out, u32(0xfffd))
				i += if second < 0x80 { 1 } else { 2 }
			}
			continue
		}
		if first == 0x8e {
			if i + 1 >= input.len {
				return incomplete_multibyte_result(mut out, input, i, final)
			}
			second := input[i + 1]
			if second >= 0xa1 && second <= 0xdf {
				append_utf8(mut out, u32(0xff61) + u32(second - 0xa1))
				i += 2
			} else {
				append_utf8(mut out, u32(0xfffd))
				i += if second < 0x80 { 1 } else { 2 }
			}
			continue
		}
		if first == 0x8f {
			if i + 2 >= input.len {
				return incomplete_multibyte_result(mut out, input, i, final)
			}
			second := input[i + 1]
			if second < 0xa1 || second > 0xfe {
				append_utf8(mut out, u32(0xfffd))
				i += if second < 0x80 { 1 } else { 2 }
				continue
			}
			third := input[i + 2]
			mut codepoint := u32(0)
			if third >= 0xa1 && third <= 0xfe {
				pointer := (int(second) - 0xa1) * 94 + int(third) - 0xa1
				codepoint = C.rg_index_jis0212_lookup(pointer)
			}
			if codepoint != 0 {
				append_utf8(mut out, codepoint)
				i += 3
			} else {
				append_utf8(mut out, u32(0xfffd))
				i += if third < 0x80 { 2 } else { 3 }
			}
			continue
		}
		append_utf8(mut out, u32(0xfffd))
		i++
	}
	return IconvConvertResult{out, []u8{}}
}

fn decode_big5_exact(input []u8, final bool) IconvConvertResult {
	mut out := []u8{cap: input.len}
	mut i := 0
	for i < input.len {
		first := input[i]
		if first < 0x80 {
			append_utf8(mut out, u32(first))
			i++
			continue
		}
		if first < 0x81 || first > 0xfe {
			append_utf8(mut out, u32(0xfffd))
			i++
			continue
		}
		if i + 1 >= input.len {
			return incomplete_multibyte_result(mut out, input, i, final)
		}
		second := input[i + 1]
		mut trail_offset := -1
		if second >= 0x40 && second <= 0x7e {
			trail_offset = int(second) - 0x40
		} else if second >= 0xa1 && second <= 0xfe {
			trail_offset = int(second) - 0x62
		}
		mut codepoint := u32(0)
		mut pointer := -1
		if trail_offset >= 0 {
			pointer = (int(first) - 0x81) * 157 + trail_offset
			codepoint = C.rg_index_big5_lookup(pointer)
		}
		if pointer in [1133, 1135, 1164, 1166] {
			append_utf8(mut out, if pointer < 1164 { u32(0x00ca) } else { u32(0x00ea) })
			append_utf8(mut out, if pointer in [1133, 1164] { u32(0x0304) } else { u32(0x030c) })
			i += 2
		} else if codepoint != 0 {
			append_utf8(mut out, codepoint)
			i += 2
		} else {
			append_utf8(mut out, u32(0xfffd))
			i += if second < 0x80 { 1 } else { 2 }
		}
	}
	return IconvConvertResult{out, []u8{}}
}

fn decode_euc_kr_exact(input []u8, final bool) IconvConvertResult {
	mut out := []u8{cap: input.len}
	mut i := 0
	for i < input.len {
		first := input[i]
		if first < 0x80 {
			append_utf8(mut out, u32(first))
			i++
			continue
		}
		if first < 0x81 || first > 0xfe {
			append_utf8(mut out, u32(0xfffd))
			i++
			continue
		}
		if i + 1 >= input.len {
			return incomplete_multibyte_result(mut out, input, i, final)
		}
		second := input[i + 1]
		mut codepoint := u32(0)
		if second >= 0x41 && second <= 0xfe {
			pointer := (int(first) - 0x81) * 190 + int(second) - 0x41
			codepoint = C.rg_index_euc_kr_lookup(pointer)
		}
		if codepoint != 0 {
			append_utf8(mut out, codepoint)
			i += 2
		} else {
			append_utf8(mut out, u32(0xfffd))
			i += if second < 0x80 { 1 } else { 2 }
		}
	}
	return IconvConvertResult{out, []u8{}}
}

fn decode_gb18030_exact(input []u8, final bool) IconvConvertResult {
	mut out := []u8{cap: input.len}
	mut i := 0
	for i < input.len {
		first := input[i]
		if first < 0x80 {
			append_utf8(mut out, u32(first))
			i++
			continue
		}
		if first == 0x80 {
			append_utf8(mut out, u32(0x20ac))
			i++
			continue
		}
		if first < 0x81 || first > 0xfe {
			append_utf8(mut out, u32(0xfffd))
			i++
			continue
		}
		if i + 1 >= input.len {
			return incomplete_multibyte_result(mut out, input, i, final)
		}
		second := input[i + 1]
		if second >= 0x30 && second <= 0x39 {
			if i + 3 >= input.len {
				return incomplete_multibyte_result(mut out, input, i, final)
			}
			third := input[i + 2]
			fourth := input[i + 3]
			if third < 0x81 || third > 0xfe || fourth < 0x30 || fourth > 0x39 {
				append_utf8(mut out, u32(0xfffd))
				i++
				continue
			}
			pointer := (u32(first) - 0x81) * (10 * 126 * 10) + (u32(second) - 0x30) * (10 * 126) +
				(u32(third) - 0x81) * 10 + u32(fourth) - 0x30
			mut codepoint := u32(0)
			if pointer <= 39419 {
				codepoint = if pointer == 7457 { u32(0xe7c7) } else { C.rg_gb18030_range_lookup(pointer) }
			} else if pointer >= 189000 && pointer <= 1237575 {
				codepoint = pointer - 189000 + 0x10000
			}
			append_utf8(mut out, if codepoint == 0 { u32(0xfffd) } else { codepoint })
			i += 4
			continue
		}
		mut codepoint := u32(0)
		mut trail_offset := -1
		if second >= 0x40 && second <= 0x7e {
			trail_offset = int(second) - 0x40
		} else if second >= 0x80 && second <= 0xfe {
			trail_offset = int(second) - 0x41
		}
		if trail_offset >= 0 {
			pointer := (int(first) - 0x81) * 190 + trail_offset
			codepoint = C.rg_index_gb18030_lookup(pointer)
		}
		if codepoint != 0 {
			append_utf8(mut out, codepoint)
			i += 2
		} else {
			append_utf8(mut out, u32(0xfffd))
			i += if second < 0x80 { 1 } else { 2 }
		}
	}
	return IconvConvertResult{out, []u8{}}
}

fn (mut stream IconvStream) iso2022_output_byte(byte u8, mut out []u8) {
	stream.iso2022_output_flag = false
	match stream.iso2022_state {
		iso2022_ascii {
			if byte > 0x7f || byte in [u8(0x0e), 0x0f] {
				append_utf8(mut out, u32(0xfffd))
			} else {
				append_utf8(mut out, u32(byte))
			}
		}
		iso2022_roman {
			if byte == 0x5c {
				append_utf8(mut out, u32(0x00a5))
			} else if byte == 0x7e {
				append_utf8(mut out, u32(0x203e))
			} else if byte > 0x7f || byte in [u8(0x0e), 0x0f] {
				append_utf8(mut out, u32(0xfffd))
			} else {
				append_utf8(mut out, u32(byte))
			}
		}
		iso2022_katakana {
			if byte >= 0x21 && byte <= 0x5f {
				append_utf8(mut out, u32(0xff61) + u32(byte - 0x21))
			} else {
				append_utf8(mut out, u32(0xfffd))
			}
		}
		iso2022_lead {
			if byte >= 0x21 && byte <= 0x7e {
				stream.windows_iso2022_mode = int(byte)
				stream.iso2022_state = iso2022_trail
			} else {
				append_utf8(mut out, u32(0xfffd))
			}
		}
		else {
			append_utf8(mut out, u32(0xfffd))
		}
	}
}

fn (mut stream IconvStream) decode_iso2022_jp_exact(input []u8, final bool) IconvConvertResult {
	mut out := []u8{cap: input.len}
	mut i := 0
	mut escape_start := -1
	mut escape_prior_state := stream.iso2022_state
	mut escape_prior_flag := stream.iso2022_output_flag
	mut pair_start := -1
	for i < input.len {
		byte := input[i]
		if stream.iso2022_state in [iso2022_ascii, iso2022_roman, iso2022_katakana,
			iso2022_lead] {
			if byte == 0x1b {
				escape_start = i
				escape_prior_state = stream.iso2022_state
				escape_prior_flag = stream.iso2022_output_flag
				stream.iso2022_state = iso2022_escape_start
				i++
				continue
			}
			if stream.iso2022_state == iso2022_lead && byte >= 0x21 && byte <= 0x7e {
				pair_start = i
			}
			stream.iso2022_output_byte(byte, mut out)
			i++
			continue
		}
		if stream.iso2022_state == iso2022_trail {
			lead := u8(stream.windows_iso2022_mode)
			stream.windows_iso2022_mode = 0
			stream.iso2022_state = iso2022_lead
			if byte == 0x1b {
				append_utf8(mut out, u32(0xfffd))
				escape_start = i
				escape_prior_state = iso2022_lead
				escape_prior_flag = false
				stream.iso2022_state = iso2022_escape_start
				pair_start = -1
				i++
				continue
			}
			mut codepoint := u32(0)
			if byte >= 0x21 && byte <= 0x7e {
				pointer := (int(lead) - 0x21) * 94 + int(byte) - 0x21
				codepoint = C.rg_index_jis0208_lookup(pointer)
			}
			append_utf8(mut out, if codepoint == 0 { u32(0xfffd) } else { codepoint })
			stream.iso2022_output_flag = false
			pair_start = -1
			i++
			continue
		}
		if stream.iso2022_state == iso2022_escape_start {
			if byte in [u8(`$`), `(`] {
				stream.windows_iso2022_mode = int(byte)
				stream.iso2022_state = iso2022_escape
				i++
				continue
			}
			append_utf8(mut out, u32(0xfffd))
			stream.iso2022_state = stream.iso2022_output_state
			stream.iso2022_output_flag = false
			escape_start = -1
			continue
		}
		if stream.iso2022_state == iso2022_escape {
			lead := u8(stream.windows_iso2022_mode)
			mut next_state := -1
			if lead == `(` && byte == `B` {
				next_state = iso2022_ascii
			} else if lead == `(` && byte == `J` {
				next_state = iso2022_roman
			} else if lead == `(` && byte == `I` {
				next_state = iso2022_katakana
			} else if lead == `$` && byte in [u8(`@`), `B`] {
				next_state = iso2022_lead
			}
			if next_state >= 0 {
				if stream.iso2022_output_flag {
					append_utf8(mut out, u32(0xfffd))
				}
				stream.windows_iso2022_mode = 0
				stream.iso2022_state = next_state
				stream.iso2022_output_state = next_state
				stream.iso2022_output_flag = true
				escape_start = -1
				i++
				continue
			}
			append_utf8(mut out, u32(0xfffd))
			stream.windows_iso2022_mode = 0
			stream.iso2022_state = stream.iso2022_output_state
			stream.iso2022_output_flag = false
			stream.iso2022_output_byte(lead, mut out)
			escape_start = -1
			continue
		}
	}
	if !final {
		if stream.iso2022_state in [iso2022_escape_start, iso2022_escape] && escape_start >= 0 {
			stream.iso2022_state = escape_prior_state
			stream.iso2022_output_flag = escape_prior_flag
			stream.windows_iso2022_mode = 0
			return IconvConvertResult{
				bytes: out
				tail:  input[escape_start..].clone()
			}
		}
		if stream.iso2022_state == iso2022_trail && pair_start >= 0 {
			stream.iso2022_state = iso2022_lead
			stream.windows_iso2022_mode = 0
			return IconvConvertResult{
				bytes: out
				tail:  input[pair_start..].clone()
			}
		}
	} else {
		if stream.iso2022_state == iso2022_trail {
			append_utf8(mut out, u32(0xfffd))
			stream.iso2022_state = iso2022_lead
			stream.windows_iso2022_mode = 0
		} else if stream.iso2022_state == iso2022_escape_start {
			append_utf8(mut out, u32(0xfffd))
			stream.iso2022_state = stream.iso2022_output_state
			stream.iso2022_output_flag = false
		} else if stream.iso2022_state == iso2022_escape {
			lead := u8(stream.windows_iso2022_mode)
			append_utf8(mut out, u32(0xfffd))
			stream.iso2022_state = stream.iso2022_output_state
			stream.iso2022_output_flag = false
			stream.iso2022_output_byte(lead, mut out)
			if stream.iso2022_state == iso2022_trail {
				append_utf8(mut out, u32(0xfffd))
				stream.iso2022_state = iso2022_lead
				stream.windows_iso2022_mode = 0
			}
		}
	}
	return IconvConvertResult{out, []u8{}}
}

fn (mut stream IconvStream) convert_windows(input []u8, final bool) !IconvConvertResult {
	mut usable := input.len
	mut next_mode := stream.windows_iso2022_mode
	if !final {
		if stream.windows_label.to_upper() == 'ISO-2022-JP' {
			usable, next_mode = iso2022jp_stream_boundary(input, stream.windows_iso2022_mode)
		} else {
			usable = multibyte_stream_boundary(input, stream.windows_label)
		}
	}
	if usable == 0 {
		return IconvConvertResult{
			bytes: []u8{}
			tail:  input.clone()
		}
	}
	mut source := input[..usable].clone()
	if stream.windows_label.to_upper() == 'ISO-2022-JP' && source.len > 0 {
		prefix := iso2022jp_mode_prefix(stream.windows_iso2022_mode)
		if prefix.len > 0 {
			source.prepend(prefix)
		}
	}
	bytes := decode_iconv(source, stream.windows_label)!
	stream.windows_iso2022_mode = next_mode
	return IconvConvertResult{
		bytes: bytes
		tail:  input[usable..].clone()
	}
}

// Returns the largest prefix that does not split a character. Single-byte
// encodings return the complete input. Malformed bytes are left in the prefix
// so that the platform decoder applies its normal replacement behavior.
fn multibyte_stream_boundary(input []u8, label string) int {
	upper := label.to_upper()
	mut i := 0
	for i < input.len {
		byte := input[i]
		mut width := 1
		match upper {
			'SHIFT_JIS' {
				if (byte >= 0x81 && byte <= 0x9f) || (byte >= 0xe0 && byte <= 0xfc) {
					width = 2
				}
			}
			'EUC-JP' {
				if byte == 0x8f {
					width = 3
				} else if byte == 0x8e || (byte >= 0xa1 && byte <= 0xfe) {
					width = 2
				}
			}
			'BIG5', 'GBK', 'EUC-KR' {
				if byte >= 0x81 && byte <= 0xfe {
					width = 2
				}
			}
			'GB18030' {
				if byte >= 0x81 && byte <= 0xfe {
					if i + 1 >= input.len {
						return i
					}
					width = if input[i + 1] >= 0x30 && input[i + 1] <= 0x39 { 4 } else { 2 }
				}
			}
			else {}
		}
		if i + width > input.len {
			return i
		}
		i += width
	}
	return i
}

fn iso2022jp_mode_prefix(mode int) []u8 {
	return match mode {
		1 { [u8(0x1b), `(`, `J`] }
		2 { [u8(0x1b), `(`, `I`] }
		3 { [u8(0x1b), `$`, `B`] }
		4 { [u8(0x1b), `$`, `(`, `D`] }
		else { []u8{} }
	}
}

// ISO-2022-JP is stateful. This finds a complete prefix and reports the mode
// at its end so the next Windows one-shot conversion can resume in that mode.
fn iso2022jp_stream_boundary(input []u8, initial_mode int) (int, int) {
	mut mode := initial_mode
	mut i := 0
	for i < input.len {
		if input[i] == 0x1b {
			if i + 2 >= input.len {
				return i, mode
			}
			if input[i + 1] == `$` && input[i + 2] == `(` {
				if i + 3 >= input.len {
					return i, mode
				}
				mode = if input[i + 3] == `D` { 4 } else { 0 }
				i += 4
				continue
			}
			if input[i + 1] == `$` && input[i + 2] in [`@`, `B`] {
				mode = 3
			} else if input[i + 1] == `(` && input[i + 2] == `J` {
				mode = 1
			} else if input[i + 1] == `(` && input[i + 2] == `I` {
				mode = 2
			} else if input[i + 1] == `(` && input[i + 2] == `B` {
				mode = 0
			}
			i += 3
			continue
		}
		if mode in [3, 4] {
			if i + 1 >= input.len {
				return i, mode
			}
			i += 2
		} else {
			i++
		}
	}
	return i, mode
}

fn read_to_end(mut read_from &io.Reader, mut dst []u8) ! {
	mut scratch := []u8{len: 8 * (1 << 10)}
	for {
		nread := reader_ref_read(mut read_from, mut scratch) or {
			if is_reader_eof(err) {
				break
			}
			return err
		}
		if nread == 0 {
			break
		}
		dst << scratch[..nread]
	}
}

struct DecodedUtf8 {
	bytes []u8
	tail  []u8
}

fn decode_utf8_lossy(input []u8, final bool) DecodedUtf8 {
	mut out := []u8{cap: input.len}
	mut i := 0
	for i < input.len {
		first := input[i]
		if first < 0x80 {
			out << first
			i++
			continue
		}
		width := if first >= 0xc2 && first <= 0xdf {
			2
		} else if first >= 0xe0 && first <= 0xef {
			3
		} else if first >= 0xf0 && first <= 0xf4 {
			4
		} else {
			append_utf8(mut out, u32(0xfffd))
			i++
			continue
		}
		mut valid_prefix := 1
		mut invalid := false
		for offset in 1 .. width {
			if i + offset >= input.len {
				if !final {
					return DecodedUtf8{
						bytes: out
						tail:  input[i..].clone()
					}
				}
				append_utf8(mut out, u32(0xfffd))
				i = input.len
				invalid = true
				break
			}
			byte := input[i + offset]
			mut lower := u8(0x80)
			mut upper := u8(0xbf)
			if offset == 1 {
				if first == 0xe0 {
					lower = 0xa0
				} else if first == 0xed {
					upper = 0x9f
				} else if first == 0xf0 {
					lower = 0x90
				} else if first == 0xf4 {
					upper = 0x8f
				}
			}
			if byte < lower || byte > upper {
				append_utf8(mut out, u32(0xfffd))
				i += valid_prefix
				invalid = true
				break
			}
			valid_prefix++
		}
		if invalid {
			continue
		}
		out << input[i..i + width]
		i += width
	}
	return DecodedUtf8{
		bytes: out
		tail:  []u8{}
	}
}

fn reader_ref_read(mut read_from &io.Reader, mut buf []u8) !int {
	return read_from.read(mut buf)!
}

fn decode_utf16(slice []u8, big_endian bool) []u8 {
	mut out := []u8{cap: slice.len}
	mut i := 0
	for i + 1 < slice.len {
		unit := read_u16(slice[i], slice[i + 1], big_endian)
		i += 2
		if unit >= u16(0xd800) && unit <= u16(0xdbff) {
			if i + 1 < slice.len {
				next := read_u16(slice[i], slice[i + 1], big_endian)
				if next >= u16(0xdc00) && next <= u16(0xdfff) {
					codepoint := u32(0x10000) + ((u32(unit) - u32(0xd800)) << 10) +
						(u32(next) - u32(0xdc00))
					append_utf8(mut out, codepoint)
					i += 2
					continue
				}
			}
			append_utf8(mut out, u32(0xfffd))
		} else if unit >= u16(0xdc00) && unit <= u16(0xdfff) {
			append_utf8(mut out, u32(0xfffd))
		} else {
			append_utf8(mut out, u32(unit))
		}
	}
	if i < slice.len {
		append_utf8(mut out, u32(0xfffd))
	}
	return out
}

fn read_u16(first u8, second u8, big_endian bool) u16 {
	if big_endian {
		return (u16(first) << 8) | u16(second)
	}
	return (u16(second) << 8) | u16(first)
}

fn decode_windows1252(slice []u8) []u8 {
	return decode_encoding_single_byte(slice, 'WINDOWS-1252') or { []u8{} }
}

fn decode_x_user_defined(slice []u8) []u8 {
	mut out := []u8{cap: slice.len}
	for byte in slice {
		if byte < 0x80 {
			append_utf8(mut out, u32(byte))
		} else {
			append_utf8(mut out, u32(0xf780) + u32(byte) - u32(0x80))
		}
	}
	return out
}

fn append_utf8(mut bytes []u8, codepoint u32) {
	if codepoint < 0x80 {
		bytes << u8(codepoint)
	} else if codepoint < 0x800 {
		bytes << u8(0xc0 | (codepoint >> 6))
		bytes << u8(0x80 | (codepoint & 0x3f))
	} else if codepoint < 0x10000 {
		bytes << u8(0xe0 | (codepoint >> 12))
		bytes << u8(0x80 | ((codepoint >> 6) & 0x3f))
		bytes << u8(0x80 | (codepoint & 0x3f))
	} else {
		bytes << u8(0xf0 | (codepoint >> 18))
		bytes << u8(0x80 | ((codepoint >> 12) & 0x3f))
		bytes << u8(0x80 | ((codepoint >> 6) & 0x3f))
		bytes << u8(0x80 | (codepoint & 0x3f))
	}
}

/// Fill the buffer for use with multi-line searching from the given file.
/// This reads from the file until EOF or until an error occurs. If the
/// contents exceed the configured heap limit, then an error is returned.
fn (mut s Searcher) fill_multi_line_buffer_from_file(mut file os.File, path string, has_path bool) ! {
	assert s.config.multi_line
	mut read_from := TranscodingReader.new(&file, &s.config)
	defer {
		read_from.close()
	}

	if s.config.heap_limit != none {
		s.multi_line_buffer = []u8{}
		s.read_all_into_multi_line_buffer(mut read_from)!
		return
	}
	capacity := mmap_file_size(mut file, path, has_path) or { usize(0) }
	s.multi_line_buffer = []u8{cap: int(capacity + 1)}
	s.read_all_into_multi_line_buffer(mut read_from)!
}

/// Fill the buffer for use with multi-line searching from the given
/// reader. This reads from the reader until EOF or until an error occurs.
/// If the contents exceed the configured heap limit, then an error is
/// returned.
fn (mut s Searcher) fill_multi_line_buffer_from_reader(mut read_from io.Reader) ! {
	assert s.config.multi_line
	mut decoded := TranscodingReader.new(&read_from, &s.config)
	defer {
		decoded.close()
	}

	s.multi_line_buffer = []u8{}
	if limit := s.config.heap_limit {
		if limit == 0 {
			return alloc_error(limit)
		}
	}
	s.read_all_into_multi_line_buffer(mut decoded)!
}

fn (mut s Searcher) read_all_into_multi_line_buffer(mut read_from io.Reader) ! {
	mut scratch := []u8{len: 8 * (1 << 10)}
	for {
		nread := read_from.read(mut scratch) or {
			if is_reader_eof(err) {
				break
			}
			return err
		}
		if nread == 0 {
			break
		}
		if limit := s.config.heap_limit {
			if usize(s.multi_line_buffer.len + nread) >= limit {
				return alloc_error(limit)
			}
		}
		s.multi_line_buffer << scratch[..nread]
	}
}

/// The following methods permit querying the configuration of a searcher.
/// These can be useful in generic implementations of [`Sink`], where the
/// output may be tailored based on how the searcher is configured.

/// Returns the line terminator used by this searcher.
pub fn (s &Searcher) line_terminator() matcher.LineTerminator {
	return s.config.line_term
}

/// Returns the type of binary detection configured on this searcher.
pub fn (s &^a Searcher) binary_detection[^a]() &^a BinaryDetection {
	return &s.config.binary
}

/// Returns true if and only if this searcher is configured to invert its
/// search results. That is, matching lines are lines that do **not** match
/// the searcher's matcher.
pub fn (s &Searcher) invert_match() bool {
	return s.config.invert_match
}

/// Returns true if and only if this searcher is configured to count line
/// numbers.
pub fn (s &Searcher) line_number() bool {
	return s.config.line_number
}

/// Returns true if and only if this searcher is configured to perform
/// multi line search.
pub fn (s &Searcher) multi_line() bool {
	return s.config.multi_line
}

/// Returns true if and only if this searcher is configured to stop when it
/// finds a non-matching line after a matching one.
pub fn (s &Searcher) stop_on_nonmatch() bool {
	return s.config.stop_on_nonmatch
}

/// Returns the maximum number of matches emitted by this searcher, if
/// such a limit was set.
///
/// If multi line search is enabled and a match spans multiple lines, then
/// that match is counted exactly once for the purposes of enforcing this
/// limit, regardless of how many lines it spans.
///
/// Note that `0` is a legal value. This will cause the searcher to
/// immediately quick without searching anything.
pub fn (s &Searcher) max_matches() ?u64 {
	return s.config.max_matches
}

/// Returns true if and only if this searcher will choose a multi-line
/// strategy given the provided matcher.
///
/// This may diverge from the result of `multi_line` in cases where the
/// searcher has been configured to execute a search that can report
/// matches over multiple lines, but where the matcher guarantees that it
/// will never produce a match over multiple lines.
pub fn (s &Searcher) multi_line_with_matcher(matcher_ &matcher.Matcher) bool {
	if !s.multi_line() {
		return false
	}
	if line_term := matcher_.line_terminator() {
		if line_term.equals(s.line_terminator()) {
			return false
		}
	}
	if non_matching := matcher_.non_matching_bytes() {
		// If the line terminator is CRLF, we don't actually need to care
		// whether the regex can match `\r` or not. Namely, a `\r` is
		// neither necessary nor sufficient to terminate a line. A `\n` is
		// always required.
		if matcher.byte_set_contains(non_matching, s.line_terminator().as_byte()) {
			return false
		}
	}
	return true
}

/// Returns the number of "after" context lines to report. When context
/// reporting is not enabled, this returns `0`.
pub fn (s &Searcher) after_context() usize {
	return s.config.after_context
}

/// Returns the number of "before" context lines to report. When context
/// reporting is not enabled, this returns `0`.
pub fn (s &Searcher) before_context() usize {
	return s.config.before_context
}

/// Returns true if and only if the searcher has "passthru" mode enabled.
pub fn (s &Searcher) passthru() bool {
	return s.config.passthru
}

// V-specific: update multi-line mode on an existing searcher.
pub fn (mut s Searcher) set_multi_line(yes bool) {
	s.config.multi_line = yes
}

// V-specific: update the line terminator on an existing searcher.
pub fn (mut s Searcher) set_line_terminator(line_terminator matcher.LineTerminator) {
	s.config.line_term = line_terminator
	s.line_buffer.config.lineterm = line_terminator.as_byte()
}

/// Set the binary detection method used on this searcher.
pub fn (mut s Searcher) set_binary_detection(binary_detection BinaryDetection) {
	s.config.binary = binary_detection
	s.line_buffer.set_binary_detection(binary_detection)
}

// V-specific: update inverted matching on an existing searcher.
pub fn (mut s Searcher) set_invert_match(yes bool) {
	s.config.invert_match = yes
}

/// A trait that describes errors that can be reported by searchers and
/// implementations of `Sink`.
///
/// Unless you have a specialized use case, you probably don't need to
/// implement this trait explicitly. It's likely that using `std::io::Error`
/// (which implements this trait) for your error type is good enough,
/// largely because most errors that occur during search will likely be an
/// `std::io::Error`.
///
/// V-specific: V's structural error interface supplies `msg` and `code`, while
/// the associated constructors are the functions below.
pub interface SinkError {
	msg() string
	code() int
}

/// A constructor for converting any value that satisfies the
/// `std::fmt::Display` trait into an error.
///
/// V-specific: V results use the common `IError` interface instead of an
/// associated `Sink::Error` type, so the `SinkError` constructors are exposed
/// as functions.
pub fn sink_error_message(message string) IError {
	return error(message)
}

/// A constructor for converting I/O errors that occur while searching into
/// an error of this type.
///
/// By default, this is implemented via the `error_message` constructor.
pub fn sink_error_io(err IError) IError {
	return err
}

/// A constructor for converting configuration errors that occur while
/// building a searcher into an error of this type.
///
/// By default, this is implemented via the `error_message` constructor.
pub fn sink_error_config(err ConfigError) IError {
	return error(err.msg())
}

// An `std::io::Error` can be used as an error for `Sink` implementations out
// of the box.
//
// A `Box<dyn std::error::Error>` can be used as an error for `Sink`
// implementations out of the box. V's corresponding common representation
// for both is `IError`.

/// Summary data reported at the end of a search.
///
/// This reports data such as the total number of bytes searched and the
/// absolute offset of the first occurrence of binary data, if any were found.
///
/// A searcher that stops early because of an error does not call `finish`.
/// A searcher that stops early because the `Sink` implementor instructed it
/// to will still call `finish`.
pub struct SinkFinish implements IClone {
	byte_count_         u64
	binary_byte_offset_ ?u64
}

// V-specific constructor used where Rust initializes crate-private fields.
pub fn SinkFinish.new(byte_count u64) SinkFinish {
	return SinkFinish{
		byte_count_: byte_count
	}
}

/// Return the total number of bytes searched.
pub fn (finish &SinkFinish) byte_count() u64 {
	return finish.byte_count_
}

/// If binary detection is enabled and if binary data was found, then this
/// returns the absolute byte offset of the first detected byte of binary
/// data.
///
/// Note that since this is an absolute byte offset, it cannot be relied
/// upon to index into any addressable memory.
pub fn (finish &SinkFinish) binary_byte_offset() ?u64 {
	return finish.binary_byte_offset_
}

// V-specific builder used where Rust initializes crate-private fields.
pub fn (finish SinkFinish) with_binary_byte_offset(binary_byte_offset ?u64) SinkFinish {
	return SinkFinish{
		byte_count_:         finish.byte_count_
		binary_byte_offset_: binary_byte_offset
	}
}

/// An iterator over lines in a particular slice of bytes.
///
/// Line terminators are considered part of the line they terminate. All lines
/// yielded by the iterator are guaranteed to be non-empty.
///
/// `'b` refers to the lifetime of the underlying bytes.
pub struct LineIter[^b] implements IClone {
	// V-specific: Rust stores this as a borrowed `&'b [u8]`; V's slice value is
	// the corresponding non-owning view into the active search buffer.
	bytes_   []u8
	stepper_ LineStep
}

/// Create a new line iterator that yields lines in the given bytes that
/// are terminated by `line_term`.
pub fn LineIter.new[^b](line_term u8, bytes []u8) LineIter[^b] {
	return LineIter[^b]{
		bytes_:   bytes
		stepper_: LineStep.new(line_term, 0, bytes.len)
	}
}

pub fn (iter &LineIter[^b]) count[^b]() u64 {
	mut stepper := iter.stepper_
	mut count := u64(0)
	for {
		m := stepper.next_match(iter.bytes_) or { break }
		_ = m
		count++
	}
	return count
}

pub fn (mut iter LineIter[^b]) next[^b]() ?[]u8 {
	m := iter.stepper_.next_match(iter.bytes_) or { return none }
	return iter.bytes_[m.start()..m.end()]
}

/// A type that describes a match reported by a searcher.
pub struct SinkMatch[^b] implements IClone {
	line_term_             matcher.LineTerminator = matcher.LineTerminator.default()
	// V-specific: V slices are already borrowed descriptors, while `^b` keeps
	// the Rust lifetime relationship explicit in the type and API.
	bytes_                 []u8
	absolute_byte_offset_  u64
	line_number_           ?u64
	buffer_                []u8
	bytes_range_in_buffer_ matcher.Match
}

// V-specific constructor used where Rust initializes crate-private fields.
pub fn SinkMatch.new[^b](buffer []u8, bytes_range_in_buffer matcher.Match) SinkMatch[^b] {
	return SinkMatch[^b]{
		bytes_:                 buffer[bytes_range_in_buffer.start()..bytes_range_in_buffer.end()]
		buffer_:                buffer
		bytes_range_in_buffer_: bytes_range_in_buffer
	}
}

// V-specific builder used where Rust initializes crate-private fields.
pub fn (mat SinkMatch[^b]) with_absolute_byte_offset[^b](absolute_byte_offset u64) SinkMatch[^b] {
	return SinkMatch[^b]{
		line_term_:             mat.line_term_
		bytes_:                 mat.bytes_
		absolute_byte_offset_:  absolute_byte_offset
		line_number_:           mat.line_number_
		buffer_:                mat.buffer_
		bytes_range_in_buffer_: mat.bytes_range_in_buffer_
	}
}

// V-specific builder used where Rust initializes crate-private fields.
pub fn (mat SinkMatch[^b]) with_line_number[^b](line_number ?u64) SinkMatch[^b] {
	return SinkMatch[^b]{
		line_term_:             mat.line_term_
		bytes_:                 mat.bytes_
		absolute_byte_offset_:  mat.absolute_byte_offset_
		line_number_:           line_number
		buffer_:                mat.buffer_
		bytes_range_in_buffer_: mat.bytes_range_in_buffer_
	}
}

// V-specific builder used where Rust initializes crate-private fields.
pub fn (mat SinkMatch[^b]) with_line_term[^b](line_term matcher.LineTerminator) SinkMatch[^b] {
	return SinkMatch[^b]{
		line_term_:             line_term
		bytes_:                 mat.bytes_
		absolute_byte_offset_:  mat.absolute_byte_offset_
		line_number_:           mat.line_number_
		buffer_:                mat.buffer_
		bytes_range_in_buffer_: mat.bytes_range_in_buffer_
	}
}

/// Exposes as much of the underlying buffer that was search as possible.
pub fn (mat &SinkMatch[^b]) buffer[^b]() []u8 {
	return mat.buffer_
}

/// Returns a range that corresponds to where [`SinkMatch::bytes`] appears
/// in [`SinkMatch::buffer`].
pub fn (mat &SinkMatch[^b]) bytes_range_in_buffer[^b]() matcher.Match {
	return mat.bytes_range_in_buffer_.clone()
}

/// Returns the bytes for all matching lines, including the line
/// terminators, if they exist.
pub fn (mat &SinkMatch[^b]) bytes[^b]() []u8 {
	return mat.bytes_
}

// V-specific: exposes the active search-buffer slice for printer internals
// that consume it before the search buffer is reused.
pub fn (mat &SinkMatch[^b]) bytes_view[^b]() []u8 {
	return mat.bytes_
}

/// Returns the absolute byte offset of the start of this match. This
/// offset is absolute in that it is relative to the very beginning of the
/// input in a search, and can never be relied upon to be a valid index
/// into an in-memory slice.
pub fn (mat &SinkMatch[^b]) absolute_byte_offset[^b]() u64 {
	return mat.absolute_byte_offset_
}

/// Returns the line number of the first line in this match, if available.
///
/// Line numbers are only available when the search builder is instructed
/// to compute them.
pub fn (mat &SinkMatch[^b]) line_number[^b]() ?u64 {
	return mat.line_number_
}

/// Return an iterator over the lines in this match.
///
/// If multi line search is enabled, then this may yield more than one
/// line (but always at least one line). If multi line search is disabled,
/// then this always reports exactly one line (but may consist of just
/// the line terminator).
///
/// Lines yielded by this iterator include their terminators.
pub fn (mat &SinkMatch[^b]) lines[^b]() LineIter[^b] {
	return LineIter.new(mat.line_term_.as_byte(), mat.bytes())
}

/// An explicit iterator over lines in a particular slice of bytes.
///
/// This iterator avoids borrowing the bytes themselves, and instead requires
/// callers to explicitly provide the bytes when moving through the iterator.
/// While not idiomatic, this provides a simple way of iterating over lines
/// that doesn't require borrowing the slice itself, which can be convenient.
///
/// Line terminators are considered part of the line they terminate. All lines
/// yielded by the iterator are guaranteed to be non-empty.
pub struct LineStep implements IClone {
	line_term u8
mut:
	pos usize
	end usize
}

/// Create a new line iterator over the given range of bytes using the
/// given line terminator.
///
/// Callers should provide the actual bytes for each call to `next`. The
/// same slice must be provided to each call.
///
/// This panics if `start` is not less than or equal to `end`.
pub fn LineStep.new(line_term u8, start usize, end usize) LineStep {
	if start > end {
		panic('${start} is not <= ${end}')
	}
	return LineStep{
		line_term: line_term
		pos:       start
		end:       end
	}
}

/// Return the start and end position of the next line in the given bytes.
///
/// The caller must past exactly the same slice of bytes for each call to
/// `next`.
///
/// The range returned includes the line terminator. Ranges are always
/// non-empty.
pub fn (mut step LineStep) next(bytes []u8) ?(usize, usize) {
	if step.end > bytes.len {
		panic('line step end exceeds byte slice length')
	}
	mut i := step.pos
	for i < step.end {
		if bytes[i] == step.line_term {
			start := step.pos
			end := i + 1
			step.pos = end
			return start, end
		}
		i++
	}
	if step.pos < step.end {
		start := step.pos
		end := step.end
		step.pos = end
		return start, end
	}
	return none
}

pub fn (mut step LineStep) next_match(bytes []u8) ?matcher.Match {
	start, end := step.next(bytes) or { return none }
	return matcher.Match.new(start, end)
}

/// Count the number of occurrences of `line_term` in `bytes`.
pub fn count_lines(bytes []u8, line_term u8) u64 {
	mut count := u64(0)
	for byte in bytes {
		if byte == line_term {
			count++
		}
	}
	return count
}

/// Given a line that possibly ends with a terminator, return that line without
/// the terminator.
pub fn without_terminator(bytes []u8, line_term matcher.LineTerminator) []u8 {
	term := line_term.as_bytes()
	if bytes.len < term.len {
		return bytes.clone()
	}
	start := bytes.len - term.len
	if bytes[start..] == term {
		return bytes[..start].clone()
	}
	return bytes.clone()
}

/// Return the start and end offsets of the lines containing the given range
/// of bytes.
///
/// Line terminators are considered part of the line they terminate.
pub fn locate(bytes []u8, line_term u8, range matcher.Match) matcher.Match {
	mut line_start := usize(0)
	mut i := range.start()
	for i > 0 {
		i--
		if bytes[i] == line_term {
			line_start = i + 1
			break
		}
	}
	mut line_end := bytes.len
	if range.end() > line_start && range.end() > 0 && bytes[range.end() - 1] == line_term {
		line_end = range.end()
	} else {
		mut j := range.end()
		for j < bytes.len {
			if bytes[j] == line_term {
				line_end = j + 1
				break
			}
			j++
		}
	}
	return matcher.Match.new(line_start, line_end)
}

/// Returns the minimal starting offset of the line that occurs `count` lines
/// before the last line in `bytes`.
///
/// Lines are terminated by `line_term`. If `count` is zero, then this returns
/// the starting offset of the last line in `bytes`.
///
/// If `bytes` ends with a line terminator, then the terminator itself is
/// considered part of the last line.
pub fn preceding(bytes []u8, line_term u8, count usize) usize {
	return preceding_by_position(bytes, bytes.len, line_term, count)
}

/// Returns the minimal starting offset of the line that occurs `count` lines
/// before the line containing `pos`. Lines are terminated by `line_term`.
/// If `count` is zero, then this returns the starting offset of the line
/// containing `pos`.
///
/// If `pos` points just past a line terminator, then it is considered part of
/// the line that it terminates. For example, given `bytes = b"abc\nxyz\n"`
/// and `pos = 7`, `preceding(bytes, pos, b'\n', 0)` returns `4` (as does `pos
/// = 8`) and `preceding(bytes, pos, `b'\n', 1)` returns `0`.
fn preceding_by_position(bytes []u8, pos usize, line_term u8, count usize) usize {
	mut cur_pos := pos
	mut remaining := count
	if cur_pos == 0 {
		return 0
	} else if bytes[cur_pos - 1] == line_term {
		cur_pos--
	}
	for {
		mut found_idx := usize(0)
		mut has_found := false
		mut i := cur_pos
		for i > 0 {
			i--
			if bytes[i] == line_term {
				found_idx = i
				has_found = true
				break
			}
		}
		if !has_found {
			return 0
		}
		if remaining == 0 {
			return found_idx + 1
		} else if found_idx == 0 {
			return 0
		}
		remaining--
		cur_pos = found_idx
	}
	return 0
}

pub enum SinkContextKind {
	/// The line reported occurred before a match.
	before
	/// The line reported occurred after a match.
	after
	/// Any other type of context reported, e.g., as a result of a searcher's
	/// "passthru" mode.
	other
}

/// A type that describes a contextual line reported by a searcher.
pub struct SinkContext[^b] implements IClone {
	// V-specific: Rust only stores this under `#[cfg(test)]` for
	// `SinkContext::lines`, but translated V tests compile as normal module
	// files and still need it.
	line_term_             matcher.LineTerminator = matcher.LineTerminator.default()
	// V-specific: V slices are already borrowed descriptors, while `^b` keeps
	// the Rust lifetime relationship explicit in the type and API.
	bytes_                 []u8
	kind_                  SinkContextKind
	absolute_byte_offset_  u64
	line_number_           ?u64
}

// V-specific constructor used where Rust initializes crate-private fields.
fn SinkContext.new[^b](line_term matcher.LineTerminator, bytes []u8, kind SinkContextKind, absolute_byte_offset u64, line_number ?u64) SinkContext[^b] {
	return SinkContext[^b]{
		line_term_:            line_term
		bytes_:                bytes
		kind_:                 kind
		absolute_byte_offset_: absolute_byte_offset
		line_number_:          line_number
	}
}

/// Returns the context bytes, including line terminators.
pub fn (ctx &SinkContext[^b]) bytes[^b]() []u8 {
	return ctx.bytes_
}

/// Returns the type of context.
pub fn (ctx &^a SinkContext[^b]) kind[^a, ^b]() &^a SinkContextKind {
	return &ctx.kind_
}

/// Return an iterator over the lines in this match.
///
/// This always yields exactly one line (and that one line may contain just
/// the line terminator).
///
/// Lines yielded by this iterator include their terminators.
fn (ctx &SinkContext[^b]) lines[^b]() LineIter[^b] {
	return LineIter.new(ctx.line_term_.as_byte(), ctx.bytes())
}

/// Returns the absolute byte offset of the start of this context. This
/// offset is absolute in that it is relative to the very beginning of the
/// input in a search, and can never be relied upon to be a valid index
/// into an in-memory slice.
pub fn (ctx &SinkContext[^b]) absolute_byte_offset[^b]() u64 {
	return ctx.absolute_byte_offset_
}

/// Returns the line number of the first line in this context, if available.
///
/// Line numbers are only available when the search builder is instructed to
/// compute them.
pub fn (ctx &SinkContext[^b]) line_number[^b]() ?u64 {
	return ctx.line_number_
}

/// A trait that defines how results from searchers are handled.
///
/// In this crate, a searcher follows the "push" model. What that means is that
/// the searcher drives execution, and pushes results back to the caller. This
/// is in contrast to a "pull" model where the caller drives execution and
/// takes results as they need them. These are also known as "internal" and
/// "external" iteration strategies, respectively.
///
/// For a variety of reasons, including the complexity of the searcher
/// implementation, this crate chooses the "push" or "internal" model of
/// execution. Thus, in order to act on search results, callers must provide
/// an implementation of this trait to a searcher, and the searcher is then
/// responsible for calling the methods on this trait.
///
/// This trait defines several behaviors:
///
/// * What to do when a match is found. Callers must provide this.
/// * What to do when an error occurs. Callers must provide this via the
///   [`SinkError`] trait. Generally, callers can just use `std::io::Error` for
///   this, which already implements `SinkError`.
/// * What to do when a contextual line is found. By default, these are
///   ignored.
/// * What to do when a gap between contextual lines has been found. By
///   default, this is ignored.
/// * What to do when a search has started. By default, this does nothing.
/// * What to do when a search has finished successfully. By default, this does
///   nothing.
///
/// Callers must, at minimum, specify the behavior when an error occurs and
/// the behavior when a match occurs. The rest is optional. For each behavior,
/// callers may report an error (say, if writing the result to another
/// location failed) or simply return `false` if they want the search to stop
/// (e.g., when implementing a cap on the number of search results to show).
///
/// When errors are reported (whether in the searcher or in the implementation
/// of `Sink`), then searchers quit immediately without calling `finish`.
///
/// For simpler uses of `Sink`, callers may elect to use one of
/// the more convenient but less flexible implementations in the
/// [`sinks`] module.
///
/// The type of an error that should be reported by a searcher.
///
/// Errors of this type are not only returned by the methods on this
/// trait, but the constructors defined in `SinkError` are also used in
/// the searcher implementation itself. e.g., When a I/O error occurs when
/// reading data from a file.
///
/// V-specific: `IError` is the common result error type. Since V interfaces do
/// not provide default method bodies, implementations can embed `SinkDefaults`
/// for the optional behavior or provide equivalent methods directly.
pub interface Sink {
mut:
	/// This method is called whenever a match is found.
	///
	/// If multi line is enabled on the searcher, then the match reported here
	/// may span multiple lines and it may include multiple matches. When multi
	/// line is disabled, then the match is guaranteed to span exactly one
	/// non-empty line (where a single line is, at minimum, a line terminator).
	///
	/// If this returns `true`, then searching continues. If this returns
	/// `false`, then searching is stopped immediately and `finish` is called.
	///
	/// If this returns an error, then searching is stopped immediately,
	/// `finish` is not called and the error is bubbled back up to the caller
	/// of the searcher.
	matched[^b](searcher &Searcher, mat &SinkMatch[^b]) !bool
	/// This method is called whenever a context line is found, and is optional
	/// to implement. By default, it does nothing and returns `true`.
	///
	/// In all cases, the context given is guaranteed to span exactly one
	/// non-empty line (where a single line is, at minimum, a line terminator).
	///
	/// If this returns `true`, then searching continues. If this returns
	/// `false`, then searching is stopped immediately and `finish` is called.
	///
	/// If this returns an error, then searching is stopped immediately,
	/// `finish` is not called and the error is bubbled back up to the caller
	/// of the searcher.
	context[^b](searcher &Searcher, ctx &SinkContext[^b]) !bool
	/// This method is called whenever a break in contextual lines is found,
	/// and is optional to implement. By default, it does nothing and returns
	/// `true`.
	///
	/// A break can only occur when context reporting is enabled (that is,
	/// either or both of `before_context` or `after_context` are greater than
	/// `0`). More precisely, a break occurs between non-contiguous groups of
	/// lines.
	///
	/// If this returns `true`, then searching continues. If this returns
	/// `false`, then searching is stopped immediately and `finish` is called.
	///
	/// If this returns an error, then searching is stopped immediately,
	/// `finish` is not called and the error is bubbled back up to the caller
	/// of the searcher.
	context_break(searcher &Searcher) !bool
	/// This method is called whenever binary detection is enabled and binary
	/// data is found. If binary data is found, then this is called at least
	/// once for the first occurrence with the absolute byte offset at which
	/// the binary data begins.
	///
	/// If this returns `true`, then searching continues. If this returns
	/// `false`, then searching is stopped immediately and `finish` is called.
	///
	/// If this returns an error, then searching is stopped immediately,
	/// `finish` is not called and the error is bubbled back up to the caller
	/// of the searcher.
	///
	/// By default, it does nothing and returns `true`.
	binary_data(searcher &Searcher, binary_byte_offset u64) !bool
	/// This method is called when a search has begun, before any search is
	/// executed. By default, this does nothing.
	///
	/// If this returns `true`, then searching continues. If this returns
	/// `false`, then searching is stopped immediately and `finish` is called.
	///
	/// If this returns an error, then searching is stopped immediately,
	/// `finish` is not called and the error is bubbled back up to the caller
	/// of the searcher.
	begin(searcher &Searcher) !bool
	/// This method is called when a search has completed. By default, this
	/// does nothing.
	///
	/// If this returns an error, the error is bubbled back up to the caller of
	/// the searcher.
	finish(searcher &Searcher, finish &SinkFinish) !
}

/// Default implementations of the optional `Sink` behavior.
pub struct SinkDefaults {}

pub fn (mut sink SinkDefaults) context[^b](searcher &Searcher, ctx &SinkContext[^b]) !bool {
	_ = sink
	_ = searcher
	_ = ctx
	return true
}

pub fn (mut sink SinkDefaults) context_break(searcher &Searcher) !bool {
	_ = sink
	_ = searcher
	return true
}

pub fn (mut sink SinkDefaults) binary_data(searcher &Searcher, binary_byte_offset u64) !bool {
	_ = sink
	_ = searcher
	_ = binary_byte_offset
	return true
}

pub fn (mut sink SinkDefaults) begin(searcher &Searcher) !bool {
	_ = sink
	_ = searcher
	return true
}

pub fn (mut sink SinkDefaults) finish(searcher &Searcher, finish &SinkFinish) ! {
	_ = sink
	_ = searcher
	_ = finish
}

/// A collection of convenience implementations of `Sink`.
///
/// Each implementation in this module makes some kind of sacrifice in the name
/// of making common cases easier to use. Most frequently, each type is a
/// wrapper around a closure specified by the caller that provides limited
/// access to the full suite of information available to implementors of
/// `Sink`.
///
/// For example, the `UTF8` sink makes the following sacrifices:
///
/// * All matches must be UTF-8. An arbitrary `Sink` does not have this
///   restriction and can deal with arbitrary data. If this sink sees invalid
///   UTF-8, then an error is returned and searching stops. (Use the `Lossy`
///   sink instead to suppress this error.)
/// * The searcher must be configured to report line numbers. If it isn't,
///   an error is reported at the first match and searching stops.
/// * Context lines, context breaks and summary data reported at the end of
///   a search are all ignored.
/// * Implementors are forced to use `std::io::Error` as their error type.
///
/// If you need more flexibility, then you're advised to implement the `Sink`
/// trait directly.
///
/// V-specific: these types are in the `searcher` module because V modules are
/// directory based.
// V-specific callback aliases represent the closure types used by the Rust
// convenience sinks. V slices and strings are borrowed descriptors here.
pub type BytesSinkCallback = fn (u64, []u8) !bool

pub type StringSinkCallback = fn (u64, string) !bool

/// A sink that provides line numbers and matches as strings while ignoring
/// everything else.
///
/// This implementation will return an error if a match contains invalid
/// UTF-8 or if the searcher was not configured to count lines. Errors
/// on invalid UTF-8 can be suppressed by using the `Lossy` sink instead
/// of this one.
///
/// The closure accepts two parameters: a line number and a UTF-8 string
/// containing the matched data. The closure returns a
/// `Result<bool, std::io::Error>`. If the `bool` is `false`, then the
/// search stops immediately. Otherwise, searching continues.
///
/// If multi line mode was enabled, the line number refers to the line
/// number of the first line in the match.
pub struct UTF8 implements IClone {
	SinkDefaults
	callback StringSinkCallback
}

// V-specific constructor for the Rust tuple struct.
pub fn UTF8.new(callback StringSinkCallback) UTF8 {
	return UTF8{
		callback: callback
	}
}

pub fn (mut sink UTF8) matched[^b](searcher &Searcher, mat &SinkMatch[^b]) !bool {
	_ = searcher
	matched := mat.bytes()
	if err := first_utf8_error(matched) {
		return error(err.msg())
	}
	line_number := mat.line_number() or { return error('line numbers not enabled') }
	return sink.callback(line_number, matched.bytestr())!
}

/// A sink that provides line numbers and matches as (lossily converted)
/// strings while ignoring everything else.
///
/// This is like `UTF8`, except that if a match contains invalid UTF-8,
/// then it will be lossily converted to valid UTF-8 by substituting
/// invalid UTF-8 with Unicode replacement characters.
///
/// This implementation will return an error on the first match if the
/// searcher was not configured to count lines.
///
/// The closure accepts two parameters: a line number and a UTF-8 string
/// containing the matched data. The closure returns a
/// `Result<bool, std::io::Error>`. If the `bool` is `false`, then the
/// search stops immediately. Otherwise, searching continues.
///
/// If multi line mode was enabled, the line number refers to the line
/// number of the first line in the match.
pub struct Lossy implements IClone {
	SinkDefaults
	callback StringSinkCallback
}

// V-specific constructor for the Rust tuple struct.
pub fn Lossy.new(callback StringSinkCallback) Lossy {
	return Lossy{
		callback: callback
	}
}

pub fn (mut sink Lossy) matched[^b](searcher &Searcher, mat &SinkMatch[^b]) !bool {
	_ = searcher
	line_number := mat.line_number() or { return error('line numbers not enabled') }
	return sink.callback(line_number, lossy_utf8_string(mat.bytes()))!
}

/// A sink that provides line numbers and matches as raw bytes while
/// ignoring everything else.
///
/// This implementation will return an error on the first match if the
/// searcher was not configured to count lines.
///
/// The closure accepts two parameters: a line number and a raw byte string
/// containing the matched data. The closure returns a
/// `Result<bool, std::io::Error>`. If the `bool` is `false`, then the
/// search stops immediately. Otherwise, searching continues.
///
/// If multi line mode was enabled, the line number refers to the line
/// number of the first line in the match.
pub struct Bytes implements IClone {
	SinkDefaults
	callback BytesSinkCallback
}

// V-specific constructor for the Rust tuple struct.
pub fn Bytes.new(callback BytesSinkCallback) Bytes {
	return Bytes{
		callback: callback
	}
}

pub fn (mut sink Bytes) matched[^b](searcher &Searcher, mat &SinkMatch[^b]) !bool {
	_ = searcher
	line_number := mat.line_number() or { return error('line numbers not enabled') }
	return sink.callback(line_number, mat.bytes())!
}

fn is_valid_utf8_bytes(bytes []u8) bool {
	if bytes.len == 0 {
		return true
	}
	return validate.utf8_data(&bytes[0], bytes.len)
}

struct Utf8ErrorInfo {
	valid_up_to usize
	error_len   ?usize
}

fn (err Utf8ErrorInfo) msg() string {
	if error_len := err.error_len {
		return 'invalid utf-8 sequence of ${error_len} bytes from index ${err.valid_up_to}'
	}
	return 'incomplete utf-8 byte sequence from index ${err.valid_up_to}'
}

fn first_utf8_error(bytes []u8) ?Utf8ErrorInfo {
	mut i := usize(0)
	for i < usize(bytes.len) {
		first := bytes[i]
		if first < 0x80 {
			i++
			continue
		}
		width := utf8_sequence_width(first)
		if width == 0 {
			return Utf8ErrorInfo{
				valid_up_to: i
				error_len:   usize(1)
			}
		}
		if i + 1 >= usize(bytes.len) {
			return Utf8ErrorInfo{
				valid_up_to: i
				error_len:   none
			}
		}
		if !is_valid_utf8_second(first, bytes[i + 1]) {
			return Utf8ErrorInfo{
				valid_up_to: i
				error_len:   usize(1)
			}
		}
		if width == 2 {
			i += 2
			continue
		}
		if i + 2 >= usize(bytes.len) {
			return Utf8ErrorInfo{
				valid_up_to: i
				error_len:   none
			}
		}
		if !is_utf8_continuation(bytes[i + 2]) {
			return Utf8ErrorInfo{
				valid_up_to: i
				error_len:   usize(2)
			}
		}
		if width == 3 {
			i += 3
			continue
		}
		if i + 3 >= usize(bytes.len) {
			return Utf8ErrorInfo{
				valid_up_to: i
				error_len:   none
			}
		}
		if !is_utf8_continuation(bytes[i + 3]) {
			return Utf8ErrorInfo{
				valid_up_to: i
				error_len:   usize(3)
			}
		}
		i += 4
	}
	return none
}

fn lossy_utf8_string(bytes []u8) string {
	if is_valid_utf8_bytes(bytes) {
		return bytes.bytestr()
	}
	mut out := []u8{cap: bytes.len}
	mut start := usize(0)
	for start < usize(bytes.len) {
		err := first_utf8_error(bytes[start..]) or {
			append_bytes(mut out, bytes[start..])
			break
		}
		valid_end := start + err.valid_up_to
		append_bytes(mut out, bytes[start..valid_end])
		append_utf8(mut out, u32(0xfffd))
		error_len := err.error_len or { break }
		start = valid_end + error_len
	}
	return out.bytestr()
}

fn utf8_sequence_width(first u8) usize {
	return if first >= 0xc2 && first <= 0xdf {
		2
	} else if first >= 0xe0 && first <= 0xef {
		3
	} else if first >= 0xf0 && first <= 0xf4 {
		4
	} else {
		0
	}
}

fn is_valid_utf8_second(first u8, second u8) bool {
	return match first {
		0xe0 { second >= 0xa0 && second <= 0xbf }
		0xed { second >= 0x80 && second <= 0x9f }
		0xf0 { second >= 0x90 && second <= 0xbf }
		0xf4 { second >= 0x80 && second <= 0x8f }
		else { is_utf8_continuation(second) }
	}
}

fn is_utf8_continuation(byte u8) bool {
	return byte >= 0x80 && byte <= 0xbf
}

fn append_bytes(mut dst []u8, bytes []u8) {
	for byte in bytes {
		dst << byte
	}
}

fn matcher_ref_value(matcher_ &matcher.Matcher) matcher.Matcher {
	return *matcher_
}

fn sink_ref_value(sink &Sink) Sink {
	return *sink
}

enum FastMatchResult {
	continue_search
	stop
	switch_to_slow
}

struct Core[^s] {
	// V-specific: interfaces replace the Rust matcher's and sink's generic
	// parameters while preserving the same owned values.
	config   &^s Config
	matcher_ matcher.Matcher
	searcher &^s Searcher
mut:
	sink                Sink
	binary              bool
	pos                 usize
	absolute_byte_offset u64
	binary_byte_offset_ ?usize
	line_number         ?u64
	last_line_counted   usize
	last_line_visited   usize
	after_context_left  usize
	has_sunk            bool
	has_matched         bool
	count_              u64
}

fn Core.new[^s](searcher &^s Searcher, matcher_ matcher.Matcher, sink Sink, binary bool) Core[^s] {
	mut line_number := ?u64(none)
	if searcher.config.line_number {
		line_number = u64(1)
	}
	core := Core[^s]{
		config:      &searcher.config
		matcher_:    matcher_
		searcher:    searcher
		sink:        sink
		binary:      binary
		line_number: line_number
	}
	if !core.searcher.multi_line_with_matcher(&core.matcher_) {
		// V-specific: V's standard logger has no trace level, so Rust trace
		// records use its least verbose level, debug.
		if core.is_line_by_line_fast() {
			log.debug('searcher core: will use fast line searcher')
		} else {
			log.debug('searcher core: will use slow line searcher')
		}
	}
	return core
}

fn (core &Core[^s]) pos[^s]() usize {
	return core.pos
}

fn (mut core Core[^s]) set_pos[^s](pos usize) {
	core.pos = pos
}

fn (core &Core[^s]) count[^s]() u64 {
	return core.count_
}

fn (mut core Core[^s]) increment_count[^s]() {
	core.count_++
}

fn (core &Core[^s]) binary_byte_offset[^s]() ?u64 {
	if offset := core.binary_byte_offset_ {
		return u64(offset)
	}
	return none
}

fn (core &^a Core[^s]) matcher[^a, ^s]() &^a matcher.Matcher {
	return &core.matcher_
}

fn (mut core Core[^s]) matched[^s](buf []u8, range matcher.Match) !bool {
	return core.sink_matched(buf, range)!
}

fn (mut core Core[^s]) binary_data[^s](binary_byte_offset u64) !bool {
	return core.sink.binary_data(core.searcher, binary_byte_offset)!
}

fn (core &Core[^s]) is_match[^s](line []u8) !bool {
	// We need to strip the line terminator here to match the
	// semantics of line-by-line searching. Namely, regexes
	// like `(?m)^$` can match at the final position beyond a
	// line terminator, which is non-sensical in line oriented
	// matching.
	line_without_term := without_terminator(line, core.config.line_term)
	shortest := core.matcher_.shortest_match_at(line_without_term, 0)!
	if _ := shortest.get() {
		return true
	}
	return false
}

fn (mut core Core[^s]) find[^s](slice []u8) !matcher.FallibleMatch {
	if core.has_exceeded_match_limit() {
		return matcher.FallibleMatch.absent()
	}
	maybe_match := core.matcher().find_at(slice, 0)!
	if mat := maybe_match.get() {
		core.increment_count()
		return matcher.FallibleMatch.some(mat)
	}
	return matcher.FallibleMatch.absent()
}

fn (mut core Core[^s]) shortest_match[^s](slice []u8) !matcher.FallibleUsize {
	if core.has_exceeded_match_limit() {
		return matcher.FallibleUsize.absent()
	}
	return core.matcher_.shortest_match_at(slice, 0)!
}

fn (mut core Core[^s]) begin[^s]() !bool {
	return core.sink.begin(core.searcher)!
}

fn (mut core Core[^s]) finish[^s](byte_count u64, binary_byte_offset ?u64) ! {
	finish := SinkFinish{
		byte_count_:         byte_count
		binary_byte_offset_: binary_byte_offset
	}
	core.sink.finish(core.searcher, &finish)!
}

fn (mut core Core[^s]) match_by_line[^s](buf []u8) !bool {
	if core.is_line_by_line_fast() {
		result := core.match_by_line_fast(buf)!
		return match result {
			.switch_to_slow { core.match_by_line_slow(buf)! }
			.continue_search { true }
			.stop { false }
		}
	}
	return core.match_by_line_slow(buf)!
}

fn (mut core Core[^s]) roll[^s](buf []u8) usize {
	consumed := if core.config.max_context() == 0 {
		buf.len
	} else {
		// It might seem like all we need to care about here is just
		// the "before context," but in order to sink the context
		// separator (when before_context==0 and after_context>0), we
		// need to know something about the position of the previous
		// line visited, even if we're at the beginning of the buffer.
		//
		// ... however, we only need to find the N preceding lines based
		// on before context. We can skip this (potentially costly, for
		// large values of N) step when before_context==0.
		context_start := preceding(buf, core.config.line_term.as_byte(), core.config.before_context)
		if context_start > core.last_line_visited {
			context_start
		} else {
			core.last_line_visited
		}
	}
	core.count_lines(buf, consumed)
	core.absolute_byte_offset += u64(consumed)
	core.last_line_counted = 0
	core.last_line_visited = 0
	core.set_pos(buf.len - consumed)
	return consumed
}

fn (mut core Core[^s]) detect_binary[^s](buf []u8, range matcher.Match) !bool {
	if _ := core.binary_byte_offset_ {
		if _ := core.config.binary.quit_byte() {
			return true
		}
		return false
	}
	mut binary_byte := u8(0)
	if core.config.binary.kind == .quit || core.config.binary.kind == .convert {
		binary_byte = core.config.binary.byte
	} else {
		return false
	}
	if i := find_byte(buf[range.start()..range.end()], binary_byte) {
		offset := range.start() + i
		core.binary_byte_offset_ = offset
		if !core.binary_data(u64(offset))! {
			return true
		}
		if _ := core.config.binary.quit_byte() {
			return true
		}
	}
	return false
}

fn (mut core Core[^s]) before_context_by_line[^s](buf []u8, upto usize) !bool {
	if core.config.before_context == 0 {
		return true
	}
	range := matcher.Match.new(core.last_line_visited, upto)
	if range.is_empty() {
		return true
	}
	before_context_start := range.start() + preceding(buf[range.start()..range.end()],
		core.config.line_term.as_byte(), core.config.before_context - 1)

	context_range := matcher.Match.new(before_context_start, range.end())
	mut stepper := LineStep.new(core.config.line_term.as_byte(), context_range.start(),
		context_range.end())
	for {
		line := stepper.next_match(buf) or { break }
		if !core.sink_break_context(line.start())! {
			return false
		}
		if !core.sink_before_context(buf, line)! {
			return false
		}
	}
	return true
}

fn (mut core Core[^s]) after_context_by_line[^s](buf []u8, upto usize) !bool {
	if core.after_context_left == 0 {
		return true
	}
	exceeded_match_limit := core.has_exceeded_match_limit()
	range := matcher.Match.new(core.last_line_visited, upto)
	mut stepper := LineStep.new(core.config.line_term.as_byte(), range.start(), range.end())
	for {
		line := stepper.next_match(buf) or { break }
		if exceeded_match_limit
			&& core.is_match(buf[line.start()..line.end()])! != core.config.invert_match {
			after_context_left := core.after_context_left
			core.set_pos(line.end())
			if !core.sink_matched(buf, line)! {
				return false
			}
			core.after_context_left = after_context_left - 1
		} else if !core.sink_after_context(buf, line)! {
			return false
		}
		if core.after_context_left == 0 {
			break
		}
	}
	return true
}

fn (mut core Core[^s]) other_context_by_line[^s](buf []u8, upto usize) !bool {
	range := matcher.Match.new(core.last_line_visited, upto)
	mut stepper := LineStep.new(core.config.line_term.as_byte(), range.start(), range.end())
	for {
		line := stepper.next_match(buf) or { break }
		if !core.sink_other_context(buf, line)! {
			return false
		}
	}
	return true
}

fn (mut core Core[^s]) match_by_line_slow[^s](buf []u8) !bool {
	$if debug {
		assert !core.searcher.multi_line_with_matcher(&core.matcher_)
	}
	range := matcher.Match.new(core.pos(), buf.len)
	mut stepper := LineStep.new(core.config.line_term.as_byte(), range.start(), range.end())
	for {
		line := stepper.next_match(buf) or { break }
		if core.has_exceeded_match_limit() && !core.config.passthru && core.after_context_left == 0 {
			return false
		}
		// Stripping the line terminator is necessary to prevent some
		// classes of regexes from matching the empty position *after*
		// the end of the line. For example, `(?m)^$` will match at
		// position (2, 2) in the string `a\n`.
		slice := without_terminator(buf[line.start()..line.end()], core.config.line_term)
		mut matched := false
		if _ := core.shortest_match(slice)!.get() {
			matched = true
		}
		core.set_pos(line.end())

		success := matched != core.config.invert_match
		if success {
			core.has_matched = true
			core.increment_count()
			if !core.before_context_by_line(buf, line.start())! {
				return false
			}
			if !core.sink_matched(buf, line)! {
				return false
			}
		} else if core.after_context_left >= 1 {
			if !core.sink_after_context(buf, line)! {
				return false
			}
		} else if core.config.passthru {
			if !core.sink_other_context(buf, line)! {
				return false
			}
		}
		if core.config.stop_on_nonmatch && !success && core.has_matched {
			return false
		}
	}
	return true
}

fn (mut core Core[^s]) match_by_line_fast[^s](buf []u8) !FastMatchResult {
	$if debug {
		assert !core.config.passthru
	}
	for core.pos() < buf.len {
		if core.config.stop_on_nonmatch && core.has_matched {
			return .switch_to_slow
		}
		if core.config.invert_match {
			if !core.match_by_line_fast_invert(buf)! {
				break
			}
		} else {
			maybe_line := core.find_by_line_fast(buf)!
			if line := maybe_line.get() {
				core.has_matched = true
				core.increment_count()
				if core.config.max_context() > 0 {
					if !core.after_context_by_line(buf, line.start())! {
						return .stop
					}
					if !core.before_context_by_line(buf, line.start())! {
						return .stop
					}
				}
				core.set_pos(line.end())
				if !core.sink_matched(buf, line)! {
					return .stop
				}
			} else {
				break
			}
		}
	}
	if !core.after_context_by_line(buf, buf.len)! {
		return .stop
	}
	if core.has_exceeded_match_limit() && core.after_context_left == 0 {
		return .stop
	}
	core.set_pos(buf.len)
	return .continue_search
}

@[inline]
fn (mut core Core[^s]) match_by_line_fast_invert[^s](buf []u8) !bool {
	assert core.config.invert_match

	maybe_line := core.find_by_line_fast(buf)!
	invert_match := if line := maybe_line.get() {
		range := matcher.Match.new(core.pos(), line.start())
		core.set_pos(line.end())
		range
	} else {
		range := matcher.Match.new(core.pos(), buf.len)
		core.set_pos(range.end())
		range
	}
	if invert_match.is_empty() {
		return true
	}
	core.has_matched = true
	if !core.after_context_by_line(buf, invert_match.start())! {
		return false
	}
	if !core.before_context_by_line(buf, invert_match.start())! {
		return false
	}
	mut stepper := LineStep.new(core.config.line_term.as_byte(), invert_match.start(), invert_match.end())
	for {
		line := stepper.next_match(buf) or { break }
		core.increment_count()
		if !core.sink_matched(buf, line)! {
			return false
		}
		if core.has_exceeded_match_limit() {
			return false
		}
	}
	return true
}

@[inline]
fn (mut core Core[^s]) find_by_line_fast[^s](buf []u8) !matcher.FallibleMatch {
	$if debug {
		assert !core.searcher.multi_line_with_matcher(&core.matcher_)
		assert core.is_line_by_line_fast()
	}
	mut pos := core.pos()
	for pos < buf.len {
		if core.has_exceeded_match_limit() {
			return matcher.FallibleMatch.absent()
		}
		maybe_kind := core.matcher_.find_candidate_line(buf[pos..])!
		kind := maybe_kind.get() or {
			return matcher.FallibleMatch.absent()
		}
		if kind.is_confirmed() {
			line := locate(buf, core.config.line_term.as_byte(), matcher.Match.zero(kind.position()).offset(pos))
			// If we matched beyond the end of the buffer, then we
			// don't report this as a match.
			if line.start() == buf.len {
				pos = buf.len
				continue
			}
			return matcher.FallibleMatch.some(line)
		}
		line := locate(buf, core.config.line_term.as_byte(), matcher.Match.zero(kind.position()).offset(pos))
		if core.is_match(buf[line.start()..line.end()])! {
			return matcher.FallibleMatch.some(line)
		}
		pos = line.end()
	}
	return matcher.FallibleMatch.absent()
}

@[inline]
fn (mut core Core[^s]) sink_matched[^s](buf []u8, range matcher.Match) !bool {
	if core.binary && core.detect_binary(buf, range)! {
		return false
	}
	if !core.sink_break_context(range.start())! {
		return false
	}
	core.count_lines(buf, range.start())
	offset := core.absolute_byte_offset + u64(range.start())
	mut mat := SinkMatch.new(buf, range)
	mat = mat.with_line_term(core.config.line_term)
	mat = mat.with_absolute_byte_offset(offset)
	mat = mat.with_line_number(core.line_number)
	keepgoing := core.sink.matched(core.searcher, &mat)!
	if !keepgoing {
		return false
	}
	core.last_line_visited = range.end()
	core.after_context_left = core.config.after_context
	core.has_sunk = true
	return true
}

fn (mut core Core[^s]) sink_before_context[^s](buf []u8, range matcher.Match) !bool {
	if core.binary && core.detect_binary(buf, range)! {
		return false
	}
	core.count_lines(buf, range.start())
	offset := core.absolute_byte_offset + u64(range.start())
	ctx := SinkContext.new(core.config.line_term, buf[range.start()..range.end()],
		.before, offset, core.line_number)
	keepgoing := core.sink.context(core.searcher, &ctx)!
	if !keepgoing {
		return false
	}
	core.last_line_visited = range.end()
	core.has_sunk = true
	return true
}

fn (mut core Core[^s]) sink_after_context[^s](buf []u8, range matcher.Match) !bool {
	assert core.after_context_left >= 1

	if core.binary && core.detect_binary(buf, range)! {
		return false
	}
	core.count_lines(buf, range.start())
	offset := core.absolute_byte_offset + u64(range.start())
	ctx := SinkContext.new(core.config.line_term, buf[range.start()..range.end()],
		.after, offset, core.line_number)
	keepgoing := core.sink.context(core.searcher, &ctx)!
	if !keepgoing {
		return false
	}
	core.last_line_visited = range.end()
	core.after_context_left--
	core.has_sunk = true
	return true
}

fn (mut core Core[^s]) sink_other_context[^s](buf []u8, range matcher.Match) !bool {
	if core.binary && core.detect_binary(buf, range)! {
		return false
	}
	core.count_lines(buf, range.start())
	offset := core.absolute_byte_offset + u64(range.start())
	ctx := SinkContext.new(core.config.line_term, buf[range.start()..range.end()],
		.other, offset, core.line_number)
	keepgoing := core.sink.context(core.searcher, &ctx)!
	if !keepgoing {
		return false
	}
	core.last_line_visited = range.end()
	core.has_sunk = true
	return true
}

fn (mut core Core[^s]) sink_break_context[^s](start_of_line usize) !bool {
	is_gap := core.last_line_visited < start_of_line
	any_context := core.config.before_context > 0 || core.config.after_context > 0

	if !any_context || !core.has_sunk || !is_gap {
		return true
	}
	return core.sink.context_break(core.searcher)!
}

fn (mut core Core[^s]) count_lines[^s](buf []u8, upto usize) {
	if line_number := core.line_number {
		if core.last_line_counted >= upto {
			return
		}
		slice := buf[core.last_line_counted..upto]
		count := count_lines(slice, core.config.line_term.as_byte())
		core.line_number = line_number + count
		core.last_line_counted = upto
	}
}

fn (core &Core[^s]) is_line_by_line_fast[^s]() bool {
	$if debug {
		assert !core.searcher.multi_line_with_matcher(&core.matcher_)
	}
	if core.config.passthru {
		return false
	}
	if core.config.stop_on_nonmatch && core.has_matched {
		return false
	}
	if line_term := core.matcher_.line_terminator() {
		// FIXME: This works around a bug in grep-regex where it does
		// not set the line terminator of the regex itself, and thus
		// line anchors like `(?m:^)` and `(?m:$)` will not match
		// anything except for `\n`. So for now, we just disable the fast
		// line-by-line searcher which requires the regex to be able to
		// deal with line terminators correctly. The slow line-by-line
		// searcher strips line terminators and thus absolves the regex
		// engine from needing to care about whether they are `\n` or NUL.
		if line_term.as_byte() == `\x00` {
			return false
		}
		if line_term == core.config.line_term {
			return true
		}
	}
	if non_matching := core.matcher_.non_matching_bytes() {
		// If the line terminator is CRLF, we don't actually need to care
		// whether the regex can match `\r` or not. Namely, a `\r` is
		// neither necessary nor sufficient to terminate a line. A `\n` is
		// always required.
		if matcher.byte_set_contains(non_matching, core.config.line_term.as_byte()) {
			return true
		}
	}
	return false
}

fn (core &Core[^s]) has_exceeded_match_limit[^s]() bool {
	if limit := core.config.max_matches {
		return core.count() >= limit
	}
	return false
}

struct ReadByLine[^s, ^r, ^b] {
	config &^s Config
mut:
	core Core[^s]
	rdr  LineBufferReader[^r, ^b]
}

fn ReadByLine.new[^s, ^r, ^b](searcher &^s Searcher, matcher_ matcher.Matcher, read_from LineBufferReader[^r, ^b], write_to Sink) ReadByLine[^s, ^r, ^b] {
	$if debug {
		assert !searcher.multi_line_with_matcher(&matcher_)
	}
	return ReadByLine[^s, ^r, ^b]{
		config: &searcher.config
		core:   Core.new(searcher, matcher_, write_to, false)
		rdr:    read_from
	}
}

fn (mut search ReadByLine[^s, ^r, ^b]) run[^s, ^r, ^b]() ! {
	if search.core.begin()! {
		for search.fill()! {
			if !search.core.match_by_line(search.rdr.buffer())! {
				search.consume_remaining()
				break
			}
		}
	}
	search.core.finish(search.rdr.absolute_byte_offset(), search.rdr.binary_byte_offset())!
}

fn (mut search ReadByLine[^s, ^r, ^b]) consume_remaining[^s, ^r, ^b]() {
	consumed := search.core.pos()
	search.rdr.consume(consumed)
}

fn (mut search ReadByLine[^s, ^r, ^b]) fill[^s, ^r, ^b]() !bool {
	assert search.rdr.buffer()[search.core.pos()..].len == 0

	already_binary := search.rdr.binary_byte_offset() != none
	old_buf_len := search.rdr.buffer().len
	consumed := search.core.roll(search.rdr.buffer())
	search.rdr.consume(consumed)
	didread := search.rdr.fill()!
	if !already_binary {
		if offset := search.rdr.binary_byte_offset() {
			if !search.core.binary_data(offset)! {
				return false
			}
		}
	}
	if !didread || search.should_binary_quit() {
		return false
	}
	// If rolling the buffer didn't result in consuming anything and if
	// re-filling the buffer didn't add any bytes, then the only thing in
	// our buffer is leftover context, which we no longer need since there
	// is nothing left to search. So forcefully quit.
	if consumed == 0 && old_buf_len == search.rdr.buffer().len {
		search.rdr.consume(old_buf_len)
		return false
	}
	return true
}

fn (search ReadByLine[^s, ^r, ^b]) should_binary_quit[^s, ^r, ^b]() bool {
	return search.rdr.binary_byte_offset() != none && search.config.binary.quit_byte() != none
}

struct SliceByLine[^s] {
	slice &^s []u8
mut:
	core Core[^s]
}

fn SliceByLine.new[^s](searcher &^s Searcher, matcher_ matcher.Matcher, slice &^s []u8, write_to Sink) SliceByLine[^s] {
	$if debug {
		assert !searcher.multi_line_with_matcher(&matcher_)
	}
	return SliceByLine[^s]{
		core:  Core.new(searcher, matcher_, write_to, true)
		slice: slice
	}
}

fn (mut search SliceByLine[^s]) run[^s]() ! {
	if search.core.begin()! {
		binary_upto := if search.slice.len < int(default_buffer_capacity) {
			search.slice.len
		} else {
			int(default_buffer_capacity)
		}
		binary_range := matcher.Match.new(0, usize(binary_upto))
		if !search.core.detect_binary(search.slice, binary_range)! {
			for search.core.pos() < search.slice.len && search.core.match_by_line(search.slice)! {}
		}
	}
	byte_count := search.byte_count()
	binary_byte_offset := search.core.binary_byte_offset()
	search.core.finish(byte_count, binary_byte_offset)!
}

fn (mut search SliceByLine[^s]) byte_count[^s]() u64 {
	if offset := search.core.binary_byte_offset() {
		if offset < u64(search.core.pos()) {
			return offset
		}
	}
	return u64(search.core.pos())
}

struct MultiLine[^s] {
	config &^s Config
	slice  &^s []u8
mut:
	core       Core[^s]
	last_match ?matcher.Match
}

fn MultiLine.new[^s](searcher &^s Searcher, matcher_ matcher.Matcher, slice &^s []u8, write_to Sink) MultiLine[^s] {
	$if debug {
		assert searcher.multi_line_with_matcher(&matcher_)
	}
	return MultiLine[^s]{
		config: &searcher.config
		core:   Core.new(searcher, matcher_, write_to, true)
		slice:  slice
	}
}

fn (mut search MultiLine[^s]) run[^s]() ! {
	if search.core.begin()! {
		binary_upto := if search.slice.len < int(default_buffer_capacity) {
			search.slice.len
		} else {
			int(default_buffer_capacity)
		}
		binary_range := matcher.Match.new(0, usize(binary_upto))
		if !search.core.detect_binary(search.slice, binary_range)! {
			mut keepgoing := true
			for search.core.pos() < search.slice.len && keepgoing {
				keepgoing = search.sink()!
			}
			if keepgoing {
				if last_match := search.last_match {
					if search.sink_context(last_match)! {
						search.sink_matched(last_match)!
					}
					search.last_match = none
				}
			}
			// Take care of any remaining context after the last match.
			if keepgoing {
				if search.config.passthru {
					search.core.other_context_by_line(search.slice, search.slice.len)!
				} else {
					search.core.after_context_by_line(search.slice, search.slice.len)!
				}
			}
		}
	}
	byte_count := search.byte_count()
	binary_byte_offset := search.core.binary_byte_offset()
	search.core.finish(byte_count, binary_byte_offset)!
}

fn (mut search MultiLine[^s]) sink[^s]() !bool {
	if search.config.invert_match {
		return search.sink_matched_inverted()!
	}
	maybe_mat := search.find()!
	mat := maybe_mat.get() or {
		search.core.set_pos(search.slice.len)
		return true
	}
	search.advance(mat)

	line := locate(search.slice, search.config.line_term.as_byte(), mat)
	// We delay sinking the match to make sure we group adjacent matches
	// together in a single sink. Adjacent matches are distinct matches
	// that start and end on the same line, respectively. This guarantees
	// that a single line is never sinked more than once.
	if last_match := search.last_match {
		// If the lines in the previous match overlap with the lines
		// in this match, then simply grow the match and move on. This
		// happens when the next match begins on the same line that the
		// last match ends on.
		//
		// Note that we do not technically require strict overlap here.
		// Instead, we only require that the lines are adjacent. This
		// provides larger blocks of lines to the printer, and results
		// in overall better behavior with respect to how replacements
		// are handled.
		//
		// See: https://github.com/BurntSushi/ripgrep/issues/1311
		// And also the associated commit fixing #1311.
		if last_match.end() >= line.start() {
			search.last_match = last_match.with_end(line.end())
			return true
		}
		search.last_match = line
		if !search.sink_context(last_match)! {
			return false
		}
		return search.sink_matched(last_match)!
	}
	search.last_match = line
	return true
}

fn (mut search MultiLine[^s]) sink_matched_inverted[^s]() !bool {
	assert search.config.invert_match

	maybe_mat := search.find()!
	invert_match := if mat := maybe_mat.get() {
		line := locate(search.slice, search.config.line_term.as_byte(), mat)
		range := matcher.Match.new(search.core.pos(), line.start())
		search.advance(line)
		range
	} else {
		range := matcher.Match.new(search.core.pos(), search.slice.len)
		search.core.set_pos(range.end())
		range
	}
	if invert_match.is_empty() {
		return true
	}
	if !search.sink_context(invert_match)! {
		return false
	}
	mut stepper := LineStep.new(search.config.line_term.as_byte(), invert_match.start(), invert_match.end())
	for {
		line := stepper.next_match(search.slice) or { break }
		if !search.sink_matched(line)! {
			return false
		}
	}
	return true
}

fn (mut search MultiLine[^s]) sink_matched[^s](range matcher.Match) !bool {
	if range.is_empty() {
		// The only way we can produce an empty line for a match is if we
		// match the position immediately following the last byte that we
		// search, and where that last byte is also the line terminator. We
		// never want to report that match, and we know we're done at that
		// point anyway, so stop the search.
		return false
	}
	return search.core.matched(search.slice, range)!
}

fn (mut search MultiLine[^s]) sink_context[^s](range matcher.Match) !bool {
	if search.config.passthru {
		if !search.core.other_context_by_line(search.slice, range.start())! {
			return false
		}
	} else {
		if !search.core.after_context_by_line(search.slice, range.start())! {
			return false
		}
		if !search.core.before_context_by_line(search.slice, range.start())! {
			return false
		}
	}
	return true
}

fn (mut search MultiLine[^s]) find[^s]() !matcher.FallibleMatch {
	maybe_match := search.core.find(search.slice[search.core.pos()..])!
	if mat := maybe_match.get() {
		return matcher.FallibleMatch.some(mat.offset(search.core.pos()))
	}
	return matcher.FallibleMatch.absent()
}

/// Advance the search position based on the previous match.
///
/// If the previous match is zero width, then this advances the search
/// position one byte past the end of the match.
fn (mut search MultiLine[^s]) advance[^s](range matcher.Match) {
	search.core.set_pos(range.end())
	if range.is_empty() && search.core.pos() < search.slice.len {
		newpos := search.core.pos() + 1
		search.core.set_pos(newpos)
	}
}

fn (mut search MultiLine[^s]) byte_count[^s]() u64 {
	if offset := search.core.binary_byte_offset() {
		if offset < u64(search.core.pos()) {
			return offset
		}
	}
	return u64(search.core.pos())
}

/// Returns true if and only if the given slice begins with a UTF-8 or UTF-16
/// BOM.
///
/// This is used by the searcher to determine if a transcoder is necessary.
/// Otherwise, it is advantageous to search the slice directly.
fn slice_has_bom(slice []u8) bool {
	return slice_has_utf8_bom(slice) || slice_has_utf16le_bom(slice) || slice_has_utf16be_bom(slice)
}

fn slice_has_utf8_bom(slice []u8) bool {
	return slice.len >= 3 && slice[0] == 0xef && slice[1] == 0xbb && slice[2] == 0xbf
}

fn slice_has_utf16le_bom(slice []u8) bool {
	return slice.len >= 2 && slice[0] == 0xff && slice[1] == 0xfe
}

fn slice_has_utf16be_bom(slice []u8) bool {
	return slice.len >= 2 && slice[0] == 0xfe && slice[1] == 0xff
}
