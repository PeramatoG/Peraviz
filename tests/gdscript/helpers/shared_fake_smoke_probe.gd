extends RefCounted

const Smoke = preload("res://scripts/runtime/shared_fake_smoke.gd")

# Reuses the established six-shaft/opaque receiver probe. No FPS acceptance gates.
static func run(probe: RefCounted, tree: SceneTree, test: RefCounted, viewport: SubViewport, loader: Node, service: RefCounted, directory: String) -> void:
	var smoke := Smoke.new()
	var shafts: Array[MeshInstance3D] = []
	var shaders: Array[Shader] = []
	var baseline_shaders: Dictionary = {}
	for anchor in loader.anchors:
		var beam: MeshInstance3D = loader.renderer.get_beam_resource(anchor)
		shafts.append(beam)
		var shader: Shader = beam.material_override.shader
		shaders.append(shader)
		if not baseline_shaders.has(shader):
			var baseline := Shader.new()
			var start: int = shader.code.find("\tif (peraviz_fake_smoke_enabled)")
			var end: int = shader.code.find("\n\t}",start)+3
			baseline.code = shader.code.substr(0,start)+shader.code.substr(end)
			baseline_shaders[shader] = baseline
	var images: Array[Image] = []
	var reports: Array = []
	for mode in ["existing_vector_prism","fake_smoke_modest","disabled_after_use","uniform_field_diagnostic"]:
		for index in range(shafts.size()): shafts[index].material_override.shader = baseline_shaders[shaders[index]] if mode == "existing_vector_prism" else shaders[index]
		smoke.apply({"fake_smoke_enabled":mode in ["fake_smoke_modest","uniform_field_diagnostic"],"fake_smoke_variation":0.0 if mode == "uniform_field_diagnostic" else 0.35})
		var stats: Dictionary = await probe._capture(tree,viewport,directory.path_join(mode+".png"))
		stats["case"] = mode
		stats["footprints"] = service._dense_adapter._footprints.volumes.size()
		reports.append(stats)
		images.append(viewport.get_texture().get_image())
	var disabled: Dictionary = probe._difference(images[0],images[2])
	var enabled: Dictionary = probe._difference(images[0],images[1])
	test.check(disabled.max_pixel_error == 0,"Disabled smoke reproduces the original shader's actual pixels")
	test.check(enabled.changed_pixels > 100,"Modest shared smoke visibly changes the lit shafts")
	test.check(reports[0].draw_calls == reports[1].draw_calls and reports[0].primitives == reports[1].primitives and reports[1].draw_calls == reports[2].draw_calls,"Smoke adds no draws or geometry and keeps full fixture coverage")
	for index in range(shafts.size()): shafts[index].material_override.shader = shaders[index]
	# Frozen, uniform-density modulation must equal the existing appearance too.
	smoke.apply({"fake_smoke_enabled":true,"fake_smoke_variation":0.0,"fake_smoke_density":1.0})
	await probe._capture(tree,viewport,directory.path_join("zero_variation.png"))
	test.check(probe._difference(images[0],viewport.get_texture().get_image()).max_pixel_error == 0,"Unit uniform atmosphere preserves masking, profiles, Color and attenuation")
	# Moving the whole fixture/receiver/camera setup preserves beam-local coordinates,
	# but a world-anchored frozen field must change. Returning restores the field.
	smoke.apply({"fake_smoke_enabled":true,"fake_smoke_animation_speed":0.0,"fake_smoke_wind_speed":0.0})
	await probe._capture(tree,viewport,directory.path_join("world_field_original.png"))
	var frozen: Image = viewport.get_texture().get_image()
	var stage: Node3D = viewport.get_node("FootprintStage")
	stage.position.x += 3.0
	var moved_bounds: AABB = loader._loaded_bounds
	moved_bounds.position.x += 3.0
	for volume in service._dense_adapter._footprints.volumes: volume.set_receiver_bounds(moved_bounds,true); volume.sync()
	await probe._capture(tree,viewport,directory.path_join("world_field_translated.png"))
	test.check(probe._difference(frozen,viewport.get_texture().get_image()).changed_pixels > 100,"Field is anchored in world space rather than fixture coordinates")
	stage.position.x -= 3.0
	for volume in service._dense_adapter._footprints.volumes: volume.set_receiver_bounds(loader._loaded_bounds,true); volume.sync()
	await probe._capture(tree,viewport,directory.path_join("world_field_return.png"))
	test.check(probe._difference(frozen,viewport.get_texture().get_image()).max_pixel_error == 0,"Frozen shared field returns exactly across all fixtures")
	smoke.apply({"fake_smoke_enabled":true})
	for anchor in loader.anchors:
		anchor.get_parent().rotate_y(0.15)
		loader._fixture_gobo_projector.set_presentation_rotation(anchor,67.0)
	for volume in service._dense_adapter._footprints.volumes: volume.sync()
	await probe._capture(tree,viewport,directory.path_join("moving_pan_tilt_gobo.png"))
	# Footprints alone remain byte-equivalent with smoke on/off.
	for shaft in shafts: shaft.visible = false
	smoke.apply({"fake_smoke_enabled":false})
	await probe._capture(tree,viewport,directory.path_join("surfaces_off.png"))
	var surfaces: Image = viewport.get_texture().get_image()
	smoke.apply({"fake_smoke_enabled":true})
	await probe._capture(tree,viewport,directory.path_join("surfaces_on.png"))
	test.check(probe._difference(surfaces,viewport.get_texture().get_image()).max_pixel_error == 0,"Shared smoke never changes the actual Custom Footprint pixels")
	var report := {"adapter":RenderingServer.get_video_adapter_name(),"resolution":viewport.size,"cases":reports,"disabled_difference":disabled,"enabled_difference":enabled,"note":"Real Forward+ frames. Software-device times are not physical GPU/FPS claims; compare on owner hardware."}
	FileAccess.open(directory.path_join("fake_smoke.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("SHARED_FAKE_SMOKE_GRAPHICS ",JSON.stringify(report))
	smoke.apply({"fake_smoke_enabled":false})
	smoke.release()
	service.reset_scene_state()
	viewport.free()
	await tree.process_frame
