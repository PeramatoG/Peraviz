extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path := ProjectSettings.globalize_path("user://generated_project_loading.mvr")
	var project_path := ProjectSettings.globalize_path("user://generated_project_loading.pvz")
	test.check(OS.execute("python3", PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_render_group_fixture.py"), path, "--instances=2"])) == 0, "Generate generic repeated fixtures for the real PVZ opening route")
	var app: Node = load("res://test.tscn").instantiate()
	root.add_child(app)
	app._user_preferences.auto_load_last_file = false
	await process_frame
	var settings: Dictionary = app._visual_settings.duplicate(true)
	settings["beam_softness"] = 0.37
	settings["beam_multiplier"] = 7.0
	settings["beam_presentation"] = 1
	settings["footprint_backend"] = "custom"
	settings["beam_render_mode"] = 0
	var saved: Dictionary = app._project_archive.save_project(project_path, path, "test", settings, {"universe_offset": 2, "auto_start_dmx": false}, {})
	var round_trip: Dictionary = app._project_archive.open_project(project_path)
	test.check(round_trip.visual_settings.footprint_backend == "custom", "PVZ preserves explicit custom backend")
	var legacy_settings: Dictionary = settings.duplicate()
	legacy_settings.erase("footprint_backend")
	var legacy_path := ProjectSettings.globalize_path("user://generated_legacy_footprint.pvz")
	app._project_archive.save_project(legacy_path, path, "test", legacy_settings, {}, {})
	var legacy: Dictionary = app._project_archive.open_project(legacy_path)
	test.check(legacy.visual_settings.footprint_backend == "native" and legacy.visual_settings.beam_presentation == 1, "Legacy PVZ preserves Vector Prism with native footprint reference")
	test.check(saved.get("ok", false), "Save a generic PVZ with non-default visual and patch settings")
	var phases: Array[String] = []
	var observed: Array[Dictionary] = []
	var sample: Callable = func() -> void:
		for child in app.get_children():
			if child.get_script() == preload("res://scripts/scene_loading/scene_loading_overlay.gd"):
				phases.append(child._phase_label.text)
		if app._fixture_light_apply_service.is_dense_presentation_active():
			observed.append({"softness": app._visual_settings["beam_softness"], "offset": app._dmx_controller.get_universe_offset()})
	process_frame.connect(sample)
	await app._open_project(project_path)
	process_frame.disconnect(sample)
	test.check(not app._scene_loading and not app._scene_load_failed, "Real PVZ opening completes inside the scene-loading generation")
	test.check(phases.has("Restoring project settings…"), "PVZ restoration receives loading feedback before renderer construction")
	test.check(not observed.is_empty(), "Observe the installed production renderer during readiness")
	for item in observed:
		test.check(is_equal_approx(item.softness, 0.37) and item.offset == 2, "Every installed renderer already uses saved settings and patch offset")
	test.check(app.last_loaded_file_type == "pvz" and app._user_preferences.last_file_path == project_path, "Publication remembers the original PVZ rather than its extracted MVR")
	var adapter: RefCounted = app._fixture_light_apply_service._dense_adapter
	app._fixture_light_apply_service.set_performance_trace_enabled(true)
	# Seed nonzero native state without a live receiver, then verify replay preserves it.
	var runtime: RefCounted = app._dmx_controller._dmx_fixture_runtime
	var dmx := PackedByteArray()
	dmx.resize(512)
	dmx.fill(160)
	runtime._native_visual_runtime.submit_universe_frame(3, dmx)
	var frame: Dictionary = runtime._native_visual_runtime.consume_latest_visual_frame()
	runtime._sectioned_visual_frame_applier.apply_snapshot(frame, app, app._fixture_light_apply_service, 0.016, runtime, runtime._native_fixture_uuids_by_id, runtime._fixture_nodes)
	app._fixture_light_apply_service.set_performance_trace_enabled(true)
	var before: Dictionary = adapter.diagnostics()
	var physical: Array[PackedFloat32Array] = []
	for index in range(adapter._outputs.size()): physical.append(adapter._native.physical_values(index))
	test.check(not physical.is_empty() and physical[0][0] > 0.0, "Saved patch offset routes nonzero held DMX state to the native fixture")
	var started := Time.get_ticks_usec()
	app._apply_visual_settings({"beam_softness": 0.51, "beam_multiplier": 9.0})
	var elapsed_ms := (Time.get_ticks_usec() - started) / 1000.0
	var after: Dictionary = adapter.diagnostics()
	test.check(int(after["forced_replays"]) - int(before["forced_replays"]) == 1, "A bulk visual update rebuilds all groups exactly once, not once per physical member")
	test.check(after["physical_outputs"] == 102 and after["aggregate_shaft_resources"] == 2 and after["final_render_rows"] == 4, "Bulk settings updates preserve physical identities and aggregate resource counts")
	for index in range(physical.size()): test.check(adapter._native.physical_values(index) == physical[index], "Settings rebind preserves exact held native physical state")
	print("PROJECT_SETTINGS_BATCH ", JSON.stringify({"physical_outputs": after["physical_outputs"], "global_rebuilds": int(after["forced_replays"]) - int(before["forced_replays"]), "wall_ms": elapsed_ms}))
	var original_renderer: BeamRendererBase = app._active_beam_renderer
	for preset in ["Vector Prism + Native Footprints", "Vector Prism + Custom Footprints"]:
		app._apply_visual_settings(preload("res://scripts/visual_settings_window.gd").QUICK_PRESETS[preset])
		test.check(app._active_beam_renderer == original_renderer and app._visual_settings.beam_presentation == 1, "Preset changes preserve the atmospheric renderer")
		for index in range(physical.size()): test.check(adapter._native.physical_values(index) == physical[index], "Preset switching preserves exact held native DMX")
	test.check(app._visual_settings.footprint_backend == "custom" and not app._visual_settings.enable_realtime_spotlights, "Preferred preset resolves independent backend policy")
	# A second opening must retire the previous generation and avoid late settings work.
	var old_generation: int = adapter._generation
	await app._open_project(project_path)
	adapter = app._fixture_light_apply_service._dense_adapter
	test.check(adapter._generation != old_generation and not app._scene_loading, "PVZ reload retires the old generation and completes readiness")
	app._clear_scene()
	app.queue_free()
	await process_frame
	test.finish(self)
