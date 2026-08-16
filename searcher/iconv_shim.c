#include "iconv_shim.h"

#include <errno.h>

int rg_iconv_error_illegal_sequence(void) {
	return EILSEQ;
}

int rg_iconv_error_incomplete_sequence(void) {
	return EINVAL;
}

int rg_iconv_error_output_full(void) {
	return E2BIG;
}
