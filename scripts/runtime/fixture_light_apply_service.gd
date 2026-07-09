extends RefCounted
class_name FixtureLightApplyService

const VISUAL_CHANGE_TRANSFORM: int = 1 << 0
const VISUAL_CHANGE_DIMMER: int = 1 << 1
const VISUAL_CHANGE_COLOR: int = 1 << 2
const VISUAL_CHANGE_ZOOM: int = 1 << 3
const VISUAL_CHANGE_GOBO: int = 1 << 4
const VISUAL_CHANGE_GOBO_ROTATION: int = 1 << 5
const VISUAL_CHANGE_MATERIAL: int = 1 << 8
const VISUAL_CHANGE_BEAM_TOPOLOGY: int = 1 << 9

# Mirrors the native visual-frame row: fixture id, channel mask, visual mask, 13 compact controls, then 9 render-ready values.
const VISUAL_FRAME_HEADER_COUNT: int = 3
const VISUAL_FRAME_CHANNEL_COUNT: int = 13
const VISUAL_FRAME_RENDER_VALUE_COUNT: int = 9
const VISUAL_FRAME_STRIDE: int = VISUAL_FRAME_HEADER_COUNT + VISUAL_FRAME_CHANNEL_COUNT + VISUAL_FRAME_RENDER_VALUE_COUNT
const VISUAL_FRAME_CHANNEL_MASK_OFFSET: int = 1
const VISUAL_FRAME_VISUAL_MASK_OFFSET: int = 2
const VISUAL_FRAME_VALUES_OFFSET: int = VISUAL_FRAME_HEADER_COUNT
const VISUAL_FRAME_RENDER_VALUES_OFFSET: int = VISUAL_FRAME_HEADER_COUNT + VISUAL_FRAME_CHANNEL_COUNT

const DmxGoboControlsResolverScript = preload("res://scripts/dmx_gobo_controls_resolver.gd")

var _phase_metrics: Dictionary = {
	"dmx_decode": {"calls": 0, "total_usec": 0},
	"fixture_apply": {"calls": 0, "total_usec": 0},
	"light_apply": {"calls": 0, "total_usec": 0},
	"material_apply": {"calls": 0, "total_usec": 0},
	"beam_update": {"calls": 0, "total_usec": 0},
	"gobo_update": {"calls": 0, "total_usec": 0},
}
var _visual_apply_counters: Dictionary = {
	"fixtures_applied": 0,
	"light_rids_updated": 0,
	"materials_updated": 0,
	"beam_topology_rebuilds": 0,
	"beam_intensity_updates": 0,
	"gobo_topology_updates": 0,
	"gobo_parametric_updates": 0,
	"gobo_motion_render_state_updates": 0,
	"gobo_texture_compositions": 0,
	"beam_visible_count": 0,
	"spotlight_visible_count": 0,
	"rendering_server_calls": 0,
}
var _diagnostic_warning_keys: Dictionary = {}
var _diagnostic_info_keys: Dictionary = {}

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

func apply_visual_frame_to_fixture(loader: Node, fixture_uuid: String, visual_frame: PackedFloat32Array, base: int, frame_delta_sec: float, dmx_runtime: Object = null) -> void:
	var phase_start: int = Time.get_ticks_usec()
	var visual_mask: int = int(visual_frame[base + VISUAL_FRAME_VISUAL_MASK_OFFSET])
	var dimmer_norm: float = clamp(visual_frame[base + VISUAL_FRAME_VALUES_OFFSET], 0.0, 1.0)
	var pan_norm: float = clamp(visual_frame[base + VISUAL_FRAME_VALUES_OFFSET + 1], 0.0, 1.0)
	var tilt_norm: float = clamp(visual_frame[base + VISUAL_FRAME_VALUES_OFFSET + 2], 0.0, 1.0)
	var beam_energy: float = max(visual_frame[base + VISUAL_FRAME_RENDER_VALUES_OFFSET], 0.0)
	var spot_energy: float = max(visual_frame[base + VISUAL_FRAME_RENDER_VALUES_OFFSET + 1], 0.0)
	var beam_half_angle: float = clamp(visual_frame[base + VISUAL_FRAME_RENDER_VALUES_OFFSET + 2], 0.1, 90.0)
	var beam_angle: float = clamp(visual_frame[base + VISUAL_FRAME_RENDER_VALUES_OFFSET + 3], 0.1, 90.0)
	var beam_color := Color(clamp(visual_frame[base + VISUAL_FRAME_RENDER_VALUES_OFFSET + 4], 0.0, 1.0), clamp(visual_frame[base + VISUAL_FRAME_RENDER_VALUES_OFFSET + 5], 0.0, 1.0), clamp(visual_frame[base + VISUAL_FRAME_RENDER_VALUES_OFFSET + 6], 0.0, 1.0), 1.0)
	var beam_intensity: float = max(visual_frame[base + VISUAL_FRAME_RENDER_VALUES_OFFSET + 7], 0.0)
	var gobo_norm: float = clamp(visual_frame[base + VISUAL_FRAME_VALUES_OFFSET + 7], 0.0, 1.0)
	var gobo_index_norm: float = clamp(visual_frame[base + VISUAL_FRAME_VALUES_OFFSET + 8], 0.0, 1.0)
	var gobo_rotation_norm: float = clamp(visual_frame[base + VISUAL_FRAME_VALUES_OFFSET + 9], 0.0, 1.0)
	var material_energy: float = max(visual_frame[base + VISUAL_FRAME_RENDER_VALUES_OFFSET + 8], 0.0)
	_visual_apply_counters["fixtures_applied"] = int(_visual_apply_counters.get("fixtures_applied", 0)) + 1
	if (visual_mask & VISUAL_CHANGE_TRANSFORM) != 0:
		_apply_visual_frame_pan_tilt(loader, fixture_uuid, pan_norm, tilt_norm)
	if (visual_mask & (VISUAL_CHANGE_DIMMER | VISUAL_CHANGE_COLOR | VISUAL_CHANGE_ZOOM | VISUAL_CHANGE_GOBO | VISUAL_CHANGE_GOBO_ROTATION | VISUAL_CHANGE_MATERIAL | VISUAL_CHANGE_BEAM_TOPOLOGY)) != 0:
		_apply_visual_frame_lighting(loader, fixture_uuid, visual_mask, dimmer_norm, beam_energy, spot_energy, beam_half_angle, beam_angle, beam_color, beam_intensity, material_energy, frame_delta_sec, gobo_norm, gobo_index_norm, gobo_rotation_norm, dmx_runtime)
	_track_phase("fixture_apply", phase_start)

func _apply_visual_frame_pan_tilt(loader: Node, fixture_uuid: String, pan_degrees: float, tilt_degrees: float) -> void:
	loader._apply_pan_tilt_components_to_fixture(fixture_uuid, true, pan_degrees, true, tilt_degrees)

func apply_transform_targets(loader: Node, pan_component_id: int, tilt_component_id: int, pan_degrees: float, tilt_degrees: float) -> Dictionary:
	if loader.has_method("_apply_native_transform_targets"):
		return loader._apply_native_transform_targets(pan_component_id, tilt_component_id, pan_degrees, tilt_degrees)
	return {"failed": 1, "reason": "Native transform target registry is unavailable."}

func apply_emitter_intensity(loader: Node, fixture_uuid: String, dimmer_target_id: int, changed_mask: int, dimmer_norm: float, beam_energy: float, spot_energy: float, beam_intensity: float, material_energy: float) -> Dictionary:
	if dimmer_target_id <= 0 or (loader.has_method("_has_native_dimmer_target") and not loader._has_native_dimmer_target(dimmer_target_id)):
		return {"dimmer_requested": dimmer_target_id > 0, "dimmer_applied": false, "failed": 1}
	_visual_apply_counters["fixtures_applied"] = int(_visual_apply_counters.get("fixtures_applied", 0)) + 1
	_set_fixture_intensity_state(fixture_uuid, dimmer_norm, beam_energy, spot_energy, beam_intensity, material_energy)
	var target_record: Dictionary = loader._get_native_dimmer_target_record(dimmer_target_id) if loader.has_method("_get_native_dimmer_target_record") else {}
	var geometry_nodes: Array = target_record.get("geometry_nodes", [])
	var emitter_nodes: Array = target_record.get("emitter_nodes", [])
	if geometry_nodes.is_empty() and emitter_nodes.is_empty():
		_warn_visual_once(fixture_uuid + ":no_visual_nodes", "Fixture %s has dimmer %.3f but no geometry or emitter nodes." % [fixture_uuid, dimmer_norm], dimmer_norm > 0.0001)
		return {"dimmer_requested": true, "dimmer_applied": false, "failed": 1}
	var beam_color: Color = _fixture_render_color(fixture_uuid)
	_apply_visual_frame_materials(loader, fixture_uuid, geometry_nodes, beam_color, material_energy)
	var emitter_photometrics: Array = target_record.get("emitter_photometrics", [])
	var emitter_lights: Array = target_record.get("emitter_lights", [])
	var visible_beams: int = 0
	var visible_lights: int = 0
	for index in range(emitter_lights.size()):
		var light: SpotLight3D = emitter_lights[index]
		if light == null or not is_instance_valid(light):
			continue
		var photometric: Dictionary = _resolve_emitter_photometric(loader, emitter_photometrics, index)
		_apply_intensity_to_light(loader, fixture_uuid, light, photometric, changed_mask, dimmer_norm, beam_energy, spot_energy, beam_intensity, material_energy)
		if _should_enable_realtime_spotlight(loader, dimmer_norm > 0.0001):
			visible_lights += 1
		if _beam_is_visible(light, beam_intensity):
			visible_beams += 1
	_visual_apply_counters["beam_visible_count"] = int(_visual_apply_counters.get("beam_visible_count", 0)) + visible_beams
	_visual_apply_counters["spotlight_visible_count"] = int(_visual_apply_counters.get("spotlight_visible_count", 0)) + visible_lights
	return {"dimmer_requested": true, "dimmer_applied": true, "failed": 0}

func apply_emitter_color(loader: Node, fixture_uuid: String, beam_color: Color) -> void:
	_visual_apply_counters["fixtures_applied"] = int(_visual_apply_counters.get("fixtures_applied", 0)) + 1
	_set_fixture_render_color(fixture_uuid, beam_color)
	var geometry_nodes: Array = loader._get_fixture_geometry_nodes(fixture_uuid)
	_apply_visual_frame_materials(loader, fixture_uuid, geometry_nodes, beam_color, _fixture_material_energy(fixture_uuid))
	for light in _fixture_lights(loader, fixture_uuid):
		light.light_color = beam_color
		if light.has_meta("peraviz_beam_last_params"):
			_apply_visual_frame_beam(loader, light, VISUAL_CHANGE_COLOR, _fixture_dimmer(fixture_uuid) > 0.0001, _fixture_dimmer(fixture_uuid), _fixture_beam_angle(fixture_uuid), beam_color, _fixture_beam_intensity(fixture_uuid))

func apply_beam_optics(loader: Node, fixture_uuid: String, beam_half_angle: float, beam_angle: float) -> void:
	_visual_apply_counters["fixtures_applied"] = int(_visual_apply_counters.get("fixtures_applied", 0)) + 1
	_set_fixture_beam_angles(fixture_uuid, beam_half_angle, beam_angle)
	for light in _fixture_lights(loader, fixture_uuid):
		light.spot_angle = beam_half_angle
		_apply_visual_frame_beam(loader, light, VISUAL_CHANGE_ZOOM | VISUAL_CHANGE_BEAM_TOPOLOGY, _fixture_dimmer(fixture_uuid) > 0.0001, _fixture_dimmer(fixture_uuid), beam_angle, _fixture_render_color(fixture_uuid), _fixture_beam_intensity(fixture_uuid))

func apply_wheel_selection(loader: Node, fixture_uuid: String, changed_mask: int, frame_delta_sec: float, gobo_norm: float, dmx_runtime: Object = null) -> void:
	_visual_apply_counters["fixtures_applied"] = int(_visual_apply_counters.get("fixtures_applied", 0)) + 1
	_set_fixture_gobo_selection(fixture_uuid, gobo_norm)
	for light in _fixture_lights(loader, fixture_uuid):
		var topology_changed: bool = _apply_visual_frame_gobo(loader, fixture_uuid, light, changed_mask, frame_delta_sec, gobo_norm, _fixture_gobo_index(fixture_uuid), _fixture_gobo_rotation(fixture_uuid), dmx_runtime)
		if topology_changed:
			_apply_visual_frame_beam(loader, light, VISUAL_CHANGE_BEAM_TOPOLOGY, _fixture_dimmer(fixture_uuid) > 0.0001, _fixture_dimmer(fixture_uuid), _fixture_beam_angle(fixture_uuid), _fixture_render_color(fixture_uuid), _fixture_beam_intensity(fixture_uuid))

func apply_wheel_motion(loader: Node, fixture_uuid: String, changed_mask: int, frame_delta_sec: float, gobo_index_norm: float, gobo_rotation_norm: float, dmx_runtime: Object = null) -> void:
	_visual_apply_counters["fixtures_applied"] = int(_visual_apply_counters.get("fixtures_applied", 0)) + 1
	_set_fixture_gobo_motion(fixture_uuid, gobo_index_norm, gobo_rotation_norm)
	for light in _fixture_lights(loader, fixture_uuid):
		_apply_visual_frame_gobo(loader, fixture_uuid, light, changed_mask, frame_delta_sec, _fixture_gobo_selection(fixture_uuid), gobo_index_norm, gobo_rotation_norm, dmx_runtime)

func apply_temporal_output(_loader: Node, fixture_uuid: String, strobe_norm: float, output_norm: float) -> void:
	var key: String = _fixture_state_key(fixture_uuid)
	_visual_apply_counters["fixtures_applied"] = int(_visual_apply_counters.get("fixtures_applied", 0)) + 1
	_diagnostic_info_keys[key + ":temporal_state"] = {"strobe_norm": strobe_norm, "output_norm": output_norm}

func _apply_intensity_to_light(loader: Node, fixture_uuid: String, light: SpotLight3D, photometric: Dictionary, changed_mask: int, dimmer_norm: float, beam_energy: float, spot_energy: float, beam_intensity: float, material_energy: float) -> void:
	var visible: bool = dimmer_norm > 0.0001
	var beam_color: Color = _fixture_render_color(fixture_uuid)
	var beam_half_angle: float = _fixture_beam_half_angle(fixture_uuid)
	var beam_angle: float = _fixture_beam_angle(fixture_uuid)
	var light_energy: float = spot_energy if spot_energy > 0.0 else beam_energy
	_apply_canonical_light_visibility(loader, light, visible, _should_enable_realtime_spotlight(loader, visible))
	light.light_energy = light_energy
	light.spot_angle = beam_half_angle
	light.light_color = beam_color
	light.set_meta("peraviz_base_light_energy", beam_energy)
	light.set_meta("peraviz_beam_base_intensity", dimmer_norm)
	_visual_apply_counters["light_rids_updated"] = int(_visual_apply_counters.get("light_rids_updated", 0)) + 1
	if not light.has_meta("peraviz_beam_last_params"):
		_apply_visual_frame_initial_light_state(loader, light, photometric, dimmer_norm, beam_color, beam_energy, spot_energy, beam_half_angle, beam_angle, beam_intensity, material_energy)
	else:
		_apply_visual_frame_beam(loader, light, changed_mask, visible, dimmer_norm, beam_angle, beam_color, beam_intensity)

func _fixture_lights(loader: Node, fixture_uuid: String) -> Array:
	return loader._collect_fixture_emitter_lights(fixture_uuid, loader._get_fixture_emitter_nodes(fixture_uuid))

func _fixture_state_key(fixture_uuid: String) -> String:
	return "section_state:" + fixture_uuid

func _fixture_state(fixture_uuid: String) -> Dictionary:
	var key: String = _fixture_state_key(fixture_uuid)
	if not _diagnostic_info_keys.has(key):
		_diagnostic_info_keys[key] = {
			"dimmer": 0.0,
			"beam_energy": 0.0,
			"spot_energy": 0.0,
			"beam_intensity": 0.0,
			"material_energy": 0.0,
			"beam_half_angle": 12.5,
			"beam_angle": 25.0,
			"beam_color": Color.WHITE,
			"gobo": 0.0,
			"gobo_index": 0.0,
			"gobo_rotation": 0.0,
		}
	return _diagnostic_info_keys[key]

func _set_fixture_intensity_state(fixture_uuid: String, dimmer_norm: float, beam_energy: float, spot_energy: float, beam_intensity: float, material_energy: float) -> void:
	var state: Dictionary = _fixture_state(fixture_uuid)
	state["dimmer"] = dimmer_norm
	state["beam_energy"] = beam_energy
	state["spot_energy"] = spot_energy
	state["beam_intensity"] = beam_intensity
	state["material_energy"] = material_energy

func _set_fixture_render_color(fixture_uuid: String, beam_color: Color) -> void:
	_fixture_state(fixture_uuid)["beam_color"] = beam_color

func _set_fixture_beam_angles(fixture_uuid: String, beam_half_angle: float, beam_angle: float) -> void:
	var state: Dictionary = _fixture_state(fixture_uuid)
	state["beam_half_angle"] = beam_half_angle
	state["beam_angle"] = beam_angle

func _set_fixture_gobo_selection(fixture_uuid: String, gobo_norm: float) -> void:
	_fixture_state(fixture_uuid)["gobo"] = gobo_norm

func _set_fixture_gobo_motion(fixture_uuid: String, gobo_index_norm: float, gobo_rotation_norm: float) -> void:
	var state: Dictionary = _fixture_state(fixture_uuid)
	state["gobo_index"] = gobo_index_norm
	state["gobo_rotation"] = gobo_rotation_norm

func _fixture_dimmer(fixture_uuid: String) -> float:
	return float(_fixture_state(fixture_uuid).get("dimmer", 0.0))

func _fixture_material_energy(fixture_uuid: String) -> float:
	return float(_fixture_state(fixture_uuid).get("material_energy", 0.0))

func _fixture_beam_intensity(fixture_uuid: String) -> float:
	return float(_fixture_state(fixture_uuid).get("beam_intensity", 0.0))

func _fixture_beam_half_angle(fixture_uuid: String) -> float:
	return float(_fixture_state(fixture_uuid).get("beam_half_angle", 12.5))

func _fixture_beam_angle(fixture_uuid: String) -> float:
	return float(_fixture_state(fixture_uuid).get("beam_angle", 25.0))

func _fixture_render_color(fixture_uuid: String) -> Color:
	return _fixture_state(fixture_uuid).get("beam_color", Color.WHITE)

func _fixture_gobo_selection(fixture_uuid: String) -> float:
	return float(_fixture_state(fixture_uuid).get("gobo", 0.0))

func _fixture_gobo_index(fixture_uuid: String) -> float:
	return float(_fixture_state(fixture_uuid).get("gobo_index", 0.0))

func _fixture_gobo_rotation(fixture_uuid: String) -> float:
	return float(_fixture_state(fixture_uuid).get("gobo_rotation", 0.0))

func _beam_is_visible(light: SpotLight3D, fallback_intensity: float) -> bool:
	var beam_params: Dictionary = light.get_meta("peraviz_beam_last_params", {}) if light.has_meta("peraviz_beam_last_params") else {}
	var threshold: float = float(beam_params.get("intensity_visibility_threshold", 0.015))
	var scaled_intensity: float = clamp(float(beam_params.get("scaled_intensity", fallback_intensity)), 0.0, max(float(beam_params.get("intensity_max", 100.0)), 0.01))
	return scaled_intensity > threshold

func _apply_visual_frame_lighting(loader: Node, fixture_uuid: String, visual_mask: int, dimmer_norm: float, beam_energy: float, spot_energy: float, beam_half_angle: float, beam_angle: float, beam_color: Color, beam_intensity: float, material_energy: float, frame_delta_sec: float, gobo_norm: float, gobo_index_norm: float, gobo_rotation_norm: float, dmx_runtime: Object = null) -> void:
	var geometry_nodes: Array = loader._get_fixture_geometry_nodes(fixture_uuid)
	var emitter_nodes: Array = loader._get_fixture_emitter_nodes(fixture_uuid)
	if geometry_nodes.is_empty() and emitter_nodes.is_empty():
		_warn_visual_once(fixture_uuid + ":no_visual_nodes", "Fixture %s has dimmer %.3f but no geometry or emitter nodes." % [fixture_uuid, dimmer_norm], dimmer_norm > 0.0001)
		return
	_warn_visual_once(fixture_uuid + ":no_emitters", "Fixture %s has dimmer %.3f but no emitter nodes." % [fixture_uuid, dimmer_norm], dimmer_norm > 0.0001 and emitter_nodes.is_empty())
	if (visual_mask & (VISUAL_CHANGE_DIMMER | VISUAL_CHANGE_COLOR | VISUAL_CHANGE_MATERIAL)) != 0:
		_apply_visual_frame_materials(loader, fixture_uuid, geometry_nodes, beam_color, material_energy)
	var emitter_photometrics: Array = loader._get_fixture_emitter_photometrics(fixture_uuid)
	var emitter_lights: Array = loader._collect_fixture_emitter_lights(fixture_uuid, emitter_nodes)
	_warn_visual_once(fixture_uuid + ":no_runtime_lights", "Fixture %s has dimmer %.3f but no SpotLight3D runtime lights." % [fixture_uuid, dimmer_norm], dimmer_norm > 0.0001 and emitter_lights.is_empty())
	var visible_beams: int = 0
	var visible_lights: int = 0
	for index in range(emitter_lights.size()):
		var light: SpotLight3D = emitter_lights[index]
		if light == null or not is_instance_valid(light):
			continue
		var photometric: Dictionary = _resolve_emitter_photometric(loader, emitter_photometrics, index)
		var applied_state: Dictionary = _apply_visual_frame_light(loader, fixture_uuid, light, photometric, visual_mask, dimmer_norm, beam_energy, spot_energy, beam_half_angle, beam_angle, beam_color, beam_intensity, material_energy, frame_delta_sec, gobo_norm, gobo_index_norm, gobo_rotation_norm, dmx_runtime)
		if bool(applied_state.get("light_visible", false)):
			visible_lights += 1
		if bool(applied_state.get("beam_visible", false)):
			visible_beams += 1
	_warn_visual_once(fixture_uuid + ":no_visible_beams", "Fixture %s has dimmer %.3f but no visible beam/cone after apply." % [fixture_uuid, dimmer_norm], dimmer_norm > 0.0001 and not emitter_lights.is_empty() and visible_beams == 0)
	_visual_apply_counters["beam_visible_count"] = int(_visual_apply_counters.get("beam_visible_count", 0)) + visible_beams
	_visual_apply_counters["spotlight_visible_count"] = int(_visual_apply_counters.get("spotlight_visible_count", 0)) + visible_lights

func _apply_visual_frame_gobo(loader: Node, fixture_uuid: String, light: SpotLight3D, visual_mask: int, frame_delta_sec: float, gobo_norm: float, gobo_index_norm: float, gobo_rotation_norm: float, dmx_runtime: Object = null) -> bool:
	if (visual_mask & (VISUAL_CHANGE_GOBO | VISUAL_CHANGE_GOBO_ROTATION)) == 0:
		return false
	if not loader.has_method("_apply_live_visual_gobo_to_light"):
		return false
	var gobo_phase_start: int = Time.get_ticks_usec()
	var live_controls: Dictionary = {}
	var diagnostics: Dictionary = {}
	if dmx_runtime != null and dmx_runtime.has_method("get_live_gobo_diagnostics_for_fixture"):
		diagnostics = dmx_runtime.get_live_gobo_diagnostics_for_fixture(fixture_uuid)
	var result: Dictionary = loader._apply_live_visual_gobo_to_light(fixture_uuid, light, {
		"frame_delta_sec": frame_delta_sec,
		"gobo_norm": gobo_norm,
		"gobo_index_norm": gobo_index_norm,
		"gobo_rotation_norm": gobo_rotation_norm,
		"topology_changed": (visual_mask & VISUAL_CHANGE_GOBO) != 0,
		"parametric_changed": (visual_mask & VISUAL_CHANGE_GOBO_ROTATION) != 0,
		"diagnostics": diagnostics,
	}, live_controls)
	_track_phase("gobo_update", gobo_phase_start)
	if bool(result.get("applied", false)):
		_visual_apply_counters["gobo_parametric_updates"] = int(_visual_apply_counters.get("gobo_parametric_updates", 0)) + 1
		if bool(result.get("topology_changed", false)):
			_visual_apply_counters["gobo_topology_updates"] = int(_visual_apply_counters.get("gobo_topology_updates", 0)) + 1
		if bool(result.get("motion_state_updated", false)):
			_visual_apply_counters["gobo_motion_render_state_updates"] = int(_visual_apply_counters.get("gobo_motion_render_state_updates", 0)) + 1
		_visual_apply_counters["gobo_texture_compositions"] = int(result.get("texture_compositions", _visual_apply_counters.get("gobo_texture_compositions", 0)))
	return bool(result.get("topology_changed", false))

func _apply_visual_frame_materials(loader: Node, fixture_uuid: String, geometry_nodes: Array, beam_color: Color, material_energy: float) -> void:
	var material_phase_start: int = Time.get_ticks_usec()
	var emissive_materials: Array = _prewarm_emissive_materials(loader, fixture_uuid, geometry_nodes)
	for material in emissive_materials:
		if material is BaseMaterial3D:
			var material_rid: RID = _get_cached_material_rid(material)
			if material_rid.is_valid():
				RenderingServer.material_set_param(material_rid, "emission", beam_color)
				RenderingServer.material_set_param(material_rid, "emission_energy_multiplier", material_energy)
				_visual_apply_counters["materials_updated"] = int(_visual_apply_counters.get("materials_updated", 0)) + 1
				_visual_apply_counters["rendering_server_calls"] = int(_visual_apply_counters.get("rendering_server_calls", 0)) + 2
	_track_phase("material_apply", material_phase_start)

func _apply_visual_frame_light(loader: Node, fixture_uuid: String, light: SpotLight3D, photometric: Dictionary, visual_mask: int, dimmer_norm: float, beam_energy: float, spot_energy: float, beam_half_angle: float, beam_angle: float, beam_color: Color, beam_intensity: float, material_energy: float, frame_delta_sec: float, gobo_norm: float, gobo_index_norm: float, gobo_rotation_norm: float, dmx_runtime: Object = null) -> Dictionary:
	var light_phase_start: int = Time.get_ticks_usec()
	var visible: bool = dimmer_norm > 0.0001
	var real_spot_visible: bool = _should_enable_realtime_spotlight(loader, visible)
	var light_energy: float = spot_energy if spot_energy > 0.0 else beam_energy
	_apply_canonical_light_visibility(loader, light, visible, real_spot_visible)
	light.light_energy = light_energy
	light.spot_angle = beam_half_angle
	light.light_color = beam_color
	light.set_meta("peraviz_base_light_energy", beam_energy)
	light.set_meta("peraviz_beam_base_intensity", dimmer_norm)
	_visual_apply_counters["light_rids_updated"] = int(_visual_apply_counters.get("light_rids_updated", 0)) + 1
	_track_phase("light_apply", light_phase_start)
	var gobo_topology_changed: bool = _apply_visual_frame_gobo(loader, fixture_uuid, light, visual_mask, frame_delta_sec, gobo_norm, gobo_index_norm, gobo_rotation_norm, dmx_runtime)
	if gobo_topology_changed:
		visual_mask |= VISUAL_CHANGE_BEAM_TOPOLOGY
	if not light.has_meta("peraviz_beam_last_params"):
		_apply_visual_frame_initial_light_state(loader, light, photometric, dimmer_norm, beam_color, beam_energy, spot_energy, beam_half_angle, beam_angle, beam_intensity, material_energy)
	else:
		_apply_visual_frame_beam(loader, light, visual_mask, visible, dimmer_norm, beam_angle, beam_color, beam_intensity)
	if gobo_topology_changed and loader.has_method("_record_live_visual_gobo_beam_result"):
		loader._record_live_visual_gobo_beam_result(fixture_uuid, light)
	var beam_params: Dictionary = light.get_meta("peraviz_beam_last_params", {}) if light.has_meta("peraviz_beam_last_params") else {}
	var threshold: float = float(beam_params.get("intensity_visibility_threshold", 0.015))
	var scaled_intensity: float = clamp(float(beam_params.get("scaled_intensity", beam_intensity)), 0.0, max(float(beam_params.get("intensity_max", 100.0)), 0.01))
	var beam_visible: bool = scaled_intensity > threshold
	_log_visual_once("beam_parent_visible_spot_rid_hidden", "[PeravizVisualRuntime] Beam intensity is visible while realtime SpotLight rendering is disabled; the SpotLight node stays visible as the beam parent and its RenderingServer instance remains hidden.", dimmer_norm > 0.0001 and beam_visible and not real_spot_visible and _is_visual_debug_logging_enabled(loader))
	_warn_visual_once(str(light.get_instance_id()) + ":beam_params_not_visible", "Light %s has dimmer %.3f but beam params are not visible." % [str(light.get_instance_id()), dimmer_norm], dimmer_norm > 0.0001 and not beam_visible)
	return {"light_visible": real_spot_visible, "beam_visible": beam_visible}


func _apply_visual_frame_initial_light_state(loader: Node, light: SpotLight3D, photometric: Dictionary, dimmer_norm: float, beam_color: Color, beam_energy: float, spot_energy: float, beam_half_angle: float, beam_angle: float, beam_intensity: float, material_energy: float) -> void:
	var render_ready_values := PackedFloat32Array([
		beam_energy,
		spot_energy,
		beam_half_angle,
		beam_angle,
		beam_color.r,
		beam_color.g,
		beam_color.b,
		beam_intensity,
		material_energy,
	])
	loader._apply_emitter_light_state(light, photometric, dimmer_norm, {"render_ready_values": render_ready_values, "skip_gobo_projection": true})
	var visible: bool = dimmer_norm > 0.0001
	_apply_canonical_light_visibility(loader, light, visible, _should_enable_realtime_spotlight(loader, visible))

func _apply_visual_frame_beam(loader: Node, light: SpotLight3D, visual_mask: int, visible: bool, dimmer_norm: float, beam_angle: float, beam_color: Color, beam_intensity: float) -> void:
	if not loader.has_method("_update_beam_for_light"):
		return
	var needs_topology: bool = (visual_mask & VISUAL_CHANGE_BEAM_TOPOLOGY) != 0 or not light.has_meta("peraviz_beam_last_params")
	if needs_topology:
		var beam_phase_start: int = Time.get_ticks_usec()
		_apply_visual_frame_beam_topology(loader, light, visible, dimmer_norm, beam_angle, beam_color, beam_intensity)
		_track_phase("beam_update", beam_phase_start)
		return
	if loader.has_method("_update_beam_intensity_for_light"):
		var beam_phase_start: int = Time.get_ticks_usec()
		_apply_canonical_light_visibility(loader, light, visible, _should_enable_realtime_spotlight(loader, visible))
		if loader._update_beam_intensity_for_light(light, dimmer_norm, beam_color, beam_intensity):
			_visual_apply_counters["beam_intensity_updates"] = int(_visual_apply_counters.get("beam_intensity_updates", 0)) + 1
		elif visible:
			_apply_visual_frame_beam_topology(loader, light, visible, dimmer_norm, beam_angle, beam_color, beam_intensity)
		_track_phase("beam_update", beam_phase_start)

func _apply_visual_frame_beam_topology(loader: Node, light: SpotLight3D, visible: bool, dimmer_norm: float, beam_angle: float, beam_color: Color, beam_intensity: float) -> void:
	loader._ensure_beam_runtime_for_light(light)
	var lens_radius: float = max(float(light.get_meta("peraviz_lens_radius", 0.03)), 0.005)
	var beam_defaults: Dictionary = loader.get("_cached_beam_defaults") if loader.get("_cached_beam_defaults") is Dictionary else {}
	var beam_params: Dictionary = loader._build_cached_beam_params(light, beam_angle, beam_color, dimmer_norm, beam_intensity, lens_radius, beam_defaults)
	beam_params["normalized_dimmer"] = dimmer_norm
	beam_params["scaled_intensity"] = beam_intensity
	beam_params["beam_intensity"] = beam_intensity
	beam_params["intensity_max"] = float(loader.get("BEAM_INTENSITY_MAX")) if loader.get("BEAM_INTENSITY_MAX") != null else 50.0
	loader._update_beam_for_light(light, beam_params)
	_apply_canonical_light_visibility(loader, light, visible, _should_enable_realtime_spotlight(loader, visible))
	_visual_apply_counters["beam_topology_rebuilds"] = int(_visual_apply_counters.get("beam_topology_rebuilds", 0)) + 1

# Keeps the light node available as a beam parent while independently gating the real SpotLight RID.
func _apply_canonical_light_visibility(loader: Node, light: SpotLight3D, visible: bool, real_spot_visible: bool) -> void:
	if light == null or not is_instance_valid(light):
		return
	light.visible = visible
	var last_state: Dictionary = loader._get_or_create_emitter_last_state(light) if loader.has_method("_get_or_create_emitter_last_state") else {}
	last_state["prop:visible"] = visible
	last_state["prop:realtime_spot_visible"] = real_spot_visible
	var instance_rid: RID = light.get_instance()
	if instance_rid.is_valid():
		RenderingServer.instance_set_visible(instance_rid, real_spot_visible)
		_visual_apply_counters["rendering_server_calls"] = int(_visual_apply_counters.get("rendering_server_calls", 0)) + 1

func _should_enable_realtime_spotlight(loader: Node, visible: bool) -> bool:
	if not visible:
		return false
	var settings: Variant = loader.get("_visual_settings")
	if settings is Dictionary:
		return bool((settings as Dictionary).get("enable_realtime_spotlights", false))
	return false

# Emits a one-time diagnostic message for live visual-frame state transitions.
func _is_visual_debug_logging_enabled(loader: Node) -> bool:
	var settings: Variant = loader.get("_visual_settings") if loader != null else null
	if settings is Dictionary:
		return bool((settings as Dictionary).get("beam_debug_optics", false))
	return false

func _log_visual_once(key: String, message: String, condition: bool = true) -> void:
	if not condition or _diagnostic_info_keys.has(key):
		return
	_diagnostic_info_keys[key] = true
	print(message)

func _warn_visual_once(key: String, message: String, condition: bool = true) -> void:
	if not condition or _diagnostic_warning_keys.has(key):
		return
	_diagnostic_warning_keys[key] = true
	push_warning(message)

func get_visual_apply_counters() -> Dictionary:
	return _visual_apply_counters.duplicate(false)

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

# Resolves lighting gobo controls through the shared live/legacy resolver.
func resolve_gobo_controls(controls: Dictionary) -> Dictionary:
	return DmxGoboControlsResolverScript.resolve(controls)

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
