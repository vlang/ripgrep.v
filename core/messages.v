@[has_globals]
module core

import sync.stdatomic

__global (
	messages_state        &stdatomic.AtomicVal[bool] = stdatomic.new_atomic(false)
	ignore_messages_state &stdatomic.AtomicVal[bool] = stdatomic.new_atomic(false)
	errored_state         &stdatomic.AtomicVal[bool] = stdatomic.new_atomic(false)
)

/*
This module defines some macros and some light shared mutable state.

This state is responsible for keeping track of whether we should emit certain
kinds of messages to the user (such as errors) that are distinct from the
standard "debug" or "trace" log messages. This state is specifically set at
startup time when CLI arguments are parsed and then never changed.

The other state tracked here is whether ripgrep experienced an error
condition. Aside from errors associated with invalid CLI arguments, ripgrep
generally does not abort when an error occurs (e.g., if reading a file failed).
But when an error does occur, it will alter ripgrep's exit status. Thus, when
an error message is emitted via `err_message`, then a global flag is toggled
indicating that at least one error occurred. When ripgrep exits, this flag is
consulted to determine what the exit status ought to be.
*/

/// Like eprintln, but locks stdout to prevent interleaving lines.
///
/// This locks stdout, not stderr, even though this prints to stderr. This
/// avoids the appearance of interleaving output when stdout and stderr both
/// correspond to a tty.
pub fn eprintln_locked(msg string) {
	eprintln('rg: ${msg}')
}

/// Emit a non-fatal error message, unless messages were disabled.
pub fn message(msg string) {
	if messages() {
		eprintln_locked(msg)
	}
}

/// Like message, but sets ripgrep's "errored" flag, which controls the exit
/// status.
pub fn err_message(msg string) {
	set_errored()
	message(msg)
}

/// Emit a non-fatal ignore-related error message (like a parse error), unless
/// ignore-messages were disabled.
pub fn ignore_message(msg string) {
	if messages() && ignore_messages() {
		eprintln_locked(msg)
	}
}

/// Returns true if and only if messages should be shown.
pub fn messages() bool {
	return messages_state.load()
}

/// Set whether messages should be shown or not.
///
/// By default, they are not shown.
pub fn set_messages(yes bool) {
	messages_state.store(yes)
}

/// Returns true if and only if "ignore" related messages should be shown.
pub fn ignore_messages() bool {
	return ignore_messages_state.load()
}

/// Set whether "ignore" related messages should be shown or not.
///
/// By default, they are not shown.
///
/// Note that this is overridden if `messages` is disabled. Namely, if
/// `messages` is disabled, then "ignore" messages are never shown, regardless
/// of this setting.
pub fn set_ignore_messages(yes bool) {
	ignore_messages_state.store(yes)
}

/// Returns true if and only if ripgrep came across a non-fatal error.
pub fn errored() bool {
	return errored_state.load()
}

/// Indicate that ripgrep has come across a non-fatal error.
///
/// Callers should not use this directly. Instead, it is called automatically
/// via the `err_message` macro.
pub fn set_errored() {
	errored_state.store(true)
}
