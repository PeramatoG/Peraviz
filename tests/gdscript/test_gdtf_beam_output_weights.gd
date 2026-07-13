extends SceneTree

const NativeRendererTargetRegistryScript = preload("res://scripts/runtime/native_renderer_target_registry.gd")
const LegacyConeBeamRendererScript = preload("res://scripts/beam_renderers/legacy_cone_beam_renderer.gd")
const VolumetricBeamRendererScript = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd")

class RegistryHarness:
	extends Node
	var renderer = LegacyConeBeamRendererScript.new()
	var node_index: Dictionary = {}
	var light_cache: Dictionary = {}
	var photometrics: Dictionary = {}

	func add_geometry(key: String, is_emitter: bool = false) -> Node3D:
		var node := Node3D.new()
		node.name = key.get_file().replace("/", "_")
		node.set_meta("peraviz_gdtf_geometry_key", key)
		node.set_meta("peraviz_fixture_uuid", key.split("/")[0])
		node.set_meta("peraviz_is_emitter", is_emitter)
		add_child(node)
		node_index[key] = node
		return node

	func collect_emitter_lights(cache_key: String, emitter_nodes: Array) -> Array:
		if light_cache.has(cache_key):
			return light_cache.get(cache_key, [])
		var lights: Array = []
		for emitter_node in emitter_nodes:
			var node3d: Node3D = emitter_node as Node3D
			if node3d == null:
				continue
			var light := SpotLight3D.new()
			node3d.add_child(light)
			lights.append(light)
		light_cache[cache_key] = lights
		return lights

	func get_emitter_photometrics(fixture_uuid: String) -> Array:
		return photometrics.get(fixture_uuid, [])

	func ensure_beam_runtime(light: SpotLight3D) -> void:
		renderer.ensure_beam(light)

	func get_beam_resource(light: SpotLight3D) -> MeshInstance3D:
		return renderer.get_beam_resource(light)

func _target(fixture_uuid: String, semantic: String, target_id: int, geometry_key: String, optical: Dictionary = {}) -> Dictionary:
	var target := {
		"fixture_id": 1,
		"fixture_uuid": fixture_uuid,
		"property_id": target_id + 1000,
		"component_id": target_id,
		"render_target_id": target_id,
		"target_id": target_id,
		"semantic": semantic,
		"geometry_key": geometry_key,
	}
	if not optical.is_empty():
		target["beam_optical_profile"] = optical
	return target

func _make_registry(harness: RegistryHarness) -> Variant:
	var registry = NativeRendererTargetRegistryScript.new()
	registry.configure({
		"node_index": harness.node_index,
		"callbacks": {
			"collect_emitter_lights": Callable(harness, "collect_emitter_lights"),
			"get_emitter_photometrics": Callable(harness, "get_emitter_photometrics"),
			"ensure_beam_runtime": Callable(harness, "ensure_beam_runtime"),
			"get_beam_resource": Callable(harness, "get_beam_resource"),
		},
	})
	return registry

func _assert_registry_uses_native_weights() -> void:
	var harness := RegistryHarness.new()
	get_root().add_child(harness)
	harness.add_geometry("fixture-a/Base")
	var photometrics: Array = []
	var targets: Array = []
	for index in range(10):
		var key: String = "fixture-a/Base/Beam%d" % index
		harness.add_geometry(key, true)
		photometrics.append({"beam_type_effective": "Wash", "luminous_flux": 100.0})
		targets.append(_target("fixture-a", "beam_profile", 300 + index, key, {"beam_output_weight": 0.1, "beam_type_effective": "Wash"}))
	harness.photometrics["fixture-a"] = photometrics
	targets.append(_target("fixture-a", "dimmer", 201, "fixture-a/Base"))
	var registry = _make_registry(harness)
	registry.install_manifest([{"fixture_uuid": "fixture-a", "targets": targets}])
	var record: Dictionary = registry.get_dimmer_target_record(201)
	assert(record.get("emitter_anchors", []).size() == 10)
	assert(record.get("beam_instances", []).size() == 10)
	var total_weight: float = 0.0
	for entry in record.get("emitter_photometrics", []):
		total_weight += float((entry as Dictionary).get("beam_output_weight", 0.0))
		assert(is_equal_approx(float((entry as Dictionary).get("beam_output_weight", 0.0)), 0.1))
	assert(is_equal_approx(total_weight, 1.0))
	for light in record.get("emitter_anchors", []):
		assert(is_equal_approx(float((light as SpotLight3D).get_meta("peraviz_beam_output_weight", 0.0)), 0.1))

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
		"beam_output_weight": output_weight,
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
	_assert_registry_uses_native_weights()
	_assert_legacy_renderer_output_weight()
	_assert_volumetric_renderer_output_weight()
	quit(0)
