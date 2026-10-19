extends SceneTree

const LoaderScript = preload("res://tests/gdscript/helpers/coalescing_loader.gd")
const ServiceScript = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const TraceScript = preload("res://scripts/runtime/performance_trace_snapshot.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")
const LoadSceneScript = preload("res://scripts/load_scene.gd")
const VectorCacheScript = preload("res://scripts/gobo_vectorization/gobo_vectorization_cache.gd")
const VolumetricScript = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd")
const RegistryScript = preload("res://scripts/runtime/native_renderer_target_registry.gd")

var test = HeadlessTestCaseScript.new()

class DiagnosticOwner:
	extends Node
	var _fixture_light_apply_service: Object
	var _native_target_registry: Object
	var _beam_renderers: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _sizes(service: Object) -> Dictionary:
	var result: Dictionary = {}
	for key in TraceScript.APPLY_COLLECTIONS:
		result[key] = (service.get(key) as Dictionary).size()
	return result

func _run() -> void:
	for index in range(32):
		var resource_registry = RegistryScript.new()
		var registry_vectorizer: Object = resource_registry._gobo_resources._vectorizer
		resource_registry = null
		test.check(not is_instance_valid(registry_vectorizer), "Resource registry must release its native Object vectorizer")
		var vector_cache = VectorCacheScript.new()
		var cache_vectorizer: Object = vector_cache._native_vectorizer
		vector_cache = null
		test.check(not is_instance_valid(cache_vectorizer), "Vector cache must release its native Object vectorizer")
	var service = ServiceScript.new()
	var native_runtime: Object = ClassDB.instantiate("PeravizVisualRuntime")
	var trace = TraceScript.new()
	trace.configure(get_root())
	var diagnostic_owner := DiagnosticOwner.new()
	diagnostic_owner._fixture_light_apply_service = service
	var binding_owner = LoadSceneScript.new()
	binding_owner._fixture_light_apply_service = service
	binding_owner._native_target_registry = RegistryScript.new()
	for generation in range(3):
		# Exercise the actual binding installation boundary, not just the reset helper.
		binding_owner._register_native_runtime_targets([])
		for count in _sizes(service).values():
			test.check(int(count) == 0, "New native bindings must retire old presentation identities")
		var loader = LoaderScript.new()
		loader.output_count = 51
		get_root().add_child(loader)
		await process_frame
		for output in loader.outputs:
			output["lens_material_targets"] = [StandardMaterial3D.new()]
		service.set_performance_trace_enabled(generation != 1)
		var warm: Dictionary = {}
		var beam_ids: Array[int] = []
		for frame_index in range(512):
			var level: float = float((frame_index % 251) + 1) / 255.0
			var color := Color(level, 1.0 - level, 0.4)
			service.begin_visual_snapshot()
			service.apply_emitter_intensity_fast(loader, "fixture", 201, 1 << 1, level, level * 20.0, level * 16.0, level * 20.0, level * 4.0)
			service.apply_emitter_color_fast(loader, "fixture", 301, 1 << 2, color, 1.0)
			test.check(service._snapshot_output_commits.size() == 51, "Shared control must coalesce to exactly 51 physical commits")
			service.end_visual_snapshot()
			test.check(service._snapshot_output_commits.is_empty(), "Snapshot-local commits must clear every frame")
			if frame_index == 0:
				warm = _sizes(service)
				for anchor in loader.anchors:
					beam_ids.append(loader.renderer.get_beam_resource(anchor).get_instance_id())
			else:
				test.check(_sizes(service) == warm, "Persistent maps must stabilize despite changing DMX values")
			for index in range(loader.anchors.size()):
				test.check(loader.renderer.get_beam_resource(loader.anchors[index]).get_instance_id() == beam_ids[index], "Steady DMX must reuse renderer resources")
			if frame_index % 64 == 0:
				var sample: Dictionary = trace.collect(diagnostic_owner, native_runtime)
				test.check(float(sample["viewport_cpu_ms"]) >= 0.0 and float(sample["viewport_gpu_ms"]) >= 0.0, "Headless renderer timings may be zero")
				test.check((sample["sizes"] as Dictionary).get("apply_snapshot_output_commits", -1) == 0, "Report must observe drained commits")
		var params: Dictionary = loader.anchors[0].get_meta("peraviz_beam_last_params", {})
		test.check(params.get("beam_color", Color.BLACK) == Color(float((511 % 251) + 1) / 255.0, 1.0 - float((511 % 251) + 1) / 255.0, 0.4), "Latest held color must survive fan-out")
		for anchor in loader.anchors:
			loader.renderer.cleanup_beam(anchor)
		loader.renderer.reset_scene_state()
		test.check(loader.renderer._mesh_builder._mesh_cache.is_empty(), "Scene retirement must release cached renderer meshes")
		loader.free()
		await process_frame
	var renderer = VolumetricScript.new()
	renderer.configure(null, {"beam_presentation": 3})
	for index in range(32):
		var light := SpotLight3D.new()
		get_root().add_child(light)
		renderer.update_beam(light, {"beam_type": "Spot", "scaled_intensity": 10.0, "beam_range": 4.0})
		test.check(int(renderer.get_proxy_diagnostics()["allocated_shader_proxies"]) == 1, "Proxy registry must describe the current emitter")
		renderer.cleanup_beam(light)
		test.check(int(renderer.get_proxy_diagnostics()["allocated_shader_proxies"]) == 0, "Presentation cleanup must retire proxy IDs")
		light.free()
	var mesh_builder = renderer._shape_providers["gobo_prism"]._mesh_builder
	mesh_builder.build_normalized_beam_mesh(null)
	test.check(not mesh_builder._mesh_cache.is_empty(), "Seed a scene-owned normalized mesh cache")
	renderer.reset_scene_state()
	test.check(mesh_builder._mesh_cache.is_empty(), "Volumetric scene retirement must release cached topology")
	service.reset_scene_state()
	for count in _sizes(service).values():
		test.check(int(count) == 0, "Scene reset must retire all presentation state")
	test.check(trace._sampled_high_water.size() <= 40, "Trace must retain fixed keys, not one sample per frame")
	binding_owner.free()
	diagnostic_owner.free()
	trace = null
	service = null
	native_runtime = null
	await process_frame
	test.finish(self)
