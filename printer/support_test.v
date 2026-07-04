module printer

fn test_custom_decimal_format() {
	ints := [u64(0), 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 100, 123, 18446744073709551615]
	for n in ints {
		assert n.str() == DecimalFormatter.new(n).as_bytes().bytestr()
	}
}
