#ifndef RIPGREP_V_CORE_FLAGS_STAT_TIME_H
#define RIPGREP_V_CORE_FLAGS_STAT_TIME_H

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
