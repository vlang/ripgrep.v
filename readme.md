# ripgrep_v

V translation of ripgrep components and CLI behavior.

## Verification

The translated source snapshot is ripgrep `15.1.0`, commit `4519153`. Every
one of its 100 Rust files is accounted for, including crate tests, integration
tests, examples, the benchmark and the fuzz target. The production function
audit found no omitted logic or translation stubs. See
[TRANSLATION_AUDIT.md](TRANSLATION_AUDIT.md) for the source-file inventory and
the V mappings for functions whose names necessarily changed.

The current tree was built and tested with V from the exact current
`origin/master`, commit `e2ebb33f58bfcc11f829f5c6c382f2160064b47b`. A clean
V3 ownership compiler can be reproduced with:

```sh
git -C /path/to/v fetch origin master
git -C /path/to/v worktree add --detach /tmp/v-origin-master origin/master
make -C /tmp/v-origin-master
/tmp/v-origin-master/v -nocache -prod -gc none -d ownership -d v3_ttime \
  -o /tmp/v-origin-master/v3 /tmp/v-origin-master/vlib/v3/v3.v
```

Build ripgrep_v in ownership mode (the full translation currently needs the
explicit V3 memory-limit override):

```sh
cd /path/to/ripgrep_v
/tmp/v-origin-master/v3 -no-memory-limit -nocache -d ownership -ownership \
  -prod -o /tmp/ripgrep_v_rg .
/tmp/v-origin-master/v3 -no-memory-limit -nocache -d ownership -ownership \
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
V was the exact `origin/master` commit above, with the V3 compiler itself built
using `-prod`. Rust was `rustc 1.97.1`; the Rust source was ripgrep `15.1.0` at
commit `4519153`. Dependencies were downloaded before timing, both builds had
an empty output directory, and no compiler cache was used.

| Clean release build | Time |
| --- | ---: |
| V3 frontend and C generation | 4.18 s |
| Clang `-O3 -flto` invoked by V3 | 11.79 s |
| ripgrep_v total | 15.98 s |
| Rust `cargo build --release --locked` total | 5.53 s |

The V frontend parses 268 files and 98,594 lines for this build: 57,113 lines
come from ripgrep_v and 41,481 come from imported V library modules. Thus the
frontend measurement is not a compile of only the roughly 57K project lines.
The external Clang/LTO step dominates the clean V release-build wall time.

V3 prints the following per-stage breakdown when the build command below uses
`-v`:

| V3 stage | Time |
| --- | ---: |
| Parse setup/cache | 2.87 ms |
| Parse `.vh` | 0.00 ms |
| Parse `.v` in parallel | 27.01 ms |
| Resolve imports | 30.61 ms |
| Check in parallel | 1,038.26 ms |
| Ownership | 33.33 ms |
| Mark used | 28.74 ms |
| Transform | 232.76 ms |
| Annotate types | 1,245.41 ms |
| Monomorphize | 1,372.64 ms |
| Generate C in parallel | 203.70 ms |
| C object cache | 2.21 ms |
| Clang | 11,792.45 ms |
| Total | 15,977.08 ms |

The timed commands were:

```sh
cd /path/to/ripgrep_v
/usr/bin/time -l /tmp/v-origin-master/v3 -no-memory-limit -nocache \
  -d ownership -ownership -prod -v -o /tmp/ripgrep_v_rg .

cd /path/to/ripgrep
cargo fetch --locked
/usr/bin/time -l cargo build --release --locked \
  --target-dir /tmp/ripgrep-rust-clean-target
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
