extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()
var app: Node
var runtime: RefCounted
var service: RefCounted
var adapter: RefCounted
var dmx := PackedByteArray()
var snapshots: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _apply() -> Dictionary:
	runtime._native_visual_runtime.submit_universe_frame(0, dmx)
	var frame: Dictionary = service.consume_native_snapshot(runtime._native_visual_runtime, runtime._sectioned_visual_frame_applier.schema_generation())
	while frame.get("pending", false):
		await process_frame
		frame = service.consume_native_snapshot(runtime._native_visual_runtime, runtime._sectioned_visual_frame_applier.schema_generation(), true)
	runtime._sectioned_visual_frame_applier.apply_snapshot(frame, app, service, 0.016, runtime, runtime._native_fixture_uuids_by_id, runtime._fixture_nodes)
	return frame

func _run() -> void:
	test.check(change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) == OK, "Application loads")
	await process_frame
	await process_frame
	app = current_scene
	var path := ProjectSettings.globalize_path("user://rgb_strip.mvr")
	test.check(OS.execute("python3", PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_rgb_strip_fixture.py"), path])) == 0, "Synthetic 180-slot fixture generated")
	var imported: Dictionary = await app._load_mvr_scene(path, "mvr", false)
	test.check(imported.get("ok", false), "Production import succeeds")
	runtime = app._dmx_controller._dmx_fixture_runtime
	service = app._fixture_light_apply_service
	service.set_performance_trace_enabled(true)
	adapter = service._dense_adapter
	test.check(adapter._binding_records.size() == 60, "60 independent output identities installed")
	var offsets: PackedInt32Array = PackedInt32Array(runtime._native_setup_summary.get("relevant_offsets_by_universe", {}).get("0", []))
	offsets.sort()
	test.check(offsets.size() == 180 and offsets[0] == 0 and offsets[179] == 179, "Footprint remains exactly 180 consecutive DMX channels")
	for index in range(60):
		test.check(not service._has_projected_beam(adapter._binding_records[index].get("beam_optical_profile", {})), "Glow stays emission-only")
		for handle in adapter._outputs[index].lights:
			test.check(not handle.projected and (not is_instance_valid(handle.beam) or not handle.beam.visible) and not handle.realtime_visible, "Glow anchor has no projected light or shaft")
		test.check(not adapter._outputs[index].materials.is_empty(), "Every exposed lens has a real material binding")
	dmx.resize(512)
	await _apply()
	for index in range(60):
		test.check(adapter._native.physical_values(index)[7] == 0, "Zero RGB has zero material energy")
	for rgb in [Vector3(1,0,0), Vector3(0,1,0), Vector3(0,0,1), Vector3.ONE, Vector3.ZERO]:
		for pixel in range(60):
			for c in range(3): dmx[pixel*3+c] = int(rgb[c]*255)
		await _apply()
		for index in range(60):
			for handle in adapter._outputs[index].lights:
				test.check(not handle.realtime_visible and (not is_instance_valid(handle.beam) or not handle.beam.visible), "Lit Glow lens never enables projected light or shaft")
			var values: PackedFloat32Array = adapter._native.physical_values(index)
			test.check((values[7] > 0) == (rgb != Vector3.ZERO), "RGB drives actual physical material energy")
			for material in adapter._outputs[index].materials:
				var lens: PackedFloat32Array = adapter._native.material_values(material.rid)
				test.check((lens[3] > 0) == (rgb != Vector3.ZERO), "Native material binding receives visible lens energy")
				if rgb != Vector3.ZERO:
					test.check(Vector3(lens[0],lens[1],lens[2]).is_equal_approx(rgb), "Lens receives expected chromaticity")
	for pixel in range(60): snapshots.append(adapter._native.physical_values(pixel))
	dmx[51] = 255
	await _apply()
	var dirty := 0
	for index in range(60):
		if adapter._native.physical_values(index) != snapshots[index]:
			dirty += 1
			test.check(str(adapter._binding_records[index].geometry_key).contains("/Pixel17/"), "Changed output is the pixel addressed by slots 52–54")
	test.check(dirty == 1, "One pixel changed without affecting any peer")
	var held: Array = []
	for index in range(60): held.append(adapter._native.physical_values(index))
	adapter.consume_diagnostics()
	await _apply()
	var counts: Dictionary = adapter.consume_diagnostics()
	test.check(counts.get("material_parameter_writes", -1) == 0, "Unchanged DMX causes no material mutations")
	adapter._native.set_lens_emission_gain(0)
	for output in adapter._outputs:
		for material in output.materials: test.check(adapter._native.material_values(material.rid)[3] == 0, "Blackout suppresses material emission")
	adapter._native.set_lens_emission_gain(1)
	adapter._native.invalidate_renderer()
	await _apply()
	for index in range(60): test.check(adapter._native.physical_values(index) == held[index], "Held RGB and implicit intensity survive blackout and forced replay")
	var emitting := 0
	for output in adapter._outputs:
		for material in output.materials:
			if adapter._native.material_values(material.rid)[3] > 0: emitting += 1
	test.check(emitting == 1, "Only the selected lens restores positive emission")
	runtime.set_render_diagnostic_mode("transforms-only")
	service.set_render_diagnostic_mode("transforms-only")
	for output in adapter._outputs:
		for material in output.materials: test.check(adapter._native.material_values(material.rid)[3] == 0, "Renderer suppression gates lens emission")
	runtime.set_render_diagnostic_mode("full")
	service.set_render_diagnostic_mode("full")
	await _apply()
	for index in range(60): test.check(adapter._native.physical_values(index) == held[index], "Renderer restore replays held per-pixel physical state")
	app._clear_scene()
	app.queue_free()
	await process_frame
	test.finish(self)
