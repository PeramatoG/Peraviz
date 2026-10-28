extends RefCounted

# Opt-in real-renderer companion to the normal headless contract test; no timing/FPS assertions.
static func run(owner: SceneTree, source: ArrayMesh, derived: ArrayMesh, foreground_level: float = 0.2) -> void:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	owner.root.add_child(viewport)
	var camera := Camera3D.new()
	camera.fov = 50
	viewport.add_child(camera)
	camera.current = true
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.03,0.03,0.03)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.2
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35,-25,0)
	sun.shadow_enabled = false
	viewport.add_child(sun)
	var mesh := MeshInstance3D.new()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	viewport.add_child(mesh)
	var near_count: int = 0
	var far_count: int = 0
	var minimum_lit_pixels: int = 1000000
	var output: String = ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--lod-output="): output = argument.trim_prefix("--lod-output=")
	if not output.is_empty(): DirAccess.make_dir_recursive_absolute(output)
	for size in [128,512]:
		viewport.size = Vector2i(size,size)
		for distance in [1.0,4.0,16.0,64.0]:
			camera.position = Vector3(0.0,0.0,distance)
			camera.look_at(Vector3(0,-0.05,0))
			for threshold in [0.0,1.0,4.0]:
				viewport.mesh_lod_threshold = threshold
				var samples: Array = []
				var setup: Array = []
				for variant in [source,derived]:
					var start := Time.get_ticks_usec()
					mesh.mesh = variant
					setup.append(Time.get_ticks_usec()-start)
					for frame in range(3): await RenderingServer.frame_post_draw
					samples.append({"image":viewport.get_texture().get_image(), "primitives":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
				var metrics: Dictionary = compare(samples[0].image,samples[1].image,foreground_level)
				if threshold == 0.0:
					owner.test.check(samples[0].primitives == samples[1].primitives and metrics.mean_error < 0.0001, "LOD disabled preserves highest-detail geometry and shaded textured appearance")
				if size == 512 and distance == 1.0 and threshold == 1.0: near_count = samples[1].primitives
				if size == 512 and distance == 64.0 and threshold == 1.0: far_count = samples[1].primitives
				if distance <= 4: minimum_lit_pixels = mini(minimum_lit_pixels,metrics.foreground_pixels)
				var result := {"size":size,"distance":distance,"threshold":threshold,"reference_primitives":samples[0].primitives,"lod_primitives":samples[1].primitives,"assignment_us":setup,"pixels":metrics}
				print("RUNTIME_MESH_LOD_GRAPHICS ",JSON.stringify(result))
				if not output.is_empty() and threshold == 1.0:
					samples[0].image.save_png(output.path_join("reference_%d_%d.png" % [size,distance]))
					samples[1].image.save_png(output.path_join("lod_%d_%d.png" % [size,distance]))
	owner.test.check(minimum_lit_pixels > 100 and far_count > 0 and far_count < near_count, "Actual native LOD draws fewer distant triangles with nonempty visible casing")
	# Godot selects existing index levels as the camera moves. No generation or node replacement.
	viewport.size = Vector2i(512,512)
	viewport.mesh_lod_threshold = 1.0
	var sweep: Array = []
	for distance in [1,2,4,8,16,32,64,32,16,8,4,2,1]:
		camera.position.z = distance
		camera.look_at(Vector3(0,-0.05,0))
		for frame in range(3): await RenderingServer.frame_post_draw
		sweep.append(viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME))
	owner.test.check(sweep[0] == sweep[-1] and mesh.mesh == derived, "Camera return restores the same LOD using one retained mesh")
	print("RUNTIME_MESH_LOD_SWEEP ",JSON.stringify({"primitives":sweep,"renderer":RenderingServer.get_video_adapter_name()}))
	viewport.free()

static func compare(reference_image: Image, actual: Image, foreground_level: float = 0.2) -> Dictionary:
	var total: float = 0.0
	var maximum: float = 0.0
	var changed: int = 0
	var foreground: int = 0
	for y in range(reference_image.get_height()):
		for x in range(reference_image.get_width()):
			var a: Color = reference_image.get_pixel(x,y)
			var b: Color = actual.get_pixel(x,y)
			var error: float = maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
			total += error
			maximum = maxf(maximum,error)
			if error > 1.0/255.0: changed += 1
			if maxf(a.r,maxf(a.g,a.b)) > foreground_level: foreground += 1
	return {"mean_error":total/(reference_image.get_width()*reference_image.get_height()),"max_error":maximum,"changed_pixels":changed,"foreground_pixels":foreground}
