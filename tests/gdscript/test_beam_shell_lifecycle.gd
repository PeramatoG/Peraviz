extends SceneTree

const BeamAppearanceProfileScript = preload("res://scripts/beam_appearance_profile.gd")
const BeamGeometryCalculatorScript = preload("res://scripts/beam_geometry_calculator.gd")
const LegacyConeBeamRendererScript = preload("res://scripts/beam_renderers/legacy_cone_beam_renderer.gd")

var failures: Array[String] = []

func _init() -> void:
	_run()
	if failures.is_empty():
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _run() -> void:
	_test_shell_sample_contract()
	_test_lightweight_field_core_lifecycle()

func _test_shell_sample_contract() -> void:
	_check_close(float(BeamGeometryCalculatorScript.far_radius_for_full_angle(0.05, 25.0, 75.0).get("far_radius_m", 0.0)), 16.6770997, 0.0001, "25 degree 75 m geometry must match the known-good beam radius")
	_check_close(float(BeamGeometryCalculatorScript.far_radius_for_full_angle(0.05, 25.0, 100.0).get("far_radius_m", 0.0)), 22.2194663, 0.0001, "25 degree 100 m geometry must match the known-good beam radius")
	var near_radius := 0.05
	for beam_type in ["Spot", "Wash", "PC", "Fresnel", "Rectangle", "__absent__"]:
		var params := {"beam_angle": 25.0, "beam_visual_length_m": 75.0, "lens_radius": near_radius}
		if beam_type != "__absent__":
			params["beam_type"] = beam_type
		var profile: Dictionary = BeamAppearanceProfileScript.resolve(params, {})
		var shell_radius_norm := BeamAppearanceProfileScript.circular_normalized_radius(near_radius, 0.0, near_radius)
		if str(profile.get("shape", "")) == "rectangle":
			shell_radius_norm = BeamAppearanceProfileScript.rectangular_normalized_radius(near_radius, 0.0, near_radius, near_radius)
		_check_close(shell_radius_norm, 1.0, 0.0001, "Shell sample should represent a point on the envelope for %s" % [beam_type if beam_type != "__absent__" else "default Wash"])
		_check(BeamAppearanceProfileScript.shell_sample_energy(profile, shell_radius_norm) > 0.0, "Shell sample energy must remain visible for %s" % [beam_type if beam_type != "__absent__" else "default Wash"])

func _test_lightweight_field_core_lifecycle() -> void:
	var renderer = LegacyConeBeamRendererScript.new()
	var light := SpotLight3D.new()
	get_root().add_child(light)
	var params := {
		"beam_type": "Spot",
		"beam_angle": 25.0,
		"beam_visual_length_m": 75.0,
		"beam_range": 75.0,
		"lens_radius": 0.05,
		"render_near_radius_m": 0.05,
		"beam_color": Color.WHITE,
		"scaled_intensity": 10.0,
		"beam_intensity": 10.0,
		"intensity_max": 50.0,
	}
	renderer.ensure_beam(light)
	renderer.apply_beam_optics(light, params)
	renderer.update_beam(light, params)
	renderer.update_beam_intensity(light, params)
	var field: MeshInstance3D = light.get_meta(LegacyConeBeamRendererScript.MAIN_KEY) as MeshInstance3D
	var core: MeshInstance3D = light.get_meta(LegacyConeBeamRendererScript.CORE_LAYER_KEY) as MeshInstance3D
	var child_count := light.get_child_count()
	var field_id := field.get_instance_id()
	var core_id := core.get_instance_id()
	var field_mesh: Mesh = field.mesh
	var core_mesh: Mesh = core.mesh
	var field_material: Material = field.material_override
	var core_material: Material = core.material_override
	for index in range(4):
		params["beam_angle"] = 25.0 + float(index)
		renderer.ensure_beam(light)
		renderer.apply_beam_optics(light, params)
		renderer.update_beam(light, params)
		renderer.update_beam_intensity(light, params)
		field = light.get_meta(LegacyConeBeamRendererScript.MAIN_KEY) as MeshInstance3D
		core = light.get_meta(LegacyConeBeamRendererScript.CORE_LAYER_KEY) as MeshInstance3D
		_check(field != null and core != null, "Field and core layers must stay registered")
		_check(field.get_instance_id() == field_id, "Field layer must keep the same instance ID")
		_check(core.get_instance_id() == core_id, "Core layer must keep the same instance ID")
		_check(field.mesh != null and core.mesh != null, "Field and core layers must keep meshes")
		_check(field.material_override != null and core.material_override != null, "Field and core layers must keep materials")
		_check(light.get_child_count() == child_count, "Repeated updates must not grow SpotLight3D children")
		_check(field.material_override == field_material and core.material_override == core_material, "Dimmer and zoom updates must not recreate materials")
		_check(field.mesh == field_mesh and core.mesh == core_mesh, "Zoom updates for the same aperture must reuse topology")
		_check(not core.is_queued_for_deletion(), "Core layer must not be queue_free() during a normal update")
		_check(core.extra_cull_margin >= 75.0, "Core layer must receive enough cull margin for shader-deformed geometry")
	light.queue_free()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _check_close(actual: float, expected: float, tolerance: float, message: String) -> void:
	_check(abs(actual - expected) <= tolerance, "%s (actual %.6f expected %.6f)" % [message, actual, expected])
