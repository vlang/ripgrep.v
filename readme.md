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
`origin/master`, commit `fcfd4246e8b8197568502aab2179e9183021c0ad`. A clean
V3 ownership compiler can be reproduced with:

```sh
git -C /path/to/v fetch origin master
git -C /path/to/v worktree add --detach /tmp/v-origin-master origin/master
make -C /tmp/v-origin-master
/tmp/v-origin-master/v -nocache -gc none -d ownership \
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
