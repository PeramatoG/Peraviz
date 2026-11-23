extends RefCounted
class_name StatusPresenter

const Palette = preload("res://scripts/ui/ui_palette.gd")

enum PresenterState {
	IDLE,
	LOADING,
	LOADED,
	WARNING,
	ERROR,
}

const TOAST_DURATION_SEC: float = 2.6

var _status_label: Label
var _topbar_row: HBoxContainer
var _badge_row: HBoxContainer
var _badge_labels: Dictionary = {}
var _badge_values: Dictionary = {}
var _toast_label: Label
var _toast_timer: Timer
var _last_dmx_running: bool = false
var _last_dmx_receiving_signal: bool = false
var _has_dmx_state: bool = false

func configure(owner: Node,
		status_label: Label,
		toast_label: Label,
		topbar_row: HBoxContainer,
		load_button: Button,
		show_advanced_controls_toggle: CheckButton) -> void:
	_status_label = status_label
	_toast_label = toast_label
	_topbar_row = topbar_row
	_ensure_badges(load_button, show_advanced_controls_toggle)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(_on_toast_timeout)
	owner.add_child(_toast_timer)
	set_scene_state_idle()
	set_dmx_badge(false, false)
	set_mvr_xchange_badge(false, 0)
	set_selected_fixture_badge("")
	set_render_mode_badge("Volumetric")

func set_scene_state_idle() -> void:
	_set_status(PresenterState.IDLE, "Idle · Load MVR/PVZ")
	_set_badge("MVR", "Idle")

func set_scene_state_loading(path: String) -> void:
	_set_status(PresenterState.LOADING, "Loading · %s" % path.get_file())
	_set_badge("MVR", "Loading")

func set_scene_state_loaded(node_count: int) -> void:
	_set_status(PresenterState.LOADED, "Loaded · %d nodes" % node_count)
	_set_badge("MVR", "Loaded")

func set_scene_state_warning_unbound(unbound_count: int) -> void:
	_set_status(PresenterState.WARNING, "Warning · %d fixtures unbound" % unbound_count)
	_set_badge("MVR", "Warning")

func set_scene_state_load_error(message: String) -> void:
	_set_status(PresenterState.ERROR, "Load error")
	show_toast("Load failed: %s" % message, true)
	_set_badge("MVR", "Error")

func set_dmx_badge(is_running: bool, receiving_signal: bool) -> void:
	if _has_dmx_state and is_running == _last_dmx_running and receiving_signal == _last_dmx_receiving_signal:
		return
	_last_dmx_running = is_running
	_last_dmx_receiving_signal = receiving_signal
	_has_dmx_state = true
	if _badge_labels.has("DMX"):
		_badge_labels["DMX"].modulate = Palette.SUCCESS if is_running and receiving_signal else (Palette.AMBER if is_running else Palette.MUTED)
	if not is_running:
		_set_badge("DMX", "OFF")
		return
	_set_badge("DMX", "Receiving" if receiving_signal else "Listening")

func set_mvr_xchange_badge(is_running: bool, station_count: int, state: String = "") -> void:
	match state:
		"joined":
			_set_badge("MVR-xchange", "Joined")
			return
		"revision_available":
			_set_badge("MVR-xchange", "New revision")
			return
		"requesting":
			_set_badge("MVR-xchange", "Receiving")
			return
		"received":
			_set_badge("MVR-xchange", "Loaded")
			return
		"error":
			_set_badge("MVR-xchange", "Error")
			return
	if not is_running:
		_set_badge("MVR-xchange", "OFF")
	elif station_count <= 0:
		_set_badge("MVR-xchange", "Discovering")
	elif station_count == 1:
		_set_badge("MVR-xchange", "1 station")
	else:
		_set_badge("MVR-xchange", "%d stations" % station_count)

func set_selected_fixture_badge(fixture_uuid: String) -> void:
	_set_badge("Selected Fixture", "None" if fixture_uuid.is_empty() else "Selected")

func set_render_mode_badge(render_mode_label: String) -> void:
	_set_badge("Render Mode", render_mode_label)

func show_toast(message: String, is_error: bool = false) -> void:
	if _toast_label == null:
		return
	_toast_label.modulate = Palette.ERROR if is_error else Palette.AMBER
	_toast_label.text = message
	_toast_label.tooltip_text = message
	_toast_label.visible = true
	if _toast_timer != null:
		_toast_timer.start(TOAST_DURATION_SEC)

func _set_status(state: int, text: String) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	match state:
		PresenterState.IDLE:
			_status_label.modulate = Palette.TEXT
		PresenterState.LOADING:
			_status_label.modulate = Palette.AMBER
		PresenterState.LOADED:
			_status_label.modulate = Palette.TEXT
		PresenterState.WARNING:
			_status_label.modulate = Palette.AMBER
		PresenterState.ERROR:
			_status_label.modulate = Palette.ERROR

func _ensure_badges(load_button: Button, show_advanced_controls_toggle: CheckButton) -> void:
	if _topbar_row == null:
		return
	_badge_row = HBoxContainer.new()
	_badge_row.name = "StatusBadges"
	_badge_row.alignment = BoxContainer.ALIGNMENT_END
	_badge_row.add_theme_constant_override("separation", 6)

	var top_spacer: Control = _topbar_row.get_node_or_null("TopSpacer") as Control
	if top_spacer != null:
		_topbar_row.move_child(top_spacer, _topbar_row.get_child_count() - 1)
	_topbar_row.add_child(_badge_row)

	_create_badge("DMX")

	if load_button != null:
		load_button.tooltip_text = "Load an MVR or Peraviz project file"
	if show_advanced_controls_toggle != null:
		show_advanced_controls_toggle.tooltip_text = "Toggle advanced controls"

func _create_badge(name: String) -> void:
	if _badge_row == null:
		return
	var badge := Label.new()
	badge.name = "%sBadge" % name.replace(" ", "")
	badge.text = "%s: --" % name
	badge.clip_text = true
	badge.custom_minimum_size = Vector2(112, 0)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.add_theme_font_size_override("font_size", 11)
	badge.modulate = Palette.MUTED
	_badge_row.add_child(badge)
	_badge_labels[name] = badge

func _set_badge(name: String, value: String) -> void:
	if not _badge_labels.has(name):
		_badge_values[name] = value
		if _status_label != null: _status_label.tooltip_text = JSON.stringify(_badge_values, "  ")
		return
	if str(_badge_values.get(name, "")) == value:
		return
	_badge_values[name] = value
	var badge: Label = _badge_labels[name]
	badge.text = "%s: %s" % [name, value]

func _on_toast_timeout() -> void:
	if _toast_label != null:
		_toast_label.visible = false
