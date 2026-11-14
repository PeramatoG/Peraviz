extends RefCounted

# Column normalization removes absolute scale from the volume test. The inverse
# check still rejects underflow/overflow and matrices unusable by Godot's real_t.
static func is_basis_valid(value: Basis) -> bool:
	if not value.is_finite(): return false
	var lengths := Vector3(value.x.length(), value.y.length(), value.z.length())
	if not lengths.is_finite() or lengths.x <= 0.0 or lengths.y <= 0.0 or lengths.z <= 0.0: return false
	var unit := Basis(value.x / lengths.x, value.y / lengths.y, value.z / lengths.z)
	if absf(unit.determinant()) <= 0.000001: return false
	var determinant: float = value.determinant()
	return is_finite(determinant) and determinant != 0.0 and value.inverse().is_finite()
