#ifndef RIPGREP_V_CORE_FLAGS_STAT_TIME_H
#define RIPGREP_V_CORE_FLAGS_STAT_TIME_H

#if defined(_WIN32)
#include <windows.h>

static inline long long rg_v_creation_time_seconds(const wchar_t *wpath, int *ok) {
	WIN32_FILE_ATTRIBUTE_DATA data;
	if (!GetFileAttributesExW(wpath, GetFileExInfoStandard, &data)) {
		*ok = 0;
		return 0;
	}
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

static inline long long rg_v_birthtime_seconds(const char *path, int *ok) {
	struct stat st;
	if (stat(path, &st) != 0) {
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
