extends SceneTree

const FixtureLightApplyServiceScript = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const LegacyConeBeamRendererScript = preload("res://scripts/beam_renderers/legacy_cone_beam_renderer.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

class PrismLoader:
	extends Node
	const BEAM_INTENSITY_MAX: float = 50.0
	const EMITTER_LIGHT_DIRECTION_FIX: Vector3 = Vector3.ZERO
	const DEFAULT_EMITTER_PHOTOMETRICS: Dictionary = {"luminous_flux": 10000.0, "beam_angle": 25.0, "field_angle": 25.0, "beam_radius": 0.05}
	var renderer = LegacyConeBeamRendererScript.new()
	var anchor := SpotLight3D.new()
	var lens := MeshInstance3D.new()
	var target_record: Dictionary = {}
	var ready_calls: int = 0
	var _cached_beam_defaults: Dictionary = {}
	var _visual_settings: Dictionary = {"beam_multiplier": 20.0, "spot_multiplier": 0.0, "enable_realtime_spotlights": true}

	func _ready() -> void:
		ready_calls += 1
		anchor.name = "PeravizEmitterLight"
		lens.name = "EmitterLens"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.1, 0.1, 0.02)
		lens.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.2, 0.2, 0.2, 1.0)
		lens.material_override = material
		add_child(lens)
		add_child(anchor)
		renderer.ensure_beam(anchor)
		var prism: MeshInstance3D = renderer.get_beam_resource(anchor)
		var lens_material := material.duplicate(true) as StandardMaterial3D
		lens_material.emission_enabled = true
		lens_material.emission = Color.WHITE
		lens_material.emission_energy_multiplier = 0.0
		lens.material_override = lens_material
		target_record = {
			"geometry_nodes": [lens],
			"emitter_nodes": [lens],
			"emitter_anchors": [anchor],
			"optional_spotlights": [anchor],
			"beam_instances": [prism],
			"lens_material_targets": [{"mesh": lens, "surface": 0, "material": lens_material}],
			"emitter_photometrics": [DEFAULT_EMITTER_PHOTOMETRICS],
		}

	func _has_native_dimmer_target(target_id: int) -> bool:
		return target_id == 201

	func _get_native_dimmer_target_record(target_id: int) -> Dictionary:
		return target_record if target_id == 201 else {}

	func _get_beam_resource_for_light(light: SpotLight3D) -> MeshInstance3D:
		return renderer.get_beam_resource(light)

	func _ensure_beam_runtime_for_light(light: SpotLight3D) -> void:
		renderer.ensure_beam(light)

	func _update_beam_for_light(light: SpotLight3D, params: Dictionary) -> void:
		light.set_meta("peraviz_beam_last_params", params)
		renderer.ensure_beam(light)
		renderer.update_beam(light, params)

	func _update_beam_intensity_for_light(light: SpotLight3D, dimmer_norm: float, beam_color: Color, scaled_intensity_override: float = -1.0) -> int:
		var params: Dictionary = light.get_meta("peraviz_beam_last_params", {}) if light.has_meta("peraviz_beam_last_params") else _build_cached_beam_params(light, 25.0, beam_color, dimmer_norm, scaled_intensity_override, 0.03, {})
		params["normalized_dimmer"] = dimmer_norm
		params["scaled_intensity"] = scaled_intensity_override if scaled_intensity_override >= 0.0 else dimmer_norm * 20.0
		params["beam_intensity"] = params["scaled_intensity"]
		params["intensity_max"] = BEAM_INTENSITY_MAX
		var result: int = renderer.update_beam_intensity(light, params)
		light.set_meta("peraviz_beam_last_params", params)
		return result

	func _apply_emitter_light_state(light: SpotLight3D, photometric: Dictionary, normalized_dimmer: float, controls: Dictionary = {}) -> void:
		var values: PackedFloat32Array = controls.get("render_ready_values", PackedFloat32Array())
		var beam_intensity: float = values[7] if values.size() >= 9 else normalized_dimmer * 20.0
		var params: Dictionary = _build_cached_beam_params(light, float(photometric.get("beam_angle", 25.0)), Color.WHITE, normalized_dimmer, beam_intensity, 0.03, {})
		params["intensity_max"] = BEAM_INTENSITY_MAX
		light.light_energy = values[1] if values.size() >= 2 else 0.0
		_update_beam_for_light(light, params)

	func _build_cached_beam_params(_light: SpotLight3D, beam_angle: float, beam_color: Color, normalized_dimmer: float, scaled_intensity: float, lens_radius: float, _beam_defaults: Dictionary) -> Dictionary:
		return {
			"beam_angle": beam_angle,
			"beam_color": beam_color,
			"normalized_dimmer": normalized_dimmer,
			"scaled_intensity": scaled_intensity,
			"beam_intensity": scaled_intensity,
			"beam_range": 4.0,
			"lens_radius": lens_radius,
			"gobo_projection_radius": 0.2,
			"intensity_visibility_threshold": 0.015,
			"intensity_max": BEAM_INTENSITY_MAX,
		}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var root := PrismLoader.new()
	get_root().add_child(root)
	await process_frame
	var service = FixtureLightApplyServiceScript.new()
	var prism: MeshInstance3D = root.renderer.get_beam_resource(root.anchor)
	test.check(root.ready_calls == 1, "PrismLoader setup should run exactly once through SceneTree readiness")
	test.check(prism != null, "Prism beam resource should be created during setup")
	test.check(not prism.visible, "Zero-initialized prism should remain hidden")
	var zero: Dictionary = service.apply_emitter_intensity(root, "fixture-a", 201, 2, 0.0, 0.0, 0.0, 0.0, 0.0)
	test.check(bool(zero.get("dimmer_applied", false)), "Zero dimmer should apply to the registered target")
	test.check(not prism.visible, "Zero dimmer should keep the prism hidden")
	var mid: Dictionary = service.apply_emitter_intensity(root, "fixture-a", 201, 2, 0.5, 10.0, 0.0, 10.0, 2.0)
	test.check(bool(mid.get("dimmer_applied", false)), "Mid dimmer should apply to the registered target")
	test.check(prism.visible, "Mid dimmer should make the prism visible")
	test.check(int(mid.get("materials_mutated", 0)) > 0, "Mid dimmer should update lens emission")
	var maxed: Dictionary = service.apply_emitter_intensity(root, "fixture-a", 201, 2, 1.0, 20.0, 0.0, 20.0, 4.0)
	test.check(bool(maxed.get("dimmer_applied", false)), "Full dimmer should apply to the registered target")
	test.check(prism.visible, "Full dimmer should keep the prism visible")
	test.check(int(maxed.get("materials_mutated", 0)) > 0, "Increasing dimmer should update the higher lens emission value")
	service.set_render_diagnostic_mode("no-beams")
	var beam_updates_before_no_beams: int = int(service.get_visual_apply_counters().get("beam_intensity_updates", 0))
	service.apply_emitter_intensity(root, "fixture-a", 201, 2, 1.0, 20.0, 0.0, 20.0, 4.0)
	test.check(not prism.visible, "No-beams diagnostic mode must hide the existing beam without destroying it")
	test.check(int(service.get_visual_apply_counters().get("beam_intensity_updates", 0)) == beam_updates_before_no_beams, "No-beams mode must suppress beam renderer updates")
	service.set_render_diagnostic_mode("full")
	service.apply_emitter_intensity(root, "fixture-a", 201, 2, 1.0, 20.0, 0.0, 20.0, 4.0)
	test.check(prism.visible, "Returning to full mode must rehydrate held beam state")
	root.target_record["emitter_records"] = [{"projected_lumen_scale": 0.5, "emission_lumen_scale": 0.5, "has_projected_beam": true}]
	var scaled: Dictionary = service.apply_emitter_intensity(root, "fixture-a", 201, 2, 1.0, 20.0, 10.0, 20.0, 4.0)
	test.check(bool(scaled.get("dimmer_applied", false)), "Scaled emitter dimmer should apply")
	test.check(is_equal_approx(root.anchor.light_energy, 5.0), "Emitter lumen scaling should scale spotlight energy")
	var params: Dictionary = root.anchor.get_meta("peraviz_beam_last_params", {})
	test.check(is_equal_approx(float(params.get("beam_intensity", -1.0)), 10.0), "Emitter lumen scaling should scale beam intensity")
	root._visual_settings["enable_realtime_spotlights"] = false
	var counters_before_disabled: Dictionary = service.get_visual_apply_counters()
	var disabled: Dictionary = service.apply_emitter_intensity(root, "fixture-a", 201, 2, 0.75, 15.0, 8.0, 15.0, 3.0)
	var counters_after_disabled: Dictionary = service.get_visual_apply_counters()
	test.check(int(counters_after_disabled.get("light_properties_written", 0)) - int(counters_before_disabled.get("light_properties_written", 0)) <= 2, "Disabling a realtime spotlight may only transition node/RID visibility")
	test.check(float(root.anchor.get_meta("peraviz_beam_last_params", {}).get("beam_intensity", -1.0)) > 0.0, "Disabled realtime spotlight must retain scaled beam intensity")
	var counters_before_disabled_repeat: Dictionary = service.get_visual_apply_counters()
	service.apply_emitter_intensity(root, "fixture-a", 201, 2, 0.5, 10.0, 6.0, 10.0, 2.0)
	var counters_after_disabled_repeat: Dictionary = service.get_visual_apply_counters()
	test.check(int(counters_after_disabled_repeat.get("light_properties_written", 0)) == int(counters_before_disabled_repeat.get("light_properties_written", 0)), "Disabled spotlight Dimmer changes must not write Light3D properties")
	root._visual_settings["enable_realtime_spotlights"] = true
	service.apply_emitter_intensity(root, "fixture-a", 201, 2, 0.75, 15.0, 8.0, 15.0, 3.0)
	test.check(is_equal_approx(root.anchor.light_energy, 4.0), "Re-enabling realtime spotlights must apply held scaled energy")
	var counters_before_repeat: Dictionary = service.get_visual_apply_counters()
	service.apply_emitter_intensity(root, "fixture-a", 201, 2, 0.75, 15.0, 8.0, 15.0, 3.0)
	var counters_after_repeat: Dictionary = service.get_visual_apply_counters()
	test.check(int(counters_after_repeat.get("light_properties_written", 0)) == int(counters_before_repeat.get("light_properties_written", 0)), "Repeated enabled spotlight state must not rewrite Light3D properties")
	test.check(int(counters_after_repeat.get("beam_topology_rebuilds", 0)) == int(counters_before_repeat.get("beam_topology_rebuilds", 0)), "Unchanged beam state must not fall back to topology work")
	test.check(int(counters_after_repeat.get("beam_shader_parameters_written", 0)) == int(counters_before_repeat.get("beam_shader_parameters_written", 0)), "Unchanged beam state must not rewrite shader parameters")
	root.target_record["emitter_records"] = [{"beam_type": "Glow", "has_projected_beam": false, "projected_lumen_scale": 0.0, "emission_lumen_scale": 0.5}]
	var beam_updates_before_glow: int = int(service.get_visual_apply_counters().get("beam_intensity_updates", 0))
	service.apply_emitter_intensity(root, "fixture-a", 201, 2, 1.0, 20.0, 10.0, 20.0, 4.0)
	test.check(not prism.visible, "BeamType Glow must keep emissive geometry without a projected beam")
	test.check(int(service.get_visual_apply_counters().get("beam_intensity_updates", 0)) == beam_updates_before_glow, "BeamType Glow must not perform beam shader work")
	var hidden: Dictionary = service.apply_emitter_intensity(root, "fixture-a", 201, 2, 0.0, 0.0, 0.0, 0.0, 0.0)
	test.check(bool(hidden.get("dimmer_applied", false)), "Final zero dimmer should apply")
	test.check(not prism.visible, "Returning to zero should hide the prism")
	root.renderer.cleanup_beam(root.anchor)
	await process_frame
	root.free()
	prism = null
	service = null
	await process_frame
	await process_frame
	test.finish(self)
