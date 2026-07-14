module printer

/// A writer that counts the number of bytes that have been successfully
/// written.
pub struct CounterWriter[W] implements IClone {
mut:
	wtr          W
	count_       u64
	total_count_ u64
}

pub fn CounterWriter.new[W](wtr W) CounterWriter[W] {
	return CounterWriter[W]{
		wtr: wtr
	}
}

/// Returns the total number of bytes written since construction or the
/// last time `reset` was called.
pub fn (w CounterWriter[W]) count() u64 {
	return w.count_
}

/// Returns the total number of bytes written since construction.
pub fn (w CounterWriter[W]) total_count() u64 {
	return w.total_count_ + w.count_
}

/// Resets the number of bytes written to `0`.
pub fn (mut w CounterWriter[W]) reset_count() {
	w.total_count_ += w.count_
	w.count_ = 0
}

/// Return a mutable reference to the underlying writer.
pub fn (mut w CounterWriter[W]) get_mut() &W {
	return &w.wtr
}

pub fn (mut w CounterWriter[W]) write(buf []u8) !int {
	$if W is WriteColor {
		n := w.wtr.write(buf)!
		w.count_ += u64(n)
		return n
	} $else {
		_ = buf
		return error('CounterWriter requires a WriteColor implementation')
	}
}

pub fn (mut w CounterWriter[W]) flush() ! {
	$if W is WriteColor {
		w.wtr.flush()!
	} $else {
		return error('CounterWriter requires a WriteColor implementation')
	}
}

pub fn (mut w CounterWriter[W]) set_color(spec ColorSpec) ! {
	$if W is WriteColor {
		w.wtr.set_color(spec)!
	} $else {
		_ = spec
		return error('CounterWriter requires a WriteColor implementation')
	}
}

pub fn (mut w CounterWriter[W]) set_hyperlink(link HyperlinkSpec) ! {
	$if W is WriteColor {
		w.wtr.set_hyperlink(link)!
	} $else {
		_ = link
		return error('CounterWriter requires a WriteColor implementation')
	}
}

pub fn (mut w CounterWriter[W]) reset() ! {
	$if W is WriteColor {
		w.wtr.reset()!
	} $else {
		return error('CounterWriter requires a WriteColor implementation')
	}
}

pub fn (w CounterWriter[W]) supports_color() bool {
	$if W is WriteColor {
		return w.wtr.supports_color()
	} $else {
		return false
	}
}

pub fn (w CounterWriter[W]) supports_hyperlinks() bool {
	$if W is WriteColor {
		return w.wtr.supports_hyperlinks()
	} $else {
		return false
	}
}

pub fn (w CounterWriter[W]) is_synchronous() bool {
	$if W is WriteColor {
		return w.wtr.is_synchronous()
	} $else {
		return true
	}
}

pub fn (w CounterWriter[W]) into_inner() W {
	return w.wtr
}
