extends SceneTree

const Case = preload("res://tests/gdscript/headless_test_case.gd")
const Probe = preload("res://tests/gdscript/helpers/shutter_output_probe.gd")
var test = Case.new()
var app: Node
var adapter: RefCounted
var runtime: RefCounted
var source: String
var source_hash: String

func _initialize() -> void: run.call_deferred()

func open_scene(flags: Array = [], count: int = 32) -> void:
	source = ProjectSettings.globalize_path("user://public_shutter_%d.mvr" % OS.get_process_id())
	var args := PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_shutter_fixture.py"),source,"--outputs",str(count)])
	for flag in flags: args.append(flag)
	test.check(OS.execute("python3",args) == 0,"Generate public deterministic shutter archive")
	source_hash = FileAccess.get_sha256(source)
	app = load("res://test.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	app._user_preferences.auto_load_last_file = false
	app._dmx_controller.set_universe_offset(-1,false)
	app._apply_visual_settings({"beam_presentation":1,"footprint_backend":"custom","fake_smoke_enabled":false,"lens_emission_multiplier":1.0})
	var loaded: Dictionary = await app._load_mvr_scene(source,"mvr",false)
	test.check(loaded.get("ok",false),"Production MVR import/native compilation/renderer setup")
	adapter = app._fixture_light_apply_service._dense_adapter
	runtime = app._dmx_controller._dmx_fixture_runtime
	runtime._native_visual_runtime.set_runtime_now_seconds_for_testing(0)
	runtime._native_visual_runtime.set_performance_trace_enabled(true)
	var fixture_count: int = int(flags[flags.find("--fixtures")+1]) if flags.has("--fixtures") else 1
	test.check(adapter._outputs.size() == count*fixture_count,"Every referenced emitter retains a physical identity")

func packet() -> PackedByteArray:
	var bytes := PackedByteArray(); bytes.resize(512)
	return bytes

func send(packets: Dictionary, now: float) -> Dictionary:
	runtime._native_visual_runtime.set_runtime_now_seconds_for_testing(now)
	for universe in packets: runtime._native_visual_runtime.submit_universe_frame(universe,packets[universe])
	var frame: Dictionary = runtime._native_visual_runtime.consume_latest_visual_frame()
	runtime._sectioned_visual_frame_applier.apply_snapshot(frame,app,app._fixture_light_apply_service,0.016,runtime,runtime._native_fixture_uuids_by_id,runtime._fixture_nodes)
	adapter._native.advance_shutters(adapter._generation,now)
	return frame

func close_scene() -> void:
	test.check(FileAccess.get_sha256(source) == source_hash,"Import/playback never modify the original MVR/GDTF archive")
	app._clear_scene(); app.queue_free()
	await process_frame
	app = null; adapter = null; runtime = null

func run() -> void:
	await open_scene(["--gobo"])
	var primary := packet(); primary[0] = 255; primary[1] = 255
	var cells := packet(); cells.fill(10)
	send({0:primary,2:cells},0)
	var baseline: Array = Probe.capture(adapter)
	Probe.check(self,baseline,0,1.0)
	var revision: int = app._active_beam_renderer._resource_revision
	cells[0] = 119; cells[1] = 20; cells[2] = 120; cells[3] = 160
	send({2:cells},1.0)
	var source_evaluations: int = runtime._native_visual_runtime.get_stats().source_programs_evaluated
	for now in [1.08,2.08,5.08]:
		adapter._native.advance_shutters(adapter._generation,now)
		Probe.check(self,baseline,0,1.0)
		Probe.check(self,baseline,1,0.0)
	test.check(runtime._native_visual_runtime.get_stats().source_programs_evaluated == source_evaluations,"Seconds of autonomous 10 Hz hold create no new physical source evaluations")
	adapter._native.advance_shutters(adapter._generation,1.125)
	Probe.check(self,baseline,0,0.0)
	Probe.check(self,baseline,2,0.5)
	Probe.check(self,baseline,3,0.0) # PulseOpen: duty 50%, end offset 75%.
	adapter._native.advance_shutters(adapter._generation,1.25)
	Probe.check(self,baseline,2,1.0)
	Probe.check(self,baseline,3,0.5)
	var unchanged: Dictionary = send({2:cells},1.25)
	test.check(unchanged.get("descriptors",PackedInt32Array()).is_empty(),"Identical DMX does not reset or republish temporal state")
	adapter._native.advance_shutters(adapter._generation,1.375)
	Probe.check(self,baseline,2,0.5)
	cells[0] = 20
	var changed: Dictionary = send({2:cells},1.425)
	var temporal: Dictionary = Probe.parameters(changed,adapter._outputs[cell_index(0)].canonical_id)
	test.check_close(temporal.phase,0.25,0.00001,"Frequency edit preserves accumulated phase")
	test.check_close(temporal.frequency,2,0.00001,"PhysicalFrom mapping follows selected ChannelFunction range")
	cells[0] = 10; cells[1] = 0; cells[2] = 200
	send({2:cells},2)
	app._apply_visual_settings({"lens_emission_multiplier":2.0})
	adapter._native.advance_shutters(adapter._generation,2.125)
	test.check(adapter._native.shutter_values()[cell_index(1)] == 0.0,"Lens gain edits never open a closed shutter or change temporal phase")
	app._apply_visual_settings({"lens_emission_multiplier":1.0})
	adapter._native.advance_shutters(adapter._generation,2.125)
	Probe.check(self,baseline,0,1.0)
	Probe.check(self,baseline,1,0.0)
	adapter._native.advance_shutters(adapter._generation,2.125)
	Probe.check(self,baseline,2,0.75)
	cells[4] = 240
	var random_frame: Dictionary = send({2:cells},3)
	var unsupported: Dictionary = Probe.parameters(random_frame,adapter._outputs[cell_index(4)].canonical_id)
	test.check(unsupported.mode == 9 and unsupported.status == 1,"Random shutter is an explicit deterministic visual approximation")
	Probe.check(self,baseline,4,0.0)
	cells[4] = 250
	var unknown_frame: Dictionary = send({2:cells},3.1)
	var unknown: Dictionary = Probe.parameters(unknown_frame,adapter._outputs[cell_index(4)].canonical_id)
	test.check(unknown.mode == -1 and unknown.status == 2,"Unknown manufacturer shutter polarity stays explicitly unsupported")
	Probe.check(self,baseline,4,1.0)
	for now in [3.01,3.08,3.11,4.08,8.08]: adapter._native.advance_shutters(adapter._generation,now)
	Probe.resources(self,baseline)
	test.check(app._active_beam_renderer._resource_revision == revision,"No flash recreates beam/gobo resources")
	var registry: RefCounted = app._native_target_registry._gobo_resources
	var target: int = adapter._outputs[cell_index(0)].canonical_id
	var clock: int = Time.get_ticks_usec()
	var phase: float = registry.current_phase_degrees(target,1,clock)
	registry.advance_motion_at_usec(clock+500000,app._native_target_registry._dimmer_targets)
	test.check_close(fposmod(registry.current_phase_degrees(target,1,clock+500000)-phase,360.0),15.0,0.001,"Gobo PosRotate advances exactly 30 degrees/s independently during shutter hold")
	app._apply_visual_settings({"footprint_backend":"native"})
	adapter._native.advance_shutters(adapter._generation,2.125)
	test.check(adapter._outputs[cell_index(1)].lights[0].light.light_energy == 0.0,"Existing Native gobo projector energy is zero for a closed shutter")
	test.check(adapter._outputs[cell_index(0)].lights[0].light.light_energy > 0.0,"Open preserves the existing Native projector path")
	var native_light = adapter._outputs[cell_index(2)].lights[0].light
	test.check(native_light.light_projector != null,"Native diagnostic/reference footprint retains its existing gobo projector texture")
	var texture: Texture2D = native_light.light_projector
	test.check_close(native_light.light_energy,baseline[cell_index(2)].physical[5]*adapter._surface_multiplier*0.75,0.001,"Native gobo footprint uses the same pulse envelope")
	adapter._native.advance_shutters(adapter._generation,2.25)
	test.check(native_light.light_projector == texture,"Native projector resources remain identical while the pulse advances")
	var old_generation: int = adapter._generation
	app._visual_settings["beam_render_mode"] = 1
	app._update_beam_renderer_mode(false); adapter.refresh_renderer()
	adapter._native.advance_shutters(adapter._generation,2.125)
	test.check(adapter._native.shutter_values()[cell_index(1)] == 0.0,"Renderer replacement restores a held closed shutter")
	app._fixture_light_apply_service.set_render_diagnostic_mode("no-beams")
	adapter._native.advance_shutters(adapter._generation,2.2)
	app._fixture_light_apply_service.set_render_diagnostic_mode("full")
	adapter._native.advance_shutters(adapter._generation,2.125)
	test.check_close(adapter._native.shutter_values()[cell_index(2)],0.75,0.00001,"Suppression/resume retains the logical phase")
	var retired_native: RefCounted = adapter._native
	await app._load_mvr_scene(source,"mvr",false)
	adapter = app._fixture_light_apply_service._dense_adapter
	test.check(retired_native.get_sizes().shutter_layers == 0 and retired_native.advance_shutters(old_generation,2.125) == -1,"Reload clears retired temporal state and resource routes")
	test.check(adapter._native.advance_shutters(old_generation+1000,2.125) == -1,"Stale renderer generation cannot advance retired shutter bindings")
	await close_scene()
	await preload("res://tests/gdscript/helpers/shutter_fidelity_probe.gd").run(self)
	await split_modes()
	await shared_groups()
	await absent_shutter()
	await preload("res://tests/gdscript/helpers/shutter_stress_probe.gd").run(self)
	test.finish(self)

func split_modes() -> void:
	await open_scene(["--split"],8)
	var primary := packet(); primary[0] = 255; primary[2] = 255
	var cells := packet()
	for cell in range(8): cells[cell*3] = 10; cells[cell*3+1] = 255; cells[cell*3+2] = 51
	send({0:primary,2:cells},0)
	var baseline: Array = Probe.capture(adapter)
	cells[0] = 20; cells[3] = 120
	send({2:cells},1)
	adapter._native.advance_shutters(adapter._generation,1.095)
	Probe.check(self,baseline,0,1)
	adapter._native.advance_shutters(adapter._generation,1.08)
	Probe.check(self,baseline,0,0)
	adapter._native.advance_shutters(adapter._generation,1.025)
	Probe.check(self,baseline,1,0.5)
	cells[0] = 0
	send({2:cells},2)
	Probe.check(self,baseline,0,0)
	cells[0] = 10
	send({2:cells},3)
	Probe.check(self,baseline,0,1)
	await close_scene()

func shared_groups() -> void:
	await open_scene(["--shared","--shutter-index","12"],32)
	var values := packet(); values[0] = 255; values[3] = 255; values[4] = 10
	send({0:values},0)
	var groups: Dictionary = adapter.diagnostics()
	test.check(groups.godot_accepted_aggregates > 0,"Proven identical shared shutter preserves an existing aggregate")
	values[4] = 119
	send({0:values},1)
	adapter._native.advance_shutters(adapter._generation,1.08)
	for row in adapter._render_bindings.rows:
		for handle in row.output.lights: test.check(handle.beam.visible,"Shared strobe opens the retained aggregate")
	adapter._native.advance_shutters(adapter._generation,1.11)
	for row in adapter._render_bindings.rows:
		for handle in row.output.lights: test.check(not handle.beam.visible,"Shared strobe closes the retained aggregate")
	await close_scene()

func cell_index(cell: int) -> int:
	for index in range(adapter._binding_records.size()):
		if str(adapter._binding_records[index].geometry_key).ends_with("/Cell%d/Cell/Pixel" % cell): return index
	return -1

func absent_shutter() -> void:
	await open_scene(["--absent"],8)
	var values := packet(); values[0] = 255; values[1] = 255
	send({0:values},0)
	var baseline: Array = Probe.capture(adapter)
	var counts: Dictionary = adapter._native.get_sizes()
	var image: Image
	if RenderingServer.get_rendering_device() != null:
		RenderingServer.force_draw()
		image = root.get_texture().get_image()
	for now in [0.0,0.075,1.0,10.0]:
		test.check(adapter._native.advance_shutters(adapter._generation,now) == 0,"Absent shutter has zero temporal output work")
	Probe.resources(self,baseline)
	for index in range(8): Probe.check(self,baseline,index,1.0)
	test.check(adapter._native.get_sizes().shutter_beam_writes == counts.shutter_beam_writes and counts.shutter_layers == 0,"Absent shutter leaves every presentation resource untouched")
	if image != null:
		RenderingServer.force_draw()
		test.check(image.get_data() == root.get_texture().get_image().get_data(),"Absent shutter preserves the exact rendered image")
		print("SHUTTER_GRAPHICS Forward+/Vulkan image equivalence passed")
	else: print("SHUTTER_GRAPHICS skipped: headless RenderingServer has no rendering device")
	await close_scene()
