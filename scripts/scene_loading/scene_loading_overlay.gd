extends CanvasLayer

const PHASE_LABELS: Dictionary = {
	"loading_feedback": "Opening scene…",
	"native_mvr": "Reading scene and fixture definitions…",
	"mode_compile": "Preparing fixture controls…",
	"control_groups": "Matching light controls…",
	"render_groups": "Grouping light sources…",
	"node_payload": "Preparing scene data…",
	"node_resources": "Building scene models…",
	"fixture_registration": "Preparing fixture selection…",
	"patch_binding": "Binding DMX controls…",
	"runtime_payload_and_manifest": "Preparing renderer bindings…",
	"godot_targets": "Preparing lights and lenses…",
	"dense_binding": "Binding lighting resources…",
	"control_group_resources": "Preparing shared materials…",
	"aggregate_resources": "Preparing combined beams…",
	"final_runtime_install": "Installing fixture controls…",
	"native_runtime_install": "Installing fixture controls…",
	"fixture_prewarm": "Preparing lighting…",
	"finalize": "Finishing scene setup…",
	"first_render": "Preparing first rendered frames…",
}
var _phase_label: Label

# Modal feedback prevents renderer/settings changes against partially registered targets.
func _ready() -> void:
	layer = 100
	var shield := ColorRect.new()
	shield.color = Color(0.025, 0.03, 0.04, 1.0)
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
	_phase_label = Label.new()
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_phase_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_phase_label)
	set_phase("loading_feedback")
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

func set_phase(value: String) -> void:
	if _phase_label != null:
		_phase_label.text = str(PHASE_LABELS.get(value, "Preparing scene…"))

func set_render_progress(completed: int, total: int) -> void:
	if _phase_label != null:
		_phase_label.text = "%s %d / %d" % [PHASE_LABELS["first_render"], completed, total]
