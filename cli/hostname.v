module cli

import os

/// Returns the hostname of the current system.
///
/// It is unusual, although technically possible, for this routine to return
/// an error. It is difficult to list out the error conditions, but one such
/// possibility is platform support.
///
/// # Platform specific behavior
///
/// On Windows, this currently uses the "physical DNS hostname" computer name.
/// This may change in the future.
///
/// On Unix, this returns the result of the `gethostname` function from the
/// `libc` linked into the program.
pub fn hostname() !string {
	return os.hostname()
}
