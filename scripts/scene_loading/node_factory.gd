extends RefCounted
class_name NodeFactory

var _missing_cache_roots_reported: Dictionary = {}
var asset_load_summary: Dictionary = {}
var _mesh_facts: Dictionary = {}
var _inspection_metrics: Dictionary = {}
var setup_metrics: Dictionary = {}
var _profile_setup: bool = false
var invalid_basis_fallbacks: int = 0
var fixture_casing_lod: bool = true
const ModelGeometry = preload("res://scripts/scene_loading/model_geometry.gd")
const AssetDiagnostics = preload("res://scripts/scene_loading/scene_asset_diagnostics.gd")
var asset_diagnostics: RefCounted = AssetDiagnostics.new()

func build_node_tree(nodes: Array, proxies_root: Node3D, node_index: Dictionary, rebuild_loaded_bounds: Callable, loader: PeravizLoader, asset_cache: PeravizRuntimeAssetCache, budget: SceneLoadBudget = null) -> bool:
	var constructed: Array[Node3D] = []
	_profile_setup = budget != null and budget.trace_enabled
	setup_metrics = {
		"node_construction_ms":0.0,
		"resource_decode_ms":0.0,
		"scene_instantiation_ms":0.0,
		"material_preparation_ms":0.0,
		"orientation_ms":0.0,
		"dummy_removal_ms":0.0,
		"lod_installation_ms":0.0,
		"bounds_diagnostics_ms":0.0,
		"mesh_decode_calls":0,
		"mesh_build_calls":0,
		"texture_decode_calls":0,
		"scene_decode_calls":0,
		"scene_pack_calls":0,
		"scene_pack_ms":0.0,
		"mesh_creation_ms":0.0,
		"texture_preparation_ms":0.0,
		"scene_clone_calls":0,
		"orientation_plan_ms":0.0,
		"shell_creation_ms":0.0,
		"visual_creation_ms":0.0,
		"visual_attach_ms":0.0,
		"mesh_instance_creation_ms":0.0,
		"mesh_instance_assignment_ms":0.0,
		"dummy_creation_ms":0.0,
		"dummy_instances_created":0,
		"dummy_material_ms":0.0,
		"primitive_creation_ms":0.0,
	}
	asset_cache.model_inspection_metrics = ModelGeometry.new_metrics(_profile_setup)
	_inspection_metrics = asset_cache.model_inspection_metrics
	_mesh_facts = asset_cache.geometry_facts
	node_index.clear()
	_missing_cache_roots_reported.clear()
	invalid_basis_fallbacks = 0
	asset_diagnostics.reset(nodes)
	asset_load_summary = asset_diagnostics.counts
	for item in nodes:
		if budget != null and not await budget.checkpoint():
			_discard_unattached_nodes(constructed)
			return false
		if item is Dictionary:
			var node_id: String = str(item.get("node_id", ""))
			if node_id.is_empty():
				continue
			var started: int = Time.get_ticks_usec() if _profile_setup else 0
			var node: Node3D = create_scene_node(item, loader, asset_cache, true)
			if _profile_setup: setup_metrics.shell_creation_ms += (Time.get_ticks_usec()-started)/1000.0
			if _profile_setup: setup_metrics.node_construction_ms += (Time.get_ticks_usec()-started)/1000.0
			constructed.append(node)
			node_index[node_id] = node

	var plan_started := Time.get_ticks_usec()
	var orientation_flags: Dictionary = await _plan_orientation(nodes,node_index,proxies_root,budget)
	setup_metrics.orientation_plan_ms = (Time.get_ticks_usec()-plan_started)/1000.0
	if budget != null and not budget.valid():
		_discard_unattached_nodes(constructed)
		return false
	for item: Dictionary in nodes:
		if budget != null and not await budget.checkpoint():
			_discard_unattached_nodes(constructed)
			return false
		var id: String = str(item.get("node_id",""))
		var node: Node3D = node_index.get(id)
		if node == null: continue
		var started: int = Time.get_ticks_usec() if _profile_setup else 0
		_install_scene_visual(node,item,loader,asset_cache,bool(orientation_flags.get(id,node.transform.basis.determinant()<0.0)))
		if _profile_setup: setup_metrics.node_construction_ms += (Time.get_ticks_usec()-started)/1000.0

	for item in nodes:
		if budget != null and not await budget.checkpoint():
			_discard_unattached_nodes(constructed)
			return false
		if item is Dictionary:
			var node_id: String = str(item.get("node_id", ""))
			var parent_id: String = str(item.get("parent_id", ""))
			var node: Node3D = node_index.get(node_id)
			if node == null:
				continue
			var parent_node: Node3D = proxies_root
			if not parent_id.is_empty() and node_index.has(parent_id):
				parent_node = node_index[parent_id]
			parent_node.add_child(node)

	var phase_started := Time.get_ticks_usec()
	_apply_mesh_orientation_corrections(proxies_root, false, loader, asset_cache)
	setup_metrics.orientation_ms = (Time.get_ticks_usec()-phase_started)/1000.0
	phase_started = Time.get_ticks_usec()
	_remove_redundant_dummy_meshes(proxies_root)
	setup_metrics.dummy_removal_ms = (Time.get_ticks_usec()-phase_started)/1000.0
	phase_started = Time.get_ticks_usec()
	asset_cache.derived_lods.automatic = fixture_casing_lod
	if not await preload("res://scripts/scene_loading/housing_lod_installation.gd").install(nodes,node_index,asset_cache.derived_lods,budget): return false
	setup_metrics.lod_installation_ms = (Time.get_ticks_usec()-phase_started)/1000.0
	phase_started = Time.get_ticks_usec()
	rebuild_loaded_bounds.call()
	for item: Dictionary in nodes:
		var created: Node3D = node_index.get(str(item.get("node_id", "")))
		if created != null: asset_diagnostics.observe(item, created, asset_cache)
	asset_load_summary["invalid_basis_fallbacks"] = invalid_basis_fallbacks
	if invalid_basis_fallbacks > 0:
		push_warning("[Peraviz] Invalid basis fallback occurrences=%d" % invalid_basis_fallbacks)
	asset_diagnostics.finish()
	setup_metrics.bounds_diagnostics_ms = (Time.get_ticks_usec()-phase_started)/1000.0
	setup_metrics.merge(ModelGeometry.metrics(_inspection_metrics))
	return true

# Generation-local derived flags use the same validated transforms and parent
# IDs as attachment. Resolve in O(nodes), including child-before-parent payloads;
# no scene node is attached early and no alternate live transform state survives.
func _plan_orientation(nodes: Array, index: Dictionary, proxies_root: Node3D, budget: SceneLoadBudget) -> Dictionary:
	var children: Dictionary = {}
	var flags: Dictionary = {}
	var pending: Array[String] = []
	var root_flip: bool = proxies_root.transform.basis.determinant() < 0.0
	for data: Dictionary in nodes:
		if budget != null and not await budget.checkpoint(): return {}
		var id: String = str(data.get("node_id",""))
		var node: Node3D = index.get(id)
		if node == null: continue
		var parent: String = str(data.get("parent_id",""))
		if index.has(parent):
			if not children.has(parent): children[parent] = []
			children[parent].append(id)
		else:
			flags[id] = root_flip != (node.transform.basis.determinant() < 0.0)
			pending.append(id)
	while not pending.is_empty():
		if budget != null and not await budget.checkpoint(): return {}
		var parent: String = pending.pop_back()
		for id: String in children.get(parent,[]):
			var node: Node3D = index[id]
			flags[id] = bool(flags[parent]) != (node.transform.basis.determinant() < 0.0)
			pending.append(id)
	return flags

func _discard_unattached_nodes(constructed: Array[Node3D]) -> void:
	for node in constructed:
		if is_instance_valid(node) and node.get_parent() == null:
			node.free()

func create_scene_node(data: Dictionary, loader: PeravizLoader, asset_cache: PeravizRuntimeAssetCache, defer_visual: bool = false) -> Node3D:
	var item_type: String = str(data.get("type", "scene_object"))
	var item_class: String = _extract_node_class(data, item_type)
	var is_axis: bool = bool(data.get("is_axis", false))
	var is_emitter: bool = bool(data.get("is_emitter", false))
	var is_lens: bool = bool(data.get("is_lens", false))
	var node_name: String = str(data.get("name", item_type))
	var flip_orientation: bool = false

	var root := Node3D.new()
	root.name = "%s_%s" % [item_class, node_name]
	root.set_meta("peraviz_type", item_type)
	root.set_meta("peraviz_asset_archive_path",str(data.get("asset_archive_path","")))
	root.set_meta("peraviz_model_quality",str(data.get("model_quality","")))
	root.set_meta("peraviz_is_axis", is_axis)
	root.set_meta("peraviz_is_emitter", is_emitter)
	root.set_meta("peraviz_is_lens", is_lens)
	root.set_meta("peraviz_is_beam", bool(data.get("is_beam", false)))
	root.set_meta("peraviz_gdtf_geometry_key", str(data.get("gdtf_geometry_key", "")))
	root.set_meta("peraviz_gdtf_geometry_path", str(data.get("gdtf_geometry_path", "")))
	var geometry_key: String = str(data.get("gdtf_geometry_key", ""))
	if not geometry_key.is_empty():
		var separator: int = geometry_key.find("/")
		root.set_meta("peraviz_fixture_uuid", geometry_key if separator < 0 else geometry_key.substr(0, separator))
	var node_position: Vector3 = _safe_position(data.get("pos", Vector3.ZERO), "create_scene_node:" + root.name)
	if bool(data.get("has_basis", false)):
		var node_basis: Basis = _safe_basis_from_data(data)
		flip_orientation = node_basis.determinant() < 0.0
		root.transform = Transform3D(node_basis, node_position)
	else:
		root.position = node_position
		root.rotation_degrees = data.get("rot", Vector3.ZERO)
		root.scale = _safe_scale_from_data(data, "create_scene_node_euler:" + root.name)
		flip_orientation = root.transform.basis.determinant() < 0.0

	if is_axis:
		var pivot := Node3D.new()
		pivot.name = "AxisPivot"
		root.add_child(pivot)

	if is_emitter:
		var emitter := Node3D.new()
		emitter.name = "EmitterMarker"
		root.add_child(emitter)

	if not defer_visual:
		_install_scene_visual(root,data,loader,asset_cache,flip_orientation)
	return root

func _install_scene_visual(root: Node3D, data: Dictionary, loader: PeravizLoader, asset_cache: PeravizRuntimeAssetCache, flip_orientation: bool) -> void:
	var item_type: String = str(data.get("type","scene_object"))
	var item_class: String = _extract_node_class(data,item_type)
	var is_fixture: bool = bool(data.get("is_fixture",false))
	var visual_scale_hint: float = _extract_visual_scale_hint(data)
	var started: int = Time.get_ticks_usec() if _profile_setup else 0
	var model_node: Node3D = _build_visual_node(data,item_type,item_class,is_fixture,visual_scale_hint,loader,asset_cache,flip_orientation)
	_record_setup("visual_creation_ms",started)
	started = Time.get_ticks_usec() if _profile_setup else 0
	if model_node != null:
		root.add_child(model_node)
		root.set_meta("peraviz_model_visual",model_node)
	_record_setup("visual_attach_ms",started)

func _is_basis_valid(candidate_basis: Basis) -> bool:
	return preload("res://scripts/scene_loading/transform_validation.gd").is_basis_valid(candidate_basis)

func _safe_basis_from_data(data: Dictionary) -> Basis:
	var basis_x: Vector3 = data.get("basis_x", Vector3.RIGHT)
	var basis_y: Vector3 = data.get("basis_y", Vector3.UP)
	var basis_z: Vector3 = data.get("basis_z", Vector3.BACK)
	var candidate_basis := Basis(basis_x, basis_y, basis_z)
	if _is_basis_valid(candidate_basis):
		return candidate_basis

	invalid_basis_fallbacks += 1
	return Basis.IDENTITY

func _safe_position(value: Vector3, context: String) -> Vector3:
	if is_finite(value.x) and is_finite(value.y) and is_finite(value.z):
		return value
	print("[PeravizCoordDebug] event=invalid_position_fallback context=", context, " pos=", value)
	return Vector3.ZERO

func _safe_scale_from_data(data: Dictionary, context: String) -> Vector3:
	var raw_scale: Vector3 = data.get("scale", Vector3.ONE)
	if not is_finite(raw_scale.x) or not is_finite(raw_scale.y) or not is_finite(raw_scale.z):
		print("[PeravizCoordDebug] event=invalid_scale_fallback context=", context, " scale=", raw_scale)
		return Vector3.ONE

	var min_axis: float = 0.0001
	var sx: float = raw_scale.x
	var sy: float = raw_scale.y
	var sz: float = raw_scale.z
	if sx == 0.0:
		sx = min_axis
	if sy == 0.0:
		sy = min_axis
	if sz == 0.0:
		sz = min_axis

	if not is_equal_approx(sx, raw_scale.x) or not is_equal_approx(sy, raw_scale.y) or not is_equal_approx(sz, raw_scale.z):
		print("[PeravizCoordDebug] event=zero_scale_sanitized context=", context, " raw_scale=", raw_scale, " sanitized_scale=", Vector3(sx, sy, sz))
	return Vector3(sx, sy, sz)

func _apply_mesh_orientation_corrections(node: Node3D, inherited_flip: bool, loader: PeravizLoader, asset_cache: PeravizRuntimeAssetCache) -> void:
	if node == null:
		return

	var node_flip: bool = node.transform.basis.determinant() < 0.0
	var global_flip: bool = inherited_flip != node_flip
	if node is MeshInstance3D:
		_rebuild_mesh_instance_for_orientation(node as MeshInstance3D, global_flip, loader, asset_cache)

	for child in node.get_children():
		if child is Node3D:
			_apply_mesh_orientation_corrections(child as Node3D, global_flip, loader, asset_cache)

func _rebuild_mesh_instance_for_orientation(mesh_instance: MeshInstance3D, flip_orientation: bool, loader: PeravizLoader, asset_cache: PeravizRuntimeAssetCache) -> void:
	if mesh_instance == null:
		return
	if not mesh_instance.has_meta("peraviz_asset_path"):
		return
	var asset_path: String = str(mesh_instance.get_meta("peraviz_asset_path", ""))
	if asset_path.is_empty():
		return

	var mesh_cache_key: String = asset_path
	if flip_orientation:
		mesh_cache_key = "%s#flipped" % asset_path

	var cached_mesh: Mesh = asset_cache.get_mesh(mesh_cache_key)
	if cached_mesh == null:
		var mesh_data: Dictionary = _decode_3ds_mesh(asset_path,loader)
		if not bool(mesh_data.get("ok", false)):
			return
		var rebuilt_mesh: ArrayMesh = _build_3ds_mesh(mesh_data, flip_orientation, asset_cache)
		if rebuilt_mesh == null:
			return
		asset_cache.store_mesh(mesh_cache_key, rebuilt_mesh)
		cached_mesh = rebuilt_mesh

	mesh_instance.mesh = cached_mesh
	mesh_instance.set_meta("peraviz_flip_orientation_applied", flip_orientation)

func _remove_redundant_dummy_meshes(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		_remove_redundant_dummy_meshes(child)
	if root is not Node3D:
		return
	var root_node: Node3D = root
	var placeholders_to_remove: Array[Node] = []
	for child in root_node.get_children():
		if child is MeshInstance3D and bool(child.get_meta("peraviz_dummy_placeholder", false)) and not bool(child.get_meta("peraviz_keep_partial_placeholder", false)):
			placeholders_to_remove.push_back(child)
	if placeholders_to_remove.is_empty():
		return
	if not _node_has_real_visual_descendants(root_node, placeholders_to_remove):
		return
	for placeholder in placeholders_to_remove:
		if root_node.has_meta("peraviz_model_visual") and root_node.get_meta("peraviz_model_visual") == placeholder:
			root_node.remove_meta("peraviz_model_visual")
		root_node.remove_child(placeholder)
		placeholder.queue_free()

func _node_has_real_visual_descendants(root: Node, ignored_nodes: Array[Node]) -> bool:
	if root is MeshInstance3D:
		if not bool(root.get_meta("peraviz_dummy_placeholder", false)):
			return true
	elif root is MultiMeshInstance3D:
		return true
	for child in root.get_children():
		if ignored_nodes.has(child):
			continue
		if _node_has_real_visual_descendants(child, ignored_nodes):
			return true
	return false

func _build_visual_node(data: Dictionary, item_type: String, _item_class: String, is_fixture: bool, visual_scale_hint: float, loader: PeravizLoader, asset_cache: PeravizRuntimeAssetCache, flip_orientation: bool = false) -> Node3D:
	if item_type == "group": return null
	var asset_path: String = str(data.get("asset_path", ""))
	var asset_kind: String = _extract_asset_kind(data, asset_path)
	var failed: bool = not str(data.get("asset_error", "")).is_empty()
	if not asset_path.is_empty():
		var loaded: Variant = _load_3d_asset(asset_path, loader, asset_cache, asset_kind, flip_orientation)
		if loaded is Node3D:
			var visual: Node3D = loaded
			if item_type == "fixture_geometry":
				var normalized: Dictionary = ModelGeometry.dimension_fixture_model(visual, data.get("model_dimensions", Vector3.ZERO), asset_cache.geometry_facts, asset_cache.model_inspection_metrics)
				if normalized.ok:
					visual = normalized.visual
				else:
					visual.free()
					visual = null
					# Dimensions belong to this model instance, not to the shared raw resource.
					data["asset_error"] = normalized.error
					data["asset_error_stage"] = "mesh_creation"
			if visual != null:
				var material_started: int = Time.get_ticks_usec() if _profile_setup else 0
				var immutable_scenery: bool = item_type == "model_part" and not is_fixture and (asset_path.get_extension().to_lower() == "3ds" or bool(visual.get_meta("peraviz_static_scenery",false)))
				_force_double_sided_materials(visual, asset_cache if immutable_scenery else null)
				if _profile_setup: setup_metrics.material_preparation_ms += (Time.get_ticks_usec()-material_started)/1000.0
				return visual
		failed = true
	if item_type == "fixture" or item_type == "fixture_geometry":
		var primitive: String = str(data.get("primitive_type", "")).to_lower()
		var known_primitive: bool = primitive in ["cube", "cylinder", "sphere", "base", "yoke", "head", "scanner", "conventional", "pigtail", "base1_1", "scanner1_1", "conventional1_1"]
		if known_primitive or failed:
			var primitive_started: int = Time.get_ticks_usec() if _profile_setup else 0
			var substitute: Node3D = _create_gdtf_primitive_mesh(data)
			_record_setup("primitive_creation_ms",primitive_started)
			if failed:
				substitute.set_meta("peraviz_model_fallback", true)
				substitute.set_meta("peraviz_dummy_placeholder", true)
				substitute.set_meta("peraviz_keep_partial_placeholder", true)
				var fallback_material := StandardMaterial3D.new()
				fallback_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				fallback_material.albedo_color = Color(1.0, 0.55, 0.1, 0.18)
				fallback_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				fallback_material.cull_mode = BaseMaterial3D.CULL_DISABLED
				(substitute as MeshInstance3D).material_override = fallback_material
			_force_double_sided_materials(substitute)
			return substitute
		if not primitive.is_empty() and primitive != "undefined":
			data["asset_error"] = "unsupported_primitive"
		return null
	var dummy_started: int = Time.get_ticks_usec() if _profile_setup else 0
	var dummy: Node3D = _create_dummy_mesh(is_fixture, visual_scale_hint)
	_record_setup("dummy_creation_ms",dummy_started)
	if failed: dummy.set_meta("peraviz_model_fallback", true)
	# Built-in dummy materials are already independent and double-sided.
	return dummy

func _force_double_sided_materials(root: Node, static_cache: PeravizRuntimeAssetCache = null) -> void:
	if root == null:
		return
	if root is MeshInstance3D:
		_apply_double_sided_to_mesh_instance(root as MeshInstance3D, static_cache)
	elif root is MultiMeshInstance3D:
		_apply_double_sided_to_multimesh_instance(root as MultiMeshInstance3D, static_cache)
	for child in root.get_children():
		_force_double_sided_materials(child, static_cache)

func _apply_double_sided_to_mesh_instance(mesh_instance: MeshInstance3D, static_cache: PeravizRuntimeAssetCache = null) -> void:
	if mesh_instance == null:
		return
	if mesh_instance.material_override != null:
		mesh_instance.material_override = _duplicate_as_double_sided(mesh_instance.material_override, static_cache)
	_apply_double_sided_to_mesh_surfaces(mesh_instance, mesh_instance.mesh, static_cache)

func _apply_double_sided_to_multimesh_instance(multimesh_instance: MultiMeshInstance3D, static_cache: PeravizRuntimeAssetCache = null) -> void:
	if multimesh_instance == null:
		return
	if multimesh_instance.material_override != null:
		multimesh_instance.material_override = _duplicate_as_double_sided(multimesh_instance.material_override, static_cache)
	var mesh: Mesh = multimesh_instance.multimesh.mesh if multimesh_instance.multimesh != null else null
	_apply_double_sided_to_mesh_surfaces(multimesh_instance, mesh, static_cache)

func _apply_double_sided_to_mesh_surfaces(geometry_instance: GeometryInstance3D, mesh: Mesh, static_cache: PeravizRuntimeAssetCache = null) -> void:
	if geometry_instance == null or mesh == null:
		return
	var surface_count: int = mesh.get_surface_count()
	for surface_index in range(surface_count):
		var override_material: Material = geometry_instance.get_surface_override_material(surface_index)
		if override_material != null:
			geometry_instance.set_surface_override_material(surface_index, _duplicate_as_double_sided(override_material, static_cache))
			continue
		var surface_material: Material = mesh.surface_get_material(surface_index)
		if surface_material != null:
			geometry_instance.set_surface_override_material(surface_index, _duplicate_as_double_sided(surface_material, static_cache))
		else:
			geometry_instance.set_surface_override_material(surface_index, static_cache.static_double_sided(null) if static_cache != null else _create_default_double_sided_material())

func _duplicate_as_double_sided(material: Material, static_cache: PeravizRuntimeAssetCache = null) -> Material:
	if static_cache != null:
		var prepared: Material = static_cache.static_double_sided(material)
		if prepared != null: return prepared
	if material is not BaseMaterial3D:
		return material
	var base_material: BaseMaterial3D = material as BaseMaterial3D
	if base_material.cull_mode == BaseMaterial3D.CULL_DISABLED:
		return material
	var duplicated_material: BaseMaterial3D = base_material.duplicate(true)
	duplicated_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return duplicated_material

func _create_default_double_sided_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _extract_visual_scale_hint(data: Dictionary) -> float:
	if bool(data.get("has_basis", false)):
		var basis_x: Vector3 = data.get("basis_x", Vector3.RIGHT)
		var basis_y: Vector3 = data.get("basis_y", Vector3.UP)
		var basis_z: Vector3 = data.get("basis_z", Vector3.BACK)
		var average_basis_length: float = (basis_x.length() + basis_y.length() + basis_z.length()) / 3.0
		if not is_finite(average_basis_length): return 1.0
		return max(average_basis_length, 0.0001)
	var node_scale: Vector3 = data.get("scale", Vector3.ONE)
	var average_scale: float = (abs(node_scale.x) + abs(node_scale.y) + abs(node_scale.z)) / 3.0
	if not is_finite(average_scale):
		return 1.0
	return max(average_scale, 0.0001)

func _load_3d_asset(asset_path: String, loader: PeravizLoader, asset_cache: PeravizRuntimeAssetCache, asset_kind_hint: String = "", flip_orientation: bool = false) -> Variant:
	if asset_cache.is_failed(asset_path):
		return null
	var resolved_asset_kind: String = asset_kind_hint.to_lower()
	if resolved_asset_kind.is_empty() or resolved_asset_kind == "none":
		resolved_asset_kind = _infer_asset_kind_from_extension(asset_path)
	var extension: String = asset_path.get_extension().to_lower()
	if resolved_asset_kind == "mesh" or extension == "3ds":
		var mesh_cache_key: String = asset_path
		if flip_orientation:
			mesh_cache_key = "%s#flipped" % asset_path
		var cached_mesh: Mesh = asset_cache.get_mesh(mesh_cache_key)
		if cached_mesh != null:
			var instance_started: int = Time.get_ticks_usec() if _profile_setup else 0
			var cached_mesh_instance := MeshInstance3D.new()
			_record_setup("mesh_instance_creation_ms",instance_started)
			instance_started = Time.get_ticks_usec() if _profile_setup else 0
			cached_mesh_instance.mesh = cached_mesh
			_record_setup("mesh_instance_assignment_ms",instance_started)
			cached_mesh_instance.set_meta("peraviz_asset_path", asset_path)
			cached_mesh_instance.set_meta("peraviz_asset_kind", "mesh")
			cached_mesh_instance.set_meta("peraviz_flip_orientation_applied", flip_orientation)
			return cached_mesh_instance
		var mesh_data: Dictionary = _decode_3ds_mesh(asset_path,loader)
		if not bool(mesh_data.get("ok", false)):
			asset_cache.mark_failed(asset_path, str(mesh_data.get("error", "invalid_3ds")))
			return null
		var mesh: ArrayMesh = _build_3ds_mesh(mesh_data, flip_orientation, asset_cache)
		if mesh == null:
			asset_cache.mark_failed(asset_path, "mesh_construction_failed", "mesh_creation")
			return null
		asset_cache.store_mesh(mesh_cache_key, mesh)
		var instance_started: int = Time.get_ticks_usec() if _profile_setup else 0
		var mesh_instance := MeshInstance3D.new()
		_record_setup("mesh_instance_creation_ms",instance_started)
		instance_started = Time.get_ticks_usec() if _profile_setup else 0
		mesh_instance.mesh = mesh
		_record_setup("mesh_instance_assignment_ms",instance_started)
		mesh_instance.set_meta("peraviz_asset_path", asset_path)
		mesh_instance.set_meta("peraviz_asset_kind", "mesh")
		mesh_instance.set_meta("peraviz_flip_orientation_applied", flip_orientation)
		return mesh_instance
	if resolved_asset_kind == "scene" or extension == "glb" or extension == "gltf":
		var cached_scene_instance: Node3D = _instantiate_cached_scene(asset_path,asset_cache)
		if cached_scene_instance != null:
			return cached_scene_instance
		if not FileAccess.file_exists(asset_path):
			var cache_root: String = _runtime_cache_workspace_for_path(asset_path)
			if not _missing_cache_roots_reported.has(cache_root):
				_missing_cache_roots_reported[cache_root] = true
				push_error("path_missing_before_godot_load: fixture asset cache is missing: %s" % cache_root)
			asset_cache.mark_failed(asset_path, "file_missing", "decoding")
			return null
		var decode_started: int = Time.get_ticks_usec() if _profile_setup else 0
		setup_metrics["scene_decode_calls"] = int(setup_metrics.get("scene_decode_calls",0)) + 1
		var gltf := GLTFDocument.new()
		var state := GLTFState.new()
		var err: int = gltf.append_from_file(asset_path, state)
		if err != OK:
			asset_cache.mark_failed(asset_path, "scene_parse_failed:%d" % err)
			return null
		var generated: Node = gltf.generate_scene(state)
		if _profile_setup: setup_metrics.resource_decode_ms += (Time.get_ticks_usec()-decode_started)/1000.0
		if generated is Node3D and _has_renderable_mesh(generated):
			generated.set_meta("peraviz_static_scenery",generated.find_children("*","AnimationMixer",true,false).is_empty() and generated.find_children("*","Skeleton3D",true,false).is_empty())
			var packed_scene := PackedScene.new()
			setup_metrics["scene_pack_calls"] = int(setup_metrics.get("scene_pack_calls",0)) + 1
			var pack_started: int = Time.get_ticks_usec() if _profile_setup else 0
			var pack_error: Error = packed_scene.pack(generated)
			if _profile_setup: setup_metrics.scene_pack_ms += (Time.get_ticks_usec()-pack_started)/1000.0
			if pack_error == OK:
				asset_cache.store_scene(asset_path, packed_scene)
				generated.free()
				return _instantiate_cached_scene(asset_path,asset_cache)
			asset_cache.mark_failed(asset_path, "scene_pack_failed", "scene_instantiation")
			generated.free()
			return null
		if generated != null:
			generated.free()
		asset_cache.mark_failed(asset_path, "no_renderable_geometry", "scene_instantiation")
		return null
	var scene_instance: Node3D = _instantiate_cached_scene(asset_path,asset_cache)
	if scene_instance != null:
		return scene_instance
	var resource: Resource = load(asset_path)
	if resource is PackedScene:
		asset_cache.store_scene(asset_path, resource)
		return _instantiate_cached_scene(asset_path,asset_cache)
	asset_cache.mark_failed(asset_path)
	return null

func _instantiate_cached_scene(path: String, asset_cache: PeravizRuntimeAssetCache) -> Node3D:
	var started: int = Time.get_ticks_usec() if _profile_setup else 0
	var instance: Node3D = asset_cache.instantiate_scene(path)
	if instance != null:
		setup_metrics["scene_clone_calls"] = int(setup_metrics.get("scene_clone_calls",0)) + 1
	if _profile_setup: setup_metrics.scene_instantiation_ms += (Time.get_ticks_usec()-started)/1000.0
	return instance

func _has_renderable_mesh(node: Node) -> bool:
	if node is MeshInstance3D and node.mesh != null and node.mesh.get_surface_count() > 0:
		return true
	for child in node.get_children():
		if _has_renderable_mesh(child):
			return true
	return false

func _runtime_cache_workspace_for_path(asset_path: String) -> String:
	var normalized: String = asset_path.replace("\\", "/")
	var marker: String = "/cache/v1/"
	var marker_index: int = normalized.find(marker)
	if marker_index < 0:
		return asset_path.get_base_dir()
	var workspace_start: int = marker_index + marker.length()
	var workspace_end: int = normalized.find("/", workspace_start)
	if workspace_end < 0:
		return normalized
	return normalized.substr(0, workspace_end)

func _extract_node_class(data: Dictionary, item_type: String) -> String:
	var node_class: String = str(data.get("class", ""))
	if node_class.is_empty():
		node_class = item_type
	return node_class

func _extract_asset_kind(data: Dictionary, asset_path: String) -> String:
	var kind: String = str(data.get("asset_kind", "")).to_lower()
	if kind.is_empty() or kind == "none":
		kind = _infer_asset_kind_from_extension(asset_path)
	return kind

func _infer_asset_kind_from_extension(asset_path: String) -> String:
	var extension: String = asset_path.get_extension().to_lower()
	if extension == "3ds":
		return "mesh"
	if extension == "glb" or extension == "gltf" or extension == "obj" or extension == "dae" or extension == "fbx" or extension == "stl":
		return "scene"
	return "none"

func _decode_3ds_mesh(asset_path: String, loader: PeravizLoader) -> Dictionary:
	setup_metrics["mesh_decode_calls"] = int(setup_metrics.get("mesh_decode_calls",0)) + 1
	var started: int = Time.get_ticks_usec() if _profile_setup else 0
	var data: Dictionary = loader.load_3ds_mesh_data(asset_path)
	if _profile_setup: setup_metrics.resource_decode_ms += (Time.get_ticks_usec()-started)/1000.0
	return data

func _build_3ds_mesh(mesh_data: Dictionary, flip_orientation: bool = false, asset_cache: PeravizRuntimeAssetCache = null) -> ArrayMesh:
	setup_metrics["mesh_build_calls"] = int(setup_metrics.get("mesh_build_calls",0)) + 1
	var started: int = Time.get_ticks_usec() if _profile_setup else 0
	var mesh: ArrayMesh = _create_3ds_mesh(mesh_data,flip_orientation,asset_cache)
	if _profile_setup: setup_metrics.mesh_creation_ms += (Time.get_ticks_usec()-started)/1000.0
	return mesh

func _create_3ds_mesh(mesh_data: Dictionary, flip_orientation: bool = false, asset_cache: PeravizRuntimeAssetCache = null) -> ArrayMesh:
	var vertices: PackedVector3Array = mesh_data.get("vertices", PackedVector3Array())
	var normals: PackedVector3Array = mesh_data.get("normals", PackedVector3Array())
	var texcoords: PackedVector2Array = mesh_data.get("texcoords", PackedVector2Array())
	var indices: PackedInt32Array = mesh_data.get("indices", PackedInt32Array())
	var texture_path: String = str(mesh_data.get("texture_path", ""))
	var has_material_base_color: bool = bool(mesh_data.get("has_material_base_color", false))
	var material_base_color_vec: Vector3 = mesh_data.get("material_base_color", Vector3.ONE)
	var material_base_color: Color = Color(material_base_color_vec.x, material_base_color_vec.y, material_base_color_vec.z, 1.0)
	if vertices.is_empty() or indices.is_empty():
		return null
	if flip_orientation:
		if (indices.size() % 3) != 0:
			push_warning("[Peraviz] 3DS mesh index count is not divisible by 3; skipping orientation flip.")
		else:
			for i in range(0, indices.size(), 3):
				var tmp: int = indices[i + 1]
				indices[i + 1] = indices[i + 2]
				indices[i + 2] = tmp
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	if texcoords.size() == vertices.size():
		arrays[Mesh.ARRAY_TEX_UV] = texcoords
	arrays[Mesh.ARRAY_INDEX] = indices
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if array_mesh.get_surface_count() == 0:
		return null
	if not texture_path.is_empty() and texcoords.size() == vertices.size():
		var texture: Texture2D = _load_3ds_texture(texture_path,asset_cache)
		if texture != null:
			var material := StandardMaterial3D.new()
			material.albedo_color = Color.WHITE
			material.albedo_texture = texture
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			array_mesh.surface_set_material(0,material)
	elif has_material_base_color:
		var base_color_material := StandardMaterial3D.new()
		base_color_material.albedo_color = material_base_color
		base_color_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		array_mesh.surface_set_material(0, base_color_material)
	else:
		var textured_fallback_material := StandardMaterial3D.new()
		textured_fallback_material.albedo_color = Color(0.2, 0.2, 0.2, 1.0)
		textured_fallback_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		array_mesh.surface_set_material(0, textured_fallback_material)
	return array_mesh

# Image decoding/upload is once per exact resolved path and import generation.
# Missing images keep the previous material fallback and retry on the next import.
func _load_3ds_texture(path: String, asset_cache: PeravizRuntimeAssetCache) -> Texture2D:
	if asset_cache != null:
		if asset_cache.is_texture_failed(path): return null
		var cached: Texture2D = asset_cache.get_texture(path)
		if cached != null: return cached
	setup_metrics["texture_decode_calls"] = int(setup_metrics.get("texture_decode_calls",0)) + 1
	var started: int = Time.get_ticks_usec() if _profile_setup else 0
	var image := Image.new()
	var error: Error = image.load(path)
	if error != OK:
		if asset_cache != null: asset_cache.mark_texture_failed(path)
		push_warning("[Peraviz] Failed to load 3DS texture image: %s (error=%d)" % [path,error])
		return null
	if image.get_format() != Image.FORMAT_RGBA8: image.convert(Image.FORMAT_RGBA8)
	var texture: ImageTexture = ImageTexture.create_from_image(image)
	if _profile_setup: setup_metrics.texture_preparation_ms += (Time.get_ticks_usec()-started)/1000.0
	if asset_cache != null: asset_cache.store_texture(path,texture)
	return texture

func _create_dummy_mesh(is_fixture: bool, visual_scale_hint: float) -> Node3D:
	setup_metrics["dummy_instances_created"] = int(setup_metrics.get("dummy_instances_created",0)) + 1
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.set_meta("peraviz_dummy_placeholder", true)
	var world_target_size: float = 0.35
	var normalized_scale: float = max(visual_scale_hint, 0.0001)
	var local_size_multiplier: float = world_target_size / normalized_scale
	if is_fixture:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.15 * local_size_multiplier
		cone.height = 0.4 * local_size_multiplier
		mesh_instance.mesh = cone
	else:
		var box := BoxMesh.new()
		box.size = Vector3.ONE * (0.3 * local_size_multiplier)
		mesh_instance.mesh = box
	var material_started: int = Time.get_ticks_usec() if _profile_setup else 0
	# This is a known built-in descriptor, not an authored material. Construct its
	# final independent state directly instead of deep-duplicating every stored
	# property. The latter dominated the Forward+ placeholder preparation probe.
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.5, 0.1) if is_fixture else Color(0.2, 0.8, 1.0)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	# Preserve the legacy surface override too, including when a caller clears
	# the whole-instance override. Both resources remain independently editable.
	mesh_instance.set_surface_override_material(0,_create_default_double_sided_material())
	_record_setup("dummy_material_ms",material_started)
	return mesh_instance

func _create_gdtf_primitive_mesh(data: Dictionary) -> Node3D:
	var primitive_type: String = str(data.get("primitive_type", "")).to_lower()
	var primitive_shape: String = _classify_gdtf_primitive_shape(primitive_type)
	var primitive_scale := Vector3(float(data.get("primitive_size_x", 0.1)), float(data.get("primitive_size_z", 0.1)), float(data.get("primitive_size_y", 0.1)))
	for axis in range(3):
		if not is_finite(primitive_scale[axis]) or primitive_scale[axis] <= 0: primitive_scale[axis] = 0.1
	var mesh_instance := MeshInstance3D.new()
	if primitive_shape == "sphere":
		var sphere := SphereMesh.new()
		sphere.radius = 0.5
		sphere.height = 1.0
		mesh_instance.mesh = sphere
	elif primitive_shape == "cylinder":
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.5
		cylinder.bottom_radius = 0.5
		cylinder.height = 1.0
		mesh_instance.mesh = cylinder
	elif primitive_shape == "cone":
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.5
		cone.height = 1.0
		mesh_instance.mesh = cone
	else:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		mesh_instance.mesh = box
	# Primitive tessellation bounds can be slightly smaller than the nominal unit shape.
	# Fit the actual renderer mesh so declared dimensions remain authoritative.
	var unit_size: Vector3 = mesh_instance.mesh.get_aabb().size
	for axis in range(3):
		if unit_size[axis] > 0: primitive_scale[axis] /= unit_size[axis]
	mesh_instance.scale = primitive_scale
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.2, 0.22, 1.0)
	material.roughness = 0.3
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	return mesh_instance

func _classify_gdtf_primitive_shape(primitive_type: String) -> String:
	var normalized: String = primitive_type.strip_edges().to_lower()
	if normalized.is_empty() or normalized == "undefined":
		return "box"
	if normalized.contains("cone"):
		return "cone"
	if normalized.contains("cylinder"):
		return "cylinder"
	if normalized.contains("sphere"):
		return "sphere"
	if normalized in ["yoke", "scanner", "scanner1_1", "pigtail"]:
		return "cylinder"
	if normalized in ["head"]:
		return "sphere"
	if normalized in ["base", "base1_1", "conventional", "conventional1_1", "cube"]:
		return "box"
	return "box"

# Scene activation and renderer installation may change visibility after resource creation.
# Keep these observations distinct from decoding/mesh success and from actual pixel coverage.
func refresh_scene_visibility(node_index: Dictionary, budget: SceneLoadBudget = null) -> bool:
	var visible: int = 0
	var attached: int = 0
	var invalid_bounds: int = 0
	var visible_fixtures: Dictionary = {}
	for node: Node3D in node_index.values():
		if budget != null and not await budget.checkpoint(): return false
		if not node.has_meta("peraviz_model_visual"): continue
		var visual: Variant = node.get_meta("peraviz_model_visual")
		if not is_instance_valid(visual) or visual.get_meta("peraviz_model_fallback", false): continue
		var report: Dictionary = ModelGeometry.inspect(visual, _mesh_facts, _inspection_metrics)
		if report.meshes == 0 or not report.has_bounds: continue
		if not visual.is_inside_tree(): continue
		attached += 1
		var world_bounds: AABB = node.global_transform * report.bounds
		if not report.valid or not world_bounds.position.is_finite() or not world_bounds.size.is_finite() or world_bounds.size.length_squared() == 0:
			invalid_bounds += 1
		elif report.visible_meshes > 0:
			visible += 1
			var uuid: String = str(node.get_meta("peraviz_fixture_uuid", ""))
			if not uuid.is_empty(): visible_fixtures[uuid] = true
	asset_load_summary["attached"] = attached
	asset_load_summary["visible"] = visible
	asset_load_summary["fixtures_visible"] = visible_fixtures.size()
	asset_load_summary["invalid_world_bounds"] = invalid_bounds
	asset_load_summary["visibility_audited_after_activation"] = true
	print("[Peraviz] Activated geometry attached=", attached, " visible=", visible, " fixtures_visible=", visible_fixtures.size(), " invalid_world_bounds=", invalid_bounds)
	return true

# Bounded aggregate setup spans; nested timings are not additive phase totals.
func _record_setup(key: String, started: int) -> void:
	if _profile_setup:
		setup_metrics[key] = float(setup_metrics.get(key,0.0)) + (Time.get_ticks_usec()-started)/1000.0
