module flags

$if !windows {
	#include "@VMODROOT/core/flags/stat_time.h"
}

$if !windows {
	fn C.rg_v_birthtime_seconds(path &char, ok &int) i64
}

fn creation_time_for_path(path string) ?i64 {
	$if windows {
		return none
	} $else {
		mut ok := 0
		value := unsafe { C.rg_v_birthtime_seconds(&char(path.str), &ok) }
		if ok == 0 {
			return none
		}
		return value
	}
}
