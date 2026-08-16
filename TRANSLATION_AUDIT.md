# Translation audit

## Scope and result

This audit compares this repository with the Rust tree at
`/Users/alex/code/3rd/ripgrep`, commit `4519153e5e461527f4bca45b042fff45c4ec6fb9`
(ripgrep 15.1.0).

- Rust inventory: 100 `.rs` files and 52,266 lines.
- V inventory: 162 `.v` files and 80,167 lines.
- All Rust source files, inline tests, standalone tests, examples, benchmark
  code and the fuzz target are represented in V.
- No translated production file contains a stub or placeholder for logic from
  that file.
- Production function identifiers were cross-checked against all V function
  declarations. Exact names were preserved wherever V permits it. The complete
  non-exact-name set is accounted for below.
- The ownership test run covers all translated modules and passes 1,236 tests.

Counts can be reproduced with:

```sh
find /Users/alex/code/3rd/ripgrep -type f -name '*.rs' | sort
find /Users/alex/code/3rd/ripgrep -type f -name '*.rs' -print0 | xargs -0 wc -l
find . -type f -name '*.v' | sort
find . -type f -name '*.v' -print0 | xargs -0 wc -l
```

## File inventory

Every upstream Rust file belongs to one of the mappings below. A basename
mapping means `name.rs` is translated to `name.v`, with its `#[cfg(test)]`
module in `name_test.v` when present.

| Rust source | V translation |
| --- | --- |
| `build.rs` | `build_script/build.v` |
| `crates/cli/src/{decompress,escape,hostname,human,lib,pattern,process,wtr}.rs` | Corresponding `cli/*.v` and `cli/*_test.v` |
| `crates/core/flags/complete/{bash,fish,powershell,zsh}.rs` | `core/flags/complete_*.v` |
| `crates/core/flags/complete/mod.rs` | `core/flags/complete.v` and `complete_test.v` |
| `crates/core/flags/{config,defs,hiargs,parse}.rs` | Corresponding `core/flags/*.v` and `*_test.v` |
| `crates/core/flags/doc/{help,man,version}.rs` | `core/flags/doc_*.v` and translated tests |
| `crates/core/flags/doc/mod.rs` | `core/flags/doc.v` and `doc_test.v` |
| `crates/core/flags/lowargs.rs` | `core/flags/types.v`, `schema.v` and `stat_time.v` |
| `crates/core/flags/mod.rs` | `core/flags/defs.v`, `schema.v`, `complete.v` and `doc.v` |
| `crates/core/{haystack,logger,messages,search}.rs` | Corresponding `core/*.v` and `*_test.v` |
| `crates/core/main.rs` | `rg/main.v` and the root `main.v` entry point |
| `crates/globset/src/{fnv,glob,lib,pathutil,serde_impl}.rs` | Corresponding `globset/*.v` and `*_test.v` |
| `crates/globset/benches/bench.rs` | `globset/benches/bench.v` |
| `crates/grep/src/lib.rs` | `grep/lib.v` and `lib_test.v` |
| `crates/grep/examples/simplegrep.rs` | `examples/simplegrep/main.v` |
| `crates/ignore/src/{default_types,dir,gitignore,overrides,pathutil,types,walk}.rs` | Corresponding `ignore/*.v` and `*_test.v` |
| `crates/ignore/src/lib.rs` | `ignore/lib.v`, `error.v`, `match.v` and `lib_test.v` |
| `crates/ignore/examples/walk.rs` | `examples/walk/main.v` |
| `crates/ignore/tests/gitignore_matched_path_or_any_parents_tests.rs` | `ignore/gitignore_extra_test.v` |
| `crates/ignore/tests/gitignore_skip_bom.rs` | `ignore/gitignore_extra_test.v` |
| `crates/matcher/src/{interpolate,lib}.rs` | Corresponding `matcher/*.v` and translated tests |
| `crates/matcher/tests/{test_matcher,tests,util}.rs` | `matcher/test_matcher_test.v` |
| `crates/pcre2/src/{error,lib,matcher}.rs` | Corresponding `pcre2/*.v` and `*_test.v` |
| `crates/printer/src/{color,counter,json,jsont,lib,path,standard,stats,summary}.rs` | Corresponding `printer/*.v` and `*_test.v` |
| `crates/printer/src/hyperlink/aliases.rs` | `printer/hyperlink_aliases.v` |
| `crates/printer/src/hyperlink/mod.rs` | `printer/hyperlink.v` and `hyperlink_test.v` |
| `crates/printer/src/{macros,util}.rs` | `printer/support.v`, `writecolor.v` and their translated call sites/tests |
| `crates/regex/src/{ast,config,error,lib,literal,matcher,non_matching}.rs` | Corresponding `regex/*.v` and `*_test.v` |
| `crates/regex/src/ban.rs` | `regex/config.v` (`ban_check`) and `ban_test.v` |
| `crates/regex/src/strip.rs` | `regex/config.v` (`strip_line_terminator_from_match`) and `strip_test.v` |
| `crates/searcher/src/{lib,line_buffer}.rs` | Corresponding `searcher/*.v` and translated tests |
| `crates/searcher/src/lines.rs` | `searcher/lib.v` and `lines_test.v` |
| `crates/searcher/src/macros.rs` | The concrete implementations at the translated call sites |
| `crates/searcher/src/searcher/{core,mmap,mod}.rs` | `searcher/lib.v` and searcher test files |
| `crates/searcher/src/searcher/glue.rs` | `searcher/glue.v` and `glue_test.v` |
| `crates/searcher/src/{sink,testutil}.rs` | `searcher/lib.v` and translated sink/search tests |
| `crates/searcher/examples/search-stdin.rs` | `examples/search_stdin/main.v` |
| `fuzz/fuzz_targets/fuzz_glob.rs` | `fuzz/fuzz_glob.v` |
| `tests/{binary,feature,json,misc,multiline,regression}.rs` | Corresponding `integration/*_test.v` |
| `tests/hay.rs` | `integration/hay.v` |
| `tests/{macros,tests,util}.rs` | `integration/testutil.v` and the translated integration suite |

This table expands to exactly the 100 paths returned by the first inventory
command.

## Non-exact production function names

The following are the complete set of production identifiers that do not
appear verbatim as V declarations. Each has translated logic at the indicated
location or is lowered to a native V language operation.

| Rust identifiers | V mapping |
| --- | --- |
| `add_assign`, `as_ref`, `eq`, `fmt`, `hash`, `imp`, `index`, `index_mut` | V arithmetic/direct references, `str`/`msg`, compile-time platform branches and native slice operations at the same call sites |
| `serialize`, `deserialize`, `expecting`, `visit_seq`, `visit_str` | Direct JSON encoders/decoders in `globset/serde_impl.v` and `printer/jsont.v` |
| `and_then` | The explicit `ParseResult` match in `core/flags/parse.v` |
| `attach_timestamps` | `TimestampedHaystack` construction in `HiArgs.sort` |
| `int`, `overflow` | `parse_size_error_int` and `parse_size_error_overflow` |
| `gethostname` | `cli.hostname`, backed by `os.hostname` |
| `is_exe` | Executable/file checks in `try_resolve_binary` |
| `r` (Rust `r#async`), `stderr_to_command_error` | `StderrReader.new_async`, `stderr_drain_fd` and `CommandReader.read_stderr_to_end` |
| `parse_reader` | `parse_config_reader` |
| `generate_digits`, `generate_short`, `generate_long`, `generate_pcre2` | `generate_version_*` and `generate_help_*` |
| `generate_flag` | `generate_man_flag` |
| `from_cow` | `candidate_from_string` |
| `new_regex_set` | `MultiStrategyBuilder.regex_set` |
| `from_entry`, `from_entry_os`, `metadata_internal`, `new_walkdir` | `DirEntryRaw.from_child`, `from_child_known`, `from_path` and `metadata` |
| `from_walkdir` | Direct `IgnoreError` construction in the translated walker, which does not depend on Rust's `walkdir` crate |
| `is_file_name` | `gitignore_is_file_name` |
| `is_symlink` | `DirEntryRaw.path_is_symlink` and file-type checks |
| `read_dir`, `walkdir_is_dir` | `read_dir_children` and root-entry metadata handling |
| `new_for_each_thread`, `steal` | `WorkStealingStacks.new` and `WorkStealingStacks.take` |
| `generate_work`, `run_one`, `should_skip_entry` | `WalkParallel.initial_work`, `walk_stealing_run_one` and `should_skip_entry_with_scratch` |
| `get_work`, `activate_worker`, `deactivate_worker`, `quit_now`, `is_quit_now`, `send`, `send_quit`, `recv` | `take_work`, atomic stop/active-worker state and `WorkStealingQueue` operations |
| `from_parse_error` | `color_error_from_parse_error` |
| `allocate` | Lazy allocation inside `Replacer.replace_all` |
| `replace_separator` | The replacement loop in `PrinterPath.with_separator` |
| `is_space` | The ASCII-space predicate in `trim_ascii_prefix` |
| `write_line_number`, `write_column_number`, `write_byte_offset`, `write_separator` | `StandardImpl.write_prelude` and `write_prelude_separator` |
| `wtr` | Direct ownership-safe access to `standard.wtr` |
| `captures_mut` | Direct access to the translated `RegexCaptures` group storage |
| `check` | `ban_check` |
| `extract_repetition` | `extract_repetition_from_seq` |
| `extract_class_unicode`, `extract_class_bytes`, `class_over_limit_unicode`, `class_over_limit_bytes` | `PatternLiteralParser.parse_class`, including `limit_class` enforcement |
| `from_iter` | `TSeq.new` |
| `remove_matching_bytes` | `analyze_non_matching_pattern` and the `Hir` non-matching-byte properties |
| `strip_from_match`, `strip_from_match_ascii` | `strip_line_terminator_from_match` and class/range stripping helpers |
| `error_message`, `error_io`, `error_config` | `sink_error_message`, `sink_error_io`, `sink_error_config` |

Rust test functions are translated to V `_test.v` files. Their names carry a
`test_` prefix, and a crate/file prefix where Rust's file-local test modules
would otherwise produce duplicate V module-level names. Helper functions use
the same qualification rule. This is why a raw name-only comparison of test
functions produces additional benign differences.

## Ownership and behavior verification

The exact latest V compiler and build commands are in `readme.md`. With that
compiler, both the default and `-d pcre2` production binaries compile with
`-d ownership -ownership`. Module results are:

| Module | Tests |
| --- | ---: |
| `cli` | 52 |
| `core` | 14 |
| `core/flags` | 171 |
| `core/flags/ownflag` | 4 |
| `globset` | 42 |
| `grep` | 1 |
| `ignore` | 189 |
| `integration` | 333 |
| `matcher` | 38 |
| `pcre2` | 17 |
| `printer` | 141 |
| `regex` | 95 |
| `regex/meta` | 1 |
| `searcher` | 138 |
| **Total** | **1,236** |

The PCRE2 module and integration suite were repeated with `-d pcre2`; they
pass 17/17 and 333/333 respectively. Output parity and performance results are
recorded in `readme.md`.
