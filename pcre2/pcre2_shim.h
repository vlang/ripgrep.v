#ifndef RIPGREP_V_PCRE2_SHIM_H
#define RIPGREP_V_PCRE2_SHIM_H

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * V embeds this header before its generated libc declarations and removes the
 * system includes above. Keep the two allocator declarations local to that
 * embedding mode; normal C users continue to get them from <stdlib.h>.
 */
#if RIPGREP_V_C_EMBEDDED
void *calloc(size_t, size_t);
void free(void *);
#endif

#ifndef RIPGREP_V_PCRE2_ENABLED
#define RIPGREP_V_PCRE2_ENABLED 0
#endif

#if RIPGREP_V_PCRE2_ENABLED
#define PCRE2_CODE_UNIT_WIDTH 8
#if defined(__has_include) && __has_include(<pcre2.h>)
#include <pcre2.h>
#else
#include "pcre2_8_minimal.h"
#endif

static inline uint32_t rg_pcre2_opt_caseless(void) { return PCRE2_CASELESS; }
static inline int rg_pcre2_enabled(void) { return 1; }
static inline uint32_t rg_pcre2_opt_dotall(void) { return PCRE2_DOTALL; }
static inline uint32_t rg_pcre2_opt_extended(void) { return PCRE2_EXTENDED; }
static inline uint32_t rg_pcre2_opt_multiline(void) { return PCRE2_MULTILINE; }
static inline uint32_t rg_pcre2_opt_ucp(void) { return PCRE2_UCP; }
static inline uint32_t rg_pcre2_opt_utf(void) { return PCRE2_UTF; }

/* PCRE2_MATCH_INVALID_UTF was introduced in PCRE2 10.34. */
static inline uint32_t rg_pcre2_opt_match_invalid_utf(void) {
#ifdef PCRE2_MATCH_INVALID_UTF
	return PCRE2_MATCH_INVALID_UTF;
#else
	return 0;
#endif
}
static inline int rg_pcre2_error_nomatch(void) { return PCRE2_ERROR_NOMATCH; }
static inline size_t rg_pcre2_unset(void) { return PCRE2_UNSET; }

typedef struct rg_pcre2_regex_8 {
	pcre2_code_8 *code;
	pcre2_match_context_8 *match_context;
	pcre2_jit_stack_8 *jit_stack;
	size_t max_jit_stack_size;
} rg_pcre2_regex_8;

static volatile size_t rg_pcre2_live_regexes = 0;

static inline size_t rg_pcre2_live_regex_count(void) {
	return __atomic_add_fetch(&rg_pcre2_live_regexes, 0, 5);
}

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

static inline void rg_pcre2_code_free(pcre2_code_8 *code) {
	if (code != NULL) {
		pcre2_code_free_8(code);
	}
}

static inline rg_pcre2_regex_8 *rg_pcre2_regex_new(
	pcre2_code_8 *code,
	int use_match_context,
	size_t max_jit_stack_size
) {
	if (code == NULL) {
		return NULL;
	}
	rg_pcre2_regex_8 *regex = (rg_pcre2_regex_8 *)calloc(1, sizeof(rg_pcre2_regex_8));
	if (regex == NULL) {
		pcre2_code_free_8(code);
		return NULL;
	}
	regex->code = code;
	regex->max_jit_stack_size = max_jit_stack_size;
	if (use_match_context) {
		regex->match_context = pcre2_match_context_create_8(NULL);
		if (regex->match_context == NULL) {
			pcre2_code_free_8(code);
			free(regex);
			return NULL;
		}
		if (max_jit_stack_size > 0) {
			regex->jit_stack = pcre2_jit_stack_create_8(
				32 * 1024,
				max_jit_stack_size,
				NULL
			);
			if (regex->jit_stack != NULL) {
				pcre2_jit_stack_assign_8(regex->match_context, NULL, regex->jit_stack);
			}
		}
	}
	__atomic_add_fetch(&rg_pcre2_live_regexes, 1, 5);
	return regex;
}

static inline rg_pcre2_regex_8 *rg_pcre2_regex_clone(rg_pcre2_regex_8 *regex) {
	if (regex == NULL || regex->code == NULL) {
		return NULL;
	}
	pcre2_code_8 *code = pcre2_code_copy_8(regex->code);
	if (code == NULL) {
		return NULL;
	}
	size_t jit_size = 0;
	if (pcre2_pattern_info_8(regex->code, PCRE2_INFO_JITSIZE, &jit_size) == 0
		&& jit_size > 0) {
		if (pcre2_jit_compile_8(code, PCRE2_JIT_COMPLETE) != 0) {
			pcre2_code_free_8(code);
			return NULL;
		}
	}
	return rg_pcre2_regex_new(
		code,
		regex->match_context != NULL,
		regex->max_jit_stack_size
	);
}

static inline void rg_pcre2_regex_free(rg_pcre2_regex_8 *regex) {
	if (regex == NULL) {
		return;
	}
	if (regex->match_context != NULL) {
		pcre2_match_context_free_8(regex->match_context);
	}
	if (regex->jit_stack != NULL) {
		pcre2_jit_stack_free_8(regex->jit_stack);
	}
	if (regex->code != NULL) {
		pcre2_code_free_8(regex->code);
	}
	__atomic_sub_fetch(&rg_pcre2_live_regexes, 1, 5);
	free(regex);
}

static inline pcre2_code_8 *rg_pcre2_regex_code(rg_pcre2_regex_8 *regex) {
	return regex == NULL ? NULL : regex->code;
}

static inline pcre2_match_context_8 *rg_pcre2_regex_match_context(rg_pcre2_regex_8 *regex) {
	return regex == NULL ? NULL : regex->match_context;
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

#else

static inline uint32_t rg_pcre2_opt_caseless(void) { return 0; }
static inline int rg_pcre2_enabled(void) { return 0; }
static inline size_t rg_pcre2_live_regex_count(void) { return 0; }
static inline uint32_t rg_pcre2_opt_dotall(void) { return 0; }
static inline uint32_t rg_pcre2_opt_extended(void) { return 0; }
static inline uint32_t rg_pcre2_opt_multiline(void) { return 0; }
static inline uint32_t rg_pcre2_opt_ucp(void) { return 0; }
static inline uint32_t rg_pcre2_opt_utf(void) { return 0; }
static inline uint32_t rg_pcre2_opt_match_invalid_utf(void) { return 0; }
static inline int rg_pcre2_error_nomatch(void) { return -1; }
static inline size_t rg_pcre2_unset(void) { return (size_t)-1; }
static inline int rg_pcre2_jit_available(void) { return 0; }

static inline char *rg_pcre2_version(char *buf, size_t len) {
	if (len > 0) {
		snprintf(buf, len, "unavailable");
		buf[len - 1] = 0;
	}
	return buf;
}

static inline char *rg_pcre2_error_message(int code, char *buf, size_t len) {
	if (len > 0) {
		snprintf(buf, len, "PCRE2 error %d", code);
		buf[len - 1] = 0;
	}
	return buf;
}

static inline void *rg_pcre2_compile(
	const unsigned char *pattern,
	size_t len,
	uint32_t options,
	int crlf,
	int *errorcode,
	size_t *erroroffset
) {
	(void)pattern;
	(void)len;
	(void)options;
	(void)crlf;
	if (errorcode != NULL) {
		*errorcode = -1;
	}
	if (erroroffset != NULL) {
		*erroroffset = 0;
	}
	return NULL;
}

static inline int rg_pcre2_jit_compile(void *code) {
	(void)code;
	return -1;
}

static inline void rg_pcre2_code_free(void *code) {
	(void)code;
}

static inline void *rg_pcre2_regex_new(
	void *code,
	int use_match_context,
	size_t max_jit_stack_size
) {
	(void)code;
	(void)use_match_context;
	(void)max_jit_stack_size;
	return NULL;
}

static inline void rg_pcre2_regex_free(void *regex) {
	(void)regex;
}

static inline void *rg_pcre2_regex_code(void *regex) {
	(void)regex;
	return NULL;
}

static inline void *rg_pcre2_regex_match_context(void *regex) {
	(void)regex;
	return NULL;
}

static inline void *rg_pcre2_match_data_create(void *code) {
	(void)code;
	return NULL;
}

static inline void rg_pcre2_match_data_free(void *match_data) {
	(void)match_data;
}

static inline int rg_pcre2_match(
	void *code,
	const unsigned char *subject,
	size_t len,
	size_t start,
	uint32_t options,
	void *match_data,
	void *match_context
) {
	(void)code;
	(void)subject;
	(void)len;
	(void)start;
	(void)options;
	(void)match_data;
	(void)match_context;
	return -1;
}

static inline size_t *rg_pcre2_ovector(void *match_data) {
	(void)match_data;
	return NULL;
}

static inline uint32_t rg_pcre2_capture_count(void *code) {
	(void)code;
	return 0;
}

static inline uint32_t rg_pcre2_name_count(void *code) {
	(void)code;
	return 0;
}

static inline uint32_t rg_pcre2_name_entry_size(void *code) {
	(void)code;
	return 0;
}

static inline unsigned char *rg_pcre2_name_table(void *code) {
	(void)code;
	return NULL;
}

static inline uint32_t rg_pcre2_name_entry_group(
	unsigned char *table,
	uint32_t entry_size,
	uint32_t index
) {
	(void)table;
	(void)entry_size;
	(void)index;
	return 0;
}

static inline unsigned char *rg_pcre2_name_entry_name(
	unsigned char *table,
	uint32_t entry_size,
	uint32_t index
) {
	(void)table;
	(void)entry_size;
	(void)index;
	return NULL;
}

#endif

#endif
