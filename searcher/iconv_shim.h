#ifndef RIPGREP_V_ICONV_SHIM_H
#define RIPGREP_V_ICONV_SHIM_H

int rg_iconv_error_illegal_sequence(void);
int rg_iconv_error_incomplete_sequence(void);
int rg_iconv_error_output_full(void);

#endif
