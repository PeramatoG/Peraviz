extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()
var owner_check_pending: bool = false
var app: Node
var service: RefCounted
var runtime: RefCounted
var adapter: RefCounted
var dmx := PackedByteArray()
var last_setup_us: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _generate(pixels: bool, load_case: bool = false, independent: bool = false) -> String:
	var path: String = ProjectSettings.globalize_path("user://render_group_%s_%s.mvr" % [str(pixels), str(load_case)])
	var args := PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_render_group_fixture.py"), path])
	if pixels: args.append("--pixels")
	if load_case: args.append("--load")
	if independent: args.append("--independent")
	if independent: args.append("--apertures")
	test.check(OS.execute("python3", args) == 0, "Standard MVR/GDTF synthetic fixture is generated")
	return path

func _load(path: String) -> void:
	var setup_start: int = Time.get_ticks_usec()
	var imported: Dictionary = await app._load_mvr_scene(path, "mvr", false)
	test.check(bool(imported.get("ok", false)), "Production MVR import succeeds")
	service = app._fixture_light_apply_service
	service.set_performance_trace_enabled(true)
	runtime = app._dmx_controller._dmx_fixture_runtime
	runtime._native_visual_runtime.set_performance_trace_enabled(true)
	runtime._sectioned_visual_frame_applier.set_performance_trace_enabled(true)
	adapter = service._dense_adapter
	last_setup_us = Time.get_ticks_usec() - setup_start
	owner_check_pending = true
	test.check(adapter != null and service.is_dense_presentation_active(), "Production native renderer installation succeeds")

# Test-only waiting drives the same nonblocking production poll without submitting another packet.
func _completed() -> Dictionary:
	var frame: Dictionary = service.consume_native_snapshot(runtime._native_visual_runtime, runtime._sectioned_visual_frame_applier.schema_generation())
	var deadline: int = Time.get_ticks_msec() + 5000
	while frame.get("pending", false) and Time.get_ticks_msec() < deadline:
		await process_frame
		frame = service.consume_native_snapshot(runtime._native_visual_runtime, runtime._sectioned_visual_frame_applier.schema_generation(), true)
	test.check(not frame.get("pending", false), "Native snapshot completes while polling without fresh DMX")
	return frame

class StoppedReceiver extends RefCounted:
	func is_running() -> bool: return false

func _apply() -> void:
	runtime._native_visual_runtime.submit_universe_frame(0, dmx)
	var frame: Dictionary
	if owner_check_pending:
		# Retain the existing semantic-owner assertion once; subsequent playback uses the direct transaction.
		frame = runtime._native_visual_runtime.consume_latest_visual_frame()
	else:
		frame = await _completed()
		test.check(bool(frame.get("native_presentation", false)), "Direct native render-group transaction succeeds")
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
	if frame.get("native_presentation", false) or not (frame.get("descriptors", PackedInt32Array()) as PackedInt32Array).is_empty():
		runtime._sectioned_visual_frame_applier.apply_snapshot(frame, app, service, 0.016, runtime, runtime._native_fixture_uuids_by_id, runtime._fixture_nodes)
	await process_frame

# A cold synchronous binding probe extends the same renderer workload; it uses no alternate lighting evaluator.
func _check_native_binding_boundary(source: MeshInstance3D) -> void:
	var beam := MeshInstance3D.new()
	beam.mesh = source.mesh
	beam.material_override = source.material_override
	root.add_child(beam)
	var native: Object = ClassDB.instantiate("PeravizPresentationState")
	var generation: int = native.install(PackedInt32Array([1]), PackedFloat32Array([1.0]), PackedInt32Array([2,11,0,3,12,0]))
	native.install_render_rows(PackedInt32Array([0]), PackedInt32Array([0]))
	var objects := PackedInt64Array([beam.get_instance_id()])
	var thresholds := PackedFloat64Array([0.015])
	test.check(not native.install_beams(generation+1, objects, thresholds), "Stale generation cannot install renderer handles")
	test.check(native.install_beams(generation, objects, thresholds), "Current renderer generation admits weak indexed handles")
	native.set_beam_policy(true, 1.1)
	var initial: Dictionary = native.compose(generation, PackedInt32Array([2,1,0,0,0]), PackedInt32Array([1,11,2]), PackedFloat32Array([0.5,10,8,10,2]), true)
	test.check(initial["script_count"] == 1, "Initial geometry/topology remains an exact script fallback")
	var color: Dictionary = native.compose(generation, PackedInt32Array([3,1,0,0,0]), PackedInt32Array([1,12,4]), PackedFloat32Array([0.2,0.4,0.8,1]), true)
	var values: PackedFloat32Array = native.physical_values(0)
	test.check(color["script_count"] == 0 and color["native_beam_applied"] == 1, "Synchronous native publication executes the same batch")
	test.check(beam.get_instance_shader_parameter("beam_dynamic_state") == Color(values[1], values[2], values[3], clampf(values[6]*1.1,0.0,50.0)), "Non-integer presentation scale preserves the reference float conversion")
	beam.free()
	var stale: Dictionary = native.compose(generation, PackedInt32Array([3,1,0,0,0]), PackedInt32Array([1,12,4]), PackedFloat32Array([0.8,0.4,0.2,1]), true)
	test.check(stale["script_count"] == 1 and stale["native_beam_stale"] == 1 and native.get_sizes()["native_beam_bindings"] == 0, "Freed weak handles retire safely and nominate the authoritative fallback")
	native.clear()

# Inspect actual native GPU data against authoritative held physical values, not a second lighting evaluator.
func _check_lens_instances(expected: bool) -> void:
	var batch_owner = adapter._lens_batches
	var sizes: Dictionary = adapter._native.get_sizes()
	if not expected:
		test.check(sizes["gpu_lens_instances"] == 0 and batch_owner.members.is_empty(), "Reference/policy fallback owns no GPU lens routes")
		return
	test.check(sizes["gpu_lens_instances"] >= 900 and sizes["gpu_lens_batches"] > 0, "Approximately one thousand independently controlled apertures enter production MultiMesh batches")
	var visited: Dictionary = {}
	for output_index in batch_owner.members:
		var location: Vector2i = batch_owner.members[output_index]
		var data: PackedFloat32Array = adapter._native.lens_buffer(location.x)
		var physical: PackedFloat32Array = adapter._native.physical_values(output_index)
		var base: int = location.y * 16
		var mesh: MeshInstance3D = batch_owner.batches[location.x].entries[location.y].mesh
		var scale: float = adapter._outputs[output_index].materials[0].scale
		test.check(mesh.layers == 0 and mesh.visible, "Instanced source retains identity, picking children and local visibility with no duplicate draw layer")
		test.check(not visited.has(location), "Every admitted canonical output has one unique stable GPU slot")
		visited[location] = true
		test.check(data[base+12] == physical[1] and data[base+13] == physical[2] and data[base+14] == physical[3] and is_equal_approx(data[base+15], physical[7]*scale), "GPU instance custom data equals independent native Color and material energy")
		var node: MultiMeshInstance3D = batch_owner.batches[location.x].node
		var transform := Transform3D(Basis(Vector3(data[base],data[base+4],data[base+8]),Vector3(data[base+1],data[base+5],data[base+9]),Vector3(data[base+2],data[base+6],data[base+10])),Vector3(data[base+3],data[base+7],data[base+11]))
		test.check((node.global_transform*transform).is_equal_approx(mesh.global_transform), "Batch instance inherits the same mechanical ancestor and exact local lens transform")

# Optional real graphics probe reuses production resources/data with separated probe placement.
# It measures actual viewport submissions; software-renderer timing is never a GPU performance claim.
func _lens_graphics_probe() -> void:
	if not "--render-lens-probe" in OS.get_cmdline_user_args(): return
	for universe in range(10):
		dmx.fill(0)
		for fixture in range(2):
			var base: int = fixture*256
			dmx[base+3] = 160
			for emitter in range(50):
				var index: int = (universe*2+fixture)*50+emitter
				dmx[base+4+emitter*4] = 30+(index*23)%220
				for component in range(3): dmx[base+5+emitter*4+component] = 25+(index*17+component*63)%225
		runtime._native_visual_runtime.submit_universe_frame(universe,dmx)
	var frame: Dictionary = await _completed()
	runtime._sectioned_visual_frame_applier.apply_snapshot(frame,app,service,0.016,runtime,runtime._native_fixture_uuids_by_id,runtime._fixture_nodes)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512,512)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14.0
	camera.position = Vector3(6.2,20,6.2)
	camera.look_at(Vector3(6.2,0,6.2), Vector3.FORWARD)
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	viewport.add_child(environment)
	var images: Array[Image] = []
	var stats: Array = []
	for instanced in [false,true]:
		if instanced: OS.unset_environment("PERAVIZ_GPU_LENSES")
		else: OS.set_environment("PERAVIZ_GPU_LENSES","0")
		adapter.refresh_renderer() # Replays held values into reference RIDs or the actual native instance buffer.
		var holder := Node3D.new()
		viewport.add_child(holder)
		var members: Dictionary = adapter._lens_batches.members
		for index in range(adapter._outputs.size()):
			if members.has(index): continue
			var entry: Dictionary = adapter._binding_records[index]["lens_material_targets"][0]
			var mesh := MeshInstance3D.new()
			mesh.mesh = entry.mesh.mesh
			mesh.material_override = entry.material
			mesh.transform = _probe_transform(index)
			holder.add_child(mesh)
		for batch_index in range(adapter._lens_batches.batches.size()):
			var source = adapter._lens_batches.batches[batch_index]
			var mesh := MultiMeshInstance3D.new()
			mesh.multimesh = MultiMesh.new()
			mesh.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			mesh.multimesh.use_custom_data = true
			mesh.multimesh.mesh = source.node.multimesh.mesh
			mesh.multimesh.instance_count = source.entries.size()
			mesh.material_override = source.node.material_override
			var data: PackedFloat32Array = adapter._native.lens_buffer(batch_index)
			for slot in range(source.entries.size()):
				var t: Transform3D = _probe_transform(source.entries[slot].output)
				var transform := PackedFloat32Array([t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x,t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y,t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z])
				for component in range(12): data[slot*16+component] = transform[component]
			mesh.multimesh.buffer = data
			holder.add_child(mesh)
		for _rendered_frame in range(4): await RenderingServer.frame_post_draw
		images.append(viewport.get_texture().get_image())
		stats.append({"instanced": instanced, "objects": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_OBJECTS_IN_FRAME), "draw_calls": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME), "primitives": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
		holder.free()
	var max_error: float = 0.0
	var lit_pixels: int = 0
	for y in range(images[0].get_height()):
		for x in range(images[0].get_width()):
			var reference: Color = images[0].get_pixel(x,y)
			var actual: Color = images[1].get_pixel(x,y)
			if reference.r+reference.g+reference.b > 0.05: lit_pixels += 1
			max_error = maxf(max_error,maxf(absf(reference.r-actual.r),maxf(absf(reference.g-actual.g),absf(reference.b-actual.b))))
	test.check(lit_pixels > 1000 and max_error == 0.0, "Real graphics backend preserves reference lens pixels, including nonempty independent colors")
	test.check(stats[1].draw_calls < stats[0].draw_calls, "RenderingServer reports fewer actual draw calls for admitted apertures")
	print("GPU_LENS_GRAPHICS ", JSON.stringify({"renderer": RenderingServer.get_video_adapter_name(), "reference": stats[0], "instanced": stats[1], "max_pixel_error":max_error,"lit_pixels":lit_pixels}))
	viewport.free()

func _probe_transform(index: int) -> Transform3D:
	return Transform3D(Basis.IDENTITY.scaled(Vector3(3,3,3)),Vector3((index%32)*0.4,0,floorf(float(index)/32.0)*0.4))

func _aggregate() -> RefCounted:
	return adapter._render_bindings.aggregate_outputs()[0]

func _run() -> void:
	if "--render-lens-probe" in OS.get_cmdline_user_args(): root.disable_3d = true
	var lazy_expected: bool = OS.get_environment("PERAVIZ_LAZY_AGGREGATE_SHAFTS") != "0"
	test.check(change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) == OK, "Normal application scene loads")
	await process_frame
	await process_frame
	app = current_scene
	app._visual_settings["enable_realtime_spotlights"] = false
	app._visual_settings["beam_presentation"] = 1
	app._visual_settings["beam_render_mode"] = 0
	app._update_beam_renderer_mode(true)
	if "--render-lens-probe" in OS.get_cmdline_user_args():
		await _load(_generate(true,true,true))
		dmx.resize(512)
		await _lens_graphics_probe()
		_check_lens_instances(true)
		app._clear_scene()
		app.queue_free()
		await process_frame
		quit(0 if test.failures.is_empty() else 1)
		return
	await _load(_generate(false))
	var sizes: Dictionary = adapter.diagnostics()
	test.check(sizes["physical_outputs"] == 51 and sizes["render_rows"] == 2 and sizes["aggregated_members"] == 50, "51 canonical outputs bind one aggregate shaft plus independent emission-only row")
	if int(sizes.get("aggregated_groups", 0)) != 1:
		print("TEST FAILURE: Production compact source did not aggregate: ", sizes)
		app._clear_scene()
		app.queue_free()
		await process_frame
		quit(1)
		return
	test.check(sizes["allocated_member_shafts"] == (1 if lazy_expected else 51), "Accepted fifty members allocate no individual shafts; the unrelated Glow path remains eager")
	test.check(sizes["member_shafts_created"] == (1 if lazy_expected else 51), "Setup avoids creation itself rather than creating and hiding member shafts")
	var deferred: int = 0
	for output in adapter._outputs:
		for handle in output.lights:
			if handle.light.has_meta(&"peraviz_deferred_aggregate_shaft"):
				deferred += 1
				test.check(handle.beam == null and handle.light.get_node_or_null("PeravizVolumetricBeam") == null, "Deferred physical anchor owns no hidden shaft child")
	test.check(deferred == (50 if lazy_expected else 0), "All canonical compact members retain lightweight anchors")
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
	await _load(_generate(true))
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
	await _load(_generate(false, true))
	counts = adapter.diagnostics()
	test.check(counts["physical_outputs"] == 1000 and counts["render_rows"] == 20 and counts["aggregate_shaft_resources"] == 20,
		"Twenty production-imported compact sources retain 1000 physical outputs and allocate exactly 20 aggregate shafts")
	test.check(counts["allocated_member_shafts"] == (0 if lazy_expected else 1000) and counts["member_shafts_created"] == (0 if lazy_expected else 1000), "Thousand-output setup avoids actual member nodes and material allocation")
	var allocation_setup: Dictionary = {"scene_setup_us": last_setup_us, "binding_metrics": app._scene_setup_resource_metrics.duplicate(), "resources": counts}
	print("AGGREGATE_RESOURCE_SETUP ", JSON.stringify(allocation_setup))
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
	var held_values: PackedFloat32Array = adapter._native.physical_values(0)
	var stable: Dictionary = adapter.diagnostics()
	test.check(stable["member_shafts_created"] == (0 if lazy_expected else 1000) and stable["aggregate_shafts_created"] == 20, "Normal Dimmer/Color playback never rebuilds lazy resources")
	print("AGGREGATE_RESOURCE_ACTIVE ", JSON.stringify(stable))
	app._visual_settings["enable_realtime_spotlights"] = true
	app._update_beam_renderer_mode(false)
	adapter.refresh_renderer()
	var fallback: Dictionary = adapter.diagnostics()
	test.check(fallback["godot_accepted_aggregates"] == 0 and fallback["godot_rejected_aggregates"] == 20 and fallback["godot_binding_rejections"].get("renderer_policy",0) == 20 and fallback["final_render_rows"] == 1000,
		"Explicit realtime policy reports Godot-only rejection and safely restores individual rows")
	test.check(fallback["allocated_member_shafts"] == 1000 and fallback["aggregate_shaft_resources"] == 0, "Fallback creates every required individual shaft")
	test.check(fallback["rehydrated_member_shafts"] == (1000 if lazy_expected else 0), "Rehydration counts actual lazy allocations")
	test.check(adapter._native.physical_values(0) == held_values, "Fallback preserves authoritative held physical values without a new DMX packet")
	var rehydrated_nodes: Array = []
	for output in adapter._outputs:
		var handle = output.lights[0]
		var values: PackedFloat32Array = adapter._native.physical_values(output.index)
		test.check(is_instance_valid(handle.beam) and handle.beam.visible and handle.beam.mesh != null, "Every rehydrated shaft is initialized from held state")
		test.check(handle.beam.get_instance_shader_parameter("beam_dynamic_state") == Color(values[1],values[2],values[3],clampf(values[6],0.0,50.0)), "Rehydration restores exact held shader values")
		rehydrated_nodes.append(handle.beam)
	app._visual_settings["enable_realtime_spotlights"] = false
	app._update_beam_renderer_mode(false)
	adapter.refresh_renderer()
	var regrouped: Dictionary = adapter.diagnostics()
	test.check(regrouped["aggregated_members"] == 1000 and regrouped["render_rows"] == 20 and regrouped["allocated_member_shafts"] == (0 if lazy_expected else 1000), "Re-aggregation retires unnecessary individuals and retains every physical output")
	if lazy_expected:
		for node in rehydrated_nodes: test.check(not is_instance_valid(node), "Retirement frees real nodes immediately and leaves no duplicates")
		test.check(regrouped["retired_member_shafts"] == 1000, "Retirement counts actual freed members")
	for record in app._native_target_registry._beam_output_records_by_id.values():
		for node in record.get("beam_instances", []): test.check(node == null or is_instance_valid(node), "Registry resource views contain no freed member references")
	test.check(adapter._native.physical_values(0) == held_values and regrouped["visible_aggregate_shafts"] == 20, "Re-aggregation replays the held aggregate appearance")
	print("AGGREGATE_RESOURCE_RESTORED ", JSON.stringify(regrouped))
	# Actual renderer replacement exercises the same held-state resource transaction.
	app._visual_settings["beam_render_mode"] = 1
	app._update_beam_renderer_mode(true)
	adapter.refresh_renderer()
	test.check(adapter.diagnostics()["allocated_member_shafts"] == 1000 and adapter.diagnostics()["aggregate_shaft_resources"] == 0, "Legacy renderer replacement safely restores every required individual")
	app._visual_settings["beam_render_mode"] = 0
	app._update_beam_renderer_mode(true)
	adapter.refresh_renderer()
	test.check(adapter.diagnostics()["aggregated_members"] == 1000 and adapter.diagnostics()["allocated_member_shafts"] == (0 if lazy_expected else 1000), "Returning Vector Prism recreates only accepted aggregate shafts")
	test.check(adapter._native.physical_values(0) == held_values, "Renderer replacement preserves authoritative held values")

	rehydrated_nodes.clear()
	# The same generic fixture generator now exercises independently patched Dimmer and RGB at scale.
	app._visual_settings["enable_realtime_spotlights"] = false
	OS.set_environment("PERAVIZ_NATIVE_EVALUATION", "parallel")
	await _load(_generate(true, true, true))
	counts = adapter.diagnostics()
	test.check(counts["physical_outputs"] == 1000 and counts["render_rows"] == 1000 and counts["godot_accepted_aggregates"] == 0,
		"One thousand independent Dimmer/RGB emitters retain one thousand renderer rows")
	var lens_expected: bool = RenderingServer.get_current_rendering_method() == "forward_plus" and OS.get_environment("PERAVIZ_GPU_LENSES") != "0"
	print("LENS_SETUP ", JSON.stringify(adapter.diagnostics()))
	var renderer_totals: Dictionary = {}
	var original_meshes: Array = []
	var original_transforms: Array = []
	var backend_expected: bool = OS.get_environment("PERAVIZ_NATIVE_BEAM_APPLY") != "0"
	for tick in range(10):
		for universe in range(10):
			dmx.fill(0)
			for fixture in range(2):
				var base: int = fixture * 256
				dmx[base+3] = 160
				for emitter in range(50):
					var index: int = (universe*2+fixture)*50+emitter
					dmx[base+4+emitter*4] = (0 if tick == 8 else 50+(index*31+tick*19)%200)
					dmx[base+5+emitter*4+(index+tick)%3] = 255
			runtime._native_visual_runtime.submit_universe_frame(universe,dmx)
		var frame: Dictionary = await _completed()
		test.check(bool(frame.get("native_presentation", false)), "Independent generation composes directly")
		test.check(adapter._payload["count"] == 1000, "Every independently changed emitter publishes once")
		runtime._sectioned_visual_frame_applier.apply_snapshot(frame,app,service,0.016,runtime,runtime._native_fixture_uuids_by_id,runtime._fixture_nodes)
		for output_index in range(adapter._binding_records.size()):
			var record: Dictionary = adapter._binding_records[output_index]
			var fixture_index: int = str(record["fixture_uuid"]).get_slice("-",1).to_int()-1
			var emitter: int = str(record["geometry_key"]).get_slice("Emitter",1).to_int()
			var index: int = fixture_index*50+emitter
			var values: PackedFloat32Array = adapter._native.physical_values(output_index)
			test.check(is_equal_approx(values[0],float(0 if tick == 8 else 50+(index*31+tick*19)%200)/255.0), "Independent physical Dimmer retains its canonical patch")
			test.check(is_equal_approx(values[1+(index+tick)%3],1.0) and is_zero_approx(values[1+(index+tick+1)%3]) and is_zero_approx(values[1+(index+tick+2)%3]), "Independent RGB retains its canonical patch")
			var handle = adapter._outputs[output_index].lights[0]
			var intensity: float = clampf(values[6], 0.0, 50.0)
			test.check(handle.beam.visible == (intensity > 0.015), "Native batch preserves exact reference blackout threshold")
			if intensity > 0.015:
				test.check(handle.beam.get_instance_shader_parameter("beam_dynamic_state") == Color(values[1], values[2], values[3], intensity), "Actual Vector Prism uniform equals final physical RGB/intensity")
			if tick == 1:
				original_meshes.append(handle.beam.mesh)
				original_transforms.append(handle.beam.transform)
			elif tick >= 2:
				test.check(handle.beam.mesh == original_meshes[output_index] and handle.beam.transform == original_transforms[output_index], "Dynamic batches preserve meshes and local optical transforms")
		_check_lens_instances(lens_expected)
		var sample: Dictionary = adapter.consume_diagnostics()
		if tick >= 2 and tick < 8:
			for key in ["renderer_outputs_processed", "renderer_outputs_changed", "renderer_outputs_unchanged", "compatibility_adapter_us", "renderer_mutation_us", "native_beam_apply_us", "native_beam_applied", "native_beam_fallback", "native_boundary_us", "payload_conversion_us", "native_material_us", "main_thread_publication_us", "optics_apply_calls", "beam_topology_rebuilt", "actual_beam_dynamic_renderer_writes", "gpu_lens_transfer_bytes", "gpu_lens_submissions", "gpu_lens_pack_us", "gpu_lens_submit_us"]:
				renderer_totals[key] = int(renderer_totals.get(key, 0)) + int(sample.get(key, 0))
		var unchanged: Dictionary = service.consume_native_snapshot(runtime._native_visual_runtime, runtime._sectioned_visual_frame_applier.schema_generation())
		test.check(unchanged.get("pending", false) or adapter._payload["count"] == 0, "Held independent state never republishes changed renderer rows")
		if not unchanged.get("pending", false):
			runtime._sectioned_visual_frame_applier.apply_snapshot(unchanged,app,service,0.016,runtime,runtime._native_fixture_uuids_by_id,runtime._fixture_nodes)
	test.check(renderer_totals["renderer_outputs_processed"] == 6000 and renderer_totals["native_beam_applied"] == (6000 if backend_expected else 0), "Warm independent generations execute the production native batch or explicit reference loop")
	test.check(renderer_totals["optics_apply_calls"] == 0 and renderer_totals["beam_topology_rebuilt"] == 0, "Dimmer/Color playback does not rebuild optical geometry")
	renderer_totals["scene_setup_us"] = last_setup_us
	renderer_totals["native_enabled"] = backend_expected
	renderer_totals["resources"] = adapter._native.get_sizes()
	print("INDEPENDENT_RENDER_COMPARISON ", JSON.stringify(renderer_totals))
	_check_lens_instances(lens_expected)
	# Force one unsupported material, then rebuild from held state and restore admission.
	if lens_expected:
		var output_index: int = adapter._lens_batches.members.keys()[0]
		var material: StandardMaterial3D = adapter._outputs[output_index].materials[0].material
		material.roughness = 0.5
		adapter.refresh_renderer()
		test.check(not adapter._lens_batches.members.has(output_index) and adapter._binding_records[output_index]["lens_material_targets"][0].mesh.layers == 1, "Unsupported material restores its original individual graphical resource")
		var held: PackedFloat32Array = adapter._native.physical_values(output_index)
		var committed: PackedFloat32Array = adapter._native.material_values(material.get_rid())
		test.check(committed[0] == held[1] and is_equal_approx(committed[3],held[7]*adapter._outputs[output_index].materials[0].scale), "Fallback initializes exact held lens Color/energy without another DMX packet")
		material.roughness = 1.0
		adapter.refresh_renderer()
		_check_lens_instances(true)
		var anchor: SpotLight3D = adapter._outputs[output_index].lights[0].light
		# This specific regression deliberately exercises native projector admission.
		app._apply_visual_settings({"footprint_backend": "native"})
		anchor.light_projector = GradientTexture2D.new()
		service.rebind_dense_light(anchor)
		test.check(not adapter._lens_batches.members.has(output_index), "Projector resource changes retire incompatible GPU slots")
		anchor.light_projector = null
		service.rebind_dense_light(anchor)
		_check_lens_instances(true)
		var old_node: MultiMeshInstance3D = adapter._lens_batches.batches[0].node
		app._visual_settings["beam_render_mode"] = 1
		app._update_beam_renderer_mode(false)
		adapter.refresh_renderer()
		test.check(not is_instance_valid(old_node), "Actual renderer replacement retires the old GPU generation")
		_check_lens_instances(true)
		app._visual_settings["beam_render_mode"] = 0
		app._update_beam_renderer_mode(false)
		adapter.refresh_renderer()
		_check_lens_instances(true)
		test.check(not adapter._native.install_lenses(adapter._generation+1,[],[],[],[]), "A stale binding generation cannot replace current GPU routes")
		var location: Vector2i = adapter._lens_batches.members[output_index]
		var mesh: MeshInstance3D = adapter._lens_batches.batches[location.x].entries[location.y].mesh
		mesh.hide()
		await process_frame
		test.check(adapter._native.lens_buffer(location.x)[location.y*16] == 0.0, "Source visibility suppresses its GPU geometry without new DMX")
		mesh.show()
		await process_frame
		var mechanical: Node3D = adapter._lens_batches.batches[location.x].node.get_parent()
		var before: Transform3D = mesh.global_transform
		mechanical.rotation.y += 0.1
		test.check(not mesh.global_transform.is_equal_approx(before), "Mechanical motion changes actual source lens placement")
		_check_lens_instances(true)
		mechanical.rotation.y -= 0.1
	_check_native_binding_boundary(adapter._outputs[0].lights[0].beam)
	var transform_handle = adapter._outputs[0].lights[0]
	var inherited_before: Transform3D = transform_handle.beam.global_transform
	transform_handle.light.rotation.y += 0.1
	test.check(transform_handle.beam.global_transform != inherited_before, "Native application retains normal ancestor/mechanical transform propagation")
	transform_handle.light.rotation.y -= 0.1
	app._apply_visual_settings({"footprint_backend": "custom"})
	if not adapter._native.get_sizes().get("native_async_active", false):
		var resumed: Dictionary = await _completed()
		runtime._sectioned_visual_frame_applier.apply_snapshot(resumed,app,service,0.016,runtime,runtime._native_fixture_uuids_by_id,runtime._fixture_nodes)
	test.check(adapter._footprints.volumes.size() == 1000, "Async runtime retains independent physical footprints behind native shaft/lens batching")
	for index in [0, 499, 999]:
		var surface: MeshInstance3D = adapter._footprints.volumes[index]
		var physical: PackedFloat32Array = adapter._native.physical_values(index)
		var committed: PackedFloat32Array = adapter._native.footprint_values(surface.material_override.get_rid())
		test.check(committed[0] == physical[1] and committed[1] == physical[2] and committed[2] == physical[3] and is_equal_approx(committed[3],(physical[5] if physical[5] > 0 else physical[4]) * float(app._visual_settings.footprint_multiplier)), "Completed native snapshots apply exact physical surface Color/energy")
	print("NATIVE_ASYNC_PUBLICATION ", JSON.stringify(adapter.consume_diagnostics()))
	test.check(adapter.diagnostics().get("native_async_active", false), "Production Godot boundary uses native asynchronous calculations")
	var competing: RefCounted = ClassDB.instantiate("PeravizPresentationState")
	var competing_generation: int = competing.install(PackedInt32Array(), PackedFloat32Array(), PackedInt32Array())
	var rejected: Dictionary = competing.consume_runtime(runtime._native_visual_runtime, competing_generation, runtime._sectioned_visual_frame_applier.schema_generation(), false)
	test.check(not rejected.get("valid", true), "A second renderer cannot enter a running core's serial evaluator")
	competing.clear()
	var retired_batches: Array = []
	for batch in adapter._lens_batches.batches: retired_batches.append(batch.node)
	service.set_render_diagnostic_mode("no-beams")
	_check_lens_instances(false)
	for node in retired_batches: test.check(not is_instance_valid(node), "Diagnostic fallback retires actual MultiMesh nodes")
	for output in adapter._outputs: test.check(not output.lights[0].beam.visible, "Diagnostic suppression hides independently batched shafts")
	service.set_render_diagnostic_mode("full")
	for output in adapter._outputs: test.check(output.lights[0].beam.visible, "Held replay restores every independently batched shaft")
	_check_lens_instances(lens_expected)
	# Submit once, then drive the actual collection path with a stopped receiver and no packets.
	dmx.fill(150)
	runtime._native_visual_runtime.submit_universe_frame(0, dmx)
	var stopped := StoppedReceiver.new()
	var deadline: int = Time.get_ticks_msec() + 5000
	var collected: Dictionary = {"native_frame_pending": true}
	while collected.get("native_frame_pending", false) and Time.get_ticks_msec() < deadline:
		await process_frame
		collected = runtime._collect_dmx(stopped, Callable(), app, service, 0.016)
	test.check(not collected.get("native_frame_pending", false) and collected.get("universes_changed", -1) == 0, "Stopped-stream collection consumes a previously submitted complete snapshot")
	adapter.refresh_renderer()
	var replay: Dictionary = await _completed()
	test.check(replay.get("native_presentation", false), "Renderer replacement replays held state without another packet")
	OS.unset_environment("PERAVIZ_NATIVE_EVALUATION")
	if test.failures.is_empty(): print("DIRECT_INDEPENDENT_1000 passed outputs=1000 rows=1000")
	var retired_native: Object = adapter._native
	var retired_beam: MeshInstance3D = adapter._outputs[0].lights[0].beam
	var retired_lens_nodes: Array = []
	for batch in adapter._lens_batches.batches: retired_lens_nodes.append(batch.node)
	app._clear_scene()
	for node in retired_lens_nodes: test.check(not is_instance_valid(node), "Scene reload releases every GPU aperture node")
	test.check(retired_native.get_sizes()["gpu_lens_instances"] == 0 and retired_native.get_sizes()["gpu_lens_buffer_bytes"] == 0, "Scene teardown clears borrowed GPU routes and buffers")
	test.check(retired_native.get_sizes()["native_beam_bindings"] == 0 and retired_native.get_sizes()["native_beam_buffer_bytes"] == 0, "Scene teardown releases every native beam binding and fallback buffer")
	app.queue_free()
	service = null
	runtime = null
	adapter = null
	aggregate = null
	original_meshes.clear()
	await process_frame
	test.check(not is_instance_valid(retired_beam), "Scene teardown frees individual shaft nodes without native strong references")
	await process_frame
	test.finish(self)
