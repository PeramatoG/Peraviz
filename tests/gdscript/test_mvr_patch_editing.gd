extends "res://tests/gdscript/test_mvr_document_editing.gd"

var packet_sequence: int = 0

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1366, 768)
	existed = FileAccess.file_exists(prefs_path)
	saved = FileAccess.get_file_as_bytes(prefs_path) if existed else PackedByteArray()
	var config := ConfigFile.new()
	config.set_value("session", "auto_load_last_file", false)
	config.set_value("ui", "fixture_casing_lod", false)
	config.save(prefs_path)
	var source := ProjectSettings.globalize_path("user://patch-%d.mvr" % OS.get_process_id())
	test.check(OS.execute("python3", PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_patch_editing_fixture.py"), source, "--count", "32"])) == 0, "Generate canonical patch fixture")
	var source_hash := FileAccess.get_sha256(source)
	app = load("res://test.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	var loaded: Dictionary = await app._load_mvr_scene(source, "mvr", false)
	test.check(loaded.get("ok", false), "Canonical patch scene imports")
	if not loaded.get("ok",false):
		await finish()
		return
	app.camera.set_process(false)
	var editor: RefCounted = app.app_shell.document
	app.app_shell.selection.select(PackedStringArray([ID_A]))
	var panel = app._fixture_inspection_panel._patch_panel
	test.check(panel != null and panel._rows.get_child_count() == 1, "Single fixture exposes just its existing patch row")
	var inputs: Array = panel._rows.get_child(0).find_children("*", "LineEdit", true, false)
	test.check(inputs.size() == 2 and inputs[0].text == "1" and inputs[1].text == "1", "Inspector displays authored 1-based universe/address")
	inputs[1].grab_focus()
	inputs[1].text = "223"
	inputs[0].grab_focus()
	await process_frame
	test.check(inputs[1].text == "1" and editor.fixture(ID_A).addresses[0].address == 1 and not editor.state().dirty, "Leaving an unconfirmed field restores its canonical value without a command")
	inputs[1].grab_focus()
	inputs[1].text = "513"
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	root.push_input(enter, true)
	test.check(not editor.state().dirty and inputs[1].text == "1" and panel._message.text.contains("whole number"), "Enter rejects invalid text and restores the saved address")
	inputs[0].grab_focus()
	inputs[0].text = "2"
	root.push_input(enter, true)
	test.check(editor.fixture(ID_A).addresses[0].universe == 2 and editor.state().dirty, "Enter alone commits a valid Universe through the document/runtime transaction")
	test.check(editor.history(false) and not editor.state().dirty, "Undo of Enter submission restores the original patch")
	inputs = panel._rows.get_child(0).find_children("*", "LineEdit", true, false)
	inputs[1].grab_focus()
	inputs[1].text = "101"
	root.push_input(enter, true)
	test.check(editor.fixture(ID_A).addresses[0].address == 101 and editor.fixture(ID_A).addresses[0].universe == 1, "Address Enter changes only the submitted field")
	test.check(editor.history(false) and not editor.state().dirty, "Address Undo retains original XML semantics")
	inputs = panel._rows.get_child(0).find_children("*", "LineEdit", true, false)
	inputs[0].grab_focus()
	inputs[0].text = "7"
	inputs[0].release_focus()
	test.check(inputs[0].text == "1" and editor.fixture(ID_A).addresses[0].universe == 1, "Unconfirmed Universe is discarded on focus loss")
	inputs[1].grab_focus()
	inputs[1].text = "223"
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape, true)
	test.check(inputs[1].text == "1" and not editor.state().dirty and app.app_shell.selection.ids == PackedStringArray([ID_A]), "Escape discards the draft without clearing fixture selection")
	var scene_identity: int = app.proxies_root.get_instance_id()
	var generation: int = app._dmx_controller._dmx_fixture_runtime._runtime_generation
	var camera_transform: Transform3D = app.camera.global_transform
	var resources := source_materials()
	test.check(app._dmx_controller.start_dmx(), "Start real Art-Net before patch")
	udp.connect_to_host("127.0.0.1", 6454)
	app._dmx_controller.process_dmx(0.016)
	await send_patch_frames(64)
	resources = source_materials()
	camera_transform = app.camera.global_transform
	if OS.get_environment("PERAVIZ_NATIVE_EVALUATION") == "parallel":
		test.check(app._fixture_light_apply_service._dense_adapter._native.get_sizes().get("native_async_active",false),"Forced parallel patch test owns the native asynchronous presentation session")
	var normal := -270.0 + 540.0 * 64.0 / 255.0
	test.check(absf(axis(ID_A,true).rotation_degrees.y-normal)<0.01, "Original address responds to Art-Net")
	test.check(editor.apply(PackedStringArray([ID_A]),0,true), "Invert Pan before repatching")
	test.check(editor.apply_patch(ID_A,0,2,101), "Repatch to held universe/slot commits atomically")
	await poll()
	var moved := 270.0 - 540.0 * 192.0 / 255.0
	test.check(absf(axis(ID_A,true).rotation_degrees.y-moved)<0.01, "Held data at new patch applies without a new external packet and retains inversion")
	test.check(absf(axis(ID_B,true).rotation_degrees.y-normal)<0.01, "Overlapping neighbor keeps its independent old patch")
	test.check(absf(axis(ID_A,false).rotation_degrees.x-(-135.0+270.0*96.0/255.0))<0.01, "Repatch updates independent Tilt routing as well as inverted Pan")
	var capture := OS.get_environment("PERAVIZ_EDIT_CAPTURE")
	if not capture.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture)
	test.check(editor.fixture(ID_A).addresses[0].universe == 2 and editor.state().dirty, "Canonical document and Inspector agree with native routing")
	test.check(app._fixture_row_provider.get_fixture_row(ID_A).universe == "2" and int(app._loader.get_runtime_table_cell("fixtures",ID_A,5)) == 2, "Existing row provider and read-only native table project the edited authored patch")
	await send_patch_frames(32)
	test.check(absf(axis(ID_A,true).rotation_degrees.y-moved)<0.01 and absf(axis(ID_B,true).rotation_degrees.y-(-270.0+540.0*32.0/255.0))<0.01, "Old-address changes no longer drive repatched fixture")
	test.check(editor.history(false), "Undo patch")
	await poll()
	test.check(absf(axis(ID_A,true).rotation_degrees.y-(270.0-540.0*32.0/255.0))<0.01, "Undo consumes currently held old-address bytes")
	test.check(editor.history(false) and not editor.fixture(ID_A).pan, "Undo inversion after patch")
	test.check(editor.history(true) and editor.history(true), "Redo inversion and patch in one shared history")
	await poll()
	test.check(editor.apply_patch(ID_A,0,1,1) and not editor.patch_warnings.is_empty(), "Intentional overlaps remain valid and report a warning")
	test.check(editor.history(false), "Undo overlap returns the edited patch without relocating neighbors")
	test.check(editor.apply_patch(ID_A,7,3,201,"insert"), "Explicit unused noncontiguous break insertion is safe")
	test.check(editor.apply_patch(ID_A,7,0,0,"remove"), "Explicit removal retains required runtime routing")
	var before: Array = editor.fixture(ID_A).addresses.duplicate(true)
	test.check(not editor.apply_patch(ID_A,0,0,0,"remove") and editor.fixture(ID_A).addresses == before, "Unsafe required-break removal rolls back document and runtime")
	test.check(not editor.apply_patch(ID_A,0,32768,512) and editor.fixture(ID_A).addresses == before, "Out-of-range native universe reports a transactional failure")
	test.check(app.proxies_root.get_instance_id() == scene_identity and app._dmx_controller._dmx_fixture_runtime._runtime_generation == generation and source_materials() == resources and app.camera.global_transform == camera_transform, "Patch edits preserve geometry/materials, generation and camera")
	test.check(app.app_shell.selection.ids == PackedStringArray([ID_A]), "Selection survives patch commands")
	app.app_shell.selection.select(PackedStringArray([ID_A, ID_B]))
	test.check(panel._rows.get_child_count() == 0 and panel._message.text.contains("Select one fixture"), "Multi-fixture patch is read-only without collapsing distinct addresses")
	app.app_shell.selection.select(PackedStringArray([ID_A]))
	var exported := source + "-unsaved.mvr"
	test.check(editor.export_mvr(exported), "Export canonical patch before PVZ save")
	var project := source + ".pvz"
	app._on_save_project_selected(project)
	var zip := ZIPReader.new()
	test.check(zip.open(project) == OK and zip.read_file("scene.mvr") == FileAccess.get_file_as_bytes(exported), "Embedded MVR and standalone canonical patch archive are byte-identical")
	zip.close()
	test.check(OS.execute("python3",PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_patch_editing_fixture.py"),"--verify",source,exported])) == 0, "Independent preservation reader verifies resource SHA-256 and untouched XML")
	test.check(not editor.export_mvr(source) and FileAccess.get_sha256(source) == source_hash,"Imported original remains protected")
	app._dmx_controller.stop_dmx()
	test.check(editor.apply_patch(ID_A,0,2,201), "Patch edits work while Art-Net is stopped")
	test.check(app._dmx_controller.start_dmx(), "Restart Art-Net after stopped edit")
	await send_patch_frames(32)
	test.check(absf(axis(ID_A,true).rotation_degrees.y-(270.0-540.0*128.0/255.0))<0.01, "Stopped edit routes correctly after restart")
	app._dmx_controller.stop_dmx()
	await app._open_project(project)
	test.check(app.app_shell.document.fixture(ID_A).addresses[0].address == 101 and app.app_shell.document.fixture(ID_A).pan, "PVZ reopen restores embedded authored patch and inversion")
	await app._load_mvr_scene(exported,"mvr",false)
	test.check(app.app_shell.document.fixture(ID_A).addresses[0].universe == 2, "Standalone canonical MVR reopens with edited patch")
	await finish()

func send_patch_frames(old_pan: int) -> void:
	for universe in [0,1]:
		packet_sequence = 1 + packet_sequence % 255
		var packet := PackedByteArray([65,114,116,45,78,101,116,0,0,80,0,14,packet_sequence,0,universe,0,2,0])
		var data := PackedByteArray()
		data.resize(512)
		data[0]=255;data[1]=old_pan;data[2]=32
		data[100]=255;data[101]=192;data[102]=96
		data[200]=255;data[201]=128;data[202]=16
		packet.append_array(data)
		test.check(udp.put_packet(packet) == OK,"Send patch test universe")
	await create_timer(0.05).timeout
	await poll()
