#ifndef RIPGREP_V_PCRE2_SHIM_H
#define RIPGREP_V_PCRE2_SHIM_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>

static inline uint32_t rg_pcre2_opt_caseless(void) { return PCRE2_CASELESS; }
static inline uint32_t rg_pcre2_opt_dotall(void) { return PCRE2_DOTALL; }
static inline uint32_t rg_pcre2_opt_extended(void) { return PCRE2_EXTENDED; }
static inline uint32_t rg_pcre2_opt_multiline(void) { return PCRE2_MULTILINE; }
static inline uint32_t rg_pcre2_opt_ucp(void) { return PCRE2_UCP; }
static inline uint32_t rg_pcre2_opt_utf(void) { return PCRE2_UTF; }
static inline int rg_pcre2_error_nomatch(void) { return PCRE2_ERROR_NOMATCH; }
static inline size_t rg_pcre2_unset(void) { return PCRE2_UNSET; }

static inline int rg_pcre2_jit_available(void) {
	int jit = 0;
	if (pcre2_config_8(PCRE2_CONFIG_JIT, &jit) != 0) {
		return 0;
	}
	return jit != 0;
}

static inline char *rg_pcre2_version(char *buf, size_t len) {
	if (len == 0) {
		return buf;
	}
	int rc = pcre2_config_8(PCRE2_CONFIG_VERSION, buf);
	if (rc < 0) {
		snprintf(buf, len, "unknown");
	}
	buf[len - 1] = 0;
	return buf;
}

static inline char *rg_pcre2_error_message(int code, char *buf, size_t len) {
	if (len == 0) {
		return buf;
	}
	int rc = pcre2_get_error_message_8(code, (PCRE2_UCHAR8 *)buf, len);
	if (rc < 0) {
		snprintf(buf, len, "PCRE2 error %d", code);
	}
	buf[len - 1] = 0;
	return buf;
}

static inline pcre2_code_8 *rg_pcre2_compile(
	const unsigned char *pattern,
	size_t len,
	uint32_t options,
	int crlf,
	int *errorcode,
	size_t *erroroffset
) {
	pcre2_compile_context_8 *ctx = NULL;
	if (crlf) {
		ctx = pcre2_compile_context_create_8(NULL);
		if (ctx != NULL) {
			pcre2_set_newline_8(ctx, PCRE2_NEWLINE_ANYCRLF);
		}
	}
	pcre2_code_8 *code = pcre2_compile_8(
		(PCRE2_SPTR8)pattern,
		len,
		options,
		errorcode,
		(PCRE2_SIZE *)erroroffset,
		ctx
	);
	if (ctx != NULL) {
		pcre2_compile_context_free_8(ctx);
	}
	return code;
}

static inline int rg_pcre2_jit_compile(pcre2_code_8 *code) {
	return pcre2_jit_compile_8(code, PCRE2_JIT_COMPLETE);
}

static inline void *rg_pcre2_match_context_create(size_t max_jit_stack_size) {
	pcre2_match_context_8 *ctx = pcre2_match_context_create_8(NULL);
	if (ctx == NULL) {
		return NULL;
	}
	if (max_jit_stack_size > 0) {
		pcre2_jit_stack_8 *stack = pcre2_jit_stack_create_8(
			32 * 1024,
			max_jit_stack_size,
			NULL
		);
		if (stack != NULL) {
			pcre2_jit_stack_assign_8(ctx, NULL, stack);
		}
	}
	return ctx;
}

static inline pcre2_match_data_8 *rg_pcre2_match_data_create(pcre2_code_8 *code) {
	return pcre2_match_data_create_from_pattern_8(code, NULL);
}

static inline void rg_pcre2_match_data_free(pcre2_match_data_8 *match_data) {
	pcre2_match_data_free_8(match_data);
}

static inline int rg_pcre2_match(
	pcre2_code_8 *code,
	const unsigned char *subject,
	size_t len,
	size_t start,
	uint32_t options,
	pcre2_match_data_8 *match_data,
	void *match_context
) {
	return pcre2_match_8(
		code,
		(PCRE2_SPTR8)subject,
		len,
		start,
		options,
		match_data,
		(pcre2_match_context_8 *)match_context
	);
}

static inline size_t *rg_pcre2_ovector(pcre2_match_data_8 *match_data) {
	return (size_t *)pcre2_get_ovector_pointer_8(match_data);
}

static inline uint32_t rg_pcre2_capture_count(pcre2_code_8 *code) {
	uint32_t count = 0;
	pcre2_pattern_info_8(code, PCRE2_INFO_CAPTURECOUNT, &count);
	return count;
}

static inline uint32_t rg_pcre2_name_count(pcre2_code_8 *code) {
	uint32_t count = 0;
	pcre2_pattern_info_8(code, PCRE2_INFO_NAMECOUNT, &count);
	return count;
}

static inline uint32_t rg_pcre2_name_entry_size(pcre2_code_8 *code) {
	uint32_t size = 0;
	pcre2_pattern_info_8(code, PCRE2_INFO_NAMEENTRYSIZE, &size);
	return size;
}

static inline unsigned char *rg_pcre2_name_table(pcre2_code_8 *code) {
	PCRE2_SPTR8 table = NULL;
	pcre2_pattern_info_8(code, PCRE2_INFO_NAMETABLE, &table);
	return (unsigned char *)table;
}

static inline uint32_t rg_pcre2_name_entry_group(
	unsigned char *table,
	uint32_t entry_size,
	uint32_t index
) {
	unsigned char *entry = table + (entry_size * index);
	return ((uint32_t)entry[0] << 8) | (uint32_t)entry[1];
}

static inline unsigned char *rg_pcre2_name_entry_name(
	unsigned char *table,
	uint32_t entry_size,
	uint32_t index
) {
	unsigned char *entry = table + (entry_size * index);
	return entry + 2;
}

#endif
