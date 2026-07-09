#ifndef RIPGREP_V_CORE_FLAGS_STAT_TIME_H
#define RIPGREP_V_CORE_FLAGS_STAT_TIME_H

#if defined(_WIN32)
#include <stdlib.h>
#include <windows.h>

static inline long long rg_v_creation_time_seconds(const char *path, int *ok) {
	int wlen = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
	if (wlen <= 0) {
		*ok = 0;
		return 0;
	}
	wchar_t *wpath = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)wlen);
	if (wpath == NULL) {
		*ok = 0;
		return 0;
	}
	if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wpath, wlen) <= 0) {
		free(wpath);
		*ok = 0;
		return 0;
	}
	WIN32_FILE_ATTRIBUTE_DATA data;
	if (!GetFileAttributesExW(wpath, GetFileExInfoStandard, &data)) {
		free(wpath);
		*ok = 0;
		return 0;
	}
	free(wpath);
	ULARGE_INTEGER ticks;
	ticks.LowPart = data.ftCreationTime.dwLowDateTime;
	ticks.HighPart = data.ftCreationTime.dwHighDateTime;
	const unsigned long long windows_to_unix_epoch = 116444736000000000ULL;
	if (ticks.QuadPart < windows_to_unix_epoch) {
		*ok = 0;
		return 0;
	}
	*ok = 1;
	return (long long)((ticks.QuadPart - windows_to_unix_epoch) / 10000000ULL);
}
#else
#include <sys/stat.h>

int stat(char *path, void *buf);

static inline long long rg_v_birthtime_seconds(const char *path, int *ok) {
	struct stat st;
	if (stat((char *)path, (void *)&st) != 0) {
		*ok = 0;
		return 0;
	}
#if defined(__APPLE__) || defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__)
	*ok = 1;
	return (long long)st.st_birthtime;
#else
	*ok = 0;
	return 0;
#endif
}
#endif

#endif
