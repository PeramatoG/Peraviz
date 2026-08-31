extends SceneTree

const LegacyConeBeamRendererScript = preload("res://scripts/beam_renderers/legacy_cone_beam_renderer.gd")
const VolumetricBeamRendererScript = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _check_renderer(LegacyConeBeamRendererScript.new(), "legacy")
	await _check_renderer(VolumetricBeamRendererScript.new(), "volumetric")
	test.finish(self)

func _check_renderer(renderer: RefCounted, label: String) -> void:
	var light := SpotLight3D.new()
	get_root().add_child(light)
	renderer.ensure_beam(light)
	test.check(not light.has_meta("peraviz_beam_debug_axis"), "%s ensure_beam must not allocate debug geometry" % label)
	var params: Dictionary = {
		"beam_type": "Wash",
		"beam_angle": 20.0,
		"beam_range": 10.0,
		"lens_radius": 0.02,
		"scaled_intensity": 10.0,
		"intensity_max": 50.0,
		"beam_color": Color.WHITE,
		"beam_debug_optics": true,
	}
	renderer.update_beam(light, params)
	var axis: MeshInstance3D = light.get_meta("peraviz_beam_debug_axis", null) as MeshInstance3D
	test.check(axis != null and axis.visible, "%s debug mode must lazily create and show its axis" % label)
	params["beam_debug_optics"] = false
	renderer.update_beam(light, params)
	test.check(axis != null and not axis.visible, "%s disabling debug mode must hide its axis" % label)
	renderer.cleanup_beam(light)
	test.check(not light.has_meta("peraviz_beam_debug_axis"), "%s cleanup must remove debug-axis metadata" % label)
	light.free()
	axis = null
	renderer = null
	await process_frame
