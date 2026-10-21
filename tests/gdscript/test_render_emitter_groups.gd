extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()
var app: Node
var service: RefCounted
var runtime: RefCounted
var adapter: RefCounted
var dmx := PackedByteArray()

func _initialize() -> void:
	call_deferred("_run")

func _generate(pixels: bool) -> String:
	var path: String = ProjectSettings.globalize_path("user://render_group_%s.mvr" % str(pixels))
	var args := PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_render_group_fixture.py"), path])
	if pixels: args.append("--pixels")
	test.check(OS.execute("python3", args) == 0, "Standard MVR/GDTF synthetic fixture is generated")
	return path

func _load(path: String) -> void:
	var imported: Dictionary = app._load_mvr_scene(path, "mvr", false)
	test.check(bool(imported.get("ok", false)), "Production MVR import succeeds")
	service = app._fixture_light_apply_service
	service.set_performance_trace_enabled(true)
	runtime = app._dmx_controller._dmx_fixture_runtime
	runtime._sectioned_visual_frame_applier.set_performance_trace_enabled(true)
	adapter = service._dense_adapter
	test.check(adapter != null and service.is_dense_presentation_active(), "Production native renderer installation succeeds")

func _apply() -> void:
	runtime._native_visual_runtime.submit_universe_frame(0, dmx)
	var frame: Dictionary = runtime._native_visual_runtime.consume_latest_visual_frame()
	if not (frame.get("descriptors", PackedInt32Array()) as PackedInt32Array).is_empty():
		runtime._sectioned_visual_frame_applier.apply_snapshot(frame, app, service, 0.016, runtime, runtime._native_fixture_uuids_by_id, runtime._fixture_nodes)
	await process_frame

func _aggregate() -> RefCounted:
	return adapter._render_bindings.aggregate_outputs()[0]

func _run() -> void:
	test.check(change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) == OK, "Normal application scene loads")
	await process_frame
	await process_frame
	app = current_scene
	app._visual_settings["enable_realtime_spotlights"] = false
	app._visual_settings["beam_presentation"] = 1
	app._visual_settings["beam_render_mode"] = 0
	app._update_beam_renderer_mode(true)
	_load(_generate(false))
	var sizes: Dictionary = adapter.diagnostics()
	test.check(sizes["physical_outputs"] == 51 and sizes["render_rows"] == 2 and sizes["aggregated_members"] == 50, "51 canonical outputs bind one aggregate shaft plus independent emission-only row")
	if int(sizes.get("aggregated_groups", 0)) != 1:
		print("TEST FAILURE: Production compact source did not aggregate: ", sizes)
		app._clear_scene()
		app.queue_free()
		await process_frame
		quit(1)
		return
	test.check(sizes["packed_buffer_bytes"] == 2 * (2 * 4 + 12 * 4), "Only two renderer rows size the single integer/float payload pair")
	dmx.resize(512)
	dmx.fill(0)
	dmx[0] = 200
	dmx[1] = 100
	dmx[2] = 100
	dmx[3] = 160
	dmx[4] = 255
	dmx[5] = 120
	dmx[6] = 40
	await _apply()
	var aggregate: RefCounted = _aggregate()
	var light: SpotLight3D = aggregate.lights[0].light
	var beam: MeshInstance3D = aggregate.lights[0].beam
	var origin: Vector3 = light.position
	var counts: Dictionary = adapter.diagnostics()
	test.check(counts["control_groups"] == 2 and counts["largest_group"] == 50, "Production profile routes do not masquerade as independent Zoom authority")
	test.check(counts["visible_member_shafts"] == 0 and counts["visible_aggregate_shafts"] == 1 and counts["total_visible_vector_prism_shafts"] == 1, "Exactly one real Vector Prism shaft renders; fifty member shafts do not render")
	test.check(counts["surface_lights"]["active_open_surface_lights"] == 0, "Aggregation does not reactivate open-beam realtime lights")
	var transform: Transform3D = light.global_transform
	dmx[1] = 200
	await _apply()
	test.check(light.global_transform != transform and light.position == origin, "Aggregate inherits normal mechanical Pan without moving its local nominal centroid")
	for iteration in range(6):
		adapter.consume_diagnostics()
		dmx[0] = 0
		await _apply()
		var dark: Dictionary = adapter.consume_diagnostics()
		test.check(not beam.visible and dark["beam_visibility_writes"] == 1, "A Dimmer zero crossing changes only the aggregate shaft visibility")
		dmx[4] = 10 + iteration * 10
		dmx[6] = 200
		await _apply()
		dmx[0] = 210
		await _apply()
		test.check(beam.visible and light.position == origin, "Held Color and Dimmer restore one stable aggregate without origin wobble")
	test.check(adapter.diagnostics()["visible_member_shafts"] == 0, "Repeated zero crossings never revive member shaft resources")
	var old_generation: int = adapter._generation
	var old_light: SpotLight3D = light
	_load(_generate(true))
	test.check(not is_instance_valid(old_light) and adapter._generation != old_generation, "Scene replacement retires old aggregate nodes and native generation")
	test.check(adapter.diagnostics()["aggregated_members"] == 50 and adapter.diagnostics()["control_groups"] == 51, "Independent pixel controls retain one compact optical aggregate plus Aura")
	dmx.fill(0)
	dmx[0] = 200
	dmx[3] = 160
	for i in range(50): dmx[4+i*3+(0 if i < 25 else 2)] = 255
	await _apply()
	var mixed: Color = _aggregate().lights[0].beam.get_instance_shader_parameter("beam_dynamic_state")
	test.check(absf(mixed.r - 0.735357) < 0.005 and absf(mixed.b - 0.735357) < 0.005 and mixed.g < 0.005, "Production independently addressed red/blue pixels mix in linear light")
	var first: PackedFloat32Array = adapter._native.physical_values(0)
	var red_pixels: int = 0
	var blue_pixels: int = 0
	for index in range(adapter._outputs.size()):
		var values: PackedFloat32Array = adapter._native.physical_values(index)
		if values[1] > 0.99 and values[3] < 0.01: red_pixels += 1
		if values[3] > 0.99 and values[1] < 0.01: blue_pixels += 1
	test.check(red_pixels == 25 and blue_pixels == 25 and not first.is_empty(), "All individual native pixels remain exact behind the mixed shaft")
	app._clear_scene()
	app.queue_free()
	service = null
	runtime = null
	adapter = null
	aggregate = null
	await process_frame
	await process_frame
	test.finish(self)
