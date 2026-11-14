extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1366, 768)
	var preferences_path := UserPreferences.SETTINGS_FILE_PATH
	var existed := FileAccess.file_exists(preferences_path)
	var saved := FileAccess.get_file_as_bytes(preferences_path) if existed else PackedByteArray()
	# A legacy preference file must retain explicit choices and gain layout defaults.
	var config := ConfigFile.new()
	config.set_value("ui", "sidebar_open", false)
	config.set_value("ui", "show_fps", true)
	config.set_value("ui", "advanced_mode", true)
	config.set_value("session", "auto_load_last_file", false)
	config.save(preferences_path)
	var preferences := UserPreferences.new()
	preferences.load_from_disk()
	test.check(not preferences.sidebar_open and preferences.show_fps and preferences.advanced_mode and preferences.inspector_open, "Legacy sidebar, FPS and advanced choices migrate without loss")
	var app: Node3D = load("res://test.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var shell: AppShell = app.app_shell
	shell.reset_layout()
	await process_frame
	await process_frame
	test.check(shell._left.visible and shell._right.visible, "Default layout exposes both panels")
	test.check(absf(shell._left.size.x - 270) < 2 and absf(shell._right.size.x - 320) < 2, "Default divider positions restore requested panel widths")
	shell._outer.split_offset = 310
	shell._outer.dragged.emit(310)
	shell._inner.split_offset = -350
	shell._inner.dragged.emit(-350)
	shell.toggle_tools()
	shell.toggle_tools()
	await process_frame
	await process_frame
	test.check(absf(shell._left.size.x - 310) < 2 and absf(shell._right.size.x - 350) < 2, "Panel resizing persists widths and restores them after Hide Tools")
	shell.reset_layout()
	await process_frame
	await process_frame
	var original_area: float = shell._area.size.x
	shell.toggle_side_panel()
	await process_frame
	await process_frame
	test.check(not shell._left.visible and shell._area.size.x > original_area, "Hiding explorer expands viewport")
	shell.toggle_inspector()
	await process_frame
	await process_frame
	test.check(not shell._right.visible, "Inspector hides independently")
	shell.toggle_tools()
	test.check(not shell._toolbar.visible, "Distraction-free hides viewport tools")
	shell.toggle_tools()
	test.check(not shell._left.visible and not shell._right.visible and shell._toolbar.visible, "Restore respects individually hidden panels")
	shell.reset_layout()
	for resolution in [Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		for scale in [1.0, 1.25, 1.5]:
			root.size = resolution
			root.content_scale_factor = scale
			await process_frame
			await process_frame
			test.check(shell._area.size.x >= 280, "Viewport retains practical minimum across desktop sizes and UI scales")
			test.check(shell._row.get_global_rect().end.x <= root.get_visible_rect().end.x + 1, "Essential toolbar fits at all tested desktop sizes and UI scales")
	root.content_scale_factor = 1.0
	root.size = Vector2i(1366, 768)
	await process_frame
	await process_frame
	test.check(app._dmx_controller.start_dmx(), "Art-Net starts from the existing production controller")
	var receiver_button: Button = shell._row.get_node("ArtNetToggle")
	test.check(receiver_button.button_pressed, "Toolbar reflects running receiver")
	app._on_dmx_status_changed(true, false)
	test.check(app._status_presenter._badge_labels["DMX"].text.contains("Listening"), "Running without packets is labeled Listening")
	app._on_dmx_status_changed(true, true)
	test.check(app._status_presenter._badge_labels["DMX"].text.contains("Receiving"), "Packet reception is explicit")
	app._dmx_controller.stop_dmx()
	test.check(not receiver_button.button_pressed and app._status_presenter._badge_labels["DMX"].text.contains("OFF"), "Stopped Art-Net never appears connected")
	var group := Node3D.new()
	group.set_meta("peraviz_type", "group")
	group.set_meta("peraviz_object_id", "group-uuid")
	group.set_meta("peraviz_name", "Front truss")
	app.proxies_root.add_child(group)
	var fixture := Node3D.new()
	fixture.set_meta("peraviz_type", "fixture")
	fixture.set_meta("peraviz_object_id", "fixture-uuid")
	fixture.set_meta("peraviz_fixture_uuid", "fixture-uuid")
	fixture.set_meta("peraviz_name", "Missing GDTF fixture")
	group.add_child(fixture)
	var fixture_mesh := MeshInstance3D.new()
	fixture_mesh.mesh = BoxMesh.new()
	fixture.add_child(fixture_mesh)
	app._attach_fixture_pick_colliders("fixture-uuid", fixture)
	app._node_index["group-uuid"] = group
	app._node_index["fixture-uuid"] = fixture
	app._scene_registry.register_fixture("fixture-uuid", fixture)
	shell.publish_scene()
	test.check(shell.explorer._items["fixture-uuid"].get_parent() == shell.explorer._items["group-uuid"], "Explorer preserves imported hierarchy")
	shell.selection.select(PackedStringArray(["fixture-uuid"]))
	test.check(shell.explorer._items["fixture-uuid"].is_selected(0), "Application selection synchronizes explorer")
	test.check(shell.inspector._details.text.contains("DMX Mode") and shell.inspector._details.text.contains("Unavailable in this preview"), "Inspector supports missing/unbound fixtures and never invents inversion")
	test.check(not shell.inspector._details.text.contains("UUID:") and not shell.explorer._items["fixture-uuid"].get_tooltip_text(0).contains("fixture-uuid"), "Normal identification hides internal UUIDs")
	shell.inspector.show_object_uuids = true
	shell.inspector.refresh([])
	shell.explorer.set_technical_identity(true)
	test.check(shell.inspector._details.text.contains("UUID: fixture-uuid") and shell.explorer._items["fixture-uuid"].get_tooltip_text(0).contains("UUID: fixture-uuid"), "Technical identity remains explicitly accessible")
	shell.inspector.show_object_uuids = false
	shell.inspector.refresh([])
	shell.explorer.set_technical_identity(false)
	test.check(not app.manual_fixture_toggle.button_pressed, "Selection works without manual fixture mode")
	shell.explorer.tree.deselect_all()
	shell.explorer._items["group-uuid"].select(0)
	shell.explorer._picked(shell.explorer._items["group-uuid"], 0, true)
	test.check(shell.selection.ids == PackedStringArray(["group-uuid"]) and not shell.inspector._details.text.contains("DMX Mode"), "Explorer selects different object types with applicable inspector properties")
	shell.selection.select(PackedStringArray(["fixture-uuid", "group-uuid"]))
	test.check(shell.inspector._details.text.contains("2 objects selected"), "Multiple selection has a read-only inspector state")
	shell.selection.clear()
	test.check(shell.inspector._details.text.contains("Select an object"), "Empty selection is safe")
	# The root viewport and rays must agree after asymmetric panel changes.
	await process_frame
	app.camera._update_camera_transform()
	var target_pixel: Vector2 = app.camera.unproject_position(app.camera.target_position)
	test.check(target_pixel.distance_to(app.camera.scene_view_rect.get_center()) < 1.0, "Camera target projects to unobscured viewport center")
	await physics_frame
	await physics_frame
	var clicked_pixel: Vector2 = app.camera.unproject_position(fixture.global_position)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = clicked_pixel
		click.global_position = clicked_pixel
		root.push_input(click, true)
	test.check(shell.selection.ids == PackedStringArray(["fixture-uuid"]), "Viewport mouse click selects fixture through normal unhandled input")
	test.check(not app.camera._is_dragging() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Selection clicks never capture mouse for orbit")
	shell.pick(Vector2(shell._area.global_position.x + 8.0, shell._area.global_position.y + shell._area.size.y - 8.0))
	test.check(shell.selection.ids.is_empty(), "Clicking empty viewport clears selection")
	var orbit_press := InputEventMouseButton.new()
	orbit_press.button_index = MOUSE_BUTTON_RIGHT
	orbit_press.pressed = true
	app.camera._handle_mouse_button(orbit_press)
	var orbit_release := InputEventMouseButton.new()
	orbit_release.button_index = MOUSE_BUTTON_RIGHT
	orbit_release.position = Vector2(20, 120)
	root.push_input(orbit_release, true)
	test.check(not app.camera._is_dragging() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Navigation releases safely over dock controls")
	var camera_distance: float = app.camera.target_distance
	var key := InputEventKey.new()
	key.keycode = KEY_F
	key.pressed = true
	shell.explorer.search.grab_focus()
	shell._unhandled_input(key)
	test.check(app.camera.target_distance == camera_distance, "Text input shields camera shortcuts")
	shell.explorer.search.release_focus()
	var old_size := root.size
	var old_position := root.position
	var old_mode := root.mode
	shell.toggle_fullscreen()
	test.check(shell._modes.active, "Fullscreen enters without replacing scene")
	shell.toggle_fullscreen()
	test.check(not shell._modes.active and root.size == old_size and root.position == old_position and root.mode == old_mode, "Fullscreen restores window geometry and mode")
	for window in shell._windows:
		window.popup_centered()
		test.check(window.visible, "Production and diagnostic windows remain accessible")
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		window.window_input.emit(escape)
		test.check(not window.visible, "Escape dismisses child tools before the application window")
	app._clear_scene()
	test.check(shell.selection.ids.is_empty() and shell.explorer._items.is_empty(), "Scene retirement invalidates stale selection and explorer")
	app.queue_free()
	await process_frame
	if existed:
		var file := FileAccess.open(preferences_path, FileAccess.WRITE)
		file.store_buffer(saved)
	else: DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences_path))
	test.finish(self)
