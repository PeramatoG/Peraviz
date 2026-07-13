extends SceneTree

const NativeRendererTargetRegistryScript = preload("res://scripts/runtime/native_renderer_target_registry.gd")
const LegacyConeBeamRendererScript = preload("res://scripts/beam_renderers/legacy_cone_beam_renderer.gd")
const VolumetricBeamRendererScript = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd")

func _equal_fluxes(count: int, flux: float) -> Array:
	var photometrics: Array = []
	for _index in range(count):
		photometrics.append({"beam_type_effective": "Wash", "luminous_flux": flux})
	return photometrics

func _sum_weights(weights: Array) -> float:
	var total: float = 0.0
	for weight in weights:
		total += float(weight)
	return total

func _assert_weight_cases() -> void:
	var registry = NativeRendererTargetRegistryScript.new()
	var single: Array = registry._calculate_emitter_output_weights([{"beam_type_effective": "Spot", "luminous_flux": 26000.0}], 1)
	assert(single.size() == 1)
	assert(is_equal_approx(float(single[0]), 1.0))
	var quantum: Array = registry._calculate_emitter_output_weights(_equal_fluxes(50, 320.0), 50)
	assert(quantum.size() == 50)
	assert(is_equal_approx(float(quantum[0]), 0.02))
	assert(is_equal_approx(_sum_weights(quantum), 1.0))
	var spiider: Array = registry._calculate_emitter_output_weights(_equal_fluxes(20, 579.0), 20)
	assert(spiider.size() == 20)
	assert(is_equal_approx(float(spiider[0]), 0.05))
	assert(is_equal_approx(_sum_weights(spiider), 1.0))
	var incomplete: Array = registry._calculate_emitter_output_weights([{"beam_type_effective": "Wash", "luminous_flux": 320.0}, {"beam_type_effective": "Wash"}], 2)
	assert(is_equal_approx(float(incomplete[0]), 0.5))
	assert(is_equal_approx(float(incomplete[1]), 0.5))
	var non_projected: Array = registry._calculate_emitter_output_weights([{"beam_type_effective": "None", "luminous_flux": 1.0}, {"beam_type_effective": "Glow", "luminous_flux": 1.0}, {"beam_type_effective": "Wash", "luminous_flux": 100.0}], 3)
	assert(is_equal_approx(float(non_projected[0]), 1.0))
	assert(is_equal_approx(float(non_projected[1]), 1.0))
	assert(is_equal_approx(float(non_projected[2]), 1.0))

func _base_params(output_weight: float, intensity: float = 20.0) -> Dictionary:
	return {
		"scaled_intensity": intensity,
		"beam_intensity": intensity,
		"normalized_dimmer": intensity / 20.0,
		"intensity_visibility_threshold": 0.015,
		"intensity_max": 50.0,
		"beam_color": Color.WHITE,
		"beam_angle": 25.0,
		"beam_range": 8.0,
		"beam_visual_length_m": 8.0,
		"lens_radius": 0.03,
		"gobo_projection_radius": 0.2,
		"photometric_output_weight": output_weight,
	}

func _assert_legacy_renderer_output_weight() -> void:
	var renderer = LegacyConeBeamRendererScript.new()
	var single_light := SpotLight3D.new()
	var weighted_light := SpotLight3D.new()
	get_root().add_child(single_light)
	get_root().add_child(weighted_light)
	var single_params: Dictionary = _base_params(1.0)
	var weighted_params: Dictionary = _base_params(0.02)
	renderer.update_beam(single_light, single_params)
	renderer.update_beam(weighted_light, weighted_params)
	var single_beam: MeshInstance3D = renderer.get_beam_resource(single_light)
	var weighted_beam: MeshInstance3D = renderer.get_beam_resource(weighted_light)
	assert(single_beam != null and single_beam.visible)
	assert(weighted_beam != null and weighted_beam.visible)
	assert(is_equal_approx(float(single_params.get("scaled_intensity", 0.0)), 20.0))
	assert(is_equal_approx(float(weighted_params.get("scaled_intensity", 0.0)), 20.0))
	assert(is_equal_approx(float(weighted_beam.get_instance_shader_parameter("near_alpha")), float(single_beam.get_instance_shader_parameter("near_alpha")) * 0.02))
	assert(is_equal_approx(float(weighted_beam.get_instance_shader_parameter("near_emission")), float(single_beam.get_instance_shader_parameter("near_emission")) * 0.02))
	var hidden_params: Dictionary = _base_params(0.02, 0.0)
	renderer.update_beam(weighted_light, hidden_params)
	assert(not weighted_beam.visible)

func _assert_volumetric_renderer_output_weight() -> void:
	var renderer = VolumetricBeamRendererScript.new()
	renderer.configure(null, {})
	var single_light := SpotLight3D.new()
	var weighted_light := SpotLight3D.new()
	get_root().add_child(single_light)
	get_root().add_child(weighted_light)
	var single_params: Dictionary = _base_params(1.0)
	var weighted_params: Dictionary = _base_params(0.05)
	renderer.update_beam(single_light, single_params)
	renderer.update_beam(weighted_light, weighted_params)
	var single_beam: MeshInstance3D = renderer.get_beam_resource(single_light)
	var weighted_beam: MeshInstance3D = renderer.get_beam_resource(weighted_light)
	assert(single_beam != null and single_beam.visible)
	assert(weighted_beam != null and weighted_beam.visible)
	assert(is_equal_approx(float(single_params.get("scaled_intensity", 0.0)), 20.0))
	assert(is_equal_approx(float(weighted_params.get("scaled_intensity", 0.0)), 20.0))
	assert(is_equal_approx(float(single_beam.get_instance_shader_parameter("beam_intensity")), float(weighted_beam.get_instance_shader_parameter("beam_intensity"))))
	assert(is_equal_approx(float(single_beam.get_instance_shader_parameter("max_brightness")), float(weighted_beam.get_instance_shader_parameter("max_brightness"))))
	assert(is_equal_approx(float(single_beam.get_instance_shader_parameter("beam_visibility")), 1.0))
	assert(is_equal_approx(float(weighted_beam.get_instance_shader_parameter("beam_visibility")), 0.05))
	var single_color: Color = single_beam.get_instance_shader_parameter("base_color")
	var weighted_color: Color = weighted_beam.get_instance_shader_parameter("base_color")
	assert(is_equal_approx(weighted_color.r, single_color.r * 0.05))
	assert(is_equal_approx(weighted_color.g, single_color.g * 0.05))
	assert(is_equal_approx(weighted_color.b, single_color.b * 0.05))
	assert(is_equal_approx(weighted_color.a, single_color.a))
	var hidden_params: Dictionary = _base_params(0.05, 0.0)
	renderer.update_beam(weighted_light, hidden_params)
	assert(not weighted_beam.visible)

func _init() -> void:
	_assert_weight_cases()
	_assert_legacy_renderer_output_weight()
	_assert_volumetric_renderer_output_weight()
	quit(0)
