module cli

import io
import os
import strings
import time

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
	program string
	args    []string
}

/// Create a new command that runs `program`.
pub fn Command.new(program string) Command {
	return Command{
		program: program.to_owned()
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

/// Configures and builds a streaming reader for process output.
pub struct CommandReaderBuilder implements IClone {
mut:
	async_stderr bool
}

/// Create a new builder with the default configuration.
pub fn CommandReaderBuilder.new() CommandReaderBuilder {
	return CommandReaderBuilder{}
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
	_ = builder
	$if !windows {
		stdout_path := process_temp_path('stdout')
		stderr_path := process_temp_path('stderr')
		mut words := []string{cap: command.args.len + 1}
		words << shell_quote(command.program)
		for arg in command.args {
			words << shell_quote(arg)
		}
		line := '${words.join(' ')} > ${shell_quote(stdout_path)} 2> ${shell_quote(stderr_path)}'
		result := os.execute(line)
		stdout := os.read_bytes(stdout_path) or { []u8{} }
		stderr := os.read_bytes(stderr_path) or { []u8{} }
		os.rm(stdout_path) or {}
		os.rm(stderr_path) or {}
		return CommandReader{
			stdout:    stdout
			stderr:    stderr
			exit_code: result.exit_code
		}
	}
	mut process := os.new_process(command.program)
	process.set_args(command.args)
	process.set_redirect_stdio()
	process.run()
	if process.err.len > 0 {
		return CommandError.io(error(process.err))
	}
	process.wait()
	stdout := process.stdout_slurp().bytes()
	stderr := process.stderr_slurp().bytes()
	code := process.code
	process.close()
	return CommandReader{
		stdout:    stdout
		stderr:    stderr
		exit_code: code
	}
}

fn process_temp_path(label string) string {
	return os.join_path(os.temp_dir(), 'ripgrep_v_process_${label}_${os.getpid()}_${time.now().unix_nano()}')
}

fn shell_quote(s string) string {
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
pub struct CommandReader implements IClone {
mut:
	stdout    []u8
	stderr    []u8
	pos       int
	exit_code int
	closed    bool
	/// This is set to true once 'read' returns zero bytes. When this isn't
	/// set and we close the reader, then we anticipate a pipe error when
	/// reaping the child process and silence it.
	eof bool
}

/// Create a new streaming reader for the given command using the default
/// configuration.
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
pub fn (mut reader CommandReader) close() ! {
	if reader.closed {
		return
	}
	reader.closed = true
	if reader.exit_code == 0 {
		return
	}
	command_err := CommandError.stderr(reader.stderr)
	if !reader.eof && command_err.is_empty() {
		return
	}
	return command_err
}

pub fn (mut reader CommandReader) read(mut buf []u8) !int {
	if reader.pos >= reader.stdout.len {
		reader.eof = true
		reader.close()!
		return io.Eof{}
	}
	nread := copy(mut buf, reader.stdout[reader.pos..])
	reader.pos += nread
	return nread
}
