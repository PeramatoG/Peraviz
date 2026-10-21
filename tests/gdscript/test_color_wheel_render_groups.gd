extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()
var app: Node
var runtime: RefCounted
var adapter: RefCounted
var service: RefCounted
var dmx := PackedByteArray()
var wheel_rows: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _load(wheel: String, pixels: bool = false, load_case: bool = false, selected_mode: String = "") -> void:
	var path: String = ProjectSettings.globalize_path("user://wheel_%s_%s_%s.mvr" % [wheel,pixels,load_case])
	var args := PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_render_group_fixture.py"),path,"--wheel="+wheel])
	if not selected_mode.is_empty(): args.append("--mode="+selected_mode)
	if pixels: args.append("--pixels")
	if load_case: args.append("--load")
	test.check(OS.execute("python3",args) == 0,"Representative standard Color-wheel MVR is generated")
	var imported: Dictionary = app._load_mvr_scene(path,"mvr",false)
	test.check(imported.get("ok",false),"Normal MVR import succeeds")
	service = app._fixture_light_apply_service
	runtime = app._dmx_controller._dmx_fixture_runtime
	service.set_performance_trace_enabled(true)
	runtime._sectioned_visual_frame_applier.set_performance_trace_enabled(true)
	adapter = service._dense_adapter
	wheel_rows.clear()

func _apply() -> void:
	runtime._native_visual_runtime.submit_universe_frame(0,dmx)
	var frame: Dictionary = runtime._native_visual_runtime.consume_latest_visual_frame()
	var descriptors: PackedInt32Array = frame["descriptors"]
	var integers: PackedInt32Array = frame["integers"]
	for offset in range(0,descriptors.size(),5):
		if descriptors[offset] != 5: continue
		for row in range(descriptors[offset+1]):
			var base: int = descriptors[offset+2]+row*8
			wheel_rows[integers[base+1]] = [integers[base+3],integers[base+4],integers[base+5],integers[base+7]]
	if not descriptors.is_empty(): runtime._sectioned_visual_frame_applier.apply_snapshot(frame,app,service,0.016,runtime,runtime._native_fixture_uuids_by_id,runtime._fixture_nodes)
	await process_frame

func _check_physical_and_lenses(slot: int) -> void:
	for output in adapter._outputs:
		test.check(wheel_rows.has(output.canonical_id) and wheel_rows[output.canonical_id][0] == 0 and wheel_rows[output.canonical_id][1] == slot and wheel_rows[output.canonical_id][2] == slot,"Every physical WheelSelection keeps its canonical ID, mode and exact seated slot")
		var values: PackedFloat32Array = adapter._native.physical_values(output.index)
		for material in output.materials:
			var lens: PackedFloat32Array = adapter._native.material_values(material.rid)
			test.check(is_equal_approx(lens[0],values[1]) and is_equal_approx(lens[1],values[2]) and is_equal_approx(lens[2],values[3]) and is_equal_approx(lens[3],values[7]*material.scale),"Physical lenses retain composed Color and gain behind the aggregate")

func _check_shared_shaft() -> void:
	var row: RefCounted
	for candidate in adapter._render_bindings.rows:
		if candidate.presentation_class == 1:
			row = candidate
			break
	var physical: PackedFloat32Array = adapter._native.physical_values(row.members[0])
	var shaft: Color = row.output.lights[0].beam.get_instance_shader_parameter("beam_dynamic_state")
	var expected_intensity: float = 0
	for index in row.members: expected_intensity += adapter._native.physical_values(index)[6]
	test.check(absf(shaft.a-clampf(expected_intensity,0,50)*adapter._shaft_multiplier)<0.002,"Aggregate intensity includes exact physical Dimmer and Color gain without double scaling")
	test.check(absf(shaft.r-physical[1])<0.001 and absf(shaft.g-physical[2])<0.001 and absf(shaft.b-physical[3])<0.001,"Uniform wheel Color reaches the real aggregate shader exactly once")

func _run() -> void:
	test.check(change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) == OK,"Normal application scene loads")
	await process_frame
	await process_frame
	app = current_scene
	app._visual_settings["enable_realtime_spotlights"] = false
	app._visual_settings["beam_presentation"] = 1
	app._visual_settings["beam_render_mode"] = 0
	app._update_beam_renderer_mode(true)
	dmx.resize(512)
	_load("select",false,true)
	var sizes: Dictionary = adapter.diagnostics()
	test.check(sizes["physical_outputs"] == 1000 and sizes["render_rows"] == 20 and sizes["aggregated_members"] == 1000 and sizes["control_groups"] == 20,"Twenty normal-imported Color-wheel heads retain 1000 physical outputs and bind 20 real aggregates")
	if sizes["aggregated_groups"] != 20:
		print("TEST FAILURE: Wheel imports failed to aggregate: ",sizes)
		app.queue_free()
		await process_frame
		quit(1)
		return
	test.check(sizes["unique_lens_material_rids"] > 0,"Real imported lens meshes participate in production material binding")
	dmx.fill(0)
	for f in range(20):
		dmx[f*16] = 200
		dmx[f*16+3] = 160
		for color in range(3): dmx[f*16+4+color] = 255
	await _apply()
	_check_physical_and_lenses(1)
	adapter.consume_diagnostics()
	for f in range(20): dmx[f*16+7] = 80
	await _apply()
	_check_physical_and_lenses(2)
	_check_shared_shaft()
	var counts: Dictionary = adapter.consume_diagnostics()
	test.check(counts["visible_member_shafts"] == 0 and counts["visible_aggregate_shafts"] == 20 and counts["renderer_outputs_processed"] == 20 and counts["actual_beam_dynamic_renderer_writes"] == 20,"A live Color wheel change updates 20 visible aggregate shafts while all 1000 member shafts stay hidden")
	test.check(counts["optics_apply_calls"] == 0 and counts["beam_topology_rebuilt"] == 0 and counts["beam_visibility_writes"] == 0,"Seated Color wheel changes never rebuild optics/topology or toggle visible shafts")
	var old_light: SpotLight3D = adapter._render_bindings.aggregate_outputs()[0].lights[0].light
	adapter.refresh_renderer()
	test.check(not is_instance_valid(old_light) and adapter.diagnostics()["visible_aggregate_shafts"] == 20,"Renderer replacement retires aggregates and replays held wheel Color")
	_check_shared_shaft()
	for cycle in range(3):
		for f in range(20): dmx[f*16] = 0
		await _apply()
		for f in range(20): dmx[f*16+7] = 144 if cycle%2 == 0 else 80
		await _apply()
		for f in range(20): dmx[f*16] = 200
		await _apply()
		_check_shared_shaft()
		test.check(adapter.diagnostics()["visible_member_shafts"] == 0,"Held wheel Color survives repeated Dimmer zero crossings without reviving member shafts")
	for f in range(20): dmx[f*16+7] = 220
	await _apply()
	test.check(adapter.diagnostics()["visible_aggregate_shafts"] == 0 and adapter._native.physical_values(0)[10] == 0,"A closed filter preserves exact zero Color gain and aggregate blackout")
	for f in range(20): dmx[f*16+7] = 0
	await _apply()
	test.check(adapter.diagnostics()["visible_aggregate_shafts"] == 20,"Leaving wheel blackout restores held Dimmer without another Dimmer packet")
	var aggregate: SpotLight3D = adapter._render_bindings.aggregate_outputs()[0].lights[0].light
	var transform: Transform3D = aggregate.global_transform
	dmx[1] = 190
	await _apply()
	test.check(aggregate.global_transform != transform,"Color-wheel aggregate inherits the original mechanical Pan chain")
	transform = aggregate.global_transform
	dmx[2] = 130
	await _apply()
	test.check(aggregate.global_transform != transform,"Color-wheel aggregate retains mechanical Tilt inheritance")
	_load("select",true)
	test.check(not is_instance_valid(aggregate) and adapter.diagnostics()["control_groups"] == 51 and adapter.diagnostics()["render_rows"] == 2,"Scene replacement retains independent pixel authorities and retires old aggregates")
	dmx.fill(0)
	dmx[0] = 200
	dmx[3] = 160
	for i in range(50): dmx[4+i*3+(0 if i<25 else 2)] = 255
	await _apply()
	var mixed: Color = adapter._render_bindings.aggregate_outputs()[0].lights[0].beam.get_instance_shader_parameter("beam_dynamic_state")
	test.check(absf(mixed.r-0.735357)<0.005 and absf(mixed.b-0.735357)<0.005,"Independent pixels under an open Color wheel retain linear-light aggregate mixing")
	dmx[154] = 80
	await _apply()
	var red: int = 0
	var dark: int = 0
	for output in adapter._outputs:
		if not output.lights[0].projected: continue
		var physical: PackedFloat32Array = adapter._native.physical_values(output.index)
		if physical[1]>0.99 and physical[10]>0: red += 1
		if physical[10] == 0: dark += 1
	test.check(red == 25 and dark == 25,"Shared red transmission composes with independent RGB pixels without collapsing their physical state")
	for kind in ["media","facet","gobo","gobo_motion","missing","unknown_slot"]:
		_load(kind)
		var fallback: Dictionary = adapter.diagnostics()
		test.check(fallback["aggregated_groups"] == 0 and fallback["render_rows"] == 51,"Unsupported/spatial wheel or gobo remains individual: "+kind)
	for kind in ["index","spin","random","audio","unknown","fx"]:
		_load(kind)
		test.check(adapter.diagnostics()["render_rows"] == 2,"Uniform resolved Color approximation permits one shaft regardless of unsupported capability: "+kind)
	# Generic concentric-ring geometry and mixed ChannelFunction ranges, authored independently of private assets.
	_load("basic",false,true,"BasicControls")
	test.check(adapter.diagnostics()["physical_outputs"] == 1000 and adapter.diagnostics()["render_rows"] == 20,"Twenty Basic-style ring heads with unlinked FX and Base Color controls retain 1000 canonical outputs and bind 20 combined shafts")
	if adapter.diagnostics()["render_rows"] != 20:
		print("TEST FAILURE: Base Color control regression: ",adapter.diagnostics())
		app.queue_free()
		await process_frame
		test.finish(self)
		return
	var compiled: Dictionary = app._loader.compile_visual_runtime_scene(0)
	test.check(compiled["renderer_manifest"][0]["render_group_diagnostics"]["native_approximate_projected_color_outputs"] == 1000,"Setup identifies accepted approximation without misreporting unsupported effect fidelity")
	var basic_codes: Dictionary = {}
	for diagnostic in compiled["diagnostics"]: basic_codes[diagnostic["code"]] = true
	test.check(not basic_codes.has("PVZ-COLOR-WHEEL-RESOURCE-MISSING") and basic_codes.has("PVZ-COLOR-EFFECT-UNSUPPORTED"),"Unlinked FX remains approximate while unrelated Base Color controls produce no missing-wheel diagnostic")
	var descriptor: Dictionary = compiled["renderer_manifest"][0]["render_emitter_groups"][0]
	test.check(absf(descriptor["aperture_radius"]-0.142)<0.001 and absf(descriptor["packing_density"]-0.80)<0.02 and descriptor["beam_angle"] == 28 and descriptor["field_angle"] == 43.75,"Actual converted native geometry proves enclosure/density and retains Beam/Field angles")
	dmx.fill(0)
	for f in range(20):
		dmx[f*16] = 200
		dmx[f*16+3] = 160
		for color in range(3): dmx[f*16+4+color] = 255
	await _apply()
	for f in range(20): dmx[f*16+7] = 5
	await _apply()
	_check_physical_and_lenses(2)
	_check_shared_shaft()
	for f in range(20): dmx[f*16+9] = 200
	await _apply()
	_check_physical_and_lenses(2)
	_check_shared_shaft()
	test.check(adapter.diagnostics()["render_rows"] == 20,"Base calibration/control DMX changes preserve shaft membership and supported Color")
	for f in range(20):
		dmx[f*16+3] = 220
		dmx[f*16+8] = 128
	await _apply()
	var ring_aggregate: SpotLight3D = adapter._render_bindings.aggregate_outputs()[0].lights[0].light
	test.check(is_equal_approx(adapter._native.physical_values(0)[9],adapter._render_bindings.aggregate_outputs()[0].lights[0].projection.source_full_angle_deg),"Live shared Zoom remains exact on the ring aggregate")
	_check_shared_shaft()
	_load("basic",false,false,"Basic")
	test.check(not is_instance_valid(ring_aggregate) and adapter.diagnostics()["render_rows"] == 2,"Scene replacement retires old aggregate resources while Basic keeps efficient shaft presentation")
	compiled = app._loader.compile_visual_runtime_scene(0)
	test.check(compiled["setup_summary"]["source_program_count"] == 11,"Mixed selected mode retains scalar, wheel selection, Spin and unsupported FX source programs")
	var codes: Dictionary = {}
	for diagnostic in compiled["diagnostics"]: codes[diagnostic["code"]] = true
	test.check(codes.has("PVZ-COLOR-EFFECT-UNSUPPORTED") and codes.has("PVZ-WHEEL-TEMPORAL-UNSUPPORTED"),"Spin first-slot approximation and unsupported FX remain explicit setup diagnostics")
	dmx.fill(0)
	dmx[0] = 200
	dmx[4] = 255
	dmx[5] = 255
	dmx[6] = 255
	dmx[7] = 5
	await _apply()
	_check_physical_and_lenses(2)
	var stable_aggregate: SpotLight3D = adapter._render_bindings.aggregate_outputs()[0].lights[0].light
	adapter.consume_diagnostics()
	dmx[7] = 160
	await _apply()
	_check_shared_shaft()

	for output in adapter._outputs:
		test.check(wheel_rows[output.canonical_id][0] == 2 and wheel_rows[output.canonical_id][1] == 1,"Unsupported Spin preserves the compiled physical mode while explicitly retaining its pre-existing first-slot display limitation")
	dmx[7] = 200
	await _apply()
	_check_shared_shaft()
	for output in adapter._outputs:
		test.check(wheel_rows[output.canonical_id][0] == 5,"Linked unsupported FX retains its own physical binding and explicit unsupported mode")
	test.check(adapter._render_bindings.aggregate_outputs()[0].lights[0].light == stable_aggregate and adapter.diagnostics()["render_rows"] == 2,"Entering unsupported Spin/FX never reclassifies or reconstructs shaft resources")
	dmx[7] = 240
	await _apply()
	for output in adapter._outputs:
		var physical: PackedFloat32Array = adapter._native.physical_values(output.index)
		test.check(physical[1]>0.99 and physical[2]>0.99 and physical[3]>0.99 and physical[10]>0.99,"NoFeature removes the wheel optical layer and restores held additive Color")
	_load("basic",false,false,"Extended")
	test.check(adapter.diagnostics()["render_rows"] == 2 and adapter.diagnostics()["control_groups"] == 4,"Extended mode recomputes independent ring authority while retaining compatible optical aggregation")
	_load("basic",false,false,"ExtendedSeated")
	test.check(adapter.diagnostics()["render_rows"] == 2 and adapter.diagnostics()["control_groups"] == 4,"Ring-level RGB authorities remain distinct even with one optically valid aggregate")
	dmx.fill(0)
	dmx[0] = 200
	dmx[4] = 255
	dmx[8] = 255
	dmx[12] = 255
	await _apply()
	var colors: Dictionary = {}
	for output in adapter._outputs:
		if not output.lights[0].projected: continue
		var physical: PackedFloat32Array = adapter._native.physical_values(output.index)
		var channel: int = 0 if physical[1]>0.99 else 1 if physical[2]>0.99 else 2
		colors[channel] = int(colors.get(channel,0))+1
	test.check(colors.get(0,0)==14 and colors.get(1,0)==16 and colors.get(2,0)==20,"All three independently controlled rings retain exact physical membership and RGB")
	_load("basic",false,false,"Seated")
	test.check(adapter.diagnostics()["render_rows"] == 2 and adapter.diagnostics()["control_groups"] == 2,"Returning to a supported selected mode compiles fresh shared authority and geometry")
	_load("basic",false,false,"BrokenControls")
	compiled = app._loader.compile_visual_runtime_scene(0)
	var broken: Dictionary = compiled["renderer_manifest"][0]["render_group_diagnostics"]
	test.check(adapter.diagnostics()["render_rows"] == 51 and broken["native_accepted_aggregates"] == 0 and broken["native_rejected_physical"].get("wheel_missing_palette",0) == 50,"An actual unresolved Wheel remains individual even alongside unlinked FX and unrelated Base controls")
	app._clear_scene()
	app.queue_free()
	service = null
	runtime = null
	adapter = null
	await process_frame
	await process_frame
	test.finish(self)
