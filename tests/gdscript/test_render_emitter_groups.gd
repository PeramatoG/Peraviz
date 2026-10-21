extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()
var owner_check_pending: bool = false
var app: Node
var service: RefCounted
var runtime: RefCounted
var adapter: RefCounted
var dmx := PackedByteArray()

func _initialize() -> void:
	call_deferred("_run")

func _generate(pixels: bool, load_case: bool = false) -> String:
	var path: String = ProjectSettings.globalize_path("user://render_group_%s_%s.mvr" % [str(pixels), str(load_case)])
	var args := PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_render_group_fixture.py"), path])
	if pixels: args.append("--pixels")
	if load_case: args.append("--load")
	test.check(OS.execute("python3", args) == 0, "Standard MVR/GDTF synthetic fixture is generated")
	return path

func _load(path: String) -> void:
	var imported: Dictionary = app._load_mvr_scene(path, "mvr", false)
	test.check(bool(imported.get("ok", false)), "Production MVR import succeeds")
	service = app._fixture_light_apply_service
	service.set_performance_trace_enabled(true)
	runtime = app._dmx_controller._dmx_fixture_runtime
	runtime._native_visual_runtime.set_performance_trace_enabled(true)
	runtime._sectioned_visual_frame_applier.set_performance_trace_enabled(true)
	adapter = service._dense_adapter
	owner_check_pending = true
	test.check(adapter != null and service.is_dense_presentation_active(), "Production native renderer installation succeeds")

func _apply() -> void:
	runtime._native_visual_runtime.submit_universe_frame(0, dmx)
	var frame: Dictionary = runtime._native_visual_runtime.consume_latest_visual_frame()
	if owner_check_pending:
		var expected: Dictionary = {}
		for record in adapter._binding_records: expected[int(record["beam_render_target_id"])] = record["fixture_uuid"]
		var descriptors: PackedInt32Array = frame["descriptors"]
		var integers: PackedInt32Array = frame["integers"]
		for offset in range(0,descriptors.size(),5):
			if descriptors[offset] != 3: continue
			for row in range(descriptors[offset+1]):
				var base: int = descriptors[offset+2] + row*3
				test.check(expected[integers[base+1]] == runtime._native_fixture_uuids_by_id[integers[base]], "Indexed Color owner matches canonical fixture after import/reload")
		owner_check_pending = false
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
	_load(_generate(false, true))
	counts = adapter.diagnostics()
	test.check(counts["physical_outputs"] == 1000 and counts["render_rows"] == 20 and counts["aggregate_shaft_resources"] == 20,
		"Twenty production-imported compact sources retain 1000 physical outputs and allocate exactly 20 aggregate shafts")
	dmx.fill(0)
	for f in range(20):
		dmx[f*16] = 200
		dmx[f*16+3] = 160
		dmx[f*16+4] = 255
	await _apply()
	adapter.consume_diagnostics()
	for f in range(20):
		dmx[f*16+4] = 64
		dmx[f*16+6] = 255
	await _apply()
	counts = adapter.consume_diagnostics()
	test.check(counts["visible_member_shafts"] == 0 and counts["visible_aggregate_shafts"] == 20 and counts["total_visible_vector_prism_shafts"] == 20,
		"The 1000-output application graph renders 20 actual shafts and no member shafts")
	test.check(counts["renderer_outputs_processed"] == 20 and counts["native_dirty_outputs"] == 1000,
		"One shared Color tick crosses the production boundary as 20 render rows rather than 1000 physical rows")
	test.check(counts["packed_buffer_bytes"] == 20 * 56, "The 1000-output application's packed payload is renderer-sized")
	test.check(counts["physical_color_outputs"] == 1000 and counts["beam_topology_rebuilt"] == 0 and counts["optics_apply_calls"] == 0 and counts["beam_visibility_writes"] == 0,
		"Dynamic Color changes 1000 physical states without optics, topology or visibility mutations")
	print("COLOR_AUDIT_ONE_TICK ", JSON.stringify(counts))
	var native_before: Dictionary = runtime._native_visual_runtime.get_stats()
	var timing_totals: Dictionary = {}
	for tick in range(60):
		for f in range(20): dmx[f*16+4] = 20 + tick * 3
		await _apply()
		var sample: Dictionary = adapter.consume_diagnostics()
		for key in ["native_physical_us", "native_reduction_us", "native_material_us", "compatibility_adapter_us", "actual_lens_material_renderer_writes", "lens_rids_affected", "renderer_outputs_processed"]:
			timing_totals[key] = int(timing_totals.get(key, 0)) + int(sample[key])
	print("COLOR_AUDIT_60_TICKS ", JSON.stringify(timing_totals))
	var native_interval: Dictionary = runtime._native_visual_runtime.get_stats()
	for key in ["color_evaluation_us", "color_composition_us", "color_inputs_evaluated", "color_targets_cooked", "color_rows"]: native_interval[key] -= native_before[key]
	print("COLOR_AUDIT_NATIVE_60_TICKS ", JSON.stringify(native_interval))
	app._visual_settings["enable_realtime_spotlights"] = true
	adapter.refresh_renderer()
	var fallback: Dictionary = adapter.diagnostics()
	test.check(fallback["godot_accepted_aggregates"] == 0 and fallback["godot_rejected_aggregates"] == 20 and fallback["godot_binding_rejections"].get("renderer_policy",0) == 20 and fallback["final_render_rows"] == 1000,
		"Explicit realtime policy reports Godot-only rejection and safely restores individual rows")
	app._clear_scene()
	app.queue_free()
	service = null
	runtime = null
	adapter = null
	aggregate = null
	await process_frame
	await process_frame
	test.finish(self)
