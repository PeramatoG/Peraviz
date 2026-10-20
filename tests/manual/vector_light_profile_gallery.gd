extends SceneTree

# Reproducible visual review fixture. Run with a real Forward+ renderer (software
# Vulkan is sufficient for captures, never for reference-scene FPS comparisons).
# Open surface projectors are enabled ONLY in this four-light review scene.
const Renderer = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd")
const Projector = preload("res://scripts/fixture_gobo_projector.gd")
const Cache = preload("res://scripts/beam_renderers/footprint_profile_cache.gd")
var renderer = Renderer.new()
var world: Node3D
var camera: Camera3D
var cache = Cache.new()

func _init() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 800)
	world = Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color(0.009, 0.013, 0.022)
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.02
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = settings
	world.add_child(environment)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(14, 8, 6)
	camera.look_at(Vector3(0, 1, -9))
	camera.fov = 56
	renderer.configure(camera, {"beam_presentation": 1})
	for mode in ["open-spot", "wash", "gobo", "near-far-footprint", "overlapping-white"]:
		var objects := Node3D.new()
		world.add_child(objects)
		if mode == "near-far-footprint":
			camera.position = Vector3(15, 10, 13)
			camera.look_at(Vector3(0, 1, -9))
			add_beam(objects, "Spot", Vector3(-4, 1, 0), false, 8)
			add_beam(objects, "Spot", Vector3(4, 1, 0), false, 16)
		else:
			camera.position = Vector3(14, 8, 6)
			camera.look_at(Vector3(0, 1, -9))
			add_beam(objects, "Wash" if mode == "wash" else "Spot", Vector3(0, 1, 0), mode == "gobo", 11 if mode == "gobo" else 0)
			if mode == "overlapping-white":
				add_beam(objects, "Spot", Vector3(0.7, 1, 0), false, 0)
		var label := Label.new()
		label.text = "Vector Gobo Prism | " + mode + "\nForward+ visual fixture | software Vulkan | no reference-scene FPS claim"
		label.position = Vector2(24, 20)
		label.add_theme_font_size_override("font_size", 20)
		root.add_child(label)
		for frame in range(12): await process_frame
		await RenderingServer.frame_post_draw
		var output: String = "res://docs/images/vector-light-profile/" + mode + ".png"
		root.get_texture().get_image().save_png(output)
		print("Captured ", output)
		label.free()
		objects.free()
		await process_frame
	quit()

func add_beam(parent: Node3D, kind: String, origin: Vector3, gobo: bool, wall_distance: float) -> void:
	var light := SpotLight3D.new()
	parent.add_child(light)
	light.position = origin
	light.spot_range = 50
	light.light_energy = 120
	light.light_color = Color.WHITE
	if gobo:
		var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		image.fill(Color.BLACK)
		for y in range(64):
			for x in range(64):
				var point := Vector2(x - 32, y - 32)
				if point.length() < 28 and (x < 25 or y > 36): image.set_pixel(x, y, Color.WHITE)
		var texture := ImageTexture.create_from_image(image)
		light.set_meta("peraviz_gobo_texture", texture)
		Projector.new()._set_light_projector_texture(light, texture)
	var params := {"beam_type": kind, "beam_angle": 12.0, "field_angle": 18.0 if gobo else 0.0, "beam_range": 20.0, "beam_visual_length_m": 20.0, "lens_radius": 0.03, "scaled_intensity": 12.0, "haze_density": 0.3, "beam_color": Color.WHITE, "beam_longitudinal_falloff": 1.1}
	renderer.update_beam(light, params)
	var state: RefCounted = light.get_meta(&"peraviz_optical_projection_state")
	if wall_distance > 0:
		if not gobo:
			# Isolated generic profile acceptance, not the production activation policy.
			Projector.new()._set_light_projector_texture(light, cache.texture_for(state.radial_profile, null))
			renderer.get_beam_resource(light).visible = false
		var wall := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(7, 7, 0.05)
		wall.mesh = box
		wall.position = origin + Vector3(0, 0, -wall_distance)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.65, 0.65, 0.65)
		wall.material_override = material
		parent.add_child(wall)
