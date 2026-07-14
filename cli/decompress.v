module cli

import globset
import io
import os

/// A builder for a matcher that determines which files get decompressed.
pub struct DecompressionMatcherBuilder implements IClone {
	/// The commands for each matching glob.
mut:
	commands []DecompressionCommand
	/// Whether to include the default matching rules.
	defaults bool = true
}

/// A representation of a single command for decompressing data
/// out-of-process.
struct DecompressionCommand implements IClone {
	/// The glob that matches this command.
	glob string
	/// The command or binary name.
	bin string
	/// The arguments to invoke with the command.
	args []string
}

/// Create a new builder for configuring a decompression matcher.
pub fn DecompressionMatcherBuilder.new() DecompressionMatcherBuilder {
	return DecompressionMatcherBuilder{
		commands: []DecompressionCommand{}
		defaults: true
	}
}

/// Build a matcher for determining how to decompress files.
///
/// If there was a problem compiling the matcher, then an error is
/// returned.
pub fn (builder &DecompressionMatcherBuilder) build() !DecompressionMatcher {
	defaults := if builder.defaults {
		default_decompression_commands()
	} else {
		[]DecompressionCommand{}
	}
	mut glob_builder := globset.GlobSetBuilder.new()
	mut commands := []DecompressionCommand{}
	for decomp_cmd in defaults {
		glob := globset.Glob.new(decomp_cmd.glob) or { return CommandError.io(err) }
		glob_builder.add(glob)
		commands << decomp_cmd.clone()
	}
	for decomp_cmd in builder.commands {
		glob := globset.Glob.new(decomp_cmd.glob) or { return CommandError.io(err) }
		glob_builder.add(glob)
		commands << decomp_cmd.clone()
	}
	globs := glob_builder.build() or { return CommandError.io(err) }
	return DecompressionMatcher{
		globs:    globs
		commands: commands
	}
}

/// When enabled, the default matching rules will be compiled into this
/// matcher before any other associations. When disabled, only the
/// rules explicitly given to this builder will be used.
///
/// This is enabled by default.
pub fn (mut builder DecompressionMatcherBuilder) defaults(yes bool) &DecompressionMatcherBuilder {
	builder.defaults = yes
	return &builder
}

/// Associates a glob with a command to decompress files matching the glob.
///
/// If multiple globs match the same file, then the most recently added
/// glob takes precedence.
///
/// The syntax for the glob is documented in the
/// [`globset` crate](https://docs.rs/globset/#syntax).
///
/// The `program` given is resolved with respect to `PATH` and turned
/// into an absolute path internally before being executed by the current
/// platform. Notably, on Windows, this avoids a security problem where
/// passing a relative path to `CreateProcess` will automatically search
/// the current directory for a matching program. If the program could
/// not be resolved, then it is silently ignored and the association is
/// dropped. For this reason, callers should prefer `try_associate`.
pub fn (mut builder DecompressionMatcherBuilder) associate(glob string, program string, args []string) &DecompressionMatcherBuilder {
	builder.try_associate(glob, program, args) or {}
	return &builder
}

/// Associates a glob with a command to decompress files matching the glob.
///
/// If multiple globs match the same file, then the most recently added
/// glob takes precedence.
///
/// The syntax for the glob is documented in the
/// [`globset` crate](https://docs.rs/globset/#syntax).
///
/// The `program` given is resolved with respect to `PATH` and turned
/// into an absolute path internally before being executed by the current
/// platform. Notably, on Windows, this avoids a security problem where
/// passing a relative path to `CreateProcess` will automatically search
/// the current directory for a matching program. If the program could not
/// be resolved, then an error is returned.
pub fn (mut builder DecompressionMatcherBuilder) try_associate(glob string, program string, args []string) !&DecompressionMatcherBuilder {
	bin := try_resolve_binary(program)!
	builder.commands << DecompressionCommand{
		glob: glob.to_owned()
		bin:  bin
		args: args.clone()
	}
	return &builder
}

/// A matcher for determining how to decompress files.
pub struct DecompressionMatcher implements IClone {
	/// The set of globs to match. Each glob has a corresponding entry in
	/// `commands`. When a glob matches, the corresponding command should be
	/// used to perform out-of-process decompression.
	globs globset.GlobSet
	/// The commands for each matching glob.
	commands []DecompressionCommand
}

/// Create a new matcher with default rules.
///
/// To add more matching rules, build a matcher with
/// [`DecompressionMatcherBuilder`].
pub fn DecompressionMatcher.new() DecompressionMatcher {
	return DecompressionMatcherBuilder.new().build() or {
		panic('built-in matching rules should always compile')
	}
}

/// Return a pre-built command based on the given file path that can
/// decompress its contents. If no such decompressor is known, then this
/// returns `None`.
///
/// If there are multiple possible commands matching the given path, then
/// the command added last takes precedence.
pub fn (matcher &DecompressionMatcher) command(path string) ?Command {
	matches := matcher.globs.matches(path)
	if matches.len == 0 {
		return none
	}
	i := matches[matches.len - 1]
	decomp_cmd := matcher.commands[int(i)]
	mut cmd := Command.new(decomp_cmd.bin)
	cmd.args(decomp_cmd.args)
	return cmd
}

/// Returns true if and only if the given file path has at least one
/// matching command to perform decompression on.
pub fn (matcher &DecompressionMatcher) has_command(path string) bool {
	return matcher.globs.is_match(path)
}

/// Configures and builds a streaming reader for decompressing data.
pub struct DecompressionReaderBuilder implements IClone {
mut:
	matcher         DecompressionMatcher
	command_builder CommandReaderBuilder
}

/// Create a new builder with the default configuration.
pub fn DecompressionReaderBuilder.new() DecompressionReaderBuilder {
	return DecompressionReaderBuilder{
		matcher:         DecompressionMatcher.new()
		command_builder: CommandReaderBuilder.new()
	}
}

// V-specific constructor alias used by ownership-aware generic callers.
pub fn new_decompression_reader_builder() DecompressionReaderBuilder {
	return DecompressionReaderBuilder.new()
}

/// Build a new streaming reader for decompressing data.
///
/// If decompression is done out-of-process and if there was a problem
/// spawning the process, then its error is logged at the debug level and a
/// passthru reader is returned that does no decompression. This behavior
/// typically occurs when the given file path matches a decompression
/// command, but is executing in an environment where the decompression
/// command is not available.
///
/// If the given file path could not be matched with a decompression
/// strategy, then a passthru reader is returned that does no
/// decompression.
pub fn (builder &DecompressionReaderBuilder) build(path string) !DecompressionReader {
	mut cmd := builder.matcher.command(path) or { return DecompressionReader.new_passthru(path) }
	cmd.arg(path)
	cmd_reader := builder.command_builder.build(cmd) or {
		// V-specific: this standalone module has no process-global logger, so
		// the source's debug event is omitted while preserving its fallback.
		return DecompressionReader.new_passthru(path)
	}
	return DecompressionReader{
		inner: &DecompressionReaderInner{
			kind:       .command
			cmd_reader: cmd_reader
		}
	}
}

/// Set the matcher to use to look up the decompression command for each
/// file path.
///
/// A set of sensible rules is enabled by default. Setting this will
/// completely replace the current rules.
pub fn (mut builder DecompressionReaderBuilder) matcher(matcher DecompressionMatcher) &DecompressionReaderBuilder {
	builder.matcher = matcher
	return &builder
}

/// Get the underlying matcher currently used by this builder.
pub fn (builder &^a DecompressionReaderBuilder) get_matcher[^a]() &^a DecompressionMatcher {
	return &builder.matcher
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
pub fn (mut builder DecompressionReaderBuilder) async_stderr(yes bool) &DecompressionReaderBuilder {
	builder.command_builder.async_stderr(yes)
	return &builder
}

enum DecompressionReaderKind {
	command
	passthru
}

/// A streaming reader for decompressing the contents of a file.
///
/// The purpose of this reader is to provide a seamless way to decompress the
/// contents of file using existing tools in the current environment. This is
/// meant to be an alternative to using decompression libraries in favor of the
/// simplicity and portability of using external commands such as `gzip` and
/// `xz`. This does impose the overhead of spawning a process, so other means
/// for performing decompression should be sought if this overhead isn't
/// acceptable.
///
/// A decompression reader comes with a default set of matching rules that are
/// meant to associate file paths with the corresponding command to use to
/// decompress them. For example, a glob like `*.gz` matches gzip compressed
/// files with the command `gzip -d -c`. If a file path does not match any
/// existing rules, or if it matches a rule whose command does not exist in the
/// current environment, then the decompression reader passes through the
/// contents of the underlying file without doing any decompression.
///
/// The default matching rules are probably good enough for most cases, and if
/// they require revision, pull requests are welcome. In cases where they must
/// be changed or extended, they can be customized through the use of
/// [`DecompressionMatcherBuilder`] and [`DecompressionReaderBuilder`].
///
/// By default, this reader will asynchronously read the processes' stderr.
/// This prevents subtle deadlocking bugs for noisy processes that write a lot
/// to stderr. Currently, the entire contents of stderr is read on to the heap.
///
/// # Example
///
/// This example shows how to read the decompressed contents of a file without
/// needing to explicitly choose the decompression command to run.
///
/// Note that if you need to decompress multiple files, it is better to use
/// `DecompressionReaderBuilder`, which will amortize the cost of compiling the
/// matcher.
///
/// ```no_run
/// use std::{io::Read, process::Command};
///
/// use grep_cli::DecompressionReader;
///
/// let mut rdr = DecompressionReader::new("/usr/share/man/man1/ls.1.gz")?;
/// let mut contents = vec![];
/// rdr.read_to_end(&mut contents)?;
/// # Ok::<(), Box<dyn std::error::Error>>(())
/// ```
pub struct DecompressionReader implements Drop {
	// V-specific: dynamic `io.Reader` calls copy concrete reader values at the
	// interface boundary. Keep the owned process/file state behind a shared
	// inner pointer so copies all mutate and close the same reader.
mut:
	inner &DecompressionReaderInner = unsafe { nil }
}

struct DecompressionReaderInner {
mut:
	kind       DecompressionReaderKind
	cmd_reader CommandReader
	file       os.File
	has_file   bool
	closed     bool
}

/// Build a new streaming reader for decompressing data.
///
/// If decompression is done out-of-process and if there was a problem
/// spawning the process, then its error is returned.
///
/// If the given file path could not be matched with a decompression
/// strategy, then a passthru reader is returned that does no
/// decompression.
///
/// This uses the default matching rules for determining how to decompress
/// the given file. To change those matching rules, use
/// [`DecompressionReaderBuilder`] and [`DecompressionMatcherBuilder`].
///
/// When creating readers for many paths. it is better to use the builder
/// since it will amortize the cost of constructing the matcher.
pub fn DecompressionReader.new(path string) !DecompressionReader {
	return DecompressionReaderBuilder.new().build(path)
}

/// Creates a new "passthru" decompression reader that reads from the file
/// corresponding to the given path without doing decompression and without
/// executing another process.
fn DecompressionReader.new_passthru(path string) !DecompressionReader {
	file := os.open(path) or { return CommandError.io(err) }
	return DecompressionReader{
		inner: &DecompressionReaderInner{
			kind:     .passthru
			file:     file
			has_file: true
		}
	}
}

/// Closes this reader, freeing any resources used by its underlying child
/// process, if one was used. If the child process exits with a nonzero exit
/// code, the returned Err value will include its stderr.
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
/// `close` is also called in `drop` as a last line of defense against
/// resource leakage. Any error from the child process is then printed as a
/// warning to stderr. This can be avoided by explicitly calling `close`
/// before the CommandReader is dropped.
pub fn (mut reader DecompressionReader) close() ! {
	if isnil(reader.inner) {
		return
	}
	mut inner := reader.inner
	if inner.kind != .command {
		return
	}
	if inner.closed {
		return
	}
	inner.closed = true
	mut cmd_reader := &inner.cmd_reader
	cmd_reader.close() or { return error(err.msg()) }
}

fn (mut reader DecompressionReader) drop() {
	if isnil(reader.inner) {
		return
	}
	mut inner := reader.inner
	if inner.kind == .command {
		reader.close() or {}
	} else if inner.has_file {
		inner.file.close()
		inner.has_file = false
	}
	unsafe {
		free(reader.inner)
	}
	reader.inner = unsafe { nil }
}

pub fn (mut reader DecompressionReader) read(mut buf []u8) !int {
	return reader.read_impl(mut buf, false)
}

/// Read decompressed bytes for a searcher that will explicitly call `close`
/// after it has produced a search result.
pub fn (mut reader DecompressionReader) read_for_search(mut buf []u8) !int {
	return reader.read_impl(mut buf, true)
}

fn (mut reader DecompressionReader) read_impl(mut buf []u8, for_search bool) !int {
	if isnil(reader.inner) {
		return io.Eof{}
	}
	mut inner := reader.inner
	if inner.kind == .command {
		mut cmd_reader := &inner.cmd_reader
		if for_search {
			return cmd_reader.read_for_search(mut buf) or {
				if is_broken_pipe_error(err) || err.msg() == '' {
					return io.Eof{}
				}
				return error(err.msg())
			}
		}
		return cmd_reader.read(mut buf) or { return error(err.msg()) }
	}
	if !inner.has_file {
		reader.close()!
		return io.Eof{}
	}
	nread := inner.file.read(mut buf)!
	if nread == 0 {
		reader.close()!
		return io.Eof{}
	}
	return nread
}

/// Resolves a path to a program to a path by searching for the program in
/// `PATH`.
///
/// If the program could not be resolved, then an error is returned.
///
/// The purpose of doing this instead of passing the path to the program
/// directly to Command::new is that Command::new will hand relative paths
/// to CreateProcess on Windows, which will implicitly search the current
/// working directory for the executable. This could be undesirable for
/// security reasons. e.g., running ripgrep with the -z/--search-zip flag on an
/// untrusted directory tree could result in arbitrary programs executing on
/// Windows.
///
/// Note that this could still return a relative path if PATH contains a
/// relative path. We permit this since it is assumed that the user has set
/// this explicitly, and thus, desires this behavior.
///
/// # Platform behavior
///
/// On non-Windows, this is a no-op.
pub fn resolve_binary(prog string) !string {
	$if windows {
		return try_resolve_binary(prog)
	} $else {
		return prog.to_owned()
	}
}

/// Resolves a path to a program to a path by searching for the program in
/// `PATH`.
///
/// If the program could not be resolved, then an error is returned.
///
/// The purpose of doing this instead of passing the path to the program
/// directly to Command::new is that Command::new will hand relative paths
/// to CreateProcess on Windows, which will implicitly search the current
/// working directory for the executable. This could be undesirable for
/// security reasons. e.g., running ripgrep with the -z/--search-zip flag on an
/// untrusted directory tree could result in arbitrary programs executing on
/// Windows.
///
/// Note that this could still return a relative path if PATH contains a
/// relative path. We permit this since it is assumed that the user has set
/// this explicitly, and thus, desires this behavior.
///
/// If `check_exists` is false or the path is already an absolute path this
/// will return immediately.
fn try_resolve_binary(prog string) !string {
	if os.is_abs_path(prog) {
		return prog.to_owned()
	}
	syspaths := os.getenv_opt('PATH') or {
		return CommandError.io(error('system PATH environment variable not found'))
	}
	for syspath in syspaths.split(os.path_delimiter) {
		if syspath == '' {
			continue
		}
		abs_prog := os.join_path(syspath, prog)
		if os.exists(abs_prog) && !os.is_dir(abs_prog) {
			return abs_prog
		}
		if os.file_ext(abs_prog) == '' {
			for extension in ['com', 'exe'] {
				with_extension := '${abs_prog}.${extension}'
				if os.exists(with_extension) && !os.is_dir(with_extension) {
					return with_extension
				}
			}
		}
	}
	return CommandError.io(error('${prog}: could not find executable in PATH'))
}

fn default_decompression_commands() []DecompressionCommand {
	mut cmds := []DecompressionCommand{}
	add_decompression_command('*.gz', ['gzip', '-d', '-c'], mut cmds)
	add_decompression_command('*.tgz', ['gzip', '-d', '-c'], mut cmds)
	add_decompression_command('*.bz2', ['bzip2', '-d', '-c'], mut cmds)
	add_decompression_command('*.tbz2', ['bzip2', '-d', '-c'], mut cmds)
	add_decompression_command('*.xz', ['xz', '-d', '-c'], mut cmds)
	add_decompression_command('*.txz', ['xz', '-d', '-c'], mut cmds)
	add_decompression_command('*.lz4', ['lz4', '-d', '-c'], mut cmds)
	add_decompression_command('*.lzma', ['xz', '--format=lzma', '-d', '-c'], mut cmds)
	add_decompression_command('*.br', ['brotli', '-d', '-c'], mut cmds)
	add_decompression_command('*.zst', ['zstd', '-q', '-d', '-c'], mut cmds)
	add_decompression_command('*.zstd', ['zstd', '-q', '-d', '-c'], mut cmds)
	add_decompression_command('*.Z', ['uncompress', '-c'], mut cmds)
	return cmds
}

fn add_decompression_command(glob string, args []string, mut cmds []DecompressionCommand) {
	if args.len == 0 {
		return
	}
	bin := resolve_binary(args[0]) or {
		// V-specific: this standalone module has no process-global logger, so
		// the source's debug event is omitted when a default is unavailable.
		return
	}
	cmds << DecompressionCommand{
		glob: glob.to_owned()
		bin:  bin
		args: args[1..].clone()
	}
}
