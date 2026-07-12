extends SceneTree

const FixtureLightApplyServiceScript = preload("res://scripts/runtime/fixture_light_apply_service.gd")

class FluxLoader:
	extends Node
	const BEAM_INTENSITY_MAX: float = 50.0
	var _visual_settings: Dictionary = {"enable_realtime_spotlights": false}
	var target_record: Dictionary = {}
	var lights: Array = []
	var beams: Array = []
	var materials: Array = []

	func configure_fluxes(fluxes: Array) -> void:
		for child in get_children():
			remove_child(child)
			child.queue_free()
		lights.clear()
		beams.clear()
		materials.clear()
		var photometrics: Array = []
		for index in range(fluxes.size()):
			var light := SpotLight3D.new()
			var beam := MeshInstance3D.new()
			var material := StandardMaterial3D.new()
			material.emission_enabled = true
			beam.visible = false
			add_child(light)
			add_child(beam)
			lights.append(light)
			beams.append(beam)
			materials.append(material)
			light.set_meta("test_beam", beam)
			var flux_value: Variant = fluxes[index]
			photometrics.append({} if flux_value == null else {"luminous_flux": flux_value, "beam_angle": 25.0, "field_angle": 25.0, "beam_radius": 0.05})
		target_record = {
			"geometry_nodes": [],
			"emitter_anchors": lights,
			"beam_instances": beams,
			"lens_material_targets": materials,
			"emitter_photometrics": photometrics,
		}

	func _has_native_dimmer_target(target_id: int) -> bool:
		return target_id == 201

	func _get_native_dimmer_target_record(target_id: int) -> Dictionary:
		return target_record if target_id == 201 else {}

	func _get_beam_resource_for_light(light: SpotLight3D) -> MeshInstance3D:
		return light.get_meta("test_beam", null) if light.has_meta("test_beam") else null

	func _ensure_beam_runtime_for_light(_light: SpotLight3D) -> void:
		pass

	func _apply_emitter_light_state(light: SpotLight3D, _photometric: Dictionary, normalized_dimmer: float, controls: Dictionary = {}) -> void:
		var values: PackedFloat32Array = controls.get("render_ready_values", PackedFloat32Array())
		var intensity: float = values[7] if values.size() >= 9 else normalized_dimmer * 20.0
		var energy: float = values[1] if values.size() >= 2 and values[1] > 0.0 else values[0]
		light.light_energy = energy
		var beam: MeshInstance3D = _get_beam_resource_for_light(light)
		if beam != null:
			beam.visible = normalized_dimmer > 0.0001 and intensity > 0.015
		light.set_meta("peraviz_beam_last_params", {
			"normalized_dimmer": normalized_dimmer,
			"scaled_intensity": intensity,
			"beam_intensity": intensity,
			"intensity_visibility_threshold": 0.015,
			"intensity_max": BEAM_INTENSITY_MAX,
		})

	func _update_beam_intensity_for_light(light: SpotLight3D, normalized_dimmer: float, _beam_color: Color, scaled_intensity_override: float = -1.0) -> bool:
		var params: Dictionary = light.get_meta("peraviz_beam_last_params", {}) if light.has_meta("peraviz_beam_last_params") else {}
		params["normalized_dimmer"] = normalized_dimmer
		params["scaled_intensity"] = scaled_intensity_override
		params["beam_intensity"] = scaled_intensity_override
		params["intensity_visibility_threshold"] = 0.015
		params["intensity_max"] = BEAM_INTENSITY_MAX
		light.set_meta("peraviz_beam_last_params", params)
		var beam: MeshInstance3D = _get_beam_resource_for_light(light)
		var was_visible: bool = beam != null and beam.visible
		if beam != null:
			beam.visible = normalized_dimmer > 0.0001 and scaled_intensity_override > 0.015
		return beam != null and was_visible != beam.visible

func _apply(loader: FluxLoader, service: Variant, dimmer_norm: float = 1.0) -> Dictionary:
	return service.apply_emitter_intensity(loader, "fixture-a", 201, 2, dimmer_norm, 10.0 * dimmer_norm, 0.0, 20.0 * dimmer_norm, 4.0 * dimmer_norm)

func _sum_intensity(loader: FluxLoader) -> float:
	var total: float = 0.0
	for light in loader.lights:
		var params: Dictionary = light.get_meta("peraviz_beam_last_params", {})
		total += float(params.get("scaled_intensity", 0.0))
	return total

func _assert_flux_case(service: Variant, fluxes: Array, expected_single_intensity: float, expected_total: float) -> FluxLoader:
	var loader := FluxLoader.new()
	get_root().add_child(loader)
	loader.configure_fluxes(fluxes)
	var before_lights: int = loader.lights.size()
	var before_beams: int = loader.beams.size()
	var before_materials: int = loader.materials.size()
	var result: Dictionary = _apply(loader, service)
	assert(bool(result.get("dimmer_applied", false)))
	assert(int(result.get("lights_considered", 0)) == before_lights)
	assert(int(result.get("beam_instances_considered", 0)) == before_beams)
	assert(int(result.get("lens_material_targets_considered", 0)) == before_materials)
	assert(loader.lights.size() == before_lights)
	assert(loader.beams.size() == before_beams)
	assert(loader.materials.size() == before_materials)
	var first_params: Dictionary = loader.lights[0].get_meta("peraviz_beam_last_params", {})
	assert(is_equal_approx(float(first_params.get("scaled_intensity", 0.0)), expected_single_intensity))
	assert(is_equal_approx(_sum_intensity(loader), expected_total))
	return loader

func _init() -> void:
	var service = FixtureLightApplyServiceScript.new()
	var reference := _assert_flux_case(service, [10000.0], 20.0, 20.0)
	var fifty_320: Array = []
	for _index in range(50):
		fifty_320.append(320.0)
	var quantum := _assert_flux_case(service, fifty_320, 0.64, 32.0)
	var twenty_579: Array = []
	for _index in range(20):
		twenty_579.append(579.0)
	var spiider := _assert_flux_case(service, twenty_579, 1.158, 23.16)
	var viper := _assert_flux_case(service, [26000.0], 52.0, 52.0)
	var missing := _assert_flux_case(service, [null], 20.0, 20.0)
	assert(float(viper.lights[0].get_meta("peraviz_beam_last_params", {}).get("scaled_intensity", 0.0)) > _sum_intensity(quantum))
	assert(reference.beams[0].visible)
	assert(quantum.beams[0].visible)
	assert(spiider.beams[0].visible)
	assert(missing.beams[0].visible)
	var hidden: Dictionary = _apply(missing, service, 0.0)
	assert(bool(hidden.get("dimmer_applied", false)))
	assert(not missing.beams[0].visible)
	quit(0)
