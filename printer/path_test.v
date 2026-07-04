module printer

import os

fn test_printer_path_as_bytes() {
	path := 'alpha/beta.txt'
	ppath := PrinterPath.new(&path)

	assert ppath.as_bytes().bytestr() == 'alpha/beta.txt'
	assert *ppath.as_path() == path
}

fn test_printer_path_separator() {
	path := 'alpha/beta/gamma.txt'
	ppath := PrinterPath.new(&path).with_separator(u8(92))

	assert ppath.as_bytes().bytestr() == 'alpha\\beta\\gamma.txt'
}

fn test_printer_path_without_separator() {
	path := 'alpha/beta.txt'
	ppath := PrinterPath.new(&path).with_separator(none)

	assert ppath.as_bytes().bytestr() == 'alpha/beta.txt'
}

fn test_printer_path_hyperlink_for_existing_path() {
	path := os.join_path(os.temp_dir(), 'ripgrep_v_printer_path_hyperlink_test.txt')
	os.write_file(path, '')!
	defer {
		os.rm(path) or {}
	}

	mut ppath := PrinterPath.new(&path)
	hyperlink := ppath.as_hyperlink() or { panic('missing hyperlink path') }
	assert hyperlink.bytes.bytestr().starts_with('/')
}
