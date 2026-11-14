extends SceneTree

# Isolates first visibility from decoding and node construction. --rendered checks
# real Forward+ pixels and frame acknowledgments; headless only measures scheduling.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	scene.hide()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0,1,1)
	var shared := BoxMesh.new()
	shared.size = Vector3(0.025,0.025,0.025)
	shared.material = material
	for i in range(10000):
		var instance := MeshInstance3D.new()
		instance.mesh = shared
		instance.position = Vector3(i % 100, int(i / 100.0), 0) * 0.03
		scene.add_child(instance)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(1.5,1.5,5)
	camera.current = true
	await process_frame
	var budget := SceneLoadBudget.new()
	budget.tree = self
	budget.current = func() -> bool: return true
	var readiness := preload("res://scripts/scene_loading/scene_render_readiness.gd").new()
	var started := Time.get_ticks_usec()
	var ready: bool = await readiness.prepare_scene(scene,budget)
	var elapsed := (Time.get_ticks_usec()-started)/1000.0
	var pixels: int = -1
	if OS.get_cmdline_user_args().has("--rendered"):
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		pixels = 0
		for y in range(capture.get_height()):
			for x in range(capture.get_width()):
				var color: Color = capture.get_pixel(x,y)
				if color.g > 0.5 and color.b > 0.5 and color.r < 0.2: pixels += 1
		if pixels < 100: ready = false
	print("ACTIVATION_BENCHMARK ",JSON.stringify({"ok":ready,"activation_ms":elapsed,"cyan_pixels":pixels,"metrics":readiness.metrics,"renderer":RenderingServer.get_video_adapter_name()}))
	scene.free()
	camera.free()
	quit(0 if ready else 1)
