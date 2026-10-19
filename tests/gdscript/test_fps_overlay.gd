extends SceneTree

const Overlay = preload("res://scripts/ui/fps_overlay.gd")
const Preferences = preload("res://scripts/ui/user_preferences.gd")
const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()

func _init() -> void:
	call_deferred("run")

func run() -> void:
	# Preserve the user's preferences even when this regression runs locally.
	var existed := FileAccess.file_exists(Preferences.SETTINGS_FILE_PATH)
	var saved := FileAccess.get_file_as_bytes(Preferences.SETTINGS_FILE_PATH) if existed else PackedByteArray()
	var preferences = Preferences.new()
	test.check(preferences.show_fps, "FPS defaults on")
	var topbar := HBoxContainer.new()
	var viewport_area := Control.new()
	get_root().add_child(topbar)
	get_root().add_child(viewport_area)
	var overlay: Label = Overlay.install(topbar, viewport_area, preferences)
	test.check(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "FPS never intercepts mouse input")
	var timer: Timer = overlay.get_child(0) as Timer
	test.check(timer.wait_time == 0.25 and not timer.is_stopped(), "FPS samples at four Hz without a process callback")
	overlay.text = "sample pending"
	await create_timer(0.3).timeout
	test.check(overlay.text.begins_with("FPS "), "Timer updates normal Godot frame statistics")
	var menu: MenuButton = topbar.get_node("ViewMenu")
	menu.get_popup().id_pressed.emit(0)
	var loaded = Preferences.new()
	loaded.load_from_disk()
	test.check(not loaded.show_fps and not overlay.visible, "View toggle persists hidden preference")
	overlay.text = "hidden"
	await create_timer(0.3).timeout
	test.check(overlay.text == "hidden", "Hidden FPS skips UI writes")
	menu.get_popup().id_pressed.emit(0)
	loaded.load_from_disk()
	test.check(loaded.show_fps and overlay.visible, "View toggle restores persisted visible preference")
	if existed:
		var file := FileAccess.open(Preferences.SETTINGS_FILE_PATH, FileAccess.WRITE)
		file.store_buffer(saved)
		file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Preferences.SETTINGS_FILE_PATH))
	topbar.free()
	viewport_area.free()
	await process_frame
	test.finish(self)
