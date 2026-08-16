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
(`3911` lines, `299653` bytes) and a default recursive `if` search (`9402`
lines, `606743` bytes). The latter rechecks the binary-file behavior that an
older version of this port handled differently.

## Benchmark Notes

The current optimized build was measured on Darwin arm64 with V `0.5.2`
(`34a7d3b`) and installed ripgrep `15.2.0`. The V binary was built with:

```sh
v -nocache -prod -ownership -o /tmp/ripgrep_v_benchmark_rg .
```

Each sample ran 100 searches to reduce timer-resolution noise. After one
warmup batch, ten measured batches were interleaved between implementations
and timed with `/usr/bin/time -p`. Standard output and error were redirected to
`/dev/null` during timing.

| Workload | ripgrep_v | installed rg | rg speedup |
| --- | ---: | ---: | ---: |
| Explicit source search | 12.86 +/- 0.29 ms/search | 7.14 +/- 0.15 ms/search | 1.80x |
| Default recursive `if` search | 13.43 +/- 0.13 ms/search | 7.59 +/- 0.45 ms/search | 1.77x |

The explicit source search was:

```sh
--no-ignore -n 'fn ' cli core ignore printer regex searcher pcre2 rg integration globset grep matcher
```

Before timing, sorted output from both implementations was confirmed to be
byte-identical for both workloads. Raw output order can differ because
parallel traversal order is not identical. These results are workload- and
machine-specific; on these measurements, installed ripgrep was about
`1.8x` faster.
