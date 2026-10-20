extends SceneTree

const Profile = preload("res://scripts/beam_renderers/radial_light_profile.gd")
const Cache = preload("res://scripts/beam_renderers/footprint_profile_cache.gd")
const Builder = preload("res://scripts/beam_renderers/gobo_prism_mesh_builder.gd")
const Renderer = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd")
const Migration = preload("res://scripts/visual_settings_migration.gd")
const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()

func _init() -> void:
	call_deferred("run")

func run() -> void:
	for angles in [Vector2(10, 20), Vector2(20, 40), Vector2(35, 48), Vector2(60, 90)]:
		var profile = Profile.new()
		profile.configure("Spot", angles.x, angles.y)
		test.check(profile.anchored, "Valid metadata resolves an anchored profile")
		test.check_close(profile.sample_radius(0.0), 1.0, 0.00001, "Peak anchor")
		test.check_close(profile.sample_radius(1.0), 0.5, 0.00001, "Beam half-angle anchor")
		var field_radius := tan(deg_to_rad(angles.y * 0.5)) / tan(deg_to_rad(angles.x * 0.5))
		test.check_close(profile.sample_radius(field_radius), 0.1, 0.00001, "Field half-angle anchor")
		var previous: float = 1.0
		for index in range(1001):
			var value: float = profile.sample_radius(float(index) / 1000.0 * profile.support_scale)
			test.check(value <= previous + 0.000001 and is_finite(value), "Continuous monotonic finite profile")
			test.check(absf(previous - value) < 0.02, "No radial bands or discontinuities")
			previous = value
	var spot = Profile.new()
	spot.configure("Spot", 20, 0)
	for kind in ["Wash", "Fresnel", "PC"]:
		var soft = Profile.new()
		soft.configure(kind, 20, 0)
		test.check(soft.exponent < spot.exponent and soft.sample_radius(1.3) > spot.sample_radius(1.3), "Soft BeamTypes have longer shoulders than Spot")
	for invalid in [Vector2(0, 0), Vector2(25, 25), Vector2(25, 25.00001), Vector2(-10, 20), Vector2(NAN, INF), Vector2(30, 10)]:
		spot.configure("Spot", invalid.x, invalid.y)
		test.check(not spot.anchored and is_finite(spot.exponent), "Invalid/unstable angles use a finite fallback")
	spot.configure("Spot", NAN, INF)
	test.check(not spot.configure("Spot", NAN, INF), "Repeated invalid metadata reuses its fallback instead of rebuilding curves")
	for kind in ["None", "Glow"]:
		spot.configure(kind, 20, 40)
		test.check(not spot.projected and spot.sample_support(Vector2.ZERO) == 0.0, "None/Glow have no projection")
	spot.configure("Rectangle", 20, 0, 4.0)
	test.check_close(spot.sample_support(Vector2(spot.aspect.x * 0.5, 0)), spot.sample_support(Vector2(0, spot.aspect.y * 0.5)), 0.00001, "Rectangle uses its aperture metric")
	for length_m in [1.0, 12.0, 75.0, 150.0]:
		for decay in [0.0, 1.1, 4.0]:
			test.check(Profile.axial(length_m, length_m, decay) < Profile.TERMINAL_EPSILON and Profile.axial(length_m * 0.98, length_m, decay) == 0.0, "Finite shaft reaches zero before the end even with decay disabled")
		test.check(Profile.axial(0, length_m) > Profile.axial(length_m * 0.5, length_m) and Profile.axial(length_m * 0.5, length_m) > Profile.axial(length_m * 0.95, length_m), "Axial intensity decays continuously")
	test.check(Profile.surface_distance(5) > Profile.surface_distance(10), "Surface inverse-square baseline attenuates with distance")
	check_mesh(Builder.new().build_normalized_beam_mesh(null))
	var rectangle := Builder.new().build_normalized_rectangle_mesh(2.0)
	check_mesh(rectangle)
	var rectangle_vertices: PackedVector3Array = rectangle.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in rectangle_vertices:
		test.check(Vector2(vertex.x, vertex.z).length() <= 1.00001, "Rectangle corners fit within the common projector cone")
		test.check_close(absf(vertex.x / vertex.z), 2.0, 0.00001, "Normalized Rectangle preserves the GDTF aspect ratio")
	var cache = Cache.new()
	spot.configure("Spot", 20, 40)
	var texture: Texture2D = cache.texture_for(spot, null)
	var image := texture.get_image()
	test.check(image.get_pixel(64, 64).r > image.get_pixel(110, 64).r, "Open surface center is brighter than edge")
	test.check(cache.texture_for(spot, null) == texture and cache.creations == 1, "Repeated profile shares a cached resource")
	var texel := Vector2i(int((1.0 / spot.support_scale + 1.0) * 0.5 * Cache.SIZE), Cache.SIZE / 2)
	test.check_close(image.get_pixelv(texel).srgb_to_linear().r, 0.5, 0.04, "Projector atlas preserves the linear 50% anchor after sRGB decoding")
	var mask := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	mask.fill(Color.WHITE)
	mask.set_pixel(4, 4, Color.BLACK)
	var masked := cache.texture_for(spot, ImageTexture.create_from_image(mask)).get_image()
	test.check(masked.get_pixel(72, 72).r < image.get_pixel(72, 72).r, "Gobo transmission multiplies the shared envelope")
	test.check(Migration.migrate({"spot_multiplier": 0.7})["footprint_multiplier"] == 0.7, "Old project intensity migrates")
	test.check(Migration.migrate({"spot_multiplier": 0.7, "footprint_multiplier": 0.0})["footprint_multiplier"] == 0.0, "Explicit footprint blackout wins")
	await check_renderer()
	test.finish(self)

func check_mesh(mesh: ArrayMesh) -> void:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for index in range(0, vertices.size(), 3):
		test.check(not (is_equal_approx(vertices[index].y, vertices[index+1].y) and is_equal_approx(vertices[index].y, vertices[index+2].y)), "No axial gobo/aperture cap triangle exists")

func check_renderer() -> void:
	var light := SpotLight3D.new()
	get_root().add_child(light)
	var renderer = Renderer.new()
	renderer.configure(null, {"beam_presentation": 1})
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	light.set_meta("peraviz_gobo_texture", ImageTexture.create_from_image(image))
	light.light_projector = light.get_meta("peraviz_gobo_texture")
	var params := {"beam_type": "Spot", "beam_angle": 20.0, "field_angle": 40.0, "beam_angle_explicit": true, "field_angle_explicit": true, "beam_visual_length_m": 75.0, "beam_range": 75.0, "scaled_intensity": 20.0, "haze_density": 0.0}
	renderer.update_beam(light, params)
	var beam: MeshInstance3D = renderer.get_beam_resource(light)
	var state: RefCounted = light.get_meta(&"peraviz_optical_projection_state")
	var profile: RefCounted = state.radial_profile
	var revision: int = state.profile_revision
	var surface: Texture2D = light.light_projector
	var mesh := beam.mesh
	var creations: int = renderer._footprint_cache.creations
	test.check(beam.custom_aabb.has_point(Vector3(state.far_radius * 0.99, 0, 0)), "CPU culling encloses the shader-expanded optical support")
	test.check(beam.get_instance_shader_parameter("haze_density") == 0.0, "Zero haze is not replaced with a visibility floor")
	test.check(light.spot_attenuation == 2.0 and light.spot_angle_attenuation == 0.0, "Surface distance/angular controls have correct semantics")
	for frame in range(600):
		params["beam_angle"] = 10.0 + float(frame % 50)
		params["scaled_intensity"] = 1.0 + float(frame % 20)
		renderer.apply_beam_optics(light, params)
		renderer.update_beam_intensity(light, params)
		test.check(state.radial_profile == profile and state.profile_revision == revision and beam.mesh == mesh, "Zoom and intensity reuse the profile and mesh")
		test.check(light.light_projector == surface and renderer._footprint_cache.creations == creations, "No projector generation during Zoom/DMX playback")
	light.free()
	await process_frame
