#!/usr/bin/env ruby
# Generates compact C lookup tables from the Encoding Standard indexes.
# Usage: generate_multibyte_encoding_tables.rb index-directory output.h

abort "usage: #{$PROGRAM_NAME} index-directory output.h" unless ARGV.length == 2

directory = ARGV[0]

def read_index(path)
  entries = {}
  File.foreach(path) do |line|
    line = line.sub(/#.*/, '').strip
    next if line.empty?
	pointer, codepoint = line.split(/[[:space:]]+/).first(2).map { |value| Integer(value, 0) }
    entries[pointer] = codepoint
  end
  entries
end

indexes = {
  'big5' => read_index(File.join(directory, 'index-big5.txt')),
  'euc_kr' => read_index(File.join(directory, 'index-euc-kr.txt')),
  'gb18030' => read_index(File.join(directory, 'index-gb18030.txt')),
  'jis0208' => read_index(File.join(directory, 'index-jis0208.txt')),
  'jis0212' => read_index(File.join(directory, 'index-jis0212.txt'))
}
ranges = read_index(File.join(directory, 'index-gb18030-ranges.txt')).sort

output = +<<~C
  #ifndef RIPGREP_V_MULTIBYTE_ENCODING_TABLES_H
  #define RIPGREP_V_MULTIBYTE_ENCODING_TABLES_H

  #include <stdint.h>

  /* Generated from the WHATWG Encoding Standard indexes by
     build_script/generate_multibyte_encoding_tables.rb. */
C

indexes.each do |name, entries|
  length = entries.keys.max + 1
  output << "static const uint32_t rg_index_#{name}[#{length}] = {\n"
  entries.each { |pointer, codepoint| output << "  [#{pointer}] = 0x#{codepoint.to_s(16)},\n" }
  output << "};\n\n"
  output << <<~C
    static inline uint32_t rg_index_#{name}_lookup(int pointer) {
      if (pointer < 0 || pointer >= #{length}) return 0;
      return rg_index_#{name}[pointer];
    }

  C
end

output << "static const uint32_t rg_gb18030_range_pointers[#{ranges.length}] = {\n"
ranges.each_slice(8) { |slice| output << '  ' << slice.map(&:first).join(', ') << ",\n" }
output << "};\n"
output << "static const uint32_t rg_gb18030_range_codepoints[#{ranges.length}] = {\n"
ranges.each_slice(8) do |slice|
  output << '  ' << slice.map { |entry| "0x#{entry.last.to_s(16)}" }.join(', ') << ",\n"
end
output << <<~C
  };

  static inline uint32_t rg_gb18030_range_lookup(uint32_t pointer) {
    int low = 0;
    int high = #{ranges.length};
    while (low + 1 < high) {
      int mid = low + (high - low) / 2;
      if (rg_gb18030_range_pointers[mid] <= pointer) low = mid;
      else high = mid;
    }
    if (rg_gb18030_range_pointers[low] > pointer) return 0;
    return rg_gb18030_range_codepoints[low] +
      (pointer - rg_gb18030_range_pointers[low]);
  }

  #endif
C

File.write(ARGV[1], output)
