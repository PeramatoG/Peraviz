extends RefCounted

# Extension of the existing opt-in bottleneck probe, never a saved visual policy.
# Dense snapshots isolate presentation; mechanical motion bypasses DMX evaluation.
static func run(probe: RefCounted, tree: SceneTree, test: RefCounted, viewport: Viewport, loader: Node, service: RefCounted, directory: String, inputs: RefCounted = null) -> void:
	var adapter: RefCounted = service._dense_adapter
	service.set_performance_trace_enabled(true)
	var warmup := 30
	var samples := 120
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--footprint-warmup="): warmup = maxi(1, int(arg.trim_prefix("--footprint-warmup=")))
		if arg.begins_with("--footprint-samples="): samples = maxi(2, int(arg.trim_prefix("--footprint-samples=")))
	var shafts: Array[MeshInstance3D] = []
	var shaft_layers: Array[int] = []
	for output in adapter._outputs + adapter._render_bindings.aggregate_outputs():
		for handle in output.lights:
			if is_instance_valid(handle.beam) and not shafts.has(handle.beam):
				shafts.append(handle.beam)
				shaft_layers.append(handle.beam.layers)
	var footprint_layers: Array[int] = []
	for volume in adapter._footprints.volumes: footprint_layers.append(volume.layers)
	var mechanics: Array[Node3D] = []
	var bases: Array[Transform3D] = []
	var frames: Array[Dictionary] = []
	var held: Dictionary
	var scope := "Generated presentation workload; no raw DMX/GDTF evaluation."
	if inputs != null:
		mechanics.assign(inputs.mechanics)
		frames.assign(inputs.frames)
		held = inputs.held
		scope = inputs.scope
	else:
		for anchor in loader.anchors:
			var mechanical: Node3D = anchor.get_parent()
			if not mechanics.has(mechanical): mechanics.append(mechanical)
		# Prebuild deterministic inputs; never allocate semantic frames in timed playback.
		for index in range(120):
			var phase := float(index) * TAU / 120.0
			frames.append(loader.frame(0.8 + 0.15 * sin(phase), 0.7 + 0.25 * cos(phase)))
		held = loader.frame(0.8, 0.7)
	for mechanical in mechanics: bases.append(mechanical.transform)
	var trivial := Shader.new()
	trivial.code = "shader_type spatial; render_mode unshaded,blend_add,depth_draw_never,depth_test_disabled,cull_front,fog_disabled; void fragment(){ALBEDO=vec3(1.0); ALPHA=1.0;}"
	var results: Array = []
	var membership: Array = []
	for row in adapter._render_bindings.rows:
		membership.append({"row": row.id, "class": row.presentation_class, "members": row.members})
	var old_fps: int = Engine.max_fps
	Engine.max_fps = 0
	var vsync := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# A-D hold the same continuous combined presentation workload, hiding only draws.
	# E-H hold full resources and vary just the indicated inputs.
	for mode in ["A_full", "B_shafts_only", "C_footprints_only", "D_scene_motion", "E_static", "F_dimmer_color", "G_pan_tilt", "H_combined", "I_trivial", "J_no_footprint_writes"]:
		for index in range(mechanics.size()): mechanics[index].transform = bases[index]
		service.compose_dense_snapshot(held.descriptors, held.integers, held.floats)
		service.end_visual_snapshot()
		var footprints_on: bool = mode not in ["B_shafts_only", "D_scene_motion", "J_no_footprint_writes"]
		var shafts_on: bool = mode not in ["C_footprints_only", "D_scene_motion"]
		for index in range(shafts.size()): shafts[index].layers = shaft_layers[index] if shafts_on else 0
		for index in range(adapter._footprints.volumes.size()):
			var volume: MeshInstance3D = adapter._footprints.volumes[index]
			volume.layers = footprint_layers[index] if footprints_on else 0
			volume.material_override.shader = trivial if mode == "I_trivial" else volume.SHADER
		adapter._native.set_footprints_enabled(mode != "J_no_footprint_writes")
		adapter._native.replay_presentation_gains(false, true, float(loader._visual_settings.footprint_multiplier), true)
		var changing_color: bool = mode not in ["E_static", "G_pan_tilt"]
		var changing_motion: bool = mode != "E_static" and mode != "F_dimmer_color"
		var counters: Array = [0, 0, 0]
		var baseline: Dictionary = {}
		var callback := _drive.bind(service, adapter, mechanics, bases, frames, changing_color, changing_motion, counters)
		var reset := _reset.bind(adapter, counters, baseline)
		var stats: Dictionary = await probe._capture(tree, viewport, directory.path_join(mode + ".png"), callback, warmup, samples, reset)
		var after: Dictionary = adapter.consume_diagnostics()
		var work: Dictionary = {}
		for name in preload("res://scripts/beam_renderers/custom_footprint_volume.gd").WORK_NAMES + ["projector_parameter_updates"]:
			var key: String = "custom_" + name
			work[key] = int(after.get(key, 0)) - int(baseline.get(key, 0))
		stats["case"] = mode
		stats["projector_work"] = work
		stats["presentation_trace"] = after
		stats["application_us_per_frame"] = float(counters[1]) / samples
		stats["physical_footprint_material_writes"] = counters[2]
		stats["samples"] = samples
		stats["warmup"] = warmup
		stats["memory_static_bytes"] = Performance.get_monitor(Performance.MEMORY_STATIC)
		stats["video_memory_bytes"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
		stats["transparent_objects"] = null # Godot's public viewport counter combines opaque and transparent objects.
		results.append(stats)
		print("FOOTPRINT_LIVE_CASE ", JSON.stringify(stats))
		if mode == "E_static": test.check(work.get("custom_world_changes", -1) == 0 and counters[2] == 0, "Held projection does no world or physical material writes")
		if mode == "F_dimmer_color": test.check(work.get("custom_world_changes", -1) == 0 and counters[2] > 0, "Color/Dimmer is isolated from projector transforms")
		if mode == "G_pan_tilt": test.check(work.get("custom_world_changes", 0) > 0 and counters[2] == 0, "Mechanical motion is isolated from physical material writes")
		if mode == "J_no_footprint_writes": test.check(counters[2] == 0, "Diagnostic write suppression retains resources without physical footprint writes")
	for index in range(shafts.size()): shafts[index].layers = shaft_layers[index]
	for index in range(adapter._footprints.volumes.size()):
		adapter._footprints.volumes[index].layers = footprint_layers[index]
		adapter._footprints.volumes[index].material_override.shader = adapter._footprints.volumes[index].SHADER
	for index in range(mechanics.size()): mechanics[index].transform = bases[index]
	adapter._native.set_footprints_enabled(true)
	Engine.max_fps = old_fps
	DisplayServer.window_set_vsync_mode(vsync)
	var camera: Camera3D = viewport.get_camera_3d()
	var camera_world: Transform3D = camera.global_transform
	var physical_ids := PackedInt32Array()
	for output in adapter._outputs: physical_ids.append(output.canonical_id)
	var report := {"camera": {"world_columns": [camera_world.basis.x.x, camera_world.basis.x.y, camera_world.basis.x.z, camera_world.basis.y.x, camera_world.basis.y.y, camera_world.basis.y.z, camera_world.basis.z.x, camera_world.basis.z.y, camera_world.basis.z.z, camera_world.origin.x, camera_world.origin.y, camera_world.origin.z], "fov": camera.fov, "near": camera.near, "far": camera.far, "projection": camera.projection, "cull_mask": camera.cull_mask}, "physical_output_ids": physical_ids, "adapter": RenderingServer.get_video_adapter_name(), "engine": Engine.get_version_info(), "os": OS.get_name(), "rendering_method": RenderingServer.get_current_rendering_method(), "resolution": [viewport.size.x, viewport.size.y], "render_group_membership": membership, "cases": results,
		"scope": scope + " A-D preserve mutations and suppress draw layers only; B/J additionally isolates physical footprint material writes. I uses a white volume shader with different fragment coverage; it is a pipeline bound, not an equivalent-image shader benchmark. Timers overlap; differences are not additive. Software GPU timings cannot establish hardware speedup."}
	var native: Object = adapter._native
	var owner: RefCounted = adapter._footprints
	service.reset_scene_state()
	var retired: Dictionary = native.get_sizes()
	report["cleanup"] = {"remaining_volumes": owner.volumes.size(), "created": owner.created, "retired": owner.retired, "native_beam_bindings": retired.native_beam_bindings, "gpu_lens_buffer_bytes": retired.gpu_lens_buffer_bytes, "active_custom_footprints": retired.active_custom_footprints}
	test.check(owner.volumes.is_empty() and owner.created == owner.retired and retired.native_beam_bindings == 0 and retired.gpu_lens_buffer_bytes == 0, "Probe teardown revokes native routes and retires every footprint")
	if viewport is SubViewport: viewport.free()
	var file := FileAccess.open(directory.path_join("live-bottleneck.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))

static func _reset(adapter: RefCounted, counters: Array, baseline: Dictionary) -> void:
	for index in range(counters.size()): counters[index] = 0
	baseline.merge(adapter.consume_diagnostics(), true)

static func _drive(service: RefCounted, adapter: RefCounted, mechanics: Array[Node3D], bases: Array[Transform3D], frames: Array[Dictionary], color: bool, motion: bool, counters: Array) -> void:
	var start := Time.get_ticks_usec()
	var tick: int = counters[0]
	if motion:
		var rotation := Basis.from_euler(Vector3(0.04 * sin(tick * 0.037), 0.08 * sin(tick * 0.023), 0))
		for index in range(mechanics.size()): mechanics[index].transform = bases[index] * Transform3D(rotation, Vector3.ZERO)
	if color:
		var frame: Dictionary = frames[tick % frames.size()]
		service.compose_dense_snapshot(frame.descriptors, frame.integers, frame.floats)
		service.end_visual_snapshot()
	counters[1] += Time.get_ticks_usec() - start
	# CPU-only cache counters, no RenderingServer readback. Probe overhead is not application_us.
	if color: counters[2] += int(adapter._native.get_sizes().custom_footprint_dynamic_writes)
	counters[0] += 1
