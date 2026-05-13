module printer

import time

/// Summary statistics produced at the end of a search.
///
/// When statistics are reported by a printer, they correspond to all searches
/// executed with that printer.
pub struct Stats implements IClone {
	elapsed_             NiceDuration
	searches_            u64
	searches_with_match_ u64
	bytes_searched_      u64
	bytes_printed_       u64
	matched_lines_       u64
	matches_             u64
}

/// Return a new value for tracking aggregate statistics across searches.
///
/// All statistics are set to `0`.
pub fn Stats.new() Stats {
	return Stats{}
}

/// Return the total amount of time elapsed.
pub fn (stats Stats) elapsed() time.Duration {
	return stats.elapsed_.duration
}

/// Return the total number of searches executed.
pub fn (stats Stats) searches() u64 {
	return stats.searches_
}

/// Return the total number of searches that found at least one match.
pub fn (stats Stats) searches_with_match() u64 {
	return stats.searches_with_match_
}

/// Return the total number of bytes searched.
pub fn (stats Stats) bytes_searched() u64 {
	return stats.bytes_searched_
}

/// Return the total number of bytes printed.
pub fn (stats Stats) bytes_printed() u64 {
	return stats.bytes_printed_
}

/// Return the total number of lines that participated in a match.
///
/// When matches may contain multiple lines then this includes every line
/// that is part of every match.
pub fn (stats Stats) matched_lines() u64 {
	return stats.matched_lines_
}

/// Return the total number of matches.
///
/// There may be multiple matches per line.
pub fn (stats Stats) matches() u64 {
	return stats.matches_
}

/// Add to the elapsed time.
pub fn (mut stats Stats) add_elapsed(duration time.Duration) {
	stats.elapsed_.duration += duration
}

/// Add to the number of searches executed.
pub fn (mut stats Stats) add_searches(n u64) {
	stats.searches_ += n
}

/// Add to the number of searches that found at least one match.
pub fn (mut stats Stats) add_searches_with_match(n u64) {
	stats.searches_with_match_ += n
}

/// Add to the total number of bytes searched.
pub fn (mut stats Stats) add_bytes_searched(n u64) {
	stats.bytes_searched_ += n
}

/// Add to the total number of bytes printed.
pub fn (mut stats Stats) add_bytes_printed(n u64) {
	stats.bytes_printed_ += n
}

/// Add to the total number of lines that participated in a match.
pub fn (mut stats Stats) add_matched_lines(n u64) {
	stats.matched_lines_ += n
}

/// Add to the total number of matches.
pub fn (mut stats Stats) add_matches(n u64) {
	stats.matches_ += n
}

pub fn (left Stats) + (right Stats) Stats {
	return Stats{
		elapsed_:             NiceDuration{
			duration: left.elapsed_.duration + right.elapsed_.duration
		}
		searches_:            left.searches_ + right.searches_
		searches_with_match_: left.searches_with_match_ + right.searches_with_match_
		bytes_searched_:      left.bytes_searched_ + right.bytes_searched_
		bytes_printed_:       left.bytes_printed_ + right.bytes_printed_
		matched_lines_:       left.matched_lines_ + right.matched_lines_
		matches_:             left.matches_ + right.matches_
	}
}
