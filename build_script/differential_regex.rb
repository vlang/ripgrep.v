#!/usr/bin/env ruby

require "open3"
require "tempfile"
require "timeout"

v_rg = ARGV.fetch(0, "/tmp/rg_v")
rust_rg = ARGV.fetch(1, "/opt/homebrew/bin/rg")

patterns = [
  "abc",
  "a|bc",
  "(?:ab)+",
  "a+?",
  "(?U:a+)",
  "(?U)a+",
  "(?-U:a+?)",
  "(?i:delta)",
  "(?i:δ)",
  "(?i-u:delta)",
  "(?s:a.*c)",
  "(?m:^abc$)",
  "\\Aabc",
  "abc\\z",
  "\\bword\\b",
  "\\b{start}word",
  "word\\b{end}",
  "\\b{start-half}-",
  "-\\b{end-half}",
  "(?-u:\\b)word",
  "\\w+",
  "\\W+",
  "\\d+",
  "\\D+",
  "\\s+",
  "\\S+",
  "\\p{Greek}+",
  "\\p{Script=Han}+",
  "\\p{General_Category=Uppercase_Letter}+",
  "\\p{Age=3.0}+",
  "\\P{Greek}+",
  "[[:alnum:]]+",
  "[[:^digit:]]+",
  "[a-z&&[^aeiou]]+",
  "[a-c--b]+",
  "[a-c~~b-d]+",
  "[\\x00-\\x7F]+",
  "[\\p{Greek}&&[^Δ]]+",
  "\\u{03B1}+",
  "\\u03B1+",
  "\\U000003B1+",
  "(?-u:\\xFF)+",
  "(?-u:[^\\x00])+",
  "(?P<word>\\w+)",
  "(?<word>\\w+)",
  "a{2,4}",
  "a{2,}",
  "a{,4}",
  "(?:|abc)",
  "(?:abc|)",
  "()",
  "[.]",
]

# Exercise combinations as well as hand-picked syntax. Keep this deterministic
# so a mismatch can be reproduced by copying the reported pattern directly.
atoms = [
  "a",
  "δ",
  ".",
  "[a-c]",
  "[^a-c]",
  "[[:digit:]]",
  "\\w",
  "\\W",
  "\\d",
  "\\s",
  "\\p{Greek}",
  "\\P{Greek}",
  "(?:ab|a)",
  "(?i:a)",
  "(?-u:\\xFF)",
  "\\b{start-half}",
  "\\b{end-half}",
  "^",
  "$",
]
quantifiers = ["", "?", "*", "+", "{1,3}", "+?"]
rng = Random.new(0x7267)
300.times do
  left = atoms.fetch(rng.rand(atoms.length))
  right = atoms.fetch(rng.rand(atoms.length))
  left_quantifier = quantifiers.fetch(rng.rand(quantifiers.length))
  right_quantifier = quantifiers.fetch(rng.rand(quantifiers.length))
  join = ["", "", "|"].fetch(rng.rand(3))
  patterns << "(?:#{left}#{left_quantifier}#{join}#{right}#{right_quantifier})"
end
patterns.uniq!

contents = [
  "abc aaaa bc\n",
  "word words -word word-\n",
  "delta DELTA Δ δ α Ω\n",
  "mañana κόσμος кириллица 漢字\n",
  "ABC 123_456 !? \t spaced\n",
  "aeiou bcdfgh a b c d\n",
  "a\r\nc\n",
].join.b
contents << [0xff, 0xfe, 0x00, 0x61, 0x0a].pack("C*")

modes = [
  ["-n"],
  ["-n", "--word-regexp"],
  ["-n", "--only-matching", "--column", "--byte-offset"],
  ["-n", "--replace", '<$1/${word}>'],
]

failures = []
Tempfile.create("ripgrep-v-regex") do |file|
  file.binmode
  file.write(contents)
  file.flush
  patterns.each do |pattern|
    modes.each do |mode|
      results = [rust_rg, v_rg].map do |rg|
        Timeout.timeout(10) do
          stdout, stderr, status = Open3.capture3(
            rg,
            "--no-config",
            "--color=never",
            "--no-heading",
            "--text",
            *mode,
            "--",
            pattern,
            file.path,
          )
          [stdout.b, stderr.b, status.exitstatus]
        end
      rescue Timeout::Error
        ["".b, "timeout".b, 124]
      end
      rust, v = results
      next if rust[0] == v[0] && rust[2] == v[2]

      failures << [pattern, mode, rust, v]
    end
  end
end

failures.each do |pattern, mode, rust, v|
  warn "pattern: #{pattern.inspect} mode: #{mode.join(" ")}"
  warn "  Rust status=#{rust[2]} stdout=#{rust[0].inspect} stderr=#{rust[1].inspect}"
  warn "  V    status=#{v[2]} stdout=#{v[0].inspect} stderr=#{v[1].inspect}"
end
abort "#{failures.length} regex differential failure(s)" unless failures.empty?

puts "#{patterns.length} regex patterns in #{modes.length} output modes matched Rust ripgrep"
