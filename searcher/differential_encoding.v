module searcher

$if encoding_differential ? {
	// differential_decode exposes the production transcoder only to the
	// encoding_rs differential harness.
	pub fn differential_decode(label string, input []u8) ![]u8 {
		mut builder := SearcherBuilder.new()
		builder.encoding(Encoding.new(label)!)
		searcher_ := builder.build()
		return searcher_.transcode_slice(input)
	}
}
