#ifndef RIPGREP_V_PCRE2_8_MINIMAL_H
#define RIPGREP_V_PCRE2_8_MINIMAL_H

/*
 * Minimal PCRE2 8-bit declarations used by pcre2_shim.h. These declarations
 * follow PCRE2's public pcre2.h interface and let the optional feature link
 * against platforms such as macOS that ship libpcre2-8 without its SDK header.
 */

#include <stddef.h>
#include <stdint.h>

#define PCRE2_CASELESS          0x00000008u
#define PCRE2_DOTALL            0x00000020u
#define PCRE2_EXTENDED          0x00000080u
#define PCRE2_MULTILINE         0x00000400u
#define PCRE2_UCP               0x00020000u
#define PCRE2_UTF               0x00080000u
#define PCRE2_MATCH_INVALID_UTF 0x04000000u

#define PCRE2_JIT_COMPLETE      0x00000001u
#define PCRE2_NEWLINE_ANYCRLF   5
#define PCRE2_ERROR_NOMATCH     (-1)

#define PCRE2_INFO_CAPTURECOUNT   4
#define PCRE2_INFO_JITSIZE       10
#define PCRE2_INFO_NAMECOUNT     17
#define PCRE2_INFO_NAMEENTRYSIZE 18
#define PCRE2_INFO_NAMETABLE     19

#define PCRE2_CONFIG_JIT      1
#define PCRE2_CONFIG_VERSION 11

#define PCRE2_UNSET (~(size_t)0)

typedef uint8_t PCRE2_UCHAR8;
typedef const PCRE2_UCHAR8 *PCRE2_SPTR8;
#define PCRE2_SIZE size_t

typedef struct pcre2_real_general_context_8 pcre2_general_context_8;
typedef struct pcre2_real_compile_context_8 pcre2_compile_context_8;
typedef struct pcre2_real_match_context_8 pcre2_match_context_8;
typedef struct pcre2_real_code_8 pcre2_code_8;
typedef struct pcre2_real_match_data_8 pcre2_match_data_8;
typedef struct pcre2_real_jit_stack_8 pcre2_jit_stack_8;
typedef pcre2_jit_stack_8 *(*pcre2_jit_callback_8)(void *);

int pcre2_config_8(uint32_t what, void *where);
int pcre2_get_error_message_8(int errorcode, PCRE2_UCHAR8 *buffer, size_t size);

pcre2_compile_context_8 *pcre2_compile_context_create_8(pcre2_general_context_8 *gcontext);
void pcre2_compile_context_free_8(pcre2_compile_context_8 *ccontext);
int pcre2_set_newline_8(pcre2_compile_context_8 *ccontext, uint32_t newline);

pcre2_code_8 *pcre2_compile_8(PCRE2_SPTR8 pattern, size_t length,
	uint32_t options, int *errorcode, size_t *erroroffset,
	pcre2_compile_context_8 *ccontext);
void pcre2_code_free_8(pcre2_code_8 *code);
pcre2_code_8 *pcre2_code_copy_8(const pcre2_code_8 *code);
int pcre2_pattern_info_8(const pcre2_code_8 *code, uint32_t what, void *where);

pcre2_match_context_8 *pcre2_match_context_create_8(pcre2_general_context_8 *gcontext);
void pcre2_match_context_free_8(pcre2_match_context_8 *mcontext);
pcre2_jit_stack_8 *pcre2_jit_stack_create_8(size_t startsize, size_t maxsize,
	pcre2_general_context_8 *gcontext);
void pcre2_jit_stack_assign_8(pcre2_match_context_8 *mcontext,
	pcre2_jit_callback_8 callback, void *data);
void pcre2_jit_stack_free_8(pcre2_jit_stack_8 *jit_stack);
int pcre2_jit_compile_8(pcre2_code_8 *code, uint32_t options);

pcre2_match_data_8 *pcre2_match_data_create_from_pattern_8(
	const pcre2_code_8 *code, pcre2_general_context_8 *gcontext);
void pcre2_match_data_free_8(pcre2_match_data_8 *match_data);
int pcre2_match_8(const pcre2_code_8 *code, PCRE2_SPTR8 subject,
	size_t length, size_t startoffset, uint32_t options,
	pcre2_match_data_8 *match_data, pcre2_match_context_8 *mcontext);
size_t *pcre2_get_ovector_pointer_8(pcre2_match_data_8 *match_data);

#endif
