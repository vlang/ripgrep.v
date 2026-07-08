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
pub fn (builder DecompressionMatcherBuilder) build() !DecompressionMatcher {
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
pub fn (mut builder DecompressionMatcherBuilder) associate(glob string, program string, args []string) &DecompressionMatcherBuilder {
	builder.try_associate(glob, program, args) or {}
	return &builder
}

/// Associates a glob with a command to decompress files matching the glob.
///
/// If multiple globs match the same file, then the most recently added
/// glob takes precedence.
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
pub fn (matcher DecompressionMatcher) command(path string) ?Command {
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
pub fn (matcher DecompressionMatcher) has_command(path string) bool {
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
pub fn (builder DecompressionReaderBuilder) build(path string) !DecompressionReader {
	mut cmd := builder.matcher.command(path) or {
		return DecompressionReader.new_passthru(path)
	}
	cmd.arg(path)
	cmd_reader := builder.command_builder.build(cmd) or {
		return DecompressionReader.new_passthru(path)
	}
	return DecompressionReader{
		kind:        .command
		cmd_reader:  cmd_reader
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
pub fn (builder DecompressionReaderBuilder) get_matcher() &DecompressionMatcher {
	return &builder.matcher
}

/// When enabled, the reader will asynchronously read the contents of the
/// command's stderr output. When disabled, stderr is only read after the
/// stdout stream has been exhausted (or if the process quits with an error
/// code).
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
/// `xz`.
pub struct DecompressionReader implements IClone {
mut:
	kind       DecompressionReaderKind
	cmd_reader CommandReader
	file       os.File
	has_file   bool
	closed     bool
}

/// Build a new streaming reader for decompressing data.
pub fn DecompressionReader.new(path string) !DecompressionReader {
	return DecompressionReaderBuilder.new().build(path)
}

/// Creates a new "passthru" decompression reader that reads from the file
/// corresponding to the given path without doing decompression and without
/// executing another process.
fn DecompressionReader.new_passthru(path string) !DecompressionReader {
	file := os.open(path) or { return CommandError.io(err) }
	return DecompressionReader{
		kind:     .passthru
		file:     file
		has_file: true
	}
}

/// Closes this reader, freeing any resources used by its underlying child
/// process, if one was used. If the child process exits with a nonzero exit
/// code, the returned Err value will include its stderr.
pub fn (mut reader DecompressionReader) close() ! {
	if reader.closed {
		return
	}
	reader.closed = true
	if reader.kind == .command {
		reader.cmd_reader.close()!
		return
	}
	if reader.has_file {
		reader.file.close()
		reader.has_file = false
	}
}

pub fn (mut reader DecompressionReader) read(mut buf []u8) !int {
	if reader.kind == .command {
		return reader.cmd_reader.read(mut buf)
	}
	if !reader.has_file {
		reader.close()!
		return io.Eof{}
	}
	nread := reader.file.read(mut buf)!
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
/// On non-Windows, this is a no-op.
pub fn resolve_binary(prog string) !string {
	$if windows {
		return try_resolve_binary(prog)
	} $else {
		return prog.to_owned()
	}
}

fn try_resolve_binary(prog string) !string {
	$if windows {
		if os.is_abs_path(prog) {
			return prog.to_owned()
		}
		found := os.find_abs_path_of_executable(prog) or {
			return CommandError.io(error('${prog}: could not find executable in PATH'))
		}
		return found.to_owned()
	} $else {
		return prog.to_owned()
	}
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
	bin := resolve_binary(args[0]) or { return }
	cmds << DecompressionCommand{
		glob: glob.to_owned()
		bin:  bin
		args: args[1..].clone()
	}
}
