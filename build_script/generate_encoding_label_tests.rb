#!/usr/bin/env ruby
# Generates the exhaustive encoding_rs label parity test.
# Usage: generate_encoding_label_tests.rb path/to/encoding_rs/src/lib.rs output.v

abort "usage: #{$PROGRAM_NAME} encoding_rs/src/lib.rs output.v" unless ARGV.length == 2

source = File.read(ARGV[0])
labels = source[/static LABELS_SORTED.*?= \[(.*?)\];/m, 1].scan(/"([^"]+)"/).flatten
encodings = source[/static ENCODINGS_IN_LABEL_SORT.*?= \[(.*?)\];/m, 1]
  .scan(/&([A-Z0-9_]+)_INIT/).flatten
abort "label/encoding count mismatch" unless labels.length == encodings.length

names = {}
source.scan(/pub static ([A-Z0-9_]+)_INIT: Encoding = Encoding \{\s*name: "([^"]+)"/m) do |key, name|
  names[key] = name
end

valid = []
rejected = []
labels.zip(encodings).each do |label, encoding|
  if encoding == 'REPLACEMENT'
    rejected << label
  else
    valid << [label, names.fetch(encoding)]
  end
end

output = +<<~V
  module searcher

  // Generated from encoding_rs 0.8.35 by
  // build_script/generate_encoding_label_tests.rb.
  struct EncodingLabelCase {
      label     string
      canonical string
  }

  fn test_all_encoding_rs_labels_and_canonical_names() {
      cases := [
V
valid.each do |label, canonical|
  output << "\t\tEncodingLabelCase{'#{label}', '#{canonical}'},\n"
end
output << <<~V
      ]
      for case in cases {
          encoding := Encoding.new(case.label) or { panic('rejected encoding_rs label `${case.label}`') }
          assert encoding.label == case.canonical
      }
  }

  fn test_encoding_rs_replacement_labels_are_rejected() {
      for label in [
V
rejected.each { |label| output << "\t\t'#{label}',\n" }
output << <<~V
      ] {
          if _ := Encoding.new(label) {
              panic('accepted encoding_rs replacement label `${label}`')
          }
      }
  }
V

File.write(ARGV[1], output)
