module regex

import regex.pcre

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
fn InnerLiterals.new(chir &ConfiguredHIR, re &pcre.Regex) InnerLiterals {
	_ = re
	if _ := chir.config().line_terminator {
	} else {
		return InnerLiterals.none()
	}
	pattern := chir.hir().to_regex()
	analysis := AstAnalysis.from_pattern(pattern) or { AstAnalysis.new() }
	config := chir.config()
	if config.case_insensitive || (config.case_smart && analysis.any_literal()
		&& !analysis.any_uppercase()) {
		return InnerLiterals.none()
	}
	if pattern_has_inline_case_insensitive_flag(pattern) {
		return InnerLiterals.none()
	}
	if chir.hir().is_alternation_literal() {
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
fn (lits InnerLiterals) one_regex() !MaybeRegex {
	literals := lits.seq.literals() or { return MaybeRegex.none() }
	if literals.len == 0 {
		return MaybeRegex.none()
	}
	mut alts := []string{cap: literals.len}
	for lit in literals {
		if lit.bytes.len == 0 {
			continue
		}
		alts << escape_regex(lit.bytes.bytestr())
	}
	if alts.len == 0 {
		return MaybeRegex.none()
	}
	pattern := if alts.len == 1 {
		alts[0]
	} else {
		'(?:${alts.join('|')})'
	}
	regex := pcre.compile(pattern) or { return Error.regex(err.msg()) }
	return MaybeRegex.some(regex)
}

struct MaybeRegex {
	has_value bool
	value     pcre.Regex
}

fn MaybeRegex.some(value pcre.Regex) MaybeRegex {
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
	seq.seq.optimize_for_prefix_by_preference()
	if !seq.is_good() {
		seq.make_infinite()
	}
	return seq.seq
}

/// Execute the extractor and return a sequence of literals.
fn (ex Extractor) extract(hir &Hir) TSeq {
	return match hir.kind {
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
			ex.extract_pattern(hir.pattern)
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
		if seq.is_inexact() {
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
		if !seq.is_finite() {
			break
		}
		mut other := ex.extract(&hir)
		seq = ex.union(seq, mut other)
	}
	return seq
}

fn (ex Extractor) extract_pattern(pattern string) TSeq {
	mut parser := PatternLiteralParser.new(pattern)
	return TSeq{
		seq:    parser.parse()
		prefix: true
	}
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
	ex.enforce_literal_len(mut seq1)
	return seq1
}

/// Union the two sequences if the result would be within configured
/// limits. Otherwise, make `seq2` infinite and union the infinite sequence
/// with `seq1`.
fn (ex Extractor) union(mut seq1 TSeq, mut seq2 TSeq) TSeq {
	if max := seq1.max_union_len(seq2) {
		if max > ex.limit_total {
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
	seq1.prefix = seq1.prefix && seq2.prefix
	return seq1
}

/// Applies the literal length limit to the given sequence. If none of the
/// literals in the sequence exceed the limit, then this is a no-op.
fn (ex Extractor) enforce_literal_len(mut seq TSeq) {
	seq.keep_first_bytes(ex.limit_literal_len)
}

struct TSeq {
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

fn (seq TSeq) literals() ?[]Literal {
	return seq.seq.literals()
}

fn (mut seq TSeq) make_inexact() {
	seq.seq.make_inexact()
}

fn (mut seq TSeq) make_infinite() {
	seq.seq.make_infinite()
}

fn (mut seq TSeq) cross_forward(mut other TSeq) {
	seq.seq.cross_forward(mut other.seq)
}

fn (mut seq TSeq) union(mut other TSeq) {
	seq.seq.union(mut other.seq)
}

fn (mut seq TSeq) dedup() {
	seq.seq.dedup()
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

fn (seq TSeq) is_inexact() bool {
	return seq.seq.is_inexact()
}

fn (seq TSeq) max_union_len(other TSeq) ?usize {
	return seq.seq.max_union_len(other.seq)
}

fn (seq TSeq) max_cross_len(other TSeq) ?usize {
	return seq.seq.max_cross_len(other.seq)
}

fn (seq TSeq) min_literal_len() ?usize {
	return seq.seq.min_literal_len()
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
	for lit in lits {
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
	if len1 > len2 {
		return seq2
	}
	if len2 > len1 {
		return seq1
	}
	return seq1
}

struct Literal {
mut:
	bytes []u8
	exact bool
}

fn Literal.exact(bytes []u8) Literal {
	return Literal{
		bytes: bytes.clone()
		exact: true
	}
}

fn Literal.inexact(bytes []u8) Literal {
	return Literal{
		bytes: bytes.clone()
		exact: false
	}
}

fn (lit Literal) clone() Literal {
	return Literal{
		bytes: lit.bytes.clone()
		exact: lit.exact
	}
}

fn (lit Literal) len() usize {
	return usize(lit.bytes.len)
}

struct Seq {
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
		lits: [lit.clone()]
	}
}

fn Seq.new(lits []Literal) Seq {
	return Seq{
		lits: clone_literals(lits)
	}
}

fn (seq Seq) clone() Seq {
	return Seq{
		infinite: seq.infinite
		lits:     clone_literals(seq.lits)
	}
}

fn (seq Seq) literals() ?[]Literal {
	if seq.infinite {
		return none
	}
	return clone_literals(seq.lits)
}

fn (mut seq Seq) push(lit Literal) {
	if seq.infinite {
		return
	}
	seq.lits << lit.clone()
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
	if seq.infinite || other.infinite {
		seq.make_infinite()
		return
	}
	mut crossed := []Literal{cap: seq.lits.len * other.lits.len}
	for left in seq.lits {
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
		mut found := false
		for i in 0 .. deduped.len {
			if literal_bytes_equal(deduped[i], lit) {
				if !lit.exact {
					deduped[i].exact = false
				}
				found = true
				break
			}
		}
		if !found {
			deduped << lit.clone()
		}
	}
	seq.lits = deduped
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

fn (seq Seq) max_union_len(other Seq) ?usize {
	if seq.infinite || other.infinite {
		return none
	}
	return usize(seq.lits.len + other.lits.len)
}

fn (seq Seq) max_cross_len(other Seq) ?usize {
	if seq.infinite || other.infinite {
		return none
	}
	return usize(seq.lits.len * other.lits.len)
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

fn (mut seq Seq) optimize_for_prefix_by_preference() {
	if seq.infinite || seq.lits.len <= 1 {
		return
	}
	seq.dedup()
	prefix := common_literal_prefix(seq.lits)
	if prefix.len >= 2 {
		seq.lits = [Literal.inexact(prefix)]
	}
}

fn clone_literals(lits []Literal) []Literal {
	mut cloned := []Literal{cap: lits.len}
	for lit in lits {
		cloned << lit.clone()
	}
	return cloned
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
	return lit.bytes[0] in [` `, `\t`, `\n`, `\r`]
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
}

fn PatternToken.literal(bytes []u8) PatternToken {
	return PatternToken{
		kind:  .literal
		bytes: bytes.clone()
	}
}

fn PatternToken.candidate(seq Seq) PatternToken {
	return PatternToken{
		kind: .candidate
		seq:  seq.clone()
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

struct PatternLiteralParser {
	pattern string
mut:
	pos int
}

fn PatternLiteralParser.new(pattern string) PatternLiteralParser {
	return PatternLiteralParser{
		pattern: pattern.to_owned()
	}
}

fn (mut p PatternLiteralParser) parse() Seq {
	seq := p.parse_expr(0)
	if p.pos != p.pattern.len {
		return Seq.infinite()
	}
	return seq
}

fn (mut p PatternLiteralParser) parse_expr(end u8) Seq {
	mut branches := []Seq{}
	for {
		branches << p.parse_branch(end)
		if p.pos < p.pattern.len && p.pattern[p.pos] == `|` {
			p.pos++
			continue
		}
		break
	}
	if branches.len == 0 {
		return Seq.infinite()
	}
	mut seq := Seq.empty()
	for branch in branches {
		if !branch.is_finite() {
			return Seq.infinite()
		}
		mut other := branch.clone()
		seq.union(mut other)
	}
	return seq
}

fn (mut p PatternLiteralParser) parse_branch(end u8) Seq {
	mut candidates := []Seq{}
	mut run := []u8{}
	for p.pos < p.pattern.len {
		if end != 0 && p.pattern[p.pos] == end {
			break
		}
		if p.pattern[p.pos] == `|` {
			break
		}
		token := p.parse_token()
		qend := quantifier_end(p.pattern, p.pos)
		quantified := qend > p.pos
		if quantified {
			p.flush_run(mut candidates, mut run)
			p.pos = qend
			continue
		}
		match token.kind {
			.literal {
				run << token.bytes
			}
			.candidate {
				if lit := single_exact_literal(token.seq) {
					run << lit.bytes
				} else {
					p.flush_run(mut candidates, mut run)
					if token.seq.is_finite() && !token.seq.is_empty() {
						candidates << token.seq.clone()
					}
				}
			}
			.zero_width {}
			.breaker {
				p.flush_run(mut candidates, mut run)
			}
		}
	}
	p.flush_run(mut candidates, mut run)
	return choose_best_seq(candidates)
}

fn (mut p PatternLiteralParser) flush_run(mut candidates []Seq, mut run []u8) {
	if run.len == 0 {
		return
	}
	candidates << Seq.singleton(Literal.exact(run))
	run = []u8{}
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
			p.pos++
			return PatternToken.literal([ch])
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
				return PatternToken.literal([byte])
			}
			return PatternToken.breaker()
		}
	}
}

fn (mut p PatternLiteralParser) parse_class() PatternToken {
	_, ok, next := parse_class_set(p.pattern, p.pos + 1)
	if ok {
		p.pos = next
		return PatternToken.breaker()
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
			p.pos = scan + 1
			return p.parse_group_body()
		}
		if scan < p.pattern.len && p.pattern[scan] == `)` {
			p.pos = scan + 1
			return PatternToken.zero_width()
		}
		p.pos = start
		p.skip_balanced_group()
		return PatternToken.breaker()
	}
	return p.parse_group_body()
}

fn (mut p PatternLiteralParser) parse_group_body() PatternToken {
	seq := p.parse_expr(`)`)
	if p.pos >= p.pattern.len || p.pattern[p.pos] != `)` {
		return PatternToken.breaker()
	}
	p.pos++
	return PatternToken.candidate(seq)
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
