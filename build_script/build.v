module main

import os

fn main() {
	set_git_revision_hash()
	set_windows_exe_options()
}

/// Embed a Windows manifest and set some linker options.
///
/// The main reason for this is to enable long path support on Windows. This
/// still, I believe, requires enabling long path support in the registry. But
/// if that's enabled, then this will let ripgrep use C:\... style paths that
/// are longer than 260 characters.
fn set_windows_exe_options() {
	manifest_name := 'pkg/windows/Manifest.xml'
	target_os := os.getenv_opt('CARGO_CFG_TARGET_OS') or { return }
	target_env := os.getenv_opt('CARGO_CFG_TARGET_ENV') or { return }
	if !(target_os == 'windows' && target_env == 'msvc') {
		return
	}
	mut manifest := os.getwd()
	manifest = os.join_path(manifest, manifest_name)

	println('cargo:rerun-if-changed=${manifest_name}')
	// Embed the Windows application manifest file.
	println('cargo:rustc-link-arg-bin=rg=/MANIFEST:EMBED')
	println('cargo:rustc-link-arg-bin=rg=/MANIFESTINPUT:${manifest}')
	// Turn linker warnings into errors. Helps debugging, otherwise the
	// warnings get squashed (I believe).
	println('cargo:rustc-link-arg-bin=rg=/WX')
}

/// Make the current git hash available to the build as the environment
/// variable `RIPGREP_BUILD_GIT_HASH`.
fn set_git_revision_hash() {
	result := os.execute('git rev-parse --short=10 HEAD')
	if result.exit_code == 0 {
		rev := result.output.trim_space()
		if rev.len == 0 {
			println('cargo:warning=output from `git rev-parse` is empty, so skipping embedding of commit hash')
			return
		}
		println('cargo:rustc-env=RIPGREP_BUILD_GIT_HASH=${rev}')
		return
	}
	println('cargo:warning=failed to run `git rev-parse`, so skipping embedding of commit hash: ${result.output.trim_space()}')
}
