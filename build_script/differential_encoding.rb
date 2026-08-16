#!/usr/bin/env ruby

require "open3"
require "fileutils"
require "tempfile"
require "timeout"
require "tmpdir"

v_compiler = ARGV.fetch(0, "/tmp/v3_latest")

encodings = [
  "Big5", "EUC-JP", "EUC-KR", "GBK", "gb18030", "IBM866",
  "ISO-2022-JP", "ISO-8859-2", "ISO-8859-3", "ISO-8859-4",
  "ISO-8859-5", "ISO-8859-6", "ISO-8859-7", "ISO-8859-8",
  "ISO-8859-8-I", "ISO-8859-10", "ISO-8859-13", "ISO-8859-14",
  "ISO-8859-15", "ISO-8859-16", "KOI8-R", "KOI8-U", "Shift_JIS",
  "UTF-8", "UTF-16BE", "UTF-16LE", "macintosh", "windows-874",
  "windows-1250", "windows-1251", "windows-1252", "windows-1253",
  "windows-1254", "windows-1255", "windows-1256", "windows-1257",
  "windows-1258", "x-mac-cyrillic", "x-user-defined",
]

def compare(rust_harness, v_harness, encoding, path)
  results = [rust_harness, v_harness].map do |harness|
    Timeout.timeout(120) do
      stdout, stderr, status = Open3.capture3(
        harness,
        encoding,
        path,
      )
      [stdout.b, stderr.b, status.exitstatus]
    end
  rescue Timeout::Error
    ["".b, "timeout".b, 124]
  end
  rust, v = results
  return if rust[0] == v[0] && rust[2] == v[2]

  warn "encoding: #{encoding} corpus: #{File.basename(path)}"
  warn "  Rust status=#{rust[2]} bytes=#{rust[0].bytesize} stderr=#{rust[1].inspect}"
  warn "  V    status=#{v[2]} bytes=#{v[0].bytesize} stderr=#{v[1].inspect}"
  abort "encoding differential failure"
end

workspace = Dir.mktmpdir("ripgrep-v-encoding-differential")
at_exit { FileUtils.rm_rf(workspace) }

File.write(File.join(workspace, "Cargo.toml"), <<~TOML)
  [package]
  name = "encoding-rs-differential"
  version = "0.0.0"
  edition = "2021"

  [dependencies]
  encoding_rs = "=0.8.35"
TOML
FileUtils.mkdir_p(File.join(workspace, "src"))
File.write(File.join(workspace, "src", "main.rs"), <<~'RUST')
  use std::{env, fs, io::{self, Write}, process};

  fn main() {
      let args: Vec<_> = env::args_os().collect();
      if args.len() != 3 {
          process::exit(2);
      }
      let label = args[1].to_string_lossy();
      let Some(encoding) = encoding_rs::Encoding::for_label_no_replacement(label.as_bytes()) else {
          process::exit(2);
      };
      let input = fs::read(&args[2]).unwrap();
      let (decoded, _) = encoding.decode_without_bom_handling(&input);
      io::stdout().write_all(decoded.as_bytes()).unwrap();
  }
RUST

unless system("cargo", "build", "--quiet", "--release", "--offline", "--manifest-path",
              File.join(workspace, "Cargo.toml"))
  abort "failed to build encoding_rs differential harness"
end
rust_harness = File.join(workspace, "target", "release", "encoding-rs-differential")
v_harness = File.join(workspace, "v-encoding-differential")
unless system(v_compiler, "-d", "encoding_differential", "-o", v_harness,
              File.join(__dir__, "encoding_differential_harness.v"))
  abort "failed to build V differential harness"
end

Tempfile.create(["ripgrep-v-all-byte-pairs", ".bin"]) do |pairs|
  pairs.binmode
  256.times do |first|
    256.times do |second|
      pairs.write([first, second, 0x0a].pack("C*"))
    end
  end
  pairs.flush
  encodings.each { |encoding| compare(rust_harness, v_harness, encoding, pairs.path) }
end

Tempfile.create(["ripgrep-v-gb18030-four-byte", ".bin"]) do |gb4|
  gb4.binmode
  (0x81..0xfe).each do |first|
    (0x30..0x39).each do |second|
      (0x81..0xfe).each do |third|
        (0x30..0x39).each do |fourth|
          gb4.write([first, second, third, fourth, 0x0a].pack("C*"))
        end
      end
    end
  end
  gb4.flush
  ["GBK", "gb18030"].each do |encoding|
    compare(rust_harness, v_harness, encoding, gb4.path)
  end
end

Tempfile.create(["ripgrep-v-iso2022jp-state", ".bin"]) do |iso2022|
  iso2022.binmode
  iso2022.write([
    0x1b, 0x24, 0x42, 0x24, 0x22, 0x1b, 0x28, 0x42, 0x0a,
    0x1b, 0x28, 0x4a, 0x5c, 0x7e, 0x1b, 0x28, 0x42, 0x0a,
    0x1b, 0x28, 0x49, 0x21, 0x5f, 0x1b, 0x28, 0x42, 0x0a,
    0x1b, 0x24, 0x42, 0x24, 0x0a,
    0x1b, 0x24, 0x40, 0x7f, 0x7f, 0x1b, 0x28, 0x42, 0x0a,
    0x1b, 0x00, 0x1b, 0x24, 0x00, 0x0a,
  ].pack("C*"))
  iso2022.flush
  compare(rust_harness, v_harness, "ISO-2022-JP", iso2022.path)
end

puts "#{encodings.length} encodings matched encoding_rs for all byte pairs; " \
  "GBK/GB18030 also matched all 1,587,600 four-byte sequences"
