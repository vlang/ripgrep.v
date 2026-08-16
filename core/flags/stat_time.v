module flags

#include "@VMODROOT/core/flags/stat_time.h"

$if !windows {
	fn C.rg_v_birthtime_seconds(path &char, ok &int) i64
}

$if windows {
	fn C.rg_v_creation_time_seconds(path &u16, ok &int) i64
}

fn creation_time_for_path(path string) ?i64 {
	$if windows {
		mut ok := 0
		wide_path := path.to_wide()
		value := C.rg_v_creation_time_seconds(wide_path, &ok)
		unsafe {
			free(wide_path)
		}
		if ok == 0 {
			return none
		}
		return value
	} $else {
		mut ok := 0
		value := unsafe { C.rg_v_birthtime_seconds(&char(path.str), &ok) }
		if ok == 0 {
			return none
		}
		return value
	}
}
