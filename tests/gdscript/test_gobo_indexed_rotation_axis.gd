extends SceneTree

const PresentationScript = preload("res://scripts/runtime/gobo_indexed_rotation_presentation.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	for parent_rotation in [Vector3.ZERO, Vector3(0.0, 90.0, 0.0), Vector3(-50.0, 35.0, 0.0)]:
		for mirror_scale in [Vector3(1.0, 75.0, 1.0), Vector3(-1.0, 75.0, -1.0), Vector3(-1.0, 75.0, 1.0)]:
			_test_parent_orientation(parent_rotation, mirror_scale)
	_test_shader_alignment()
	test.finish(self)

func _test_parent_orientation(parent_rotation_degrees: Vector3, mirror_scale: Vector3) -> void:
	var parent := Node3D.new()
	var beam := MeshInstance3D.new()
	get_root().add_child(parent)
	parent.add_child(beam)
	parent.rotation_degrees = parent_rotation_degrees
	beam.position = Vector3(0.2, -0.3, 1.4)
	_establish_prism_base(beam, 180.0, mirror_scale)
	var original_position: Vector3 = beam.position
	var original_axis: Vector3 = beam.global_transform.basis.y.normalized()
	var original_lengths := Vector3(beam.transform.basis.x.length(), beam.transform.basis.y.length(), beam.transform.basis.z.length())
	var zero_transverse: Vector3 = beam.global_transform.basis.x.normalized()
	var zero_transverse_z: Vector3 = beam.global_transform.basis.z.normalized()
	for angle in [0.0, 30.0, 45.0, 90.0, 180.0, -90.0, 270.0, 360.0]:
		PresentationScript.apply_physical_angle(beam, angle, "vector_prism")
		_assert_prism_invariants(beam, original_axis, original_position, original_lengths, angle)
		if is_equal_approx(absf(angle), 180.0):
			test.check(beam.global_transform.basis.x.normalized().dot(zero_transverse) < -0.9999, "Pos 180 must flip the transverse gobo axis without reversing the beam")
		if is_equal_approx(angle, 90.0):
			test.check(beam.global_transform.basis.x.normalized().dot(zero_transverse_z) > 0.9999, "Positive Pos must follow the existing renderer local-Y handedness")
		if is_equal_approx(angle, -90.0):
			test.check(beam.global_transform.basis.x.normalized().dot(zero_transverse_z) < -0.9999, "Negative Pos must follow the opposite renderer local-Y handedness")
		if is_equal_approx(angle, 360.0):
			test.check(beam.global_transform.basis.x.normalized().dot(zero_transverse) > 0.9999, "Pos 360 must return to the Pos 0 transverse orientation")
	PresentationScript.apply_physical_angle(beam, 45.0, "vector_prism")
	var persisted_transverse: Vector3 = beam.global_transform.basis.x.normalized()
	for refresh in range(3):
		_establish_prism_base(beam, 180.0, mirror_scale)
		PresentationScript.reapply_after_base_alignment(beam)
		test.check(beam.global_transform.basis.y.normalized().dot(original_axis) > 0.999999, "Renderer refresh must preserve the optical axis")
		test.check(beam.global_transform.basis.x.normalized().dot(persisted_transverse) > 0.999999, "Renderer refresh must reapply Pos exactly once without accumulation")
	parent.queue_free()

func _establish_prism_base(beam: MeshInstance3D, base_alignment_degrees: float, mirror_scale: Vector3) -> void:
	beam.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	beam.scale = mirror_scale
	beam.rotate_object_local(Vector3.UP, deg_to_rad(-base_alignment_degrees))

func _assert_prism_invariants(beam: MeshInstance3D, original_axis: Vector3, original_position: Vector3, original_lengths: Vector3, angle: float) -> void:
	var basis: Basis = beam.transform.basis
	var lengths := Vector3(basis.x.length(), basis.y.length(), basis.z.length())
	test.check(beam.global_transform.basis.y.normalized().dot(original_axis) > 0.999999, "Pos %s must not tip or reverse the optical axis" % angle)
	test.check(beam.position.is_equal_approx(original_position), "Pos must not change beam position")
	test.check(lengths.is_equal_approx(original_lengths), "Pos must preserve beam scale and length")
	test.check(absf(basis.x.normalized().dot(basis.y.normalized())) < 0.000001 and absf(basis.y.normalized().dot(basis.z.normalized())) < 0.000001 and absf(basis.x.normalized().dot(basis.z.normalized())) < 0.000001, "Pos must not introduce shear")

func _test_shader_alignment() -> void:
	var beam := MeshInstance3D.new()
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial; instance uniform float gobo_rotation_deg = 0.0; void fragment() { ALBEDO = vec3(1.0); }"
	material.shader = shader
	beam.material_override = material
	get_root().add_child(beam)
	var original_basis: Basis = beam.transform.basis
	PresentationScript.apply_physical_angle(beam, 45.0, PresentationScript.SHADER_BACKEND)
	PresentationScript.reapply_after_base_alignment(beam, 180.0)
	test.check(beam.transform.basis == original_basis, "Shader Pos must not rotate beam geometry")
	test.check(is_equal_approx(float(beam.get_instance_shader_parameter("gobo_rotation_deg")), 135.0), "Shader Pos must combine base alignment and handedness exactly once")
	PresentationScript.apply_physical_angle(beam, -45.0, PresentationScript.SHADER_BACKEND)
	test.check(is_equal_approx(float(beam.get_instance_shader_parameter("gobo_rotation_deg")), 225.0), "Shader negative Pos must use the opposite presentation direction")
	beam.queue_free()
