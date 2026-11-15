extends RefCounted

const LIMITS := [30, 60, 120, 0]

# Godot consumes engine FPS flags before exposing OS.get_cmdline_args().
static func has_command_line_override() -> bool:
	if ClassDB.class_exists("PeravizApplicationOptions"):
		return bool(ClassDB.class_call_static("PeravizApplicationOptions", "has_fps_override"))
	# A nonzero engine cap must also survive startup without the native extension.
	return Engine.max_fps != int(ProjectSettings.get_setting("application/run/max_fps", 0))

static func install(popup: PopupMenu, preferences: UserPreferences) -> void:
	var overridden := has_command_line_override()
	if not overridden: Engine.max_fps = preferences.fps_limit
	var limits := PopupMenu.new()
	limits.name = "FrameRateLimit"
	popup.add_child(limits)
	for limit in LIMITS:
		limits.add_radio_check_item("Unlimited" if limit == 0 else "%d FPS" % limit, limit)
		limits.set_item_checked(limits.item_count - 1, preferences.fps_limit == limit)
	popup.add_submenu_item("FPS limit", limits.name, 1)
	if overridden:
		popup.set_item_disabled(popup.item_count - 1, true)
		popup.set_item_tooltip(popup.item_count - 1, "FPS controlled by Godot command-line options")
	limits.id_pressed.connect(func(limit: int) -> void:
		if overridden or limit not in LIMITS: return
		preferences.fps_limit = limit
		Engine.max_fps = limit
		for index in range(limits.item_count):
			limits.set_item_checked(index, limits.get_item_id(index) == limit)
		preferences.save_to_disk())
