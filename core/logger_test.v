module core

fn test_logger_init_and_enabled() {
	Logger.init() or { panic(err) }
	logger := Logger{}
	assert logger.enabled()
	logger.flush()
}

fn test_log_level_state() {
	set_log_level(.off)
	assert !debug_enabled()
	assert !trace_enabled()

	set_log_level(.debug)
	assert debug_enabled()
	assert !trace_enabled()

	set_log_level(.trace)
	assert debug_enabled()
	assert trace_enabled()

	set_log_level(.off)
}
