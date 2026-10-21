extends CanvasLayer

# Modal feedback prevents renderer/settings changes against partially registered targets.
func _ready() -> void:
	layer = 100
	var shield := ColorRect.new()
	shield.color = Color(0.025, 0.03, 0.04, 0.88)
	shield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shield.mouse_filter = Control.MOUSE_FILTER_STOP
	shield.focus_mode = Control.FOCUS_ALL
	add_child(shield)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield.add_child(center)
	var content := VBoxContainer.new()
	content.custom_minimum_size.x = 240
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(content)
	var label := Label.new()
	label.text = "Loading scene…"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(label)
	var progress := ProgressBar.new()
	progress.indeterminate = true
	progress.show_percentage = false
	progress.custom_minimum_size.y = 14
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(progress)
	shield.grab_focus()

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
