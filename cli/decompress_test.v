module cli

fn test_decompression_try_associate_keeps_relative_program_on_non_windows() {
	$if !windows {
		mut builder := DecompressionMatcherBuilder.new()
		builder.defaults(false)
		builder.try_associate('*.foo', 'definitely-not-a-real-ripgrep-v-command', ['-d'])!
		matcher := builder.build()!
		cmd := matcher.command('sample.foo') or { panic('missing decompression command') }

		assert cmd.program == 'definitely-not-a-real-ripgrep-v-command'
		assert cmd.args == ['-d']
	}
}

fn test_decompression_command_prefers_last_matching_glob() {
	$if !windows {
		mut builder := DecompressionMatcherBuilder.new()
		builder.defaults(false)
		builder.try_associate('*.foo', 'first-command', ['first'])!
		builder.try_associate('*.foo', 'second-command', ['second'])!
		matcher := builder.build()!
		cmd := matcher.command('sample.foo') or { panic('missing decompression command') }

		assert cmd.program == 'second-command'
		assert cmd.args == ['second']
	}
}

fn test_decompression_reader_builder_has_default_matcher() {
	$if !windows {
		builder := DecompressionReaderBuilder.new()
		assert builder.get_matcher().has_command('sample.gz')
	}
}
