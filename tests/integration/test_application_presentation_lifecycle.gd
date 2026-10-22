extends SceneTree

# Load the real main scene at runtime: do not preload renderer/service dependencies
# in a test-specific order that could hide application compilation failures.
const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()
var app: Node
var service: RefCounted
var runtime: RefCounted
var dmx := PackedByteArray()
var beams: Array[MeshInstance3D] = []
var lights: Array[SpotLight3D] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var fixture: String = args[args.find("--mvr")+1] if args.has("--mvr") else ""
	if fixture.is_empty():
		push_error("Application lifecycle test requires --mvr <generated fixture>")
		quit(1)
		return
	test.check(change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) == OK, "Normal main scene loads")
	await process_frame
	await process_frame
	app = current_scene
	if app == null or not app.has_method("_load_mvr_scene"):
		push_error("Normal application script did not compile/instantiate")
		quit(1)
		return
	app._visual_settings["enable_realtime_spotlights"] = true
	app._visual_settings["beam_presentation"] = 1
	app._visual_settings["beam_render_mode"] = 1 if args.has("--legacy") else 0
	app._update_beam_renderer_mode(true)
	var imported: Dictionary = await app._load_mvr_scene(fixture, "mvr", false)
	test.check(bool(imported.get("ok", false)), "Reference fixture uses normal MVR import path")
	service = app._fixture_light_apply_service
	test.check(service.is_dense_presentation_active(), "Dense production installation is active")
	if not service.is_dense_presentation_active():
		test.finish(self)
		return
	runtime = app._dmx_controller._dmx_fixture_runtime
	test.check(service._dense_adapter._outputs.size() == 2, "Both independent physical outputs bind")
	for output in service._dense_adapter._outputs:
		for handle in output.lights:
			lights.append(handle.light)
	if lights.size() != 2:
		push_error("Expected two real emitter anchors from MVR import")
		quit(1)
		return
	dmx.resize(512)
	await apply_dmx(200, 150, 210, 255, 128, 128, 100, 255)
	for light in lights: beams.append(app._get_beam_resource_for_light(light))
	check_active("Initial full")
	for light in lights:
		app._fixture_gobo_projector.set_presentation_rotation(light,37.0)
		var projector_basis: Basis = light.basis
		app._find_or_create_emitter_light(light.get_parent())
		test.check(light.basis.is_equal_approx(projector_basis), "Cold discovery preserves actual gobo projector rotation")
		app._fixture_gobo_projector.set_presentation_rotation(light,0.0)
	var first_mesh: Mesh = beams[0].mesh
	var first_cache: RefCounted = service._dense_adapter._outputs[0].lights[0].bound_state
	var before_transform: Transform3D = lights[0].global_transform
	var before_zoom: float = lights[0].spot_angle
	await apply_dmx(200, 150, 210, 255, 200, 180, 230, 255)
	test.check(not is_equal_approx(lights[0].spot_angle,before_zoom), "Zoom changes actual SpotLight angle")
	test.check(lights[0].global_transform != before_transform, "Pan/tilt reach the real emitter transform")
	service._dense_adapter.consume_diagnostics()
	for i in range(90):
		if i == 30: app._visual_settings["enable_realtime_spotlights"] = false
		await apply_dmx(120+i%100, 40+i%150, 210-i%100, 255, 200, 180, 230, 255)
		for light in lights:
			test.check(app._find_or_create_emitter_light(light.get_parent()) == light, "Cold light discovery preserves identity")
		check_active("Continuous active playback")
		for index in range(lights.size()):
			test.check(app._get_beam_resource_for_light(lights[index]) == beams[index], "Color/intensity preserves bound MeshInstance identity")
	var stable: Dictionary = service._dense_adapter.consume_diagnostics()
	for key in ["beam_initializations", "beam_initialization_succeeded", "beam_initialization_failed", "beam_resource_rebounds", "beam_topology_rebuilt"]:
		test.check(int(stable[key]) == 0, "Steady state does not initialize/rebind/rebuild: "+key)
	test.check(service._dense_adapter._outputs[0].lights[0].bound_state == first_cache, "Bound cache survives playback")
	test.check(beams[0].mesh != null and first_mesh != null, "Both initial/current beam topology are real resources")
	app._visual_settings["enable_realtime_spotlights"] = true
	await apply_dmx(0, 130, 120, 255, 200, 180, 230, 255)
	check_hidden("Blackout")
	await apply_dmx(200, 130, 120, 255, 200, 180, 230, 255)
	check_active("Dimmer-only reactivation")
	runtime.set_render_diagnostic_mode("no-beams")
	service.set_render_diagnostic_mode("no-beams")
	check_hidden("No-beams")
	await apply_dmx(210, 80, 190, 230, 200, 180, 230, 0)
	check_hidden("Suppressed open gobo")
	runtime.set_render_diagnostic_mode("full")
	service.set_render_diagnostic_mode("full")
	check_active("Full restores current held open state without DMX", false)
	await apply_dmx(210, 80, 190, 230, 200, 180, 230, 255)
	check_active("Reselected gobo")
	# External visibility and renderer/settings refresh must preserve footprint lifetime.
	app.proxies_root.visible = false
	app.proxies_root.visible = true
	check_active("Ancestor visibility restoration")
	app._on_visual_settings_changed(app._visual_settings.duplicate())
	check_active("Renderer refresh without new DMX")
	service._dense_adapter.consume_diagnostics()
	await apply_dmx(210, 80, 190, 230, 200, 180, 230, 255)
	var unchanged: Dictionary = service._dense_adapter.consume_diagnostics()
	for key in ["spot_node_visibility_writes", "spot_rid_visibility_writes", "beam_visibility_writes", "beam_shader_parameter_writes", "material_parameter_writes"]:
		test.check(int(unchanged[key]) == 0, "Identical real application state has zero redundant writes: "+key)
	var trace: RefCounted = load("res://scripts/runtime/performance_trace_snapshot.gd").new()
	var sample: Dictionary = trace.collect(app,runtime._native_visual_runtime)
	test.check(sample.get("dense_presentation_active",false) and sample.has("dense_presentation"), "Stability trace explicitly confirms active dense installation")
	for key in ["apply_target_states", "apply_committed_output_states"]:
		test.check(int(sample["legacy_compatibility"]["sizes"].get(key,-1)) == 0, "Legacy state owner remains empty: "+key)
	print("[peraviz-stability] ", sample)
	if test.failures.is_empty(): print("Application presentation lifecycle passed: actual beams, footprints, gobos, blackout and held restoration checked.")
	app._clear_scene()
	app.queue_free()
	service = null
	runtime = null
	beams.clear()
	lights.clear()
	await process_frame
	test.finish(self)

func apply_dmx(dimmer: int, red: int, green: int, blue: int, pan: int, tilt: int, zoom: int, gobo: int) -> void:
	for base in [0,16]:
		for offset in range(8): dmx[base+offset] = [dimmer,red,green,blue,pan,tilt,zoom,gobo][offset]
	runtime._native_visual_runtime.submit_universe_frame(0,dmx)
	service.set_performance_trace_enabled(runtime._performance_trace_enabled)
	var frame: Dictionary = service.consume_native_snapshot(runtime._native_visual_runtime, runtime._sectioned_visual_frame_applier.schema_generation())
	test.check(bool(frame.get("native_presentation", false)), "Direct native transaction accepts the installed generations")
	var descriptors: PackedInt32Array = frame.get("descriptors", PackedInt32Array())
	for base in range(0, descriptors.size(), 5):
		test.check(descriptors[base] not in [2,3,4], "Intermediate lighting scalars stay native")
	runtime._sectioned_visual_frame_applier.apply_snapshot(frame,app,service,0.016,runtime,runtime._native_fixture_uuids_by_id,runtime._fixture_nodes)
	await process_frame

func check_active(context: String, gobo: bool = true) -> void:
	for i in range(lights.size()):
		var light: SpotLight3D = lights[i]
		var beam: MeshInstance3D = app._get_beam_resource_for_light(light)
		test.check(beam != null and beam.mesh != null and beam.material_override != null,context+": actual beam resources exist")
		if beam == null: continue
		test.check(beam.visible and beam.is_visible_in_tree(),context+": actual beam is visible in tree")
		var params: Dictionary = light.get_meta("peraviz_beam_last_params",{})
		test.check(is_equal_approx(float(params.get("normalized_dimmer",-1)),float(dmx[0])/255.0), context+": held dimmer follows native DMX")
		var color: Color = params.get("beam_color",Color.BLACK)
		if int(app._visual_settings["beam_render_mode"]) == 0:
			var dynamic: Variant = beam.get_instance_shader_parameter("beam_dynamic_state")
			test.check(dynamic is Color and is_equal_approx((dynamic as Color).a,float(params["scaled_intensity"])) and dynamic.a > 0.015,context+": actual shader intensity follows held state")
			if dynamic is Color:
				test.check(Vector3(dynamic.r,dynamic.g,dynamic.b).is_equal_approx(Vector3(color.r,color.g,color.b)),context+": actual shader color follows held DMX")
		else:
			test.check(beam.get_instance_shader_parameter("beam_color") == color, context+": actual legacy shader color follows held state")
			test.check(float(beam.get_instance_shader_parameter("near_emission")) > 0.0, context+": actual legacy shader emission is active")
		test.check(light.visible and light.is_visible_in_tree() and light.light_energy > 0.0,context+": actual footprint Node and energy are active")
		test.check(service._dense_adapter._outputs[i].lights[0].realtime_visible,context+": footprint RID remains enabled")
		test.check((light.light_projector != null) == gobo,context+": actual projector follows gobo selection")

func check_hidden(context: String) -> void:
	for i in range(lights.size()):
		var beam: MeshInstance3D = app._get_beam_resource_for_light(lights[i])
		test.check(beam != null and not beam.visible,context+": actual beam hides")
		test.check(not service._dense_adapter._outputs[i].lights[0].realtime_visible,context+": footprint RID disables")
