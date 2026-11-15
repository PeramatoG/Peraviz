extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
const Highlight = preload("res://scripts/ui/selection_highlight.gd")
const Camera = preload("res://scripts/editor_camera.gd")
const Cube = preload("res://scripts/ui/navigation_cube.gd")
var test = TestCase.new()

func _initialize() -> void:
	call_deferred("_run")

func _settle(camera: Camera3D) -> void:
	camera.current_yaw = camera.target_yaw
	camera.current_pitch = camera.target_pitch
	camera.current_distance = camera.target_distance
	camera.current_roll = camera.target_roll
	camera._update_camera_transform()

func _run() -> void:
	root.size = Vector2i(1366, 768)
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera.new()
	scene.add_child(camera)
	camera.scene_view_rect = Rect2(270, 70, 760, 660)
	var cube := Cube.new()
	root.add_child(cube)
	cube.configure(camera)
	camera.set_view_direction(Vector3.ONE)
	_settle(camera)
	cube._project()
	test.check(cube._viewport.own_world_3d and cube._viewport.world_3d != camera.get_world_3d(), "The real 3D cube has an isolated tiny world, never a second render of the MVR")
	test.check(cube._model.patches.size() == 26, "All 26 selectable regions are actual beveled mesh surfaces")
	for patch in cube._model.patches:
		if not patch.face or camera.global_basis.z.dot(patch.direction) < 0.2: continue
		test.check(cube.hit_direction(cube.patch_screen_center(patch.direction)).is_equal_approx(patch.direction), "Ray picking hits the visible rendered face")
	test.check(cube.hit_direction(cube.patch_screen_center(Vector3.ONE)).is_equal_approx(Vector3.ONE.normalized()), "The rendered corner selects an isometric direction")
	test.check(cube.hit_direction(cube.patch_screen_center(Vector3(0,1,1))).is_equal_approx(Vector3(0,1,1).normalized()), "The rendered beveled edge selects a two-axis view")
	for direction in [Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT]:
		camera.set_view_direction(direction)
		_settle(camera)
		test.check(camera.global_basis.z.is_equal_approx(direction), "All six face views, including exact poles, have a valid camera basis")
		cube._project()
		test.check(cube.hit_direction(cube.patch_screen_center(direction)).is_equal_approx(direction), "Axis-aligned cube keeps the visible face clickable")
	camera.set_view_direction(Vector3.ONE)
	_settle(camera)
	var center: Vector2 = camera.unproject_position(camera.target_position)
	camera.set_projection_mode(true)
	_settle(camera)
	test.check(camera.unproject_position(camera.target_position).distance_to(center) < 0.01, "Orthographic projection preserves unobscured viewport center")
	var old_size: float = camera.size
	camera._apply_zoom(-1)
	test.check(camera.size < old_size, "Wheel zoom changes orthographic extent")
	camera.set_projection_mode(false)
	test.check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Perspective projection can be restored")
	var before_yaw: float = camera.target_yaw
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = cube.patch_screen_center(Vector3.ONE)
	cube._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(18, 3)
	cube._gui_input(motion)
	test.check(camera.target_yaw != before_yaw and not camera._is_dragging(), "Cube drag orbits without capturing the viewport mouse")
	press.pressed = false
	press.position = Vector2(900, 500)
	cube._input(press)
	test.check(not cube._pressed, "Cube drag safely releases outside its control")
	camera._middle_down = true
	camera._update_drag_mode(true)
	test.check(camera._drag_mode == camera.DragMode.ORBIT, "Shift+middle drag provides CAD-style orbit")
	camera._update_drag_mode(false)
	test.check(camera._drag_mode == camera.DragMode.PAN, "Middle drag retains pan")
	camera._middle_down = false
	camera.set_view_direction(Vector3.BACK)
	_settle(camera)
	camera.roll_view(PI*0.5)
	_settle(camera)
	cube._project()
	test.check(camera.global_basis.z.is_equal_approx(Vector3.BACK) and absf(camera.global_basis.y.x) > 0.999, "A 90-degree roll keeps the face direction and rotates the view")
	test.check(cube._model.view_camera.global_basis.is_equal_approx(camera.global_basis), "The actual 3D cube follows camera roll as well as orbit")
	cube._menu_action(1)
	var saved_yaw: float = camera.current_yaw
	camera.target_yaw += 1.0
	cube._home()
	test.check(is_equal_approx(camera.target_yaw,saved_yaw), "Set current view as Home restores a real saved view")
	cube.reset_home()
	test.check(cube._home_snapshot.is_empty(), "Replacing the scene can invalidate its session-specific Home")
	cube._menu_action(12)
	cube._activate(Vector3.UP)
	test.check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Hybrid projection uses true orthographic face views")
	cube._activate(Vector3.ONE.normalized())
	test.check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Hybrid projection returns to perspective for corner views")
	cube._menu_action(10)
	cube._activate(Vector3.ONE.normalized())
	test.check(camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "Parallel mode remains orthographic for angled views")
	cube._menu_action(11)
	cube._activate(Vector3.UP)
	test.check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Perspective mode remains perspective for face views")
	camera.set_view_direction(Vector3.ONE)
	_settle(camera)
	cube._project()
	var compass_pixel: Vector2 = cube.PREVIEW_RECT.position + cube._model.view_camera.unproject_position(Vector3(1.8,-1.3,0)) * cube.PREVIEW_RECT.size / Vector2(cube._viewport.size)
	var compass_press := InputEventMouseButton.new()
	compass_press.button_index = MOUSE_BUTTON_LEFT
	compass_press.pressed = true
	compass_press.position = compass_pixel
	cube._gui_input(compass_press)
	compass_press.pressed = false
	cube._gui_input(compass_press)
	test.check(is_equal_approx(camera.target_yaw,PI*0.5), "Clicking the actual 3D compass east marker rotates the scene to east")
	camera.set_view_direction(Vector3.UP)
	_settle(camera)
	cube._turn_compass(Vector3.RIGHT)
	_settle(camera)
	test.check(camera.global_basis.y.is_equal_approx(Vector3.RIGHT), "Top-view compass turns the actual scene using roll rather than ineffective pole yaw")
	camera.set_view_direction(Vector3.BACK)
	_settle(camera)
	cube._adjacent(1)
	test.check(is_equal_approx(camera.target_yaw,PI*0.5), "Adjacent-face controls move to the neighboring face")
	var state := SceneSelection.new()
	var group := Node3D.new()
	scene.add_child(group)
	var fixture := Node3D.new()
	group.add_child(fixture)
	var source := MeshInstance3D.new()
	source.mesh = BoxMesh.new()
	var original := StandardMaterial3D.new()
	original.emission_enabled = true
	original.emission = Color.BLUE
	source.material_override = original
	fixture.add_child(source)
	var light := SpotLight3D.new()
	fixture.add_child(light)
	var beam := MeshInstance3D.new()
	beam.mesh = CylinderMesh.new()
	light.add_child(beam)
	state.publish({"group":group,"fixture":fixture})
	var highlight := Highlight.new()
	scene.add_child(highlight)
	highlight.configure(state)
	state.select(PackedStringArray(["fixture", "group"]))
	test.check(highlight._overlays.size() == 1, "Overlapping selections highlight each model once and exclude beam subtrees")
	var overlay: MeshInstance3D = highlight._overlays[source.get_instance_id()]
	test.check(source.material_override == original and source.material_overlay == null and original.next_pass == null, "Native source material and lens admission properties remain untouched")
	test.check(overlay.mesh == source.mesh and overlay.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "Highlight shares geometry and cannot cast extra shadows")
	var before := overlay.global_transform
	fixture.rotation_degrees.y = 45
	await process_frame
	test.check(overlay.global_transform != before and overlay.global_transform.is_equal_approx(source.global_transform), "Highlight follows articulated fixture motion without transform polling")
	test.check(not preload("res://scripts/runtime/instanced_lens_batches.gd")._has_visual_children(source), "Selection adds no visual child that could disqualify native lens batching")
	source.hide()
	test.check(not overlay.visible, "Native source visibility controls the independent highlight")
	source.show()
	test.check(overlay.visible, "Highlight returns when source visibility is restored")
	var replacement := SphereMesh.new()
	source.mesh = replacement
	highlight.refresh_meshes()
	test.check(overlay.mesh == replacement, "LOD mesh replacement synchronizes the selection geometry")
	test.check(state.bounds().size.length() < 5, "Selection-only geometry never expands document bounds")
	state.retire()
	test.check(highlight._overlays.is_empty() and source.material_override == original and source.get_child_count() == 0, "Deselect/reload removes highlight instances and preserves original materials")
	state.select(PackedStringArray(["fixture"]))
	source.free()
	await process_frame
	test.check(highlight._overlays.is_empty(), "Source retirement cannot leave a detached highlight or stale render resource")
	cube.queue_free()
	scene.queue_free()
	await process_frame
	test.finish(self)
