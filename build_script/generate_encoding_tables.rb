#!/usr/bin/env ruby
# Generates the single-byte decoder tables used by searcher from encoding_rs.
# Usage: generate_encoding_tables.rb path/to/encoding_rs/src/data.rs output.v

abort "usage: #{$PROGRAM_NAME} encoding_rs/src/data.rs output.v" unless ARGV.length == 2

source = File.read(ARGV[0])
names = source[/pub struct SingleByteData \{(.*?)\n\}/m, 1]
  .scan(/pub ([a-z0-9_]+): \[u16; 128\]/).flatten
tables = names.map do |name|
  body = source[/\n    #{Regexp.escape(name)}: \[(.*?)\n    \],/m, 1]
  abort "missing table #{name}" unless body
  values = body.scan(/0x[0-9A-Fa-f]+/)
  abort "#{name} has #{values.length} entries" unless values.length == 128
  values
end

aliases = {
  'IBM866' => 'ibm866',
  'ISO-8859-2' => 'iso_8859_2',
  'ISO-8859-3' => 'iso_8859_3',
  'ISO-8859-4' => 'iso_8859_4',
  'ISO-8859-5' => 'iso_8859_5',
  'ISO-8859-6' => 'iso_8859_6',
  'ISO-8859-7' => 'iso_8859_7',
  'ISO-8859-8' => 'iso_8859_8',
  'ISO-8859-10' => 'iso_8859_10',
  'ISO-8859-13' => 'iso_8859_13',
  'ISO-8859-14' => 'iso_8859_14',
  'ISO-8859-15' => 'iso_8859_15',
  'ISO-8859-16' => 'iso_8859_16',
  'KOI8-R' => 'koi8_r',
  'KOI8-U' => 'koi8_u',
  'MACINTOSH' => 'macintosh',
  'WINDOWS-874' => 'windows_874',
  'WINDOWS-1250' => 'windows_1250',
  'WINDOWS-1251' => 'windows_1251',
  'WINDOWS-1252' => 'windows_1252',
  'WINDOWS-1253' => 'windows_1253',
  'WINDOWS-1254' => 'windows_1254',
  'WINDOWS-1255' => 'windows_1255',
  'WINDOWS-1256' => 'windows_1256',
  'WINDOWS-1257' => 'windows_1257',
  'WINDOWS-1258' => 'windows_1258',
  'MAC-CYRILLIC' => 'x_mac_cyrillic'
}

output = +<<~V
  module searcher

  // Generated from encoding_rs 0.8.35 `SINGLE_BYTE_DATA` by
  // build_script/generate_encoding_tables.rb. A zero entry is an unmapped
  // byte and is decoded as the Unicode replacement character.
  const encoding_single_byte_tables = [
V
tables.each do |values|
  values.each_slice(8) do |slice|
    output << "\t" << slice.map { |value| "u16(#{value.downcase})" }.join(', ') << ",\n"
  end
end
output << "]\n\n"
output << "fn encoding_single_byte_table_id(label string) int {\n\treturn match label.to_upper() {\n"
aliases.each do |label, name|
  output << "\t\t'#{label}' { #{names.index(name)} }\n"
end
output << "\t\telse { -1 }\n\t}\n}\n\n"
output << <<~V
  fn decode_encoding_single_byte(slice []u8, label string) ?[]u8 {
      table_id := encoding_single_byte_table_id(label)
      if table_id < 0 {
          return none
      }
	return decode_encoding_single_byte_table(slice, table_id)
  }

  fn decode_encoding_single_byte_table(slice []u8, table_id int) []u8 {
      mut out := []u8{cap: slice.len}
      base := table_id * 128
      for byte in slice {
          if byte < 0x80 {
              append_utf8(mut out, u32(byte))
              continue
          }
          mapped := encoding_single_byte_tables[base + int(byte) - 0x80]
          append_utf8(mut out, if mapped == 0 { u32(0xfffd) } else { u32(mapped) })
      }
      return out
  }
V

File.write(ARGV[1], output)
