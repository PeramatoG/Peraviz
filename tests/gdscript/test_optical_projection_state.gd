extends SceneTree

const ProjectionState = preload("res://scripts/runtime/optical_projection_state.gd")
const Renderer = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd")
const Projector = preload("res://scripts/fixture_gobo_projector.gd")
const Rotation = preload("res://scripts/runtime/gobo_indexed_rotation_presentation.gd")
const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var fixture := Node3D.new()
	var light := SpotLight3D.new()
	var camera := Camera3D.new()
	get_root().add_child(fixture)
	fixture.add_child(light)
	get_root().add_child(camera)
	light.position = Vector3(0.2, 0.4, -0.1)
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	image.set_pixel(1, 1, Color.BLACK)
	var texture := ImageTexture.create_from_image(image)
	light.set_meta("peraviz_gobo_texture", texture)
	var renderer = Renderer.new()
	renderer.configure(camera, {"beam_presentation": 1})
	var projector = Projector.new()
	var params := {"beam_type": "Spot", "beam_angle": 25.0, "beam_range": 12.0, "lens_radius": 0.03, "lens_offset_m": 0.015, "scaled_intensity": 10.0, "beam_color": Color.WHITE, "beam_gobo_mirror_x": true, "beam_gobo_mirror_z": false}
	renderer.update_beam(light, params)
	var beam: MeshInstance3D = renderer.get_beam_resource(light)
	var state = ProjectionState.resolve(light)
	var original: Transform3D = beam.transform
	var original_light: Transform3D = light.transform
	var mesh: Mesh = beam.mesh
	test.check(beam.get_meta(ProjectionState.META) == state, "Shaft and footprint share state identity")
	for angle in [5.0, 60.0, 12.0, 100.0, 25.0]:
		var before: int = state.revision
		params["beam_angle"] = angle
		renderer.apply_beam_optics(light, params)
		test.check(state.revision == before + 1, "One Zoom creates one projection revision")
		check_consumers(state, light, beam)
		var zoom_transform: Transform3D = beam.transform
		var revision: int = state.revision
		renderer.apply_beam_optics(light, params)
		test.check(state.revision == revision and beam.transform.is_equal_approx(zoom_transform) and beam.mesh == mesh, "Identical Zoom preserves revision, transform and topology")
	test.check(beam.transform.is_equal_approx(original) and light.transform.is_equal_approx(original_light), "Returning Zoom restores original geometry")
	for step in range(600):
		# Indexed and advancing continuous phase use the same presentation entry.
		var roll: float = 45.0 if step < 10 else float(step) * 1.73
		fixture.rotation = Vector3(float(step) * 0.003, float(step) * 0.005, 0.0)
		Rotation.apply_physical_angle(beam, roll, "vector_prism")
		projector.set_presentation_rotation(light, roll)
		params["beam_angle"] = 5.0 + float(step % 70)
		renderer.apply_beam_optics(light, params)
		check_consumers(state, light, beam)
		var revision: int = state.revision
		var shaft_before: Transform3D = beam.transform
		var footprint_before: Transform3D = light.transform
		camera.transform = Transform3D(Basis.from_euler(Vector3(step, step * 0.2, step * 0.7)), Vector3(step, -step, step * 3))
		params["beam_color"] = Color(float(step % 7) / 7.0, 0.2, 0.5)
		renderer.update_beam_intensity(light, params)
		test.check(state.revision == revision and beam.transform.is_equal_approx(shaft_before) and light.transform.is_equal_approx(footprint_before), "Camera/color/intensity cannot rebuild projection")
	# Zoom while black must not leave an initialized mesh on the old aperture.
	params["scaled_intensity"] = 0.0
	params["beam_angle"] = 33.0
	renderer.apply_beam_optics(light, params)
	test.check(not beam.visible, "Blackout retains hidden projection")
	check_consumers(state, light, beam)
	params["scaled_intensity"] = 10.0
	renderer.update_beam_intensity(light, params)
	test.check(beam.visible, "Reactivation reuses synchronized geometry")
	projector.set_presentation_rotation(light, 0.0)
	params["beam_angle"] = 25.0
	renderer.apply_beam_optics(light, params)
	test.check(beam.transform.is_equal_approx(original) and light.transform.is_equal_approx(original_light), "Sustained playback has no cumulative local drift")
	for mirrors in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		params["beam_gobo_mirror_x"] = mirrors.x > 0
		params["beam_gobo_mirror_z"] = mirrors.y > 0
		params["beam_gobo_alignment_rotation_deg"] = 17.0
		params["gobo_scale"] = 1.7
		projector.set_presentation_rotation(light, 73.0)
		renderer.apply_beam_optics(light, params)
		check_consumers(state, light, beam)
	fixture.free()
	camera.free()
	await process_frame
	test.finish(self)

func check_consumers(state: RefCounted, light: SpotLight3D, beam: MeshInstance3D) -> void:
	test.check(state.shaft_revision == state.revision and state.footprint_revision == state.revision, "Both consumers have current revision")
	test.check_close(light.spot_angle * 2.0, state.full_angle_deg, 0.0001, "Projector half angle comes from canonical full angle")
	test.check(beam.global_basis.x.normalized().dot(light.global_basis.x.normalized()) > 0.99999, "Source artwork X follows the projector texture U direction")
	# Godot Forward+ spot projection uses biased clip XY and flips atlas V:
	# U = 0.5 + X/(2*depth*tan(half_angle)), V = 0.5 - Y/(2*depth*tan(half_angle)).
	# Compare asymmetric source coordinates, not a circular/symmetric silhouette.
	# Normalize the finite-lens cross section; the point projector has no near radius.
	for artwork in [Vector2(-0.7, -0.35), Vector2(0.2, -0.6), Vector2(0.55, 0.8)]:
		var prism_point := Vector3(artwork.x, -0.5, artwork.y)
		var local_point: Vector3 = light.global_transform.affine_inverse() * (beam.global_transform * prism_point)
		var projector_uv := Vector2(0.5 + local_point.x * 0.5, 0.5 - local_point.y * 0.5)
		var source_uv: Vector2 = (artwork + Vector2.ONE) * 0.5
		test.check(projector_uv.is_equal_approx(source_uv), "Asymmetric prism artwork maps to the same footprint texel without U/V reflection")
	var far_radius: float = beam.get_instance_shader_parameter("topology_far_radius")
	var near_radius: float = beam.get_instance_shader_parameter("topology_near_radius")
	test.check_close(far_radius - near_radius, tan(deg_to_rad(light.spot_angle)) * state.visual_range, 0.0002, "Shaft spread and projector use one aperture tangent")
	var apex: Vector3 = beam.global_transform * Vector3(0, 0.5, 0)
	test.check(apex.is_equal_approx(light.global_position), "Shaft near origin and projector share optical origin")
	test.check(beam.global_basis.y.normalized().dot(light.global_basis.z.normalized()) > 0.99999, "Shaft and footprint share optical axis through Pan/Tilt and roll")
