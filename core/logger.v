module core

/// The simplest possible logger that logs to stderr.
///
/// This logger does no filtering. Instead, it relies on the `log` crates
/// filtering via its global max_level setting.
pub struct Logger {}

/// A singleton used as the target for an implementation of the `Log` trait.
const logger = Logger{}

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
	if path := file {
		if line_number := line {
			eprintln('${level}|${target}|${path}:${line_number}: ${message}')
			return
		}
		eprintln('${level}|${target}|${path}: ${message}')
		return
	}
	eprintln('${level}|${target}: ${message}')
}

pub fn (logger Logger) flush() {
	_ = logger
	// We use eprintln_locked! which is flushed on every call.
}
