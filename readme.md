# ripgrep_v

V translation of ripgrep components and CLI behavior.

## Benchmark Notes

The current optimized build was measured on Darwin arm64 with V `0.5.1`
(`70c6d80`), Apple clang `17.0.0`, and Homebrew ripgrep `15.1.0`.

Build command:

```sh
v -prod -ownership -o /tmp/rg_v_prod_opt main.v
```

Benchmark workload:

```sh
--no-ignore -n 'fn ' cli core ignore printer regex searcher pcre2 rg integration globset grep matcher
```

Output validation for the benchmark workload:

- V and Rust ripgrep both produced `3281` lines.
- Sorted output was byte-identical.
- Raw output order can differ because traversal order is not identical.

These results are workload-specific. They should not be read as a blanket claim
that this V port is faster than Rust ripgrep.

Validated `path:line:match` workload, `hyperfine` loop benchmark, 5 measured
runs after 1 warmup:

```text
rg 15.1.0 search x100            608.7 ms +/- 6.8 ms
ripgrep_v opt -prod search x100  552.6 ms +/- 11.1 ms
```

For this output-heavy `path:line:match` workload, the optimized V build ran
about `1.10x` faster than the installed Rust `rg`. Single-run timings are near
hyperfine's shell timing floor, so the 100-iteration loop is the more stable
number.

Counterexample, default recursive `if` search, `hyperfine --warmup 5 --runs 20`:

```text
ripgrep_v opt -prod if            9.6 ms +/- 0.8 ms
rg 15.1.0 if                      6.9 ms +/- 0.9 ms
```

For this default workload, Rust `rg` ran about `1.39x` faster. This workload is
also not output-equivalent in the current port: the V build produced `6549`
lines while Rust `rg` produced `6595`, with differences around binary-file
handling for `integration/data/sherlock-nul.txt`.

Benchmark command:

```sh
hyperfine --warmup 1 --runs 5 \
  --command-name 'rg 15.1.0 search x100' \
  "i=0; while [ \$i -lt 100 ]; do /opt/homebrew/bin/rg --no-ignore -n 'fn ' cli core ignore printer regex searcher pcre2 rg integration globset grep matcher > /dev/null; i=\$((i+1)); done" \
  --command-name 'ripgrep_v opt -prod search x100' \
  "i=0; while [ \$i -lt 100 ]; do /tmp/rg_v_prod_opt --no-ignore -n 'fn ' cli core ignore printer regex searcher pcre2 rg integration globset grep matcher > /dev/null; i=\$((i+1)); done"
```
