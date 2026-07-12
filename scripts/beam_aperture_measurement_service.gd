extends RefCounted
class_name BeamApertureMeasurementService

const CONFIDENCE_NONE: float = 0.0
const CONFIDENCE_MESH_SLICE: float = 0.9
const BEAM_LOCAL_DIRECTION: Vector3 = Vector3(0.0, -1.0, 0.0)
const BEAM_LOCAL_U: Vector3 = Vector3(1.0, 0.0, 0.0)
const BEAM_LOCAL_V: Vector3 = Vector3(0.0, 0.0, 1.0)

func measure_circular_aperture(beam_root: Node3D, require_name_hints: bool = true) -> Dictionary:
	if beam_root == null:
		return _empty_result("missing Beam geometry node")
	var samples: Array[Vector3] = []
	_collect_samples(beam_root, beam_root.global_transform.affine_inverse(), require_name_hints, samples)
	if samples.is_empty() and require_name_hints:
		_collect_samples(beam_root, beam_root.global_transform.affine_inverse(), false, samples)
	if samples.is_empty():
		return _empty_result("empty Beam-owned mesh surfaces")
	var max_y: float = -INF
	for p in samples:
		if _is_finite_vector(p):
			max_y = max(max_y, p.y)
	if not is_finite(max_y):
		return _empty_result("non-finite Beam-owned mesh samples")
	var tolerance: float = 0.002
	var radius: float = 0.0
	var half_width: float = 0.0
	var half_height: float = 0.0
	var used: int = 0
	for p in samples:
		if abs(p.y - max_y) > tolerance:
			continue
		used += 1
		half_width = max(half_width, abs(p.x))
		half_height = max(half_height, abs(p.z))
		radius = max(radius, Vector2(p.x, p.z).length())
	if used < 3 or radius <= 0.0:
		return _empty_result("no output-facing aperture slice")
	return {"measured_model_aperture_radius_m": radius, "measured_aperture_half_width_m": half_width, "measured_aperture_half_height_m": half_height, "measurement_confidence": CONFIDENCE_MESH_SLICE, "measurement_provenance": "beam_owned_mesh_output_slice_xz", "beam_direction": BEAM_LOCAL_DIRECTION, "aperture_u": BEAM_LOCAL_U, "aperture_v": BEAM_LOCAL_V, "sample_count": used}

func _collect_samples(node: Node3D, world_to_beam: Transform3D, require_name_hints: bool, output: Array[Vector3]) -> void:
	if node is MeshInstance3D and ((not require_name_hints) or _is_lens_mesh(node.name)):
		var mesh_instance: MeshInstance3D = node
		if mesh_instance.mesh != null:
			for surface_index in range(mesh_instance.mesh.get_surface_count()):
				var arrays: Array = mesh_instance.mesh.surface_get_arrays(surface_index)
				if arrays.size() <= Mesh.ARRAY_VERTEX:
					continue
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for vertex in vertices:
					output.append(world_to_beam * (mesh_instance.global_transform * vertex))
	for child in node.get_children():
		if child is Node3D:
			_collect_samples(child, world_to_beam, require_name_hints, output)

func _is_lens_mesh(node_name: String) -> bool:
	var n: String = node_name.to_lower()
	return n.contains("lens") or n.contains("glass") or n.contains("emitter") or n.contains("beam")

func _is_finite_vector(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)

func _empty_result(reason: String) -> Dictionary:
	return {"measured_model_aperture_radius_m": 0.0, "measured_aperture_half_width_m": 0.0, "measured_aperture_half_height_m": 0.0, "measurement_confidence": CONFIDENCE_NONE, "measurement_provenance": reason, "beam_direction": BEAM_LOCAL_DIRECTION, "aperture_u": BEAM_LOCAL_U, "aperture_v": BEAM_LOCAL_V}
