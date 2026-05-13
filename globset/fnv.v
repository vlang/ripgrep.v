module globset

/// A hasher that implements the Fowler-Noll-Vo (FNV) hash.
pub struct Hasher implements IClone {
mut:
	value u64
}

const hasher_offset_basis = u64(0xcbf29ce484222325)
const hasher_prime = u64(0x100000001b3)

/// Return the default FNV hasher state.
pub fn Hasher.default() Hasher {
	return Hasher{
		value: hasher_offset_basis
	}
}

/// Return the current hash state.
pub fn (h Hasher) finish() u64 {
	return h.value
}

/// Write bytes into this hasher.
pub fn (mut h Hasher) write(bytes []u8) {
	for byte in bytes {
		h.value = (h.value ^ u64(byte)) * hasher_prime
	}
}
