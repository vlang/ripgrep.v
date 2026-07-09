module flags

import os

$if pcre2 ? {
	$if $pkgconfig('libpcre2-8') {
		#pkgconfig --cflags --libs libpcre2-8
	} $else $if macos {
		#flag -I/opt/homebrew/include
		#flag -L/opt/homebrew/lib
		#flag -lpcre2-8
	} $else {
		#flag -lpcre2-8
	}
	#include "@VMODROOT/pcre2/pcre2_shim.h"
	fn C.rg_pcre2_version(buf &char, len usize) &char
}

/*
Provides routines for generating version strings.

Version strings can be just the digits, an overall short one-line description
or something more verbose that includes things like CPU target feature support.
*/

/// Generates just the numerical part of the version of ripgrep.
///
/// This includes the git revision hash.
pub fn generate_version_digits() string {
	semver := os.getenv_opt('CARGO_PKG_VERSION') or { 'N/A' }
	hash := os.getenv_opt('RIPGREP_BUILD_GIT_HASH') or { return semver.to_owned() }
	if hash == '' {
		return semver.to_owned()
	}
	return '${semver} (rev ${hash})'
}

/// Generates a short version string of the form `ripgrep x.y.z`.
pub fn generate_version_short() string {
	digits := generate_version_digits()
	return 'ripgrep ${digits}'
}

/// Generates a longer multi-line version string.
///
/// This includes not only the version of ripgrep but some other information
/// about its build. For example, SIMD support and PCRE2 support.
pub fn generate_version_long() string {
	compile := compile_cpu_features()
	runtime := runtime_cpu_features()
	mut out := []string{}
	out << generate_version_short()
	out << ''
	out << 'features:${features().join(',')}'
	if compile.len > 0 {
		out << 'simd(compile):${compile.join(',')}'
	}
	if runtime.len > 0 {
		out << 'simd(runtime):${runtime.join(',')}'
	}
	pcre2_version, _ := generate_version_pcre2()
	out << ''
	out << pcre2_version.trim_right('\n')
	return out.join('\n') + '\n'
}

/// Generates multi-line version string with PCRE2 information.
///
/// This also returns whether PCRE2 is actually available in this build of
/// ripgrep.
pub fn generate_version_pcre2() (string, bool) {
	$if pcre2 ? {
		return 'PCRE2 ${pcre2_version()} is available\n', true
	} $else {
		return 'PCRE2 is not available in this build of ripgrep.\n', false
	}
}

fn pcre2_version() string {
	$if pcre2 ? {
		mut buf := []u8{len: 128}
		C.rg_pcre2_version(&char(buf.data), usize(buf.len))
		mut end := 0
		for end < buf.len && buf[end] != 0 {
			end++
		}
		return buf[..end].bytestr()
	} $else {
		return 'unavailable'
	}
}

/// Returns the relevant SIMD features supported by the CPU at runtime.
///
/// This is kind of a dirty violation of abstraction, since it assumes
/// knowledge about what specific SIMD features are being used by various
/// components.
fn runtime_cpu_features() []string {
	$if x64 {
		return ['+SSE2', '-SSSE3', '-AVX2']
	} $else $if amd64 {
		return ['+SSE2', '-SSSE3', '-AVX2']
	} $else $if arm64 {
		return ['+NEON']
	} $else $if aarch64 {
		return ['+NEON']
	} $else {
		return []string{}
	}
}

/// Returns the SIMD features supported while compiling ripgrep.
///
/// In essence, any features listed here are required to run ripgrep correctly.
///
/// This is kind of a dirty violation of abstraction, since it assumes
/// knowledge about what specific SIMD features are being used by various
/// components.
///
/// An easy way to enable everything available on your current CPU is to
/// compile ripgrep with `RUSTFLAGS="-C target-cpu=native"`. But note that
/// the binary produced by this will not be portable.
fn compile_cpu_features() []string {
	$if x64 {
		return ['+SSE2', '-SSSE3', '-AVX2']
	} $else $if amd64 {
		return ['+SSE2', '-SSSE3', '-AVX2']
	} $else $if arm64 {
		return ['+NEON']
	} $else $if aarch64 {
		return ['+NEON']
	} $else {
		return []string{}
	}
}

/// Returns a list of "features" supported (or not) by this build of ripgrpe.
fn features() []string {
	mut features_ := []string{}
	$if pcre2 ? {
		features_ << '+pcre2'
	} $else {
		features_ << '-pcre2'
	}
	return features_
}

/// Returns `+` when `enabled` is `true` and `-` otherwise.
fn sign(enabled bool) string {
	if enabled {
		return '+'
	}
	return '-'
}
