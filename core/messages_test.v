module core

fn test_messages_default_to_false() {
	assert !messages()
	assert !ignore_messages()
	assert !errored()
}

fn test_messages_setters() {
	set_messages(true)
	assert messages()
	set_messages(false)
	assert !messages()

	set_ignore_messages(true)
	assert ignore_messages()
	set_ignore_messages(false)
	assert !ignore_messages()
}

fn test_set_errored() {
	set_errored()
	assert errored()
}
