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
pub enum ParseResultKind {
	special
	ok
	err
}

pub struct ParseResult[T] {
pub:
	kind    ParseResultKind
	special SpecialMode
	value   T
	err     string
}

pub fn parse_result_special[T](mode SpecialMode) ParseResult[T] {
	return ParseResult[T]{
		kind:    .special
		special: mode
	}
}

pub fn parse_result_ok[T](value T) ParseResult[T] {
	return ParseResult[T]{
		kind:  .ok
		value: value
	}
}

pub fn parse_result_err[T](err string) ParseResult[T] {
	return ParseResult[T]{
		kind: .err
		err:  err.to_owned()
	}
}

/// Parse CLI arguments and convert then to their high level representation.
pub fn parse() ParseResult[HiArgs] {
	rawargs := if os.args.len > 1 { os.args[1..].clone() } else { []string{} }
	return parse_from_raw(rawargs)
}

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
	rawargs := if os.args.len > 1 { os.args[1..].clone() } else { []string{} }
	return parse_low_from_raw(rawargs)
}

fn parse_low_from_raw(rawargs []string) ParseResult[LowArgs] {
	core.Logger.init() or {
		return parse_result_err[LowArgs]('failed to initialize logger: ${err.msg()}')
	}

	mut low := parse_low_raw(rawargs) or { return parse_result_err[LowArgs](err.msg()) }
	set_log_levels(low)
	if special := low.special {
		low.special = none
		return parse_result_special[LowArgs](special)
	}
	if low.no_config {
		return parse_result_ok[LowArgs](low)
	}

	config := config_args()
	if config.len == 0 {
		return parse_result_ok[LowArgs](low)
	}
	mut final_args := config.clone()
	for arg in rawargs {
		final_args << arg.to_owned()
	}
	mut reparsed := parse_low_raw(final_args) or { return parse_result_err[LowArgs](err.msg()) }
	set_log_levels(reparsed)
	return parse_result_ok[LowArgs](reparsed)
}

/// Sets global state flags that control logging based on low-level arguments.
fn set_log_levels(low LowArgs) {
	core.set_messages(!low.no_messages)
	core.set_ignore_messages(!low.no_ignore_messages)
	// V-specific: the translated logger does not expose global level filtering
	// yet, so `--debug` and `--trace` are parsed but do not change a global
	// log max-level here.
	_ = low.has_logging
	_ = low.logging
}

/// Possibly return a message suggesting flags similar in the name to the one
/// given.
///
/// The one given should be a flag given by the user (without the leading
/// dashes) that was unrecognized. This attempts to find existing flags that
/// are similar to the one given.
fn suggest(unrecognized string) ?string {
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
fn find_similar_names(unrecognized string) []string {
	// The jaccard similarity threshold at which we consider two flag names
	// similar enough that it's worth suggesting it to the end user.
	//
	// This value was determined by some ad hoc experimentation. It might need
	// further tweaking.
	threshold := 0.4

	mut similar := []string{}
	bow_given := ngrams(unrecognized)
	for flag in flags {
		name := flag.name_long()
		bow := ngrams(name)
		if jaccard_index(bow_given, bow) >= threshold {
			similar << name
		}
		if negated := flag.name_negated() {
			negated_bow := ngrams(negated)
			if jaccard_index(bow_given, negated_bow) >= threshold {
				similar << negated
			}
		}
		for alias in flag.aliases() {
			alias_bow := ngrams(alias)
			if jaccard_index(bow_given, alias_bow) >= threshold {
				similar << alias
			}
		}
	}
	return similar
}

/// A "bag of words" is a set of ngrams.
type BagOfWords = []string

/// Returns the jaccard index (a measure of similarity) between sets of ngrams.
fn jaccard_index(ngrams1 BagOfWords, ngrams2 BagOfWords) f64 {
	mut union_set := map[string]bool{}
	for ngram in ngrams1 {
		union_set[ngram] = true
	}
	for ngram in ngrams2 {
		union_set[ngram] = true
	}
	mut intersection := 0
	for ngram in ngrams1 {
		if ngram in ngrams2 {
			intersection++
		}
	}
	if union_set.len == 0 {
		return 0.0
	}
	return f64(intersection) / f64(union_set.len)
}

/// Returns all 3-grams in the slice given.
///
/// If the slice doesn't contain a 3-gram, then one is artificially created by
/// padding it out with a character that will never appear in a flag name.
fn ngrams(flag_name string) BagOfWords {
	// We only allow ASCII flag names, so we can just use bytes.
	if flag_name.len == 0 {
		return ['!!!']
	}
	if flag_name.len == 1 {
		return ['${flag_name[0].ascii_str()}!!']
	}
	if flag_name.len == 2 {
		return ['${flag_name[0].ascii_str()}${flag_name[1].ascii_str()}!']
	}
	mut seen := map[string]bool{}
	mut out := []string{}
	for i in 0 .. flag_name.len - 2 {
		ngram := flag_name[i..i + 3]
		if ngram !in seen {
			seen[ngram] = true
			out << ngram
		}
	}
	return out
}
