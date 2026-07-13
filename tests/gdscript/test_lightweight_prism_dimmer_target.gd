extends SceneTree

const FixtureLightApplyServiceScript = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const LegacyConeBeamRendererScript = preload("res://scripts/beam_renderers/legacy_cone_beam_renderer.gd")

class PrismLoader:
	extends Node
	const BEAM_INTENSITY_MAX: float = 50.0
	const EMITTER_LIGHT_DIRECTION_FIX: Vector3 = Vector3.ZERO
	const DEFAULT_EMITTER_PHOTOMETRICS: Dictionary = {"luminous_flux": 10000.0, "beam_angle": 25.0, "field_angle": 25.0, "beam_radius": 0.05}
	var renderer = LegacyConeBeamRendererScript.new()
	var anchor := SpotLight3D.new()
	var lens := MeshInstance3D.new()
	var target_record: Dictionary = {}
	var _cached_beam_defaults: Dictionary = {}
	var _visual_settings: Dictionary = {"beam_multiplier": 20.0, "spot_multiplier": 0.0}

	func _ready() -> void:
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

	func _update_beam_intensity_for_light(light: SpotLight3D, dimmer_norm: float, beam_color: Color, scaled_intensity_override: float = -1.0) -> bool:
		var params: Dictionary = light.get_meta("peraviz_beam_last_params", {}) if light.has_meta("peraviz_beam_last_params") else _build_cached_beam_params(light, 25.0, beam_color, dimmer_norm, scaled_intensity_override, 0.03, {})
		params["normalized_dimmer"] = dimmer_norm
		params["scaled_intensity"] = scaled_intensity_override if scaled_intensity_override >= 0.0 else dimmer_norm * 20.0
		params["beam_intensity"] = params["scaled_intensity"]
		params["intensity_max"] = BEAM_INTENSITY_MAX
		var changed: bool = renderer.update_beam_intensity(light, params)
		light.set_meta("peraviz_beam_last_params", params)
		return changed

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
	var root := PrismLoader.new()
	get_root().add_child(root)
	root._ready()
	var service = FixtureLightApplyServiceScript.new()
	var prism: MeshInstance3D = root.renderer.get_beam_resource(root.anchor)
	assert(prism != null)
	assert(not prism.visible)
	var zero: Dictionary = service.apply_emitter_intensity(root, "fixture-a", 201, 2, 0.0, 0.0, 0.0, 0.0, 0.0)
	assert(bool(zero.get("dimmer_applied", false)))
	assert(not prism.visible)
	var mid: Dictionary = service.apply_emitter_intensity(root, "fixture-a", 201, 2, 0.5, 10.0, 0.0, 10.0, 2.0)
	assert(bool(mid.get("dimmer_applied", false)))
	assert(prism.visible)
	var mid_energy: float = float((root.lens.material_override as BaseMaterial3D).emission_energy_multiplier)
	assert(mid_energy > 0.0)
	var maxed: Dictionary = service.apply_emitter_intensity(root, "fixture-a", 201, 2, 1.0, 20.0, 0.0, 20.0, 4.0)
	assert(bool(maxed.get("dimmer_applied", false)))
	assert(prism.visible)
	assert(float((root.lens.material_override as BaseMaterial3D).emission_energy_multiplier) > mid_energy)
	root.target_record["emitter_records"] = [{"projected_lumen_scale": 0.5, "emission_lumen_scale": 0.5, "has_projected_beam": true}]
	var scaled: Dictionary = service.apply_emitter_intensity(root, "fixture-a", 201, 2, 1.0, 20.0, 10.0, 20.0, 4.0)
	assert(bool(scaled.get("dimmer_applied", false)))
	assert(is_equal_approx(root.anchor.light_energy, 5.0))
	var params: Dictionary = root.anchor.get_meta("peraviz_beam_last_params", {})
	assert(is_equal_approx(float(params.get("beam_intensity", -1.0)), 10.0))
	var hidden: Dictionary = service.apply_emitter_intensity(root, "fixture-a", 201, 2, 0.0, 0.0, 0.0, 0.0, 0.0)
	assert(bool(hidden.get("dimmer_applied", false)))
	assert(not prism.visible)
	quit(0)
