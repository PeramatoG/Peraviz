extends SceneTree

const NativeRendererTargetRegistryScript = preload("res://scripts/runtime/native_renderer_target_registry.gd")
const LegacyConeBeamRendererScript = preload("res://scripts/beam_renderers/legacy_cone_beam_renderer.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

class RegistryHarness:
	extends Node
	var renderer = LegacyConeBeamRendererScript.new()
	var node_index: Dictionary = {}
	var light_cache: Dictionary = {}
	var collect_emitter_light_calls: int = 0
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

	func collect_emitter_lights(_cache_key: String, emitter_nodes: Array) -> Array:
		collect_emitter_light_calls += 1
		var lights: Array = []
		for emitter_node in emitter_nodes:
			var node3d: Node3D = emitter_node as Node3D
			if node3d == null:
				continue
			var geometry_key: String = str(node3d.get_meta("peraviz_gdtf_geometry_key", ""))
			if light_cache.has(geometry_key):
				lights.append(light_cache.get(geometry_key))
				continue
			var light := SpotLight3D.new()
			light.name = "PeravizEmitterLight"
			node3d.add_child(light)
			light_cache[geometry_key] = light
			lights.append(light)
		return lights

	func get_emitter_photometrics(fixture_uuid: String) -> Array:
		return photometrics.get(fixture_uuid, [])

	func ensure_beam_runtime(light: SpotLight3D) -> void:
		renderer.ensure_beam(light)

	func get_beam_resource(light: SpotLight3D) -> MeshInstance3D:
		return renderer.get_beam_resource(light)

	func is_emitter_lens_mesh(mesh_instance: MeshInstance3D) -> bool:
		return mesh_instance.name.to_lower().contains("lens")

	func cleanup_resources() -> void:
		for light in light_cache.values():
			if light is SpotLight3D and is_instance_valid(light):
				renderer.cleanup_beam(light)
		light_cache.clear()

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

func _target(fixture_uuid: String, semantic: String, target_id: int, geometry_key: String, profile: Dictionary = {}) -> Dictionary:
	return {
		"fixture_id": 1,
		"fixture_uuid": fixture_uuid,
		"property_id": target_id + 1000,
		"component_id": target_id,
		"render_target_id": target_id,
		"target_id": target_id,
		"semantic": semantic,
		"geometry_key": geometry_key,
		"beam_optical_profile": profile,
	}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var harness := RegistryHarness.new()
	get_root().add_child(harness)
	var pan := harness.add_geometry("fixture-a/Base/Pan")
	var tilt := harness.add_geometry("fixture-a/Base/Pan/Tilt")
	harness.add_geometry("fixture-a/Base")
	var emitter := harness.add_geometry("fixture-a/Base/EmitterLens", true, true)
	var registry: NativeRendererTargetRegistry = _make_registry(harness)
	var empty_summary: Dictionary = registry.get_summary()
	test.check(int(empty_summary.get("pan_targets_resolved", -1)) == 0, "Registry contract check failed near source line 103")
	registry.install_manifest([{
		"fixture_uuid": "fixture-a",
		"targets": [
			_target("fixture-a", "pan", 101, "fixture-a/Base/Pan"),
			_target("fixture-a", "tilt", 102, "fixture-a/Base/Pan/Tilt"),
			_target("fixture-a", "dimmer", 201, "fixture-a/Base"),
		],
	}])
	var summary: Dictionary = registry.get_summary()
	test.check(int(summary.get("pan_targets_resolved", 0)) == 1, "Registry contract check failed near source line 113")
	test.check(int(summary.get("tilt_targets_resolved", 0)) == 1, "Registry contract check failed near source line 114")
	test.check(int(summary.get("dimmer_targets_resolved", 0)) == 1, "Registry contract check failed near source line 115")
	var transform_result: Dictionary = registry.apply_transform_targets(101, 102, 45.0, -20.0)
	test.check(bool(transform_result.get("pan_applied", false)), "Registry contract check failed near source line 117")
	test.check(bool(transform_result.get("tilt_applied", false)), "Registry contract check failed near source line 118")
	test.check(is_equal_approx(pan.rotation_degrees.y, 45.0), "Registry contract check failed near source line 119")
	test.check(is_equal_approx(tilt.rotation_degrees.x, -20.0), "Registry contract check failed near source line 120")
	var initial_record: Dictionary = registry.get_dimmer_target_record(201)
	test.check(initial_record.get("emitter_anchors", []).size() == 1, "Registry contract check failed near source line 122")
	test.check(initial_record.get("beam_instances", []).size() == 1, "Registry contract check failed near source line 123")
	test.check(initial_record.get("lens_material_targets", []).size() >= 1, "Registry contract check failed near source line 124")
	test.check(not (initial_record.get("beam_instances", [])[0] as MeshInstance3D).visible, "Registry contract check failed near source line 125")
	var gobo_path: String = _write_gobo_mask()
	registry.install_gobo_assets([{"gobo_asset_id": 901, "wheel_id": 71, "slot_index": 1, "extracted_media_path": gobo_path, "media_valid": true}])
	registry.apply_gobo_selection(201, 71, 1, 1, 901, 0)
	registry.apply_gobo_rotation_state(201, 71, 1, 2, 1, 30.0, 60.0, 1.0, 1.0)
	var selected_beam: MeshInstance3D = initial_record.get("beam_instances", [])[0] as MeshInstance3D
	var selected_mesh: Mesh = selected_beam.mesh
	registry.install_manifest([{"fixture_uuid": "fixture-a", "targets": [_target("fixture-a", "dimmer", 201, "fixture-a/Base")] }])
	var refreshed_record: Dictionary = registry.get_dimmer_target_record(201)
	var refreshed_beam: MeshInstance3D = refreshed_record.get("beam_instances", [])[0] as MeshInstance3D
	test.check(refreshed_beam.mesh == selected_mesh, "Renderer manifest refresh must rehydrate the held selected gobo without new DMX")
	test.check(int(registry.get_gobo_counters().get("renderer_reassertions", 0)) > 0, "Renderer manifest refresh must record a gobo presentation reassertion")
	DirAccess.remove_absolute(gobo_path)
	registry.clear()
	test.check(not registry.has_dimmer_target(201), "Registry contract check failed near source line 127")

	registry.install_manifest([{"fixture_uuid": "fixture-a", "targets": [_target("fixture-a", "pan", 101, "fixture-a/Missing")]}])
	test.check(registry.get_target_failure(101) is Dictionary, "Registry contract check failed near source line 130")

	registry.install_manifest([{"fixture_uuid": "fixture-a", "targets": [_target("fixture-a", "pan", 101, "fixture-a/Base/Pan"), _target("fixture-a", "pan", 101, "fixture-a/Base/Pan")]}])
	var duplicate_summary: Dictionary = registry.get_summary().get("registry_summary", {})
	test.check(int(duplicate_summary.get("duplicate_manifest_target_ids", 0)) == 1, "Registry contract check failed near source line 134")

	registry.install_manifest([{"fixture_uuid": "fixture-a", "targets": [_target("fixture-a", "dimmer", 201, "fixture-a/Base"), _target("fixture-a", "dimmer", 202, "fixture-a/Base/EmitterLens")]}])
	var overlap_summary: Dictionary = registry.get_summary().get("registry_summary", {})
	test.check(int(overlap_summary.get("dimmer_target_overlaps", 0)) >= 1, "Registry contract check failed near source line 138")
	test.check(registry.get_target_failure(202) is Dictionary, "Registry contract check failed near source line 139")

	harness.collect_emitter_light_calls = 0
	registry.install_manifest([{"fixture_uuid": "fixture-a", "targets": [
		_target("fixture-a", "beam_profile", 401, "fixture-a/Base/EmitterLens", {"beam_type": "Wash", "has_projected_beam": true, "projected_lumen_scale": 0.25, "emission_lumen_scale": 0.25}),
		_target("fixture-a", "dimmer", 201, "fixture-a/Base/EmitterLens"),
		_target("fixture-a", "color", 401, "fixture-a/Base/EmitterLens"),
		_target("fixture-a", "beam_profile", 401, "fixture-a/Base/EmitterLens", {"beam_type": "Wash", "has_projected_beam": true, "projected_lumen_scale": 0.25, "emission_lumen_scale": 0.25}),
	]}])
	var color_summary: Dictionary = registry.get_summary().get("registry_summary", {})
	var shared_dimmer_record: Dictionary = registry.get_dimmer_target_record(201)
	var shared_color_record: Dictionary = registry.get_color_target_record(401)
	test.check(registry.has_dimmer_target(201), "Registry contract check failed near source line 151")
	test.check(registry.has_color_target(401), "Registry contract check failed near source line 152")
	test.check(int(color_summary.get("dimmer_requested", 0)) == 1, "Registry contract check failed near source line 153")
	test.check(int(color_summary.get("color_requested", 0)) == 1, "Registry contract check failed near source line 154")
	test.check(int(color_summary.get("dimmer_target_overlaps", 0)) == 0, "Registry contract check failed near source line 155")
	test.check(harness.collect_emitter_light_calls == 1, "Registry contract check failed near source line 156")
	test.check(shared_dimmer_record.get("emitter_anchors", [])[0] == shared_color_record.get("emitter_anchors", [])[0], "Registry contract check failed near source line 157")
	test.check(shared_dimmer_record.get("beam_instances", [])[0] == shared_color_record.get("beam_instances", [])[0], "Registry contract check failed near source line 158")


	var keyed_harness := RegistryHarness.new()
	get_root().add_child(keyed_harness)
	keyed_harness.add_geometry("fixture-b/Base")
	keyed_harness.add_geometry("fixture-b/Base/BeamA", true, true)
	keyed_harness.add_geometry("fixture-b/Base/BeamB", true, true)
	keyed_harness.add_geometry("fixture-b/Base/Aura", true, true)
	keyed_harness.add_geometry("fixture-b/Base/Glow", true, true)
	var keyed_registry: NativeRendererTargetRegistry = _make_registry(keyed_harness)
	var profile_a: Dictionary = {"beam_type": "Wash", "has_projected_beam": true, "effective_luminous_flux_lm": 2500.0, "projected_lumen_scale": 0.25, "emission_lumen_scale": 0.25, "luminous_flux_source": "explicit"}
	var profile_b: Dictionary = {"beam_type": "Wash", "has_projected_beam": true, "effective_luminous_flux_lm": 7500.0, "projected_lumen_scale": 0.75, "emission_lumen_scale": 0.75, "luminous_flux_source": "explicit"}
	var profile_aura: Dictionary = {"beam_type": "None", "has_projected_beam": false, "effective_luminous_flux_lm": 900.0, "projected_lumen_scale": 0.0, "emission_lumen_scale": 0.09, "luminous_flux_source": "explicit"}
	var profile_glow: Dictionary = {"beam_type": "Glow", "has_projected_beam": false, "effective_luminous_flux_lm": 500.0, "projected_lumen_scale": 0.0, "emission_lumen_scale": 0.05, "luminous_flux_source": "explicit"}
	keyed_registry.install_manifest([{"fixture_uuid": "fixture-b", "targets": [
		_target("fixture-b", "beam_profile", 302, "fixture-b/Base/BeamB", profile_b),
		_target("fixture-b", "beam_profile", 303, "fixture-b/Base/Aura", profile_aura),
		_target("fixture-b", "beam_profile", 304, "fixture-b/Base/Glow", profile_glow),
		_target("fixture-b", "beam_profile", 301, "fixture-b/Base/BeamA", profile_a),
		_target("fixture-b", "dimmer", 401, "fixture-b/Base"),
	]}])
	var keyed_record: Dictionary = keyed_registry.get_dimmer_target_record(401)
	var records: Array = keyed_record.get("emitter_records", [])
	test.check(records.size() == 4, "Dimmer inheritance must retain projected, None, and Glow physical outputs")
	var projected_sum: float = 0.0
	var aura_scale: float = -1.0
	for keyed_record_item in records:
		var keyed_emitter_record: Dictionary = keyed_record_item
		projected_sum += float(keyed_emitter_record.get("projected_lumen_scale", 0.0))
		if str(keyed_emitter_record.get("geometry_key", "")) == "fixture-b/Base/Aura":
			aura_scale = float(keyed_emitter_record.get("emission_lumen_scale", -1.0))
	test.check(is_equal_approx(projected_sum, 1.0), "Registry contract check failed near source line 187")
	test.check(is_equal_approx(aura_scale, 0.09), "Registry contract check failed near source line 188")
	test.check(keyed_record.get("beam_instances", []).size() == 2, "Registry contract check failed near source line 189")
	test.check(int(keyed_registry.get_summary().get("registry_summary", {}).get("emission_only_beam_profiles", 0)) == 2, "BeamType None and Glow must remain emission-only without volumetric instances")

	var quantum_harness := RegistryHarness.new()
	get_root().add_child(quantum_harness)
	quantum_harness.add_geometry("fixture-q/Base")
	var quantum_targets: Array = []
	for i in range(50):
		var key: String = "fixture-q/Base/Beam%02d" % i
		quantum_harness.add_geometry(key, true, false)
		quantum_targets.append(_target("fixture-q", "beam_profile", 500 + i, key, {"beam_type": "Wash", "has_projected_beam": true, "effective_luminous_flux_lm": 320.0, "projected_lumen_scale": 0.032, "emission_lumen_scale": 0.032, "luminous_flux_source": "explicit"}))
	quantum_harness.add_geometry("fixture-q/Base/Aura", true, false)
	quantum_targets.append(_target("fixture-q", "beam_profile", 700, "fixture-q/Base/Aura", {"beam_type": "None", "has_projected_beam": false, "effective_luminous_flux_lm": 900.0, "projected_lumen_scale": 0.0, "emission_lumen_scale": 0.09, "luminous_flux_source": "explicit"}))
	quantum_targets.append(_target("fixture-q", "dimmer", 800, "fixture-q/Base"))
	var quantum_registry: NativeRendererTargetRegistry = _make_registry(quantum_harness)
	quantum_registry.install_manifest([{"fixture_uuid": "fixture-q", "targets": quantum_targets}])
	var quantum_record: Dictionary = quantum_registry.get_dimmer_target_record(800)
	test.check(quantum_record.get("beam_instances", []).size() == 50, "Registry contract check failed near source line 205")
	var quantum_sum: float = 0.0
	for quantum_record_item in quantum_record.get("emitter_records", []):
		quantum_sum += float((quantum_record_item as Dictionary).get("projected_lumen_scale", 0.0))
	test.check(abs(quantum_sum - 1.6) < 0.001, "Registry contract check failed near source line 209")
	registry.clear()
	keyed_registry.clear()
	quantum_registry.clear()
	harness.cleanup_resources()
	keyed_harness.cleanup_resources()
	quantum_harness.cleanup_resources()
	await process_frame
	harness.free()
	keyed_harness.free()
	quantum_harness.free()
	call_deferred("_finish")

func _write_gobo_mask() -> String:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var path: String = ProjectSettings.globalize_path("user://renderer_refresh_gobo.png")
	image.save_png(path)
	return path

func _finish() -> void:
	await process_frame
	await process_frame
	test.finish(self)
