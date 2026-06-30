extends RefCounted
class_name FixtureLightApplyService

var _phase_metrics: Dictionary = {
	"dmx_decode": {"calls": 0, "total_usec": 0},
	"fixture_apply": {"calls": 0, "total_usec": 0},
	"beam_update": {"calls": 0, "total_usec": 0},
	"gobo_update": {"calls": 0, "total_usec": 0},
}

func apply_dmx_controls_to_fixture(loader: Node, fixture_uuid: String, controls: Dictionary) -> void:
	var phase_start: int = Time.get_ticks_usec()
	controls["fixture_uuid"] = fixture_uuid
	if bool(controls.get("prewarm_only", false)):
		prewarm_lighting_for_fixture(loader, fixture_uuid)
		_track_phase("fixture_apply", phase_start)
		return
	if not controls.has("frame_delta_sec"):
		controls["frame_delta_sec"] = loader.get_process_delta_time()
	else:
		controls["frame_delta_sec"] = max(float(controls.get("frame_delta_sec", 0.0)), 0.0)
	var pan_tilt_controls: Dictionary = resolve_pan_tilt_controls(controls)
	if bool(pan_tilt_controls.get("has_pan", false)) or bool(pan_tilt_controls.get("has_tilt", false)):
		var has_pan: bool = bool(pan_tilt_controls.get("has_pan", false))
		var has_tilt: bool = bool(pan_tilt_controls.get("has_tilt", false))
		var pan_min: float = float(loader.pan_min_input.value)
		var pan_max: float = float(loader.pan_max_input.value)
		var tilt_min: float = float(loader.tilt_min_input.value)
		var tilt_max: float = float(loader.tilt_max_input.value)
		var pan_degrees: float = lerp(pan_min, pan_max, clamp(float(pan_tilt_controls.get("pan_norm", 0.0)), 0.0, 1.0))
		var tilt_degrees: float = lerp(tilt_min, tilt_max, clamp(float(pan_tilt_controls.get("tilt_norm", 0.0)), 0.0, 1.0))
		loader._apply_pan_tilt_components_to_fixture(fixture_uuid, has_pan, pan_degrees, has_tilt, tilt_degrees)

	if has_lighting_controls(controls):
		var dimmer_percent: float = 100.0
		var dimmer_controls: Dictionary = resolve_dimmer_controls(controls)
		if bool(dimmer_controls.get("has_dimmer", false)):
			dimmer_percent = clamp(float(dimmer_controls.get("dimmer_norm", 0.0)), 0.0, 1.0) * 100.0
		apply_dimmer_feedback_to_fixture(loader, fixture_uuid, dimmer_percent, controls)
	_track_phase("fixture_apply", phase_start)

func apply_visual_frame_to_fixture(loader: Node, fixture_uuid: String, visual_frame: PackedFloat32Array, base: int, frame_delta_sec: float) -> void:
	var phase_start: int = Time.get_ticks_usec()
	var channel_mask: int = int(visual_frame[base + 1])
	var dimmer_norm: float = clamp(visual_frame[base + 2], 0.0, 1.0)
	var pan_norm: float = clamp(visual_frame[base + 3], 0.0, 1.0)
	var tilt_norm: float = clamp(visual_frame[base + 4], 0.0, 1.0)
	var beam_energy: float = max(visual_frame[base + 15], 0.0)
	var spot_energy: float = max(visual_frame[base + 16], 0.0)
	var beam_half_angle: float = clamp(visual_frame[base + 17], 0.1, 90.0)
	var beam_color := Color(clamp(visual_frame[base + 19], 0.0, 1.0), clamp(visual_frame[base + 20], 0.0, 1.0), clamp(visual_frame[base + 21], 0.0, 1.0), 1.0)
	var material_energy: float = max(visual_frame[base + 23], 0.0)
	if (channel_mask & ((1 << 1) | (1 << 2))) != 0:
		_apply_visual_frame_pan_tilt(loader, fixture_uuid, (channel_mask & (1 << 1)) != 0, pan_norm, (channel_mask & (1 << 2)) != 0, tilt_norm)
	if (channel_mask & ((1 << 0) | (1 << 3) | (1 << 4) | (1 << 5) | (1 << 6))) != 0:
		_apply_visual_frame_lighting(loader, fixture_uuid, dimmer_norm, beam_energy, spot_energy, beam_half_angle, beam_color, material_energy, frame_delta_sec)
	_track_phase("fixture_apply", phase_start)

func _apply_visual_frame_pan_tilt(loader: Node, fixture_uuid: String, has_pan: bool, pan_norm: float, has_tilt: bool, tilt_norm: float) -> void:
	var pan_degrees: float = lerp(float(loader.pan_min_input.value), float(loader.pan_max_input.value), pan_norm)
	var tilt_degrees: float = lerp(float(loader.tilt_min_input.value), float(loader.tilt_max_input.value), tilt_norm)
	loader._apply_pan_tilt_components_to_fixture(fixture_uuid, has_pan, pan_degrees, has_tilt, tilt_degrees)

func _apply_visual_frame_lighting(loader: Node, fixture_uuid: String, dimmer_norm: float, beam_energy: float, spot_energy: float, beam_half_angle: float, beam_color: Color, material_energy: float, _frame_delta_sec: float) -> void:
	var geometry_nodes: Array = loader._get_fixture_geometry_nodes(fixture_uuid)
	var emitter_nodes: Array = loader._get_fixture_emitter_nodes(fixture_uuid)
	if geometry_nodes.is_empty() and emitter_nodes.is_empty():
		return
	_apply_visual_frame_materials(loader, fixture_uuid, geometry_nodes, beam_color, material_energy)
	var emitter_lights: Array = loader._collect_fixture_emitter_lights(fixture_uuid, emitter_nodes)
	for light in emitter_lights:
		if light == null or not is_instance_valid(light):
			continue
		_apply_visual_frame_light(loader, light, dimmer_norm, beam_energy, spot_energy, beam_half_angle, beam_color)

func _apply_visual_frame_materials(loader: Node, fixture_uuid: String, geometry_nodes: Array, beam_color: Color, material_energy: float) -> void:
	var emissive_materials: Array = _prewarm_emissive_materials(loader, fixture_uuid, geometry_nodes)
	for material in emissive_materials:
		if material is BaseMaterial3D:
			var material_rid: RID = _get_cached_material_rid(material)
			if material_rid.is_valid():
				RenderingServer.material_set_param(material_rid, "emission", beam_color)
				RenderingServer.material_set_param(material_rid, "emission_energy_multiplier", material_energy)

func _apply_visual_frame_light(loader: Node, light: SpotLight3D, dimmer_norm: float, beam_energy: float, spot_energy: float, beam_half_angle: float, beam_color: Color) -> void:
	light.visible = dimmer_norm > 0.0001
	light.light_energy = spot_energy if spot_energy > 0.0 else beam_energy
	light.spot_angle = beam_half_angle
	light.light_color = beam_color
	light.set_meta("peraviz_base_light_energy", beam_energy)
	light.set_meta("peraviz_beam_base_intensity", dimmer_norm)
	if loader.has_method("_update_beam_intensity_for_light"):
		loader._update_beam_intensity_for_light(light, dimmer_norm, beam_color)

func resolve_capability_bucket(controls: Dictionary, capability_type: String) -> Array:
	var capabilities: Dictionary = controls.get("capabilities", {})
	if capabilities is Dictionary:
		var bucket: Array = capabilities.get(capability_type, [])
		if bucket is Array:
			return bucket
	return []

func resolve_first_capability_block(controls: Dictionary, capability_type: String) -> Dictionary:
	var bucket: Array = resolve_capability_bucket(controls, capability_type)
	for item in bucket:
		if item is Dictionary:
			return item
	return {}

func resolve_pan_tilt_controls(controls: Dictionary) -> Dictionary:
	var block: Dictionary = resolve_first_capability_block(controls, "pan_tilt")
	if not block.is_empty():
		return block
	return {
		"has_pan": bool(controls.get("has_pan", false)),
		"pan_norm": float(controls.get("pan_norm", 0.0)),
		"has_tilt": bool(controls.get("has_tilt", false)),
		"tilt_norm": float(controls.get("tilt_norm", 0.0)),
	}

func resolve_dimmer_controls(controls: Dictionary) -> Dictionary:
	var block: Dictionary = resolve_first_capability_block(controls, "dimmer")
	if not block.is_empty():
		return block
	return {
		"has_dimmer": bool(controls.get("has_dimmer", false)),
		"dimmer_norm": float(controls.get("dimmer_norm", 0.0)),
		"has_zoom": bool(controls.get("has_zoom", false)),
		"zoom_norm": float(controls.get("zoom_norm", 0.0)),
		"has_zoom_physical_limits": bool(controls.get("has_zoom_physical_limits", false)),
		"zoom_physical_min_degrees": float(controls.get("zoom_physical_min_degrees", -1.0)),
		"zoom_physical_max_degrees": float(controls.get("zoom_physical_max_degrees", -1.0)),
	}

func resolve_color_wheel_controls(controls: Dictionary) -> Dictionary:
	var block: Dictionary = resolve_first_capability_block(controls, "color_wheel")
	if not block.is_empty():
		return block
	return {
		"has_cyan": bool(controls.get("has_cyan", false)),
		"cyan_norm": float(controls.get("cyan_norm", 0.0)),
		"has_magenta": bool(controls.get("has_magenta", false)),
		"magenta_norm": float(controls.get("magenta_norm", 0.0)),
		"has_yellow": bool(controls.get("has_yellow", false)),
		"yellow_norm": float(controls.get("yellow_norm", 0.0)),
	}

func resolve_gobo_controls(controls: Dictionary) -> Dictionary:
	var capabilities: Dictionary = controls.get("capabilities", {})
	if capabilities is Dictionary:
		var gobo_blocks: Array = capabilities.get("gobo", [])
		if not gobo_blocks.is_empty():
			var aggregated: Dictionary = {}
			var aggregated_bindings: Array = []
			var aggregated_slots: Array = []
			var has_any_gobo: bool = false
			for item in gobo_blocks:
				if item is not Dictionary:
					continue
				var block: Dictionary = item as Dictionary
				if aggregated.is_empty():
					aggregated = block.duplicate(true)
				if bool(block.get("has_gobo", false)):
					has_any_gobo = true
				for runtime_binding in block.get("gobo_runtime_bindings", []):
					aggregated_bindings.append(runtime_binding)
				for slot_item in block.get("gobo_slots", []):
					aggregated_slots.append(slot_item)
			if not aggregated.is_empty():
				aggregated["has_gobo"] = has_any_gobo or not aggregated_bindings.is_empty()
				aggregated["gobo_runtime_bindings"] = aggregated_bindings
				aggregated["gobo_slots"] = aggregated_slots
				return aggregated
	return {
		"has_gobo": bool(controls.get("has_gobo", false)),
		"gobo_norm": float(controls.get("gobo_norm", 0.0)),
		"has_gobo_index": bool(controls.get("has_gobo_index", false)),
		"gobo_index_norm": float(controls.get("gobo_index_norm", 0.0)),
		"has_gobo_rotation": bool(controls.get("has_gobo_rotation", false)),
		"gobo_rotation_norm": float(controls.get("gobo_rotation_norm", 0.0)),
		"gobo_slots": controls.get("gobo_slots", []),
		"gobo_ranges": controls.get("gobo_ranges", []),
		"gobo_runtime_bindings": controls.get("gobo_runtime_bindings", []),
	}

func has_lighting_controls(controls: Dictionary) -> bool:
	var changed_capability_types: Dictionary = controls.get("changed_capability_types", {})
	if not changed_capability_types.is_empty():
		return _has_changed_lighting_capability(changed_capability_types)
	var dimmer_controls: Dictionary = resolve_dimmer_controls(controls)
	if bool(dimmer_controls.get("has_dimmer", false)) or bool(dimmer_controls.get("has_zoom", false)):
		return true
	var color_controls: Dictionary = resolve_color_wheel_controls(controls)
	if bool(color_controls.get("has_cyan", false)) or bool(color_controls.get("has_magenta", false)) or bool(color_controls.get("has_yellow", false)):
		return true
	var gobo_controls: Dictionary = resolve_gobo_controls(controls)
	return bool(gobo_controls.get("has_gobo", false)) or bool(gobo_controls.get("has_gobo_index", false)) or bool(gobo_controls.get("has_gobo_rotation", false))

func prewarm_lighting_for_fixture(loader: Node, fixture_uuid: String) -> void:
	var geometry_nodes: Array = loader._get_fixture_geometry_nodes(fixture_uuid)
	var emitter_nodes: Array = loader._get_fixture_emitter_nodes(fixture_uuid)
	_prewarm_emissive_materials(loader, fixture_uuid, geometry_nodes)
	var emitter_photometrics: Array = loader._get_fixture_emitter_photometrics(fixture_uuid)
	var emitter_lights: Array = loader._collect_fixture_emitter_lights(fixture_uuid, emitter_nodes)
	var prewarm_controls: Dictionary = {
		"capabilities": {
			"dimmer": [{"has_dimmer": true, "dimmer_norm": 0.0}],
		}
	}
	for index in range(emitter_lights.size()):
		var light: SpotLight3D = emitter_lights[index]
		if light == null or not is_instance_valid(light):
			continue
		loader._ensure_beam_runtime_for_light(light)
		if light.has_meta("peraviz_beam_last_params"):
			continue
		var photometric: Dictionary = _resolve_emitter_photometric(loader, emitter_photometrics, index)
		loader._apply_emitter_light_state(light, photometric, 0.0, prewarm_controls)

func _resolve_render_ready_beam_color(controls: Dictionary) -> Color:
	var values: Variant = controls.get("render_ready_values", PackedFloat32Array())
	if values is PackedFloat32Array and values.size() >= 9:
		return Color(clamp(values[4], 0.0, 1.0), clamp(values[5], 0.0, 1.0), clamp(values[6], 0.0, 1.0), 1.0)
	return Color.TRANSPARENT

func apply_dimmer_feedback_to_fixture(loader: Node, fixture_uuid: String, dimmer: float, controls: Dictionary = {}) -> void:
	var geometry_nodes: Array = loader._get_fixture_geometry_nodes(fixture_uuid)
	var emitter_nodes: Array = loader._get_fixture_emitter_nodes(fixture_uuid)
	if geometry_nodes.is_empty() and emitter_nodes.is_empty():
		return
	var changed_capability_types: Dictionary = controls.get("changed_capability_types", {})
	var dimmer_changed: bool = changed_capability_types.is_empty() or bool(changed_capability_types.get("dimmer", false))
	var color_changed: bool = changed_capability_types.is_empty() or bool(changed_capability_types.get("color_wheel", false))
	var dimmer_percent: float = clamp(dimmer, 0.0, 100.0)
	var emitter_photometrics: Array = loader._get_fixture_emitter_photometrics(fixture_uuid)
	var normalized_dimmer: float = dimmer_percent / 100.0 if dimmer_changed else _resolve_current_fixture_dimmer(loader, fixture_uuid, emitter_nodes)
	var render_ready_color: Color = _resolve_render_ready_beam_color(controls)
	var beam_color: Color = render_ready_color if render_ready_color.a > 0.0 else loader._resolve_fixture_beam_color(emitter_photometrics, controls)
	var can_prioritize_light_dimmer: bool = dimmer_changed and not color_changed and _can_use_dimmer_only_fast_path(controls)
	if can_prioritize_light_dimmer:
		_apply_emitter_light_dimmer(loader, fixture_uuid, emitter_nodes, emitter_photometrics, beam_color, normalized_dimmer, controls)
		_apply_emissive_material_dimmer(loader, fixture_uuid, geometry_nodes, beam_color, normalized_dimmer)
		return
	if dimmer_changed or color_changed:
		_apply_emissive_material_dimmer(loader, fixture_uuid, geometry_nodes, beam_color, normalized_dimmer)
	_apply_emitter_light_dimmer(loader, fixture_uuid, emitter_nodes, emitter_photometrics, beam_color, normalized_dimmer, controls)

func _resolve_current_fixture_dimmer(loader: Node, fixture_uuid: String, emitter_nodes: Array) -> float:
	var emitter_lights: Array = loader._collect_fixture_emitter_lights(fixture_uuid, emitter_nodes)
	for light in emitter_lights:
		if light is SpotLight3D and is_instance_valid(light):
			return clamp(float(light.get_meta("peraviz_beam_base_intensity", 0.0)), 0.0, 1.0)
	return 0.0

func _apply_emissive_material_dimmer(loader: Node, fixture_uuid: String, geometry_nodes: Array, beam_color: Color, normalized_dimmer: float) -> void:
	var emissive_materials: Array = _prewarm_emissive_materials(loader, fixture_uuid, geometry_nodes)
	var energy_multiplier: float = lerp(0.0, 4.0, normalized_dimmer)
	for material in emissive_materials:
		if material is BaseMaterial3D:
			var material_rid: RID = _get_cached_material_rid(material)
			if material_rid.is_valid():
				RenderingServer.material_set_param(material_rid, "emission", beam_color)
				RenderingServer.material_set_param(material_rid, "emission_energy_multiplier", energy_multiplier)

func _prewarm_emissive_materials(loader: Node, fixture_uuid: String, geometry_nodes: Array) -> Array:
	var emissive_materials: Array = loader._collect_fixture_emissive_materials(fixture_uuid, geometry_nodes)
	for material in emissive_materials:
		if material is BaseMaterial3D and not bool(material.get_meta("peraviz_emissive_material_prewarmed", false)):
			material.emission_enabled = true
			material.set_meta("peraviz_material_rid", material.get_rid())
			material.set_meta("peraviz_emissive_material_prewarmed", true)
	return emissive_materials

func _get_cached_material_rid(material: BaseMaterial3D) -> RID:
	var cached_rid: Variant = material.get_meta("peraviz_material_rid", RID())
	if cached_rid is RID and cached_rid.is_valid():
		return cached_rid
	var material_rid: RID = material.get_rid()
	material.set_meta("peraviz_material_rid", material_rid)
	return material_rid

func _apply_emitter_light_dimmer(loader: Node, fixture_uuid: String, emitter_nodes: Array, emitter_photometrics: Array, beam_color: Color, normalized_dimmer: float, controls: Dictionary) -> void:
	var emitter_lights: Array = loader._collect_fixture_emitter_lights(fixture_uuid, emitter_nodes)
	var can_use_fast_path: bool = _can_use_dimmer_only_fast_path(controls)
	for index in range(emitter_lights.size()):
		var light: SpotLight3D = emitter_lights[index]
		if light == null or not is_instance_valid(light):
			continue
		var photometric: Dictionary = _resolve_emitter_photometric(loader, emitter_photometrics, index)
		if can_use_fast_path and _apply_emitter_light_dimmer_fast(loader, light, photometric, beam_color, normalized_dimmer, controls):
			continue
		loader._apply_emitter_light_state(light, photometric, normalized_dimmer, controls)

func _resolve_emitter_photometric(loader: Node, emitter_photometrics: Array, index: int) -> Dictionary:
	if index < emitter_photometrics.size() and emitter_photometrics[index] is Dictionary:
		var photometric: Dictionary = emitter_photometrics[index]
		if _has_required_photometric_keys(loader, photometric):
			return photometric
		var merged: Dictionary = loader.DEFAULT_EMITTER_PHOTOMETRICS.duplicate(true)
		merged.merge(photometric, true)
		return merged
	return loader.DEFAULT_EMITTER_PHOTOMETRICS

func _has_required_photometric_keys(loader: Node, photometric: Dictionary) -> bool:
	for key in loader.DEFAULT_EMITTER_PHOTOMETRICS.keys():
		if not photometric.has(key):
			return false
	return true

func _apply_emitter_light_dimmer_fast(loader: Node, light: SpotLight3D, photometric: Dictionary, beam_color: Color, normalized_dimmer: float, controls: Dictionary = {}) -> bool:
	return loader._apply_emitter_light_dimmer_fast(light, photometric, normalized_dimmer, beam_color, controls)

func _can_use_dimmer_only_fast_path(controls: Dictionary) -> bool:
	if bool(controls.get("time_tick_only", false)):
		return false
	var changed_capability_types: Dictionary = controls.get("changed_capability_types", {})
	if not changed_capability_types.is_empty():
		var changed_dimmer_controls: Dictionary = resolve_dimmer_controls(controls)
		return _only_dimmer_capability_changed(changed_capability_types) and bool(changed_dimmer_controls.get("has_dimmer", false)) and not bool(changed_dimmer_controls.get("has_zoom", false))
	var dimmer_controls: Dictionary = resolve_dimmer_controls(controls)
	if not bool(dimmer_controls.get("has_dimmer", false)) or bool(dimmer_controls.get("has_zoom", false)):
		return false
	var color_controls: Dictionary = resolve_color_wheel_controls(controls)
	if bool(color_controls.get("has_cyan", false)) or bool(color_controls.get("has_magenta", false)) or bool(color_controls.get("has_yellow", false)):
		return false
	var gobo_controls: Dictionary = resolve_gobo_controls(controls)
	return not bool(gobo_controls.get("has_gobo", false)) and not bool(gobo_controls.get("has_gobo_index", false)) and not bool(gobo_controls.get("has_gobo_rotation", false))

func _has_changed_lighting_capability(changed_capability_types: Dictionary) -> bool:
	for capability_type in ["dimmer", "color_wheel", "gobo", "prism", "strobe"]:
		if bool(changed_capability_types.get(capability_type, false)):
			return true
	return false

func _only_dimmer_capability_changed(changed_capability_types: Dictionary) -> bool:
	if not bool(changed_capability_types.get("dimmer", false)):
		return false
	for capability_type in ["color_wheel", "gobo", "prism", "strobe"]:
		if bool(changed_capability_types.get(capability_type, false)):
			return false
	return true

func record_beam_update() -> void:
	_track_phase("beam_update", Time.get_ticks_usec())

func record_gobo_update() -> void:
	_track_phase("gobo_update", Time.get_ticks_usec())

func get_phase_metrics() -> Dictionary:
	return _phase_metrics.duplicate(true)

func _track_phase(phase: String, phase_start_usec: int) -> void:
	var elapsed: int = max(Time.get_ticks_usec() - phase_start_usec, 0)
	if not _phase_metrics.has(phase):
		_phase_metrics[phase] = {"calls": 0, "total_usec": 0}
	var bucket: Dictionary = _phase_metrics.get(phase, {})
	bucket["calls"] = int(bucket.get("calls", 0)) + 1
	bucket["total_usec"] = int(bucket.get("total_usec", 0)) + elapsed
	_phase_metrics[phase] = bucket

func record_dmx_decode_elapsed(elapsed_usec: int) -> void:
	var start: int = Time.get_ticks_usec() - max(elapsed_usec, 0)
	_track_phase("dmx_decode", start)
