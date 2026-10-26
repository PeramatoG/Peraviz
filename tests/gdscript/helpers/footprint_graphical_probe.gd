extends RefCounted

const Harness = preload("res://tests/gdscript/helpers/footprint_loader.gd")
const Service = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const Volume = preload("res://scripts/beam_renderers/custom_footprint_volume.gd")

class Bindings extends RefCounted:
	var loader: Node
	func get_dense_presentation_bindings() -> Dictionary: return loader.get_dense_presentation_bindings()

func run(tree: SceneTree, test: RefCounted) -> void:
	var directory := "user://footprint-probe"
	var count := 6
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--footprint-output="): directory = arg.trim_prefix("--footprint-output=")
		if arg.begins_with("--footprint-count="): count = maxi(1, int(arg.trim_prefix("--footprint-count=")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 640)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	tree.root.add_child(viewport)
	var stage := Node3D.new()
	viewport.add_child(stage)
	var camera := Camera3D.new()
	camera.position = Vector3(15, 12, 20)
	camera.fov = 45.0
	stage.add_child(camera)
	camera.look_at(Vector3(0, 2, -1))
	var camera_transform: Transform3D = camera.transform
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.005,0.005,0.005)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.15
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	stage.add_child(environment)
	_add_box(stage, Vector3(0,-0.15,0), Vector3(20,0.3,18))
	for x in [-5.0, 0.0, 5.0]: _add_box(stage, Vector3(x,3,-5), Vector3(4.8,6,0.2))
	var ramp := _add_box(stage, Vector3(5,0.9,2), Vector3(4,0.2,5))
	ramp.rotation_degrees.x = -28.0
	var loader := Harness.new()
	loader.output_count = count
	loader.vector_prism = true
	loader._visual_settings = {"beam_presentation": 1, "footprint_backend": "custom", "footprint_max_range": 25.0, "footprint_multiplier": 2.0, "enable_realtime_spotlights": false, "beam_multiplier": 0.0}
	viewport.add_child(loader)
	await tree.process_frame
	loader.renderer.configure(camera, loader._visual_settings)
	var textures: Array[Texture2D] = _patterns(directory)
	for i in range(count):
		var anchor: SpotLight3D = loader.anchors[i]
		anchor.set_meta(&"peraviz_footprint_backend", "custom")
		var column: int = i % 3
		var x: float = (column - 1) * 5.0
		if i % 6 < 3:
			anchor.position = Vector3(x,6,3)
			anchor.look_at(Vector3(x,0,2), Vector3.FORWARD)
		else:
			anchor.position = Vector3(x,3,2)
			anchor.look_at(Vector3(x,3,-5))
		if count > 6:
			var side: int = ceili(sqrt(float(count)))
			anchor.position = Vector3((i % side - side * 0.5) * 0.55, 4, (floorf(float(i) / side) - side * 0.5) * 0.55)
			anchor.look_at(anchor.position + Vector3(0.05,-1,-0.1), Vector3.FORWARD)
		var mechanical := Node3D.new()
		mechanical.position = anchor.position
		loader.add_child(mechanical)
		anchor.reparent(mechanical, true)
		anchor.spot_range = 25.0
		anchor.set_meta("test_beam_type", "Spot" if column != 1 else "Wash")
		if column == 0: anchor.set_meta("peraviz_gobo_texture", textures[0 if i % 6 < 3 else 1])
	if count > 6:
		camera.position = Vector3(23,28,30)
		camera.look_at(Vector3.ZERO)
		loader._visual_settings.footprint_max_range = 8.0
	var service = Service.new()
	loader.dense_service = service
	loader._fixture_light_apply_service = service
	var bindings := Bindings.new()
	bindings.loader = loader
	test.check(await service.install_dense_presentation(loader, bindings), "Graphical scene installs production surface backend")
	var adapter = service._dense_adapter
	var frame: Dictionary = loader.frame(1.0, 1.0)
	# Keep identical white/color physical inputs for every reference/custom pass.
	for i in range(count):
		frame.floats[count * 5 + i * 4 + 1] = 1.0
		frame.floats[count * 5 + i * 4 + 2] = 1.0
	service.compose_dense_snapshot(frame.descriptors, frame.integers, frame.floats)
	service.end_visual_snapshot()
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var results: Array = []
	var center_reference := Color.BLACK
	for backend in (["custom", "native"] if count <= 6 else ["custom"]):
		adapter._diagnostic_open_surface_lights = backend == "native"
		loader._visual_settings.footprint_backend = backend
		loader.renderer.configure(camera, loader._visual_settings)
		service.refresh_dense_renderer()
		for anchor in loader.anchors: loader.renderer.get_beam_resource(anchor).visible = false
		var stats := await _capture(tree, viewport, directory.path_join(backend + ".png"))
		if backend == "custom":
			var update_usec: int = 0
			for iteration in range(6):
				var update: Dictionary = loader.frame(0.8 + iteration * 0.02, 0.5)
				var started := Time.get_ticks_usec()
				service.compose_dense_snapshot(update.descriptors, update.integers, update.floats)
				service.end_visual_snapshot()
				update_usec += Time.get_ticks_usec() - started
			stats["physical_update_cpu_ms"] = float(update_usec) / 6000.0
			service.compose_dense_snapshot(frame.descriptors, frame.integers, frame.floats)
			service.end_visual_snapshot()
		stats["backend"] = backend
		stats["projectors"] = count
		stats["resources"] = adapter.diagnostics().custom_projector_resources
		stats["shadowed_projector_lights"] = adapter.diagnostics().surface_lights.shadowed_projector_lights
		stats["open_light_diagnostic"] = backend == "native"
		stats["native_surface_lights"] = adapter.diagnostics().surface_lights.active_surface_lights
		results.append(stats)
		if backend == "custom" and count == 6:
			_check_receivers(viewport, camera, loader, test, ramp)
			var pixel := Vector2i(camera.unproject_position(Vector3(0,0,2)))
			center_reference = viewport.get_texture().get_image().get_pixel(pixel.x,pixel.y)
		test.check(stats.lit_pixels > 100, "Real Forward+ rendering produces visible " + backend + " footprints")
	adapter._diagnostic_open_surface_lights = false
	if count == 6:
		# Focused normal-method comparison on exactly the same opaque geometry.
		loader._visual_settings.footprint_backend = "custom"
		loader.renderer.configure(camera, loader._visual_settings)
		service.refresh_dense_renderer()
		for anchor in loader.anchors: loader.renderer.get_beam_resource(anchor).visible = false
		var derivative := Shader.new()
		derivative.code = Volume.SHADER.code.replace("uniform sampler2D normal_texture : hint_normal_roughness_texture, repeat_disable, filter_nearest;", "").replace("normalize(textureLod(normal_texture, SCREEN_UV, 0.0).xyz * 2.0 - 1.0)", "normalize(cross(dFdy(view_position), dFdx(view_position)))")
		for volume in adapter._footprints.volumes: volume.material_override.shader = derivative
		var derivative_stats := await _capture(tree, viewport, directory.path_join("depth-derivatives.png"))
		derivative_stats["backend"] = "custom-depth-derivatives-diagnostic"
		results.append(derivative_stats)
		# Perspective, roll and hierarchy changes while physical input is held.
		for i in range(count):
			var handle = adapter._outputs[i].lights[0]
			loader._fixture_gobo_projector.set_presentation_rotation(handle.light, 67.0)
			if i % 3 == 0:
				handle.params.beam_angle = 15.0
				loader.renderer.apply_beam_optics(handle.light, handle.params)
				handle.light.get_parent().rotation_degrees.y += 8.0
		for volume in adapter._footprints.volumes: volume.material_override.shader = Volume.SHADER
		results.append(await _capture(tree, viewport, directory.path_join("held-rotation-zoom.png")))

	if count == 6:
		for index in [0, 3]:
			var handle = adapter._outputs[index].lights[0]
			handle.params["beam_gobo_mirror_x"] = false
			loader.renderer.apply_beam_optics(handle.light, handle.params)
		await _capture(tree, viewport, directory.path_join("mirror-parity.png"))
		_check_receivers(viewport, camera, loader, test, ramp)
	if count == 6:
		camera.position = Vector3(0,3,2.5)
		camera.look_at(Vector3(0,0,2), Vector3.FORWARD)
		var inside := await _capture(tree, viewport, directory.path_join("camera-inside.png"))
		var pixel := Vector2i(camera.unproject_position(Vector3(0,0,2)))
		var inside_color := viewport.get_texture().get_image().get_pixel(pixel.x,pixel.y)
		test.check(absf(inside_color.r - center_reference.r) < 0.03, "Normal/incident spaces and exit-face rasterization remain correct with camera inside volume")
		results.append(inside)
		for volume in adapter._footprints.volumes: volume.configure(volume.projection, 2.0)
		var limited := await _capture(tree, viewport, directory.path_join("range-limited.png"))
		test.check(limited.lit_pixels == 0, "Finite projector range rejects opaque receivers beyond its bound")
	camera.transform = camera_transform
	var dark: Dictionary = loader.frame(0.0, 0.5)
	service.compose_dense_snapshot(dark.descriptors, dark.integers, dark.floats)
	service.end_visual_snapshot()
	var blackout := await _capture(tree, viewport, directory.path_join("blackout.png"))
	test.check(blackout.draw_calls == 5 and blackout.lit_pixels == 0, "Blackout suppresses actual volume submissions as well as light emission")
	blackout["backend"] = "custom-blackout"
	results.append(blackout)
	var report := {"adapter": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "measurements": results}
	print("CUSTOM_FOOTPRINT_GRAPHICS ", JSON.stringify(report))
	var file := FileAccess.open(directory.path_join("measurements.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	service.reset_scene_state()
	for anchor in loader.anchors: loader.renderer.cleanup_beam(anchor)
	viewport.free()
	await tree.process_frame

func _check_receivers(viewport: SubViewport, camera: Camera3D, loader: Node, test: RefCounted, ramp: MeshInstance3D) -> void:
	var image := viewport.get_texture().get_image()
	for index in range(6):
		var anchor: SpotLight3D = loader.anchors[index]
		var projection: RefCounted = anchor.get_meta(&"peraviz_optical_projection_state")
		var tangent: float = tan(deg_to_rad(projection.half_angle_deg))
		var local := Vector3(-0.45 * tangent, 0.3 * tangent, -1) if index % 3 == 0 else Vector3.FORWARD
		var direction: Vector3 = anchor.global_basis * local
		var plane := Plane(Vector3.UP, 0.0) if index < 3 else Plane(Vector3.BACK, -4.9)
		if index == 2: plane = Plane(ramp.global_basis.y, ramp.global_position + ramp.global_basis.y * 0.1)
		var hit: Variant = plane.intersects_ray(anchor.global_position, direction)
		test.check(hit != null, "Optical ray reaches receiver")
		if hit == null: continue
		var pixel := Vector2i(camera.unproject_position(hit))
		var color := image.get_pixel(pixel.x, pixel.y)
		test.check(maxf(color.r,maxf(color.g,color.b)) > 0.15, "Projected image/profile visibly reaches receiver %d (floor, wall, incline)" % index)

func _capture(tree: SceneTree, viewport: SubViewport, path: String) -> Dictionary:
	for iteration in range(8):
		await tree.process_frame
		await RenderingServer.frame_post_draw
	var cpu := 0.0
	var gpu := 0.0
	for iteration in range(6):
		await tree.process_frame
		await RenderingServer.frame_post_draw
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid())
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
	var image := viewport.get_texture().get_image()
	image.save_png(path)
	var lit: int = 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x,y)
			if maxf(color.r,maxf(color.g,color.b)) > 0.15: lit += 1
	return {"cpu_render_ms": cpu / 6.0, "gpu_render_ms": gpu / 6.0, "draw_calls": viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME), "lit_pixels": lit}

func _add_box(parent: Node3D, position: Vector3, size: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	mesh.position = position
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.25,0.25,0.25)
	mesh.material_override = material
	parent.add_child(mesh)
	return mesh

func _patterns(directory: String) -> Array[Texture2D]:
	# Generated asymmetric original raster files, independent of shaft polygons.
	var image := Image.create(64,64,false,Image.FORMAT_RGBA8)
	for y in range(64):
		for x in range(64):
			var p := (Vector2(x,y) - Vector2(31.5,31.5)) / 30.0
			var open: bool = p.length() < 0.9 and (p.x < -0.2 or p.y < -0.15 or absf(p.length() - 0.65) < 0.08)
			image.set_pixel(x,y,Color(1,1,1,1 if open else 0))
	image.save_png(directory.path_join("original.png"))
	var png := Image.load_from_file(directory.path_join("original.png"))
	# BMP is intentionally loaded through Godot's real BMP decoder as well.
	var bytes := PackedByteArray()
	bytes.resize(54 + 64 * 64 * 3)
	bytes[0] = 66; bytes[1] = 77
	bytes.encode_u32(2, bytes.size()); bytes.encode_u32(10, 54); bytes.encode_u32(14, 40)
	bytes.encode_u32(18, 64); bytes.encode_u32(22, 64); bytes.encode_u16(26, 1); bytes.encode_u16(28, 24)
	for y in range(64):
		for x in range(64):
			var value := int(image.get_pixel(x,63-y).a * 255)
			for c in range(3): bytes[54 + (y * 64 + x) * 3 + c] = value
	var file := FileAccess.open(directory.path_join("original.bmp"), FileAccess.WRITE)
	file.store_buffer(bytes); file.close()
	var bmp := Image.load_from_file(directory.path_join("original.bmp"))
	png.generate_mipmaps(); bmp.generate_mipmaps()
	return [ImageTexture.create_from_image(png), ImageTexture.create_from_image(bmp)]
