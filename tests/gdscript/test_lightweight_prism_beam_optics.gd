extends SceneTree

const LegacyConeBeamRendererScript = preload("res://scripts/beam_renderers/legacy_cone_beam_renderer.gd")

var failures: Array[String] = []

func _init() -> void:
	var renderer = LegacyConeBeamRendererScript.new()
	var light := SpotLight3D.new()
	get_root().add_child(light)
	renderer.ensure_beam(light)
	var params: Dictionary = {
		"beam_type": "Spot",
		"beam_angle": 20.0,
		"beam_range": 10.0,
		"lens_radius": 0.02,
		"render_near_radius_m": 0.02,
		"beam_color": Color.WHITE,
		"scaled_intensity": 10.0,
		"beam_intensity": 10.0,
		"intensity_max": 50.0,
	}
	renderer.update_beam(light, params)
	var beam: MeshInstance3D = renderer.get_beam_resource(light)
	_check(beam != null, "Lightweight Prism resource should be attached")
	var first_mesh: Mesh = beam.mesh
	var first_material: Material = beam.material_override
	var first_state: Dictionary = renderer.get_beam_optics_state(light)
	_check(abs(float(first_state.get("near_radius", 0.0)) - 0.02) < 0.001, "Near radius should preserve selected render radius")
	_check(float(first_state.get("far_radius", 0.0)) > 0.02, "Spot beam should be a frustum instead of a cylinder")
	_check(float(first_state.get("near_axial", -1.0)) == 1.0, "Lens-side mesh end should keep beam_axial 1.0 for near falloff")
	_check(float(first_state.get("far_axial", -1.0)) == 0.0, "Distant mesh end should keep beam_axial 0.0")
	var near_world: Vector3 = first_state.get("near_world_position", Vector3.INF)
	var far_world: Vector3 = first_state.get("far_world_position", Vector3.INF)
	_check(near_world.distance_to(light.global_position) < 0.01, "Renderer rotation/translation should place the near end at the light/lens")
	_check(far_world.z < near_world.z, "Distant end should extend along negative local/global Z in the default test orientation")
	params["beam_angle"] = 40.0
	var result: Dictionary = renderer.apply_beam_optics(light, params)
	var zoom_state: Dictionary = renderer.get_beam_optics_state(light)
	_check(bool(result.get("parametric_update_performed", false)), "Zoom must mutate renderer optics state")
	_check(beam == renderer.get_beam_resource(light), "Zoom should keep the same MeshInstance3D")
	_check(first_material == beam.material_override, "Zoom should keep the same material")
	_check(first_mesh == beam.mesh, "Zoom should reuse topology for the same aperture")
	_check(float(zoom_state.get("far_radius", 0.0)) > float(first_state.get("far_radius", 0.0)), "Zoom angle should change far spread")
	_check(abs(float(zoom_state.get("near_radius", 0.0)) - 0.02) < 0.001, "Zoom should not change the selected near aperture")
	params["beam_type"] = "Rectangle"
	params["rectangle_ratio"] = 2.0
	renderer.apply_beam_optics(light, params)
	_check(str(renderer.get_beam_optics_state(light).get("shape", "")) == "rectangle", "Rectangle BeamType should install rectangular aperture topology")
	params["beam_type"] = "None"
	renderer.apply_beam_optics(light, params)
	_check(not beam.visible, "BeamType None should hide projected custom beam")
	light.queue_free()
	if failures.is_empty():
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
