extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# The global permission is consumed at engine startup, before splash code runs.
	for setting in ["display/window/per_pixel_transparency/allowed", "display/window/size/transparent", "rendering/viewport/transparent_background"]:
		test.check(ProjectSettings.get_setting(setting, true) == false, "Opaque startup setting: " + setting)
	test.check(ProjectSettings.get_setting("application/boot_splash/bg_color").a == 1.0, "Opaque engine boot background")
	test.check(ProjectSettings.get_setting("display/window/size/borderless"), "Compact startup remains borderless")
	test.check(ProjectSettings.get_setting("display/window/size/viewport_width") == 1366 and ProjectSettings.get_setting("display/window/size/viewport_height") == 768, "Viewer reference viewport unchanged")
	var width_key := "display/window/size/window_width_override"
	var height_key := "display/window/size/window_height_override"
	test.check(ProjectSettings.get_setting(width_key) == 1366 and ProjectSettings.get_setting(height_key) == 768, "Editor starts with Viewer-sized reference, not the splash size")
	test.check(ProjectSettings.get_setting(width_key + ".template") == 222 and ProjectSettings.get_setting(height_key + ".template") == 268, "Export templates retain compact startup window")
	var expected_size := Vector2i(222, 268) if OS.has_feature("template") else Vector2i(1366, 768)
	test.check(Vector2i(ProjectSettings.get_setting_with_override(width_key), ProjectSettings.get_setting_with_override(height_key)) == expected_size, "Effective startup dimensions match runtime type")
	test.check(not root.transparent_bg, "Root viewport starts opaque")
	var splash: Control = preload("res://startup_splash.tscn").instantiate()
	var background: Panel = splash.get_node("Background")
	var style: StyleBoxFlat = background.get_theme_stylebox("panel")
	test.check(style.bg_color.a == 1.0 and style.border_color.a == 1.0, "Opaque splash panel and border")
	test.check(style.corner_radius_top_left == 0 and style.corner_radius_top_right == 0 and style.corner_radius_bottom_left == 0 and style.corner_radius_bottom_right == 0, "No artificially transparent exterior corners")
	test.check(background.anchor_right == 1.0 and background.anchor_bottom == 1.0, "Panel covers the splash")
	# Inspect the scene without triggering the Viewer or reading user preferences.
	splash.free()
	var startup = preload("res://scripts/ui/startup_splash.gd")
	var normal: Rect2i = startup._normal_window_rect(Rect2i(1920, 0, 1920, 1040))
	test.check(normal.size == Vector2i(1366, 768) and normal.position == Vector2i(2197, 136), "Normal restore size stays centered on the selected monitor")
	var small: Rect2i = startup._normal_window_rect(Rect2i(-1280, 0, 1280, 720))
	test.check(small.size == Vector2i(1216, 624) and small.position == Vector2i(-1248, 48), "Normal window fits smaller/negative-origin monitors")
	test.check(not startup._is_usable_window_size(Vector2i(222, 268), normal.size), "Reject native window stuck at splash size")
	test.check(startup._is_usable_window_size(normal.size, normal.size), "Accept a usable normal window")
	test.finish(self)
