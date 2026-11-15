extends "res://tests/gdscript/test_mvr_document_editing.gd"

func run() -> void:
	OS.set_environment("PERAVIZ_NATIVE_EVALUATION","serial")
	existed = FileAccess.file_exists(prefs_path)
	saved = FileAccess.get_file_as_bytes(prefs_path) if existed else PackedByteArray()
	var config := ConfigFile.new()
	config.set_value("session","auto_load_last_file",false)
	config.save(prefs_path)
	var source := ProjectSettings.globalize_path("user://multibreak-edit-%d.mvr" % OS.get_process_id())
	test.check(OS.execute("python3",PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_mvr_editing_fixture.py"),source,"--multibreak"])) == 0,"Generate canonical numbered-break source")
	app = load("res://test.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	var loaded: Dictionary = await app._load_mvr_scene(source,"mvr",false)
	test.check(loaded.get("ok",false),"Numbered-break MVR imports")
	app.app_shell.selection.select(PackedStringArray([ID_A]))
	var runtime: RefCounted = app._dmx_controller._dmx_fixture_runtime
	runtime.set_debug_force_full_apply(true)
	var frames := {0:PackedByteArray([255]),1:PackedByteArray([64,0,128]),2:PackedByteArray([0,32])}
	for universe in frames: runtime._native_visual_runtime.submit_universe_frame(universe,frames[universe])
	runtime.apply_visual_frame(app._dmx_controller._dmx_receiver,app,app._fixture_light_apply_service,0)
	var original := -270.0+540.0*16512.0/65535.0
	test.check(absf(axis(ID_A,true).rotation_degrees.y-original)<0.01,"Noncontiguous 16-bit Pan resolves break 1 in authored byte order")
	test.check(app.app_shell.document.apply(PackedStringArray([ID_A]),0,true),"Numbered-break Pan edit commits")
	test.check(absf(axis(ID_A,true).rotation_degrees.y+original)<0.01,"Held numbered-break bytes invert as one full 16-bit value")
	test.check(absf(axis(ID_B,true).rotation_degrees.y-original)<0.01,"Overlapping numbered-break fixture remains independent")
	test.check(app.app_shell.document.apply(PackedStringArray([ID_A]),1,true),"Independent Tilt break edit commits")
	test.check(absf(axis(ID_A,false).rotation_degrees.x-(135.0-270.0*32.0/255.0))<0.01,"Tilt uses its own numbered break without inverting Pan bytes")
	var exported := source+"-edited.mvr"
	test.check(app.app_shell.document.export_mvr(exported),"Numbered-break document exports")
	test.check(OS.execute("python3",PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_mvr_editing_fixture.py"),"--verify",source,exported])) == 0,"Address-break identity/order and all resources survive export")
	await finish()
