module regex

import log
import regex.meta

// V-specific: V's standard logger has no trace level, so source trace
// diagnostics use its debug level.
fn literal_trace(message string) {
	log.debug(message)
}

/// A type that encapsulates "inner" literal extractiong from a regex.
///
/// It uses a huge pile of heuristics to try to pluck out literals from a regex
/// that are in turn used to build a simpler regex that is more amenable to
/// optimization.
///
/// The main idea underlying the validity of this technique is the fact
/// that ripgrep searches individuals lines and not across lines. (Unless
/// -U/--multiline is enabled.) Namely, we can pluck literals out of the regex,
/// search for them, find the bounds of the line in which that literal occurs
/// and then run the original regex on only that line. This overall works
/// really really well in throughput oriented searches because it potentially
/// allows ripgrep to spend a lot more time in a fast vectorized routine for
/// finding literals as opposed to the (much) slower regex engine.
///
/// This optimization was far more important in the old days, but since then,
/// Rust's regex engine has actually grown its own (albeit limited) support for
/// inner literal optimizations. So this technique doesn't apply as much as it
/// used to.
///
/// A good example of a regex where this particular extractor helps is
/// `\s+(Sherlock|[A-Z]atso[a-z]|Moriarty)\s+`. The `[A-Z]` before the `atso`
/// in particular is what inhibits the regex engine's own inner literal
/// optimizations from kicking in. This particular regex also did not have any
/// inner literals extracted in the old implementation (ripgrep <=13). So this
/// particular implementation represents a strict improvement from both the old
/// implementation and from the regex engine's own optimizations. (Which could
/// in theory be improved still.)
struct InnerLiterals implements IClone {
	seq Seq
}

/// Create a set of inner literals from the given HIR expression.
///
/// If no line terminator was configured, then this always declines to
/// extract literals because the inner literal optimization may not be
/// valid.
///
/// Note that this requires the actual regex that will be used for a search
/// because it will query some state about the compiled regex. That state
/// may influence inner literal extraction.
fn InnerLiterals.new(chir &ConfiguredHIR, re &meta.Regex) InnerLiterals {
	// If there's no line terminator, then the inner literal optimization
	// at this level is not valid.
	if _ := chir.config().line_terminator {
	} else {
		literal_trace('skipping inner literal extraction, no line terminator is set')
		return InnerLiterals.none()
	}
	// If we believe the regex is already accelerated, then just let
	// the regex engine do its thing. We'll skip the inner literal
	// optimization.
	//
	// ... but only if the regex doesn't have any Unicode word boundaries.
	// If it does, there's enough of a chance of the regex engine falling
	// back to a slower engine that it's worth trying our own inner literal
	// optimization.
	if re.is_accelerated() {
		if !re.contains_word_unicode() {
			literal_trace('skipping inner literal extraction, existing regex is believed to already be accelerated')
			return InnerLiterals.none()
		}
	}
	// In this case, we pretty much know that the regex engine will handle
	// it as best as possible, even if it isn't reported as accelerated.
	if chir.hir().is_alternation_literal() {
		literal_trace('skipping inner literal extraction, found alternation of literals, deferring to regex engine')
		return InnerLiterals.none()
	}
	seq := Extractor.new().extract_untagged(chir.hir())
	return InnerLiterals{
		seq: seq
	}
}

/// Returns a infinite set of inner literals, such that it can never
/// produce a matcher.
fn InnerLiterals.none() InnerLiterals {
	return InnerLiterals{
		seq: Seq.infinite()
	}
}

/// If it is deemed advantageous to do so (via various suspicious
/// heuristics), this will return a single regular expression pattern that
/// matches a subset of the language matched by the regular expression that
/// generated these literal sets. The idea here is that the pattern
/// returned by this method is much cheaper to search for. i.e., It is
/// usually a single literal or an alternation of literals.
fn (lits &InnerLiterals) one_regex() !MaybeRegex {
	literals := lits.seq.literals() or { return MaybeRegex.none() }
	if literals.len == 0 {
		return MaybeRegex.none()
	}
	mut alts := []string{cap: literals.len}
	for lit in *literals {
		alts << escape_regex(lit.bytes.bytestr())
	}
	pattern := if alts.len == 1 {
		alts[0]
	} else {
		'(?:${alts.join('|')})'
	}
	log.debug('extracted fast line regex: ${pattern}')
	// V-specific: the local meta engine accepts byte-preserving V strings
	// directly, which is the counterpart of Rust's `utf8_empty(false)` setup.
	regex := meta.compile(pattern) or { return Error.regex(err.msg()) }
	return MaybeRegex.some(regex)
}

// V-specific owned return shape for Rust's `Result<Option<Regex>, Error>`.
struct MaybeRegex {
	has_value bool
	value     meta.Regex
}

fn MaybeRegex.some(value meta.Regex) MaybeRegex {
	return MaybeRegex{
		has_value: true
		value:     value
	}
}

fn MaybeRegex.none() MaybeRegex {
	return MaybeRegex{}
}

/// An inner literal extractor.
///
/// This is a somewhat stripped down version of the extractor from
/// regex-syntax. The main difference is that we try to identify a "best" set
/// of required literals while traversing the HIR.
struct Extractor {
	limit_class       usize
	limit_repeat      usize
	limit_literal_len usize
	limit_total       usize
}

/// Create a new inner literal extractor with a default configuration.
fn Extractor.new() Extractor {
	return Extractor{
		limit_class:       usize(10)
		limit_repeat:      usize(10)
		limit_literal_len: usize(100)
		limit_total:       usize(64)
	}
}

/// Execute the extractor at the top-level and return an untagged sequence
/// of literals.
fn (ex Extractor) extract_untagged(hir &Hir) Seq {
	mut seq := ex.extract(hir)
	literal_trace('extracted inner literals: ${seq.seq}')
	seq.seq.optimize_for_prefix_by_preference()
	literal_trace('extracted inner literals after optimization: ${seq.seq}')
	if !seq.is_good() {
		literal_trace('throwing away inner literals because they might be slow')
		seq.make_infinite()
	}
	return seq.seq
}

/// Execute the extractor and return a sequence of literals.
fn (ex Extractor) extract(hir &Hir) TSeq {
	return match hir.kind {
		.fail {
			TSeq.empty()
		}
		.empty, .look {
			TSeq.singleton(Literal.exact([]u8{}))
		}
		.literal {
			mut seq := TSeq.singleton(Literal.exact(hir.literal.bytes()))
			ex.enforce_literal_len(mut seq)
			seq
		}
		.concat {
			ex.extract_concat(hir.children)
		}
		.alternation {
			ex.extract_alternation(hir.children)
		}
		.raw {
			ex.extract_pattern(hir.pattern, hir.unicode)
		}
	}
}

/// Extract a sequence from the given concatenation. Sequences from each of
/// the child HIR expressions are combined via cross product.
///
/// This short circuits once the cross product turns into a sequence
/// containing only inexact literals.
fn (ex Extractor) extract_concat(hirs []Hir) TSeq {
	mut seq := TSeq.singleton(Literal.exact([]u8{}))
	mut prev := ?TSeq(none)
	for hir in hirs {
		// If every element in the sequence is inexact, then a cross
		// product will always be a no-op. Thus, there is nothing else we
		// can add to it and can quit early. Note that this also includes
		// infinite sequences.
		if seq.is_inexact() {
			// If a concatenation has an empty sequence anywhere, then
			// it's impossible for the concatenantion to ever match. So we
			// can just quit now.
			if seq.is_empty() {
				return seq
			}
			if seq.is_really_good() {
				return seq
			}
			if p := prev {
				prev = ?TSeq(p.choose(seq))
			} else {
				prev = ?TSeq(seq)
			}
			seq = TSeq.singleton(Literal.exact([]u8{}))
			seq.make_not_prefix()
		}
		// Note that 'cross' also dispatches based on whether we're
		// extracting prefixes or suffixes.
		seq = ex.cross(seq, ex.extract(&hir))
	}
	if p := prev {
		return p.choose(seq)
	}
	return seq
}

/// Extract a sequence from the given alternation.
///
/// This short circuits once the union turns into an infinite sequence.
fn (ex Extractor) extract_alternation(hirs []Hir) TSeq {
	mut seq := TSeq.empty()
	for hir in hirs {
		// Once our 'seq' is infinite, every subsequent union
		// operation on it will itself always result in an
		// infinite sequence. Thus, it can never change and we can
		// short-circuit.
		if !seq.is_finite() {
			break
		}
		mut other := ex.extract(&hir)
		seq = ex.union(seq, mut other)
	}
	return seq
}

// V-specific: raw local HIR is parsed here because the translated regex
// module does not expose regex-syntax's fully expanded HIR node variants.
fn (ex Extractor) extract_pattern(pattern string, unicode bool) TSeq {
	mut parser := PatternLiteralParser.new(pattern, ex, unicode)
	return TSeq{
		seq:    parser.parse()
		prefix: true
	}
}

/// Extract a sequence of literals from the given repetition. We do our
/// best, Some examples:
///
///   'a*'    => [inexact(a), exact("")]
///   'a*?'   => [exact(""), inexact(a)]
///   'a+'    => [inexact(a)]
///   'a{3}'  => [exact(aaa)]
///   'a{3,5} => [inexact(aaa)]
///
/// The key here really is making sure we get the 'inexact' vs 'exact'
/// attributes correct on each of the literals we add. For example, the
/// fact that 'a*' gives us an inexact 'a' and an exact empty string means
/// that a regex like 'ab*c' will result in [inexact(ab), exact(ac)]
/// literals being extracted, which might actually be a better prefilter
/// than just 'a'.
// V-specific: the local raw-HIR parser supplies the already extracted
// repeated sequence and its quantifier instead of a regex-syntax HIR node.
fn (ex Extractor) extract_repetition_from_seq(seq TSeq, quant Quantifier) TSeq {
	mut subseq := seq.clone()
	if quant.min == 0 && quant.has_max && quant.max == 0 {
		return TSeq.singleton(Literal.exact([]u8{}))
	}
	if quant.min == 0 {
		// When 'max=1', we can retain exactness, since 'a?' is
		// equivalent to 'a|'. Similarly below, 'a??' is equivalent to
		// '|a'.
		if !(quant.has_max && quant.max == 1) {
			subseq.make_inexact()
		}
		mut empty := TSeq.singleton(Literal.exact([]u8{}))
		if !quant.greedy {
			tmp := subseq
			subseq = empty
			empty = tmp
		}
		return ex.union(subseq, mut empty)
	}
	if quant.has_max && quant.min == quant.max {
		limit := u64(ex.limit_repeat)
		mut out := TSeq.singleton(Literal.exact([]u8{}))
		stop := if quant.min < limit { quant.min } else { limit }
		for _ in u64(0) .. stop {
			if out.is_inexact() {
				break
			}
			out = ex.cross(out, subseq.clone())
		}
		if quant.min > limit {
			out.make_inexact()
		}
		return out
	}
	if quant.has_max && quant.min < quant.max {
		limit := u64(ex.limit_repeat)
		mut out := TSeq.singleton(Literal.exact([]u8{}))
		stop := if quant.min < limit { quant.min } else { limit }
		for _ in u64(0) .. stop {
			if out.is_inexact() {
				break
			}
			out = ex.cross(out, subseq.clone())
		}
		out.make_inexact()
		return out
	}
	subseq.make_inexact()
	return subseq
}

/// Compute the cross product of the two sequences if the result would be
/// within configured limits. Otherwise, make `seq2` infinite and cross the
/// infinite sequence with `seq1`.
fn (ex Extractor) cross(mut seq1 TSeq, mut seq2 TSeq) TSeq {
	if !seq2.prefix {
		return seq1.choose(seq2)
	}
	if max := seq1.max_cross_len(seq2) {
		if max > ex.limit_total {
			seq2.make_infinite()
		}
	}
	seq1.cross_forward(mut seq2)
	if len := seq1.len() {
		assert len <= ex.limit_total
	}
	ex.enforce_literal_len(mut seq1)
	return seq1
}

/// Union the two sequences if the result would be within configured
/// limits. Otherwise, make `seq2` infinite and union the infinite sequence
/// with `seq1`.
fn (ex Extractor) union(mut seq1 TSeq, mut seq2 TSeq) TSeq {
	if max := seq1.max_union_len(seq2) {
		if max > ex.limit_total {
			// We try to trim our literal sequences to see if we can make
			// room for more literals. The idea is that we'd rather trim down
			// literals already in our sequence if it means we can add a few
			// more and retain a finite sequence. Otherwise, we'll union with
			// an infinite sequence and that infects everything and effectively
			// stops literal extraction in its tracks.
			//
			// We do we keep 4 bytes here? Well, it's a bit of an abstraction
			// leakage. Downstream, the literals may wind up getting fed to
			// the Teddy algorithm, which supports searching literals up to
			// length 4. So that's why we pick that number here. Arguably this
			// should be a tuneable parameter, but it seems a little tricky to
			// describe. And I'm still unsure if this is the right way to go
			// about culling literal sequences.
			seq1.keep_first_bytes(4)
			seq2.keep_first_bytes(4)
			seq1.dedup()
			seq2.dedup()
			if trimmed := seq1.max_union_len(seq2) {
				if trimmed > ex.limit_total {
					seq2.make_infinite()
				}
			}
		}
	}
	seq1.union(mut seq2)
	if len := seq1.len() {
		assert len <= ex.limit_total
	}
	seq1.prefix = seq1.prefix && seq2.prefix
	return seq1
}

/// Applies the literal length limit to the given sequence. If none of the
/// literals in the sequence exceed the limit, then this is a no-op.
fn (ex Extractor) enforce_literal_len(mut seq TSeq) {
	seq.keep_first_bytes(ex.limit_literal_len)
}

struct TSeq implements IClone {
mut:
	seq    Seq
	prefix bool
}

fn TSeq.empty() TSeq {
	return TSeq{
		seq:    Seq.empty()
		prefix: true
	}
}

fn TSeq.infinite() TSeq {
	return TSeq{
		seq:    Seq.infinite()
		prefix: true
	}
}

fn TSeq.singleton(lit Literal) TSeq {
	return TSeq{
		seq:    Seq.singleton(lit)
		prefix: true
	}
}

// V-specific: this specializes the Rust iterator/`AsRef<[u8]>` constructor
// to the byte-slice representation used by the translated extractor.
fn TSeq.new(it [][]u8) TSeq {
	mut lits := []Literal{cap: it.len}
	for bytes in it {
		lits << Literal.exact(bytes)
	}
	return TSeq{
		seq:    Seq.new(lits)
		prefix: true
	}
}

fn (seq &^a TSeq) literals[^a]() ?&^a []Literal {
	return seq.seq.literals()
}

fn (mut seq TSeq) push(lit Literal) {
	seq.seq.push(lit)
}

fn (mut seq TSeq) make_inexact() {
	seq.seq.make_inexact()
}

fn (mut seq TSeq) make_infinite() {
	seq.seq.make_infinite()
}

fn (mut seq TSeq) cross_forward(mut other TSeq) {
	assert other.prefix
	seq.seq.cross_forward(mut other.seq)
}

fn (mut seq TSeq) union(mut other TSeq) {
	seq.seq.union(mut other.seq)
}

fn (mut seq TSeq) dedup() {
	seq.seq.dedup()
}

fn (mut seq TSeq) sort() {
	seq.seq.sort()
}

fn (mut seq TSeq) keep_first_bytes(len usize) {
	seq.seq.keep_first_bytes(len)
}

fn (seq TSeq) is_finite() bool {
	return seq.seq.is_finite()
}

fn (seq TSeq) is_empty() bool {
	return seq.seq.is_empty()
}

fn (seq TSeq) len() ?usize {
	return seq.seq.len()
}

fn (seq TSeq) is_exact() bool {
	return seq.seq.is_exact()
}

fn (seq TSeq) is_inexact() bool {
	return seq.seq.is_inexact()
}

fn (seq TSeq) max_union_len(other TSeq) ?usize {
	return seq.seq.max_union_len(other.seq)
}

fn (seq TSeq) max_cross_len(other TSeq) ?usize {
	assert other.prefix
	return seq.seq.max_cross_len(other.seq)
}

fn (seq TSeq) min_literal_len() ?usize {
	return seq.seq.min_literal_len()
}

fn (seq TSeq) max_literal_len() ?usize {
	return seq.seq.max_literal_len()
}

/// Tags this sequence as "not a prefix." When this happens, this sequence
/// can't be crossed as a suffix of another sequence.
fn (mut seq TSeq) make_not_prefix() {
	seq.prefix = false
}

/// Returns true if it's believed that the sequence given is "good" for
/// acceleration. This is useful for determining whether a sequence of
/// literals has any shot of being fast.
fn (seq TSeq) is_good() bool {
	if seq.has_poisonous_literal() {
		return false
	}
	min := seq.min_literal_len() or { return false }
	len := seq.len() or { return false }
	if min <= 1 {
		return len <= 3
	}
	return min >= 2 && len <= 64
}

/// Returns true if it's believed that the sequence given is "really
/// good" for acceleration. This is useful for short circuiting literal
/// extraction.
fn (seq TSeq) is_really_good() bool {
	if seq.has_poisonous_literal() {
		return false
	}
	min := seq.min_literal_len() or { return false }
	len := seq.len() or { return false }
	return min >= 3 && len <= 8
}

/// Returns true if the given sequence contains a poisonous literal.
fn (seq TSeq) has_poisonous_literal() bool {
	lits := seq.literals() or { return false }
	for lit in *lits {
		if is_poisonous(lit) {
			return true
		}
	}
	return false
}

/// Compare the two sequences and return the one that is believed to be
/// best according to a hodge podge of heuristics.
fn (seq TSeq) choose(other TSeq) TSeq {
	mut seq1 := seq
	mut seq2 := other
	seq1.make_inexact()
	seq2.make_inexact()
	if !seq1.is_finite() {
		return seq2
	}
	if !seq2.is_finite() {
		return seq1
	}
	if seq1.has_poisonous_literal() {
		return seq2
	}
	if seq2.has_poisonous_literal() {
		return seq1
	}
	min1 := seq1.min_literal_len() or { return seq2 }
	min2 := seq2.min_literal_len() or { return seq1 }
	if min1 < min2 {
		return seq2
	}
	if min2 < min1 {
		return seq1
	}
	len1 := seq1.len() or { return seq2 }
	len2 := seq2.len() or { return seq1 }
	if len1 < len2 {
		return seq2
	}
	if len2 < len1 {
		return seq1
	}
	return seq1
}

struct Literal implements IClone {
mut:
	bytes []u8
	exact bool
}

fn Literal.exact(bytes []u8) Literal {
	return Literal{
		bytes: bytes
		exact: true
	}
}

fn Literal.inexact(bytes []u8) Literal {
	return Literal{
		bytes: bytes
		exact: false
	}
}

fn (lit Literal) len() usize {
	return usize(lit.bytes.len)
}

struct Seq implements IClone {
mut:
	infinite bool
	lits     []Literal
}

fn Seq.empty() Seq {
	return Seq{
		lits: []Literal{}
	}
}

fn Seq.infinite() Seq {
	return Seq{
		infinite: true
	}
}

fn Seq.singleton(lit Literal) Seq {
	return Seq{
		lits: [lit]
	}
}

fn Seq.new(lits []Literal) Seq {
	return Seq{
		lits: lits
	}
}

fn (seq &^a Seq) literals[^a]() ?&^a []Literal {
	if seq.infinite {
		return none
	}
	return &seq.lits
}

fn (mut seq Seq) push(lit Literal) {
	if seq.infinite {
		return
	}
	seq.lits << lit
}

fn (mut seq Seq) make_inexact() {
	if seq.infinite {
		return
	}
	for i in 0 .. seq.lits.len {
		seq.lits[i].exact = false
	}
}

fn (mut seq Seq) make_infinite() {
	seq.infinite = true
	seq.lits = []Literal{}
}

fn (mut seq Seq) cross_forward(mut other Seq) {
	if other.infinite {
		if min := seq.min_literal_len() {
			if min == 0 {
				seq.make_infinite()
			} else {
				seq.make_inexact()
			}
		} else {
			seq.make_inexact()
		}
		return
	}
	if seq.infinite {
		seq.make_infinite()
		return
	}
	mut crossed := []Literal{cap: seq.lits.len * other.lits.len}
	for left in seq.lits {
		if !left.exact {
			crossed << left.clone()
			continue
		}
		for right in other.lits {
			mut bytes := []u8{cap: left.bytes.len + right.bytes.len}
			bytes << left.bytes
			bytes << right.bytes
			crossed << Literal{
				bytes: bytes
				exact: left.exact && right.exact
			}
		}
	}
	seq.lits = crossed
	seq.dedup()
}

fn (mut seq Seq) union(mut other Seq) {
	if seq.infinite || other.infinite {
		seq.make_infinite()
		return
	}
	for lit in other.lits {
		seq.lits << lit.clone()
	}
	seq.dedup()
}

fn (mut seq Seq) dedup() {
	if seq.infinite {
		return
	}
	mut deduped := []Literal{cap: seq.lits.len}
	for lit in seq.lits {
		if deduped.len > 0 && literal_bytes_equal(deduped[deduped.len - 1], lit) {
			if !lit.exact {
				deduped[deduped.len - 1].exact = false
			}
		} else {
			deduped << lit.clone()
		}
	}
	seq.lits = deduped
}

fn (mut seq Seq) sort() {
	if seq.infinite {
		return
	}
	for i in 1 .. seq.lits.len {
		mut j := i
		for j > 0 && literal_less(seq.lits[j], seq.lits[j - 1]) {
			seq.lits[j], seq.lits[j - 1] = seq.lits[j - 1], seq.lits[j]
			j--
		}
	}
}

fn (mut seq Seq) keep_first_bytes(len usize) {
	if seq.infinite {
		return
	}
	for i in 0 .. seq.lits.len {
		if seq.lits[i].bytes.len > int(len) {
			seq.lits[i].bytes = seq.lits[i].bytes[..int(len)].clone()
			seq.lits[i].exact = false
		}
	}
}

fn (seq Seq) is_finite() bool {
	return !seq.infinite
}

fn (seq Seq) is_empty() bool {
	return !seq.infinite && seq.lits.len == 0
}

fn (seq Seq) len() ?usize {
	if seq.infinite {
		return none
	}
	return usize(seq.lits.len)
}

fn (seq Seq) is_inexact() bool {
	if seq.infinite {
		return true
	}
	if seq.lits.len == 0 {
		return false
	}
	for lit in seq.lits {
		if lit.exact {
			return false
		}
	}
	return true
}

fn (seq Seq) is_exact() bool {
	if seq.infinite {
		return false
	}
	for lit in seq.lits {
		if !lit.exact {
			return false
		}
	}
	return true
}

fn (seq Seq) max_union_len(other Seq) ?usize {
	if seq.infinite || other.infinite {
		return none
	}
	return saturating_add_usize(usize(seq.lits.len), usize(other.lits.len))
}

fn (seq Seq) max_cross_len(other Seq) ?usize {
	if seq.infinite || other.infinite {
		return none
	}
	return saturating_mul_usize(usize(seq.lits.len), usize(other.lits.len))
}

fn (seq Seq) min_literal_len() ?usize {
	if seq.infinite || seq.lits.len == 0 {
		return none
	}
	mut min := seq.lits[0].len()
	for lit in seq.lits[1..] {
		if lit.len() < min {
			min = lit.len()
		}
	}
	return min
}

fn (seq Seq) max_literal_len() ?usize {
	if seq.infinite || seq.lits.len == 0 {
		return none
	}
	mut max := seq.lits[0].len()
	for lit in seq.lits[1..] {
		if lit.len() > max {
			max = lit.len()
		}
	}
	return max
}

fn (mut seq Seq) optimize_for_prefix_by_preference() {
	if seq.infinite {
		return
	}
	if min := seq.min_literal_len() {
		if min == 0 {
			seq.make_infinite()
			return
		}
	}
	origlen := seq.lits.len
	if origlen <= 1 {
		return
	}
	seq.dedup()
	seq.minimize_by_preference_prefix()
	prefix := common_literal_prefix(seq.lits)
	if prefix.len > 0 {
		isfast := seq.is_exact() && seq.lits.len <= 16
		usefix := prefix.len > 4 || (prefix.len > 1 && !isfast)
		if usefix {
			seq.keep_first_bytes(usize(prefix.len))
			seq.dedup()
		}
	}
}

fn (mut seq Seq) minimize_by_preference_prefix() {
	if seq.infinite || seq.lits.len <= 1 {
		return
	}
	mut minimized := []Literal{cap: seq.lits.len}
	for lit in seq.lits {
		mut skip := false
		for i in 0 .. minimized.len {
			if literal_has_prefix(lit, minimized[i]) {
				if literal_bytes_equal(lit, minimized[i]) && !lit.exact {
					minimized[i].exact = false
				}
				skip = true
				break
			}
		}
		if !skip {
			minimized << lit.clone()
		}
	}
	seq.lits = minimized
}

fn literal_bytes_equal(left Literal, right Literal) bool {
	if left.bytes.len != right.bytes.len {
		return false
	}
	for i in 0 .. left.bytes.len {
		if left.bytes[i] != right.bytes[i] {
			return false
		}
	}
	return true
}

fn literal_less(left Literal, right Literal) bool {
	common := if left.bytes.len < right.bytes.len { left.bytes.len } else { right.bytes.len }
	for i in 0 .. common {
		if left.bytes[i] != right.bytes[i] {
			return left.bytes[i] < right.bytes[i]
		}
	}
	if left.bytes.len != right.bytes.len {
		return left.bytes.len < right.bytes.len
	}
	return !left.exact && right.exact
}

fn saturating_add_usize(left usize, right usize) usize {
	if left > ~usize(0) - right {
		return ~usize(0)
	}
	return left + right
}

fn saturating_mul_usize(left usize, right usize) usize {
	if left != 0 && right > ~usize(0) / left {
		return ~usize(0)
	}
	return left * right
}

fn literal_has_prefix(lit Literal, prefix Literal) bool {
	if prefix.bytes.len > lit.bytes.len {
		return false
	}
	for i in 0 .. prefix.bytes.len {
		if lit.bytes[i] != prefix.bytes[i] {
			return false
		}
	}
	return true
}

fn single_exact_literal(seq Seq) ?Literal {
	if seq.infinite || seq.lits.len != 1 || !seq.lits[0].exact {
		return none
	}
	return seq.lits[0].clone()
}

fn common_literal_prefix(lits []Literal) []u8 {
	if lits.len == 0 {
		return []u8{}
	}
	mut prefix := lits[0].bytes.clone()
	for lit in lits[1..] {
		mut n := 0
		for n < prefix.len && n < lit.bytes.len && prefix[n] == lit.bytes[n] {
			n++
		}
		prefix = prefix[..n].clone()
		if prefix.len == 0 {
			break
		}
	}
	return prefix
}

/// Returns true if it is believe that this literal is likely to match very
/// frequently, and is thus not a good candidate for a prefilter.
fn is_poisonous(lit Literal) bool {
	if lit.bytes.len == 0 {
		return true
	}
	if lit.bytes.len != 1 {
		return false
	}
	byte := lit.bytes[0]
	return byte == ` ` || byte == `e` || byte == `t` || byte >= 0xc0
}

enum PatternTokenKind {
	literal
	candidate
	zero_width
	breaker
}

struct PatternToken {
	kind PatternTokenKind
	bytes []u8
	seq   Seq
	prefix bool
}

fn PatternToken.literal(bytes []u8) PatternToken {
	return PatternToken{
		kind:  .literal
		bytes: bytes
	}
}

fn PatternToken.candidate(seq Seq) PatternToken {
	return PatternToken{
		kind:   .candidate
		seq:    seq
		prefix: true
	}
}

fn PatternToken.candidate_tseq(seq TSeq) PatternToken {
	return PatternToken{
		kind:   .candidate
		seq:    seq.seq
		prefix: seq.prefix
	}
}

fn PatternToken.zero_width() PatternToken {
	return PatternToken{
		kind: .zero_width
	}
}

fn PatternToken.breaker() PatternToken {
	return PatternToken{
		kind: .breaker
	}
}

fn (token PatternToken) to_tseq() TSeq {
	return match token.kind {
		.literal {
			TSeq.singleton(Literal.exact(token.bytes))
		}
		.candidate {
			TSeq{
				seq:    token.seq
				prefix: token.prefix
			}
		}
		.zero_width {
			TSeq.singleton(Literal.exact([]u8{}))
		}
		.breaker {
			TSeq.infinite()
		}
	}
}

// V-specific parser helper for the port's string-based HIR analysis.
struct Quantifier {
	min     u64
	has_max bool
	max     u64
	greedy  bool
	end     int
}

fn parse_quantifier(pattern string, start int) ?Quantifier {
	if start >= pattern.len {
		return none
	}
	match pattern[start] {
		`*` {
			mut end := start + 1
			mut greedy := true
			if end < pattern.len && pattern[end] == `?` {
				greedy = false
				end++
			}
			return Quantifier{
				min:     u64(0)
				has_max: false
				max:     u64(0)
				greedy:  greedy
				end:     end
			}
		}
		`+` {
			mut end := start + 1
			mut greedy := true
			if end < pattern.len && pattern[end] == `?` {
				greedy = false
				end++
			}
			return Quantifier{
				min:     u64(1)
				has_max: false
				max:     u64(0)
				greedy:  greedy
				end:     end
			}
		}
		`?` {
			mut end := start + 1
			mut greedy := true
			if end < pattern.len && pattern[end] == `?` {
				greedy = false
				end++
			}
			return Quantifier{
				min:     u64(0)
				has_max: true
				max:     u64(1)
				greedy:  greedy
				end:     end
			}
		}
		`{` {
			mut i := start + 1
			min_start := i
			for i < pattern.len && pattern[i] >= `0` && pattern[i] <= `9` {
				i++
			}
			if i == min_start {
				return none
			}
			min := parse_decimal_u64(pattern[min_start..i]) or { return none }
			mut has_max := true
			mut max := min
			if i < pattern.len && pattern[i] == `,` {
				i++
				max_start := i
				for i < pattern.len && pattern[i] >= `0` && pattern[i] <= `9` {
					i++
				}
				if i == max_start {
					has_max = false
					max = u64(0)
				} else {
					max = parse_decimal_u64(pattern[max_start..i]) or { return none }
				}
			}
			if i >= pattern.len || pattern[i] != `}` {
				return none
			}
			i++
			mut greedy := true
			if i < pattern.len && pattern[i] == `?` {
				greedy = false
				i++
			}
			return Quantifier{
				min:     min
				has_max: has_max
				max:     max
				greedy:  greedy
				end:     i
			}
		}
		else {
			return none
		}
	}
}

fn parse_decimal_u64(s string) ?u64 {
	if s.len == 0 {
		return none
	}
	mut n := u64(0)
	for b in s.bytes() {
		if b < `0` || b > `9` {
			return none
		}
		n = (n * u64(10)) + u64(b - `0`)
	}
	return n
}

fn next_utf8_text(text string, pos int) (string, int) {
	if pos >= text.len {
		return '', pos
	}
	first := text[pos]
	mut len := 1
	if first & 0xe0 == 0xc0 {
		len = 2
	} else if first & 0xf0 == 0xe0 {
		len = 3
	} else if first & 0xf8 == 0xf0 {
		len = 4
	}
	next := min_int(pos + len, text.len)
	return text[pos..next], next
}

fn case_fold_seq(text string, unicode bool) Seq {
	if !unicode {
		if text.len != 1 || text[0] >= 0x80 {
			return exact_case_variants([text])
		}
	}
	if unicode {
		match text {
			'S', 's', 'ſ' {
				return exact_case_variants(['S', 's', 'ſ'])
			}
			'Ε', 'ε', 'ϵ' {
				return exact_case_variants(['Ε', 'ε', 'ϵ'])
			}
			else {}
		}
	}
	mut variants := []string{}
	add_case_variant(mut variants, text.to_upper())
	add_case_variant(mut variants, text.to_lower())
	return exact_case_variants(variants)
}

fn exact_case_variants(variants []string) Seq {
	mut lits := []Literal{cap: variants.len}
	for variant in variants {
		lits << Literal.exact(variant.bytes())
	}
	return Seq.new(lits)
}

fn add_case_variant(mut variants []string, variant string) {
	for existing in variants {
		if existing == variant {
			return
		}
	}
	variants << variant
}

struct PatternLiteralParser {
	pattern string
	ex      Extractor
mut:
	pos              int
	case_insensitive bool
	unicode          bool
}

fn PatternLiteralParser.new(pattern string, ex Extractor, unicode bool) PatternLiteralParser {
	return PatternLiteralParser{
		pattern: pattern.to_owned()
		ex:      ex
		unicode: unicode
	}
}

fn (mut p PatternLiteralParser) parse() Seq {
	seq := p.parse_expr(0)
	if p.pos != p.pattern.len {
		return Seq.infinite()
	}
	return seq.seq
}

fn (mut p PatternLiteralParser) parse_expr(end u8) TSeq {
	mut branches := []TSeq{}
	for {
		branches << p.parse_branch(end)
		if p.pos < p.pattern.len && p.pattern[p.pos] == `|` {
			p.pos++
			continue
		}
		break
	}
	if branches.len == 0 {
		return TSeq.infinite()
	}
	mut seq := TSeq.empty()
	for branch in branches {
		if !branch.is_finite() {
			return TSeq.infinite()
		}
		mut other := branch.clone()
		seq = p.ex.union(seq, mut other)
	}
	return seq
}

fn (mut p PatternLiteralParser) parse_branch(end u8) TSeq {
	mut seq := TSeq.singleton(Literal.exact([]u8{}))
	mut prev := ?TSeq(none)
	for p.pos < p.pattern.len {
		if end != 0 && p.pattern[p.pos] == end {
			break
		}
		if p.pattern[p.pos] == `|` {
			break
		}
		if seq.is_inexact() || p.should_cut_poisonous_case_fold(seq) {
			if seq.is_empty() {
				p.skip_branch_remainder(end)
				return seq
			}
			if seq.is_really_good() {
				p.skip_branch_remainder(end)
				return seq
			}
			if pseq := prev {
				prev = ?TSeq(pseq.choose(seq))
			} else {
				prev = ?TSeq(seq)
			}
			seq = TSeq.singleton(Literal.exact([]u8{}))
			seq.make_not_prefix()
		}
		token := p.parse_token()
		mut atom := token.to_tseq()
		for {
			if q := parse_quantifier(p.pattern, p.pos) {
				p.pos = q.end
				atom = p.ex.extract_repetition_from_seq(atom, q)
				continue
			}
			break
		}
		seq = p.ex.cross(seq, atom)
	}
	if pseq := prev {
		return pseq.choose(seq)
	}
	return seq
}

fn (p PatternLiteralParser) should_cut_poisonous_case_fold(seq TSeq) bool {
	if !p.case_insensitive || seq.is_inexact() {
		return false
	}
	len := seq.len() or { return false }
	return len > 1 && seq.has_poisonous_literal()
}

fn (mut p PatternLiteralParser) skip_branch_remainder(end u8) {
	mut depth := 0
	for p.pos < p.pattern.len {
		ch := p.pattern[p.pos]
		if ch == `\\` {
			p.pos = escape_tail_end(p.pattern, p.pos)
			continue
		}
		if ch == `[` {
			_, ok, next := parse_class_set(p.pattern, p.pos + 1)
			if ok {
				p.pos = next
				continue
			}
			p.pos++
			continue
		}
		if ch == `(` {
			depth++
			p.pos++
			continue
		}
		if ch == `)` {
			if depth == 0 && end == `)` {
				return
			}
			if depth > 0 {
				depth--
			}
			p.pos++
			continue
		}
		if ch == `|` && depth == 0 {
			return
		}
		if end != 0 && ch == end && depth == 0 {
			return
		}
		p.pos++
	}
}

fn (mut p PatternLiteralParser) parse_token() PatternToken {
	if p.pos >= p.pattern.len {
		return PatternToken.breaker()
	}
	ch := p.pattern[p.pos]
	match ch {
		`\\` {
			return p.parse_escape()
		}
		`[` {
			return p.parse_class()
		}
		`(` {
			return p.parse_group()
		}
		`.` {
			p.pos++
			return PatternToken.breaker()
		}
		`^`, `$` {
			p.pos++
			return PatternToken.zero_width()
		}
		`+`, `*`, `?`, `{`, `}` {
			p.pos++
			return PatternToken.breaker()
		}
		else {
			if is_regex_meta_literal(ch, false) {
				p.pos++
				return PatternToken.breaker()
			}
			text, next := next_utf8_text(p.pattern, p.pos)
			p.pos = next
			if p.case_insensitive {
				return PatternToken.candidate(case_fold_seq(text, p.unicode))
			}
			return PatternToken.literal(text.bytes())
		}
	}
}

fn (mut p PatternLiteralParser) parse_escape() PatternToken {
	start := p.pos
	if start + 1 >= p.pattern.len {
		p.pos = p.pattern.len
		return PatternToken.breaker()
	}
	next := p.pattern[start + 1]
	match next {
		`d`, `D`, `s`, `S`, `w`, `W`, `p`, `P` {
			p.pos = escape_tail_end(p.pattern, start)
			return PatternToken.breaker()
		}
		`b`, `B`, `A`, `z` {
			p.pos = start + 2
			return PatternToken.zero_width()
		}
		else {
			has_byte, byte, next_i := parse_escape_byte(p.pattern, start)
			p.pos = next_i
			if has_byte {
				if p.case_insensitive {
					return PatternToken.candidate(case_fold_seq([byte].bytestr(), p.unicode))
				}
				return PatternToken.literal([byte])
			}
			return PatternToken.breaker()
		}
	}
}

fn (mut p PatternLiteralParser) parse_class() PatternToken {
	start := p.pos
	end := class_end(p.pattern, start)
	if end < 0 {
		p.pos++
		return PatternToken.breaker()
	}
	body := p.pattern[start + 1..end]
	if body.contains('&&') {
		p.pos = end + 1
		return PatternToken.candidate(Seq.empty())
	}
	class_set, ok, next := parse_class_set(p.pattern, p.pos + 1)
	if ok && class_is_ascii(body) {
		p.pos = next
		mut variants := []string{}
		for i, present in class_set {
			if present {
				if variants.len > int(p.ex.limit_class) {
					return PatternToken.breaker()
				}
				text := [u8(i)].bytestr()
				if p.case_insensitive {
					add_seq_strings(mut variants, case_fold_seq(text, p.unicode))
				} else {
					add_case_variant(mut variants, text)
				}
			}
		}
		if variants.len > int(p.ex.limit_class) {
			return PatternToken.breaker()
		}
		return PatternToken.candidate(exact_sorted_seq(variants))
	}
	if seq := p.parse_simple_unicode_class(body) {
		p.pos = end + 1
		return PatternToken.candidate(seq)
	}
	p.pos++
	for p.pos < p.pattern.len {
		if p.pattern[p.pos] == `\\` {
			p.pos = escape_tail_end(p.pattern, p.pos)
			continue
		}
		if p.pattern[p.pos] == `]` {
			p.pos++
			return PatternToken.breaker()
		}
		p.pos++
	}
	return PatternToken.breaker()
}

fn class_end(pattern string, start int) int {
	mut i := start + 1
	for i < pattern.len {
		if pattern[i] == `\\` {
			i = escape_tail_end(pattern, i)
			continue
		}
		if pattern[i] == `]` {
			return i
		}
		i++
	}
	return -1
}

fn class_is_ascii(body string) bool {
	for b in body.bytes() {
		if b >= 0x80 {
			return false
		}
	}
	return true
}

fn (mut p PatternLiteralParser) parse_simple_unicode_class(body string) ?Seq {
	if body.len == 0 {
		return Seq.empty()
	}
	mut variants := []string{}
	mut pos := 0
	for pos < body.len {
		if body[pos] in [`^`, `[`, `]`, `-`, `&`, `~`, `\\`] {
			return none
		}
		text, next := next_utf8_text(body, pos)
		pos = next
		if p.case_insensitive {
			add_seq_strings(mut variants, case_fold_seq(text, p.unicode))
		} else {
			add_case_variant(mut variants, text)
		}
		if variants.len > int(p.ex.limit_class) {
			return none
		}
	}
	return exact_sorted_seq(variants)
}

fn add_seq_strings(mut variants []string, seq Seq) {
	lits := seq.literals() or { return }
	for lit in *lits {
		add_case_variant(mut variants, lit.bytes.bytestr())
	}
}

fn exact_sorted_seq(variants []string) Seq {
	mut sorted := variants.clone()
	sorted.sort()
	mut lits := []Literal{cap: sorted.len}
	for variant in sorted {
		lits << Literal.exact(variant.bytes())
	}
	return Seq.new(lits)
}

fn (mut p PatternLiteralParser) parse_group() PatternToken {
	start := p.pos
	p.pos++
	if p.pos < p.pattern.len && p.pattern[p.pos] == `?` {
		p.pos++
		if p.pos >= p.pattern.len {
			return PatternToken.breaker()
		}
		prefix := p.pattern[p.pos]
		if prefix == `:` {
			p.pos++
			return p.parse_group_body()
		}
		if prefix == `=` || prefix == `!` {
			p.pos = start
			p.skip_balanced_group()
			return PatternToken.zero_width()
		}
		if prefix == `<` && p.pos + 1 < p.pattern.len
			&& (p.pattern[p.pos + 1] == `=` || p.pattern[p.pos + 1] == `!`) {
			p.pos = start
			p.skip_balanced_group()
			return PatternToken.zero_width()
		}
		if prefix == `P` {
			for p.pos < p.pattern.len && p.pattern[p.pos] != `>` && p.pattern[p.pos] != `)` {
				p.pos++
			}
			if p.pos < p.pattern.len && p.pattern[p.pos] == `>` {
				p.pos++
				return p.parse_group_body()
			}
			p.pos = start
			p.skip_balanced_group()
			return PatternToken.breaker()
		}
		mut scan := p.pos
		for scan < p.pattern.len && p.pattern[scan] != `:` && p.pattern[scan] != `)` {
			scan++
		}
		if scan < p.pattern.len && p.pattern[scan] == `:` {
			flags := p.pattern[p.pos..scan]
			p.pos = scan + 1
			old_case_insensitive := p.case_insensitive
			old_unicode := p.unicode
			p.apply_flags(flags)
			token := p.parse_group_body()
			p.case_insensitive = old_case_insensitive
			p.unicode = old_unicode
			return token
		}
		if scan < p.pattern.len && p.pattern[scan] == `)` {
			flags := p.pattern[p.pos..scan]
			p.apply_flags(flags)
			p.pos = scan + 1
			return PatternToken.zero_width()
		}
		p.pos = start
		p.skip_balanced_group()
		return PatternToken.breaker()
	}
	return p.parse_group_body()
}

fn (mut p PatternLiteralParser) apply_flags(flags string) {
	mut negated := false
	for flag in flags.bytes() {
		if flag == `-` {
			negated = true
			continue
		}
		match flag {
			`i` {
				p.case_insensitive = !negated
			}
			`u` {
				p.unicode = !negated
			}
			else {}
		}
	}
}

fn (mut p PatternLiteralParser) parse_group_body() PatternToken {
	seq := p.parse_expr(`)`)
	if p.pos >= p.pattern.len || p.pattern[p.pos] != `)` {
		return PatternToken.breaker()
	}
	p.pos++
	return PatternToken.candidate_tseq(seq)
}

fn (mut p PatternLiteralParser) skip_balanced_group() {
	if p.pos >= p.pattern.len || p.pattern[p.pos] != `(` {
		return
	}
	mut depth := 0
	for p.pos < p.pattern.len {
		ch := p.pattern[p.pos]
		if ch == `\\` {
			p.pos = escape_tail_end(p.pattern, p.pos)
			continue
		}
		if ch == `[` {
			_, ok, next := parse_class_set(p.pattern, p.pos + 1)
			if ok {
				p.pos = next
				continue
			}
		}
		if ch == `(` {
			depth++
		} else if ch == `)` {
			depth--
			p.pos++
			if depth <= 0 {
				return
			}
			continue
		}
		p.pos++
	}
}

fn choose_best_seq(candidates []Seq) Seq {
	if candidates.len == 0 {
		return Seq.infinite()
	}
	mut best := TSeq{
		seq:    candidates[0].clone()
		prefix: true
	}
	for candidate in candidates[1..] {
		best = best.choose(TSeq{
			seq:    candidate.clone()
			prefix: true
		})
	}
	return best.seq
}

fn quantifier_end(pattern string, start int) int {
	if start >= pattern.len {
		return start
	}
	mut end := start
	match pattern[start] {
		`*`, `+`, `?` {
			end = start + 1
		}
		`{` {
			mut i := start + 1
			mut saw_digit := false
			for i < pattern.len && pattern[i] >= `0` && pattern[i] <= `9` {
				saw_digit = true
				i++
			}
			if i < pattern.len && pattern[i] == `,` {
				i++
				for i < pattern.len && pattern[i] >= `0` && pattern[i] <= `9` {
					i++
				}
			}
			if !saw_digit || i >= pattern.len || pattern[i] != `}` {
				return start
			}
			end = i + 1
		}
		else {
			return start
		}
	}
	if end < pattern.len && pattern[end] == `?` {
		end++
	}
	return end
}

fn escape_tail_end(pattern string, start int) int {
	if start + 1 >= pattern.len {
		return pattern.len
	}
	next := pattern[start + 1]
	match next {
		`p`, `P` {
			mut i := start + 2
			if i < pattern.len && pattern[i] == `{` {
				i++
				for i < pattern.len && pattern[i] != `}` {
					i++
				}
				if i < pattern.len {
					i++
				}
				return i
			}
			return if i < pattern.len { i + 1 } else { i }
		}
		`x` {
			if start + 2 < pattern.len && pattern[start + 2] == `{` {
				mut i := start + 3
				for i < pattern.len && pattern[i] != `}` {
					i++
				}
				return if i < pattern.len { i + 1 } else { i }
			}
			return min_int(start + 4, pattern.len)
		}
		`u` {
			return min_int(start + 6, pattern.len)
		}
		`U` {
			return min_int(start + 10, pattern.len)
		}
		else {
			return start + 2
		}
	}
}

fn min_int(a int, b int) int {
	if a < b {
		return a
	}
	return b
}

fn pattern_has_inline_case_insensitive_flag(pattern string) bool {
	mut i := 0
	for i + 2 < pattern.len {
		if pattern[i] != `(` || pattern[i + 1] != `?` {
			i++
			continue
		}
		first := pattern[i + 2]
		if first in [`:`, `=`, `!`, `<`, `P`] {
			i += 2
			continue
		}
		mut j := i + 2
		mut negated := false
		for j < pattern.len && pattern[j] != `:` && pattern[j] != `)` {
			if pattern[j] == `-` {
				negated = true
			} else if pattern[j] == `i` {
				if !negated {
					return true
				}
			} else {
				negated = false
			}
			j++
		}
		i = j + 1
	}
	return false
}
