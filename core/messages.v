module core

import sync.stdatomic

$if windows {
	#include <io.h>
}

$if !windows {
	#include <unistd.h>
}

#include <errno.h>
#include "@VMODROOT/core/messages_lock.h"

const messages_errno_eintr = 4
const messages_errno_epipe = 32

$if windows {
	fn C._write(fd int, buf voidptr, count int) int
}

$if !windows {
	fn C.write(fd int, buf voidptr, count int) int
}

const messages_state = stdatomic.new_atomic(false)
const ignore_messages_state = stdatomic.new_atomic(false)
const errored_state = stdatomic.new_atomic(false)

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

/// Like eprintln, but flushes stdout before writing stderr.
pub fn eprintln_locked(msg string) {
	write_stderr_line('rg: ${msg}')
}

fn write_stderr_line(msg string) {
	C.rg_messages_lock()
	defer {
		C.rg_messages_unlock()
	}
	flush_stdout()
	write_stderr_all(msg.bytes())
	write_stderr_all('\n'.bytes())
}

fn write_stderr_all(buf []u8) {
	mut written_total := 0
	for written_total < buf.len {
		ptr := unsafe { voidptr(usize(buf.data) + usize(written_total)) }
		C.errno = 0
		written := $if windows {
			int(C._write(2, ptr, buf.len - written_total))
		} $else {
			int(C.write(2, ptr, buf.len - written_total))
		}
		if written < 0 {
			mut code := int(C.errno)
			$if !windows {
				if code == 0 {
					code = messages_errno_epipe
				}
			}
			if code == messages_errno_eintr {
				continue
			}
			if code == messages_errno_epipe {
				exit(0)
			}
			exit(2)
		}
		if written == 0 {
			exit(2)
		}
		written_total += written
	}
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
	return messages_state_ref().load()
}

/// Set whether messages should be shown or not.
///
/// By default, they are not shown.
pub fn set_messages(yes bool) {
	messages_state_ref().store(yes)
}

/// Returns true if and only if "ignore" related messages should be shown.
pub fn ignore_messages() bool {
	return ignore_messages_state_ref().load()
}

/// Set whether "ignore" related messages should be shown or not.
///
/// By default, they are not shown.
///
/// Note that this is overridden if `messages` is disabled. Namely, if
/// `messages` is disabled, then "ignore" messages are never shown, regardless
/// of this setting.
pub fn set_ignore_messages(yes bool) {
	ignore_messages_state_ref().store(yes)
}

/// Returns true if and only if ripgrep came across a non-fatal error.
pub fn errored() bool {
	return errored_state_ref().load()
}

/// Indicate that ripgrep has come across a non-fatal error.
///
/// Callers should not use this directly. Instead, it is called automatically
/// via the `err_message` macro.
pub fn set_errored() {
	errored_state_ref().store(true)
}

fn messages_state_ref() &stdatomic.AtomicVal[bool] {
	return messages_state
}

fn ignore_messages_state_ref() &stdatomic.AtomicVal[bool] {
	return ignore_messages_state
}

fn errored_state_ref() &stdatomic.AtomicVal[bool] {
	return errored_state
}

fn C.rg_messages_lock()
fn C.rg_messages_unlock()
