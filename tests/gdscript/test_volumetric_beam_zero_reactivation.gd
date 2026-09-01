extends SceneTree

const FixtureLightApplyServiceScript = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const VolumetricBeamRendererScript = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

class VolumetricLoader:
	extends Node
	const BEAM_INTENSITY_MAX: float = 50.0
	const EMITTER_LIGHT_DIRECTION_FIX: Vector3 = Vector3.ZERO
	const DEFAULT_EMITTER_PHOTOMETRICS: Dictionary = {"beam_type": "Wash", "has_projected_beam": true, "luminous_flux": 10000.0, "beam_angle": 25.0, "field_angle": 25.0, "beam_radius": 0.03}
	var renderer = VolumetricBeamRendererScript.new()
	var anchor := SpotLight3D.new()
	var target_record: Dictionary = {}
	var _cached_beam_defaults: Dictionary = {}
	var _visual_settings: Dictionary = {"beam_multiplier": 20.0, "spot_multiplier": 0.0, "enable_realtime_spotlights": false}

	func _ready() -> void:
		add_child(anchor)
		renderer.configure(null, {})
		renderer.ensure_beam(anchor)
		target_record = {
			"emitter_anchors": [anchor],
			"beam_instances": [renderer.get_beam_resource(anchor)],
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
		renderer.update_beam(light, params)

	func _update_beam_intensity_for_light(light: SpotLight3D, dimmer_norm: float, beam_color: Color, scaled_intensity_override: float = -1.0) -> int:
		var params: Dictionary = light.get_meta("peraviz_beam_last_params", {})
		params["normalized_dimmer"] = dimmer_norm
		params["scaled_intensity"] = scaled_intensity_override if scaled_intensity_override >= 0.0 else dimmer_norm * 20.0
		params["beam_intensity"] = params["scaled_intensity"]
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
		var beam_intensity: float = values[7] if values.size() >= 9 else normalized_dimmer * 20.0
		var params: Dictionary = _build_cached_beam_params(light, float(photometric.get("beam_angle", 25.0)), Color.WHITE, normalized_dimmer, beam_intensity, 0.03, {})
		renderer.update_beam(light, params)
		light.set_meta("peraviz_beam_last_params", params)

	func _build_cached_beam_params(_light: SpotLight3D, beam_angle: float, beam_color: Color, normalized_dimmer: float, scaled_intensity: float, lens_radius: float, _defaults: Dictionary) -> Dictionary:
		return {"beam_type": "Wash", "beam_angle": beam_angle, "beam_color": beam_color, "normalized_dimmer": normalized_dimmer, "scaled_intensity": scaled_intensity, "beam_intensity": scaled_intensity, "beam_range": 4.0, "lens_radius": lens_radius, "intensity_visibility_threshold": 0.015, "intensity_max": BEAM_INTENSITY_MAX}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var loader := VolumetricLoader.new()
	get_root().add_child(loader)
	await process_frame
	var service = FixtureLightApplyServiceScript.new()
	var beam: MeshInstance3D = loader.renderer.get_beam_resource(loader.anchor)
	test.check(beam != null and beam.mesh == null, "Allocated volumetric beam should remain uninitialized before its first state")
	service.apply_emitter_intensity(loader, "fixture", 201, 2, 0.0, 0.0, 0.0, 0.0, 0.0)
	test.check(not beam.visible and not loader.renderer.is_beam_dynamic_ready(loader.anchor), "Initial zero Dimmer should remain hidden and defer projected shape creation")
	var before_visible: Dictionary = service.get_visual_apply_counters()
	service.apply_emitter_intensity(loader, "fixture", 201, 2, 0.5, 10.0, 0.0, 10.0, 2.0)
	var after_visible: Dictionary = service.get_visual_apply_counters()
	test.check(loader.renderer.is_beam_dynamic_ready(loader.anchor) and beam.mesh != null and beam.visible, "First visible Dimmer must lazily initialize the volumetric projected shape")
	test.check(loader.renderer.get_last_parameter_write_count() == 2, "First visible initialization should count packed dynamic state and static intensity maximum writes")
	var initial_dynamic_state: Color = beam.get_instance_shader_parameter("beam_dynamic_state")
	test.check(initial_dynamic_state == Color(1.0, 1.0, 1.0, 10.0), "Packed state should retain optical RGB and raw scaled intensity")
	var visible_params: Dictionary = loader.anchor.get_meta("peraviz_beam_last_params", {})
	test.check(is_equal_approx(float(visible_params.get("scaled_intensity", -1.0)), 10.0) and visible_params.get("beam_color", Color.BLACK) == Color.WHITE, "Lazy initialization must apply current intensity and color")
	test.check(int(after_visible.get("beam_full_state_applies", 0)) == int(before_visible.get("beam_full_state_applies", 0)) + 1, "First visible Dimmer may initialize exactly once")
	var full_after_initialization: int = int(after_visible.get("beam_full_state_applies", 0))
	service.apply_emitter_intensity(loader, "fixture", 201, 2, 1.0, 20.0, 0.0, 20.0, 4.0)
	test.check(loader.renderer.get_last_parameter_write_count() == 1, "Ordinary visible intensity changes should remain one packed write")
	service.apply_emitter_intensity(loader, "fixture", 201, 2, 0.0, 0.0, 0.0, 0.0, 0.0)
	test.check(not beam.visible and beam.mesh != null, "Zero Dimmer must hide but retain the initialized volumetric shape")
	test.check(loader.renderer.get_last_parameter_write_count() == 0, "Hiding a ready beam should not write redundant dynamic shader state")
	service.apply_emitter_intensity(loader, "fixture", 201, 2, 0.0, 0.0, 0.0, 0.0, 0.0)
	test.check(loader.renderer.get_last_parameter_write_count() == 0, "An identical hidden state should remain a shader-write no-op")
	service.apply_emitter_intensity(loader, "fixture", 201, 2, 0.75, 15.0, 0.0, 15.0, 3.0)
	var unchanged_before: int = int(service.get_visual_apply_counters().get("beam_dynamic_unchanged", 0))
	service.apply_emitter_intensity(loader, "fixture", 201, 2, 0.75, 15.0, 0.0, 15.0, 3.0)
	test.check(beam.visible and beam.mesh != null, "Initialized volumetric shape must survive zero and reactivate without a retrigger")
	test.check(int(service.get_visual_apply_counters().get("beam_full_state_applies", 0)) == full_after_initialization, "Later Dimmer changes must remain on the dynamic path")
	test.check(int(service.get_visual_apply_counters().get("beam_dynamic_unchanged", 0)) == unchanged_before + 1, "Repeated identical visible state must remain a dynamic no-op")
	test.check(loader.renderer.get_last_parameter_write_count() == 0, "Repeated identical packed state should perform zero writes")
	loader._update_beam_intensity_for_light(loader.anchor, 0.75, Color(0.2, 0.4, 0.8), 15.0)
	var held_intensity_state: Color = beam.get_instance_shader_parameter("beam_dynamic_state")
	test.check(held_intensity_state == Color(0.2, 0.4, 0.8, 15.0), "Color-only updates should preserve held intensity in packed state")
	test.check(beam.get_meta("peraviz_beam_dynamic_state", Color.BLACK) == Color(0.2, 0.4, 0.8, 15.0), "Packed state should retain source optical color without CPU-side color-space conversion")
	loader._update_beam_intensity_for_light(loader.anchor, 1.0, Color(0.2, 0.4, 0.8), 25.0)
	var overdrive_state: Color = beam.get_instance_shader_parameter("beam_dynamic_state")
	test.check(overdrive_state == Color(0.2, 0.4, 0.8, 25.0), "High intensity should preserve held color and provide raw input for shader overdrive")
	test.check(is_equal_approx(float(beam.get_instance_shader_parameter("intensity_max")), 50.0), "Static intensity maximum should remain available for exact shader overdrive math")
	var max_only_params: Dictionary = loader.anchor.get_meta("peraviz_beam_last_params", {}).duplicate()
	max_only_params["intensity_max"] = 60.0
	loader.renderer.update_beam_intensity(loader.anchor, max_only_params)
	test.check(loader.renderer.get_last_parameter_write_count() == 1, "A changed intensity maximum should count its one actual instance-uniform write")
	loader.renderer.cleanup_beam(loader.anchor)
	loader.free()
	beam = null
	service = null
	await process_frame
	test.finish(self)
