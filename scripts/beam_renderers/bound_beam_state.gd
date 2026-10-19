extends RefCounted
class_name BoundBeamState

# Presentation cache only. Native dense state remains the control/value owner.
# Resolved once by the adapter; direct three-argument callers share the resource cache.
const META_KEY: StringName = &"peraviz_bound_beam_state"
var resource: MeshInstance3D
var applied_dynamic: Color = Color(-1, -1, -1, -1)
var applied_max: float = -1.0
var applied_response: Color = Color(-1, -1, -1, -1)

static func resolve(beam: MeshInstance3D, bound: BoundBeamState = null) -> BoundBeamState:
	if bound != null:
		bound.bind_resource(beam)
		return bound
	if beam.has_meta(META_KEY):
		return beam.get_meta(META_KEY) as BoundBeamState
	var state := BoundBeamState.new()
	state.bind_resource(beam)
	beam.set_meta(META_KEY, state)
	return state

func bind_resource(beam: MeshInstance3D) -> void:
	if resource != beam:
		resource = beam
		invalidate()

func invalidate() -> void:
	applied_dynamic = Color(-1, -1, -1, -1)
	applied_max = -1.0
	applied_response = Color(-1, -1, -1, -1)

# Broad optics/resource operations can change uniforms outside the dynamic entry.
static func invalidate_resource(beam: MeshInstance3D) -> void:
	if beam.has_meta(META_KEY):
		(beam.get_meta(META_KEY) as BoundBeamState).invalidate()
