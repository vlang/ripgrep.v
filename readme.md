# ripgrep_v

V translation of ripgrep components and CLI behavior.

## Verification

The translated source snapshot is ripgrep `15.1.0`, commit `4519153`. Every
one of its 100 Rust files is accounted for, including crate tests, integration
tests, examples, the benchmark and the fuzz target. The production function
audit found no omitted logic or translation stubs. See
[TRANSLATION_AUDIT.md](TRANSLATION_AUDIT.md) for the source-file inventory and
the V mappings for functions whose names necessarily changed.

The current tree was built with V from the exact current `origin/master`,
commit `702dbc6023cfa3a2b65da7515039d07477794282`, and with the profiled V3
optimizations in [vlang/v#28104](https://github.com/vlang/v/pull/28104), commit
`7092e5c1a`. Both revisions compile the translation. A clean optimized V3
ownership compiler can be reproduced with:

```sh
git -C /path/to/v fetch origin master
git -C /path/to/v fetch origin v3-ripgrep-profile-optimizations
git -C /path/to/v worktree add --detach /tmp/v-ripgrep-compiler 7092e5c1a
make -C /tmp/v-ripgrep-compiler
/tmp/v-ripgrep-compiler/v -old-compiler -nocache -prod -gc none \
  -d ownership -o /tmp/v-ripgrep-compiler/v3 \
  /tmp/v-ripgrep-compiler/vlib/v3/v3.v
```

Build ripgrep_v in ownership mode (the full translation currently needs the
explicit V3 memory-limit override):

```sh
cd /path/to/ripgrep_v
/tmp/v-ripgrep-compiler/v3 -no-memory-limit -nocache -d ownership -ownership \
  -prod -o /tmp/ripgrep_v_rg .
/tmp/v-ripgrep-compiler/v3 -no-memory-limit -nocache -d ownership -ownership \
  -prod -d pcre2 -o /tmp/ripgrep_v_pcre2_rg .
```

The complete ownership test run passes 1,236 tests. The PCRE2 module and the
333-test integration suite also pass when compiled with `-d pcre2`.

On macOS arm64, sorted output was byte-identical to installed Rust ripgrep
`15.2.0` for all of these checks:

| Workload | Lines | Bytes |
| --- | ---: | ---: |
| Explicit source search | 3,911 | 299,682 |
| Default recursive `if` search | 9,405 | 657,743 |
| PCRE2 lookbehind search | 1,237 | 81,353 |

The explicit source search was:

```sh
--no-ignore -n 'fn ' cli core ignore printer regex searcher pcre2 rg integration globset grep matcher
```

The PCRE2 check was:

```sh
-P -n '(?<=fn )test_[A-Za-z_]+' cli core ignore printer regex searcher pcre2 integration globset grep matcher
```

Raw traversal order can differ, so parity comparisons sort both outputs before
performing a byte-for-byte comparison.

## Clean Compile Time And Disk Use

These measurements were taken on the same Apple M5 Max running macOS 26.5.
V used V3 optimization commit `7092e5c1a` above, with the V3 compiler itself
built using `-prod -gc none -d ownership`. Rust was `rustc 1.97.1`; the Rust
source was ripgrep `15.1.0` at commit `4519153`. Dependencies were downloaded
before timing, every build had a distinct empty output directory, and no
compiler cache was used. These are single clean-build measurements, not
averages.

| Clean build mode | V | Rust |
| --- | ---: | ---: |
| Default/debug | 1.85 s | 3.69 s |
| Production/release | 13.41 s | 5.44 s |

The V default/debug row omits `-prod` for the ripgrep_v target and uses TCC; the
V3 compiler running that build remains a production compiler. V3 reported
1.80 s internally, including 0.23 s in TCC. The V production row uses
`-prod`: V3 reported 13.36 s internally, comprising 1.58 s in its frontend
and C generation plus 11.78 s in external Clang `-O3 -flto`.

For comparison, unmodified V `origin/master` at `702dbc602` took 6.12 s for
the default/debug build and 16.57 s for the production build under the same
conditions. The profiled changes reduce the production V3 frontend from
4.21 s to 1.58 s.

The V frontend parses 268 files and 98,614 lines for this build: 57,113 lines
come from ripgrep_v and 41,501 come from imported V library modules. Thus the
frontend measurement is not a compile of only the roughly 57K project lines.
The external Clang/LTO step dominates the clean V release-build wall time.

V3 prints the following per-stage breakdown when the build command below uses
`-v`:

| V3 stage | Time |
| --- | ---: |
| Parse setup/cache | 3.46 ms |
| Parse `.vh` | 0.00 ms |
| Parse `.v` in parallel | 28.31 ms |
| Resolve imports | 19.76 ms |
| Check in parallel | 445.50 ms |
| Ownership | 38.16 ms |
| Mark used | 25.86 ms |
| Transform | 206.21 ms |
| Annotate types | 268.31 ms |
| Monomorphize | 391.22 ms |
| Generate C in parallel | 190.71 ms |
| C object cache | 0.01 ms |
| Clang | 11,783.66 ms |
| Total | 13,363.36 ms |

The timed commands were:

```sh
cd /path/to/ripgrep_v
/usr/bin/time -l /tmp/v-ripgrep-compiler/v3 -no-memory-limit -nocache \
  -d ownership -ownership -v -o /tmp/ripgrep-v-debug-rg .
/usr/bin/time -l /tmp/v-ripgrep-compiler/v3 -no-memory-limit -nocache \
  -d ownership -ownership -prod -v -o /tmp/ripgrep-v-prod-rg .

cd /path/to/ripgrep
cargo fetch --locked
/usr/bin/time -l cargo build --locked \
  --target-dir /tmp/ripgrep-rust-debug
/usr/bin/time -l cargo build --release --locked \
  --target-dir /tmp/ripgrep-rust-release
```

Disk use was measured independently from compiler memory use. The toolchain
row includes the V compiler plus its source/standard-library tree, or the
minimal Rust compiler/standard library plus the downloaded Cargo registry.
It excludes both project source trees and the system C linker.

| Disk use | V | Rust |
| --- | ---: | ---: |
| Compiler, standard library and downloaded dependencies | 153.6 MiB | 624.5 MiB |
| Peak clean-build output/temp directory | 7.50 MiB | 154.1 MiB |
| Final executable | 2.64 MiB | 6.21 MiB |

The V toolchain figure includes the 12.83 MiB production V3 executable. The
bootstrap V executable used once to build V3 adds another 23.69 MiB if it is
retained. Cargo keeps release intermediates in its target directory, which is
why its clean-build disk figure is much larger than the final Rust executable.

## Benchmark Notes

The optimized ownership build above was compared with installed ripgrep
`15.2.0` using `hyperfine` 1.20.0 on an Apple M5 Max running macOS 26.5. Each
command had 10 warmup runs and 50 measured runs, with standard output sent to
`/dev/null`.

| Workload | ripgrep_v | installed rg | V speedup |
| --- | ---: | ---: | ---: |
| Explicit source search | 5.4 +/- 0.4 ms | 7.6 +/- 1.6 ms | 1.41x |
| Default recursive `if` search | 7.0 +/- 0.6 ms | 7.5 +/- 0.7 ms | 1.07x |
| Explicit path list repeated 20 times | 51.2 +/- 0.4 ms | 63.0 +/- 1.3 ms | 1.23x |

The repeated-path measurement reduces timer overhead for the shortest
workload. These results are workload- and machine-specific; on these
measurements, ripgrep_v meets or exceeds installed ripgrep's performance.
