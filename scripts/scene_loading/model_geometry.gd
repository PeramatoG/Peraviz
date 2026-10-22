extends RefCounted

# Bounds include every embedded GLB transform, in the model parent's coordinates.
static func inspect(root: Node3D) -> Dictionary:
	var result: Dictionary = {"bounds": AABB(), "has_bounds": false, "meshes": 0, "visible_meshes": 0, "locally_visible_meshes": 0, "valid": true}
	_collect(root, Transform3D.IDENTITY, true, result)
	return result

static func _collect(node: Node3D, parent_transform: Transform3D, inherited_visible: bool, result: Dictionary) -> void:
	var combined: Transform3D = parent_transform * node.transform
	var locally_visible: bool = inherited_visible and node.visible
	if node is MeshInstance3D and node.mesh != null and not bool(node.get_meta("peraviz_dummy_placeholder", false)):
		var renderable: bool = false
		for surface in range(node.mesh.get_surface_count()):
			var vertex_count: int = node.mesh.surface_get_array_len(surface) if node.mesh is ArrayMesh else node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()
			if vertex_count >= 3:
				renderable = true
		if renderable:
			var bounds: AABB = combined * node.get_aabb()
			result.meshes += 1
			if locally_visible: result.locally_visible_meshes += 1
			if node.is_inside_tree() and node.is_visible_in_tree(): result.visible_meshes += 1
			if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.length_squared() == 0:
				result.valid = false
			elif result.has_bounds:
				result.bounds = result.bounds.merge(bounds)
			else:
				result.bounds = bounds
				result.has_bounds = true
	for child in node.get_children():
		if child is Node3D:
			_collect(child, combined, locally_visible, result)

# Apply declared GDTF dimensions outside the imported hierarchy, about its authored origin.
# Mesh/scene resources stay raw and shared; per-model dimension changes are instance-local.
static func dimension_fixture_model(model: Node3D, dimensions: Vector3) -> Dictionary:
	if not dimensions.is_finite() or dimensions.x < 0 or dimensions.y < 0 or dimensions.z < 0:
		return {"ok": false, "error": "invalid_model_dimensions"}
	var source: Dictionary = inspect(model)
	if not source.valid or not source.has_bounds or source.meshes == 0:
		return {"ok": false, "error": "no_renderable_geometry"}
	var desired := Vector3(dimensions.x, dimensions.z, dimensions.y)
	var size: Vector3 = source.bounds.size
	var factors := Vector3.ONE
	for axis in range(3):
		if desired[axis] > 0:
			if size[axis] <= 0:
				return {"ok": false, "error": "degenerate_model_dimension_axis"}
			factors[axis] = desired[axis] / size[axis]
	if not factors.is_finite():
		return {"ok": false, "error": "invalid_model_scale"}
	var wrapper := Node3D.new()
	wrapper.name = "GdtfModel"
	wrapper.scale = factors
	wrapper.set_meta("peraviz_dimension_scale", factors)
	wrapper.add_child(model)
	return {"ok": true, "visual": wrapper}
