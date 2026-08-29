extends RefCounted
class_name GoboIndexedRotationPresentation

const ANGLE_META := "peraviz_gobo_indexed_rotation_deg"
const BACKEND_META := "peraviz_gobo_rotation_backend"
const BASE_BASIS_META := "peraviz_gobo_base_basis"
const BASE_SHADER_ANGLE_META := "peraviz_gobo_base_shader_rotation_deg"
const SHADER_BACKEND := "shader_mask"

static func apply_physical_angle(beam: MeshInstance3D, physical_angle_degrees: float, backend: String) -> void:
	if beam == null:
		return
	beam.set_meta(ANGLE_META, physical_angle_degrees)
	beam.set_meta(BACKEND_META, backend)
	_reapply(beam, false)

static func reapply_after_base_alignment(beam: MeshInstance3D, base_shader_angle_degrees: Variant = null) -> void:
	if beam == null or not beam.has_meta(ANGLE_META):
		if beam != null and base_shader_angle_degrees != null:
			beam.set_meta(BASE_SHADER_ANGLE_META, float(base_shader_angle_degrees))
		return
	if base_shader_angle_degrees != null:
		beam.set_meta(BASE_SHADER_ANGLE_META, float(base_shader_angle_degrees))
	_reapply(beam, true)

static func physical_angle(beam: MeshInstance3D) -> float:
	return float(beam.get_meta(ANGLE_META, 0.0)) if beam != null else 0.0

static func _reapply(beam: MeshInstance3D, base_alignment_was_refreshed: bool) -> void:
	var backend: String = str(beam.get_meta(BACKEND_META, "vector_prism"))
	var physical_angle_degrees: float = physical_angle(beam)
	if backend == SHADER_BACKEND:
		var base_shader_angle: float = float(beam.get_meta(BASE_SHADER_ANGLE_META, 0.0))
		beam.set_instance_shader_parameter("gobo_rotation_deg", base_shader_angle - physical_angle_degrees)
		return
	if base_alignment_was_refreshed or not beam.has_meta(BASE_BASIS_META):
		beam.set_meta(BASE_BASIS_META, beam.transform.basis)
	var base_basis: Basis = beam.get_meta(BASE_BASIS_META) as Basis
	# Renderer-child local Z is the mapped Beam axis; the sign is presentation handedness only.
	beam.transform.basis = base_basis * Basis(Vector3.FORWARD, deg_to_rad(-physical_angle_degrees))
