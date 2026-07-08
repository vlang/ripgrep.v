module integration

import os
import time

const test_dir = 'ripgrep-v-integration-tests'

/// Setup an empty work directory and return a command pointing to the ripgrep
/// executable whose CWD is set to the work directory.
///
/// The name given will be used to create the directory. Generally, it should
/// correspond to the test name.
fn setup(test_name string) (Dir, TestCommand) {
	dir := Dir.new(test_name)
	cmd := dir.command()
	return dir, cmd
}

/// Break the given string into lines, sort them and then join them back
/// together. This is useful for testing output from ripgrep that may not
/// always be in the same order.
fn sort_lines(lines string) string {
	mut split := lines.trim_space().split_into_lines()
	split.sort()
	return '${split.join('\n')}\n'
}

/// Returns true if and only if the given program can be successfully executed
/// with a `--help` flag.
fn cmd_exists(program string) bool {
	result := os.execute('${sh_quote(program)} --help > /dev/null 2>&1')
	return result.exit_code == 0
}

fn test_data_bytes(name string) []u8 {
	path := os.join_path(@VMODROOT, 'integration', 'data', name)
	return os.read_bytes(path) or { panic('${path}: ${err.msg()}') }
}

/// Dir represents a directory in which tests should be run.
///
/// Directories are created from a process/time based suffix to avoid
/// duplicates.
struct Dir {
	/// The directory in which the test should run. If a test needs to create
	/// files, they should go in here. This directory is also used as the CWD
	/// for any processes created by the test.
	dir string
	/// Set to true when the test should use PCRE2 as the regex engine.
	pcre2 bool
}

fn Dir.new(name string) Dir {
	id := '${os.getpid()}_${time.now().unix_milli()}'
	dir := os.join_path(os.temp_dir(), test_dir, name, id)
	if os.exists(dir) {
		os.rmdir_all(dir) or { panic('${dir}: ${err.msg()}') }
	}
	os.mkdir_all(dir) or { panic('${dir}: ${err.msg()}') }
	return Dir{
		dir:   dir
		pcre2: false
	}
}

/// Use PCRE2 for this test.
fn (mut dir Dir) pcre2(yes bool) {
	dir.pcre2 = yes
}

/// Returns true if and only if this test is configured to use PCRE2 as
/// the regex engine.
fn (dir Dir) is_pcre2() bool {
	return dir.pcre2
}

/// Create a new file with the given name and contents in this directory,
/// or panic on error.
fn (dir Dir) create(name string, contents string) {
	path := os.join_path(dir.dir, name)
	parent := os.dir(path)
	os.mkdir_all(parent) or { panic('${parent}: ${err.msg()}') }
	os.write_file(path, contents) or { panic('${path}: ${err.msg()}') }
}

/// Create a new file with the given name and contents in this directory,
/// or panic on error.
fn (dir Dir) create_bytes(name string, contents []u8) {
	path := os.join_path(dir.dir, name)
	parent := os.dir(path)
	os.mkdir_all(parent) or { panic('${parent}: ${err.msg()}') }
	os.write_file_array(path, contents) or { panic('${path}: ${err.msg()}') }
}

/// Try to create a new file with the given name and contents in this
/// directory.
fn (dir Dir) try_create_bytes(name string, contents []u8) bool {
	path := os.join_path(dir.dir, name)
	parent := os.dir(path)
	os.mkdir_all(parent) or { return false }
	os.write_file_array(path, contents) or { return false }
	return true
}

/// Create a new file with the given name and size.
fn (dir Dir) create_size(name string, filesize u64) {
	path := os.join_path(dir.dir, name)
	parent := os.dir(path)
	os.mkdir_all(parent) or { panic('${parent}: ${err.msg()}') }
	os.write_file(path, '') or { panic('${path}: ${err.msg()}') }
	os.truncate(path, filesize) or { panic('${path}: ${err.msg()}') }
}

/// Remove a file with the given name from this directory.
fn (dir Dir) remove(name string) {
	path := os.join_path(dir.dir, name)
	os.rm(path) or { panic('${path}: ${err.msg()}') }
}

/// Create a new directory with the given path (and any directories above
/// it) inside this directory.
fn (dir Dir) create_dir(path string) {
	full := os.join_path(dir.dir, path)
	os.mkdir_all(full) or { panic('${full}: ${err.msg()}') }
}

/// Creates a directory symlink to the src with the given target name
/// in this directory.
fn (dir Dir) link_dir(src string, target string) {
	src_path := os.join_path(dir.dir, src)
	target_path := os.join_path(dir.dir, target)
	os.rm(target_path) or {}
	os.symlink(src_path, target_path) or { panic('${target_path}: ${err.msg()}') }
}

/// Creates a file symlink to the src with the given target name
/// in this directory.
fn (dir Dir) link_file(src string, target string) {
	dir.link_dir(src, target)
}

/// Creates a new command that is set to use the ripgrep executable in
/// this working directory.
///
/// This also:
///
/// * Unsets the `RIPGREP_CONFIG_PATH` environment variable.
/// * Sets the `--path-separator` to `/` so that paths have the same output
///   on all systems. Tests that need to check `--path-separator` itself
///   can simply pass it again to override it.
fn (dir Dir) command() TestCommand {
	mut argv := ['--path-separator', '/']
	if dir.is_pcre2() {
		argv << '--pcre2'
	}
	return TestCommand{
		dir:  dir
		argv: argv
		env:  map[string]string{}
	}
}

/// Returns the path to this directory.
fn (dir Dir) path() string {
	return dir.dir
}

struct CommandOutput {
	code         int
	stdout       string
	stderr       string
	stdout_bytes []u8
	stderr_bytes []u8
}

/// A simple wrapper around a process command with some conveniences.
struct TestCommand {
	/// The dir used to launched this command.
	dir Dir
mut:
	/// The arguments passed to ripgrep.
	argv []string
	/// Environment variables set for this command.
	env map[string]string
}

/// Add an argument to pass to the command.
fn (mut cmd TestCommand) arg(arg string) &TestCommand {
	cmd.argv << arg
	return &cmd
}

/// Add any number of arguments to the command.
fn (mut cmd TestCommand) args(args []string) &TestCommand {
	cmd.argv << args
	return &cmd
}

/// Set an environment variable for this command.
fn (mut cmd TestCommand) env(key string, value string) &TestCommand {
	cmd.env[key] = value
	return &cmd
}

/// Set the working directory for this command.
///
/// The path given is interpreted relative to the directory that this
/// command was created for.
///
/// Note that this does not need to be called normally, since the creation
/// of this TestCommand causes its working directory to be set to the
/// test's directory automatically.
fn (mut cmd TestCommand) current_dir(dir string) &TestCommand {
	cmd.dir = Dir{
		dir:   os.join_path(cmd.dir.path(), dir)
		pcre2: cmd.dir.pcre2
	}
	return &cmd
}

/// Runs and captures the stdout of the given command.
fn (mut cmd TestCommand) stdout() string {
	o := cmd.output()
	return o.stdout
}

/// Pipe `input` to a command, and collect the output.
fn (mut cmd TestCommand) pipe(input []u8) string {
	stdin_path := temp_path('stdin')
	os.write_file_array(stdin_path, input) or { panic('${stdin_path}: ${err.msg()}') }
	o := cmd.output_with_stdin(stdin_path)
	os.rm(stdin_path) or {}
	return o.stdout
}

/// Gets the output of a command. If the command failed, then this panics.
fn (mut cmd TestCommand) output() CommandOutput {
	output := cmd.raw_output()
	return cmd.expect_success(output)
}

fn (mut cmd TestCommand) output_with_stdin(stdin_path string) CommandOutput {
	output := cmd.raw_output_with_stdin(stdin_path)
	return cmd.expect_success(output)
}

/// Gets the raw output of a command after filtering nonsense like jemalloc
/// error messages from stderr.
fn (mut cmd TestCommand) raw_output() CommandOutput {
	return cmd.raw_output_with_redirect(none)
}

fn (mut cmd TestCommand) raw_output_with_stdin(stdin_path string) CommandOutput {
	return cmd.raw_output_with_redirect(stdin_path)
}

/// Runs the command and asserts that it resulted in an error exit code.
fn (mut cmd TestCommand) assert_err() {
	o := cmd.raw_output()
	if o.code == 0 {
		panic(command_failure_message(cmd, o, 'command succeeded but expected failure!'))
	}
}

/// Runs the command and asserts that its exit code matches expected exit
/// code.
fn (mut cmd TestCommand) assert_exit_code(expected_code int) {
	o := cmd.raw_output()
	if o.code != expected_code {
		panic(command_failure_message(cmd, o,
			'expected exit code ${expected_code} but found ${o.code}'))
	}
}

/// Runs the command and asserts that something was printed to stderr.
fn (mut cmd TestCommand) assert_non_empty_stderr() {
	o := cmd.raw_output()
	if o.code == 0 || o.stderr.len == 0 {
		panic(command_failure_message(cmd, o,
			'command succeeded or stderr was empty but expected failure!'))
	}
}

fn (mut cmd TestCommand) expect_success(o CommandOutput) CommandOutput {
	if o.code != 0 {
		panic(command_failure_message(cmd, o, 'command failed but expected success!'))
	}
	return o
}

fn (mut cmd TestCommand) raw_output_with_redirect(stdin_path ?string) CommandOutput {
	mut words := []string{cap: cmd.argv.len + 1}
	words << sh_quote(rg_binary())
	for arg in cmd.argv {
		words << sh_quote(arg)
	}
	stdout_path := temp_path('stdout')
	stderr_path := temp_path('stderr')
	mut env_words := []string{}
	for key, value in cmd.env {
		env_words << '${key}=${sh_quote(value)}'
	}
	env_prefix := if env_words.len == 0 { '' } else { '${env_words.join(' ')} ' }
	mut line := 'cd ${sh_quote(cmd.dir.path())} && ${env_prefix}${words.join(' ')}'
	path := stdin_path or { '' }
	if path.len > 0 {
		line += ' < ${sh_quote(path)}'
	}
	line += ' > ${sh_quote(stdout_path)} 2> ${sh_quote(stderr_path)}'
	if os.getenv_opt('RGV_TRACE') != none {
		eprintln(line)
	}
	result := os.execute(line)
	stdout_bytes := os.read_bytes(stdout_path) or { []u8{} }
	stderr_bytes := os.read_bytes(stderr_path) or { []u8{} }
	stdout := utf8_lossy(stdout_bytes)
	stderr := strip_jemalloc_nonsense(utf8_lossy(stderr_bytes))
	os.rm(stdout_path) or {}
	os.rm(stderr_path) or {}
	return CommandOutput{
		code:         result.exit_code
		stdout:       stdout
		stderr:       stderr
		stdout_bytes: stdout_bytes
		stderr_bytes: stderr_bytes
	}
}

fn command_failure_message(cmd TestCommand, o CommandOutput, message string) string {
	return '\n\n==========\n${message}\n\ncommand: ${cmd.argv}\n\ncwd: ${cmd.dir.path()}\n\ndir list: ${dir_list(cmd.dir.path())}\n\nstatus: ${o.code}\n\nstdout: ${o.stdout}\n\nstderr: ${o.stderr}\n\n==========\n'
}

fn dir_list(path string) []string {
	mut paths := []string{}
	os.walk(path, fn [mut paths] (entry string) {
		paths << entry
	})
	return paths
}

fn rg_binary() string {
	if bin := os.getenv_opt('RGV_BIN') {
		return bin
	}
	out := os.join_path(os.temp_dir(), 'ripgrep_v_integration_rg')
	source := @VMODROOT
	if should_use_cached_rg_binary(out) {
		return out
	}
	vbin := if custom := os.getenv_opt('RGV_VBIN') {
		custom
	} else if os.exists('/tmp/v3_ownership_rgv') {
		'/tmp/v3_ownership_rgv'
	} else {
		@VEXE
	}
	command := '${sh_quote(vbin)} -ownership -o ${sh_quote(out)} ${sh_quote(source)}'
	result := os.execute(command)
	if result.exit_code != 0 || !os.exists(out) || os.file_size(out) == 0 {
		panic('failed to build integration rg binary with `${command}`:\n${result.output}')
	}
	return out
}

fn should_use_cached_rg_binary(out string) bool {
	if os.getenv_opt('RGV_REBUILD') != none || !os.exists(out) || os.file_size(out) == 0 {
		return false
	}
	return os.file_last_mod_unix(out) >= newest_v_source_mtime(@VMODROOT)
}

fn newest_v_source_mtime(root string) i64 {
	mut newest := i64(0)
	os.walk(root, fn [mut newest] (entry string) {
		if !entry.ends_with('.v') {
			return
		}
		modified := os.file_last_mod_unix(entry)
		if modified > newest {
			newest = modified
		}
	})
	return newest
}

fn temp_path(label string) string {
	return os.join_path(os.temp_dir(),
		'ripgrep_v_${label}_${os.getpid()}_${time.now().unix_nano()}')
}

fn sh_quote(s string) string {
	mut quoted := "'"
	for b in s.bytes() {
		if b == u8(`'`) {
			quoted += "'\\''"
		} else {
			quoted += [b].bytestr()
		}
	}
	quoted += "'"
	return quoted
}

fn strip_jemalloc_nonsense(data string) string {
	mut kept := []string{}
	for line in data.split_into_lines() {
		if !line.starts_with('<jemalloc>:') {
			kept << line
		}
	}
	if kept.len == 0 {
		return ''
	}
	return kept.join('\n') + '\n'
}

fn utf8_lossy(data []u8) string {
	mut out := []u8{cap: data.len}
	mut i := 0
	for i < data.len {
		len := valid_utf8_sequence_len(data, i)
		if len > 0 {
			out << data[i..i + len]
			i += len
		} else {
			out << [u8(0xef), 0xbf, 0xbd]
			i++
		}
	}
	return out.bytestr()
}

fn valid_utf8_sequence_len(data []u8, i int) int {
	b0 := data[i]
	if b0 < 0x80 {
		return 1
	}
	if b0 >= 0xc2 && b0 <= 0xdf {
		if has_continuation(data, i, 1) {
			return 2
		}
		return 0
	}
	if b0 == 0xe0 {
		if i + 2 < data.len && data[i + 1] >= 0xa0 && data[i + 1] <= 0xbf
			&& is_utf8_continuation(data[i + 2]) {
			return 3
		}
		return 0
	}
	if (b0 >= 0xe1 && b0 <= 0xec) || (b0 >= 0xee && b0 <= 0xef) {
		if has_continuation(data, i, 2) {
			return 3
		}
		return 0
	}
	if b0 == 0xed {
		if i + 2 < data.len && data[i + 1] >= 0x80 && data[i + 1] <= 0x9f
			&& is_utf8_continuation(data[i + 2]) {
			return 3
		}
		return 0
	}
	if b0 == 0xf0 {
		if i + 3 < data.len && data[i + 1] >= 0x90 && data[i + 1] <= 0xbf
			&& is_utf8_continuation(data[i + 2]) && is_utf8_continuation(data[i + 3]) {
			return 4
		}
		return 0
	}
	if b0 >= 0xf1 && b0 <= 0xf3 {
		if has_continuation(data, i, 3) {
			return 4
		}
		return 0
	}
	if b0 == 0xf4 {
		if i + 3 < data.len && data[i + 1] >= 0x80 && data[i + 1] <= 0x8f
			&& is_utf8_continuation(data[i + 2]) && is_utf8_continuation(data[i + 3]) {
			return 4
		}
		return 0
	}
	return 0
}

fn has_continuation(data []u8, i int, n int) bool {
	if i + n >= data.len {
		return false
	}
	for j in 1 .. n + 1 {
		if !is_utf8_continuation(data[i + j]) {
			return false
		}
	}
	return true
}

fn is_utf8_continuation(b u8) bool {
	return b >= 0x80 && b <= 0xbf
}

fn eqnice(expected string, got string) {
	if expected == got {
		return
	}
	panic('\nprinted outputs differ!\n\nexpected:\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n${expected}\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n\ngot:\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n${got}\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n')
}

fn eqnice_repr(expected string, got string) {
	if expected == got {
		return
	}
	panic('\nprinted outputs differ!\n\nexpected:\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n${expected.bytes()}\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n\ngot:\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n${got.bytes()}\n~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\n')
}
