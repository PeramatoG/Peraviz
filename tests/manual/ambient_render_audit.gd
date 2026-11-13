extends SceneTree
## Opt-in, process-local comparisons; never save graphics or optical settings.
## Each B–J candidate changes exactly one factor from A. Clean is the new default.
const CASES := ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "clean", "msaa2", "ssao", "near", "depth32"]
var options := {}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() == 2 else "true"
	call_deferred("run")

func run() -> void:
	var candidate: String = options.get("case", "clean")
	if candidate not in CASES:
		push_error("Unknown comparison: " + candidate)
		quit(1)
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var app = load("res://test.tscn").instantiate()
	root.add_child(app)
	# Disable the already queued auto-load before its deferred callback, in memory only.
	app._user_preferences.auto_load_last_file = false
	app._user_preferences.auto_start_dmx = false
	if options.has("mvr"):
		var result: Dictionary = await app._load_mvr_scene(options.mvr, "mvr", false)
		if not result.get("ok", false):
			push_error("MVR audit load failed: " + str(result))
			quit(1)
			return
	app.get_node("UIRoot").hide()
	var camera: Camera3D = app.get_node("Camera3D")
	camera.set_process(false)
	camera.set_process_unhandled_input(false)
	var center: Vector3 = app._loaded_bounds.get_center() if app._has_loaded_bounds else Vector3.ZERO
	var camera_scale: float = maxf(1.0, app._loaded_bounds.size.length() / 30.0) if app._has_loaded_bounds else 1.0
	camera.global_position = center + Vector3(24, 18, 24) * camera_scale
	camera.look_at(center)
	var light: DirectionalLight3D = app.get_node("DirectionalLight3D")
	var environment: Environment = app.get_node("WorldEnvironment").environment
	var ground: MeshInstance3D = app.get_node("Ground")
	if not options.has("mvr"):
		# Repeatable thin edges, contacts and uniform surfaces without DMX input.
		for i in range(12):
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.08 if i < 6 else 1.0, 3.0, 1.0)
			mesh.mesh = box
			app.add_child(mesh)
			mesh.position = Vector3((i % 6) * 2 - 5, 1.5, (i / 6) * 4 - 2)
	apply_case(candidate, light, environment, ground, camera)
	for i in range(120): await process_frame
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	var initial_transform := camera.global_transform
	for i in range(300):
		if options.has("moving"):
			var angle := float(i) / 300.0 * TAU
			camera.global_position = center + Vector3(34.0 * sin(angle), 18.0, 34.0 * cos(angle)) * camera_scale * (1.0 + 0.15 * sin(angle * 2.0))
			camera.look_at(center)
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
	var average := 0.0
	for value in samples: average += value / samples.size()
	var variance := 0.0
	for value in samples: variance += pow(value - average, 2.0) / samples.size()
	var report := snapshot(light, environment, ground, camera)
	report.merge({"case": candidate, "mvr": options.get("mvr", "synthetic"), "moving": options.has("moving"), "initial_camera": str(initial_transform), "frame_ms_mean": average, "frame_ms_stddev": sqrt(variance), "fps_from_mean": 1000.0 / maxf(average, 0.001), "headless": DisplayServer.get_name() == "headless", "gpu_frame_ms": "unavailable; use Godot GPU profiler on target hardware", "objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
	var output: String = options.get("out", "user://ambient-audit")
	DirAccess.make_dir_recursive_absolute(output)
	var suffix := candidate + ("-moving" if options.has("moving") else "-stationary")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(suffix + ".png"))
	var file := FileAccess.open(output.path_join(suffix + ".json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write audit report: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	app.free()
	quit()

func apply_case(candidate: String, light: DirectionalLight3D, environment: Environment, ground: MeshInstance3D, camera: Camera3D) -> void:
	if candidate in ["clean", "ssao", "near", "depth32"]:
		if candidate == "ssao":
			environment.ssao_enabled = true
			environment.ssao_radius = 0.5
			environment.ssao_intensity = 0.25
		if candidate == "near": camera.near = 0.1
		if candidate == "depth32": RenderingServer.directional_shadow_atlas_set_size(4096, false)
		return
	# Original effective 4.7 desktop settings, including startup High SSAO.
	(environment.sky.sky_material as ProceduralSkyMaterial).use_debanding = true
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.use_taa = false
	light.light_angular_distance = 0.35
	environment.ssao_enabled = true
	environment.ssao_radius = 1.0
	environment.ssao_intensity = 0.5
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	(ground.mesh as PlaneMesh).size = Vector2(20000, 20000)
	ground.global_position = Vector3.ZERO
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	match candidate:
		"B": light.shadow_enabled = false
		"C": environment.ssao_enabled = false
		"D": light.light_angular_distance = 0.0
		"E": RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
		"F": root.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		"G": root.msaa_3d = Viewport.MSAA_4X
		"H": root.use_taa = true
		"I": ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"J": light.directional_shadow_max_distance = 36.0
		"msaa2": root.msaa_3d = Viewport.MSAA_2X

func snapshot(light: DirectionalLight3D, environment: Environment, ground: MeshInstance3D, camera: Camera3D) -> Dictionary:
	var report := {"godot": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(), "viewport_size": str(root.size), "window_size": str(DisplayServer.window_get_size()), "camera_transform": str(camera.global_transform), "resolution_3d": str(Vector2i(Vector2(root.size) * root.scaling_3d_scale)), "sky_debanding": (environment.sky.sky_material as ProceduralSkyMaterial).use_debanding, "directional_transform": str(light.global_transform), "directional_energy": light.light_energy, "directional_color": str(light.light_color), "ambient_energy": environment.ambient_light_energy, "ground_size": str((ground.mesh as PlaneMesh).size), "ground_position": str(ground.global_position), "ground_cast_shadow": ground.cast_shadow, "ground_material": "StandardMaterial3D grey .45; specular .45; roughness .78", "directional_filter_effective": "soft_low" if options.get("case", "clean") in ["A", "B", "C", "D", "F", "G", "H", "I", "J", "msaa2"] else "soft_medium", "directional_depth_bits_effective": 32 if options.get("case", "clean") == "depth32" else 16}
	for pair in [[root, ["msaa_3d", "screen_space_aa", "use_taa", "use_debanding", "scaling_3d_scale", "scaling_3d_mode", "positional_shadow_atlas_size"]], [light, ["light_angular_distance", "shadow_enabled", "shadow_bias", "shadow_normal_bias", "shadow_blur", "directional_shadow_mode", "directional_shadow_max_distance", "directional_shadow_split_1", "directional_shadow_split_2", "directional_shadow_split_3"]], [environment, ["ssao_enabled", "ssao_radius", "ssao_intensity", "ssil_enabled", "ssr_enabled"]], [camera, ["near", "far"]]]:
		for key in pair[1]: report[key] = pair[0].get(key)
	for key in ["lights_and_shadows/directional_shadow/size", "environment/ssao/quality"]:
		report[key] = ProjectSettings.get_setting("rendering/" + key)
	return report
