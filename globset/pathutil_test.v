module globset

fn test_file_name_ext() {
	assert file_name_ext('foo.rs') or { '' } == '.rs'
	assert file_name_ext('.rs') or { '' } == '.rs'
	assert file_name_ext('..rs') or { '' } == '.rs'
	assert file_name_ext('') == none
	assert file_name_ext('foo') == none
}

fn test_normalize_path() {
	assert normalize_path('foo') == 'foo'
	assert normalize_path('foo/bar') == 'foo/bar'
	$if windows {
		assert normalize_path('foo\\bar') == 'foo/bar'
		assert normalize_path('foo\\bar/baz') == 'foo/bar/baz'
	} $else {
		assert normalize_path('foo\\bar') == 'foo\\bar'
		assert normalize_path('foo\\bar/baz') == 'foo\\bar/baz'
	}
}
