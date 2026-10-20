extends SceneTree

# Forward+ shaft-energy regression with equal-area masks of different topology.
# Software Vulkan validates rendering, never reference-scene FPS performance.
const Renderer = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd")
const Projector = preload("res://scripts/fixture_gobo_projector.gd")
var renderer = Renderer.new()
var world: Node3D
var camera: Camera3D
var mode_complex: bool = false
var energies: Dictionary = {}
var background_linear: float = 0.0

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
	settings.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment = settings
	world.add_child(environment)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(14, 8, 6)
	camera.look_at(Vector3(0, 1, -9))
	camera.fov = 56
	renderer.configure(camera, {"beam_presentation": 1})
	for mode in ["energy-open", "energy-simple", "energy-complex", "energy-inside"]:
		mode_complex = mode == "energy-complex"
		var objects := Node3D.new()
		world.add_child(objects)
		camera.position = Vector3(14, 8, 6)
		camera.look_at(Vector3(0, 1, -9))
		add_beam(objects, mode != "energy-open")
		if mode == "energy-inside":
			camera.position = Vector3(0,1,-5)
			camera.look_at(Vector3(4,1,-9))
		var label := Label.new()
		label.text = "Vector Gobo Prism | " + mode + "\nForward+ visual fixture | software Vulkan | no reference-scene FPS claim"
		label.position = Vector2(24, 20)
		label.add_theme_font_size_override("font_size", 20)
		root.add_child(label)
		for frame in range(12): await process_frame
		await RenderingServer.frame_post_draw
		var output: String = "res://docs/images/vector-light-profile/" + mode + ".png"
		var captured := root.get_texture().get_image()
		captured.save_png(output)
		var energy := 0.0
		if mode == "energy-open": background_linear = captured.get_pixel(0,captured.get_height()-1).srgb_to_linear().r
		var baseline: float = background_linear
		for y in range(120, captured.get_height()):
			for x in range(captured.get_width()):
				energy += maxf(captured.get_pixel(x,y).srgb_to_linear().r - baseline,0.0)
		energies[mode] = energy
		print("Captured ", output)
		label.free()
		objects.free()
		await process_frame
	print("ENERGY ", JSON.stringify(energies))
	quit(1 if energies["energy-simple"] > energies["energy-open"] or energies["energy-complex"] > energies["energy-open"] or energies["energy-complex"] > energies["energy-simple"] * 1.02 or energies["energy-inside"] <= 1.0 else 0)

func add_beam(parent: Node3D, gobo: bool) -> void:
	var light := SpotLight3D.new()
	parent.add_child(light)
	light.position = Vector3(0, 1, 0)
	light.spot_range = 50
	light.light_energy = 120
	light.light_color = Color.WHITE
	if gobo:
		var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		# Identical open-pixel count: only the spatial topology differs.
		image.fill(Color.BLACK)
		for y in range(64):
			for x in range(64):
				if Vector2(x-32,y-32).length() < 28: image.set_pixel(x,y,Color.WHITE)
		for index in range(8):
			var cx := 14 + (index % 4) * 11
			var cy := 20 + (index / 4) * 23
			for y in range(int(cy)-2,int(cy)+3):
				for x in range(cx-2,cx+3): image.set_pixel(x,y,Color.BLACK)
		if not mode_complex:
			var count := 0
			var points: Array[Vector2i] = []
			for y in range(64):
				for x in range(64):
					if image.get_pixel(x,y).r > 0.5: count += 1
					points.append(Vector2i(x,y))
			points.sort_custom(func(a: Vector2i,b: Vector2i)->bool: return (Vector2(a)-Vector2(32,32)).length_squared() < (Vector2(b)-Vector2(32,32)).length_squared())
			image.fill(Color.BLACK)
			for index in range(count): image.set_pixelv(points[index],Color.WHITE)
		var texture := ImageTexture.create_from_image(image)
		light.set_meta("peraviz_gobo_texture", texture)
		Projector.new()._set_light_projector_texture(light, texture)
	var params := {"beam_type": "Spot", "beam_type_explicit": true, "beam_angle_explicit": true, "field_angle_explicit": true, "profile_beam_angle": 12.0, "beam_angle": 12.0, "field_angle": 18.0, "beam_range": 20.0, "beam_visual_length_m": 20.0, "lens_radius": 0.03, "scaled_intensity": 12.0, "haze_density": 0.3, "beam_color": Color.WHITE, "beam_longitudinal_falloff": 1.0}
	renderer.update_beam(light, params)
