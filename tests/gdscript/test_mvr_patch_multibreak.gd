extends "res://tests/gdscript/test_mvr_document_editing.gd"

func run() -> void:
	OS.set_environment("PERAVIZ_NATIVE_EVALUATION", "serial")
	existed = FileAccess.file_exists(prefs_path)
	saved = FileAccess.get_file_as_bytes(prefs_path) if existed else PackedByteArray()
	var config := ConfigFile.new()
	config.set_value("session", "auto_load_last_file", false)
	config.save(prefs_path)
	var source := ProjectSettings.globalize_path("user://patch-multibreak-%d.mvr" % OS.get_process_id())
	test.check(OS.execute("python3",PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_patch_editing_fixture.py"),source,"--multibreak"])) == 0,"Generate multibreak canonical patch source")
	app = load("res://test.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.set_process(false)
	var loaded: Dictionary = await app._load_mvr_scene(source,"mvr",false)
	test.check(loaded.get("ok",false),"Multibreak patch source imports")
	if not loaded.get("ok",false):
		await finish()
		return
	app.camera.set_process(false)
	app.app_shell.selection.select(PackedStringArray([ID_A]))
	var editor: RefCounted = app.app_shell.document
	var runtime: RefCounted = app._dmx_controller._dmx_fixture_runtime
	runtime.set_debug_force_full_apply(true)
	var frames := {}
	for universe in range(3):
		var frame := PackedByteArray()
		frame.resize(512)
		frames[universe] = frame
	frames[0][0]=255; frames[0][20]=255
	frames[1][0]=64; frames[1][2]=128; frames[1][201]=192
	frames[2][1]=32; frames[2][100]=128; frames[2][102]=64
	for universe in frames: runtime._native_visual_runtime.submit_universe_frame(universe,frames[universe])
	runtime.apply_visual_frame(app._dmx_controller._dmx_receiver,app,app._fixture_light_apply_service,0)
	var original := -270.0+540.0*16512.0/65535.0
	var moved := 270.0-540.0*32832.0/65535.0
	test.check(app._fixture_inspection_panel._patch_panel._rows.get_child_count()==4,"Inspector retains each authored break row in original order")
	test.check(editor.apply(PackedStringArray([ID_A]),0,true),"Invert Pan in shared history")
	test.check(editor.apply_patch(ID_A,0,1,21),"Change primary Dimmer break without touching other assignments")
	test.check(editor.apply_patch(ID_A,1,3,101),"Change secondary Pan break with noncontiguous coarse/fine bytes")
	test.check(absf(axis(ID_A,true).rotation_degrees.y-moved)<0.01 and absf(axis(ID_B,true).rotation_degrees.y-original)<0.01,"Held 16-bit rebind is fixture-local and retains inversion")
	test.check(editor.history(false) and absf(axis(ID_A,true).rotation_degrees.y+original)<0.01,"Undo secondary patch restores full-width old Pan")
	test.check(editor.history(false) and editor.fixture(ID_A).addresses[1].address==1,"Undo primary patch preserves address-break order")
	test.check(editor.history(false) and not editor.fixture(ID_A).pan,"Undo inversion after two patch commands")
	test.check(editor.history(true) and editor.history(true) and editor.history(true),"Redo the complete mixed command sequence")
	test.check(editor.apply_patch(ID_A,2,2,201),"Repatch Tilt independently to its own numbered break")
	test.check(absf(axis(ID_A,false).rotation_degrees.x-(-135.0+270.0*192.0/255.0))<0.01 and absf(axis(ID_A,true).rotation_degrees.y-moved)<0.01,"Tilt uses edited break identity rather than a universe offset")
	test.check(editor.apply_patch(ID_A,7,7,201,"insert") and editor.fixture(ID_A).addresses.size()==4,"Noncontiguous optional break is inserted explicitly")
	test.check(editor.apply_patch(ID_A,7,0,0,"remove"),"Unused secondary assignment can be removed safely")
	var previous: Array = editor.fixture(ID_A).addresses.duplicate(true)
	test.check(not editor.apply_patch(ID_A,1,0,0,"remove") and editor.fixture(ID_A).addresses==previous,"Removing a required GDTF break fails without document/runtime divergence")
	for policy in ["off", "auto_safe", "auto_overlap"]:
		await app._dmx_controller.set_auto_span_policy(policy)
		for universe in frames: runtime._native_visual_runtime.submit_universe_frame(universe,frames[universe])
		runtime.apply_visual_frame(app._dmx_controller._dmx_receiver,app,app._fixture_light_apply_service,0)
		test.check(editor.apply_patch(ID_A,1,3,111), "Authored repatch is validated under Auto Span " + policy)
		test.check(editor.history(false) and editor.fixture(ID_A).addresses.size()==3 and editor.fixture(ID_A).addresses[2].address==101, "Undo retains authored breaks without inventing Auto Span continuation entries")
	var exported := source+"-edited.mvr"
	test.check(editor.export_mvr(exported),"Multibreak canonical patch exports")
	test.check(OS.execute("python3",PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_patch_editing_fixture.py"),"--verify",source,exported]))==0,"Multibreak resources, Network, unrelated hierarchy and XML survive")
	await app._load_mvr_scene(exported,"mvr",false)
	test.check(app.app_shell.document.fixture(ID_A).addresses[0]["break"]==2 and app.app_shell.document.fixture(ID_A).addresses[0].universe==2,"Reopened edited MVR retains authored order and non-primary break values")
	await finish()
