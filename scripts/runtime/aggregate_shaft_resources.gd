extends RefCounted

const BoundState = preload("res://scripts/beam_renderers/bound_beam_state.gd")

# Renderer replacement reuses native membership, never retired resource-generation handles.
static func prepare(adapter: RefCounted) -> void:
	if adapter._renderer == null or not adapter._renderer.has_method("prepare_deferred_member"): return
	var candidates: Dictionary = {}
	for descriptor in adapter._render_descriptors:
		if int(descriptor.get("presentation_class", 0)) == 1:
			for canonical in descriptor["physical_ids"]: candidates[int(canonical)] = true
	var changes: Dictionary = {}
	for output in adapter._outputs:
		if not candidates.has(output.canonical_id): continue
		for handle in output.lights:
			adapter._renderer.prepare_deferred_member(handle.light, adapter._binding_records[output.index].get("beam_optical_profile", {}))
			var beam: MeshInstance3D = adapter._renderer.get_beam_resource(handle.light)
			if is_instance_valid(beam) and handle.beam != beam:
				adapter._bind_beam_resource(handle, beam)
				changes[handle.light.get_instance_id()] = beam
	if not changes.is_empty() and adapter._loader.has_method("_rebind_native_shaft_instances"):
		adapter._loader._rebind_native_shaft_instances(changes)

# Cold resource lifecycle only. The renderer owns shafts; native dense state owns all physical values.
static func reconcile(adapter: RefCounted) -> void:
	var accepted: Dictionary = {}
	for row in adapter._render_bindings.rows:
		if row.presentation_class == 1:
			for index in row.members: accepted[index] = true
	var changes: Dictionary = {}
	for output in adapter._outputs:
		for handle in output.lights:
			var renderer = adapter._renderer
			if renderer == null: continue
			if not renderer.has_method("defer_member_shaft"):
				if handle.light.has_meta(&"peraviz_deferred_aggregate_shaft"):
					handle.light.remove_meta(&"peraviz_deferred_aggregate_shaft")
					renderer.ensure_beam(handle.light)
					adapter._bind_beam_resource(handle, renderer.get_beam_resource(handle.light))
					changes[handle.light.get_instance_id()] = handle.beam
				continue
			if accepted.has(output.index) and not renderer.shaft_compatibility(handle.light).is_empty() and renderer.defer_member_shaft(handle.light):
				handle.beam = null
				handle.bound_state = BoundState.Cache.new()
				changes[handle.light.get_instance_id()] = null
			elif renderer.is_member_deferred(handle.light):
				renderer.rehydrate_member_shaft(handle.light)
				adapter._bind_beam_resource(handle, renderer.get_beam_resource(handle.light))
				changes[handle.light.get_instance_id()] = handle.beam
	if not changes.is_empty() and adapter._loader.has_method("_rebind_native_shaft_instances"):
		adapter._loader._rebind_native_shaft_instances(changes)

# Samples actual resources at setup/report boundaries, including unique shared resources.
static func counts(adapter: RefCounted) -> Dictionary:
	var materials: Dictionary = {}
	var meshes: Dictionary = {}
	var nodes: int = 0
	for output in adapter._outputs + adapter._render_bindings.aggregate_outputs():
		for handle in output.lights:
			if not is_instance_valid(handle.beam): continue
			nodes += 1
			if handle.beam.material_override != null: materials[handle.beam.material_override.get_instance_id()] = true
			if handle.beam.mesh != null: meshes[handle.beam.mesh.get_instance_id()] = handle.beam.mesh
	var geometry_bytes: int = 0
	for mesh in meshes.values():
		if mesh is ArrayMesh:
			for surface in range(mesh.get_surface_count()):
				geometry_bytes += mesh.surface_get_array_len(surface)*12 + mesh.surface_get_array_index_len(surface)*4
	var result: Dictionary = {"allocated_shaft_nodes": nodes, "unique_shaft_materials": materials.size(), "unique_shaft_meshes": meshes.size(), "nominal_shaft_position_index_bytes": geometry_bytes}
	if adapter._renderer != null and adapter._renderer.has_method("shaft_resource_counters"):
		result.merge(adapter._renderer.shaft_resource_counters())
	return result
