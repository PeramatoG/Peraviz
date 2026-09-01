extends SceneTree

const FixtureGoboProjectorScript = preload("res://scripts/fixture_gobo_projector.gd")
const VolumetricBeamRendererScript = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var light := SpotLight3D.new()
	get_root().add_child(light)
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var projector = FixtureGoboProjectorScript.new()
	projector._set_light_projector_texture(light, texture)
	test.check(light.light_projector == texture and light.shadow_enabled, "An active surface projector must enable its Godot 4.7 shadow dependency")
	light.set_meta("peraviz_gobo_texture", texture)
	projector.set_shadow_mask_enabled(light, true)
	var mask: MeshInstance3D = light.get_meta("peraviz_gobo_plane", null) as MeshInstance3D
	test.check(mask != null and mask.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "Native shadow mode must create a shadows-only physical mask")
	projector.set_shadow_mask_enabled(light, false)
	projector._set_light_projector_texture(light, null)
	test.check(light.light_projector == null and not light.shadow_enabled, "Clearing a projector must restore the previous shadow state")
	projector.apply_gobo_projection(light, {"has_gobo": false, "gobo_runtime_bindings": []})
	test.check(light.light_projector == null and not light.has_meta("peraviz_gobo_texture"), "An open slot must leave normal unmasked spot lighting")

	var renderer = VolumetricBeamRendererScript.new()
	var params := {"beam_type": "Spot", "beam_range": 8.0, "beam_angle": 20.0, "scaled_intensity": 10.0, "intensity_max": 50.0, "beam_color": Color.WHITE}
	for mode in [0, 1, 2, 0]:
		renderer.cleanup_beam(light)
		renderer.configure(null, {"beam_presentation": mode})
		if mode == 1:
			light.set_meta("peraviz_gobo_texture", texture)
		renderer.update_beam(light, params.duplicate())
		var fog_count: int = 1 if light.get_node_or_null("PeravizFogVolumeGoboBeam") is FogVolume else 0
		if mode == 0:
			test.check(fog_count == 1, "Fog Volume mode must own exactly one reusable FogVolume")
		else:
			test.check(fog_count == 0, "Non-Fog-Volume modes must not retain an orphan FogVolume")
		if mode == 1:
			var vector_beam: MeshInstance3D = renderer.get_beam_resource(light)
			test.check(vector_beam != null and vector_beam.mesh != null and vector_beam.visible, "Vector Prism mode must retain visible gobo-equipped beams")
	renderer.cleanup_beam(light)
	light.queue_free()
	await process_frame
	test.finish(self)
