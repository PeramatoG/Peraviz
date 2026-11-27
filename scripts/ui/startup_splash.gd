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


# Shows a native-looking startup card before constructing the main Viewer.
func _ready() -> void:
	_version_label.text = "Peraviz %s" % _read_version()
	_status_label.text = "Loading Peraviz..."
	# Never manipulate the editor's own window or create transparent windows
	# in headless smoke tests. The regular viewer remains testable by path.
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
	window.transparent = true
	get_viewport().transparent_bg = true
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


# Instantiates the existing Viewer before revealing the normal maximized window.
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
	get_tree().root.add_child(viewer)
	get_tree().current_scene = viewer
	if DisplayServer.get_name() != "headless" and not Engine.is_embedded_in_editor():
		var window: Window = get_window()
		get_viewport().transparent_bg = false
		window.transparent = false
		window.borderless = false
		window.always_on_top = false
		window.unresizable = false
		window.mode = Window.MODE_WINDOWED
		window.size = MAIN_WINDOW_SIZE
		window.mode = Window.MODE_MAXIMIZED
	print("[PeravizStartup] Viewer ready")
	queue_free()


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
	_status_label.text = message
	push_error("[PeravizStartup] " + detail)
