extends SceneTree
## Opt-in, process-local comparisons; never save graphics or optical settings.
## Each B–J candidate changes exactly one factor from A. Clean is the new default.
const CASES := ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "clean", "msaa2", "ssao", "near", "depth32"]
const FOLLOWUP_CASES := ["old_bias", "bias_only", "normal_only","previous", "distance36", "distance48", "splits2", "splits_near", "filter_high", "filter_low", "filter_hard", "blur05", "blur025", "high_blur05", "atlas8192", "bias003", "normal_bias1", "no_shadows", "no_sun", "unshaded", "matte", "normals", "no_aa", "msaa4", "taa", "ground_hidden", "ground200", "ground1500", "ground_grey", "sky", "sky_deband", "viewport_deband", "no_post", "lod_original"]
var options := {}
var atlas_size := 4096
var depth_bits := 16
var filter_quality := 3

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts := arg.trim_prefix("--").split("=", true, 1)
		options[parts[0]] = parts[1] if parts.size() == 2 else "true"
	call_deferred("run")

func run() -> void:
	var candidate: String = options.get("case", "clean")
	if candidate not in CASES and candidate not in FOLLOWUP_CASES:
		push_error("Unknown comparison: " + candidate)
		quit(1)
		return
	if options.has("no-target-cast") and not options.has("target"):
		push_error("--no-target-cast requires --target")
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
	if options.has("hide-node"):
		var hidden := app.get_node_or_null(NodePath(options["hide-node"])) as Node3D
		if hidden == null:
			push_error("--hide-node must name an existing Node3D")
			quit(1)
			return
		hidden.hide()
	var camera: Camera3D = app.get_node("Camera3D")
	camera.set_process(false)
	camera.set_process_unhandled_input(false)
	var center: Vector3 = app._loaded_bounds.get_center() if app._has_loaded_bounds else Vector3.ZERO
	var camera_scale: float = maxf(1.0, app._loaded_bounds.size.length() / 30.0) if app._has_loaded_bounds else 1.0
	camera.global_position = center + Vector3(24, 18, 24) * camera_scale
	if options.has("target"):
		var target := app.get_node_or_null(NodePath(options.target)) as MeshInstance3D
		if target == null:
			push_error("--target must name a MeshInstance3D relative to Viewer")
			quit(1)
			return
		center = (target.global_transform * target.get_aabb()).get_center()
		if options.has("no-target-cast"): target.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var view: String = options.get("view", "overview")
	if view not in ["overview", "close", "flat", "distant"]:
		push_error("Unknown --view")
		quit(1)
		return
	if view == "close": camera_scale = 0.15
	if view == "flat": camera_scale = 0.3
	if view == "distant": camera_scale *= 3.0
	camera.global_position = center + Vector3(24, 18, 24) * camera_scale
	camera.look_at(center)
	var light: DirectionalLight3D = app.get_node("DirectionalLight3D")
	var environment: Environment = app.get_node("WorldEnvironment").environment
	var ground: MeshInstance3D = app.get_node("Ground")
	if not options.has("mvr"):
		var flat := MeshInstance3D.new()
		flat.name = "AuditFlatBox"
		var flat_box := BoxMesh.new()
		flat_box.size = Vector3(14, 0.1, 10)
		flat.mesh = flat_box
		app.add_child(flat)
		for tube_index in range(2):
			var tube := MeshInstance3D.new()
			tube.name = "AuditCylinder" + str(tube_index)
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.05
			cylinder.bottom_radius = 0.05
			cylinder.height = 10.0
			cylinder.radial_segments = 32
			tube.mesh = cylinder
			app.add_child(tube)
			tube.position = Vector3(0, 2.0, tube_index * 3 - 1.5)
			tube.rotation.z = PI / 2.0
		# Repeatable thin edges, contacts and uniform surfaces without DMX input.
		for i in range(12):
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.08 if i < 6 else 1.0, 3.0, 1.0)
			mesh.mesh = box
			app.add_child(mesh)
			mesh.position = Vector3((i % 6) * 2 - 5, 1.5, (i / 6) * 4 - 2)
	if candidate == "lod_original": app._asset_cache.derived_lods.set_automatic(false, root)
	apply_case(candidate, light, environment, ground, camera)
	if candidate in FOLLOWUP_CASES: isolate_geometry(app, candidate)
	var inventory := geometry_inventory(app.proxies_root)
	if options.has("world-offset"):
		var offset := Vector3(float(options["world-offset"]), 0, float(options["world-offset"]))
		app.position += offset
		center += offset
	var measure_gpu: bool = options.has("gpu-time") and DisplayServer.get_name() != "headless"
	if measure_gpu: RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	for i in range(maxi(1, int(options.get("warmup", "120")))): await process_frame
	var samples: Array[float] = []
	var gpu_samples: Array[float] = []
	var frame_count := maxi(10, int(options.get("frames", "300")))
	var previous := Time.get_ticks_usec()
	var initial_transform := camera.global_transform
	for i in range(frame_count):
		if options.has("moving"):
			var angle := float(i) / float(frame_count) * TAU
			camera.global_position = center + Vector3(34.0 * sin(angle), 18.0, 34.0 * cos(angle)) * camera_scale * (1.0 + 0.15 * sin(angle * 2.0))
			camera.look_at(center)
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now - previous) / 1000.0)
		previous = now
		if measure_gpu:
			var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
			if gpu_ms > 0.0: gpu_samples.append(gpu_ms)
	var average := 0.0
	for value in samples: average += value / samples.size()
	var variance := 0.0
	for value in samples: variance += pow(value - average, 2.0) / samples.size()
	var report := snapshot(light, environment, ground, camera)
	report.merge({"geometry_inventory": inventory, "target": options.get("target", "bounds center"), "target_cast_disabled": options.has("no-target-cast"), "hidden_node": options.get("hide-node", ""), "view": view, "world_offset": options.get("world-offset", "0"), "case": candidate, "mvr": options.get("mvr", "synthetic"), "moving": options.has("moving"), "initial_camera": str(initial_transform), "frame_ms_mean": average, "frame_ms_stddev": sqrt(variance), "fps_from_mean": 1000.0 / maxf(average, 0.001), "headless": DisplayServer.get_name() == "headless", "gpu_frame_ms": gpu_samples.reduce(func(total: float, value: float) -> float: return total + value, 0.0) / gpu_samples.size() if not gpu_samples.is_empty() else null, "gpu_timing_requested": options.has("gpu-time"), "gpu_sample_count": gpu_samples.size(), "sample_frames": frame_count, "objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
	var output: String = options.get("out", "user://ambient-audit")
	DirAccess.make_dir_recursive_absolute(output)
	var suffix := candidate + "-" + view + ("-moving" if options.has("moving") else "-stationary")
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
	if candidate in FOLLOWUP_CASES:
		match candidate:
			"old_bias":
				light.shadow_bias = 0.015
				light.shadow_normal_bias = 0.7
			"bias_only": light.shadow_normal_bias = 0.7
			"normal_only": light.shadow_bias = 0.015
			"previous":
				light.shadow_bias = 0.015
				light.shadow_normal_bias = 0.7
				(ground.mesh as PlaneMesh).size = Vector2(200, 200)
				ground.material_override = grey_material()
				environment.background_mode = Environment.BG_SKY
			"distance36": light.directional_shadow_max_distance = 36.0
			"distance48": light.directional_shadow_max_distance = 48.0
			"splits2": light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			"splits_near":
				light.directional_shadow_split_1 = 0.05
				light.directional_shadow_split_2 = 0.15
				light.directional_shadow_split_3 = 0.4
			"filter_high": filter_quality = 4
			"filter_low": filter_quality = 2
			"filter_hard": filter_quality = 0
			"blur05": light.shadow_blur = 0.5
			"blur025": light.shadow_blur = 0.25
			"high_blur05":
				filter_quality = 4
				light.shadow_blur = 0.5
			"atlas8192": atlas_size = 8192
			"bias003": light.shadow_bias = 0.03
			"normal_bias1": light.shadow_normal_bias = 1.0
			"no_shadows": light.shadow_enabled = false
			"no_sun": light.visible = false
			"no_aa": root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			"msaa4":
				root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
				root.msaa_3d = Viewport.MSAA_4X
			"taa":
				root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
				root.use_taa = true
			"ground_hidden": ground.hide()
			"ground200": (ground.mesh as PlaneMesh).size = Vector2(200, 200)
			"ground1500": (ground.mesh as PlaneMesh).size = Vector2(1500, 1500)
			"ground_grey": ground.material_override = grey_material()
			"sky", "sky_deband":
				environment.background_mode = Environment.BG_SKY
				(environment.sky.sky_material as ProceduralSkyMaterial).use_debanding = candidate == "sky_deband"
			"viewport_deband": root.use_debanding = true
			"no_post":
				environment.adjustment_enabled = false
				environment.glow_enabled = false
		RenderingServer.directional_soft_shadow_filter_set_quality(filter_quality)
		RenderingServer.directional_shadow_atlas_set_size(atlas_size, true)
		return
	if candidate in ["clean", "ssao", "near", "depth32"]:
		if candidate == "ssao":
			environment.ssao_enabled = true
			environment.ssao_radius = 0.5
			environment.ssao_intensity = 0.25
		if candidate == "near": camera.near = 0.1
		if candidate == "depth32":
			depth_bits = 32
			RenderingServer.directional_shadow_atlas_set_size(4096, false)
		return
	# Original effective 4.7 desktop settings, including startup High SSAO.
	(environment.sky.sky_material as ProceduralSkyMaterial).use_debanding = true
	environment.background_mode = Environment.BG_SKY
	ground.material_override = grey_material()
	filter_quality = 2
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.use_taa = false
	light.shadow_bias = 0.015
	light.shadow_normal_bias = 0.7
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
		"E":
			filter_quality = 3
			RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM)
		"F": root.screen_space_aa = Viewport.SCREEN_SPACE_AA_SMAA
		"G": root.msaa_3d = Viewport.MSAA_4X
		"H": root.use_taa = true
		"I": ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"J": light.directional_shadow_max_distance = 36.0
		"msaa2": root.msaa_3d = Viewport.MSAA_2X

func snapshot(light: DirectionalLight3D, environment: Environment, ground: MeshInstance3D, camera: Camera3D) -> Dictionary:
	var report := {"godot": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(), "viewport_size": str(root.size), "window_size": str(DisplayServer.window_get_size()), "camera_transform": str(camera.global_transform), "resolution_3d": str(Vector2i(Vector2(root.size) * root.scaling_3d_scale)), "sky_debanding": (environment.sky.sky_material as ProceduralSkyMaterial).use_debanding, "directional_transform": str(light.global_transform), "directional_energy": light.light_energy, "directional_color": str(light.light_color), "ambient_energy": environment.ambient_light_energy, "ground_size": str((ground.mesh as PlaneMesh).size), "ground_position": str(ground.global_position), "ground_cast_shadow": ground.cast_shadow, "ground_material": str(ground.material_override.albedo_color) if ground.material_override is StandardMaterial3D else "diagnostic shader", "ground_visible": ground.visible, "background_mode": environment.background_mode, "sun_visible": light.visible, "directional_filter_effective": filter_quality, "directional_depth_bits_effective": depth_bits, "directional_atlas_effective": atlas_size}
	for pair in [[root, ["msaa_3d", "screen_space_aa", "use_taa", "use_debanding", "scaling_3d_scale", "scaling_3d_mode", "positional_shadow_atlas_size"]], [light, ["light_angular_distance", "shadow_enabled", "shadow_bias", "shadow_normal_bias", "shadow_blur", "directional_shadow_mode", "directional_shadow_max_distance", "directional_shadow_split_1", "directional_shadow_split_2", "directional_shadow_split_3"]], [environment, ["ssao_enabled", "ssao_radius", "ssao_intensity", "ssil_enabled", "ssr_enabled"]], [camera, ["near", "far"]]]:
		for key in pair[1]: report[key] = pair[0].get(key)
	for key in ["lights_and_shadows/directional_shadow/size", "environment/ssao/quality"]:
		report[key] = ProjectSettings.get_setting("rendering/" + key)
	return report

func grey_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.45, 0.45)
	material.roughness = 0.78
	material.metallic_specular = 0.45
	return material

func isolate_geometry(app: Node, candidate: String) -> void:
	if candidate not in ["unshaded", "matte", "normals"]: return
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.5, 0.5)
	material.roughness = 1.0
	material.metallic_specular = 0.0
	if candidate == "unshaded": material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var override_material: Material = material
	if candidate == "normals":
		var shader := Shader.new()
		shader.code = "shader_type spatial; render_mode unshaded; void fragment() { ALBEDO = normalize(NORMAL) * 0.5 + 0.5; }"
		var normal_material := ShaderMaterial.new()
		normal_material.shader = shader
		override_material = normal_material
	# Instance overrides only; do not mutate shared imported materials or meshes.
	for node in app.find_children("*", "MeshInstance3D", true, false):
		if node == app.get_node("Ground") or app.proxies_root.is_ancestor_of(node) or node.get_parent() == app:
			node.material_override = override_material

func geometry_inventory(imported: Node) -> Dictionary:
	var records: Array = []
	var bounds_groups := {}
	var meshes := imported.find_children("*", "MeshInstance3D", true, false)
	for node in meshes.slice(0, 256):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null: continue
		var bounds := mesh.global_transform * mesh.get_aabb()
		var missing_normals := 0
		if mesh.mesh is ArrayMesh:
			for surface in range(mesh.mesh.get_surface_count()):
				if not mesh.mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_NORMAL: missing_normals += 1
		var path := str(imported.get_path_to(mesh))
		records.append({"path": path, "parent": str(mesh.get_parent().get_path()), "mesh_resource": mesh.mesh.resource_path, "mesh_id": mesh.mesh.get_instance_id(), "transform": str(mesh.global_transform), "basis_determinant": mesh.global_basis.determinant(), "bounds": str(bounds), "surfaces_missing_normals": missing_normals})
		var key := str(bounds)
		if not bounds_groups.has(key): bounds_groups[key] = []
		bounds_groups[key].append(path)
	var coincident_bounds: Array = []
	for group in bounds_groups.values():
		if group.size() > 1: coincident_bounds.append(group)
	return {"mesh_count": meshes.size(), "inspected_count": records.size(), "truncated": meshes.size() > 256, "meshes": records, "coincident_aabb_candidates_not_proven_coplanar_faces": coincident_bounds}
