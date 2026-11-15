extends SceneTree

const Case = preload("res://tests/gdscript/headless_test_case.gd")
const Cap = preload("res://scripts/ui/frame_rate_limit.gd")
var test = Case.new()

class CameraProbe:
	extends "res://scripts/editor_camera.gd"
	var writes: int = 0
	func _notification(what: int) -> void:
		super._notification(what)
		if what == NOTIFICATION_TRANSFORM_CHANGED: writes += 1

class Receiver:
	extends RefCounted
	var running: bool = false
	var fail: bool = false
	func start(_ip: String, _port: int) -> bool:
		running = not fail
		return running
	func stop() -> void: running = false
	func is_running() -> bool: return running
	func get_last_error() -> String: return "synthetic bind failure"

class ControllerProbe:
	extends "res://scripts/controllers/dmx_controller.gd"
	var refreshes: int = 0
	var monitor_states: Array[bool] = []
	func _refresh_dmx_quick_panel(running: bool, receiving: bool, universes: PackedInt32Array, packet: int) -> void:
		refreshes += 1
		super._refresh_dmx_quick_panel(running,receiving,universes,packet)
	func _refresh_dmx_monitor_window(running: bool) -> void: monitor_states.append(running)
	# Transport/decoding is outside this controller transition regression.
	func _poll_and_apply_latest_dmx_controls(_delta: float) -> void: pass
	func _refresh_dmx_status_if_needed(_now: int) -> void: pass

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if "--fps-override-probe" in OS.get_cmdline_user_args() or "--fps-user-probe" in OS.get_cmdline_user_args():
		var before := Engine.max_fps
		var menu := PopupMenu.new()
		root.add_child(menu)
		var startup_preferences := UserPreferences.new()
		startup_preferences.fps_limit = 30
		Cap.install(menu,startup_preferences)
		if "--fps-override-probe" in OS.get_cmdline_user_args():
			test.check(Engine.max_fps == before and menu.is_item_disabled(0), "Explicit engine FPS options retain precedence at startup")
		else:
			test.check(Engine.max_fps == 30 and not menu.is_item_disabled(0), "Application arguments cannot masquerade as engine FPS overrides")
		menu.free()
		test.finish(self)
		return
	var path := UserPreferences.SETTINGS_FILE_PATH
	var existed := FileAccess.file_exists(path)
	var saved := FileAccess.get_file_as_bytes(path) if existed else PackedByteArray()
	var old_cap := Engine.max_fps
	var preferences := UserPreferences.new()
	test.check(preferences.fps_limit == 60, "Default application cap is 60 FPS")
	var menu := PopupMenu.new()
	root.add_child(menu)
	Cap.install(menu,preferences)
	test.check(Engine.max_fps == 60, "Startup applies the default cap")
	var limits: PopupMenu = menu.get_node("FrameRateLimit")
	for limit in [30,120,0,60]:
		limits.id_pressed.emit(limit)
		var restored := UserPreferences.new()
		restored.load_from_disk()
		test.check(restored.fps_limit == limit and Engine.max_fps == limit, "Every cap including Unlimited applies live and persists")
		var restart_menu := PopupMenu.new()
		root.add_child(restart_menu)
		Engine.max_fps = 77
		Cap.install(restart_menu,restored)
		test.check(Engine.max_fps == limit, "Saved cap restores on startup")
		restart_menu.free()
	for option in [["--max-fps","0"],["--max-fps","60"],["--max-fps","144"],["--fixed-fps","144"]]:
		var output: Array = []
		var result := OS.execute(OS.get_executable_path(),PackedStringArray(["--headless","--audio-driver","Dummy","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/gdscript/test_idle_runtime_efficiency.gd",option[0],option[1],"--","--fps-override-probe"]),output,true)
		test.check(result == 0, "Real Godot command-line override subprocess passes: %s %s" % [option,str(output)])
	var user_probe_output: Array = []
	var user_probe := OS.execute(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/gdscript/test_idle_runtime_efficiency.gd","--","--fps-user-probe","--max-fps","144"]),user_probe_output,true)
	test.check(user_probe == 0, "Arguments after -- do not override the preference: %s" % str(user_probe_output))
	var invalid := ConfigFile.new()
	invalid.set_value("ui","fps_limit",-1)
	invalid.save(path)
	var sanitized := UserPreferences.new()
	sanitized.load_from_disk()
	test.check(sanitized.fps_limit == 60, "Invalid saved limits fall back to 60")
	menu.free()
	await camera_checks()
	dmx_checks()
	Engine.max_fps = old_cap
	if existed:
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	else: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	test.finish(self)

func camera_checks() -> void:
	var camera := CameraProbe.new()
	root.add_child(camera)
	camera.set_process(false)
	camera.set_notify_transform(true)
	camera.scene_view_rect = Rect2(100,50,700,600)
	camera.target_yaw += 0.7
	camera.target_pitch += 0.2
	camera.target_roll += 0.3
	camera.target_distance += 12.0
	for frame in range(300): camera._process(1.0/60.0)
	camera.force_update_transform()
	test.check(camera.current_yaw == camera.target_yaw and camera.current_pitch == camera.target_pitch and camera.current_roll == camera.target_roll and camera.current_distance == camera.target_distance, "Smoothing converges to exact targets")
	var writes := camera.writes
	for frame in range(120):
		camera._process(1.0/60.0)
		camera.force_update_transform()
	test.check(camera.writes == writes, "Settled camera performs no transform writes")
	var transform_before := camera.global_transform
	camera.target_position += Vector3(0.01,0.02,0)
	camera._process(1.0/60.0)
	test.check(camera.global_transform != transform_before, "Target position changes resume camera writes immediately")
	var yaw_before := camera.current_yaw
	camera.orbit_by(Vector2(8,2))
	camera._process(1.0/60.0)
	test.check(camera.current_yaw != yaw_before and camera.current_yaw != camera.target_yaw, "Orbit input resumes smoothing on the next frame")
	for frame in range(300): camera._process(1.0/60.0)
	transform_before = camera.global_transform
	camera.scene_view_rect.position.x += 20
	camera._process(1.0/60.0)
	test.check(camera.global_transform != transform_before, "Layout changes update settled camera centering")
	camera.queue_free()
	await process_frame

func dmx_checks() -> void:
	var controller := ControllerProbe.new()
	var toggle := Button.new()
	toggle.toggle_mode = true
	var panel := DmxQuickPanel.new()
	root.add_child(toggle)
	root.add_child(panel)
	panel.set_monitor_available(true)
	controller._dmx_toggle_button = toggle
	controller._dmx_quick_panel = panel
	var statuses: Array = []
	var failures: Array = []
	controller.set_status_callbacks(func(running: bool, receiving: bool) -> void: statuses.append([running,receiving]),func(error: String) -> void: failures.append(error))
	for frame in range(120): controller.process_dmx(0.016)
	test.check(controller.refreshes == 1 and statuses == [[false,false]], "Missing receiver initializes OFF only once")
	var receiver := Receiver.new()
	controller._dmx_receiver = receiver
	test.check(controller.start_dmx() and toggle.button_pressed and panel._running and panel._status_value_label.text == "ON (no signal)", "Start updates button and quick panel immediately")
	for frame in range(120): controller.process_dmx(0.016)
	test.check(statuses.size() == 2, "Unchanged running status is not emitted per frame")
	controller._last_updated_fixtures = 42
	controller._last_receiving_signal = true
	controller._emit_dmx_status(true,true)
	controller._emit_dmx_status(true,true)
	test.check(statuses.size() == 3, "Receiving transition is emitted once")
	var before := controller.refreshes
	controller.stop_dmx()
	test.check(not toggle.button_pressed and not panel._running and controller._last_updated_fixtures == 0 and panel._status_value_label.text == "OFF" and controller.monitor_states.back() == false, "Stop immediately resets counters, quick panel, monitor and status")
	for frame in range(120): controller.process_dmx(0.016)
	controller.stop_dmx()
	test.check(controller.refreshes == before+1 and statuses.size() == 4, "Repeated stopped frames and stop requests do no repeated UI work")
	test.check(controller.start_dmx(), "Receiver restarts after stopping")
	receiver.stop()
	controller.process_dmx(0.016)
	test.check(not panel._running and not toggle.button_pressed, "Externally stopped receiver transitions to OFF")
	receiver.fail = true
	test.check(not controller.start_dmx() and failures.size() == 1 and toggle.tooltip_text.contains("synthetic bind failure"), "Failed start preserves error and establishes OFF immediately")
	before = controller.refreshes
	for frame in range(120): controller.process_dmx(0.016)
	test.check(controller.refreshes == before and statuses.size() == 6, "Failed startup does not repeat OFF resets")
	toggle.free()
	panel.free()
