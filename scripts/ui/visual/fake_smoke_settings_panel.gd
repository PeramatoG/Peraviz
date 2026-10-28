@tool
extends "res://scripts/ui/visual/renderer_settings_panel.gd"

func _build_ui() -> void:
	add_theme_constant_override("separation",10)
	var description := Label.new()
	description.text = "Fake Smoke — Peraviz presentation for Vector Prism shafts. Shared world-space variation; no physical fog, surface or lens changes."
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(description)
	_add_option_row("Fake Smoke", "fake_smoke_enabled", ["Disabled","Enabled"], [false,true])
	_add_slider_row("Density", "fake_smoke_density", 0.0, 2.0, 0.01)
	_add_slider_row("Variation", "fake_smoke_variation", 0.0, 1.0, 0.01)
	_add_slider_row("Spatial scale (m)", "fake_smoke_scale_m", 2.0, 40.0, 0.1)
	_add_slider_row("Animation rise (m/s)", "fake_smoke_animation_speed", 0.0, 0.5, 0.01)
	_add_slider_row("Wind direction (deg)", "fake_smoke_wind_direction_deg", 0.0, 360.0, 1.0)
	_add_slider_row("Wind speed (m/s)", "fake_smoke_wind_speed", 0.0, 2.0, 0.01)

func _is_advanced(_key: String) -> bool:
	return false
