extends "res://tests/gdscript/test_mvr_document_editing.gd"

func run() -> void:
	existed = FileAccess.file_exists(prefs_path)
	saved = FileAccess.get_file_as_bytes(prefs_path) if existed else PackedByteArray()
	var config := ConfigFile.new()
	config.set_value("session", "auto_load_last_file", false)
	config.save(prefs_path)
	var base := ProjectSettings.globalize_path("user://mode-editing-%d" % OS.get_process_id())
	var source := base + ".mvr"
	var generator := ProjectSettings.globalize_path("res://tests/integration/generate_mode_editing_fixture.py")
	test.check(OS.execute("python3", PackedStringArray([generator, source])) == 0, "Generate a canonical multi-mode fixture")
	var original_hash := FileAccess.get_sha256(source)
	app = load("res://test.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	var loaded: Dictionary = await app._load_mvr_scene(source, "mvr", false)
	test.check(loaded.get("ok", false), "Multimode fixture imports")
	if not loaded.get("ok", false):
		await finish()
		return
	app.camera.set_process(false)
	var editor: RefCounted = app.app_shell.document
	app.app_shell.selection.select(PackedStringArray([ID_A]))
	var field: VBoxContainer = app._fixture_inspection_panel._mode_field
	var unavailable := "852e8e2d-e476-5f92-8ee4-a21f919f7deb"
	app.app_shell.selection.select(PackedStringArray([unavailable]))
	test.check(field._choice.disabled and field._hint.text.contains("unavailable"), "An invalid original mode is visible and read-only")
	test.check(not await editor.apply_mode(unavailable, "Alternative") and not editor.state().can_undo,
		"An invalid original mode cannot create unrecoverable Undo history")
	app.app_shell.selection.select(PackedStringArray([ID_A, ID_B]))
	test.check(not field.visible, "Multiple selections keep the mode field read-only")
	app.app_shell.selection.select(PackedStringArray([ID_A]))
	var fixture: Node3D = app._scene_registry.get_fixture(ID_A)
	var unrelated: Node3D = app._scene_registry.get_fixture(ID_B)
	var original_transform := fixture.transform
	var pan := axis(ID_A, true)
	var tilt := axis(ID_A, false)
	var other_pan := axis(ID_B, true)
	test.check(field._choice.item_count == 6 and field._choice.get_item_text(1) == "Pixels & Pan", "Inspector lists exact mode names in authored order")
	test.check(field._choice.is_item_disabled(4) and field._choice.is_item_disabled(5), "Duplicate names cannot be chosen")
	field._choice.select(1)
	field._choice.item_selected.emit(1)
	test.check(field._apply.visible and not editor.state().dirty, "Browsing changes neither runtime nor canonical document")
	field._cancel.pressed.emit()
	test.check(field._choice.selected == 0 and not editor.state().can_undo, "Cancel restores the authored selection")
	field._choice.select(1)
	field._choice.item_selected.emit(1)
	app.app_shell.selection.select(PackedStringArray([ID_B]))
	app.app_shell.selection.select(PackedStringArray([ID_A]))
	test.check(field._choice.selected == 0 and not field._apply.visible, "Selection changes discard a pending mode")
	field._choice.select(3)
	field._choice.item_selected.emit(3)
	test.check(field._apply.disabled and field._hint.text.contains("MVR break 1"), "Missing break is visible before Apply")
	test.check(await editor.apply_mode(ID_A, "Preview 3ch") and not editor.state().can_undo, "Same mode is a semantic no-op")
	test.check(not await editor.apply_mode(ID_A, "Duplicate") and not editor.state().dirty, "Duplicate rejection preserves history")
	var pan_key: String = pan.get_meta("peraviz_gdtf_geometry_key")
	pan.set_meta("peraviz_gdtf_geometry_key", "")
	test.check(not await editor.apply_mode(ID_A, "Pixels & Pan") and not editor.state().can_undo and not editor.state().dirty,
		"Renderer preflight rejection leaves history and canonical mode intact")
	pan.set_meta("peraviz_gdtf_geometry_key", pan_key)
	test.check(app._dmx_controller.start_dmx(), "Start the production Art-Net receiver")
	udp.connect_to_host("127.0.0.1", 6454)
	await send_dmx()
	var initial_meshes := physical_models()
	if OS.get_environment("PERAVIZ_NATIVE_EVALUATION") == "parallel":
		test.check(app._fixture_light_apply_service._dense_adapter._native.get_sizes().get("native_async_active", false),
			"Mode switch starts with a live asynchronous presentation worker")
	var previous_other := other_pan.rotation_degrees.y
	var original_pan := pan.rotation_degrees.y
	var stage: Dictionary = app._loader.stage_document_mode(editor.native, ID_A, "Alternative", -1)
	test.check(stage.get("ok", false), "Prepare an alternate root for late rollback")
	if stage.get("ok", false):
		editor.native.cancel()
		var failure: String = await preload("res://scripts/document/fixture_mode_transaction.gd").install(app, editor.native, stage)
		app._loader.cancel_document_mode()
		test.check(not failure.is_empty() and is_same(pan, axis(ID_A, true)) and not editor.state().dirty,
			"Late rejection restores the previous renderer, geometry and document")
		test.check(physical_models() == initial_meshes and absf(pan.rotation_degrees.y - original_pan) < 0.01,
			"Late rollback restores physical model identity and held playback")
	field._choice.select(1)
	field._choice.item_selected.emit(1)
	field._apply.pressed.emit()
	await poll()
	test.check(editor.fixture(ID_A).dmx_mode == "Pixels & Pan" and editor.state().dirty, "Inspector Apply commits the selected mode")
	test.check(is_same(pan, axis(ID_A, true)) and absf(pan.rotation_degrees.y - (-270.0+540.0*4660.0/65535.0)) < 0.01, "Held ArtDmx is reevaluated against the new sparse 16-bit Pan route")
	test.check(is_zero_approx(tilt.rotation_degrees.x) and axis(ID_A, false) == null, "Removed Tilt returns to its authored axis transform")
	test.check(other_pan.rotation_degrees.y == previous_other and is_same(unrelated, app._scene_registry.get_fixture(ID_B)), "Other fixture playback and root remain in place")
	test.check(fixture.transform == original_transform and app.app_shell.selection.ids == PackedStringArray([ID_A]), "Root transform and selection survive")
	test.check(physical_models() == initial_meshes, "Independent emitter mode preserves compatible scene meshes and materials")
	var levels: Array[float] = []
	var adapter = app._fixture_light_apply_service._dense_adapter
	for output: Dictionary in app._native_target_registry._beam_output_records_by_id.values():
		if output.fixture_uuid != ID_A: continue
		var values: PackedFloat32Array = adapter._native.physical_values(output.dense_output_index)
		if not values.is_empty(): levels.append(values[0])
	levels.sort()
	test.check(levels.size() == 2 and absf(levels[0] - 192.0 / 255.0) < 0.0001 and is_equal_approx(levels[1], 1.0),
		"The same physical emitters now follow independent Dimmer sources")
	test.check(app._scene_setup_resource_metrics.mode_geometry_created == 0, "Same-root mode creates no fixture geometry")
	test.check(editor.patch_fixture(ID_A).breaks[0].footprint == 8, "Patch footprint refreshes after Apply")
	test.check(await editor.history(false), "Undo uses the same installation path")
	await poll()
	test.check(absf(pan.rotation_degrees.y - original_pan) < 0.01 and editor.fixture(ID_A).dmx_mode == "Preview 3ch", "Undo restores the previous live mode")
	test.check(await editor.history(true), "Redo reinstalls the new mode")
	app._dmx_controller.stop_dmx()
	var old_pan_id := pan.get_instance_id()
	test.check(await editor.apply_mode(ID_A, "Alternative"), "Switch roots with DMX disabled")
	test.check(not is_instance_id_valid(old_pan_id) and is_same(fixture, app._scene_registry.get_fixture(ID_A)), "Root replacement retires generated geometry and keeps the MVR root")
	test.check(not app._scene_registry.get_anchor(ID_A, "emitters").is_empty(), "Alternative root registers its emitter")
	test.check(app._scene_setup_resource_metrics.mode_geometry_created == 2 and app._scene_setup_resource_metrics.mode_geometry_retired > 2,
		"Alternative-root installation reports the fixture-local geometry changes")
	test.check(await editor.history(false), "Undo root replacement")
	for iteration in range(3):
		test.check(await editor.history(false) and await editor.history(true), "Repeated mode Undo/Redo keeps the current fixture topology")
	test.check(await editor.history(false), "Restore source mode before interleaving document commands")
	test.check(editor.apply_patch(ID_A, 1, 2, 1, "insert"), "Assign the additional authored break explicitly")
	test.check(app._dmx_controller.start_dmx(), "Restart Art-Net for a multi-break mode change")
	await send_dmx()
	test.check(await editor.apply_mode(ID_A, "Needs break"), "Install a mode that requires two authored DMX breaks")
	test.check(is_zero_approx(axis(ID_A, true).rotation_degrees.y), "A newly subscribed universe has no fabricated Pan input")
	var second_universe := PackedByteArray()
	second_universe.resize(512)
	second_universe[0] = 0x80
	second_universe[2] = 0x80
	await send_universe(1, second_universe)
	test.check(absf(axis(ID_A, true).rotation_degrees.y - (-270.0 + 540.0 * 32896.0 / 65535.0)) < 0.01,
		"A real ArtDmx packet reaches the new break and drives 16-bit Pan")
	test.check(await editor.history(false) and editor.history(false), "Undo the mode and explicit break assignment in order")
	app._dmx_controller.stop_dmx()
	test.check(editor.apply(PackedStringArray([ID_A]), 0, true), "Stage Pan inversion in the shared history")
	test.check(editor.apply_patch(ID_A, 0, 1, 18), "Stage explicit patch in the shared history")
	test.check(await editor.apply_mode(ID_A, "Pixels & Pan"), "Stage mode after inversion and patch")
	test.check(await editor.history(false) and editor.history(false) and editor.history(false),
		"Undo traverses mode, patch and inversion in order")
	test.check(editor.fixture(ID_A).dmx_mode == "Preview 3ch" and not editor.fixture(ID_A).pan and editor.fixture(ID_A).addresses[0].address == 1,
		"Mixed undo restores original typed values")
	test.check(editor.history(true) and editor.history(true) and await editor.history(true), "Redo interleaves all three command kinds")
	test.check(await editor.history(false) and editor.history(false) and editor.history(false),
		"Restore the original values before export comparison")
	test.check(await editor.apply_mode(ID_A, "Pixels & Pan") and editor.fixture(ID_A).addresses[1]["break"] == 9,
		"Mode preserves the unused authored break")
	var exported := base + "-output.mvr"
	test.check(editor.export_mvr(exported), "Export unsaved mode edit")
	test.check(OS.execute("python3", PackedStringArray([generator, "--verify", source, exported])) == 0, "Only the exact mode value differs, with binary resources preserved")
	var project := base + ".pvz"
	app._on_save_project_selected(project)
	var zip := ZIPReader.new()
	if zip.open(project) == OK:
		test.check(zip.read_file("scene.mvr") == FileAccess.get_file_as_bytes(exported), "PVZ embeds the identical edited MVR")
		zip.close()
	else:
		test.check(false, "PVZ opens")
	await app._open_project(project)
	test.check(app.app_shell.document.fixture(ID_A).dmx_mode == "Pixels & Pan" and axis(ID_A, false) == null, "PVZ reload installs the authored mode")
	await app._load_mvr_scene(exported, "mvr", false)
	test.check(app.app_shell.document.fixture(ID_A).dmx_mode == "Pixels & Pan" and FileAccess.get_sha256(source) == original_hash, "Standalone export reopens and source is untouched")
	await finish()

func physical_models() -> PackedInt64Array:
	var ids := PackedInt64Array()
	for node: Node3D in app._node_index.values():
		if not node.has_meta("peraviz_model_visual"): continue
		var visual: Node3D = node.get_meta("peraviz_model_visual")
		if visual is MeshInstance3D and visual.mesh != null:
			ids.append(visual.get_instance_id())
			ids.append(visual.mesh.get_instance_id())
			for surface in range(visual.mesh.get_surface_count()):
				var material: Material = visual.get_active_material(surface)
				ids.append(material.get_instance_id() if material != null else 0)
	ids.sort()
	return ids

func send_dmx() -> void:
	var data := PackedByteArray()
	data.resize(512)
	data[0] = 255
	data[1] = 64
	data[2] = 32
	data[3] = 0x12
	data[5] = 0x34
	data[7] = 192
	await send_universe(0, data)

func send_universe(universe: int, data: PackedByteArray) -> void:
	app._dmx_controller.process_dmx(0.016)
	var packet := PackedByteArray([65,114,116,45,78,101,116,0,0,80,0,14,1,0,universe,0,2,0])
	packet.append_array(data)
	test.check(udp.put_packet(packet) == OK, "Send one real ArtDmx universe")
	await create_timer(0.05).timeout
	await poll()
