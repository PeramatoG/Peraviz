extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()


# Checks the Perastage-style startup layout without opening native windows.
func _initialize() -> void:
	call_deferred("_run")


# Guards the startup entry point, brand image, dimensions and status placeholders.
func _run() -> void:
	test.check(
		ProjectSettings.get_setting("application/run/main_scene") == "res://startup_splash.tscn",
		"The standalone application opens the splash scene before the existing Viewer"
	)
	test.check(ProjectSettings.get_setting("display/window/size/borderless"), "The splash starts without a system title bar")
	test.check(
		ProjectSettings.get_setting("display/window/size/viewport_width") == 1366,
		"The normal Viewer reference viewport is retained"
	)
	var arguments = preload("res://scripts/runtime/application_arguments.gd")
	var no_request: Dictionary = arguments.startup_project_request(PackedStringArray(["--peraviz-perf-trace"]))
	test.check(not no_request.requested, "Normal startup retains remembered-project behavior")
	var project_path: String = "C:/Shows/Proyecto de prueba.PVZ"
	var requested: Dictionary = arguments.startup_project_request(PackedStringArray(["--open-project", project_path]))
	test.check(requested.requested and requested.path == project_path, "Explicit PVZ path preserves spaces and accepts uppercase extension")
	var missing: Dictionary = arguments.startup_project_request(PackedStringArray(["--open-project"]))
	test.check(missing.requested and missing.path.is_empty(), "Missing path must not fall back to last project")
	var wrong: Dictionary = arguments.startup_project_request(PackedStringArray(["--open-project", "scene.mvr"]))
	test.check(wrong.requested and wrong.path.is_empty(), "Project association does not claim MVR")
	var resource: PackedScene = load("res://startup_splash.tscn") as PackedScene
	test.check(resource != null, "The startup splash scene is loadable")
	if resource == null:
		test.finish(self)
		return
	var splash: Node = resource.instantiate()
	test.check(splash != null, "The startup scene instantiates")
	if splash != null:
		var version: Label = splash.get_node_or_null("VersionLabel") as Label
		var status: Label = splash.get_node_or_null("StatusLabel") as Label
		var brand: TextureRect = splash.get_node_or_null("BrandImage") as TextureRect
		test.check(version != null and status != null, "The splash has separate version and status text")
		test.check(brand != null and brand.texture != null, "The splash includes the original Peraviz brand artwork")
		if brand != null:
			test.check(
				is_equal_approx(brand.offset_right - brand.offset_left, 180.0)
				and is_equal_approx(brand.offset_bottom - brand.offset_top, 180.0),
				"The logo preserves Perastage's 180 px presentation size"
			)
		splash.free()
	test.finish(self)
