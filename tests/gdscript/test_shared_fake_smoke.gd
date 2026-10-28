extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
const Smoke = preload("res://scripts/runtime/shared_fake_smoke.gd")
const Updates = preload("res://scripts/runtime/visual_settings_update.gd")
var test = TestCase.new()

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var smoke := Smoke.new()
	var settings: Dictionary = VisualSettingsWindow.DEFAULT_SETTINGS.duplicate()
	test.check(not settings.fake_smoke_enabled,"Fake smoke is optional and initially off")
	test.check(Smoke.VOLUME.get_width() == 32 and Smoke.VOLUME.get_height() == 1024 and Smoke.VOLUME.get_data().size() == 32768,"Shared precomputed field has bounded 32 cubed density data")
	for key in Smoke.KEYS:
		test.check(settings[key] == Smoke.DEFAULTS[key],"UI and application smoke defaults agree: "+key)
		test.check(not Updates.structural({key:settings[key]}) and not Updates.refresh_shaft_optics({key:settings[key]}),"Smoke setting does not retire or rebind optical resources: "+key)
	smoke.apply(settings)
	test.check(smoke._noise == null,"Disabled startup does not allocate a GPU noise texture")
	settings.fake_smoke_enabled = true
	smoke.apply(settings)
	var noise: ImageTexture3D = smoke._noise
	test.check(noise != null and noise.get_width() == 32 and noise.get_depth() == 32,"One volume texture is prepared on first use")
	settings.fake_smoke_density = 0.6
	settings.fake_smoke_enabled = false
	smoke.apply(settings)
	settings.fake_smoke_enabled = true
	smoke.apply(settings)
	test.check(smoke._noise == noise,"Edits and re-enabling reuse one atmosphere texture")
	var window := VisualSettingsWindow.new()
	root.add_child(window)
	await process_frame
	window.configure(settings)
	test.check(window._fake_smoke_panel._controls.fake_smoke_enabled.selected == 1,"Fake Smoke UI displays the real enabled state")
	window._on_reset_pressed()
	test.check(not window._settings.fake_smoke_enabled,"Reset restores smoke off")
	window.free()
	smoke.release()
	test.check(smoke._noise == null,"Application exit releases the shared texture")
	test.finish(self)
