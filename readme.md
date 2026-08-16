# ripgrep_v

V translation of ripgrep components and CLI behavior.

## Verification

The current tree targets ripgrep `15.1.0` and is verified with the local V
`0.5.2` (`34a7d3b`) V3 frontend in ownership mode:

```sh
v -nocache -ownership -o /tmp/ripgrep_v_rg .
v -nocache -ownership -d pcre2 -o /tmp/ripgrep_v_pcre2_rg .
```

On Darwin arm64, the default CLI's sorted output was byte-identical to the
installed Rust ripgrep `15.2.0` for both the explicit source workload below
(`3912` lines, `299746` bytes) and a default recursive `if` search (`9402`
lines, `606755` bytes). The latter rechecks the binary-file behavior that an
older version of this port handled differently.

## Benchmark Notes

The current optimized build was measured on Darwin arm64 with V `0.5.2`
(`34a7d3b`) and installed ripgrep `15.2.0`. The V binary was built with:

```sh
v -nocache -prod -ownership -o /tmp/ripgrep_v_benchmark_rg .
```

The commands were interleaved by `hyperfine` 1.20.0 with 10 warmup runs and 50
measured runs. Standard output was redirected to `/dev/null` during timing.

| Workload | ripgrep_v | installed rg | V speedup |
| --- | ---: | ---: | ---: |
| Explicit source search | 5.1 +/- 0.2 ms | 7.2 +/- 0.8 ms | 1.39x |
| Default recursive `if` search | 6.5 +/- 0.5 ms | 7.6 +/- 0.8 ms | 1.17x |

Because the explicit workload is close to `hyperfine`'s 5 ms calibration
threshold, a second measurement repeated its path arguments 20 times in each
process. It measured 49.1 +/- 0.3 ms for ripgrep_v and 60.7 +/- 0.7 ms for
installed ripgrep, making ripgrep_v 1.24x faster on the longer run.

The explicit source search was:

```sh
--no-ignore -n 'fn ' cli core ignore printer regex searcher pcre2 rg integration globset grep matcher
```

Output validation for the benchmark workload:

- V and Rust ripgrep both produced `3912` lines.
- Sorted output was byte-identical.
- Raw output order can differ because traversal order is not identical.

The default recursive workload was also sorted and compared byte-for-byte.
These results are workload- and machine-specific; on these measurements,
ripgrep_v meets or exceeds installed ripgrep's performance.
