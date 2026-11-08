extends RefCounted

# Equal final physical/optical/camera/receiver states, reached via active and dark paths.
static func run(probe: RefCounted, tree: SceneTree, test: RefCounted, viewport: SubViewport, loader: Node, service: RefCounted, directory: String) -> void:
	var adapter: RefCounted = service._dense_adapter
	var original: Array[Transform3D] = []
	var final: Array[Transform3D] = []
	for anchor in loader.anchors:
		var mechanical: Node3D = anchor.get_parent()
		original.append(mechanical.transform)
		final.append(mechanical.transform * Transform3D(Basis.from_euler(Vector3(0.02,0.04,0.01)),Vector3(0.1,0.05,0.08)))
	for output in adapter._outputs:
		for handle in output.lights:
			if is_instance_valid(handle.beam): handle.beam.visible = false
	var frame: Dictionary = loader.frame(1.0, 1.0)
	service.compose_dense_snapshot(frame.descriptors, frame.integers, frame.floats)
	service.end_visual_snapshot()
	var results: Array = []
	for mode in ["dimmer", "held_gain", "receiver_camera"]:
		for index in range(loader.anchors.size()): loader.anchors[index].get_parent().transform = final[index]
		var camera: Camera3D = viewport.get_camera_3d()
		if mode == "receiver_camera":
			camera.position += Vector3(0.3,0.1,0)
			viewport.get_node("FootprintStage").get_child(2).position += Vector3(0,0.02,0)
		var reference_stats: Dictionary = await probe._capture(tree, viewport, directory.path_join(mode + "-reference.png"))
		var reference: Image = viewport.get_texture().get_image()
		var before: Dictionary = adapter.diagnostics()
		var camera_final: Transform3D = camera.transform
		var receiver: MeshInstance3D = viewport.get_node("FootprintStage").get_child(2)
		var receiver_final: Transform3D = receiver.transform
		if mode == "held_gain":
			adapter._native.replay_presentation_gains(false,true,0.0,false)
		else:
			var dark: Dictionary = loader.frame(0.0,1.0)
			service.compose_dense_snapshot(dark.descriptors,dark.integers,dark.floats)
			service.end_visual_snapshot()
		if mode == "receiver_camera":
			camera.position += Vector3(0.5,0.1,0)
			receiver.position += Vector3(0,0.1,0)
			receiver.force_update_transform()
		for index in range(loader.anchors.size()): loader.anchors[index].get_parent().transform = original[index]
		await tree.process_frame
		await RenderingServer.frame_post_draw
		for index in range(loader.anchors.size()): loader.anchors[index].get_parent().transform = final[index]
		if mode == "receiver_camera":
			camera.transform = camera_final
			receiver.transform = receiver_final
			receiver.force_update_transform()
		# Deliberately do not deliver projector notifications before admission.
		if mode == "held_gain":
			adapter._native.replay_presentation_gains(false,true,0.6,false)
		else:
			service.compose_dense_snapshot(frame.descriptors,frame.integers,frame.floats)
			service.end_visual_snapshot()
		for volume in adapter._footprints.volumes:
			var inverse: Transform3D = volume.material_override.get_shader_parameter("world_to_projector")
			test.check((inverse * volume.get_parent().global_transform).is_equal_approx(Transform3D.IDENTITY), "Projection is current synchronously before first reactivated draw")
		var actual_stats: Dictionary = await probe._capture(tree, viewport, directory.path_join(mode + "-restored.png"), Callable(), 0, 1)
		var error: Dictionary = probe._difference(reference, viewport.get_texture().get_image())
		test.check(error.max_pixel_error == 0.0, "Reactivation is pixel identical: " + mode)
		test.check(actual_stats.draw_calls == reference_stats.draw_calls, "Reactivation preserves exact draw/resource counts")
		var after: Dictionary = adapter.diagnostics()
		test.check(before.custom_volumes_created == after.custom_volumes_created and before.custom_binding_installs == after.custom_binding_installs, "Restoration retains installed resources")
		results.append({"case":mode,"difference":error,"reference":reference_stats,"restored":actual_stats})
	var file := FileAccess.open(directory.path_join("inactive-visual.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"adapter":RenderingServer.get_video_adapter_name(),"cases":results},"\t"))
	service.reset_scene_state()
	viewport.free()
