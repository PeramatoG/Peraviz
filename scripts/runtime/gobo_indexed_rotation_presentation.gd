extends RefCounted
class_name GoboIndexedRotationPresentation

const ANGLE_META := "peraviz_gobo_indexed_rotation_deg"
const APPLIED_ANGLE_META := "peraviz_gobo_applied_indexed_rotation_deg"
const BACKEND_META := "peraviz_gobo_rotation_backend"
const BASE_SHADER_ANGLE_META := "peraviz_gobo_base_shader_rotation_deg"
const SHADER_BACKEND := "shader_mask"
const PARENT_ROLL_COMPENSATION_META := "peraviz_gobo_parent_roll_compensation_deg"

static func apply_physical_angle(beam: MeshInstance3D, physical_angle_degrees: float, backend: String) -> void:
	if beam == null:
		return
	beam.set_meta(ANGLE_META, physical_angle_degrees)
	beam.set_meta(BACKEND_META, backend)
	_reapply(beam, false)

static func reapply_after_base_alignment(beam: MeshInstance3D, base_shader_angle_degrees: Variant = null) -> void:
	if beam == null:
		return
	if base_shader_angle_degrees != null:
		beam.set_meta(BASE_SHADER_ANGLE_META, float(base_shader_angle_degrees))
	if not beam.has_meta(ANGLE_META):
		return
	_reapply(beam, true)

static func physical_angle(beam: MeshInstance3D) -> float:
	return float(beam.get_meta(ANGLE_META, 0.0)) if beam != null else 0.0

static func apply_parent_roll_compensation(beam: MeshInstance3D, parent_roll_degrees: float) -> void:
	if beam == null:
		return
	var previous: float = float(beam.get_meta(PARENT_ROLL_COMPENSATION_META, 0.0))
	var desired: float = -parent_roll_degrees
	beam.rotate_object_local(Vector3.UP, deg_to_rad(desired - previous))
	beam.set_meta(PARENT_ROLL_COMPENSATION_META, desired)

static func _reapply(beam: MeshInstance3D, base_alignment_was_refreshed: bool) -> void:
	var backend: String = str(beam.get_meta(BACKEND_META, "vector_prism"))
	var physical_angle_degrees: float = physical_angle(beam)
	if backend == SHADER_BACKEND:
		var base_shader_angle: float = float(beam.get_meta(BASE_SHADER_ANGLE_META, 0.0))
		beam.set_instance_shader_parameter("gobo_rotation_deg", base_shader_angle + physical_angle_degrees)
		return
	var previously_applied: float = 0.0 if base_alignment_was_refreshed else float(beam.get_meta(APPLIED_ANGLE_META, 0.0))
	var presentation_delta: float = physical_angle_degrees - previously_applied
	# Raw prism topology is longitudinal on local Y; spinning around Y leaves its scaled beam-length axis invariant.
	beam.rotate_object_local(Vector3.UP, deg_to_rad(presentation_delta))
	beam.set_meta(APPLIED_ANGLE_META, physical_angle_degrees)
