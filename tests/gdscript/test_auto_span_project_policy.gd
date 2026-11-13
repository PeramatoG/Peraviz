extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
const Policy = preload("res://scripts/project/dmx_auto_span_policy.gd")
var test = TestCase.new()
var app: Node
var source: String

func _initialize() -> void:
	_run.call_deferred()

# Delivers real ArtDmx on loopback; policy switches below send no additional packet.
func _send(peer: PacketPeerUDP, universe: int, values: PackedByteArray) -> void:
	var packet := PackedByteArray([65,114,116,45,78,101,116,0,0,80,0,14,0,0,universe,0,2,0])
	packet.append_array(values)
	test.check(peer.put_packet(packet) == OK,"Loopback ArtDmx packet sent")

func _settle() -> void:
	for i in range(12): await process_frame

func _material(identity: String, pixel: int) -> PackedFloat32Array:
	var adapter: RefCounted = app._fixture_light_apply_service._dense_adapter
	for index in adapter._binding_records.size():
		var key: String = str(adapter._binding_records[index].geometry_key)
		if key.begins_with(identity + "/") and key.contains("/Pixel%d/" % pixel):
			var output: RefCounted = adapter._outputs[index]
			if not output.materials.is_empty(): return adapter._native.material_values(output.materials[0].rid)
	return PackedFloat32Array()

func _run() -> void:
	test.check(Policy.normalize("invalid") == "auto_safe","Invalid identifiers recover conservatively with a diagnostic")
	test.check(change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) == OK,"Application loads")
	await process_frame
	await process_frame
	app = current_scene
	app._user_preferences.auto_load_last_file = false
	app._user_preferences.auto_start_dmx = false
	app._dmx_controller.set_universe_offset(-1,false)
	source = ProjectSettings.globalize_path("user://automatic_policy.mvr")
	test.check(OS.execute("python3",PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_auto_span_policy_fixture.py"),source])) == 0,"Generate public synthetic overlap fixture")
	var archive_hash: String = FileAccess.get_sha256(source)
	var imported: Dictionary = await app._load_mvr_scene(source,"mvr",false)
	test.check(imported.get("ok",false),"Policy-aware native preparation imports normally")
	var controller: RefCounted = app._dmx_controller
	test.check(controller.get_auto_span_policy() == "auto_safe","Ordinary MVR and new projects default to auto_safe")
	var window: Window = app.visual_settings_window
	var panel: Control = controller._auto_span_panel
	window.set_advanced_mode_enabled(false)
	test.check(window._tabs.is_tab_hidden(panel.get_index()),"DMX policy stays outside the basic viewer/settings interface")
	window.set_advanced_mode_enabled(true)
	test.check(not window._tabs.is_tab_hidden(panel.get_index()) and panel.selector.item_count == 3,"Advanced DMX selector exposes exactly three modes")
	var safe_setup: Dictionary = app._loader.compile_visual_runtime_scene(-1)
	test.check(safe_setup.dmx_auto_span_policy == "auto_safe","Prepared setup uses the project policy")
	test.check(controller.start_dmx(),"Loopback receiver starts")
	# Establish the native subscription before sending; the test must not race the first presentation tick.
	await process_frame
	var runtime: RefCounted = controller._dmx_fixture_runtime
	test.check(controller._dmx_receiver.configure_visual_runtime(runtime._native_visual_runtime),"Native replay subscription installed before packets")
	runtime._receiver_subscription_generation = runtime._runtime_generation
	var peer := PacketPeerUDP.new()
	test.check(peer.connect_to_host("127.0.0.1",6454) == OK,"Loopback UDP destination configured")
	var first := PackedByteArray()
	var second := PackedByteArray()
	first.resize(512)
	second.resize(512)
	second[8] = 255
	_send(peer,1,second)
	_send(peer,0,first)
	await create_timer(0.05).timeout
	await _settle()
	var other_before := _material("other",0)
	test.check(other_before.size() == 4 and other_before[0] > 0.99 and other_before[3] > 0,"Normally patched fixture receives its red byte")
	panel.selector.select(2)
	panel.selector.item_selected.emit(2)
	await _settle()
	test.check(controller.get_auto_span_policy() == "auto_overlap" and app._loader.get_dmx_auto_span_policy() == "auto_overlap","GUI policy reaches the native setup owner")
	var inferred := _material("strip",3)
	var other := _material("other",0)
	test.check(inferred.size() == 4 and inferred[1] > 0.99 and inferred[0] < 0.01 and inferred[3] > 0,"Held shared byte becomes green on the inferred fixture")
	test.check(other == other_before,"Policy change does not alter, suppress or prioritize the normally patched red fixture")
	test.check(not app._loader.get_load_metrics().auto_span_prepared_reused,"A changed policy cannot reuse another prepared scene/control/render generation")
	var saved: Dictionary = app._project_archive.save_project(ProjectSettings.globalize_path("user://automatic_policy.pvz"),source,"test",app._visual_settings,app._collect_dmx_project_settings(),{})
	test.check(saved.get("ok",false),"Policy persists in a PVZ without changing the source patch")
	var opened: Dictionary = app._project_archive.open_project(ProjectSettings.globalize_path("user://automatic_policy.pvz"))
	test.check(opened.get("dmx_settings",{}).get("auto_span_policy","") == "auto_overlap","Saved identifier reloads exactly")
	test.check(app._project_archive.get_default_dmx_settings().auto_span_policy == "auto_safe","Missing legacy project values use auto_safe")
	await controller.set_auto_span_policy("off")
	await _settle()
	test.check(_material("other",0) == other_before,"Strict mode preserves other fixtures during held DMX")
	await controller.set_auto_span_policy("auto_overlap")
	await _settle()
	test.check(_material("strip",3) == inferred,"Off/overlap replacement restores held material state without a new packet")
	window._on_reset_pressed()
	await _settle()
	test.check(controller.get_auto_span_policy() == "auto_safe" and panel.selector.selected == 1,"Reset restores automatic-safe project policy")
	test.check(FileAccess.get_sha256(source) == archive_hash,"GUI, playback and persistence preserve the exact source MVR archive")
	controller.stop_dmx()
	peer.close()
	opened["source_path"] = ProjectSettings.globalize_path("user://automatic_policy.pvz")
	var restored: Dictionary = await app._load_mvr_scene(str(opened.scene_path),"pvz",false,opened)
	test.check(restored.get("ok",false) and controller.get_auto_span_policy() == "auto_overlap","PVZ applies the saved policy before native preparation")
	test.check(app._loader.compile_visual_runtime_scene(-1).dmx_auto_span_policy == "auto_overlap","Restored prepared cache has the saved policy")
	await app._load_mvr_scene(source,"mvr",false)
	test.check(controller.get_auto_span_policy() == "auto_safe","Opening an ordinary MVR resets the project policy")
	app._clear_scene()
	app.queue_free()
	await process_frame
	test.finish(self)
