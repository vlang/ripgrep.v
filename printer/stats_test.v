module printer

import time

fn test_stats_new_is_zero() {
	stats := Stats.new()
	assert stats.elapsed() == time.Duration(0)
	assert stats.searches() == u64(0)
	assert stats.searches_with_match() == u64(0)
	assert stats.bytes_searched() == u64(0)
	assert stats.bytes_printed() == u64(0)
	assert stats.matched_lines() == u64(0)
	assert stats.matches() == u64(0)
}

fn test_stats_add_methods_and_plus() {
	mut left := Stats.new()
	left.add_elapsed(2 * time.second)
	left.add_searches(1)
	left.add_searches_with_match(2)
	left.add_bytes_searched(3)
	left.add_bytes_printed(4)
	left.add_matched_lines(5)
	left.add_matches(6)

	mut right := Stats.new()
	right.add_elapsed(3 * time.second)
	right.add_searches(10)
	right.add_searches_with_match(20)
	right.add_bytes_searched(30)
	right.add_bytes_printed(40)
	right.add_matched_lines(50)
	right.add_matches(60)

	sum := left + right
	assert sum.elapsed() == 5 * time.second
	assert sum.searches() == u64(11)
	assert sum.searches_with_match() == u64(22)
	assert sum.bytes_searched() == u64(33)
	assert sum.bytes_printed() == u64(44)
	assert sum.matched_lines() == u64(55)
	assert sum.matches() == u64(66)

	mut assigned := left
	assigned += right
	assert assigned.elapsed() == 5 * time.second
	assert assigned.searches() == u64(11)
	assert assigned.searches_with_match() == u64(22)
	assert assigned.bytes_searched() == u64(33)
	assert assigned.bytes_printed() == u64(44)
	assert assigned.matched_lines() == u64(55)
	assert assigned.matches() == u64(66)
}
