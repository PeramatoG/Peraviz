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
var _startup_started: int = 0
var _draw_count: int = 0
const DRAW_WAIT_MS: int = 1500


# Shows a native-looking startup card before constructing the main Viewer.
func _ready() -> void:
	_startup_started = Time.get_ticks_msec()
	_version_label.text = "Peraviz %s" % _read_version()
	_status_label.text = "Loading Peraviz..."
	# Never manipulate the editor's own window or the headless display.
	# The regular viewer remains testable by path.
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor():
		set_process(false)
		_open_viewer.call_deferred()
		return
	var window: Window = get_window()
	print("[PeravizStartup] Initial window size=%s mode=%s effective override=%sx%s" % [
		DisplayServer.window_get_size(), window.mode,
		ProjectSettings.get_setting_with_override("display/window/size/window_width_override"),
		ProjectSettings.get_setting_with_override("display/window/size/window_height_override")])
	RenderingServer.frame_post_draw.connect(_on_frame_drawn)
	z_index = 4095
	mouse_filter = Control.MOUSE_FILTER_STOP
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
	if _draw_count == 0 and Time.get_ticks_msec() - _startup_started < DRAW_WAIT_MS:
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


func _on_frame_drawn() -> void:
	_draw_count += 1

# Bounded wait, including when the window is minimized or occluded.
func _wait_for_draw() -> bool:
	var previous: int = _draw_count
	var deadline: int = Time.get_ticks_msec() + DRAW_WAIT_MS
	while _draw_count == previous and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return _draw_count != previous

func _set_stage(message: String) -> void:
	_status_label.text = message

# Keep the compact card visible while the Viewer initializes.
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
	var native_window := DisplayServer.get_name() != "headless" and not Engine.is_embedded_in_editor()
	if native_window:
		print("[PeravizStartup] Resources ready: %d ms" % (Time.get_ticks_msec() - _startup_started))
		_set_stage("Creating viewer...")
		await _wait_for_draw()
	var started: int = Time.get_ticks_msec()
	var viewer: Node = packed_scene.instantiate()
	if viewer == null:
		_show_error("Unable to start Peraviz.", "Viewer scene could not be instantiated.")
		return
	print("[PeravizStartup] Viewer instantiate: %d ms" % (Time.get_ticks_msec() - started))
	var original_process_mode := viewer.process_mode
	if native_window:
		viewer.set("startup_managed", true)
		viewer.process_mode = Node.PROCESS_MODE_DISABLED
	var window: Window = get_window()
	var normal_rect := Rect2i()
	started = Time.get_ticks_msec()
	get_tree().root.add_child(viewer)
	get_tree().current_scene = viewer
	print("[PeravizStartup] Viewer mount: %d ms" % (Time.get_ticks_msec() - started))
	if native_window:
		# Keep the card above its new sibling for drawing and GUI order.
		get_tree().root.move_child(self, -1)
		_set_stage("Preparing viewer...")
		await _wait_for_draw()
		await viewer.call("initialize_for_startup", Callable(self, "_set_stage"))
		if not bool(viewer.get("startup_initialized")):
			viewer.queue_free()
			get_tree().current_scene = self
			_show_error("Unable to start Peraviz.", "Viewer initialization did not complete.")
			return
		_set_stage("Starting viewer...")
		started = Time.get_ticks_msec()
		var compact_drawn: bool = await _wait_for_draw()
		if not compact_drawn:
			push_warning("[PeravizStartup] No draw observed before handoff.")
		print("[PeravizStartup] Compact frame wait: %d ms" % (Time.get_ticks_msec() - started))
		# Retire the card only now; preserve previous opacity and sizing fixes.
		hide()
		viewer.call("apply_startup_ui_scale")
		window.mode = Window.MODE_WINDOWED
		window.unresizable = false
		window.borderless = false
		window.always_on_top = false
		window.transparent = false
		get_viewport().transparent_bg = false
		normal_rect = _normal_window_rect(DisplayServer.screen_get_usable_rect(window.current_screen))
		_apply_normal_rect(window, normal_rect)
		# Let native resize and layout messages settle before maximizing.
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
		started = Time.get_ticks_msec()
		var normal_drawn: bool = await _wait_for_draw()
		if not normal_drawn:
			push_warning("[PeravizStartup] No normal-window draw observed; releasing startup after bounded wait.")
		print("[PeravizStartup] Normal frame wait: %d ms" % (Time.get_ticks_msec() - started))
		viewer.process_mode = original_process_mode
	else:
		hide()
	print("[PeravizStartup] Viewer ready; renderer=%s driver=%s elapsed_ms=%d" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name(), Time.get_ticks_msec() - _startup_started])
	if native_window:
		viewer.call("release_startup_file")
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
