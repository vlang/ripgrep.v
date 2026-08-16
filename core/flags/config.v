module flags

import encoding.utf8
import os

/*
This module provides routines for reading ripgrep config "rc" files.

The primary output of these routines is a sequence of arguments, where each
argument corresponds precisely to one shell argument.
*/

/// Return a sequence of arguments derived from ripgrep rc configuration files.
pub fn config_args() []string {
	config_path := os.getenv_opt('RIPGREP_CONFIG_PATH') or { return []string{} }
	if config_path == '' {
		return []string{}
	}
	args_, errs := parse_config(config_path) or {
		config_message('failed to read the file specified in RIPGREP_CONFIG_PATH: ${err.msg()}')
		return []string{}
	}
	if errs.len > 0 {
		for err in errs {
			config_message('${config_path}:${err}')
		}
	}
	return args_
}

/// Parse a single ripgrep rc file from the given path.
///
/// On success, this returns a set of shell arguments, in order, that should
/// be pre-pended to the arguments given to ripgrep at the command line.
///
/// If the file could not be read, then an error is returned. If there was
/// a problem parsing one or more lines in the file, then errors are returned
/// for each line in addition to successfully parsed arguments.
fn parse_config(path string) !([]string, []string) {
	contents := os.read_bytes(path) or { return error('${path}: ${err.msg()}') }
	return parse_config_reader(contents)
}

/// Parse a single ripgrep rc file from the given reader.
///
/// Callers should not provided a buffered reader, as this routine will use its
/// own buffer internally.
///
/// On success, this returns a set of shell arguments, in order, that should
/// be pre-pended to the arguments given to ripgrep at the command line.
///
/// If the reader could not be read, then an error is returned. If there was a
/// problem parsing one or more lines, then errors are returned for each line
/// in addition to successfully parsed arguments.
fn parse_config_reader(bytes []u8) !([]string, []string) {
	mut args_ := []string{}
	mut errs := []string{}
	mut line_number := 0
	mut start := 0
	for start <= bytes.len {
		mut end := start
		for end < bytes.len && bytes[end] != `\n` {
			end++
		}
		line_number++
		line := trim_ascii_space(bytes[start..end])
		if line.len > 0 && line[0] != `#` {
			$if windows {
				if !is_valid_utf8(line) {
					errs << '${line_number}: stream did not contain valid UTF-8'
				} else {
					args_ << line.bytestr()
				}
			} $else {
				args_ << line.bytestr()
			}
		}
		if end >= bytes.len {
			break
		}
		start = end + 1
	}
	return args_, errs
}

fn trim_ascii_space(bytes []u8) []u8 {
	mut start := 0
	mut end := bytes.len
	for start < end && is_ascii_space(bytes[start]) {
		start++
	}
	for end > start && is_ascii_space(bytes[end - 1]) {
		end--
	}
	return bytes[start..end]
}

fn is_ascii_space(byte u8) bool {
	return byte == ` ` || byte == `\t` || byte == `\n` || byte == `\r` || byte == 0x0b
		|| byte == 0x0c
}

fn is_valid_utf8(bytes []u8) bool {
	if bytes.len == 0 {
		return true
	}
	return utf8.validate(&bytes[0], bytes.len)
}

fn config_message(msg string) {
	eprintln('rg: ${msg}')
}
