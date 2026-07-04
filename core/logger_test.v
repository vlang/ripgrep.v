module core

fn test_logger_init_and_enabled() {
	Logger.init() or { panic(err) }
	logger := Logger{}
	assert logger.enabled()
	logger.flush()
}
