module cli

fn test_print_hostname() {
	name := hostname() or { panic(err) }
	assert name.len > 0
}
