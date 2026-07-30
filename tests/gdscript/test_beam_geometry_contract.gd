extends SceneTree

const BeamGeometryCalculatorScript = preload("res://scripts/beam_geometry_calculator.gd")
const BeamApertureMeasurementServiceScript = preload("res://scripts/beam_aperture_measurement_service.gd")
const LegacyConeBeamRendererScript = preload("res://scripts/beam_renderers/legacy_cone_beam_renderer.gd")
const VolumetricConeShapeProviderScript = preload("res://scripts/beam_renderers/volumetric_cone_shape_provider.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_units_and_selection()
	var aperture_root: Node3D = _create_aperture_fixture()
	var light := SpotLight3D.new()
	get_root().add_child(aperture_root)
	get_root().add_child(light)
	await process_frame
	_test_aperture_measurement_axis(aperture_root)
	_test_renderer_geometry(light)
	aperture_root.free()
	light.free()
	await process_frame
	await process_frame
	test.finish(self)

func _test_units_and_selection() -> void:
	var selected: Dictionary = BeamGeometryCalculatorScript.select_render_near_radius({"official_beam_radius_m": 0.05, "beam_radius_from_gdtf": true}, 0.05)
	test.check_close(float(selected.get("render_near_radius_m", 0.0)), 0.05, 0.00001, "BeamRadius 0.05 m must remain a 0.05 m radius")
	test.check_close(float(selected.get("render_near_diameter_m", 0.0)), 0.10, 0.00001, "Near diameter must be twice selected radius")
	var malformed: Dictionary = BeamGeometryCalculatorScript.select_render_near_radius({"official_beam_radius_m": 50.0, "beam_radius_from_gdtf": true}, 0.05)
	test.check_close(float(malformed.get("official_beam_radius_m", 0.0)), 50.0, 0.00001, "Malformed official radius must be preserved without unit conversion")
	test.check_close(float(malformed.get("render_near_radius_m", 0.0)), 0.05, 0.00001, "Gross contradiction should render measured aperture")
	test.check(bool(malformed.get("likely_1000x_mismatch", false)), "Likely 1000x mismatch should be diagnosed")
	var geometry_10: Dictionary = BeamGeometryCalculatorScript.far_radius_for_full_angle(0.02, 20.0, 10.0)
	test.check_close(float(geometry_10.get("far_radius_m", 0.0)), 1.7832698, 0.0001, "20 degree full-angle far radius should include near radius")
	test.check_close(float(BeamGeometryCalculatorScript.far_radius_for_full_angle(0.05, 25.0, 75.0).get("far_radius_m", 0.0)), 16.6770997, 0.0001, "25 degree 75 m beam should not be clipped at 10 m")
	test.check_close(float(BeamGeometryCalculatorScript.far_radius_for_full_angle(0.05, 25.0, 100.0).get("far_radius_m", 0.0)), 22.2194663, 0.0001, "25 degree 100 m beam should not change near aperture")

func _create_aperture_fixture() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.name = "FixtureBody"
	body.mesh = BoxMesh.new()
	(body.mesh as BoxMesh).size = Vector3(5.0, 5.0, 5.0)
	root.add_child(body)
	var lens := MeshInstance3D.new()
	lens.name = "LensAperture"
	var lens_mesh := CylinderMesh.new()
	lens_mesh.top_radius = 0.05
	lens_mesh.bottom_radius = 0.05
	lens_mesh.height = 2.0
	lens_mesh.radial_segments = 48
	lens.mesh = lens_mesh
	root.add_child(lens)
	return root

func _test_aperture_measurement_axis(root: Node3D) -> void:
	var before: Transform3D = root.transform
	var measurement: Dictionary = BeamApertureMeasurementServiceScript.new().measure_circular_aperture(root, true)
	var after: Transform3D = root.transform
	test.check_close(float(measurement.get("measured_model_aperture_radius_m", 0.0)), 0.05, 0.01, "Aperture measurement must use XZ radius and ignore axial Y depth")
	test.check(before.is_equal_approx(after), "Aperture measurement must not mutate fixture/model transforms")

func _test_renderer_geometry(light: SpotLight3D) -> void:
	var params := {"beam_type": "Spot", "beam_angle": 25.0, "beam_visual_length_m": 75.0, "beam_range": 75.0, "lens_radius": 0.05, "render_near_radius_m": 0.05, "scaled_intensity": 10.0, "beam_color": Color.WHITE, "intensity_max": 50.0}
	var renderer = LegacyConeBeamRendererScript.new()
	renderer.update_beam(light, params)
	var state: Dictionary = renderer.get_beam_optics_state(light)
	test.check_close(float(state.get("near_radius", 0.0)), 0.05, 0.0001, "Lightweight near radius should match selected aperture")
	test.check_close(float(state.get("far_radius", 0.0)), 16.6770997, 0.0001, "Lightweight far radius should use full-angle equation")
	test.check_close(float(state.get("beam_range", 0.0)), 75.0, 0.0001, "Lightweight beam length should be explicit")
	var beam := MeshInstance3D.new()
	var shape: Dictionary = VolumetricConeShapeProviderScript.new().apply_shape(beam, light, params)
	test.check_close(float(shape.get("gobo_projection_radius", 0.0)), 16.6770997, 0.0001, "Volumetric far radius should match Lightweight and include near radius")
	beam.free()
