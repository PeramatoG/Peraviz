extends Control

# Peraviz's small, borderless startup screen. Keep startup UI separate from
# the canonical Viewer scene; future loading messages can update StatusLabel.
const VIEWER_SCENE: String = "res://test.tscn"
const SPLASH_SIZE := Vector2i(222, 268)
const MAIN_WINDOW_SIZE := Vector2i(1366, 768)
const FALLBACK_VERSION: String = "0.1.0"

@onready var _version_label: Label = $VersionLabel
@onready var _status_label: Label = $StatusLabel

var _frames_visible: int = 0
var _launching: bool = false
var _startup_failed: bool = false


# Shows a native-looking startup card before constructing the main Viewer.
func _ready() -> void:
	_version_label.text = "Peraviz %s" % _read_version()
	_status_label.text = "Loading Peraviz..."
	# Never manipulate the editor's own window or the headless display.
	# The regular viewer remains testable by path.
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		set_process(false)
		_open_viewer.call_deferred()
		return
	var window: Window = get_window()
	window.mode = Window.MODE_WINDOWED
	window.size = SPLASH_SIZE
	window.borderless = true
	window.unresizable = true
	window.always_on_top = true
	# Borderless is independent of transparency. Keep the native swapchain opaque
	# from process startup; enabling per-pixel transparency causes sky leakage.
	window.transparent = false
	get_viewport().transparent_bg = false
	var screen: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	if screen.size.x >= SPLASH_SIZE.x and screen.size.y >= SPLASH_SIZE.y:
		window.position = screen.position + (screen.size - SPLASH_SIZE) / 2
	set_process(true)
	var request_error: Error = ResourceLoader.load_threaded_request(VIEWER_SCENE, "PackedScene")
	if request_error != OK:
		_show_error("Unable to prepare Peraviz.", "Scene loading request failed: %d" % request_error)


# Waits until Godot has displayed the splash, then transfers to the Viewer.
func _process(_delta: float) -> void:
	if _launching:
		return
	_frames_visible += 1
	if _frames_visible < 2:
		return
	match ResourceLoader.load_threaded_get_status(VIEWER_SCENE):
		ResourceLoader.THREAD_LOAD_LOADED:
			var packed_scene: PackedScene = ResourceLoader.load_threaded_get(VIEWER_SCENE) as PackedScene
			if packed_scene == null:
				_show_error("Unable to start Peraviz.", "Viewer resource is not a PackedScene.")
				return
			_open_viewer(packed_scene)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_show_error("Unable to start Peraviz.", "Unable to load %s" % VIEWER_SCENE)


# Restores a normal window, mounts the Viewer and maximizes after its initialization.
func _open_viewer(packed_scene: PackedScene = null) -> void:
	if _launching:
		return
	_launching = true
	set_process(false)
	if packed_scene == null:
		packed_scene = load(VIEWER_SCENE) as PackedScene
	if packed_scene == null:
		_show_error("Unable to start Peraviz.", "Viewer scene is unavailable.")
		return
	var viewer: Node = packed_scene.instantiate()
	if viewer == null:
		_show_error("Unable to start Peraviz.", "Viewer scene could not be instantiated.")
		return
	# Hide the card before resizing; no enlarged splash should be drawn.
	hide()
	var native_window := DisplayServer.get_name() != "headless" and not Engine.is_embedded_in_editor()
	var window: Window = get_window()
	var normal_rect := Rect2i()
	if native_window:
		window.mode = Window.MODE_WINDOWED
		window.unresizable = false
		window.borderless = false
		window.always_on_top = false
		window.transparent = false
		get_viewport().transparent_bg = false
		normal_rect = _normal_window_rect(DisplayServer.screen_get_usable_rect(window.current_screen))
		_apply_normal_rect(window, normal_rect)
	get_tree().root.add_child(viewer)
	get_tree().current_scene = viewer
	if native_window:
		# Viewer _ready() builds its layout and applies UI scaling. Let those
		# changes and native resize messages settle before requesting maximize.
		await get_tree().process_frame
		_apply_normal_rect(window, normal_rect)
		await get_tree().process_frame
		window.mode = Window.MODE_MAXIMIZED
		await get_tree().process_frame
		await get_tree().process_frame
		# Window.mode alone is not proof that the OS actually enlarged it.
		# If maximization failed, leave a usable decorated window instead.
		if not _is_usable_window_size(DisplayServer.window_get_size(), normal_rect.size):
			window.mode = Window.MODE_WINDOWED
			await get_tree().process_frame
			_apply_normal_rect(window, normal_rect)
			await get_tree().process_frame
			if not _is_usable_window_size(DisplayServer.window_get_size(), normal_rect.size):
				push_warning("[PeravizStartup] Native window resize did not reach the requested size.")
		print("[PeravizStartup] Main window mode=%s size=%s" % [window.mode, DisplayServer.window_get_size()])
	print("[PeravizStartup] Viewer ready; renderer=%s driver=%s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()])
	queue_free()


# Fit the normal restore size on the splash's monitor, with space for decorations.
static func _normal_window_rect(work_area: Rect2i) -> Rect2i:
	if work_area.size.x <= 0 or work_area.size.y <= 0:
		return Rect2i(Vector2i.ZERO, MAIN_WINDOW_SIZE)
	var available := Vector2i(maxi(1, work_area.size.x - 64), maxi(1, work_area.size.y - 96))
	var target := MAIN_WINDOW_SIZE.min(available)
	return Rect2i(work_area.position + (work_area.size - target) / 2, target)


static func _apply_normal_rect(window: Window, normal_rect: Rect2i) -> void:
	window.size = normal_rect.size
	window.position = normal_rect.position


static func _is_usable_window_size(actual: Vector2i, target: Vector2i) -> bool:
	# Allow small native/DPI rounding differences, but not the compact splash.
	return actual.x >= target.x - 16 and actual.y >= target.y - 16


# Reads the same VERSION file as the native build and Windows installer.
func _read_version() -> String:
	if FileAccess.file_exists("res://VERSION"):
		var value: String = FileAccess.get_file_as_string("res://VERSION").strip_edges()
		if not value.is_empty():
			return value
	return FALLBACK_VERSION


# Leaves the startup window visible with an actionable failure diagnostic.
func _show_error(message: String, detail: String) -> void:
	_launching = true
	set_process(false)
	_startup_failed = true
	_status_label.text = message + "\nEsc to exit"
	push_error("[PeravizStartup] " + detail)


# A borderless startup failure must still offer a way to close the application.
func _unhandled_key_input(event: InputEvent) -> void:
	if _startup_failed and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		get_tree().quit(1)
