extends RefCounted

# A deliberately narrow opaque StandardMaterial slice. Shafts always retain Vector Prism.
const LENS_SHADER = preload("res://scripts/shaders/instanced_simple_lens.gdshader")
const MIN_BATCH: int = 8
const MAX_BATCH: int = 64
const CELL_SIZE: float = 4.0
var batches: Array = []
var members: Dictionary = {}
var _optical_exclusions: Dictionary = {}
var _native: RefCounted
var _flush_pending: bool = false
var setup_us: int = 0
var created: int = 0
var retired: int = 0
var source_outputs: int = 0

func clear(native: RefCounted) -> void:
	if native != null: native.clear_lenses()
	_native = null
	for batch in batches:
		for entry in batch.entries:
			var mesh: MeshInstance3D = entry.mesh
			if not is_instance_valid(mesh): continue
			if mesh.visibility_changed.is_connected(entry.callback): mesh.visibility_changed.disconnect(entry.callback)
			mesh.layers = entry.layers
		if is_instance_valid(batch.node):
			batch.node.free()
			retired += 1
	batches.clear()
	members.clear()
	_optical_exclusions.clear()

# Every stored material option must equal the reference slice, including new engine options.
# Unknown optical/material combinations remain on the exact existing resource path.
static func _simple_material(material: Material, baseline_options: Dictionary) -> bool:
	if not material is StandardMaterial3D: return false
	for key in baseline_options:
		if material.get(key) != baseline_options[key]: return false
	return true

# Picking bodies/colliders remain under the source mesh; nested graphics require reference ownership.
static func _has_visual_children(node: Node) -> bool:
	for child in node.get_children():
		if child is VisualInstance3D or _has_visual_children(child): return true
	return false

# Finds the nearest mechanical boundary; all intervening transforms are immutable setup geometry.
static func _ancestor(mesh: MeshInstance3D) -> Node3D:
	var node: Node = mesh.get_parent()
	while node is Node3D:
		if node.top_level: return null
		if bool(node.get_meta("peraviz_is_axis", false)): return node
		node = node.get_parent()
	return null

# Setup-only physical-to-instance mapping; no live dictionaries or semantic computations.
func install(adapter: RefCounted) -> void:
	var start: int = Time.get_ticks_usec() if adapter._trace else 0
	clear(adapter._native)
	setup_us = 0
	source_outputs = 0
	for output in adapter._outputs:
		if not output.materials.is_empty(): source_outputs += 1
	_native = adapter._native
	var settings: Dictionary = adapter._loader.get("_visual_settings")
	if RenderingServer.get_current_rendering_method() != "forward_plus" or bool(ProjectSettings.get_setting("rendering/lights_and_shadows/use_physical_light_units", false)): return
	if OS.get_environment("PERAVIZ_GPU_LENSES") == "0" or adapter._mode != "full" or adapter._diagnostic_open_surface_lights or bool(settings.get("beam_debug_optics", false)) or bool(settings.get("enable_realtime_spotlights", false)): return
	var prototype := StandardMaterial3D.new()
	prototype.cull_mode = BaseMaterial3D.CULL_DISABLED
	prototype.emission_enabled = true
	var baseline_options: Dictionary = {}
	for property in prototype.get_property_list():
		var key: StringName = property.name
		if not int(property.usage) & PROPERTY_USAGE_STORAGE: continue
		if str(key).begins_with("resource_") or key in [&"emission", &"emission_energy_multiplier"]: continue
		baseline_options[key] = prototype.get(key)
	var candidates: Dictionary = {}
	var seen: Dictionary = {}
	for output in adapter._outputs:
		# Control groups may share materials; physical lens ownership and all material/optical checks still apply.
		if output.materials.size() != 1 or output.lights.size() != 1: continue
		var light = output.lights[0]
		var entries: Array = adapter._binding_records[output.index].get("lens_material_targets", [])
		if entries.size() != 1 or not entries[0] is Dictionary: continue
		var entry: Dictionary = entries[0]
		var mesh: MeshInstance3D = entry.get("mesh")
		if not is_instance_valid(mesh) or not mesh.mesh is ArrayMesh or mesh.mesh.get_surface_count() != 1 or mesh.get_blend_shape_count() != 0 or mesh.mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES: continue
		if _has_visual_children(mesh): continue
		if seen.has(mesh.get_instance_id()) or mesh.top_level or mesh.skeleton not in [NodePath(), NodePath("..")] or mesh.skin != null or mesh.material_override != null or mesh.material_overlay != null: continue
		if mesh.layers != 1 or mesh.visibility_range_begin != 0.0 or mesh.visibility_range_end != 0.0 or mesh.visibility_parent != NodePath() or mesh.transparency != 0.0: continue
		if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON or mesh.gi_mode != GeometryInstance3D.GI_MODE_STATIC or mesh.extra_cull_margin != 0.0 or mesh.ignore_occlusion_culling or mesh.custom_aabb != AABB() or mesh.lod_bias != 1.0: continue
		if not _simple_material(entry.material, baseline_options): continue
		var ancestor: Node3D = _ancestor(mesh)
		if ancestor == null: continue
		var local: Transform3D = ancestor.global_transform.affine_inverse() * mesh.global_transform
		# Non-invertible/reflected transforms retain the individual reference normal/culling path.
		if local.basis.determinant() <= 0.0 or not local.basis.is_conformal(): continue
		var bounds: AABB = local * mesh.get_aabb()
		if maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) > CELL_SIZE: continue
		var excluded: bool = light.has_gobo or light.light.light_projector != null
		_optical_exclusions[output.index] = excluded
		if excluded: continue
		var cell := Vector3i(floori(local.origin.x / CELL_SIZE), floori(local.origin.y / CELL_SIZE), floori(local.origin.z / CELL_SIZE))
		var key: Array = [ancestor.get_instance_id(), mesh.mesh.get_instance_id(), cell]
		if not candidates.has(key): candidates[key] = []
		candidates[key].append({"mesh": mesh, "output": output.index, "scale": output.materials[0].scale, "transform": local, "ancestor": ancestor, "layers": mesh.layers})
		seen[mesh.get_instance_id()] = true
	var rids: Array = []
	var owners: Array = []
	var buffers: Array = []
	var scales: Array = []
	var shared_material: ShaderMaterial = null
	for group in candidates.values():
		for first in range(0, group.size(), MAX_BATCH):
			var entries: Array = group.slice(first, mini(first + MAX_BATCH, group.size()))
			if entries.size() < MIN_BATCH: continue
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.use_custom_data = true
			multimesh.mesh = entries[0].mesh.mesh
			multimesh.instance_count = entries.size()
			var node := MultiMeshInstance3D.new()
			created += 1
			node.name = "PeravizInstancedApertures"
			node.multimesh = multimesh
			if shared_material == null:
				shared_material = ShaderMaterial.new()
				shared_material.shader = LENS_SHADER
			node.material_override = shared_material
			entries[0].ancestor.add_child(node)
			var ids := PackedInt32Array()
			var gains := PackedFloat32Array()
			var buffer := PackedFloat32Array()
			buffer.resize(entries.size() * 16)
			for slot in range(entries.size()):
				var entry: Dictionary = entries[slot]
				ids.append(entry.output)
				gains.append(entry.scale)
				var t: Transform3D = entry.transform
				# RenderingServer's 3D buffer uses three row-major vec4s followed by custom RGBA.
				var data := PackedFloat32Array([t.basis.x.x, t.basis.y.x, t.basis.z.x, t.origin.x, t.basis.x.y, t.basis.y.y, t.basis.z.y, t.origin.y, t.basis.x.z, t.basis.y.z, t.basis.z.z, t.origin.z])
				for component in range(12): buffer[slot*16+component] = data[component]
				var callback: Callable = _visibility_changed.bind(entry.mesh, batches.size(), slot)
				entry.callback = callback
				entry.mesh.visibility_changed.connect(callback)
				entry.mesh.layers = 0 # Retain canonical/picking nodes and original material; only the batch renders.
				members[entry.output] = Vector2i(batches.size(), slot)
			rids.append(multimesh.get_rid())
			owners.append(ids)
			buffers.append(buffer)
			scales.append(gains)
			batches.append({"node": node, "entries": entries})
	if not _native.install_lenses(adapter._generation, rids, owners, buffers, scales):
		clear(adapter._native)
		return
	for batch_index in range(batches.size()):
		for slot in range(batches[batch_index].entries.size()):
			var mesh: MeshInstance3D = batches[batch_index].entries[slot].mesh
			_native.set_lens_visible(batch_index, slot, mesh.is_visible_in_tree())

	setup_us = Time.get_ticks_usec() - start if adapter._trace else 0

# Existing individual gobo animation must not rebuild unrelated GPU resources.
# Only admitted members or an actual exclusion transition need the cold transaction.
func needs_rebind(index: int, light: SpotLight3D) -> bool:
	if members.has(index): return true
	var excluded: bool = (light.has_meta("peraviz_gobo_texture") and light.get_meta("peraviz_gobo_texture") != null) or light.light_projector != null
	return _optical_exclusions.has(index) and _optical_exclusions[index] != excluded

func counts() -> Dictionary:
	var nodes: int = 0
	var instances: int = 0
	var materials: Dictionary = {}
	var meshes: Dictionary = {}
	for batch in batches:
		if not is_instance_valid(batch.node): continue
		nodes += 1
		instances += batch.node.multimesh.instance_count
		materials[batch.node.material_override.get_instance_id()] = true
		meshes[batch.node.multimesh.mesh.get_instance_id()] = true
	return {"gpu_lens_setup_us": setup_us, "gpu_lens_created_batches": created, "gpu_lens_retired_batches": retired,
		"gpu_lens_fallback_outputs": source_outputs - members.size(), "gpu_lens_source_outputs": source_outputs,
		"allocated_lens_multimesh_nodes": nodes, "allocated_lens_gpu_instances": instances,
		"unique_instanced_lens_materials": materials.size(), "unique_instanced_lens_meshes": meshes.size()}

# Original source visibility is retained (layers alone suppress its duplicate draw).
func _visibility_changed(mesh: MeshInstance3D, batch: int, slot: int) -> void:
	if _native == null or not is_instance_valid(mesh): return
	_native.set_lens_visible(batch, slot, mesh.is_visible_in_tree())
	if not _flush_pending:
		_flush_pending = true
		call_deferred("_flush")

func _flush() -> void:
	_flush_pending = false
	if _native != null: _native.flush_lenses()
