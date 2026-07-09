#ifndef RIPGREP_V_CORE_MESSAGES_LOCK_H
#define RIPGREP_V_CORE_MESSAGES_LOCK_H

#if defined(_WIN32)
#include <windows.h>

static INIT_ONCE rg_messages_once = INIT_ONCE_STATIC_INIT;
static CRITICAL_SECTION rg_messages_mutex;

static BOOL CALLBACK rg_messages_init_once(PINIT_ONCE once, PVOID param, PVOID *context) {
	(void)once;
	(void)param;
	(void)context;
	InitializeCriticalSection(&rg_messages_mutex);
	return TRUE;
}

static inline void rg_messages_lock(void) {
	InitOnceExecuteOnce(&rg_messages_once, rg_messages_init_once, NULL, NULL);
	EnterCriticalSection(&rg_messages_mutex);
}

static inline void rg_messages_unlock(void) {
	LeaveCriticalSection(&rg_messages_mutex);
}
#else
#include <pthread.h>

static pthread_mutex_t rg_messages_mutex = PTHREAD_MUTEX_INITIALIZER;

static inline void rg_messages_lock(void) {
	pthread_mutex_lock(&rg_messages_mutex);
}

static inline void rg_messages_unlock(void) {
	pthread_mutex_unlock(&rg_messages_mutex);
}
#endif

#endif
