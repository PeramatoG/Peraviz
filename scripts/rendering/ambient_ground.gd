extends RefCounted
## Setup-only fallback ground coverage. Never mutate imported nodes or resources.
const EMPTY_SIZE := Vector2(200.0, 200.0)
const MARGIN_M := 20.0
const FLOOR_CLEARANCE_M := 0.05

static func fit(ground: MeshInstance3D, bounds: AABB, has_bounds: bool) -> void:
	var plane := ground.mesh as PlaneMesh
	if plane == null:
		return
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not has_bounds:
		plane.size = EMPTY_SIZE
		ground.position = Vector3.ZERO
		return
	plane.size = Vector2(maxf(EMPTY_SIZE.x, bounds.size.x + MARGIN_M * 2.0), maxf(EMPTY_SIZE.y, bounds.size.z + MARGIN_M * 2.0))
	var center := bounds.get_center()
	ground.global_position = Vector3(center.x, minf(0.0, bounds.position.y) - FLOOR_CLEARANCE_M, center.z)
