extends SceneTree

const NativeRendererTargetRegistryScript = preload("res://scripts/runtime/native_renderer_target_registry.gd")
const LegacyConeBeamRendererScript = preload("res://scripts/beam_renderers/legacy_cone_beam_renderer.gd")

class RegistryHarness:
	extends Node
	var renderer = LegacyConeBeamRendererScript.new()
	var node_index: Dictionary = {}
	var light_cache: Dictionary = {}
	var photometrics: Dictionary = {"fixture-a": [{"luminous_flux": 10000.0, "beam_angle": 25.0, "field_angle": 25.0, "beam_radius": 0.05}]}

	func add_geometry(key: String, is_emitter: bool = false, with_lens_material: bool = false) -> Node3D:
		var node: Node3D = MeshInstance3D.new() if with_lens_material else Node3D.new()
		node.name = key.get_file().replace("/", "_")
		node.set_meta("peraviz_gdtf_geometry_key", key)
		node.set_meta("peraviz_fixture_uuid", key.split("/")[0])
		node.set_meta("peraviz_is_emitter", is_emitter)
		if node is MeshInstance3D:
			var mesh_instance: MeshInstance3D = node as MeshInstance3D
			mesh_instance.name = "EmitterLens"
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.1, 0.1, 0.02)
			mesh_instance.mesh = mesh
			mesh_instance.material_override = StandardMaterial3D.new()
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
			light.name = "PeravizEmitterLight"
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

	func is_emitter_lens_mesh(mesh_instance: MeshInstance3D) -> bool:
		return mesh_instance.name.to_lower().contains("lens")

func _make_registry(harness: RegistryHarness) -> NativeRendererTargetRegistry:
	var registry: NativeRendererTargetRegistry = NativeRendererTargetRegistryScript.new()
	registry.configure({
		"node_index": harness.node_index,
		"callbacks": {
			"collect_emitter_lights": Callable(harness, "collect_emitter_lights"),
			"get_emitter_photometrics": Callable(harness, "get_emitter_photometrics"),
			"ensure_beam_runtime": Callable(harness, "ensure_beam_runtime"),
			"get_beam_resource": Callable(harness, "get_beam_resource"),
			"is_emitter_lens_mesh": Callable(harness, "is_emitter_lens_mesh"),
		},
	})
	return registry

func _target(fixture_uuid: String, semantic: String, target_id: int, geometry_key: String) -> Dictionary:
	return {
		"fixture_id": 1,
		"fixture_uuid": fixture_uuid,
		"property_id": target_id + 1000,
		"component_id": target_id,
		"render_target_id": target_id,
		"target_id": target_id,
		"semantic": semantic,
		"geometry_key": geometry_key,
	}

func _init() -> void:
	var harness := RegistryHarness.new()
	get_root().add_child(harness)
	var pan := harness.add_geometry("fixture-a/Base/Pan")
	var tilt := harness.add_geometry("fixture-a/Base/Pan/Tilt")
	harness.add_geometry("fixture-a/Base")
	var emitter := harness.add_geometry("fixture-a/Base/EmitterLens", true, true)
	var registry: NativeRendererTargetRegistry = _make_registry(harness)
	var empty_summary: Dictionary = registry.get_summary()
	assert(int(empty_summary.get("pan_targets_resolved", -1)) == 0)
	registry.install_manifest([{
		"fixture_uuid": "fixture-a",
		"targets": [
			_target("fixture-a", "pan", 101, "fixture-a/Base/Pan"),
			_target("fixture-a", "tilt", 102, "fixture-a/Base/Pan/Tilt"),
			_target("fixture-a", "dimmer", 201, "fixture-a/Base"),
		],
	}])
	var summary: Dictionary = registry.get_summary()
	assert(int(summary.get("pan_targets_resolved", 0)) == 1)
	assert(int(summary.get("tilt_targets_resolved", 0)) == 1)
	assert(int(summary.get("dimmer_targets_resolved", 0)) == 1)
	var transform_result: Dictionary = registry.apply_transform_targets(101, 102, 45.0, -20.0)
	assert(bool(transform_result.get("pan_applied", false)))
	assert(bool(transform_result.get("tilt_applied", false)))
	assert(is_equal_approx(pan.rotation_degrees.y, 45.0))
	assert(is_equal_approx(tilt.rotation_degrees.x, -20.0))
	var record: Dictionary = registry.get_dimmer_target_record(201)
	assert(record.get("emitter_anchors", []).size() == 1)
	assert(record.get("beam_instances", []).size() == 1)
	assert(record.get("lens_material_targets", []).size() >= 1)
	assert(not (record.get("beam_instances", [])[0] as MeshInstance3D).visible)
	registry.clear()
	assert(not registry.has_dimmer_target(201))

	registry.install_manifest([{"fixture_uuid": "fixture-a", "targets": [_target("fixture-a", "pan", 101, "fixture-a/Missing")]}])
	assert(registry.get_target_failure(101) is Dictionary)

	registry.install_manifest([{"fixture_uuid": "fixture-a", "targets": [_target("fixture-a", "pan", 101, "fixture-a/Base/Pan"), _target("fixture-a", "pan", 101, "fixture-a/Base/Pan")]}])
	var duplicate_summary: Dictionary = registry.get_summary().get("registry_summary", {})
	assert(int(duplicate_summary.get("duplicate_manifest_target_ids", 0)) == 1)

	registry.install_manifest([{"fixture_uuid": "fixture-a", "targets": [_target("fixture-a", "dimmer", 201, "fixture-a/Base"), _target("fixture-a", "dimmer", 202, "fixture-a/Base/EmitterLens")]}])
	var overlap_summary: Dictionary = registry.get_summary().get("registry_summary", {})
	assert(int(overlap_summary.get("dimmer_target_overlaps", 0)) >= 1)
	assert(registry.get_target_failure(202) is Dictionary)
	quit(0)
