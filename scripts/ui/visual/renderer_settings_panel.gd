@tool
extends VBoxContainer

class_name RendererSettingsPanel

const BeamPresentationOptionsScript = preload("res://scripts/ui/visual/beam_presentation_options.gd")

signal setting_changed(key: String, value: Variant)

const BASIC_KEYS := {
	"footprint_multiplier": true,
	"beam_multiplier": true,
	"lens_emission_multiplier": true,
	"bloom_multiplier": true,
	"volumetric_fog_density": true,
	"light_volumetric_fog_energy": true,
	"footprint_backend": true,
}

var _controls: Dictionary = {}
var _value_labels: Dictionary = {}
var _advanced_rows: Array[Control] = []

func _ready() -> void:
	if get_child_count() == 0:
		_build_ui()

func _build_ui() -> void:
	add_theme_constant_override("separation", 10)
	_add_slider_row("Footprint / surface intensity", "footprint_multiplier", 0.0, 3.0, 0.01)
	_add_slider_row("Experimental realtime light intensity", "spot_multiplier", 0.0, 3.0, 0.01)
	_add_slider_row("Beam / shaft intensity", "beam_multiplier", 0.0, 100.0, 0.01)
	_add_slider_row("Lens Emission Intensity", "lens_emission_multiplier", 0.0, 10.0, 0.01)
	_add_slider_row("Wash intersection (m; 0 off)", "wash_intersection_width_m", 0.0, 0.5, 0.01)
	_add_slider_row("Beam softness", "beam_softness", 0.0, 1.0, 0.01)
	_add_slider_row("Beam radial falloff", "beam_radial_falloff", 0.25, 4.0, 0.01)
	_add_slider_row("Beam axial decay", "beam_longitudinal_falloff", 0.0, 4.0, 0.01)
	_add_slider_row("Shaft haze density", "haze_density_multiplier", 0.0, 2.0, 0.01)
	_add_slider_row("Footprint softness", "footprint_softness", 0.0, 0.25, 0.005)
	_add_slider_row("Bloom", "bloom_multiplier", 0.0, 3.0, 0.01)
	_add_slider_row("Ambient fog density", "ambient_fog_density", 0.0, 0.05, 0.001)
	_add_slider_row("Volumetric fog density", "volumetric_fog_density", 0.0, 0.01, 0.0001)
	_add_slider_row("Shared haze density", "shared_haze_density", 0.0, 0.05, 0.0005)
	_add_slider_row("Shared haze margin", "shared_haze_margin", 0.0, 30.0, 0.5)
	_add_slider_row("Volumetric fog length", "volumetric_fog_length", 1.0, 200.0, 1.0)
	_add_slider_row("Volumetric fog fade", "volumetric_fog_fade", 0.0, 0.2, 0.005)
	_add_slider_row("Native light fog energy", "light_volumetric_fog_energy", 0.0, 1500.0, 10.0)
	_add_option_row("Beam presentation", "beam_presentation", [BeamPresentationOptionsScript.LABELS[1]])
	_add_option_row("Footprint backend", "footprint_backend", ["Custom (Forward+ opaque surfaces)", "Native (gobo-only diagnostic/reference)"], ["custom", "native"])
	_add_slider_row("Footprint maximum range (m)", "footprint_max_range", 1.0, 200.0, 1.0)
	_add_color_row("Background color", "background_color")

func set_advanced_mode(enabled: bool) -> void:
	for row in _advanced_rows:
		row.visible = enabled

func apply_settings(settings: Dictionary) -> void:
	for key in _controls.keys():
		var control: Control = _controls[key]
		if control == null:
			continue
		if control is HSlider:
			(control as HSlider).value = float(settings.get(key, (control as HSlider).value))
		elif control is OptionButton:
			var option: OptionButton = control as OptionButton
			if key == "beam_presentation":
				var active: int = int(settings.get(key, 1))
				option.clear()
				for id in BeamPresentationOptionsScript.visible_ids(active):
					var label: String = BeamPresentationOptionsScript.LABELS[id] if id >= 0 and id < BeamPresentationOptionsScript.LABELS.size() else "Unknown renderer (%d)" % id
					option.add_item(label, id)
					option.set_item_disabled(option.item_count - 1, id != 1 and OS.get_environment("PERAVIZ_DIAGNOSTIC_RENDERERS") != "1")
				option.select(option.get_item_index(active))
				continue
			var selected: int = ["custom", "native"].find(str(settings.get(key, "custom"))) if key == "footprint_backend" else int(settings.get(key, 0))
			option.select(clampi(selected, 0, maxi(0, option.item_count - 1)))
		elif control is ColorPickerButton:
			(control as ColorPickerButton).color = settings.get(key, Color.BLACK)
	_update_value_labels()

func _is_advanced(key: String) -> bool:
	return not BASIC_KEYS.has(key)

func _add_slider_row(label_text: String, key: String, min_value: float, max_value: float, step: float) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var setting_label: Label = Label.new()
	setting_label.text = label_text
	setting_label.custom_minimum_size = Vector2(180, 0)
	row.add_child(setting_label)

	var slider: HSlider = HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value: float) -> void:
		if key == "volumetric_fog_fade":
			value = max(value, 0.005)
		slider.value = value
		setting_changed.emit(key, value)
		_update_value_labels()
	)
	row.add_child(slider)

	var value_label: Label = Label.new()
	value_label.custom_minimum_size = Vector2(64, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	_controls[key] = slider
	_value_labels[key] = value_label
	if _is_advanced(key):
		_advanced_rows.append(row)

func _add_option_row(label_text: String, key: String, options: Array[String], values: Array = []) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var setting_label: Label = Label.new()
	setting_label.text = label_text
	setting_label.custom_minimum_size = Vector2(180, 0)
	row.add_child(setting_label)

	var option_button: OptionButton = OptionButton.new()
	option_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for option_text in options:
		option_button.add_item(option_text, 1 if key == "beam_presentation" else -1)
	option_button.item_selected.connect(func(index: int) -> void:
		setting_changed.emit(key, option_button.get_item_id(index) if key == "beam_presentation" else (values[index] if not values.is_empty() else index))
	)
	row.add_child(option_button)

	_controls[key] = option_button
	if _is_advanced(key):
		_advanced_rows.append(row)

func _add_color_row(label_text: String, key: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var setting_label: Label = Label.new()
	setting_label.text = label_text
	setting_label.custom_minimum_size = Vector2(180, 0)
	row.add_child(setting_label)

	var picker: ColorPickerButton = ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(180, 30)
	picker.color_changed.connect(func(color: Color) -> void:
		setting_changed.emit(key, color)
	)
	row.add_child(picker)

	_controls[key] = picker
	if _is_advanced(key):
		_advanced_rows.append(row)

func _update_value_labels() -> void:
	for key in _value_labels.keys():
		var value_label: Label = _value_labels[key]
		var value: float = float((_controls[key] as HSlider).value)
		match key:
			"volumetric_fog_density":
				value_label.text = "%.4f" % value
			"volumetric_fog_fade":
				value_label.text = "%.3f" % value
			_:
				value_label.text = "%.2f" % value
