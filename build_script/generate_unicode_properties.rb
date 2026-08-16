#!/usr/bin/env ruby
# Generates the Unicode property tables used by the default regex matcher from
# the same regex-syntax tables consumed by Rust ripgrep.

source = ARGV.fetch(0)
output = ARGV.fetch(1)
backend_output = ARGV[2]
case_output = ARGV[3]
tables = File.join(source, 'src', 'unicode_tables')

def rust_char(text)
  return text[/\A\\u\{([0-9a-fA-F]+)\}\z/, 1].to_i(16) if text.start_with?('\\u{')
  return text[/\A\\x([0-9a-fA-F]{2})\z/, 1].to_i(16) if text.start_with?('\\x')
  return 0 if text == '\\0'
  return 9 if text == '\\t'
  return 10 if text == '\\n'
  return 13 if text == '\\r'
  text.codepoints.first
end

def load_range_table(path)
  text = File.read(path)
  header = text[/pub const BY_NAME:.*?=\s*&\[(.*?)\];/m, 1]
  names = header.scan(/\("([^"]+)",\s*([A-Z0-9_]+)\)/).to_h
  constants = {}
  text.scan(/pub const ([A-Z0-9_]+):.*?=\s*&\[(.*?)\];/m) do |name, body|
    constants[name] = body.scan(/\('((?:\\.|[^'])*)',\s*'((?:\\.|[^'])*)'\)/).map do |first, last|
      [rust_char(first), rust_char(last)]
    end
  end
  names.transform_values { |constant| constants.fetch(constant) }
end

def load_pairs(path, constant)
  text = File.read(path)
  body = text[/pub const #{constant}:.*?=\s*&\[(.*?)\];/m, 1]
  body.scan(/\("([^"]+)",\s*"([^"]+)"\)/)
end

def load_ranges(path, constant)
  text = File.read(path)
  body = text[/pub const #{constant}:.*?=\s*&\[(.*?)\];/m, 1]
  body.scan(/\('((?:\\.|[^'])*)',\s*'((?:\\.|[^'])*)'\)/).map do |first, last|
    [rust_char(first), rust_char(last)]
  end
end

def load_case_folding(path)
  text = File.read(path)
  body = text[/pub const CASE_FOLDING_SIMPLE:.*?=\s*&\[(.*?)\];/m, 1]
  body.scan(/\('((?:\\.|[^'])*)',\s*&\[((?:[^\]]|\\\])*)\]\)/).map do |source, values|
    folded = values.scan(/'((?:\\.|[^'])*)'/).flatten.map { |value| rust_char(value) }
    [rust_char(source), folded]
  end
end

def load_property_values(path)
  text = File.read(path)
  result = {}
  text.scan(/\(\s*"([^"]+)",\s*&\[(.*?)\],\s*\)/m) do |property, body|
    result[property] = body.scan(/\("([^"]+)",\s*"([^"]+)"\)/)
  end
  result
end

def class_body(ranges)
  ranges.map do |first, last|
    a = first.to_s(16)
    first == last ? a : "#{a}-#{last.to_s(16)}"
  end.join(',')
end

def complement(ranges)
  sorted = ranges.sort_by(&:first)
  out = []
  cursor = 0
  sorted.each do |first, last|
    out << [cursor, first - 1] if cursor < first
    cursor = [cursor, last + 1].max
  end
  out << [cursor, 0x10ffff] if cursor <= 0x10ffff
  out
end

range_files = {
  'bool' => 'property_bool.rs',
  'gc' => 'general_category.rs',
  'script' => 'script.rs',
  'scx' => 'script_extension.rs',
  'gcb' => 'grapheme_cluster_break.rs',
  'sb' => 'sentence_break.rs',
  'wb' => 'word_break.rs',
}
range_tables = range_files.transform_values { |name| load_range_table(File.join(tables, name)) }
perl_word = load_ranges(File.join(tables, 'perl_word.rs'), 'PERL_WORD')
case_folding = load_case_folding(File.join(tables, 'case_folding_simple.rs'))
ages = load_range_table(File.join(tables, 'age.rs'))
age_order = %w[V1_1 V2_0 V2_1 V3_0 V3_1 V3_2 V4_0 V4_1 V5_0 V5_1 V5_2 V6_0 V6_1 V6_2 V6_3 V7_0 V8_0 V9_0 V10_0 V11_0 V12_0 V12_1 V13_0 V14_0 V15_0 V15_1 V16_0]
age_order.each_with_index do |age, index|
  range_tables['age'] ||= {}
  range_tables['age'][age] = age_order[0..index].flat_map { |name| ages.fetch(name) }
end
range_tables['gc']['ASCII'] = [[0, 0x7f]]
range_tables['gc']['Any'] = [[0, 0x10ffff]]
range_tables['gc']['Assigned'] = complement(range_tables['gc'].fetch('Unassigned'))

property_names = load_pairs(File.join(tables, 'property_names.rs'), 'PROPERTY_NAMES')
property_values = load_property_values(File.join(tables, 'property_values.rs'))
property_values['General_Category'] += [['any', 'Any'], ['ascii', 'ASCII'], ['assigned', 'Assigned']]

binary = {}
property_names.each do |alias_name, canonical|
  binary[alias_name] = "bool=#{canonical}" if range_tables['bool'].key?(canonical)
end
property_values.fetch('General_Category').each do |alias_name, canonical|
  binary[alias_name] ||= "gc=#{canonical}"
end
property_values.fetch('Script').each do |alias_name, canonical|
  binary[alias_name] ||= "script=#{canonical}"
end

groups = binary.group_by { |_, key| key }.transform_values { |pairs| pairs.map(&:first).sort }
property_alias_groups = property_names.group_by(&:last).transform_values { |pairs| pairs.map(&:first).sort }

lines = []
lines << 'module regex'
lines << ''
lines << '// Generated from regex-syntax 0.8.8 Unicode 16.0.0 tables.'
lines << 'fn generated_unicode_binary_property_key(normalized string) ?string {'
lines << "\tmatch normalized {"
groups.sort.each do |key, aliases|
  lines << "\t\t#{aliases.map { |name| "'#{name}'" }.join(', ')} { return '#{key}' }"
end
lines << "\t\telse { return none }"
lines << "\t}"
lines << '}'
lines << ''
lines << 'fn generated_unicode_property_name(normalized string) ?string {'
lines << "\tmatch normalized {"
property_alias_groups.sort.each do |canonical, aliases|
  lines << "\t\t#{aliases.map { |name| "'#{name}'" }.join(', ')} { return '#{canonical}' }"
end
lines << "\t\telse { return none }"
lines << "\t}"
lines << '}'
lines << ''
lines << 'fn generated_unicode_property_value(property string, normalized string) ?string {'
lines << "\tmatch property + '=' + normalized {"
property_values.sort.each do |property, pairs|
  pairs.group_by(&:last).sort.each do |canonical, aliases|
    names = aliases.map(&:first).sort.map { |name| "'#{property}=#{name}'" }
    lines << "\t\t#{names.join(', ')} { return '#{canonical}' }"
  end
end
lines << "\t\telse { return none }"
lines << "\t}"
lines << '}'
lines << ''
lines << 'fn generated_unicode_property_encoded(key string) ?string {'
lines << "\tmatch key {"
range_tables.sort.each do |table, values|
  values.sort.each do |name, ranges|
    lines << "\t\t'#{table}=#{name}' { return r'#{class_body(ranges)}' }"
  end
end
lines << "\t\telse { return none }"
lines << "\t}"
lines << '}'
lines << ''
lines << 'fn generated_unicode_property_body(key string) ?string {'
lines << "\tencoded := generated_unicode_property_encoded(key) or { return none }"
lines << "\treturn generated_unicode_range_body(encoded)"
lines << '}'
lines << ''
lines << 'fn generated_unicode_word_encoded() string {'
lines << "\treturn r'#{class_body(perl_word)}'"
lines << '}'
lines << ''
lines << 'fn generated_unicode_word_body() string {'
lines << "\treturn generated_unicode_range_body(generated_unicode_word_encoded())"
lines << '}'
lines << ''

File.write(output, lines.join("\n"))

if backend_output
  backend = []
  backend << 'module pcre'
  backend << ''
  backend << '// Generated from regex-syntax 0.8.8 Unicode 16.0.0 PERL_WORD.'
  backend << 'const unicode_word_range_starts = ['
  perl_word.each { |first, _| backend << "\tu32(0x#{first.to_s(16)})," }
  backend << ']'
  backend << ''
  backend << 'const unicode_word_range_ends = ['
  perl_word.each { |_, last| backend << "\tu32(0x#{last.to_s(16)})," }
  backend << ']'
  backend << ''
  backend << '@[inline]'
  backend << 'fn is_unicode_word_char(r rune) bool {'
  backend << "\tvalue := u32(r)"
  backend << "\tmut low := 0"
  backend << "\tmut high := unicode_word_range_starts.len"
  backend << "\tfor low < high {"
  backend << "\t\tmid := low + (high - low) / 2"
  backend << "\t\tif value < unicode_word_range_starts[mid] {"
  backend << "\t\t\thigh = mid"
  backend << "\t\t} else if value > unicode_word_range_ends[mid] {"
  backend << "\t\t\tlow = mid + 1"
  backend << "\t\t} else {"
  backend << "\t\t\treturn true"
  backend << "\t\t}"
  backend << "\t}"
  backend << "\treturn false"
  backend << '}'
  backend << ''
  File.write(backend_output, backend.join("\n"))
end


if case_output
  cases = []
  cases << 'module meta'
  cases << ''
  cases << '// Generated from regex-syntax 0.8.8 Unicode 16.0.0 CASE_FOLDING_SIMPLE.'
  cases << 'struct UnicodeSimpleCase {'
  cases << "\tone rune"
  cases << "\ttwo rune"
  cases << "\tthree rune"
  cases << "\tlen u8"
  cases << '}'
  cases << ''
  cases << '@[inline]'
  cases << 'fn unicode_simple_case(value rune) UnicodeSimpleCase {'
  cases << "\tmatch u32(value) {"
  case_folding.each do |source, values|
    fields = values.each_with_index.map { |value, i| "#{%w[one two three][i]}: 0x#{value.to_s(16)}" }.join(', ')
    cases << "\t\t0x#{source.to_s(16)} { return UnicodeSimpleCase{#{fields}, len: #{values.length}} }"
  end
  cases << "\t\telse { return UnicodeSimpleCase{} }"
  cases << "\t}"
  cases << '}'
  cases << ''
  cases << '@[inline]'
  cases << 'fn unicode_simple_case_equal(left rune, right rune) bool {'
  cases << "\tif left == right {"
  cases << "\t\treturn true"
  cases << "\t}"
  cases << "\tfolded := unicode_simple_case(left)"
  cases << "\treturn (folded.len >= 1 && right == folded.one)"
  cases << "\t\t|| (folded.len >= 2 && right == folded.two)"
  cases << "\t\t|| (folded.len >= 3 && right == folded.three)"
  cases << '}'
  cases << ''
  cases << '@[inline]'
  cases << 'fn unicode_simple_case_in_range(value rune, first rune, last rune) bool {'
  cases << "\tif value >= first && value <= last {"
  cases << "\t\treturn true"
  cases << "\t}"
  cases << "\tfolded := unicode_simple_case(value)"
  cases << "\treturn (folded.len >= 1 && folded.one >= first && folded.one <= last)"
  cases << "\t\t|| (folded.len >= 2 && folded.two >= first && folded.two <= last)"
  cases << "\t\t|| (folded.len >= 3 && folded.three >= first && folded.three <= last)"
  cases << '}'
  cases << ''
  File.write(case_output, cases.join("\n"))
end
