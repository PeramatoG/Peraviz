extends SceneTree

const FixtureLightApplyServiceScript = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const LegacyConeBeamRendererScript = preload("res://scripts/beam_renderers/legacy_cone_beam_renderer.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

class CoalescingLoader:
	extends Node
	const BEAM_INTENSITY_MAX: float = 50.0
	var renderer = LegacyConeBeamRendererScript.new()
	var anchors: Array[SpotLight3D] = [SpotLight3D.new(), SpotLight3D.new(), SpotLight3D.new()]
	var outputs: Array = []
	var _cached_beam_defaults: Dictionary = {}
	var _visual_settings: Dictionary = {"enable_realtime_spotlights": true}

	func _ready() -> void:
		for anchor in anchors:
			add_child(anchor)
			renderer.ensure_beam(anchor)
		outputs = [
			_output(401, anchors[0], true),
			_output(402, anchors[1], true),
			_output(403, anchors[2], false),
		]

	func _output(output_id: int, anchor: SpotLight3D, projected: bool) -> Dictionary:
		return {
			"beam_render_target_id": output_id,
			"emitter_anchors": [anchor],
			"emitter_nodes": [],
			"lens_material_targets": [],
			"beam_optical_profile": {"beam_type": "Wash" if projected else "Glow", "has_projected_beam": projected, "projected_lumen_scale": 1.0 if projected else 0.0, "beam_angle": 25.0},
		}

	func _has_native_dimmer_target(target_id: int) -> bool:
		return target_id == 201

	func _get_native_dimmer_target_record(_target_id: int) -> Dictionary:
		return {"beam_output_records": outputs, "emitter_anchors": anchors}

	func _has_native_color_target(target_id: int) -> bool:
		return target_id == 301 or target_id == 302

	func _get_native_color_target_record(target_id: int) -> Dictionary:
		return {"beam_output_records": outputs if target_id == 301 else [outputs[1]], "emitter_anchors": anchors if target_id == 301 else [anchors[1]]}

	func _get_beam_resource_for_light(light: SpotLight3D) -> MeshInstance3D:
		return renderer.get_beam_resource(light)

	func _ensure_beam_runtime_for_light(light: SpotLight3D) -> void:
		renderer.ensure_beam(light)

	func _update_beam_for_light(light: SpotLight3D, params: Dictionary) -> void:
		light.set_meta("peraviz_beam_last_params", params)
		renderer.update_beam(light, params)

	func _update_beam_intensity_for_light(light: SpotLight3D, dimmer_norm: float, beam_color: Color, scaled_intensity_override: float = -1.0) -> int:
		var params: Dictionary = light.get_meta("peraviz_beam_last_params", {})
		params["normalized_dimmer"] = dimmer_norm
		params["scaled_intensity"] = scaled_intensity_override
		params["beam_intensity"] = scaled_intensity_override
		params["beam_color"] = beam_color
		params["intensity_max"] = BEAM_INTENSITY_MAX
		var result: int = renderer.update_beam_intensity(light, params)
		if result != BeamRendererBase.INTENSITY_UNRESOLVED:
			light.set_meta("peraviz_beam_last_params", params)
		return result

	func _get_last_beam_parameter_write_count() -> int:
		return renderer.get_last_parameter_write_count()

	func _apply_emitter_light_state(light: SpotLight3D, photometric: Dictionary, normalized_dimmer: float, controls: Dictionary = {}) -> void:
		var values: PackedFloat32Array = controls.get("render_ready_values", PackedFloat32Array())
		var color := Color(values[4], values[5], values[6]) if values.size() >= 9 else Color.WHITE
		var params := _build_cached_beam_params(light, float(photometric.get("beam_angle", 25.0)), color, normalized_dimmer, values[7] if values.size() >= 9 else 0.0, 0.03, {})
		renderer.update_beam(light, params)
		light.set_meta("peraviz_beam_last_params", params)

	func _build_cached_beam_params(_light: SpotLight3D, beam_angle: float, beam_color: Color, normalized_dimmer: float, scaled_intensity: float, lens_radius: float, _defaults: Dictionary) -> Dictionary:
		return {"beam_type": "Wash", "beam_angle": beam_angle, "beam_color": beam_color, "normalized_dimmer": normalized_dimmer, "scaled_intensity": scaled_intensity, "beam_intensity": scaled_intensity, "beam_range": 4.0, "lens_radius": lens_radius, "intensity_visibility_threshold": 0.015, "intensity_max": BEAM_INTENSITY_MAX}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var loader := CoalescingLoader.new()
	get_root().add_child(loader)
	await process_frame
	var service = FixtureLightApplyServiceScript.new()
	service.set_performance_trace_enabled(true)
	var before: Dictionary = service.get_visual_apply_counters()
	service.begin_visual_snapshot()
	var deferred_intensity: Dictionary = service.apply_emitter_intensity(loader, "fixture", 201, 1 << 1, 0.5, 10.0, 8.0, 10.0, 2.0)
	service.apply_emitter_color(loader, "fixture", 301, 1 << 2, Color(0.2, 0.4, 0.8), 1.0)
	var deferred_counters: Dictionary = service.get_visual_apply_counters()
	service.end_visual_snapshot()
	var after: Dictionary = service.get_visual_apply_counters()
	test.check(int(after.get("emitter_output_commit_candidates", 0)) - int(before.get("emitter_output_commit_candidates", 0)) == 6, "Intensity and color should nominate every shared physical output")
	test.check(int(after.get("emitter_output_commits", 0)) - int(before.get("emitter_output_commits", 0)) == 3, "Each shared physical output should commit once")
	test.check(int(after.get("emitter_output_commits_coalesced", 0)) - int(before.get("emitter_output_commits_coalesced", 0)) == 3, "The duplicate intensity/color commits should be coalesced")
	test.check(bool(deferred_intensity.get("commit_deferred", false)) and not bool(deferred_intensity.get("unchanged", true)), "Deferred semantic rows must not be classified as renderer no-ops")
	test.check(int(deferred_counters.get("emitter_output_commits", 0)) == int(before.get("emitter_output_commits", 0)), "Semantic rows should remain distinguishable from deferred renderer commits")
	test.check(int(after.get("emitter_output_commit_usec", 0)) >= int(before.get("emitter_output_commit_usec", 0)), "Deferred emitter commit time should be accumulated")
	for index in range(2):
		var params: Dictionary = loader.anchors[index].get_meta("peraviz_beam_last_params", {})
		test.check(params.get("beam_color", Color.BLACK) == Color(0.2, 0.4, 0.8) and is_equal_approx(float(params.get("beam_intensity", 0.0)), 10.0), "Coalesced output should receive final color and intensity")
	test.check(not loader.renderer.get_beam_resource(loader.anchors[2]).visible, "BeamType Glow should remain emission-only after a coalesced commit")

	service.begin_visual_snapshot()
	service.apply_emitter_intensity(loader, "fixture", 201, 1 << 1, 0.75, 15.0, 12.0, 15.0, 3.0)
	service.end_visual_snapshot()
	test.check(loader.anchors[0].get_meta("peraviz_beam_last_params", {}).get("beam_color", Color.BLACK) == Color(0.2, 0.4, 0.8), "Intensity-only snapshots should retain held color")
	service.begin_visual_snapshot()
	service.apply_emitter_color(loader, "fixture", 302, 1 << 2, Color(1.0, 0.1, 0.2), 1.0)
	service.end_visual_snapshot()
	test.check(is_equal_approx(float(loader.anchors[1].get_meta("peraviz_beam_last_params", {}).get("beam_intensity", 0.0)), 15.0), "Color-only snapshots should retain held intensity")
	test.check(loader.anchors[0].get_meta("peraviz_beam_last_params", {}).get("beam_color", Color.BLACK) == Color(0.2, 0.4, 0.8), "Independent output color should remain unchanged")
	test.check(loader.anchors[1].get_meta("peraviz_beam_last_params", {}).get("beam_color", Color.BLACK) == Color(1.0, 0.1, 0.2), "Independent output should remain addressable")

	for level in [0.0, 0.5, 0.0, 0.8]:
		service.begin_visual_snapshot()
		service.apply_emitter_intensity(loader, "fixture", 201, 1 << 1, level, level * 20.0, level * 16.0, level * 20.0, level * 4.0)
		service.end_visual_snapshot()
	test.check(loader.renderer.is_beam_dynamic_ready(loader.anchors[0]) and loader.renderer.get_beam_resource(loader.anchors[0]).visible, "Projected output should survive dark start and reactivate")
	test.check(loader.renderer.get_beam_resource(loader.anchors[1]).visible, "Master intensity should update every physical projected output")
	for anchor in loader.anchors:
		loader.renderer.cleanup_beam(anchor)
	loader.free()
	service = null
	await process_frame
	test.finish(self)
