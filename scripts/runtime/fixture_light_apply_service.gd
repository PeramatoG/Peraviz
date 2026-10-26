extends RefCounted
class_name FixtureLightApplyService

# Production snapshots use required native dense composition. Dictionary helpers
# below remain only for manual fixture controls and explicit unbound API callers.

const VISUAL_CHANGE_TRANSFORM: int = 1 << 0
const VISUAL_CHANGE_DIMMER: int = 1 << 1
const VISUAL_CHANGE_COLOR: int = 1 << 2
const VISUAL_CHANGE_ZOOM: int = 1 << 3
const VISUAL_CHANGE_GOBO: int = 1 << 4
const VISUAL_CHANGE_GOBO_ROTATION: int = 1 << 5
const VISUAL_CHANGE_MATERIAL: int = 1 << 8
const VISUAL_CHANGE_BEAM_TOPOLOGY: int = 1 << 9

const DmxGoboControlsResolverScript = preload("res://scripts/dmx_gobo_controls_resolver.gd")
const RenderDiagnosticPolicyScript = preload("res://scripts/runtime/render_diagnostic_policy.gd")

const DensePresentationAdapterScript = preload("res://scripts/runtime/dense_presentation_adapter.gd")
const SurfacePolicy = preload("res://scripts/runtime/surface_light_policy.gd")
var _diagnostic_open_surface_lights: bool = SurfacePolicy.open_lights_from_arguments(OS.get_cmdline_user_args())

var _dense_adapter: RefCounted
var _dense_required: bool = false
var _dense_install_error_reported: bool = false

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
	"beam_full_state_applies": 0,
	"beam_full_state_reason_initialization": 0,
	"beam_full_state_reason_topology_mask": 0,
	"beam_dynamic_changed": 0,
	"beam_dynamic_unchanged": 0,
	"beam_dynamic_unresolved": 0,
	"beam_intensity_updates": 0,
	"beam_optics_rows": 0,
	"beam_optics_parametric_updates": 0,
	"gobo_topology_updates": 0,
	"gobo_parametric_updates": 0,
	"gobo_motion_render_state_updates": 0,
	"gobo_texture_compositions": 0,
	"beam_visible_count": 0,
	"spotlight_visible_count": 0,
	"rendering_server_calls": 0,
	"physical_outputs_considered": 0,
	"beams_considered": 0,
	"light_properties_written": 0,
	"light_visibility_calls": 0,
	"beam_shader_parameters_written": 0,
	"beam_visibility_transitions": 0,
	"material_parameters_written": 0,
	"emitter_output_commit_candidates": 0,
	"emitter_output_commits": 0,
	"emitter_output_commits_signature_skipped": 0,
	"clustered_element_limit": 0,
	"emitter_output_commits_coalesced": 0,
	"emitter_output_commit_usec": 0,
}
var _diagnostic_warning_keys: Dictionary = {}
var _diagnostic_info_keys: Dictionary = {}
var _material_state_by_rid: Dictionary = {}
var _light_desired_state: Dictionary = {}
var _render_diagnostic_mode: String = RenderDiagnosticPolicyScript.FULL
var _visible_beam_ids: Dictionary = {}
var _visible_light_ids: Dictionary = {}
var _beam_optics_signatures: Dictionary = {}
var _target_states: Dictionary = {}
var _committed_output_states: Dictionary = {}
var _snapshot_output_commits: Dictionary = {}
var _snapshot_commit_active: bool = false
var _snapshot_commit_high_water: int = 0
var _performance_trace_enabled: bool = false

# Retires identity/RID caches when a scene or native binding generation is replaced.
func reset_scene_state() -> void:
	if _dense_adapter != null:
		_dense_adapter.clear()
	_dense_adapter = null
	_dense_required = false
	_dense_install_error_reported = false
	_snapshot_commit_active = false
	_snapshot_output_commits.clear()
	_target_states.clear()
	_committed_output_states.clear()
	_beam_optics_signatures.clear()
	_light_desired_state.clear()
	_material_state_by_rid.clear()
	_visible_beam_ids.clear()
	_visible_light_ids.clear()
	_diagnostic_warning_keys.clear()
	_diagnostic_info_keys.clear()
	_snapshot_commit_high_water = 0
	_visual_apply_counters["beam_visible_count"] = 0
	_visual_apply_counters["spotlight_visible_count"] = 0

func set_render_diagnostic_mode(mode: String) -> void:
	_render_diagnostic_mode = mode
	if _dense_adapter != null: _dense_adapter.set_mode(mode)

func set_performance_trace_enabled(enabled: bool) -> void:
	_performance_trace_enabled = enabled
	if _dense_adapter != null: _dense_adapter._trace = enabled
	if enabled:
		_visual_apply_counters["clustered_element_limit"] = int(ProjectSettings.get_setting("rendering/limits/cluster_builder/max_clustered_elements", 512))

# Installs the normal native presentation path after renderer target setup.
func install_dense_presentation(loader: Node, registry: RefCounted, budget: SceneLoadBudget = null) -> bool:
	_dense_required = true
	_dense_adapter = DensePresentationAdapterScript.new()
	if not await _dense_adapter.install(loader, self, registry, budget):
		_dense_adapter.clear()
		_dense_adapter = null
		if not _dense_install_error_reported:
			_dense_install_error_reported = true
			push_error("Dense presentation installation failed (native class or bindings unavailable); lighting playback is disabled. Legacy state fallback is forbidden.")
		return false
	return true

func is_dense_presentation_active() -> bool:
	return _dense_adapter != null and _dense_adapter.is_installed()

# Rebinds resources only at explicit presentation/control boundaries.
func rebind_dense_light(light: SpotLight3D) -> void:
	if _dense_adapter != null: _dense_adapter.rebind_light(light)

func refresh_dense_renderer() -> void:
	if _dense_adapter != null: _dense_adapter.refresh_renderer()

# 0 permits explicit compatibility callers; -1 rejects an unavailable required dense path.
func compose_dense_snapshot(descriptors: PackedInt32Array, integers: PackedInt32Array, values: PackedFloat32Array, semantic_conversion_us: int = 0) -> int:
	if _dense_adapter == null: return -1 if _dense_required else 0
	return 1 if _dense_adapter.compose(descriptors, integers, values, _performance_trace_enabled, _render_diagnostic_mode, semantic_conversion_us) else -1

# One native calculation boundary for production; no intermediate lighting payload enters Godot.
func consume_native_snapshot(runtime: Object, schema_generation: int, poll_only: bool = false) -> Dictionary:
	if not is_dense_presentation_active():
		return {"valid": false, "native_presentation": false}
	return _dense_adapter.consume_runtime(runtime, schema_generation, poll_only)

# Starts snapshot-local collection of canonical physical-output renderer commits.
func begin_visual_snapshot() -> void:
	if _dense_adapter != null or _dense_required:
		_snapshot_commit_active = false
		return
	_snapshot_output_commits.clear()
	_snapshot_commit_active = true

# Commits each touched canonical physical output once after all logical state is current.
func end_visual_snapshot() -> void:
	if _dense_adapter != null:
		_dense_adapter.apply()
		_snapshot_commit_active = false
		return # Native playback never enters Dictionary coalescing or visibility accounting.
	if not _snapshot_commit_active:
		return
	var commit_start_usec: int = Time.get_ticks_usec() if _performance_trace_enabled else 0
	_snapshot_commit_active = false
	if _performance_trace_enabled:
		_snapshot_commit_high_water = maxi(_snapshot_commit_high_water, _snapshot_output_commits.size())
	for output_key in _snapshot_output_commits:
		var pending: Dictionary = _snapshot_output_commits[output_key]
		var output_id: int = int(pending.get("output_id", 0))
		var fixture_uuid: String = str(pending.get("fixture_uuid", ""))
		var loader: Node = pending.get("loader") as Node
		var output_record: Dictionary = pending.get("output_record", {})
		var state: Dictionary = _target_state(output_id, fixture_uuid)
		if _performance_trace_enabled:
			_visual_apply_counters["physical_outputs_considered"] += 1
		var result: Dictionary = _apply_beam_output_record(loader, fixture_uuid, output_record, int(pending.get("changed_mask", 0)), state)
		if _performance_trace_enabled:
			_visual_apply_counters["emitter_output_commits" if not bool(result.get("signature_skipped", false)) else "emitter_output_commits_signature_skipped"] = int(_visual_apply_counters.get("emitter_output_commits" if not bool(result.get("signature_skipped", false)) else "emitter_output_commits_signature_skipped", 0)) + 1
	_snapshot_output_commits.clear()
	if _performance_trace_enabled:
		_visual_apply_counters["emitter_output_commit_usec"] += max(Time.get_ticks_usec() - commit_start_usec, 0)
		_visual_apply_counters["beam_visible_count"] = _visible_beam_ids.size()
		_visual_apply_counters["spotlight_visible_count"] = _visible_light_ids.size()

# Defers a canonical output commit while preserving one entry per stable output ID.
func _queue_or_apply_output(loader: Node, fixture_uuid: String, output_id: int, output_record: Dictionary, changed_mask: int) -> Dictionary:
	if not _snapshot_commit_active:
		if _performance_trace_enabled:
			_visual_apply_counters["physical_outputs_considered"] += 1
		var state: Dictionary = _target_state(output_id, fixture_uuid)
		return _apply_beam_output_record(loader, fixture_uuid, output_record, changed_mask, state)
	if _performance_trace_enabled:
		_visual_apply_counters["emitter_output_commit_candidates"] += 1
	if _snapshot_output_commits.has(output_id):
		var pending: Dictionary = _snapshot_output_commits[output_id]
		pending["changed_mask"] = int(pending.get("changed_mask", 0)) | changed_mask
		if _performance_trace_enabled:
			_visual_apply_counters["emitter_output_commits_coalesced"] += 1
	else:
		_snapshot_output_commits[output_id] = {"loader": loader, "fixture_uuid": fixture_uuid, "output_id": output_id, "output_record": output_record, "changed_mask": changed_mask}
	return {"lights_mutated": 0, "beams_mutated": 0, "materials_mutated": 0, "commit_deferred": true}

# Queues one output without constructing a per-row result on the production snapshot path.
func _queue_output_fast(loader: Node, fixture_uuid: String, output_id: int, output_record: Dictionary, changed_mask: int) -> void:
	if _performance_trace_enabled:
		_visual_apply_counters["emitter_output_commit_candidates"] += 1
	if _snapshot_output_commits.has(output_id):
		var pending: Dictionary = _snapshot_output_commits[output_id]
		pending["changed_mask"] = int(pending.get("changed_mask", 0)) | changed_mask
		if _performance_trace_enabled:
			_visual_apply_counters["emitter_output_commits_coalesced"] += 1
		return
	_snapshot_output_commits[output_id] = {"loader": loader, "fixture_uuid": fixture_uuid, "output_id": output_id, "output_record": output_record, "changed_mask": changed_mask}

func _beams_enabled() -> bool:
	return RenderDiagnosticPolicyScript.renders_beams(_render_diagnostic_mode)

func apply_dmx_controls_to_fixture(loader: Node, fixture_uuid: String, controls: Dictionary) -> void:
	var phase_start: int = Time.get_ticks_usec() if _performance_trace_enabled else 0
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

func apply_transform_targets(loader: Node, pan_component_id: int, tilt_component_id: int, pan_degrees: float, tilt_degrees: float) -> Dictionary:
	if loader.has_method("_apply_native_transform_targets"):
		return loader._apply_native_transform_targets(pan_component_id, tilt_component_id, pan_degrees, tilt_degrees)
	return {"failed": 1, "reason": "Native transform target registry is unavailable."}

func apply_transform_targets_fast(loader: Node, pan_component_id: int, tilt_component_id: int, pan_degrees: float, tilt_degrees: float) -> bool:
	return loader.has_method("_apply_native_transform_targets_fast") and bool(loader._apply_native_transform_targets_fast(pan_component_id, tilt_component_id, pan_degrees, tilt_degrees))

func apply_emitter_intensity(loader: Node, fixture_uuid: String, dimmer_target_id: int, changed_mask: int, dimmer_norm: float, beam_energy: float, spot_energy: float, beam_intensity: float, material_energy: float) -> Dictionary:
	if dimmer_target_id <= 0 or (loader.has_method("_has_native_dimmer_target") and not loader._has_native_dimmer_target(dimmer_target_id)):
		return {"dimmer_requested": dimmer_target_id > 0, "target_resolved": false, "dimmer_applied": false, "failed": 1, "failure_reason": "target not registered"}
	if _performance_trace_enabled:
		_visual_apply_counters["fixtures_applied"] += 1
	var target_record: Dictionary = loader._get_native_dimmer_target_record(dimmer_target_id) if loader.has_method("_get_native_dimmer_target_record") else {}
	var output_records: Array = target_record.get("beam_output_records", [])
	var lights_mutated: int = 0
	var beams_mutated: int = 0
	var materials_mutated: int = 0
	var visible_beams: int = 0
	var visible_lights: int = 0
	var commit_deferred: bool = false
	if not output_records.is_empty():
		for output_item in output_records:
			var output_record: Dictionary = output_item
			var output_id: int = _output_id_from_record(output_record, dimmer_target_id)
			_set_target_intensity_state(output_id, fixture_uuid, dimmer_norm, beam_energy, spot_energy, beam_intensity, material_energy)
			var result: Dictionary = _queue_or_apply_output(loader, fixture_uuid, output_id, output_record, changed_mask)
			commit_deferred = commit_deferred or bool(result.get("commit_deferred", false))
			lights_mutated += int(result.get("lights_mutated", 0))
			beams_mutated += int(result.get("beams_mutated", 0))
			materials_mutated += int(result.get("materials_mutated", 0))
			if bool(result.get("visible_light", false)):
				visible_lights += 1
			if bool(result.get("visible_beam", false)):
				visible_beams += 1
	else:
		_set_target_intensity_state(dimmer_target_id, fixture_uuid, dimmer_norm, beam_energy, spot_energy, beam_intensity, material_energy)
		var beam_color: Color = _target_render_color(dimmer_target_id, fixture_uuid)
		var color_gain: float = _target_color_gain(dimmer_target_id, fixture_uuid)
		var gained_beam_energy: float = beam_energy * color_gain
		var gained_spot_energy: float = spot_energy * color_gain
		var gained_beam_intensity: float = beam_intensity * color_gain
		var gained_material_energy: float = material_energy * color_gain
		var lens_material_targets: Array = target_record.get("lens_material_targets", target_record.get("emissive_materials", []))
		materials_mutated = _apply_visual_frame_materials(loader, fixture_uuid, target_record.get("geometry_nodes", []), beam_color, gained_material_energy, lens_material_targets, true)
		var emitter_photometrics: Array = target_record.get("emitter_records", target_record.get("emitter_photometrics", []))
		var emitter_lights: Array = target_record.get("emitter_anchors", target_record.get("emitter_lights", []))
		for index in range(emitter_lights.size()):
			var light: SpotLight3D = emitter_lights[index]
			if light == null or not is_instance_valid(light):
				continue
			var photometric: Dictionary = _resolve_emitter_photometric(loader, emitter_photometrics, index)
			if _performance_trace_enabled:
				_visual_apply_counters["physical_outputs_considered"] += 1
			var light_result: Dictionary = _apply_intensity_to_light(loader, fixture_uuid, light, photometric, changed_mask, dimmer_norm, gained_beam_energy, gained_spot_energy, gained_beam_intensity, gained_material_energy, beam_color)
			lights_mutated += int(light_result.get("lights_mutated", 0))
			beams_mutated += int(light_result.get("beams_mutated", 0))
			if bool(_light_desired_for(light).get("applied_realtime_visible", false)):
				visible_lights += 1
			if _beam_is_visible(light, _clamped_beam_intensity(_scaled_projected_value(gained_beam_intensity, photometric))):
				visible_beams += 1
	if _performance_trace_enabled:
		_visual_apply_counters["beam_visible_count"] = _visible_beam_ids.size()
		_visual_apply_counters["spotlight_visible_count"] = _visible_light_ids.size()
	var beam_instances: Array = target_record.get("beam_instances", [])
	var resolved_lens_material_targets: Array = target_record.get("lens_material_targets", target_record.get("emissive_materials", []))
	var mutable_resources: int = int(target_record.get("emitter_anchors", target_record.get("emitter_lights", [])).size()) + beam_instances.size() + resolved_lens_material_targets.size()
	var mutations: int = lights_mutated + beams_mutated + materials_mutated
	if mutable_resources <= 0:
		return {"dimmer_requested": true, "target_resolved": true, "lights_considered": 0, "lights_mutated": 0, "beams_mutated": 0, "materials_mutated": 0, "visible_output_after_apply": false, "dimmer_applied": false, "failed": 1, "failure_reason": "target has no mutable Dimmer resources"}
	var emitter_lights_count: int = int(target_record.get("emitter_anchors", target_record.get("emitter_lights", [])).size())
	return {"dimmer_requested": true, "target_resolved": true, "lights_considered": emitter_lights_count, "beam_instances_considered": beam_instances.size(), "lens_material_targets_considered": resolved_lens_material_targets.size(), "lights_mutated": lights_mutated, "beams_mutated": beams_mutated, "materials_mutated": materials_mutated, "visible_output_after_apply": visible_lights > 0 or visible_beams > 0 or _any_beam_instance_visible(beam_instances) or material_energy > 0.0001, "dimmer_applied": true, "commit_deferred": commit_deferred, "unchanged": mutations == 0 and not commit_deferred, "failed": 0, "failure_reason": ""}

func apply_emitter_color(loader: Node, fixture_uuid: String, color_target_id: int, changed_mask: int, beam_color: Color, color_gain: float) -> Dictionary:
	if color_target_id <= 0 or (loader.has_method("_has_native_color_target") and not loader._has_native_color_target(color_target_id)):
		return {"color_requested": color_target_id > 0, "target_resolved": false, "color_applied": false, "failed": 1, "failure_reason": "target not registered"}
	if _performance_trace_enabled:
		_visual_apply_counters["fixtures_applied"] += 1
	var target_record: Dictionary = loader._get_native_color_target_record(color_target_id) if loader.has_method("_get_native_color_target_record") else {}
	var output_records: Array = target_record.get("beam_output_records", [])
	var materials_mutated: int = 0
	var lights_mutated: int = 0
	var beams_mutated: int = 0
	var commit_deferred: bool = false
	if not output_records.is_empty():
		for output_item in output_records:
			var output_record: Dictionary = output_item
			var output_id: int = _output_id_from_record(output_record, color_target_id)
			_set_target_color_state(output_id, fixture_uuid, beam_color, color_gain)
			var result: Dictionary = _queue_or_apply_output(loader, fixture_uuid, output_id, output_record, changed_mask)
			commit_deferred = commit_deferred or bool(result.get("commit_deferred", false))
			lights_mutated += int(result.get("lights_mutated", 0))
			beams_mutated += int(result.get("beams_mutated", 0))
			materials_mutated += int(result.get("materials_mutated", 0))
	else:
		_set_target_color_state(color_target_id, fixture_uuid, beam_color, color_gain)
		var state: Dictionary = _target_state(color_target_id, fixture_uuid)
		var final_gain: float = max(float(state.get("color_gain", 1.0)), 0.0)
		var final_material_energy: float = float(state.get("material_energy", 0.0)) * final_gain
		var final_beam_energy: float = float(state.get("beam_energy", 0.0)) * final_gain
		var final_spot_energy: float = float(state.get("spot_energy", 0.0)) * final_gain
		var final_beam_intensity: float = float(state.get("beam_intensity", 0.0)) * final_gain
		var lens_material_targets: Array = target_record.get("lens_material_targets", target_record.get("emissive_materials", []))
		materials_mutated = _apply_visual_frame_materials(loader, fixture_uuid, target_record.get("geometry_nodes", []), beam_color, final_material_energy, lens_material_targets, true)
		for light in target_record.get("emitter_anchors", []):
			if light == null or not is_instance_valid(light):
				continue
			var final_light_energy: float = final_spot_energy if final_spot_energy > 0.0 else final_beam_energy
			_update_desired_light_state(light, final_light_energy, float(_light_desired_for(light).get("angle", light.spot_angle)), beam_color, bool(_light_desired_for(light).get("visible", false)) and final_light_energy > 0.0)
			lights_mutated += _apply_desired_light_state(loader, light)
			var beam: MeshInstance3D = loader._get_beam_resource_for_light(light) if loader.has_method("_get_beam_resource_for_light") else null
			if beam != null and is_instance_valid(beam):
				if _performance_trace_enabled:
					_visual_apply_counters["beams_considered"] += 1
				if _beams_enabled():
					beams_mutated += _set_beam_dynamic_parameters(beam, beam_color, _clamped_beam_intensity(final_beam_intensity))
				else:
					beams_mutated += _set_beam_visible(beam, false)
	var mutations: int = lights_mutated + beams_mutated + materials_mutated
	return {"color_requested": true, "target_resolved": true, "color_applied": true, "commit_deferred": commit_deferred, "unchanged": mutations == 0 and not commit_deferred, "lights_mutated": lights_mutated, "beams_mutated": beams_mutated, "materials_mutated": materials_mutated, "failed": 0, "color_gain": color_gain}

# Applies the common native color row without allocating diagnostic result dictionaries.
func apply_emitter_color_fast(loader: Node, fixture_uuid: String, color_target_id: int, changed_mask: int, beam_color: Color, color_gain: float) -> bool:
	if not _snapshot_commit_active or color_target_id <= 0 or (loader.has_method("_has_native_color_target") and not loader._has_native_color_target(color_target_id)):
		return false
	var target_record: Dictionary = loader._get_native_color_target_record(color_target_id) if loader.has_method("_get_native_color_target_record") else {}
	var output_records: Array = target_record.get("beam_output_records", [])
	if output_records.is_empty():
		return false
	for output_item in output_records:
		var output_record: Dictionary = output_item
		var output_id: int = _output_id_from_record(output_record, color_target_id)
		_set_target_color_state(output_id, fixture_uuid, beam_color, color_gain)
		_queue_output_fast(loader, fixture_uuid, output_id, output_record, changed_mask)
	return true

# Applies the common native intensity row without allocating diagnostic result dictionaries.
func apply_emitter_intensity_fast(loader: Node, fixture_uuid: String, dimmer_target_id: int, changed_mask: int, dimmer_norm: float, beam_energy: float, spot_energy: float, beam_intensity: float, material_energy: float) -> bool:
	if not _snapshot_commit_active or dimmer_target_id <= 0 or (loader.has_method("_has_native_dimmer_target") and not loader._has_native_dimmer_target(dimmer_target_id)):
		return false
	var target_record: Dictionary = loader._get_native_dimmer_target_record(dimmer_target_id) if loader.has_method("_get_native_dimmer_target_record") else {}
	var output_records: Array = target_record.get("beam_output_records", [])
	if output_records.is_empty():
		return false
	for output_item in output_records:
		var output_record: Dictionary = output_item
		var output_id: int = _output_id_from_record(output_record, dimmer_target_id)
		_set_target_intensity_state(output_id, fixture_uuid, dimmer_norm, beam_energy, spot_energy, beam_intensity, material_energy)
		_queue_output_fast(loader, fixture_uuid, output_id, output_record, changed_mask)
	return true

func apply_beam_optics(loader: Node, fixture_uuid: String, optics_target_id: int, _changed_mask: int, beam_half_angle: float, beam_angle: float, zoom_norm: float) -> Dictionary:
	if optics_target_id <= 0 or (loader.has_method("_has_native_optics_target") and not loader._has_native_optics_target(optics_target_id)):
		return {"optics_requested": optics_target_id > 0, "target_resolved": false, "optics_applied": false, "optics_failed": 1, "failure_reason": "target not registered"}
	if _performance_trace_enabled:
		_visual_apply_counters["fixtures_applied"] += 1
		_visual_apply_counters["beam_optics_rows"] += 1
	_set_fixture_beam_angles(fixture_uuid, beam_half_angle, beam_angle)
	var target_record: Dictionary = loader._get_native_optics_target_record(optics_target_id) if loader.has_method("_get_native_optics_target_record") else {}
	var output_records: Array = target_record.get("beam_output_records", [])
	var emitter_lights: Array = target_record.get("emitter_anchors", [])
	var mutations: int = 0
	for index in range(emitter_lights.size()):
		var light: Variant = emitter_lights[index]
		var output_record: Dictionary = output_records[index] if index < output_records.size() and output_records[index] is Dictionary else {}
		var output_id: int = _output_id_from_record(output_record, optics_target_id)
		var spot: SpotLight3D = light as SpotLight3D
		if spot == null or not is_instance_valid(spot):
			continue
		var desired: Dictionary = _light_desired_for(spot)
		_update_desired_light_state(spot, float(desired.get("energy", spot.light_energy)), beam_half_angle, desired.get("color", spot.light_color), bool(desired.get("visible", false)))
		_apply_desired_light_state(loader, spot)
		var last_params: Dictionary = spot.get_meta("peraviz_beam_last_params", {}) if spot.has_meta("peraviz_beam_last_params") else {}
		var state: Dictionary = _target_state(output_id, fixture_uuid)
		var color_gain: float = max(float(state.get("color_gain", 1.0)), 0.0)
		var gained_beam_intensity: float = float(state.get("beam_intensity", 0.0)) * color_gain
		var profile: Dictionary = output_record.get("beam_optical_profile", target_record.get("beam_optical_profile", {}))
		var optics_signature: Array = [beam_half_angle, beam_angle, zoom_norm, gained_beam_intensity, _target_render_color(output_id, fixture_uuid)]
		if _beam_optics_signatures.get(spot.get_instance_id(), []) == optics_signature:
			continue
		_beam_optics_signatures[spot.get_instance_id()] = optics_signature
		if last_params.is_empty():
			last_params = _beam_params_from_target_record(spot, output_record if not output_record.is_empty() else target_record, beam_angle, _target_render_color(output_id, fixture_uuid), _target_dimmer(output_id, fixture_uuid), gained_beam_intensity)
		last_params["beam_angle"] = beam_angle
		last_params["normalized_dimmer"] = _target_dimmer(output_id, fixture_uuid)
		last_params["beam_color"] = _target_render_color(output_id, fixture_uuid)
		var scaled_intensity: float = _clamped_beam_intensity(_scaled_projected_value(gained_beam_intensity, profile))
		last_params["scaled_intensity"] = scaled_intensity
		last_params["beam_intensity"] = scaled_intensity
		var optics_result: Dictionary = {}
		if _beams_enabled() and _has_projected_beam(profile):
			spot.set_meta("peraviz_beam_last_params", last_params)
			optics_result = loader._apply_beam_optics_for_light(spot, last_params) if loader.has_method("_apply_beam_optics_for_light") else {}
		else:
			_hide_beam_for_light(loader, spot)
		if bool(optics_result.get("parametric_update_performed", false)) or bool(optics_result.get("topology_rebuilt", false)):
			mutations += 1
		if _performance_trace_enabled and bool(optics_result.get("topology_rebuilt", false)):
			_visual_apply_counters["beam_topology_rebuilds"] += 1
	if _performance_trace_enabled:
		_visual_apply_counters["beam_optics_parametric_updates"] += mutations
	return {"optics_requested": true, "target_resolved": true, "optics_resolved": 1, "optics_mutated": mutations, "optics_applied": true, "unchanged": mutations == 0, "optics_failed": 0}

func _beam_params_from_target_record(light: SpotLight3D, target_record: Dictionary, beam_angle: float, beam_color: Color, dimmer_norm: float, beam_intensity: float) -> Dictionary:
	var profile: Dictionary = target_record.get("beam_optical_profile", {})
	var scaled_beam_intensity: float = _clamped_beam_intensity(_scaled_projected_value(beam_intensity, profile))
	var diagnostics: Dictionary = light.get_meta("peraviz_beam_radius_diagnostics", {}) if light != null and light.has_meta("peraviz_beam_radius_diagnostics") else {}
	var beam_range: float = clamp(float(profile.get("beam_visual_length_m", profile.get("beam_range", light.spot_range if light != null else 75.0))), 1.0, 150.0)
	var measured_radius: float = max(float(light.get_meta("peraviz_lens_radius", 0.0)), 0.0) if light != null else 0.0
	var near_radius: float = max(float(diagnostics.get("render_near_radius_m", measured_radius)), 0.0)
	if near_radius <= 0.0:
		near_radius = max(float(profile.get("render_near_radius_m", profile.get("official_beam_radius_m", 0.03))), 0.001)
	return {
		"beam_angle": beam_angle,
		"beam_type_explicit": bool(profile.get("beam_type_explicit", false)),
		"beam_angle_explicit": bool(profile.get("beam_angle_explicit", false)),
		"field_angle_explicit": bool(profile.get("field_angle_explicit", false)),
		"profile_beam_angle": float(profile.get("beam_angle", beam_angle)),
		"field_angle": float(profile.get("field_angle", 0.0)),
		"beam_visual_length_m": beam_range,
		"beam_range": beam_range,
		"beam_color": beam_color,
		"lens_radius": near_radius,
		"render_near_radius_m": near_radius,
		"official_beam_radius_m": float(profile.get("official_beam_radius_m", diagnostics.get("official_beam_radius_m", 0.0))),
		"measured_model_aperture_radius_m": float(diagnostics.get("measured_model_aperture_radius_m", measured_radius)),
		"render_near_radius_source": str(diagnostics.get("render_near_radius_source", "measured_model_lens" if measured_radius > 0.0 else "official_beam_radius_no_model")),
		"radius_mismatch_ratio": float(diagnostics.get("radius_mismatch_ratio", 1.0)),
		"beam_type": str(profile.get("beam_type", "Wash")),
		"rectangle_ratio": float(profile.get("rectangle_ratio", 1.7777)),
		"normalized_dimmer": dimmer_norm,
		"scaled_intensity": scaled_beam_intensity,
		"beam_intensity": scaled_beam_intensity,
		"intensity_max": 50.0,
	}

func apply_wheel_optical_state(loader: Node, fixture_uuid: String, beam_target_id: int, wheel_renderer_id: int, mode: int, slot_a: int, slot_b: int, changed_mask: int, revision_flags: int, normalized_phase: float, split_fraction: float, boundary_angle_degrees: float, aggregate_srgb: Color, aggregate_gain: float, edge_softness: float) -> Dictionary:
	if beam_target_id <= 0 or not loader.has_method("_has_native_beam_output_record") or not loader._has_native_beam_output_record(beam_target_id):
		return {"applied": false, "wheel_state_applied": false, "target_resolved": false, "failed": 1, "failure_reason": "beam target not registered", "beam_target_id": beam_target_id}
	if _performance_trace_enabled:
		_visual_apply_counters["fixtures_applied"] += 1
	var key: String = _fixture_state_key(fixture_uuid) + ":wheel:" + str(beam_target_id) + ":" + str(wheel_renderer_id)
	var previous: Dictionary = _diagnostic_info_keys.get(key, {})
	var metadata_changed: bool = previous.get("mode", -1) != mode or previous.get("slot_a", -1) != slot_a or previous.get("slot_b", -1) != slot_b or previous.get("revision_flags", -1) != revision_flags or not is_equal_approx(float(previous.get("normalized_phase", -1.0)), normalized_phase) or not is_equal_approx(float(previous.get("split_fraction", -1.0)), split_fraction)
	_diagnostic_info_keys[key] = {"mode": mode, "slot_a": slot_a, "slot_b": slot_b, "changed_mask": changed_mask, "revision_flags": revision_flags, "normalized_phase": normalized_phase, "split_fraction": split_fraction, "boundary_angle_degrees": boundary_angle_degrees, "aggregate_srgb": aggregate_srgb, "aggregate_gain": aggregate_gain, "edge_softness": edge_softness, "coverage_model": "PeravizIndexedWheelAggregateFallback", "mutations": 0, "uniform_color_authority": "EmitterColor"}
	return {"applied": true, "wheel_state_applied": metadata_changed, "unchanged": not metadata_changed, "target_resolved": true, "lights_mutated": 0, "beams_mutated": 0, "materials_mutated": 0, "topology_rebuilds": 0, "failed": 0, "failure_reason": ""}

func apply_wheel_motion_state(_loader: Node, fixture_uuid: String, beam_target_id: int, wheel_renderer_id: int, motion_mode: int, changed_mask: int, revision: int, authoritative_phase: float, angular_velocity_degrees_per_second: float, reference_seconds: float, random_frequency_hz: float) -> Dictionary:
	if _performance_trace_enabled:
		_visual_apply_counters["fixtures_applied"] += 1
	var key: String = _fixture_state_key(fixture_uuid) + ":wheel_motion:" + str(beam_target_id) + ":" + str(wheel_renderer_id)
	_diagnostic_info_keys[key] = {"motion_mode": motion_mode, "changed_mask": changed_mask, "revision": revision, "authoritative_phase": authoritative_phase, "angular_velocity_degrees_per_second": angular_velocity_degrees_per_second, "reference_seconds": reference_seconds, "random_frequency_hz": random_frequency_hz}
	return {"applied": true, "wheel_motion_applied": true, "topology_rebuilds": 0}

func apply_gobo_selection(loader: Node, _fixture_uuid: String, beam_target_id: int, wheel_id: int, wheel_instance_index: int, slot_index: int, asset_id: int, selection_mode: int, _changed_mask: int, _revision: int) -> Dictionary:
	if not loader.has_method("_apply_native_gobo_selection"):
		return {"applied": false, "failure_reason": "native gobo registry unavailable"}
	return loader._apply_native_gobo_selection(beam_target_id, wheel_id, wheel_instance_index, slot_index, asset_id, selection_mode)

func apply_gobo_rotation_state(loader: Node, _fixture_uuid: String, beam_target_id: int, wheel_id: int, wheel_instance_index: int, rotation_mode: int, _changed_mask: int, revision: int, phase_degrees: float, angular_velocity_dps: float, reference_seconds: float, native_now_seconds: float) -> Dictionary:
	if not loader.has_method("_apply_native_gobo_rotation_state"):
		return {"applied": false, "failure_reason": "native gobo registry unavailable"}
	return loader._apply_native_gobo_rotation_state(beam_target_id, wheel_id, wheel_instance_index, rotation_mode, revision, phase_degrees, angular_velocity_dps, reference_seconds, native_now_seconds)

func apply_temporal_output(_loader: Node, fixture_uuid: String, strobe_norm: float, output_norm: float) -> void:
	var key: String = _fixture_state_key(fixture_uuid)
	if _performance_trace_enabled:
		_visual_apply_counters["fixtures_applied"] += 1
	_diagnostic_info_keys[key + ":temporal_state"] = {"strobe_norm": strobe_norm, "output_norm": output_norm}

func _output_id_from_record(output_record: Dictionary, fallback_target_id: int) -> int:
	return int(output_record.get("beam_render_target_id", fallback_target_id))


func _wheel_visual_beam_gain(physical_gain: float) -> float:
	const CLOSED_EPSILON := 0.000001
	if physical_gain <= CLOSED_EPSILON:
		return 0.0
	var clamped_gain: float = clamp(physical_gain, 0.0, 1.0)
	var perceptual_gain: float = pow(clamped_gain, 1.0 / 2.2)
	return lerp(1.0, perceptual_gain, 0.75)

func _apply_beam_output_record(loader: Node, fixture_uuid: String, output_record: Dictionary, changed_mask: int, state: Dictionary) -> Dictionary:
	var output_id: int = _output_id_from_record(output_record, int(output_record.get("target_id", 0)))
	var dimmer_norm: float = float(state.get("dimmer", 0.0))
	var beam_color: Color = state.get("beam_color", Color.WHITE)
	var color_gain: float = max(float(state.get("color_gain", 1.0)), 0.0)
	var photometric: Dictionary = output_record.get("beam_optical_profile", {})
	if photometric.is_empty():
		var records: Array = output_record.get("emitter_records", [])
		if not records.is_empty() and records[0] is Dictionary:
			photometric = records[0]
	var visual_beam_gain: float = _wheel_visual_beam_gain(color_gain)
	var final_beam_energy: float = float(state.get("beam_energy", 0.0)) * color_gain
	var final_spot_energy: float = float(state.get("spot_energy", 0.0)) * color_gain
	var final_beam_intensity: float = float(state.get("beam_intensity", 0.0)) * visual_beam_gain
	var final_material_energy: float = float(state.get("material_energy", 0.0)) * color_gain
	var previous: Dictionary = _committed_output_states.get(output_id, {})
	var intensity_changed: bool = (changed_mask & VISUAL_CHANGE_DIMMER) != 0 and (not is_equal_approx(float(previous.get("dimmer", -1.0)), dimmer_norm) or not is_equal_approx(float(previous.get("beam_intensity", -1.0)), final_beam_intensity))
	var color_changed: bool = (changed_mask & VISUAL_CHANGE_COLOR) != 0 and (previous.get("beam_color", Color(-1.0, -1.0, -1.0)) != beam_color or not is_equal_approx(float(previous.get("color_gain", -1.0)), color_gain))
	var material_changed: bool = intensity_changed or color_changed or (changed_mask & VISUAL_CHANGE_MATERIAL) != 0
	var force_apply: bool = previous.is_empty() or (changed_mask & VISUAL_CHANGE_BEAM_TOPOLOGY) != 0
	if not force_apply and not intensity_changed and not color_changed and not material_changed:
		return {"lights_mutated": 0, "beams_mutated": 0, "materials_mutated": 0, "signature_skipped": true}
	var effective_mask: int = changed_mask
	if force_apply:
		effective_mask |= VISUAL_CHANGE_DIMMER | VISUAL_CHANGE_COLOR | VISUAL_CHANGE_MATERIAL
	var materials_mutated: int = _apply_visual_frame_materials(loader, fixture_uuid, output_record.get("emitter_nodes", []), beam_color, final_material_energy, output_record.get("lens_material_targets", []), true) if material_changed or force_apply else 0
	var lights_mutated: int = 0
	var beams_mutated: int = 0
	var visible_light: bool = false
	var visible_beam: bool = false
	var last_visibility_diagnostics: Dictionary = {}
	for light in output_record.get("emitter_anchors", []):
		var spot: SpotLight3D = light as SpotLight3D
		if spot == null or not is_instance_valid(spot):
			continue
		if _performance_trace_enabled:
			_visual_apply_counters["beams_considered"] += 1
		if not _has_projected_beam(photometric):
			beams_mutated += _hide_beam_for_light(loader, spot)
			continue
		var light_result: Dictionary = _apply_intensity_to_light(loader, fixture_uuid, spot, photometric, effective_mask, dimmer_norm, final_beam_energy, final_spot_energy, _clamped_beam_intensity(final_beam_intensity), final_material_energy, beam_color)
		lights_mutated += int(light_result.get("lights_mutated", 0))
		beams_mutated += int(light_result.get("beams_mutated", 0))
		visible_light = visible_light or _should_enable_realtime_spotlight(loader, dimmer_norm > 0.0001)
		visible_beam = visible_beam or bool(light_result.get("beam_visible", false))
		last_visibility_diagnostics = light_result.get("visibility_diagnostics", {})
	_committed_output_states[output_id] = {"dimmer": dimmer_norm, "beam_intensity": final_beam_intensity, "beam_color": beam_color, "color_gain": color_gain, "material_energy": final_material_energy}
	if _performance_trace_enabled:
		last_visibility_diagnostics["physical_color_gain"] = color_gain
		last_visibility_diagnostics["visual_beam_gain"] = visual_beam_gain
	return {"lights_mutated": lights_mutated, "beams_mutated": beams_mutated, "materials_mutated": materials_mutated, "visible_light": visible_light, "visible_beam": visible_beam, "visibility_diagnostics": last_visibility_diagnostics}

func _apply_intensity_to_light(loader: Node, fixture_uuid: String, light: SpotLight3D, photometric: Dictionary, changed_mask: int, dimmer_norm: float, beam_energy: float, spot_energy: float, beam_intensity: float, material_energy: float, beam_color: Color) -> Dictionary:
	if not _has_projected_beam(photometric):
		var hidden_mutations: int = _hide_beam_for_light(loader, light)
		return {"lights_mutated": 0, "beams_mutated": hidden_mutations, "beam_visible": false, "visibility_diagnostics": {"emission_only": true}}
	var projected_scale: float = max(float(photometric.get("projected_lumen_scale", 1.0)), 0.0)
	var scaled_beam_energy: float = _scaled_projected_value(beam_energy, photometric)
	var scaled_spot_energy: float = _scaled_projected_value(spot_energy, photometric)
	var scaled_beam_intensity: float = _clamped_beam_intensity(_scaled_projected_value(beam_intensity, photometric))
	var visible: bool = dimmer_norm > 0.0001 and projected_scale > 0.0 and beam_intensity > 0.000001
	var beam_half_angle: float = _fixture_beam_half_angle(fixture_uuid)
	var beam_angle: float = _fixture_beam_angle(fixture_uuid)
	var light_energy: float = scaled_spot_energy if scaled_spot_energy > 0.0 else scaled_beam_energy
	_update_desired_light_state(light, light_energy, beam_half_angle, beam_color, visible and light_energy > 0.0)
	var light_writes: int = _apply_desired_light_state(loader, light)
	var beam_mutation_count: int = 0
	if not _beams_enabled():
		beam_mutation_count += _hide_beam_for_light(loader, light)
	elif not light.has_meta("peraviz_beam_last_params"):
		beam_mutation_count += _apply_visual_frame_initial_light_state(loader, light, photometric, dimmer_norm, beam_color, scaled_beam_energy, scaled_spot_energy, beam_half_angle, beam_angle, scaled_beam_intensity, material_energy)
	else:
		beam_mutation_count += _apply_visual_frame_beam(loader, light, changed_mask, visible, dimmer_norm, beam_angle, beam_color, scaled_beam_intensity)
	var lights_mutated: int = light_writes
	var beam: MeshInstance3D = loader._get_beam_resource_for_light(light) if loader.has_method("_get_beam_resource_for_light") else null
	var beam_visible: bool = beam != null and is_instance_valid(beam) and beam.visible
	var beams_mutated: int = beam_mutation_count
	var beam_params: Dictionary = light.get_meta("peraviz_beam_last_params", {}) if light.has_meta("peraviz_beam_last_params") else {}
	var threshold: float = float(beam_params.get("intensity_visibility_threshold", 0.015))
	var light_id: int = light.get_instance_id()
	if beam_visible:
		_visible_beam_ids[light_id] = true
	else:
		_visible_beam_ids.erase(light_id)
	if bool(_light_desired_for(light).get("applied_realtime_visible", false)):
		_visible_light_ids[light_id] = true
	else:
		_visible_light_ids.erase(light_id)
	if _performance_trace_enabled:
		_visual_apply_counters["beam_visible_count"] = _visible_beam_ids.size()
		_visual_apply_counters["spotlight_visible_count"] = _visible_light_ids.size()
	return {"lights_mutated": lights_mutated, "beams_mutated": beams_mutated, "beam_visible": beam_visible, "visibility_diagnostics": {"base_beam_intensity": beam_intensity, "projected_lumen_scale": projected_scale, "scaled_beam_intensity": scaled_beam_intensity, "visibility_threshold": threshold, "final_visible": beam_visible}}

func _has_projected_beam(profile: Dictionary) -> bool:
	if profile.has("has_projected_beam"):
		return bool(profile.get("has_projected_beam", false))
	var beam_type: String = str(profile.get("beam_type", "Wash")).to_lower()
	return beam_type != "none" and beam_type != "glow"

func _light_desired_for(light: SpotLight3D) -> Dictionary:
	if _dense_adapter != null:
		var dense_state: Dictionary = _dense_adapter.light_state(light)
		if not dense_state.is_empty():
			return dense_state
	var key: int = light.get_instance_id()
	if not _light_desired_state.has(key):
		_light_desired_state[key] = {"energy": light.light_energy, "angle": light.spot_angle, "color": light.light_color, "visible": false}
	return _light_desired_state[key]

func _update_desired_light_state(light: SpotLight3D, energy: float, angle: float, color: Color, visible: bool) -> void:
	var state: Dictionary = _light_desired_for(light)
	state["energy"] = energy
	state["angle"] = angle
	state["color"] = color
	state["visible"] = visible
	light.set_meta("peraviz_physical_output_visible", visible)

func _apply_desired_light_state(loader: Node, light: SpotLight3D) -> int:
	if _dense_adapter != null:
		var dense_writes: int = _dense_adapter.apply_light_state(light)
		if dense_writes >= 0: return dense_writes
	var state: Dictionary = _light_desired_for(light)
	var requested_visible: bool = bool(state.get("visible", false))
	var enabled: bool = (_should_enable_realtime_spotlight(loader, requested_visible) or _requires_realtime_spotlight(loader, light, requested_visible)) and _render_diagnostic_mode == RenderDiagnosticPolicyScript.FULL
	var settings: Dictionary = loader.get("_visual_settings") if loader != null and loader.get("_visual_settings") is Dictionary else {}
	enabled = enabled and float(settings.get("footprint_multiplier", 1.0)) > 0.0
	var writes: int = 0
	var property_writes: int = 0
	if not enabled and float(settings.get("footprint_multiplier", 1.0)) <= 0.0 and light.light_energy != 0.0:
		light.light_energy = 0.0
		writes += 1
		property_writes += 1
	if enabled:
		if not is_equal_approx(light.light_energy, float(state.get("energy", 0.0))):
			light.light_energy = float(state.get("energy", 0.0))
			writes += 1
			property_writes += 1
		if not is_equal_approx(light.spot_angle, float(state.get("angle", 0.0))):
			light.spot_angle = float(state.get("angle", 0.0))
			writes += 1
			property_writes += 1
		if light.light_color != state.get("color", Color.WHITE):
			light.light_color = state.get("color", Color.WHITE)
			writes += 1
			property_writes += 1
	var visibility_writes: int = _apply_canonical_light_visibility(loader, light, true, enabled)
	writes += visibility_writes
	if _performance_trace_enabled:
		_visual_apply_counters["light_properties_written"] += property_writes
		_visual_apply_counters["light_rids_updated"] += writes
	return writes

func _hide_beam_for_light(loader: Node, light: SpotLight3D) -> int:
	var beam: MeshInstance3D = loader._get_beam_resource_for_light(light) if loader.has_method("_get_beam_resource_for_light") else null
	return _set_beam_visible(beam, false)

func _set_beam_visible(beam: MeshInstance3D, visible: bool) -> int:
	if beam == null or not is_instance_valid(beam) or beam.visible == visible:
		return 0
	beam.visible = visible
	if not visible:
		beam.remove_meta("peraviz_intensity_signature")
	if _performance_trace_enabled:
		_visual_apply_counters["beam_visibility_transitions"] += 1
	return 1

func _set_beam_dynamic_parameters(beam: MeshInstance3D, color: Color, intensity: float) -> int:
	var signature: Array = beam.get_meta("peraviz_dynamic_signature", [])
	var next_signature: Array = [color, intensity]
	if signature == next_signature:
		return 0
	beam.set_meta("peraviz_dynamic_signature", next_signature)
	beam.set_instance_shader_parameter("beam_color", color)
	beam.set_instance_shader_parameter("base_color", Color(color.r, color.g, color.b, color.a))
	beam.set_instance_shader_parameter("beam_intensity", intensity)
	if _performance_trace_enabled:
		_visual_apply_counters["beam_shader_parameters_written"] += 3
	return 3

func _any_beam_instance_visible(beam_instances: Array) -> bool:
	for beam in beam_instances:
		var mesh: MeshInstance3D = beam as MeshInstance3D
		if mesh != null and is_instance_valid(mesh) and mesh.visible:
			return true
	return false

func _target_state(target_id: int, fixture_uuid: String) -> Dictionary:
	if not _target_states.has(target_id):
		_target_states[target_id] = {
			"beam_render_target_id": target_id,
			"fixture_uuid": fixture_uuid,
			"dimmer": 0.0,
			"beam_energy": 0.0,
			"spot_energy": 0.0,
			"beam_intensity": 0.0,
			"material_energy": 0.0,
			"beam_color": Color.WHITE,
			"color_gain": 1.0,
		}
	return _target_states[target_id]

func _set_target_intensity_state(target_id: int, fixture_uuid: String, dimmer_norm: float, beam_energy: float, spot_energy: float, beam_intensity: float, material_energy: float) -> void:
	var state: Dictionary = _target_state(target_id, fixture_uuid)
	state["dimmer"] = dimmer_norm
	state["beam_energy"] = beam_energy
	state["spot_energy"] = spot_energy
	state["beam_intensity"] = beam_intensity
	state["material_energy"] = material_energy

func _set_target_color_state(target_id: int, fixture_uuid: String, beam_color: Color, color_gain: float) -> void:
	var state: Dictionary = _target_state(target_id, fixture_uuid)
	state["beam_color"] = beam_color
	state["color_gain"] = max(color_gain, 0.0)

func _target_render_color(target_id: int, fixture_uuid: String) -> Color:
	return _target_state(target_id, fixture_uuid).get("beam_color", Color.WHITE)

func _target_color_gain(target_id: int, fixture_uuid: String) -> float:
	return float(_target_state(target_id, fixture_uuid).get("color_gain", 1.0))

func _target_dimmer(target_id: int, fixture_uuid: String) -> float:
	return float(_target_state(target_id, fixture_uuid).get("dimmer", 0.0))

func _fixture_state_key(fixture_uuid: String) -> String:
	return "section_state:" + fixture_uuid

func _fixture_state(fixture_uuid: String) -> Dictionary:
	var key: String = _fixture_state_key(fixture_uuid)
	if not _diagnostic_info_keys.has(key):
		# The retired fixed row no longer supplies fixture-wide lighting/gobo state.
		_diagnostic_info_keys[key] = {"beam_half_angle":12.5,"beam_angle":25.0}
	return _diagnostic_info_keys[key]

func _set_fixture_beam_angles(fixture_uuid: String, beam_half_angle: float, beam_angle: float) -> void:
	var state: Dictionary = _fixture_state(fixture_uuid)
	state["beam_half_angle"] = beam_half_angle
	state["beam_angle"] = beam_angle

func _fixture_beam_half_angle(fixture_uuid: String) -> float:
	return float(_fixture_state(fixture_uuid).get("beam_half_angle", 12.5))

func _fixture_beam_angle(fixture_uuid: String) -> float:
	return float(_fixture_state(fixture_uuid).get("beam_angle", 25.0))

func _beam_is_visible(light: SpotLight3D, fallback_intensity: float) -> bool:
	var beam_params: Dictionary = light.get_meta("peraviz_beam_last_params", {}) if light.has_meta("peraviz_beam_last_params") else {}
	var threshold: float = float(beam_params.get("intensity_visibility_threshold", 0.015))
	var scaled_intensity: float = clamp(float(beam_params.get("scaled_intensity", fallback_intensity)), 0.0, max(float(beam_params.get("intensity_max", 100.0)), 0.01))
	return scaled_intensity > threshold

func _scaled_projected_value(value: float, photometric: Dictionary) -> float:
	return value * max(float(photometric.get("projected_lumen_scale", 1.0)), 0.0)

func _clamped_beam_intensity(value: float) -> float:
	return clamp(value, 0.0, 50.0)

func _material_emission_scale(material_entry: Variant) -> float:
	if material_entry is Dictionary:
		var profile_value: Variant = (material_entry as Dictionary).get("beam_optical_profile", {})
		if profile_value is Dictionary and not (profile_value as Dictionary).is_empty():
			return max(float((profile_value as Dictionary).get("emission_lumen_scale", 1.0)), 0.0)
	return 1.0

func _apply_visual_frame_materials(loader: Node, fixture_uuid: String, geometry_nodes: Array, beam_color: Color, material_energy: float, cached_materials: Array = [], use_cached_materials: bool = false) -> int:
	var material_phase_start: int = Time.get_ticks_usec()
	var emissive_materials: Array = cached_materials if use_cached_materials else _prewarm_emissive_materials(loader, fixture_uuid, geometry_nodes)
	var materials_mutated: int = 0
	for material_entry in emissive_materials:
		var material: BaseMaterial3D = null
		if material_entry is Dictionary:
			var cached_material: Variant = (material_entry as Dictionary).get("material", null)
			if cached_material is BaseMaterial3D:
				material = cached_material
		elif material_entry is BaseMaterial3D:
			material = material_entry
		if material is BaseMaterial3D:
			var material_rid: RID = _get_cached_material_rid(material)
			if material_rid.is_valid():
				var emission_scale: float = _material_emission_scale(material_entry)
				materials_mutated += _apply_cached_material_state(material_rid, beam_color, material_energy * emission_scale)
	_track_phase("material_apply", material_phase_start)
	return materials_mutated

func _apply_visual_frame_initial_light_state(loader: Node, light: SpotLight3D, photometric: Dictionary, dimmer_norm: float, beam_color: Color, beam_energy: float, spot_energy: float, beam_half_angle: float, beam_angle: float, beam_intensity: float, material_energy: float) -> int:
	if _performance_trace_enabled:
		_visual_apply_counters["beam_full_state_applies"] += 1
		_visual_apply_counters["beam_full_state_reason_initialization"] += 1
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
	return 1 + _apply_canonical_light_visibility(loader, light, visible, _should_enable_realtime_spotlight(loader, visible))

func _apply_visual_frame_beam(loader: Node, light: SpotLight3D, visual_mask: int, visible: bool, dimmer_norm: float, beam_angle: float, beam_color: Color, beam_intensity: float) -> int:
	if not loader.has_method("_update_beam_for_light"):
		return 0
	var topology_masked: bool = (visual_mask & VISUAL_CHANGE_BEAM_TOPOLOGY) != 0 and (visual_mask & VISUAL_CHANGE_ZOOM) == 0
	var needs_initialization: bool = not light.has_meta("peraviz_beam_last_params")
	var needs_topology: bool = topology_masked or needs_initialization
	if needs_topology:
		if _performance_trace_enabled:
			_visual_apply_counters["beam_full_state_reason_initialization" if needs_initialization else "beam_full_state_reason_topology_mask"] += 1
		var beam_phase_start: int = Time.get_ticks_usec() if _performance_trace_enabled else 0
		var topology_mutations: int = _apply_visual_frame_beam_topology(loader, light, visible, dimmer_norm, beam_angle, beam_color, beam_intensity)
		_track_phase("beam_update", beam_phase_start)
		return topology_mutations
	var mutations: int = 0
	if loader.has_method("_update_beam_intensity_for_light"):
		var beam_phase_start: int = Time.get_ticks_usec() if _performance_trace_enabled else 0
		var tracked_beam: MeshInstance3D = loader._get_beam_resource_for_light(light) if loader.has_method("_get_beam_resource_for_light") else null
		var was_visible: bool = tracked_beam != null and is_instance_valid(tracked_beam) and tracked_beam.visible
		_apply_canonical_light_visibility(loader, light, visible, _should_enable_realtime_spotlight(loader, visible))
		if (visual_mask & VISUAL_CHANGE_ZOOM) != 0 and light.has_meta("peraviz_beam_last_params"):
			var optics_params: Dictionary = light.get_meta("peraviz_beam_last_params", {})
			optics_params["beam_angle"] = beam_angle
			light.set_meta("peraviz_beam_last_params", optics_params)
			if loader.has_method("_apply_beam_optics_for_light"):
				loader._apply_beam_optics_for_light(light, optics_params)
		var dynamic_result: int = loader._update_beam_intensity_for_light(light, dimmer_norm, beam_color, beam_intensity)
		if dynamic_result == BeamRendererBase.INTENSITY_CHANGED:
			mutations += 1
			if _performance_trace_enabled:
				_visual_apply_counters["beam_dynamic_changed"] += 1
				_visual_apply_counters["beam_intensity_updates"] += 1
				_visual_apply_counters["beam_shader_parameters_written"] += int(loader._get_last_beam_parameter_write_count()) if loader.has_method("_get_last_beam_parameter_write_count") else 0
		elif dynamic_result == BeamRendererBase.INTENSITY_UNCHANGED:
			if _performance_trace_enabled:
				_visual_apply_counters["beam_dynamic_unchanged"] += 1
		elif dynamic_result == BeamRendererBase.INTENSITY_UNRESOLVED:
			if _performance_trace_enabled:
				_visual_apply_counters["beam_dynamic_unresolved"] += 1
			if visible:
				if _performance_trace_enabled:
					_visual_apply_counters["beam_full_state_reason_initialization"] += 1
				mutations += _apply_visual_frame_beam_topology(loader, light, visible, dimmer_norm, beam_angle, beam_color, beam_intensity)
		if tracked_beam != null and is_instance_valid(tracked_beam) and tracked_beam.visible != was_visible:
			mutations += 1
			if _performance_trace_enabled:
				_visual_apply_counters["beam_visibility_transitions"] += 1
		_track_phase("beam_update", beam_phase_start)
	return mutations

func _apply_visual_frame_beam_topology(loader: Node, light: SpotLight3D, visible: bool, dimmer_norm: float, beam_angle: float, beam_color: Color, beam_intensity: float) -> int:
	if _performance_trace_enabled:
		_visual_apply_counters["beam_full_state_applies"] += 1
	loader._ensure_beam_runtime_for_light(light)
	var beam_params: Dictionary = light.get_meta("peraviz_beam_last_params", {}).duplicate(false) if light.has_meta("peraviz_beam_last_params") else {}
	if beam_params.is_empty():
		var diagnostics: Dictionary = light.get_meta("peraviz_beam_radius_diagnostics", {}) if light.has_meta("peraviz_beam_radius_diagnostics") else {}
		var lens_radius: float = max(float(diagnostics.get("render_near_radius_m", light.get_meta("peraviz_lens_radius", 0.03))), 0.005)
		var beam_defaults: Dictionary = loader.get("_cached_beam_defaults") if loader.get("_cached_beam_defaults") is Dictionary else {}
		beam_params = loader._build_cached_beam_params(light, beam_angle, beam_color, dimmer_norm, beam_intensity, lens_radius, beam_defaults)
	beam_params["beam_angle"] = beam_angle
	beam_params["beam_color"] = beam_color
	beam_params["normalized_dimmer"] = dimmer_norm
	beam_params["scaled_intensity"] = beam_intensity
	beam_params["beam_intensity"] = beam_intensity
	beam_params["intensity_max"] = float(loader.get("BEAM_INTENSITY_MAX")) if loader.get("BEAM_INTENSITY_MAX") != null else 50.0
	light.set_meta("peraviz_beam_last_params", beam_params)
	loader._update_beam_for_light(light, beam_params)
	_apply_canonical_light_visibility(loader, light, visible, _should_enable_realtime_spotlight(loader, visible))
	if _performance_trace_enabled:
		_visual_apply_counters["beam_topology_rebuilds"] += 1
	return 1

# Keeps the light node available as a beam parent while independently gating the real SpotLight RID.
func _apply_canonical_light_visibility(loader: Node, light: SpotLight3D, visible: bool, real_spot_visible: bool) -> int:
	if _dense_adapter != null:
		var dense_writes: int = _dense_adapter.apply_light_state(light)
		if dense_writes >= 0: return dense_writes
	if light == null or not is_instance_valid(light):
		return 0
	var physical_output_visible: bool = bool(_light_desired_for(light).get("visible", false))
	real_spot_visible = physical_output_visible and (real_spot_visible or _requires_realtime_spotlight(loader, light, physical_output_visible))
	var settings: Dictionary = loader.get("_visual_settings") if loader != null and loader.get("_visual_settings") is Dictionary else {}
	real_spot_visible = real_spot_visible and _render_diagnostic_mode == RenderDiagnosticPolicyScript.FULL and float(settings.get("footprint_multiplier", 1.0)) > 0.0
	var writes: int = 0
	if light.visible != visible:
		light.visible = visible
		writes += 1
	var last_state: Dictionary = _light_desired_for(light)
	last_state["owns_realtime_surface_light"] = real_spot_visible
	var previous_realtime_visible: bool = bool(last_state.get("applied_realtime_visible", not real_spot_visible))
	last_state["applied_realtime_visible"] = real_spot_visible
	var light_id: int = light.get_instance_id()
	if real_spot_visible:
		_visible_light_ids[light_id] = true
	else:
		_visible_light_ids.erase(light_id)
	if _performance_trace_enabled:
		_visual_apply_counters["spotlight_visible_count"] = _visible_light_ids.size()
	var instance_rid: RID = light.get_instance()
	if instance_rid.is_valid() and previous_realtime_visible != real_spot_visible:
		RenderingServer.instance_set_visible(instance_rid, real_spot_visible)
		if _performance_trace_enabled:
			_visual_apply_counters["rendering_server_calls"] += 1
			_visual_apply_counters["light_visibility_calls"] += 1
		writes += 1
	if _performance_trace_enabled:
		_visual_apply_counters["spotlight_visible_count"] = _visible_light_ids.size()
		var clustered_limit: int = int(_visual_apply_counters.get("clustered_element_limit", 512))
		_warn_visual_once("clustered_element_budget", "Shared Haze requested more realtime SpotLights than the Forward+ clustered-element limit (%d). This mode is diagnostic at this scale." % clustered_limit, _visible_light_ids.size() > clustered_limit)
		_visual_apply_counters["beam_presentation"] = int((settings as Dictionary).get("beam_presentation", 1)) if settings is Dictionary else 1
	return writes

func _apply_cached_material_state(material_rid: RID, color: Color, energy: float) -> int:
	var key: int = material_rid.get_id()
	var previous: Dictionary = _material_state_by_rid.get(key, {})
	var writes: int = 0
	if previous.get("color", Color(-1.0, -1.0, -1.0, -1.0)) != color:
		RenderingServer.material_set_param(material_rid, "emission", color)
		previous["color"] = color
		writes += 1
	if not is_equal_approx(float(previous.get("energy", -1.0)), energy):
		RenderingServer.material_set_param(material_rid, "emission_energy_multiplier", energy)
		previous["energy"] = energy
		writes += 1
	if writes > 0:
		_material_state_by_rid[key] = previous
		if _performance_trace_enabled:
			_visual_apply_counters["materials_updated"] += writes
			_visual_apply_counters["material_parameters_written"] += writes
			_visual_apply_counters["rendering_server_calls"] += writes
	return writes

func _should_enable_realtime_spotlight(loader: Node, visible: bool) -> bool:
	if not visible:
		return false
	var settings: Variant = loader.get("_visual_settings")
	if settings is Dictionary:
		return bool((settings as Dictionary).get("enable_realtime_spotlights", false))
	return false

func _requires_realtime_spotlight(loader: Node, light: SpotLight3D, visible: bool) -> bool:
	if not visible or light == null or not is_instance_valid(light):
		return false
	var has_profile: bool = false
	if light.has_meta(&"peraviz_optical_projection_state"):
		var projection: RefCounted = light.get_meta(&"peraviz_optical_projection_state")
		has_profile = projection.has_projected_surface_profile
	var settings: Variant = loader.get("_visual_settings") if loader != null else null
	return SurfacePolicy.owns_realtime_light(false, int(settings.get("beam_presentation", 1)) if settings is Dictionary else 1, light.light_projector != null, _diagnostic_open_surface_lights, has_profile, SurfacePolicy.custom_light(light))

# Emits a bounded one-time warning for compatibility presentation failures.
func _warn_visual_once(key: String, message: String, condition: bool = true) -> void:
	if not condition or _diagnostic_warning_keys.has(key):
		return
	_diagnostic_warning_keys[key] = true
	push_warning(message)

func get_visual_apply_counters() -> Dictionary:
	return _visual_apply_counters.duplicate(false)

func get_active_physical_emitter_ids() -> Dictionary:
	if _dense_adapter != null:
		return _dense_adapter.active_ids()
	var result: Dictionary = {}
	for light_id in _light_desired_state:
		if bool((_light_desired_state[light_id] as Dictionary).get("visible", false)):
			result[light_id] = true
	return result

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
	for material_entry in emissive_materials:
		var material: BaseMaterial3D = material_entry as BaseMaterial3D
		if material_entry is Dictionary:
			material = (material_entry as Dictionary).get("material", null) as BaseMaterial3D
		if material is BaseMaterial3D:
			var material_rid: RID = _get_cached_material_rid(material)
			if material_rid.is_valid():
				_apply_cached_material_state(material_rid, beam_color, energy_multiplier)

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

func get_phase_metrics() -> Dictionary:
	return _phase_metrics.duplicate(true)

func _track_phase(phase: String, phase_start_usec: int) -> void:
	if not _performance_trace_enabled:
		return
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
