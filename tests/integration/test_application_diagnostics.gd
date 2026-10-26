extends SceneTree

# Arguments are supplied by a real Godot process after --. The real main scene
# configures the production controller; this test never injects its configuration.
const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
const Trace = preload("res://scripts/runtime/performance_trace_snapshot.gd")
var test = TestCase.new()
var app: Node

func _initialize() -> void: call_deferred("run")

func argument(name: String, fallback: String = "") -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with(name+"="): return value.trim_prefix(name+"=")
	return fallback

func run() -> void:
	change_scene_to_file("res://test.tscn")
	await process_frame
	await process_frame
	app = current_scene
	var mode: String = argument("--expect-mode","full")
	var trace: bool = argument("--expect-trace","false") == "true"
	var fixture: String = argument("--fixture")
	test.check(app._dmx_controller.get_render_diagnostic_mode() == mode, "User arguments reach production diagnostic mode")
	test.check(app._dmx_controller._perf_trace_enabled == trace, "User arguments reach production trace configuration")
	test.check((await app._load_mvr_scene(fixture,"mvr",false)).get("ok",false), "Production MVR scene loads")
	# These assertions intentionally cover native projector diagnostics.
	app._apply_visual_settings({"footprint_backend": "native"})
	var service: RefCounted = app._fixture_light_apply_service
	test.check(service.is_dense_presentation_active(), "Dense installation is active in every mode")
	apply_dmx(200,120)
	await process_frame
	var initial_transform: Transform3D = app._native_target_registry._pan_targets.values()[0].global_transform
	apply_dmx(210,220)
	await process_frame
	test.check(app._native_target_registry._pan_targets.values()[0].global_transform != initial_transform, "Native Pan still changes real transforms in every mode")
	var resources: Dictionary = verify_resources(mode)
	var visible_beams: int = resources["beams"]
	var visible_spots: int = resources["lights"]
	var sampler: RefCounted = Trace.new()
	var sample: Dictionary = sampler.collect(app,app._dmx_controller._dmx_fixture_runtime._native_visual_runtime)
	var counters: Dictionary = service.get_visual_apply_counters()
	test.check(sample["render_diagnostic_mode"] == mode and sample["dense_presentation_active"], "Trace reports selected mode and active dense owner")
	test.check(sample["dense_presentation"]["render_diagnostic_mode"] == mode, "Dense report uses the selected policy")
	test.check(counters["beam_visible_count"] == visible_beams and counters["spotlight_visible_count"] == visible_spots, "Same-report visibility counts reflect actual dense resources")
	test.check(not sample["legacy_compatibility"]["active"], "Legacy diagnostics are explicitly inactive in production")
	# Exercise the actual controller's trace print ordering with a receiver that
	# supplies no packets. This verifies visible_beams is fresh in the same report.
	if trace:
		app._dmx_controller._perf_trace_last_msec = -2000
		app._dmx_controller._report_performance_trace_if_needed()
	if OS.get_cmdline_user_args().has("--reload"):
		var previous_generation: int = service._dense_adapter._generation
		var retired: Array[WeakRef] = capture_scene_resources()
		app._clear_scene()
		await process_frame
		await process_frame
		for ref in retired: test.check(ref.get_ref() == null, "Explicit unload releases owned scene resources and bound handles: "+str(ref.get_ref()))
		test.check(service._dense_adapter == null and app._native_target_registry._lens_material_cache.is_empty(), "Unload retires dense generation and material bindings")
		test.check(app._asset_cache._scene_cache.is_empty() and app._asset_cache._mesh_cache.is_empty(), "Unload releases import caches")
		test.check((await app._load_mvr_scene(fixture,"mvr",false)).get("ok",false), "Second scene load succeeds")
		test.check(service.is_dense_presentation_active() and service._dense_adapter._generation != previous_generation, "Reload installs a fresh dense generation")
		app._apply_visual_settings({"footprint_backend": "native"})
		apply_dmx(200,180)
		await process_frame
		verify_resources(mode)
		var shutdown: Array[WeakRef] = capture_scene_resources()
		var native_loader: WeakRef = weakref(app._loader)
		app.queue_free() # Deliberately omit manual scene clear: normal exit must own it.
		app = null
		await process_frame
		await process_frame
		for ref in shutdown: test.check(ref.get_ref() == null, "Application destruction releases bound handles and scene resources: "+str(ref.get_ref()))
		test.check(native_loader.get_ref() == null, "Application releases its native Object loader")
		service = null
	else:
		# Keep the scene loaded through quit to exercise Godot's real shutdown order.
		service = null
	if test.failures.is_empty(): print("APPLICATION_DIAGNOSTICS_PASSED mode=",mode," trace=",trace," beams=",visible_beams," lights=",visible_spots)
	test.finish(self)

func apply_dmx(level: int, pan: int) -> void:
	var runtime: RefCounted = app._dmx_controller._dmx_fixture_runtime
	var dmx := PackedByteArray()
	dmx.resize(512)
	for base in [0,16]:
		for offset in range(8): dmx[base+offset] = [level,150,210,255,pan,128,100,255][offset]
	runtime._native_visual_runtime.submit_universe_frame(0,dmx)
	var frame: Dictionary = runtime._native_visual_runtime.consume_latest_visual_frame()
	runtime._sectioned_visual_frame_applier.apply_snapshot(frame,app,app._fixture_light_apply_service,0.016,runtime,runtime._native_fixture_uuids_by_id,runtime._fixture_nodes)

func capture_scene_resources() -> Array[WeakRef]:
	var refs: Array[WeakRef] = []
	var adapter: RefCounted = app._fixture_light_apply_service._dense_adapter
	refs.append(weakref(adapter))
	for output in adapter._outputs:
		for material in output.materials: refs.append(weakref(material.material))
		for handle in output.lights:
			for resource in [handle,handle.bound_state,handle.beam,handle.beam.mesh,handle.beam.material_override,handle.light.light_projector]:
				if resource != null: refs.append(weakref(resource))
	for node in app.proxies_root.find_children("*","CollisionShape3D",true,false):
		refs.append(weakref(node))
		if node.shape != null: refs.append(weakref(node.shape))
	return refs

# Keep resource references in a completed helper frame before testing weak ownership.
func verify_resources(mode: String) -> Dictionary:
	var service: RefCounted = app._fixture_light_apply_service
	test.check(not app.proxies_root.find_children("*","CollisionShape3D",true,false).is_empty(), "Real imported picking/collision ownership is exercised")
	var visible_beams: int = 0
	var visible_spots: int = 0
	var lens_energy: float = 0.0
	for output in service._dense_adapter._outputs:
		test.check(not output.materials.is_empty(), "Real lens material is bound")
		for material in output.materials: lens_energy += service._dense_adapter._native.material_values(material.rid)[3]
		for handle in output.lights:
			if handle.beam != null and handle.beam.is_visible_in_tree(): visible_beams += 1
			if handle.realtime_visible: visible_spots += 1
			if mode == "full":
				test.check(handle.beam.mesh != null and handle.beam.is_visible_in_tree(), "Full shows actual shaft mesh")
				test.check(handle.light.light_projector != null, "Full restores actual gobo projector")
			else:
				test.check(not handle.light.visible and not handle.beam.visible, "Suppressed modes keep actual light/shaft Nodes hidden")
				test.check(handle.light.light_projector == null, "Suppressed modes detach actual projector")
	test.check(visible_beams == (2 if mode == "full" else 0), "Actual beam visibility differs by diagnostic mode")
	test.check(visible_spots == (2 if mode == "full" else 0), "Actual projector-light policy differs by diagnostic mode")
	test.check(lens_energy > 0.0 if mode != "transforms-only" else is_zero_approx(lens_energy), "No-beams preserves lenses; transforms-only suppresses their emission")
	return {"beams":visible_beams,"lights":visible_spots}
