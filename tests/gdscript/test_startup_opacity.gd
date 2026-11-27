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
	test.check(ProjectSettings.get_setting("display/window/size/window_width_override") == 222 and ProjectSettings.get_setting("display/window/size/window_height_override") == 268, "Compact startup window unchanged")
	test.check(not root.transparent_bg, "Root viewport starts opaque")
	var splash: Control = preload("res://startup_splash.tscn").instantiate()
	var background: Panel = splash.get_node("Background")
	var style: StyleBoxFlat = background.get_theme_stylebox("panel")
	test.check(style.bg_color.a == 1.0 and style.border_color.a == 1.0, "Opaque splash panel and border")
	test.check(style.corner_radius_top_left == 0 and style.corner_radius_top_right == 0 and style.corner_radius_bottom_left == 0 and style.corner_radius_bottom_right == 0, "No artificially transparent exterior corners")
	test.check(background.anchor_right == 1.0 and background.anchor_bottom == 1.0, "Panel covers the splash")
	# Inspect the scene without triggering the Viewer or reading user preferences.
	splash.free()
	test.finish(self)
