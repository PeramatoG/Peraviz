extends RefCounted

# Internal presentation cache only. No global class registration or renderer dependency.
# Native dense state remains the control/value owner.
const META_KEY: StringName = &"peraviz_bound_beam_state"

class Cache extends RefCounted:
	var resource: MeshInstance3D
	var applied_dynamic: Color = Color(-1, -1, -1, -1)
	var applied_max: float = -1.0
	var applied_response: Color = Color(-1, -1, -1, -1)

	func bind_resource(beam: MeshInstance3D) -> void:
		if resource != beam:
			resource = beam
			invalidate()

	func invalidate() -> void:
		applied_dynamic = Color(-1, -1, -1, -1)
		applied_max = -1.0
		applied_response = Color(-1, -1, -1, -1)

# Direct callers share the resource cache; the adapter supplies a pre-bound cache.
static func resolve(beam: MeshInstance3D, bound: RefCounted = null) -> Cache:
	if bound != null:
		bound.bind_resource(beam)
		return bound as Cache
	if beam.has_meta(META_KEY):
		return beam.get_meta(META_KEY) as Cache
	var state := Cache.new()
	state.bind_resource(beam)
	beam.set_meta(META_KEY, state)
	return state

# Broad optics/resource operations can change uniforms outside the dynamic entry.
static func invalidate_resource(beam: MeshInstance3D) -> void:
	if beam.has_meta(META_KEY):
		(beam.get_meta(META_KEY) as Cache).invalidate()
