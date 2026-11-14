extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640,360)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := preload("res://scripts/editor_camera.gd").new()
	viewport.add_child(camera)
	camera.current = true
	var model := MeshInstance3D.new()
	var box := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0,1,1)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material = material
	model.mesh = box
	viewport.add_child(model)
	for size in [Vector2i(640,360),Vector2i(360,640)]:
		viewport.size = size
		await process_frame
		for bounds in [AABB(Vector3.ONE * -0.0005,Vector3.ONE * 0.001),AABB(Vector3(-10000,-20000,-30000),Vector3(20000,40000,60000))]:
			box.size = bounds.size
			model.position = bounds.get_center()
			camera.focus_on_aabb(bounds)
			for corner in range(8):
				test.check(camera.is_position_in_frustum(bounds.get_endpoint(corner)),"Tiny/large scene corners are immediately framed and inside clipping distances in portrait/landscape")
			test.check(camera.current_distance == camera.target_distance,"First-render camera pose is already at the fitted distance")
			if OS.get_cmdline_user_args().has("--render-camera-probe"):
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var image: Image = viewport.get_texture().get_image()
				var pixels: int = 0
				for y in range(image.get_height()):
					for x in range(image.get_width()):
						var color: Color = image.get_pixel(x,y)
						if color.g > 0.5 and color.b > 0.5 and color.r < 0.2: pixels += 1
				test.check(pixels > 100,"Framed model produces actual viewport pixels")
				print("CAMERA_RENDER_PROBE ",JSON.stringify({"viewport":str(size),"bounds":str(bounds),"cyan_pixels":pixels,"near":camera.near,"far":camera.far,"distance":camera.target_distance}))
	viewport.free()
	test.finish(self)
