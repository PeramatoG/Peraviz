extends RefCounted

# Opt-in only. Each case changes one presentation domain; readback happens after
# timing, never in ordinary frames. Device times on llvmpipe are not GPU evidence.
static func run(probe: RefCounted, tree: SceneTree, test: RefCounted, viewport: SubViewport, loader: Node, service: RefCounted, directory: String) -> void:
	service.set_performance_trace_enabled(true)
	var adapter: RefCounted = service._dense_adapter
	var trivial := Shader.new()
	trivial.code = "shader_type spatial; render_mode unshaded,blend_add,depth_draw_never,depth_test_disabled,cull_front,fog_disabled; void fragment(){ ALBEDO=vec3(1.0); ALPHA=1.0; }"
	var shafts: Array[MeshInstance3D] = []
	for output in adapter._outputs:
		for handle in output.lights:
			if is_instance_valid(handle.beam): shafts.append(handle.beam)
	var results: Array = []
	var reference: Image
	var sharp: Image
	var intersection: Image
	var modes: Array = ["A_full", "B_no_footprints", "C_no_shafts", "D_scene_only", "E_trivial_footprints", "F_full_footprints", "G_full_repeated_native_updates", "H_soft_intersections", "I_uncapped_footprints", "J_soft_shafts_only"]
	if adapter._outputs.size() > 6: modes.append("O_uncapped_trivial")
	if adapter._outputs.size() == 6: modes.append_array(["K_inclined_reference", "L_inclined_soft", "M_inside_reference", "N_inside_soft"])
	for mode in modes:
		if mode == "K_inclined_reference": viewport.get_node("FootprintStage/IntersectionReceiver").rotation_degrees = Vector3(18,0,12)
		if mode == "M_inside_reference":
			viewport.get_camera_3d().position = Vector3(0,5.0,2.8)
			viewport.get_camera_3d().look_at(Vector3(0,4,3),Vector3.FORWARD)
		var footprints_on: bool = mode not in ["B_no_footprints", "D_scene_only", "J_soft_shafts_only", "K_inclined_reference", "L_inclined_soft", "M_inside_reference", "N_inside_soft"]
		var shafts_on: bool = mode in ["A_full", "B_no_footprints", "G_full_repeated_native_updates", "H_soft_intersections", "J_soft_shafts_only", "K_inclined_reference", "L_inclined_soft", "M_inside_reference", "N_inside_soft"]
		var seed: Dictionary = loader.frame(1.0, 1.0)
		for index in range(adapter._outputs.size()):
			seed.floats[adapter._outputs.size() * 5 + index * 4 + 1] = 1.0
			seed.floats[adapter._outputs.size() * 5 + index * 4 + 2] = 1.0
		service.compose_dense_snapshot(seed.descriptors, seed.integers, seed.floats)
		service.end_visual_snapshot()
		for volume in adapter._footprints.volumes: volume.set_receiver_bounds(loader._loaded_bounds, mode not in ["I_uncapped_footprints", "O_uncapped_trivial"])
		adapter._native.set_footprints_enabled(footprints_on)
		adapter._native.replay_presentation_gains(false, true, 0.6, true)
		for volume in adapter._footprints.volumes: volume.material_override.shader = trivial if mode in ["E_trivial_footprints", "O_uncapped_trivial"] else volume.SHADER
		loader._visual_settings["wash_intersection_width_m"] = 0.5 if mode in ["H_soft_intersections", "J_soft_shafts_only", "L_inclined_soft", "N_inside_soft"] else 0.0
		loader.renderer.configure(viewport.get_camera_3d(), loader._visual_settings)
		for shaft in shafts:
			shaft.visible = shafts_on
			var light: SpotLight3D = shaft.get_parent() as SpotLight3D
			loader.renderer._sync_intersection_policy(shaft, light.get_meta("peraviz_beam_last_params", {}))
		var soft_count: int = 0
		for shaft in shafts:
			if float(shaft.material_override.get_shader_parameter("wash_intersection_width")) > 0: soft_count += 1
		var pulse: Array = [0, 0]
		var callback: Callable = _pulse.bind(loader, service, pulse) if mode == "G_full_repeated_native_updates" else Callable()
		adapter.consume_diagnostics()
		var stats: Dictionary = await probe._capture(tree, viewport, directory.path_join(mode + ".png"), callback)
		var presentation: Dictionary = adapter.consume_diagnostics()
		stats["presentation_us"] = {"native_compose": presentation.get("native_compose_us", 0), "native_beam_apply": presentation.get("native_beam_apply_us", 0), "native_material": presentation.get("native_material_us", 0), "script_mutation": presentation.get("renderer_mutation_us", 0)}
		stats["case"] = mode
		stats["soft_shafts"] = soft_count
		var actual_soft: int = 0
		for shaft in shafts:
			if shaft.material_override.shader == loader.renderer.soft_intersection_shader(): actual_soft += 1
		stats["actual_soft_programs"] = actual_soft
		stats["native_compose_apply_us"] = float(pulse[1]) / pulse[0] if pulse[0] > 0 else 0.0
		stats["native_snapshot_note"] = "alternating dense native snapshots during every measured frame; excludes GDTF/DMX evaluation" if pulse[0] > 0 else "held snapshot"
		stats["footprint_resources"] = adapter._footprints.volumes.size()
		stats["eligible_footprints"] = adapter._footprints.volumes.size()
		var culled: int = 0
		for volume in adapter._footprints.volumes:
			if volume.culled: culled += 1
		stats["culled_footprints"] = culled
		stats["active_footprints"] = adapter.diagnostics().active_custom_footprints
		stats["physical_outputs"] = adapter._outputs.size()
		stats["shaft_resources"] = shafts.size()
		stats["native_surface_lights"] = adapter.diagnostics().surface_lights.active_surface_lights
		var total_range: float = 0.0
		for volume in adapter._footprints.volumes: total_range += volume.raster_range
		stats["mean_raster_depth_m"] = total_range / maxf(adapter._footprints.volumes.size(), 1)
		stats["memory_bytes"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
		results.append(stats)
		if mode in ["B_no_footprints", "K_inclined_reference", "M_inside_reference"]: sharp = viewport.get_texture().get_image()
		if mode in ["J_soft_shafts_only", "L_inclined_soft", "N_inside_soft"] and adapter._outputs.size() == 6:
			intersection = viewport.get_texture().get_image()
			var change: Dictionary = probe._difference(sharp, intersection)
			stats.merge(change)
			test.check(change.changed_pixels > 0 and change.changed_pixels < sharp.get_width() * sharp.get_height() / 5, "Depth feather changes a bounded contact region: " + mode)
		if mode == "C_no_shafts": reference = viewport.get_texture().get_image()
		if mode == "I_uncapped_footprints":
			var error: Dictionary = probe._difference(reference, viewport.get_texture().get_image())
			stats.merge(error)
			test.check(error.max_pixel_error <= 1.0 / 255.0, "Receiver depth cap preserves all visible footprint samples")
		if mode == "F_full_footprints": test.check(probe._difference(reference, viewport.get_texture().get_image()).max_pixel_error == 0, "C and F have identical held footprint rendering")
	var scene_draws: int = results[3].draw_calls
	for stats in results:
		if stats.case in ["C_no_shafts", "E_trivial_footprints", "F_full_footprints", "I_uncapped_footprints", "O_uncapped_trivial"]:
			stats["footprint_draw_delta_from_scene"] = stats.draw_calls - scene_draws
	var report := {"adapter": RenderingServer.get_video_adapter_name(), "resolution": viewport.size, "cases": results, "note": "GPU timings require physical hardware; cases overlap CPU/GPU work and differences are not additive decompositions"}
	var file := FileAccess.open(directory.path_join("bottleneck.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("FOOTPRINT_BOTTLENECK ", JSON.stringify(report))
	service.reset_scene_state()
	viewport.free()

static func _pulse(loader: Node, service: RefCounted, counters: Array) -> void:
	var frame: Dictionary = loader.frame(0.8 if counters[0] % 2 == 0 else 1.0, 0.5)
	var start := Time.get_ticks_usec()
	service.compose_dense_snapshot(frame.descriptors, frame.integers, frame.floats)
	service.end_visual_snapshot()
	counters[1] += Time.get_ticks_usec() - start
	counters[0] += 1
