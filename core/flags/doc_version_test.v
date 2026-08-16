module flags

fn test_generate_version_short_starts_with_program_name() {
	assert generate_version_short().starts_with('ripgrep 15.1.0')
}

fn test_generate_version_pcre2_reports_availability() {
	text, available := generate_version_pcre2()
	$if pcre2 ? {
		assert available
		assert text.contains('PCRE2')
		assert text.contains('is available')
	} $else {
		assert !available
		assert text.contains('PCRE2 is not available')
	}
}

fn test_generate_version_long_contains_features_and_pcre2() {
	text := generate_version_long()
	assert text.contains('features:')
	assert text.contains('PCRE2')
	$if arm64 {
		assert text.contains('simd(compile):+NEON')
		assert text.contains('simd(runtime):+NEON')
		assert !text.contains('SSE2')
	}
}
