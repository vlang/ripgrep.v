module flags

fn completion_encodings() string {
	return $embed_file('complete/encodings.sh').to_string()
}
