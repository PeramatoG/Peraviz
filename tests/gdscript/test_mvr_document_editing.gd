extends SceneTree

const Case = preload("res://tests/gdscript/headless_test_case.gd")
const ID_A := "87dd723c-3e08-5e5a-a03f-fb0e5d95f08f"
const ID_B := "4fb154e6-9b9a-5a58-84a4-73c10c285a72"
var test = Case.new()
var app: Node3D
var udp := PacketPeerUDP.new()
var prefs_path := UserPreferences.SETTINGS_FILE_PATH
var saved: PackedByteArray
var existed: bool

func _initialize() -> void: run.call_deferred()

func run() -> void:
	existed = FileAccess.file_exists(prefs_path)
	saved = FileAccess.get_file_as_bytes(prefs_path) if existed else PackedByteArray()
	var config := ConfigFile.new()
	config.set_value("session","auto_load_last_file",false)
	config.set_value("ui","fixture_casing_lod",false)
	config.save(prefs_path)
	var base := ProjectSettings.globalize_path("user://editing-%d" % OS.get_process_id())
	var source := base + ".mvr"
	test.check(OS.execute("python3",PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_mvr_editing_fixture.py"),source])) == 0,"Generate public canonical source")
	var original_hash := FileAccess.get_sha256(source)
	app = load("res://test.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	var loaded: Dictionary = await app._load_mvr_scene(source,"mvr",false)
	test.check(loaded.get("ok",false),"Canonical source imports")
	app.camera.set_process(false)
	var editor: RefCounted = app.app_shell.document
	test.check(editor.fixture(ID_A).get("editable",false),"Canonical fixture identity is editable")
	test.check(not editor.fixture(ID_A).pan and not editor.fixture(ID_A).pan_present,"Missing inversion reads false without inventing presence")
	test.check(editor.export_mvr(base+"-noop.mvr") and FileAccess.get_sha256(base+"-noop.mvr") == original_hash,"UI export preserves unmodified source bytes")
	app.app_shell.selection.select(PackedStringArray([ID_A]))
	var pan: Node3D = axis(ID_A,true)
	var tilt: Node3D = axis(ID_A,false)
	var other_pan: Node3D = axis(ID_B,true)
	test.check(pan != null and tilt != null and other_pan != null,"Qualified runtime axes resolve")
	if pan == null or tilt == null or other_pan == null:
		await finish()
		return
	var scene_identity: int = app.proxies_root.get_instance_id()
	var fixture_identity: int = app._scene_registry.get_fixture(ID_A).get_instance_id()
	var camera_transform: Transform3D = app.camera.global_transform
	var generation: int = app._dmx_controller._dmx_fixture_runtime._runtime_generation
	var resources := source_materials()
	test.check(app._dmx_controller.start_dmx(),"Production Art-Net receiver starts")
	udp.connect_to_host("127.0.0.1",6454)
	await send_dmx()
	if OS.get_environment("PERAVIZ_NATIVE_EVALUATION") == "parallel":
		test.check(app._fixture_light_apply_service._dense_adapter._native.get_sizes().get("native_async_active",false),"Forced parallel run owns a real native asynchronous presentation session")
	var normal_pan: float = pan.rotation_degrees.y
	var normal_tilt: float = tilt.rotation_degrees.x
	resources = source_materials()
	camera_transform = app.camera.global_transform
	test.check(absf(normal_pan-(-270.0+540.0*64.0/255.0)) < 0.01,"Real Art-Net drives expected Pan mapping")
	test.check(absf(normal_tilt-(-135.0+270.0*32.0/255.0)) < 0.01,"Real Art-Net drives independent Tilt mapping")
	var pan_button: Button = app._fixture_inspection_panel._inversion_rows[0].button
	test.check(pan_button.text == "OFF" and not pan_button.button_pressed,"Inspector uses one OFF toggle for an uninverted fixture")
	pan_button.button_pressed = true
	await poll()
	test.check(editor.fixture(ID_A).pan and editor.state().dirty and pan_button.text == "ON" and pan_button.button_pressed,"Inspector toggle commits canonical Pan and displays ON")
	test.check(absf(pan.rotation_degrees.y+normal_pan)<0.01 and absf(other_pan.rotation_degrees.y-normal_pan)<0.01,"Held Pan updates without a packet; overlapping fixture is unchanged")
	pan_button.button_pressed = false
	test.check(not editor.fixture(ID_A).pan and pan_button.text == "OFF","The same toggle disables Pan and displays OFF")
	await poll()
	test.check(absf(pan.rotation_degrees.y-normal_pan)<0.01,"Disabling Pan restores original mapping")
	test.check(editor.apply(PackedStringArray([ID_A]),1,true),"Tilt edits independently")
	await poll()
	test.check(absf(tilt.rotation_degrees.x+normal_tilt)<0.01 and absf(pan.rotation_degrees.y-normal_pan)<0.01,"Tilt-only inversion does not affect Pan")
	test.check(editor.history(false) and not editor.fixture(ID_A).tilt_present,"Undo restores XML absence")
	test.check(editor.history(true) and editor.fixture(ID_A).tilt,"Redo restores inversion")
	app.app_shell.selection.select(PackedStringArray([ID_A,ID_B]))
	var tilt_button: Button = app._fixture_inspection_panel._inversion_rows[1].button
	test.check(tilt_button.text == "Mixed → ON" and not tilt_button.button_pressed,"Mixed values offer an explicit enable-all action")
	tilt_button.button_pressed = true
	test.check(editor.fixture(ID_A).tilt and editor.fixture(ID_B).tilt and tilt_button.text == "ON","Mixed toggle applies ON atomically to the complete selection")
	test.check(editor.history(false) and editor.fixture(ID_A).tilt and not editor.fixture(ID_B).tilt and tilt_button.text == "Mixed → ON","Undo restores mixed values and the toggle label")
	test.check(editor.apply(PackedStringArray([ID_A,ID_B]),0,true),"Validated multi-fixture edit applies atomically")
	var capture_path := OS.get_environment("PERAVIZ_EDIT_CAPTURE")
	if not capture_path.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_path)
	var before: Dictionary = editor.state()
	test.check(not editor.apply(PackedStringArray([ID_A,"missing-id"]),1,false) and editor.fixture(ID_A).tilt and editor.fixture(ID_B).pan,"Invalid target rejects the whole selection")
	test.check(editor.state().can_undo == before.can_undo,"Rejected mutation leaves history intact")
	await poll()
	test.check(app.proxies_root.get_instance_id() == scene_identity and app._scene_registry.get_fixture(ID_A).get_instance_id() == fixture_identity and app._dmx_controller._dmx_fixture_runtime._runtime_generation == generation,"Edits do not reconstruct geometry or recompile the whole runtime")
	test.check(app.camera.global_transform == camera_transform,"Camera transform survives edits")
	test.check(resources == source_materials(),"Unrelated source mesh/material identities survive edits")
	test.check(app.app_shell.selection.ids == PackedStringArray([ID_A,ID_B]),"Editing preserves selection")
	var undone := InputEventKey.new()
	undone.keycode = KEY_Z
	undone.ctrl_pressed = true
	undone.pressed = true
	app.app_shell.explorer.search.grab_focus()
	app.app_shell._unhandled_input(undone)
	test.check(editor.fixture(ID_B).pan,"Text input owns its Undo shortcut")
	app.app_shell.explorer.search.release_focus()
	root.push_input(undone,true)
	test.check(not editor.fixture(ID_B).pan,"Ctrl+Z reaches document Undo outside text fields")
	undone.shift_pressed = true
	root.push_input(undone,true)
	test.check(editor.fixture(ID_B).pan,"Ctrl+Shift+Z reaches Redo")
	editor.context = {"project":{"other_metadata":"preserved"},"fixture_overrides":{ID_A:{"visual_only":true}}}
	test.check(not editor.guard_open(Callable()) and editor._discard_dialog.visible,"Unsaved edits require confirmation before replacing the scene")
	editor._discard_dialog.canceled.emit()
	editor._discard_dialog.hide()
	test.check(editor.state().dirty and not editor._pending_open.is_valid(),"Cancel keeps the current edited document intact")
	var project := base+".pvz"
	app._on_save_project_selected(project)
	test.check(FileAccess.file_exists(project) and not editor.state().dirty,"Save PVZ succeeds and marks the document save point")
	# Cross a ZIP timestamp quantum: a second writer would no longer accidentally match.
	await create_timer(2.1).timeout
	var exported := base+"-edited.mvr"
	test.check(editor.export_mvr(exported),"Standalone export needs no new PVZ save")
	var zip := ZIPReader.new()
	test.check(zip.open(project) == OK,"Saved PVZ opens")
	test.check(zip.read_file("scene.mvr") == FileAccess.get_file_as_bytes(exported),"Mandatory contract: embedded scene.mvr is byte-identical to standalone export")
	test.check(JSON.parse_string(zip.read_file("project.json").get_string_from_utf8()).other_metadata == "preserved","Optional project metadata survives saving")
	test.check(JSON.parse_string(zip.read_file("fixture_overrides.json").get_string_from_utf8())[ID_A].visual_only,"Distinct visual-only overrides survive without storing inversion")
	zip.close()
	test.check(OS.execute("python3",PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_mvr_editing_fixture.py"),"--verify",source,exported])) == 0,"Independent ZIP/XML reader verifies hierarchy, unknown data and resource hashes")
	test.check(not editor.export_mvr(source) and FileAccess.get_sha256(source) == original_hash,"Original imported MVR is protected")
	test.check(editor.apply(PackedStringArray([ID_A]),0,false),"Another edit remains pending")
	app._on_save_project_selected(base+"-missing/project.pvz")
	test.check(editor.state().dirty,"Failed PVZ save retains pending edits")
	var unsaved_export := base+"-unsaved.mvr"
	test.check(editor.export_mvr(unsaved_export),"Export includes edits not yet saved in PVZ")
	var exported_doc = ClassDB.instantiate("PeravizMvrDocument")
	test.check(exported_doc.open(unsaved_export) and not exported_doc.fixture(ID_A).pan,"Unsaved export contains the current edited document")
	exported_doc = null
	app._dmx_controller.stop_dmx()
	await app._open_project(project)
	app.set_process(false)
	editor = app.app_shell.document
	test.check(editor.fixture(ID_A).pan and editor.fixture(ID_A).tilt and not editor.state().can_undo,"Reopened PVZ uses embedded edited MVR and starts fresh history")
	test.check(app._dmx_controller.start_dmx(),"Art-Net restarts after project replacement")
	await send_dmx()
	test.check(absf(axis(ID_A,true).rotation_degrees.y+normal_pan)<0.01 and absf(axis(ID_A,false).rotation_degrees.x+normal_tilt)<0.01,"PVZ reload preserves actual native inversion")
	app._dmx_controller.stop_dmx()
	await app._load_mvr_scene(exported,"mvr",false)
	test.check(app.app_shell.document.fixture(ID_A).pan and app.app_shell.document.fixture(ID_A).tilt and app._node_index.has(ID_B),"Exported MVR directly reopens with canonical identities and inversion")
	await finish()

func axis(id: String, pan: bool) -> Node3D:
	var fixture: Node = app._scene_registry.get_fixture(id)
	var targets: Dictionary = app._native_target_registry._pan_targets if pan else app._native_target_registry._tilt_targets
	for node in targets.values():
		if fixture.is_ancestor_of(node): return node
	return null

func source_materials() -> PackedInt64Array:
	var ids := PackedInt64Array()
	for mesh in app.proxies_root.find_children("*","MeshInstance3D",true,false):
		ids.append(mesh.get_instance_id())
		if mesh.mesh != null:
			ids.append(mesh.mesh.get_instance_id())
			for surface in range(mesh.mesh.get_surface_count()):
				var material: Material = mesh.get_active_material(surface)
				if material != null: ids.append(material.get_instance_id())
	return ids

func send_dmx() -> void:
	app._dmx_controller.process_dmx(0.016) # Install native subscription before sending the first packet.
	var packet := PackedByteArray([65,114,116,45,78,101,116,0,0,80,0,14,1,0,0,0,2,0])
	var data := PackedByteArray()
	data.resize(512)
	data[0]=255;data[1]=64;data[2]=32
	packet.append_array(data)
	test.check(udp.put_packet(packet) == OK,"Send deterministic local ArtDmx packet")
	await create_timer(0.05).timeout
	await poll()

func poll() -> void:
	for frame in range(12):
		app._dmx_controller.process_dmx(0.016)
		await process_frame

func finish() -> void:
	udp.close()
	if app != null:
		app._dmx_controller.stop_dmx()
		app.queue_free()
		await process_frame
	if existed:
		var file := FileAccess.open(prefs_path,FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	else: DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs_path))
	test.finish(self)
