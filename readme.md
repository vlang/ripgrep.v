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

`hyperfine` loop benchmark, 5 measured runs after 1 warmup:

```text
rg 15.1.0 search x100          637.9 ms +/- 10.6 ms
ripgrep_v opt -prod search x100 515.3 ms +/- 1.5 ms
```

For this output-heavy `path:line:match` workload, the optimized V build ran
about `1.24x` faster than the installed Rust `rg`. Single-run timings were
near hyperfine's shell timing floor, so the 100-iteration loop is the more
stable number.

Benchmark command:

```sh
hyperfine --warmup 1 --runs 5 \
  --command-name 'rg 15.1.0 search x100' \
  "i=0; while [ \$i -lt 100 ]; do /opt/homebrew/bin/rg --no-ignore -n 'fn ' cli core ignore printer regex searcher pcre2 rg integration globset grep matcher > /dev/null; i=\$((i+1)); done" \
  --command-name 'ripgrep_v opt -prod search x100' \
  "i=0; while [ \$i -lt 100 ]; do /tmp/rg_v_prod_opt --no-ignore -n 'fn ' cli core ignore printer regex searcher pcre2 rg integration globset grep matcher > /dev/null; i=\$((i+1)); done"
```
