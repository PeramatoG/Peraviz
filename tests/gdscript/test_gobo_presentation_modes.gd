extends SceneTree

const FixtureGoboProjectorScript = preload("res://scripts/fixture_gobo_projector.gd")
const VolumetricBeamRendererScript = preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd")
const FixtureLightApplyServiceScript = preload("res://scripts/runtime/fixture_light_apply_service.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

class VisualLoader:
	extends Node
	var _visual_settings: Dictionary = {"enable_realtime_spotlights": false, "beam_presentation": 1}

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

	var loader := VisualLoader.new()
	get_root().add_child(loader)
	var apply_service = FixtureLightApplyServiceScript.new()
	apply_service._update_desired_light_state(light, 0.0, 10.0, Color.WHITE, false)
	apply_service._apply_canonical_light_visibility(loader, light, true, false)
	test.check(not bool(apply_service._light_desired_for(light).get("applied_realtime_visible", true)), "Parent visibility must not make an inactive physical output realtime")
	apply_service._update_desired_light_state(light, 10.0, 10.0, Color.WHITE, true)
	projector._set_light_projector_texture(light, texture)
	apply_service._apply_canonical_light_visibility(loader, light, true, false)
	test.check(bool(apply_service._light_desired_for(light).get("applied_realtime_visible", false)), "An active surface projector must keep its realtime SpotLight RID visible")
	loader._visual_settings["beam_presentation"] = 0
	apply_service._apply_canonical_light_visibility(loader, light, true, false)
	test.check(bool(apply_service._light_desired_for(light).get("applied_realtime_visible", false)), "Fog Volume with a surface projector must keep the realtime SpotLight RID visible")
	projector._set_light_projector_texture(light, null)
	loader._visual_settings["beam_presentation"] = 2
	apply_service._update_desired_light_state(light, 10.0, 10.0, Color.WHITE, true)
	apply_service._apply_canonical_light_visibility(loader, light, true, false)
	test.check(bool(apply_service._light_desired_for(light).get("applied_realtime_visible", false)), "Native Shadow mode must keep the realtime SpotLight RID visible without a gobo")
	var presentation_counters: Dictionary = apply_service.get_visual_apply_counters()
	test.check(int(presentation_counters.get("beam_presentation", -1)) == 2 and int(presentation_counters.get("spotlight_visible_count", 0)) == 1, "Presentation diagnostics must report the final forced realtime spotlight state")

	var renderer = VolumetricBeamRendererScript.new()
	var params := {"beam_type": "Spot", "beam_range": 8.0, "beam_angle": 20.0, "scaled_intensity": 10.0, "intensity_max": 50.0, "beam_color": Color.WHITE}
	renderer.configure(null, {"beam_presentation": 0})
	var inactive_params: Dictionary = params.duplicate()
	inactive_params["scaled_intensity"] = 0.0
	renderer.update_beam(light, inactive_params)
	test.check(light.get_node_or_null("PeravizFogVolumeGoboBeam") == null, "Inactive Fog mode must not allocate a FogVolume")
	for rejected_type in ["None", "Glow"]:
		inactive_params["beam_type"] = rejected_type
		inactive_params["scaled_intensity"] = 10.0
		renderer.update_beam(light, inactive_params)
		test.check(light.get_node_or_null("PeravizFogVolumeGoboBeam") == null, "Non-projected beam types must not allocate FogVolumes")
	light.set_meta("peraviz_gobo_texture", texture)
	for mode in [1, 0, 2, 1, 0, 1]:
		renderer.cleanup_beam(light)
		renderer.configure(null, {"beam_presentation": mode})
		projector.set_shadow_mask_enabled(light, mode == 2)
		renderer.update_beam(light, params.duplicate())
		var fog_count: int = 1 if light.get_node_or_null("PeravizFogVolumeGoboBeam") is FogVolume else 0
		if mode == 0:
			test.check(fog_count == 1, "Fog Volume mode must own exactly one reusable FogVolume")
			var fog_volume: FogVolume = light.get_node("PeravizFogVolumeGoboBeam") as FogVolume
			test.check(fog_volume.shape == RenderingServer.FOG_VOLUME_SHAPE_BOX and fog_volume.position.z < 0.0 and fog_volume.rotation == Vector3.ZERO, "Fog Volume must use the analytic local-negative-Z box contract")
			var original_material: Material = fog_volume.material
			var unchanged_result: int = renderer.update_beam_intensity(light, params.duplicate())
			test.check(unchanged_result == BeamRendererBase.INTENSITY_UNCHANGED and renderer.get_last_parameter_write_count() == 0, "Unchanged Fog state must perform zero shader writes")
			var dynamic_params: Dictionary = params.duplicate()
			dynamic_params["scaled_intensity"] = 5.0
			dynamic_params["beam_color"] = Color.RED
			dynamic_params["gobo_rotation_deg"] = 45.0
			renderer.update_beam(light, dynamic_params)
			test.check(light.get_node("PeravizFogVolumeGoboBeam") == fog_volume and fog_volume.material == original_material and renderer.get_last_parameter_write_count() == 3, "Fog dynamic updates must retain resources and write only intensity, color, and rotation")
		else:
			test.check(fog_count == 0, "Non-Fog-Volume modes must not retain an orphan FogVolume")
		var mask_count: int = 1 if light.has_meta("peraviz_gobo_plane") else 0
		test.check(mask_count == (1 if mode == 2 else 0), "Only Native Shadow mode may retain one physical gobo mask")
		if mode == 1:
			var vector_beam: MeshInstance3D = renderer.get_beam_resource(light)
			test.check(vector_beam != null and vector_beam.mesh != null and vector_beam.visible, "Vector Prism mode must retain visible gobo-equipped beams")
	renderer.cleanup_beam(light)
	loader.queue_free()
	light.queue_free()
	await process_frame
	test.finish(self)
