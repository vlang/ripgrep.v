module flags

import core
import os

/// The result of parsing CLI arguments.
///
/// This is basically a `Result<T>`, but with one extra variant that is
/// inhabited whenever ripgrep should execute a "special" mode. That is, when a
/// user provides the `-h/--help` or `-V/--version` flags.
///
/// This special variant exists to allow CLI parsing to short circuit as
/// quickly as is reasonable. For example, it lets CLI parsing avoid reading
/// ripgrep's configuration and converting low level arguments into a higher
/// level representation.
// V-specific: generic enum variants cannot carry the three different payloads,
// so the Rust enum is represented by a tag and payload fields.
pub enum ParseResultKind {
	special
	ok
	err
}

// V-specific: these fields are public because the `rg` module consumes the
// crate-internal parse result.
pub struct ParseResult[T] {
pub:
	kind    ParseResultKind
	special SpecialMode
	value   T
	err     string
}

// V-specific constructor for the tagged `Special` representation.
pub fn parse_result_special[T](mode SpecialMode) ParseResult[T] {
	return ParseResult[T]{
		kind:    .special
		special: mode
	}
}

// V-specific constructor for the tagged `Ok` representation.
pub fn parse_result_ok[T](value T) ParseResult[T] {
	return ParseResult[T]{
		kind:  .ok
		value: value
	}
}

// V-specific constructor for the tagged `Err` representation.
pub fn parse_result_err[T](err string) ParseResult[T] {
	return ParseResult[T]{
		kind: .err
		err:  err.to_owned()
	}
}

/// Parse CLI arguments and convert then to their high level representation.
pub fn parse() ParseResult[HiArgs] {
	rawargs := raw_os_args()
	return parse_from_raw(rawargs)
}

// V-specific argument-taking form of `parse`, used by translated tests.
fn parse_from_raw(rawargs []string) ParseResult[HiArgs] {
	low_result := parse_low_from_raw(rawargs)
	match low_result.kind {
		.special {
			return parse_result_special[HiArgs](low_result.special)
		}
		.err {
			return parse_result_err[HiArgs](low_result.err)
		}
		.ok {
			mut low := low_result.value
			hi := HiArgs.from_low_args(mut low) or { return parse_result_err[HiArgs](err.msg()) }
			return parse_result_ok[HiArgs](hi)
		}
	}
}

/// Parse CLI arguments only into their low level representation.
///
/// This takes configuration into account. That is, it will try to read
/// `RIPGREP_CONFIG_PATH` and prepend any arguments found there to the
/// arguments passed to this process.
///
/// This will also set one-time global state flags, such as the log level and
/// whether messages should be printed.
fn parse_low() ParseResult[LowArgs] {
	rawargs := raw_os_args()
	return parse_low_from_raw(rawargs)
}

// V-specific bridge from V's process argument array to the consuming parser.
fn raw_os_args() []string {
	mut rawargs := []string{cap: if os.args.len > 1 { os.args.len - 1 } else { 0 }}
	for i in 1 .. os.args.len {
		rawargs << os.args[i].to_owned()
	}
	return rawargs
}

// V-specific argument-taking form of `parse_low`, used to share the original
// parsing flow with translated tests.
fn parse_low_from_raw(rawargs []string) ParseResult[LowArgs] {
	core.Logger.init() or {
		return parse_result_err[LowArgs]('failed to initialize logger: ${err.msg()}')
	}

	mut low := parse_low_raw(rawargs) or { return parse_result_err[LowArgs](err.msg()) }
	set_log_levels(&low)
	if special := low.special {
		low.special = none
		return parse_result_special[LowArgs](special)
	}
	if low.no_config {
		core.debug_message('rg::flags::parse',
			'not reading config files because --no-config is present')
		return parse_result_ok[LowArgs](low)
	}

	config := config_args()
	if config.len == 0 {
		core.debug_message('rg::flags::parse', 'no extra arguments found from configuration file')
		return parse_result_ok[LowArgs](low)
	}
	mut final_args := config.clone()
	for arg in rawargs {
		final_args << arg.to_owned()
	}
	mut reparsed := parse_low_raw(final_args) or { return parse_result_err[LowArgs](err.msg()) }
	set_log_levels(&reparsed)
	return parse_result_ok[LowArgs](reparsed)
}

/// Sets global state flags that control logging based on low-level arguments.
fn set_log_levels(low &LowArgs) {
	core.set_messages(!low.no_messages)
	core.set_ignore_messages(!low.no_ignore_messages)
	logging := low.logging or {
		core.set_log_level(.off)
		return
	}

	match logging {
		.debug { core.set_log_level(.debug) }
		.trace { core.set_log_level(.trace) }
	}
}

/// Possibly return a message suggesting flags similar in the name to the one
/// given.
///
/// The one given should be a flag given by the user (without the leading
/// dashes) that was unrecognized. This attempts to find existing flags that
/// are similar to the one given.
fn suggest(unrecognized &string) ?string {
	similars := find_similar_names(unrecognized)
	if similars.len == 0 {
		return none
	}
	mut names := []string{cap: similars.len}
	for name in similars {
		names << '--${name}'
	}
	return 'similar flags that are available: ${names.join(', ')}'
}

/// Return a sequence of names similar to the unrecognized name given.
fn find_similar_names(unrecognized &string) []string {
	// The jaccard similarity threshold at which we consider two flag names
	// similar enough that it's worth suggesting it to the end user.
	//
	// This value was determined by some ad hoc experimentation. It might need
	// further tweaking.
	threshold := 0.4

	mut similar := []string{}
	bow_given := ngrams(unrecognized)
	for flag in flag_defs {
		name := flag.name_long()
		bow := ngrams(&name)
		if jaccard_index(bow_given, bow) >= threshold {
			similar << name
		}
		if negated := flag.name_negated() {
			negated_bow := ngrams(&negated)
			if jaccard_index(bow_given, negated_bow) >= threshold {
				similar << negated
			}
		}
		for alias in flag.aliases() {
			alias_bow := ngrams(&alias)
			if jaccard_index(bow_given, alias_bow) >= threshold {
				similar << alias
			}
		}
	}
	return similar
}

/// A "bag of words" is a set of ngrams.
type BagOfWords[^a] = []Ngram[^a]

// V-specific: this represents Rust's `Cow<'a, [u8]>` without copying borrowed
// three-byte windows. Padding bytes are read virtually past the source end.
struct Ngram[^a] implements IClone {
	source &^a string
	start  int
}

fn ngram_byte[^a](ngram &Ngram[^a], offset int) u8 {
	index := ngram.start + offset
	if index < ngram.source.len {
		return (*ngram.source)[index]
	}
	return `!`
}

fn ngram_compare[^a, ^b](left &Ngram[^a], right &Ngram[^b]) int {
	for offset in 0 .. 3 {
		left_byte := ngram_byte(left, offset)
		right_byte := ngram_byte(right, offset)
		if left_byte < right_byte {
			return -1
		}
		if left_byte > right_byte {
			return 1
		}
	}
	return 0
}

fn ngram_in[^a, ^b](needle &Ngram[^a], haystack BagOfWords[^b]) bool {
	for candidate in haystack {
		if ngram_compare(needle, &candidate) == 0 {
			return true
		}
	}
	return false
}

/// Returns the jaccard index (a measure of similarity) between sets of ngrams.
fn jaccard_index[^a, ^b](ngrams1 BagOfWords[^a], ngrams2 BagOfWords[^b]) f64 {
	mut union_count := ngrams1.len
	mut intersection := 0
	for ngram in ngrams2 {
		if ngram_in(&ngram, ngrams1) {
			intersection++
		} else {
			union_count++
		}
	}
	if union_count == 0 {
		return 0.0
	}
	return f64(intersection) / f64(union_count)
}

/// Returns all 3-grams in the slice given.
///
/// If the slice doesn't contain a 3-gram, then one is artificially created by
/// padding it out with a character that will never appear in a flag name.
fn ngrams[^a](flag_name &^a string) BagOfWords[^a] {
	// We only allow ASCII flag names, so we can just use bytes.
	count := if flag_name.len < 3 { 1 } else { flag_name.len - 2 }
	mut out := BagOfWords[^a]{}
	for start in 0 .. count {
		candidate := Ngram[^a]{
			source: flag_name
			start:  start
		}
		mut duplicate := false
		mut insert_at := out.len
		for i, existing in out {
			ordering := ngram_compare(&candidate, &existing)
			if ordering == 0 {
				duplicate = true
				break
			}
			if ordering < 0 {
				insert_at = i
				break
			}
		}
		if !duplicate {
			out.insert(insert_at, candidate)
		}
	}
	return out
}
