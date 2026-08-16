module core

import sync.stdatomic

/// The simplest possible logger that logs to stderr.
///
/// This logger does no filtering. Instead, it relies on the `log` crates
/// filtering via its global max_level setting.
pub struct Logger {}

/// A singleton used as the target for an implementation of the `Log` trait.
const logger = Logger{}
const logger_level_state = stdatomic.new_atomic(0)

pub enum LogLevel {
	off
	debug
	trace
}

/// Create a new logger that logs to stderr and initialize it as the
/// global logger. If there was a problem setting the logger, then an
/// error is returned.
pub fn Logger.init() ! {
	_ = logger
}

pub fn (logger Logger) enabled() bool {
	// We set the log level via log::set_max_level, so we don't need to
	// implement filtering here.
	return true
}

pub fn (logger Logger) log(level string, target string, file ?string, line ?int, message string) {
	_ = logger
	if !log_level_enabled(level) {
		return
	}
	if path := file {
		if line_number := line {
			write_stderr_line('${level}|${target}|${path}:${line_number}: ${message}')
			return
		}
		write_stderr_line('${level}|${target}|${path}: ${message}')
		return
	}
	write_stderr_line('${level}|${target}: ${message}')
}

pub fn (logger Logger) flush() {
	_ = logger
	// We use eprintln_locked! which is flushed on every call.
}

/// Set the maximum log level used by the global logger.
pub fn set_log_level(level LogLevel) {
	logger_level_state_ref().store(int(level))
}

/// Returns true when debug logging is enabled.
pub fn debug_enabled() bool {
	return logger_level_state_ref().load() >= int(LogLevel.debug)
}

/// Returns true when trace logging is enabled.
pub fn trace_enabled() bool {
	return logger_level_state_ref().load() >= int(LogLevel.trace)
}

/// Emit a debug log message through the global logger.
pub fn debug_message(target string, message string) {
	logger.log('DEBUG', target, none, none, message)
}

/// Emit a trace log message through the global logger.
pub fn trace_message(target string, message string) {
	logger.log('TRACE', target, none, none, message)
}

fn log_level_enabled(level string) bool {
	required := match level {
		'TRACE', 'trace' { int(LogLevel.trace) }
		'DEBUG', 'debug' { int(LogLevel.debug) }
		else { int(LogLevel.debug) }
	}
	return logger_level_state_ref().load() >= required
}

fn logger_level_state_ref() &stdatomic.AtomicVal[int] {
	return logger_level_state
}
