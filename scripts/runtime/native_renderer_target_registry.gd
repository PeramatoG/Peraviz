extends RefCounted

class_name NativeRendererTargetRegistry

var _node_index: Dictionary = {}
var _scene_registry: Object = null
var _callbacks: Dictionary = {}
var _pan_targets: Dictionary = {}
var _tilt_targets: Dictionary = {}
var _dimmer_targets: Dictionary = {}
var _optics_targets: Dictionary = {}
var _target_resolution_failures: Dictionary = {}
var _geometry_targets_by_key: Dictionary = {}
var _dimmer_emitter_owner_by_key: Dictionary = {}
var _summary: Dictionary = {}
var _lens_material_cache: Dictionary = {}

func configure(dependencies: Dictionary) -> void:
	_node_index = dependencies.get("node_index", {})
	_scene_registry = dependencies.get("scene_registry", null)
	_callbacks = dependencies.get("callbacks", {})
	clear()

func clear() -> void:
	_pan_targets.clear()
	_tilt_targets.clear()
	_dimmer_targets.clear()
	_optics_targets.clear()
	_target_resolution_failures.clear()
	_geometry_targets_by_key.clear()
	_dimmer_emitter_owner_by_key.clear()
	_lens_material_cache.clear()
	_summary = _new_summary()

func install_manifest(renderer_manifest: Array) -> void:
	clear()
	_build_geometry_target_map(renderer_manifest)
	for item in renderer_manifest:
		if item is not Dictionary:
			continue
		var row: Dictionary = item
		var targets: Array = row.get("targets", [])
		if not targets.is_empty():
			for target_item in targets:
				if target_item is Dictionary:
					_register_renderer_target(target_item)
			continue
		_register_legacy_manifest_row(row)
	_log_summary_once()

func apply_transform_targets(pan_component_id: int, tilt_component_id: int, pan_degrees: float, tilt_degrees: float) -> Dictionary:
	var pan_axis: Node3D = _pan_targets.get(pan_component_id, null) as Node3D
	var tilt_axis: Node3D = _tilt_targets.get(tilt_component_id, null) as Node3D
	var result: Dictionary = {"pan_requested": pan_component_id > 0, "pan_applied": false, "tilt_requested": tilt_component_id > 0, "tilt_applied": false, "failed": 0}
	if pan_component_id > 0 and pan_axis != null:
		pan_axis.rotation_degrees.y = pan_degrees
		result["pan_applied"] = true
	elif pan_component_id > 0:
		if not _target_resolution_failures.has(pan_component_id):
			_target_resolution_failures[pan_component_id] = {"target_id": pan_component_id, "semantic": "pan", "reason": "target never registered"}
		result["failed"] = int(result["failed"]) + 1
	if tilt_component_id > 0 and tilt_axis != null:
		tilt_axis.rotation_degrees.x = tilt_degrees
		result["tilt_applied"] = true
	elif tilt_component_id > 0:
		if not _target_resolution_failures.has(tilt_component_id):
			_target_resolution_failures[tilt_component_id] = {"target_id": tilt_component_id, "semantic": "tilt", "reason": "target never registered"}
		result["failed"] = int(result["failed"]) + 1
	return result

func has_dimmer_target(dimmer_target_id: int) -> bool:
	return dimmer_target_id > 0 and _dimmer_targets.has(dimmer_target_id)

func has_optics_target(optics_target_id: int) -> bool:
	return optics_target_id > 0 and _optics_targets.has(optics_target_id)

func get_optics_target_record(optics_target_id: int) -> Dictionary:
	if optics_target_id <= 0:
		return {}
	return _optics_targets.get(optics_target_id, {})

func get_dimmer_target_record(dimmer_target_id: int) -> Dictionary:
	if dimmer_target_id <= 0:
		return {}
	return _dimmer_targets.get(dimmer_target_id, {})

func get_target_failure(target_id: int) -> Variant:
	return _target_resolution_failures.get(target_id, null)

func get_summary() -> Dictionary:
	return {
		"pan_targets_resolved": _pan_targets.size(),
		"tilt_targets_resolved": _tilt_targets.size(),
		"dimmer_targets_resolved": _dimmer_targets.size(),
		"optics_targets_resolved": _optics_targets.size(),
		"registry_summary": _summary.duplicate(true),
		"target_resolution_failures": _target_resolution_failures.duplicate(true),
	}

func _register_legacy_manifest_row(row: Dictionary) -> void:
	var fixture_uuid: String = str(row.get("fixture_uuid", ""))
	if fixture_uuid.is_empty():
		return
	_register_axis_target(_pan_targets, row, int(row.get("pan_component_id", 0)), str(row.get("pan_geometry_key", "")), "pan")
	_register_axis_target(_tilt_targets, row, int(row.get("tilt_component_id", 0)), str(row.get("tilt_geometry_key", "")), "tilt")
	_register_dimmer_target(row, int(row.get("dimmer_target_id", 0)), fixture_uuid, str(row.get("dimmer_geometry_key", "")))

func _register_renderer_target(target: Dictionary) -> void:
	var semantic: String = str(target.get("semantic", "")).to_lower()
	var fixture_uuid: String = str(target.get("fixture_uuid", ""))
	var geometry_key: String = str(target.get("geometry_key", ""))
	if semantic == "pan":
		_register_axis_target(_pan_targets, target, int(target.get("target_id", target.get("component_id", 0))), geometry_key, "pan")
	elif semantic == "tilt":
		_register_axis_target(_tilt_targets, target, int(target.get("target_id", target.get("component_id", 0))), geometry_key, "tilt")
	elif semantic == "dimmer":
		_register_dimmer_target(target, int(target.get("render_target_id", target.get("target_id", 0))), fixture_uuid, geometry_key)
	elif semantic == "zoom" or semantic == "beam_profile":
		_register_optics_target(target, int(target.get("render_target_id", target.get("target_id", 0))), fixture_uuid, geometry_key)

func _new_summary() -> Dictionary:
	return {
		"imported_geometry_keys": 0,
		"empty_manifest_geometry_keys": 0,
		"duplicate_imported_geometry_keys": 0,
		"duplicate_manifest_target_ids": 0,
		"registration_timing_failures": 0,
		"pan_requested": 0,
		"pan_resolved": 0,
		"pan_failed": 0,
		"tilt_requested": 0,
		"tilt_resolved": 0,
		"tilt_failed": 0,
		"dimmer_requested": 0,
		"optics_requested": 0,
		"optics_resolved": 0,
		"optics_failed": 0,
		"dimmer_resolved": 0,
		"dimmer_failed": 0,
		"dimmer_owner_geometries_resolved": 0,
		"dimmer_targets_with_emitter_nodes": 0,
		"dimmer_targets_with_lights": 0,
		"dimmer_targets_with_beam_instances": 0,
		"dimmer_targets_with_lens_materials": 0,
		"dimmer_targets_with_optional_spotlights": 0,
		"dimmer_targets_with_no_mutable_resource": 0,
		"dimmer_target_overlaps": 0,
		"first_failures": [],
	}

func _build_geometry_target_map(renderer_manifest: Array) -> void:
	var fixture_uuids: Dictionary = {}
	for item in renderer_manifest:
		if item is Dictionary:
			var fixture_uuid: String = str(item.get("fixture_uuid", ""))
			if not fixture_uuid.is_empty():
				fixture_uuids[fixture_uuid] = true
	for node_id in _node_index.keys():
		var node3d: Node3D = _node_index.get(node_id, null) as Node3D
		if node3d == null:
			continue
		var key: String = str(node3d.get_meta("peraviz_gdtf_geometry_key", ""))
		if key.is_empty():
			continue
		var fixture_uuid: String = str(node3d.get_meta("peraviz_fixture_uuid", ""))
		if fixture_uuid.is_empty():
			fixture_uuid = _fixture_uuid_from_geometry_key(key)
		if not fixture_uuids.has(fixture_uuid):
			continue
		if _geometry_targets_by_key.has(key):
			_summary["duplicate_imported_geometry_keys"] = int(_summary.get("duplicate_imported_geometry_keys", 0)) + 1
		_geometry_targets_by_key[key] = node3d
	_summary["imported_geometry_keys"] = _geometry_targets_by_key.size()

func _register_axis_target(targets: Dictionary, manifest_row: Dictionary, target_id: int, geometry_key: String, role: String) -> void:
	if target_id <= 0:
		return
	_increment_counter("%s_requested" % role)
	if geometry_key.is_empty():
		_increment_counter("empty_manifest_geometry_keys")
		_register_target_failure(manifest_row, target_id, role, "Manifest target has an empty canonical geometry key.")
		return
	if targets.has(target_id):
		_increment_counter("duplicate_manifest_target_ids")
		_register_target_failure(manifest_row, target_id, role, "Duplicate native target handle in renderer manifest.")
		return
	var target: Node3D = _geometry_targets_by_key.get(geometry_key, null) as Node3D
	if target == null:
		_register_target_failure(manifest_row, target_id, role, "No imported geometry node has canonical geometry key %s" % geometry_key)
		return
	targets[target_id] = target
	_increment_counter("%s_resolved" % role)

func _register_dimmer_target(manifest_row: Dictionary, target_id: int, fixture_uuid: String, geometry_key: String) -> void:
	if target_id <= 0:
		return
	_increment_counter("dimmer_requested")
	if geometry_key.is_empty():
		_increment_counter("empty_manifest_geometry_keys")
		_register_target_failure(manifest_row, target_id, "dimmer", "Manifest target has an empty canonical geometry key.")
		return
	if _dimmer_targets.has(target_id):
		_increment_counter("duplicate_manifest_target_ids")
		_register_target_failure(manifest_row, target_id, "dimmer", "Duplicate native Dimmer target handle in renderer manifest.")
		return
	var target: Node3D = _geometry_targets_by_key.get(geometry_key, null) as Node3D
	if target == null:
		_register_target_failure(manifest_row, target_id, "dimmer", "No imported geometry node has canonical geometry key %s" % geometry_key)
		return
	var target_nodes: Array = [target]
	var emitter_nodes: Array = _collect_descendant_emitters(geometry_key)
	emitter_nodes = _filter_dimmer_target_emitters(manifest_row, target_id, emitter_nodes)
	var cache_key: String = "%s:%d" % [fixture_uuid, target_id]
	var emitter_anchors: Array = _call_array("collect_emitter_lights", [cache_key, emitter_nodes])
	var lens_material_targets: Array = _prepare_lens_materials(cache_key, target_nodes + emitter_nodes)
	var beam_instances: Array = _prepare_beam_instances(emitter_anchors)
	_dimmer_targets[target_id] = {
		"fixture_uuid": fixture_uuid,
		"property_id": int(manifest_row.get("property_id", 0)),
		"component_id": int(manifest_row.get("component_id", 0)),
		"render_target_id": target_id,
		"target_id": target_id,
		"owner_geometry_key": geometry_key,
		"owner_geometry_node": target,
		"geometry_nodes": target_nodes,
		"emitter_nodes": emitter_nodes,
		"emitter_anchors": emitter_anchors,
		"optional_spotlights": emitter_anchors,
		"beam_instances": beam_instances,
		"lens_material_targets": lens_material_targets,
		"emitter_photometrics": _call_array("get_emitter_photometrics", [fixture_uuid]),
	}
	_increment_counter("dimmer_owner_geometries_resolved")
	if not emitter_nodes.is_empty():
		_increment_counter("dimmer_targets_with_emitter_nodes")
	if not emitter_anchors.is_empty():
		_increment_counter("dimmer_targets_with_lights")
		_increment_counter("dimmer_targets_with_optional_spotlights")
	if not beam_instances.is_empty():
		_increment_counter("dimmer_targets_with_beam_instances")
	if not lens_material_targets.is_empty():
		_increment_counter("dimmer_targets_with_lens_materials")
	if emitter_anchors.is_empty() and beam_instances.is_empty() and lens_material_targets.is_empty():
		_increment_counter("dimmer_targets_with_no_mutable_resource")
	_increment_counter("dimmer_resolved")

func _register_optics_target(manifest_row: Dictionary, target_id: int, fixture_uuid: String, geometry_key: String) -> void:
	if target_id <= 0:
		return
	_increment_counter("optics_requested")
	if geometry_key.is_empty():
		_register_target_failure(manifest_row, target_id, "optics", "Manifest target has an empty canonical geometry key.")
		return
	if _optics_targets.has(target_id):
		var existing: Dictionary = _optics_targets.get(target_id, {})
		var profile: Dictionary = manifest_row.get("beam_optical_profile", {})
		if not profile.is_empty():
			existing["beam_optical_profile"] = profile
			_apply_initial_optics_profile(existing.get("emitter_anchors", []), profile)
			_optics_targets[target_id] = existing
		return
	var target: Node3D = _geometry_targets_by_key.get(geometry_key, null) as Node3D
	if target == null:
		_register_target_failure(manifest_row, target_id, "optics", "No imported geometry node has canonical geometry key %s" % geometry_key)
		return
	var emitter_nodes: Array = _collect_descendant_emitters(geometry_key)
	var cache_key: String = "%s:%d:optics" % [fixture_uuid, target_id]
	var emitter_anchors: Array = _call_array("collect_emitter_lights", [cache_key, emitter_nodes])
	var beam_instances: Array = _prepare_beam_instances(emitter_anchors)
	var optical_profile: Dictionary = manifest_row.get("beam_optical_profile", {})
	_apply_initial_optics_profile(emitter_anchors, optical_profile)
	_optics_targets[target_id] = {
		"fixture_uuid": fixture_uuid,
		"property_id": int(manifest_row.get("property_id", 0)),
		"component_id": int(manifest_row.get("component_id", 0)),
		"render_target_id": target_id,
		"target_id": target_id,
		"owner_geometry_key": geometry_key,
		"owner_geometry_node": target,
		"emitter_nodes": emitter_nodes,
		"emitter_anchors": emitter_anchors,
		"beam_instances": beam_instances,
		"beam_optical_profile": optical_profile,
	}
	_increment_counter("optics_resolved")

func _apply_initial_optics_profile(emitter_anchors: Array, optical_profile: Dictionary) -> void:
	if optical_profile.is_empty():
		return
	for anchor in emitter_anchors:
		var light: SpotLight3D = anchor as SpotLight3D
		if light == null or not is_instance_valid(light):
			continue
		var render_radius: float = max(float(optical_profile.get("render_near_radius_m", optical_profile.get("official_beam_radius_m", 0.03))), 0.001)
		var beam_range: float = max(light.spot_range, 0.1)
		var params: Dictionary = {
			"beam_type": str(optical_profile.get("beam_type", "Wash")),
			"beam_angle": float(optical_profile.get("beam_angle", 25.0)),
			"field_angle": float(optical_profile.get("field_angle", 25.0)),
			"lens_radius": render_radius,
			"render_near_radius_m": render_radius,
			"rectangle_ratio": float(optical_profile.get("rectangle_ratio", 1.7777)),
			"beam_range": beam_range,
			"scaled_intensity": 0.0,
			"beam_intensity": 0.0,
			"normalized_dimmer": 0.0,
		}
		light.set_meta("peraviz_beam_last_params", params)
		var callback: Callable = _callbacks.get("apply_beam_optics", Callable())
		if callback.is_valid():
			callback.call(light, params)

func _prepare_beam_instances(emitter_anchors: Array) -> Array:
	var beam_instances: Array = []
	for anchor in emitter_anchors:
		var spot: SpotLight3D = anchor as SpotLight3D
		if spot == null or not is_instance_valid(spot):
			continue
		spot.visible = false
		spot.light_energy = 0.0
		spot.set_meta("peraviz_beam_base_intensity", 0.0)
		_call_void("ensure_beam_runtime", [spot])
		var beam: MeshInstance3D = _call_variant("get_beam_resource", [spot]) as MeshInstance3D
		if beam != null and is_instance_valid(beam):
			beam.visible = false
			beam_instances.append(beam)
	return beam_instances

func _filter_dimmer_target_emitters(manifest_row: Dictionary, target_id: int, emitter_nodes: Array) -> Array:
	var filtered: Array = []
	for emitter_node in emitter_nodes:
		var node3d: Node3D = emitter_node as Node3D
		if node3d == null:
			continue
		var emitter_key: String = str(node3d.get_meta("peraviz_gdtf_geometry_key", ""))
		if emitter_key.is_empty():
			continue
		if _dimmer_emitter_owner_by_key.has(emitter_key):
			_increment_counter("dimmer_target_overlaps")
			_register_target_failure(manifest_row, target_id, "dimmer", "Emitter %s is already owned by Dimmer target %s." % [emitter_key, str(_dimmer_emitter_owner_by_key.get(emitter_key))])
			continue
		_dimmer_emitter_owner_by_key[emitter_key] = target_id
		filtered.append(node3d)
	return filtered

func _prepare_lens_materials(cache_key: String, geometry_nodes: Array) -> Array:
	if _lens_material_cache.has(cache_key):
		return _lens_material_cache.get(cache_key, [])
	var targets: Array = []
	for geometry_node in geometry_nodes:
		_prepare_lens_material_targets_recursive(geometry_node, targets)
	_lens_material_cache[cache_key] = targets
	return targets

func _prepare_lens_material_targets_recursive(node: Node3D, output_targets: Array) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		_prepare_mesh_lens_material_targets(node as MeshInstance3D, output_targets)
	for child in node.get_children():
		if child is Node3D:
			_prepare_lens_material_targets_recursive(child, output_targets)

func _prepare_mesh_lens_material_targets(mesh_instance: MeshInstance3D, output_targets: Array) -> void:
	if not _is_emitter_lens_mesh(mesh_instance):
		return
	var surface_count: int = mesh_instance.get_surface_override_material_count()
	if surface_count <= 0 and mesh_instance.mesh != null:
		surface_count = mesh_instance.mesh.get_surface_count()
	if surface_count <= 0:
		return
	for surface_index in range(surface_count):
		var material: Material = mesh_instance.get_surface_override_material(surface_index)
		if material == null and mesh_instance.mesh != null and surface_index < mesh_instance.mesh.get_surface_count():
			material = mesh_instance.mesh.surface_get_material(surface_index)
		var prepared: BaseMaterial3D = _prepare_lens_emissive_material(material)
		if prepared == null:
			continue
		mesh_instance.set_surface_override_material(surface_index, prepared)
		output_targets.append({"mesh": mesh_instance, "surface": surface_index, "material": prepared})

func _prepare_lens_emissive_material(material: Material) -> BaseMaterial3D:
	var prepared: BaseMaterial3D = null
	if material is BaseMaterial3D:
		prepared = (material as BaseMaterial3D).duplicate(true) as BaseMaterial3D
	else:
		prepared = StandardMaterial3D.new()
	if prepared == null:
		return null
	prepared.emission_enabled = true
	prepared.emission = Color.WHITE
	prepared.emission_energy_multiplier = 0.0
	return prepared

func _collect_descendant_emitters(geometry_key: String) -> Array:
	var nodes: Array = []
	var prefix: String = geometry_key + "/"
	for key in _geometry_targets_by_key.keys():
		var candidate_key: String = str(key)
		if candidate_key != geometry_key and not candidate_key.begins_with(prefix):
			continue
		var node: Node3D = _geometry_targets_by_key.get(key, null) as Node3D
		if node != null and bool(node.get_meta("peraviz_is_emitter", false)):
			nodes.append(node)
	return nodes

func _fixture_uuid_from_geometry_key(geometry_key: String) -> String:
	var slash_index: int = geometry_key.find("/")
	return geometry_key if slash_index < 0 else geometry_key.substr(0, slash_index)

func _increment_counter(key: String) -> void:
	_summary[key] = int(_summary.get(key, 0)) + 1

func _register_target_failure(manifest_row: Dictionary, target_id: int, semantic: String, reason: String) -> void:
	_increment_counter("%s_failed" % semantic)
	var failure: Dictionary = _target_failure(manifest_row, target_id, semantic, reason)
	_target_resolution_failures[target_id] = failure
	var failures: Array = _summary.get("first_failures", [])
	if failures.size() < 5:
		failures.append(failure)
	_summary["first_failures"] = failures

func _log_summary_once() -> void:
	print("[native-target-registry] imported_geometry_keys=%d pan=%d/%d/%d tilt=%d/%d/%d dimmer=%d/%d/%d dimmer_resources=owners:%d emitters:%d lights:%d beams:%d materials:%d empty:%d empty_manifest_keys=%d duplicate_imported_keys=%d duplicate_manifest_target_ids=%d registration_timing_failures=%d first_failures=%s" % [
		int(_summary.get("imported_geometry_keys", 0)),
		int(_summary.get("pan_requested", 0)),
		int(_summary.get("pan_resolved", 0)),
		int(_summary.get("pan_failed", 0)),
		int(_summary.get("tilt_requested", 0)),
		int(_summary.get("tilt_resolved", 0)),
		int(_summary.get("tilt_failed", 0)),
		int(_summary.get("dimmer_requested", 0)),
		int(_summary.get("dimmer_resolved", 0)),
		int(_summary.get("dimmer_failed", 0)),
		int(_summary.get("dimmer_owner_geometries_resolved", 0)),
		int(_summary.get("dimmer_targets_with_emitter_nodes", 0)),
		int(_summary.get("dimmer_targets_with_lights", 0)),
		int(_summary.get("dimmer_targets_with_beam_instances", 0)),
		int(_summary.get("dimmer_targets_with_lens_materials", 0)),
		int(_summary.get("dimmer_targets_with_no_mutable_resource", 0)),
		int(_summary.get("empty_manifest_geometry_keys", 0)),
		int(_summary.get("duplicate_imported_geometry_keys", 0)),
		int(_summary.get("duplicate_manifest_target_ids", 0)),
		int(_summary.get("registration_timing_failures", 0)),
		str(_summary.get("first_failures", [])),
	])

func _target_failure(manifest_row: Dictionary, target_id: int, semantic: String, reason: String) -> Dictionary:
	var fixture_uuid: String = str(manifest_row.get("fixture_uuid", ""))
	return {
		"fixture_uuid": fixture_uuid,
		"fixture_id": int(manifest_row.get("fixture_id", 0)),
		"semantic": semantic,
		"target_id": target_id,
		"geometry_key": str(manifest_row.get("geometry_key", manifest_row.get("%s_geometry_key" % semantic, ""))),
		"matching_imported_keys": _matching_imported_geometry_keys(fixture_uuid),
		"fixture_root_path": _fixture_root_path(fixture_uuid),
		"reason": reason,
	}

func _matching_imported_geometry_keys(fixture_uuid: String) -> Array:
	var keys: Array = []
	var prefix: String = fixture_uuid + "/"
	for key in _geometry_targets_by_key.keys():
		var candidate: String = str(key)
		if candidate.begins_with(prefix):
			keys.append(candidate)
			if keys.size() >= 8:
				break
	return keys

func _fixture_root_path(fixture_uuid: String) -> String:
	if _scene_registry == null or fixture_uuid.is_empty() or not _scene_registry.has_method("get_fixture"):
		return ""
	var fixture_node: Node = _scene_registry.get_fixture(fixture_uuid)
	return str(fixture_node.get_path()) if fixture_node != null else ""

func _is_emitter_lens_mesh(mesh_instance: MeshInstance3D) -> bool:
	var callback: Callable = _callbacks.get("is_emitter_lens_mesh", Callable())
	if callback.is_valid():
		return bool(callback.call(mesh_instance))
	var name_hint: String = mesh_instance.name.to_lower()
	return name_hint.contains("lens") or name_hint.contains("glass") or name_hint.contains("emitter") or name_hint.contains("beam")

func _call_array(callback_name: String, args: Array) -> Array:
	var value: Variant = _call_variant(callback_name, args)
	return value if value is Array else []

func _call_void(callback_name: String, args: Array) -> void:
	_call_variant(callback_name, args)

func _call_variant(callback_name: String, args: Array) -> Variant:
	if not _callbacks.has(callback_name):
		return null
	var callback: Callable = _callbacks[callback_name]
	if not callback.is_valid():
		return null
	return callback.callv(args)
