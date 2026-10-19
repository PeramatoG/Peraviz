extends Label

# One small viewport label, sampled by a timer instead of a per-frame callback.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	text = "FPS 0"
	add_theme_font_size_override("font_size", 12)
	add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 0.85))
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.timeout.connect(_sample)
	add_child(timer)
	timer.start()

func _sample() -> void:
	if visible:
		text = "FPS %d" % Engine.get_frames_per_second()

# View preference belongs to the UI, independently of project and trace settings.
static func install(topbar: Control, viewport_area: Control, preferences: UserPreferences) -> Label:
	var overlay = load("res://scripts/ui/fps_overlay.gd").new()
	overlay.name = "FpsOverlay"
	viewport_area.add_child(overlay)
	overlay.position = Vector2(12.0, 8.0)
	overlay.visible = preferences.show_fps
	var view_menu := MenuButton.new()
	view_menu.name = "ViewMenu"
	view_menu.text = "View"
	topbar.add_child(view_menu)
	var popup := view_menu.get_popup()
	popup.add_check_item("Show FPS", 0)
	popup.set_item_checked(0, preferences.show_fps)
	popup.id_pressed.connect(func(_id: int) -> void:
		preferences.show_fps = not preferences.show_fps
		popup.set_item_checked(0, preferences.show_fps)
		overlay.visible = preferences.show_fps
		preferences.save_to_disk()
	)
	return overlay
