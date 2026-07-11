module cli

import io
import os
import strings
import time

$if !windows {
	#include <unistd.h>
}

#include <errno.h>

enum CommandErrorKind {
	io
	stderr
}

/// An error that can occur while running a command and reading its output.
///
/// This error can be seamlessly converted to an `io::Error` via a `From`
/// implementation.
pub struct CommandError implements IClone {
	kind    CommandErrorKind
	message string
	bytes   []u8
}

/// Create an error from an I/O error.
pub fn CommandError.io(ioerr IError) CommandError {
	return CommandError{
		kind:    .io
		message: ioerr.msg()
	}
}

/// Create an error from the contents of stderr (which may be empty).
pub fn CommandError.stderr(bytes []u8) CommandError {
	return CommandError{
		kind:  .stderr
		bytes: bytes.clone()
	}
}

/// Returns true if and only if this error has empty data from stderr.
pub fn (err CommandError) is_empty() bool {
	return err.kind == .stderr && err.bytes.len == 0
}

pub fn (err CommandError) msg() string {
	if err.kind == .io {
		return err.message
	}
	msg := err.bytes.bytestr().trim_space()
	if msg.len == 0 {
		return '<stderr is empty>'
	}
	div := strings.repeat(`-`, 79)
	return '\n${div}\n${msg}\n${div}'
}

pub fn (err CommandError) code() int {
	_ = err
	return 0
}

pub fn (err CommandError) str() string {
	return err.msg()
}

/// A command to execute.
///
/// V-specific: Rust uses `std::process::Command` directly. This port keeps a
/// small command builder so callers can construct commands without depending
/// on V's process representation.
pub struct Command implements IClone {
pub mut:
	program         string
	args            []string
	work_folder     string
	has_work_folder bool
	env             map[string]string
	has_env         bool
	stdin_path      string
	has_stdin_path  bool
}

/// Create a new command that runs `program`.
pub fn Command.new(program string) Command {
	return Command{
		program: program.to_owned()
		env:     map[string]string{}
	}
}

/// Add one argument to this command.
pub fn (mut command Command) arg(arg string) &Command {
	command.args << arg.to_owned()
	return &command
}

/// Add multiple arguments to this command.
pub fn (mut command Command) args(args []string) &Command {
	for arg in args {
		command.args << arg.to_owned()
	}
	return &command
}

/// Set the initial working folder for this command.
pub fn (mut command Command) current_dir(path string) &Command {
	command.work_folder = path.to_owned()
	command.has_work_folder = true
	return &command
}

/// Set an environment variable for this command.
pub fn (mut command Command) env(key string, value string) &Command {
	command.env[key] = value.to_owned()
	command.has_env = true
	return &command
}

/// Set environment variables for this command.
pub fn (mut command Command) envs(envs map[string]string) &Command {
	for key, value in envs {
		command.env[key] = value.to_owned()
	}
	command.has_env = true
	return &command
}

/// Use the file at `path` as the command's stdin.
pub fn (mut command Command) stdin_path(path string) &Command {
	command.stdin_path = path.to_owned()
	command.has_stdin_path = true
	return &command
}

/// Configures and builds a streaming reader for process output.
pub struct CommandReaderBuilder implements IClone {
mut:
	async_stderr bool
}

/// Create a new builder with the default configuration.
pub fn CommandReaderBuilder.new() CommandReaderBuilder {
	return CommandReaderBuilder{
		async_stderr: true
	}
}

pub fn (builder CommandReaderBuilder) clone() CommandReaderBuilder {
	return CommandReaderBuilder{
		async_stderr: builder.async_stderr
	}
}

/// Build a new streaming reader for the given command's output.
///
/// The caller should set everything that's required on the given command
/// before building a reader, such as its arguments, environment and
/// current working directory. Settings such as the stdout and stderr (but
/// not stdin) pipes will be overridden so that they can be controlled by
/// the reader.
///
/// If there was a problem spawning the given command, then its error is
/// returned.
pub fn (builder CommandReaderBuilder) build(command Command) !CommandReader {
	if command.has_stdin_path {
		$if !windows {
			return builder.build_with_stdin_path(command)
		}
	}
	mut process := os.new_process(command.program)
	process.set_args(command.args.clone())
	if command.has_work_folder {
		process.set_work_folder(command.work_folder)
	}
	if command.has_env {
		process.set_environment(command.env)
	}
	$if windows {
		if command.has_stdin_path {
			process.set_stdin_path(command.stdin_path)
		}
	}
	process.set_redirect_stdio()
	process.run()
	if process.err.len > 0 {
		process.close()
		return error(CommandError.io(error(process.err)).msg())
	}
	stderr := if builder.async_stderr {
		StderrReader.new_async(mut process)
	} else {
		StderrReader.sync()
	}
	return CommandReader{
		process:     process
		has_process: true
		stderr:      stderr
	}
}

fn (builder CommandReaderBuilder) build_with_stdin_path(command Command) !CommandReader {
	_ = builder
	mut stdin_file := os.open(command.stdin_path) or { return error(CommandError.io(err).msg()) }
	mut stdout_pipe := os.pipe() or {
		stdin_file.close()
		return error(CommandError.io(err).msg())
	}
	mut stderr_pipe := os.pipe() or {
		stdin_file.close()
		stdout_pipe.close()
		return error(CommandError.io(err).msg())
	}
	env := command_environment(command)
	program := command_program_path(command, env) or {
		stdin_file.close()
		stdout_pipe.close()
		stderr_pipe.close()
		return error(CommandError.io(err).msg())
	}
	pid := os.fork()
	if pid < 0 {
		stdin_file.close()
		stdout_pipe.close()
		stderr_pipe.close()
		return error(CommandError.io(error('fork failed')).msg())
	}
	if pid == 0 {
		command_exec_child(command, program, env, stdin_file.fd, stdout_pipe.write_fd,
			stderr_pipe.write_fd, stdout_pipe.read_fd, stderr_pipe.read_fd)
		exit(1)
	}
	stdin_file.close()
	os.fd_close(stdout_pipe.write_fd)
	stdout_pipe.write_fd = -1
	os.fd_close(stderr_pipe.write_fd)
	stderr_pipe.write_fd = -1
	mut process := os.new_process(command.program)
	process.pid = pid
	process.status = .running
	process.code = -1
	process.args = command.args.clone()
	process.work_folder = if command.has_work_folder { command.work_folder.clone() } else { '' }
	process.env_is_custom = true
	process.env = env.clone()
	process.use_stdio_ctl = true
	process.stdio_fd = [-1, stdout_pipe.read_fd, stderr_pipe.read_fd]!
	stderr := if builder.async_stderr {
		StderrReader.new_async(mut process)
	} else {
		StderrReader.sync()
	}
	return CommandReader{
		process:     process
		has_process: true
		stderr:      stderr
	}
}

fn command_environment(command Command) []string {
	envs := if command.has_env { command.env.clone() } else { os.environ() }
	mut entries := []string{}
	for key, value in envs {
		entries << '${key}=${value}'
	}
	return entries
}

fn command_env_value(env []string, name string) ?string {
	prefix := '${name}='
	for entry in env {
		if entry.starts_with(prefix) {
			return entry[prefix.len..]
		}
	}
	return none
}

fn command_program_path(command Command, env []string) !string {
	program := command.program
	if os.is_abs_path(program) {
		return program.to_owned()
	}
	if program.contains(os.path_separator) {
		if command.has_work_folder {
			return os.abs_path(program)
		}
		return program.to_owned()
	}
	path_env := command_env_value(env, 'PATH') or { return os.find_abs_path_of_executable(program) }
	for dir in path_env.split(os.path_delimiter) {
		candidate := os.join_path(dir, program)
		if os.is_file(candidate) && os.is_executable(candidate) {
			return candidate
		}
	}
	return os.find_abs_path_of_executable(program)
}

fn command_exec_child(command Command, program string, env []string, stdin_fd int, stdout_write_fd int, stderr_write_fd int, stdout_read_fd int, stderr_read_fd int) {
	os.fd_close(stdout_read_fd)
	os.fd_close(stderr_read_fd)
	if os.fd_dup2(stdin_fd, 0) == -1 {
		eprintln(os.posix_get_error_msg(C.errno))
		exit(1)
	}
	if os.fd_dup2(stdout_write_fd, 1) == -1 {
		eprintln(os.posix_get_error_msg(C.errno))
		exit(1)
	}
	if os.fd_dup2(stderr_write_fd, 2) == -1 {
		eprintln(os.posix_get_error_msg(C.errno))
		exit(1)
	}
	os.fd_close(stdin_fd)
	os.fd_close(stdout_write_fd)
	os.fd_close(stderr_write_fd)
	if command.has_work_folder {
		os.chdir(command.work_folder) or {
			eprintln(err.msg())
			exit(1)
		}
	}
	os.execve(program, command.args, env) or {
		eprintln(err.msg())
		exit(1)
	}
}

/// When enabled, the reader will asynchronously read the contents of the
/// command's stderr output. When disabled, stderr is only read after the
/// stdout stream has been exhausted (or if the process quits with an error
/// code).
///
/// Note that when enabled, this may require launching an additional
/// thread in order to read stderr. This is done so that the process being
/// executed is never blocked from writing to stdout or stderr. If this is
/// disabled, then it is possible for the process to fill up the stderr
/// buffer and deadlock.
///
/// This is enabled by default.
pub fn (mut builder CommandReaderBuilder) async_stderr(yes bool) &CommandReaderBuilder {
	builder.async_stderr = yes
	return &builder
}

/// A streaming reader for a command's output.
///
/// The purpose of this reader is to provide an easy way to execute processes
/// whose stdout is read in a streaming way while also making the processes'
/// stderr available when the process fails with an exit code. This makes it
/// possible to execute processes while surfacing the underlying failure mode
/// in the case of an error.
///
/// Moreover, by default, this reader will asynchronously read the processes'
/// stderr. This prevents subtle deadlocking bugs for noisy processes that
/// write a lot to stderr. Currently, the entire contents of stderr is read
/// on to the heap.
///
/// # Example
///
/// This example shows how to invoke `gzip` to decompress the contents of a
/// file. If the `gzip` command reports a failing exit status, then its stderr
/// is returned as an error.
///
/// ```no_run
/// use std::{io::Read, process::Command};
///
/// use grep_cli::CommandReader;
///
/// let mut cmd = Command::new("gzip");
/// cmd.arg("-d").arg("-c").arg("/usr/share/man/man1/ls.1.gz");
///
/// let mut rdr = CommandReader::new(&mut cmd)?;
/// let mut contents = vec![];
/// rdr.read_to_end(&mut contents)?;
/// # Ok::<(), Box<dyn std::error::Error>>(())
/// ```
pub struct CommandReader implements Drop {
mut:
	process       os.Process
	has_process   bool
	stderr        StderrReader
	stdout_buffer []u8
	stdout_pos    int
	stdout_closed bool
	closed        bool
	close_error   ?string
	/// This is set to true once 'read' returns zero bytes. When this isn't
	/// set and we close the reader, then we anticipate a pipe error when
	/// reaping the child process and silence it.
	eof bool
}

/// Create a new streaming reader for the given command using the default
/// configuration.
///
/// The caller should set everything that's required on the given command
/// before building a reader, such as its arguments, environment and
/// current working directory. Settings such as the stdout and stderr (but
/// not stdin) pipes will be overridden so that they can be controlled by
/// the reader.
///
/// If there was a problem spawning the given command, then its error is
/// returned.
///
/// If the caller requires additional configuration for the reader
/// returned, then use [`CommandReaderBuilder`].
pub fn CommandReader.new(command Command) !CommandReader {
	return CommandReaderBuilder.new().build(command)
}

/// Closes the CommandReader, freeing any resources used by its underlying
/// child process. If the child process exits with a nonzero exit code, the
/// returned Err value will include its stderr.
///
/// `close` is idempotent, meaning it can be safely called multiple times.
/// The first call closes the CommandReader and any subsequent calls do
/// nothing.
///
/// This method should be called after partially reading a file to prevent
/// resource leakage. However there is no need to call `close` explicitly
/// if your code always calls `read` to EOF, as `read` takes care of
/// calling `close` in this case.
///
pub fn (mut reader CommandReader) close() ! {
	if reader.closed {
		if msg := reader.close_error {
			return error(msg)
		}
		return
	}
	reader.closed = true
	if !reader.has_process {
		return
	}
	// Dropping stdout closes the underlying file descriptor, which should
	// cause a well-behaved child process to exit. If child.stdout is None
	// we assume that close() has already been called and do nothing.
	reader.close_stdout()
	if reader.process.status in [.running, .stopped] {
		reader.process.wait()
	}
	if reader.process.code == 0 {
		reader.finish_stderr()
		reader.process.close()
		reader.has_process = false
		return
	}
	err := reader.read_stderr_to_end()
	reader.process.close()
	reader.has_process = false
	// In the specific case where we haven't consumed the full data
	// from the child process, then closing stdout above results in
	// a pipe signal being thrown in most cases. But I don't think
	// there is any reliable and portable way of detecting it. Instead,
	// if we know we haven't hit EOF (so we anticipate a broken pipe
	// error) and if stderr otherwise doesn't have anything on it, then
	// we assume total success.
	if !reader.eof && err.is_empty() {
		return
	}
	msg := err.msg()
	reader.close_error = msg.to_owned()
	return error(msg)
}

fn (mut reader CommandReader) drop() {
	reader.close() or {}
}

@[unsafe]
pub fn (mut reader CommandReader) free() {
	reader.drop()
}

pub fn (mut reader CommandReader) read(mut buf []u8) !int {
	return reader.read_impl(mut buf, true)
}

/// Read stdout for a searcher that will explicitly call `close` after it has
/// produced a search result.
///
/// V-specific: this preserves Rust's separation between reading process
/// stdout and checking the process exit status. A nonzero child status is
/// remembered by `close`, but this read path reports EOF so the searcher can
/// finish normally.
pub fn (mut reader CommandReader) read_for_search(mut buf []u8) !int {
	return reader.read_impl(mut buf, false)
}

fn (mut reader CommandReader) read_impl(mut buf []u8, report_close_error bool) !int {
	if buf.len == 0 {
		return 0
	}
	if reader.closed || !reader.has_process {
		return io.Eof{}
	}
	if reader.stdout_pos < reader.stdout_buffer.len {
		return reader.read_from_stdout_buffer(mut buf)
	}
	for {
		if out := reader.process.pipe_read(.stdout) {
			if out.len > 0 {
				reader.stdout_buffer = out.bytes()
				reader.stdout_pos = 0
				return reader.read_from_stdout_buffer(mut buf)
			}
		}
		if !reader.process.is_alive() {
			if out := reader.process.pipe_read(.stdout) {
				if out.len > 0 {
					reader.stdout_buffer = out.bytes()
					reader.stdout_pos = 0
					return reader.read_from_stdout_buffer(mut buf)
				}
			}
			reader.eof = true
			if !report_close_error {
				return io.Eof{}
			}
			reader.close() or { return error(err.msg()) }
			return io.Eof{}
		}
		time.sleep(10 * time.millisecond)
	}
	return io.Eof{}
}

fn (mut reader CommandReader) read_from_stdout_buffer(mut buf []u8) int {
	nread := copy(mut buf, reader.stdout_buffer[reader.stdout_pos..])
	reader.stdout_pos += nread
	if reader.stdout_pos >= reader.stdout_buffer.len {
		reader.stdout_buffer = []u8{}
		reader.stdout_pos = 0
	}
	return nread
}

fn (mut reader CommandReader) close_stdout() {
	if reader.stdout_closed || !reader.has_process {
		return
	}
	close_process_pipe(mut reader.process, .stdout)
	reader.stdout_closed = true
}

fn close_process_pipe(mut process os.Process, kind os.ChildProcessPipeKind) {
	$if !windows {
		idx := int(kind)
		if process.stdio_fd[idx] != -1 {
			os.fd_close(process.stdio_fd[idx])
			process.stdio_fd[idx] = -1
		}
	}
}

fn (mut reader CommandReader) read_stderr_available() {
	if !reader.has_process || reader.stderr.done {
		return
	}
	if reader.stderr.kind == .async {
		return
	}
	for {
		if chunk := reader.process.pipe_read(.stderr) {
			if chunk.len == 0 {
				return
			}
			reader.stderr.bytes << chunk.bytes()
		} else {
			return
		}
	}
}

/// Consumes all of stderr on to the heap and returns it as an error.
///
/// If there was a problem reading stderr itself, then this returns an I/O
/// command error.
fn (mut reader CommandReader) read_stderr_to_end() CommandError {
	if reader.stderr.done || !reader.has_process {
		return CommandError.stderr(reader.stderr.bytes)
	}
	if reader.stderr.kind == .async {
		reader.finish_stderr()
		return CommandError.stderr(reader.stderr.bytes)
	}
	reader.read_stderr_available()
	tail := reader.process.stderr_slurp()
	if tail.len > 0 {
		reader.stderr.bytes << tail.bytes()
	}
	reader.stderr.done = true
	return CommandError.stderr(reader.stderr.bytes)
}

fn (mut reader CommandReader) finish_stderr() {
	if reader.stderr.done {
		return
	}
	if reader.stderr.kind == .async {
		reader.stderr.bytes = <-reader.stderr.done_chan
		reader.stderr.done = true
		return
	}
	reader.read_stderr_to_end()
}

enum StderrReaderKind {
	async
	sync
}

/// A reader that encapsulates the asynchronous or synchronous reading of
/// stderr.
struct StderrReader {
	kind StderrReaderKind
mut:
	bytes     []u8
	done      bool
	done_chan chan []u8
}

/// Create a reader for stderr that reads contents asynchronously.
///
/// V-specific: the Unix implementation drains the stderr file descriptor on a
/// dedicated thread. Other platforms fall back to synchronous stderr reads.
fn StderrReader.new_async(mut process os.Process) StderrReader {
	$if !windows {
		fd := process.stdio_fd[2]
		if fd != -1 {
			process.stdio_fd[2] = -1
			done_chan := chan []u8{cap: 1}
			spawn stderr_drain_fd(fd, done_chan)
			return StderrReader{
				kind:      .async
				done_chan: done_chan
			}
		}
	}
	return StderrReader.sync()
}

fn stderr_drain_fd(fd int, done_chan chan []u8) {
	mut bytes := []u8{}
	for {
		chunk, nread := os.fd_read(fd, 4096)
		if nread <= 0 {
			break
		}
		bytes << chunk.bytes()
	}
	os.fd_close(fd)
	done_chan <- bytes
}

/// Create a reader for stderr that reads contents synchronously.
fn StderrReader.sync() StderrReader {
	done_chan := chan []u8{cap: 1}
	return StderrReader{
		kind:      .sync
		done_chan: done_chan
	}
}
