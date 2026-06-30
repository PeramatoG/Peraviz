extends Window

class_name DmxMonitorWindow

const CHANNEL_COUNT: int = 512
const CHANNEL_REFRESH_INTERVAL_MSEC: int = 250

var _receiver = null
var _selected_universe: int = -1
var _universe_buttons: Dictionary = {}
var _channel_panels: Array[PanelContainer] = []
var _channel_labels: Array[Label] = []
var _channel_values: PackedInt32Array = PackedInt32Array()
var _show_only_active_channels: bool = false
var _realtime_metrics: Dictionary = {}
var _channel_styles: Array[StyleBoxFlat] = []
var _last_channel_refresh_msec: int = 0
var _metrics_text: TextEdit
var _metrics_status_label: Label
var _log_metrics_toggle: CheckBox
var _metrics_log_file: FileAccess = null
var _metrics_log_path: String = ""

var _state_label: Label
var _universes_flow: FlowContainer

func _init() -> void:
	title = "Technical Monitor"
	size = Vector2i(1040, 680)
	unresizable = false

func _ready() -> void:
	close_requested.connect(_on_close_requested)
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 12
	root.offset_top = 12
	root.offset_right = -12
	root.offset_bottom = -12
	add_child(root)

	_state_label = Label.new()
	_state_label.text = "DMX monitor inactive"
	root.add_child(_state_label)

	var filters_row: HBoxContainer = HBoxContainer.new()
	filters_row.add_theme_constant_override("separation", 8)
	root.add_child(filters_row)

	var metrics_panel: VBoxContainer = VBoxContainer.new()
	metrics_panel.add_theme_constant_override("separation", 4)
	root.add_child(metrics_panel)
	var metrics_title: Label = Label.new()
	metrics_title.text = "Realtime DMX Metrics"
	metrics_panel.add_child(metrics_title)
	_metrics_text = TextEdit.new()
	_metrics_text.custom_minimum_size = Vector2(0, 112)
	_metrics_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_metrics_text.editable = false
	metrics_panel.add_child(_metrics_text)
	var metrics_actions: HBoxContainer = HBoxContainer.new()
	metrics_actions.add_theme_constant_override("separation", 8)
	metrics_panel.add_child(metrics_actions)
	var copy_metrics_button: Button = Button.new()
	copy_metrics_button.text = "Copy metrics JSON"
	copy_metrics_button.tooltip_text = "Copies receiver, worker, apply, and attribute metrics as JSON for sharing."
	copy_metrics_button.pressed.connect(_on_copy_metrics_pressed)
	metrics_actions.add_child(copy_metrics_button)
	var reset_metrics_button: Button = Button.new()
	reset_metrics_button.text = "Reset max metrics"
	reset_metrics_button.tooltip_text = "Resets the local Technical Monitor max/average display counters."
	reset_metrics_button.pressed.connect(_on_reset_metrics_pressed)
	metrics_actions.add_child(reset_metrics_button)
	_log_metrics_toggle = CheckBox.new()
	_log_metrics_toggle.text = "Log JSONL"
	_log_metrics_toggle.tooltip_text = "Writes one compact metrics JSON line per monitor refresh to user://dmx_metrics_*.jsonl."
	_log_metrics_toggle.toggled.connect(_on_log_metrics_toggled)
	metrics_actions.add_child(_log_metrics_toggle)
	_metrics_status_label = Label.new()
	metrics_actions.add_child(_metrics_status_label)

	var active_channels_toggle: CheckBox = CheckBox.new()
	active_channels_toggle.text = "Show only active channels"
	active_channels_toggle.toggled.connect(_on_active_channels_toggled)
	filters_row.add_child(active_channels_toggle)

	var universe_scroll: ScrollContainer = ScrollContainer.new()
	universe_scroll.custom_minimum_size = Vector2(0, 100)
	universe_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	universe_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(universe_scroll)

	_universes_flow = FlowContainer.new()
	_universes_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_universes_flow.add_theme_constant_override("h_separation", 6)
	_universes_flow.add_theme_constant_override("v_separation", 6)
	universe_scroll.add_child(_universes_flow)

	var channels_scroll: ScrollContainer = ScrollContainer.new()
	channels_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	channels_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(channels_scroll)

	var channels_grid: GridContainer = GridContainer.new()
	channels_grid.columns = 16
	channels_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	channels_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	channels_grid.add_theme_constant_override("h_separation", 4)
	channels_grid.add_theme_constant_override("v_separation", 4)
	channels_scroll.add_child(channels_grid)

	for channel_idx in range(CHANNEL_COUNT):
		var panel: PanelContainer = PanelContainer.new()
		panel.custom_minimum_size = Vector2(58, 24)
		channels_grid.add_child(panel)

		var label: Label = Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text = "%03d" % (channel_idx + 1)
		panel.add_child(label)

		_channel_panels.append(panel)
		_channel_labels.append(label)
		_channel_values.append(-1)
		var style := StyleBoxFlat.new()
		style.border_color = Color(0.05, 0.05, 0.05)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		_channel_styles.append(style)

		_update_channel_cell(channel_idx, 0, true)

func configure(receiver) -> void:
	_receiver = receiver

func set_realtime_metrics(metrics: Dictionary) -> void:
	_realtime_metrics = metrics
	_update_metrics_panel()

func refresh(running: bool) -> void:
	if _receiver == null:
		_state_label.text = "DMX unavailable"
		return

	if not running:
		_state_label.text = "DMX OFF"
		_update_universe_buttons([])
		for channel_idx in range(CHANNEL_COUNT):
			_update_channel_cell(channel_idx, 0, true)
		return

	var active_universes: PackedInt32Array = _receiver.get_active_universes(2000)
	_update_universe_buttons(active_universes)

	if _selected_universe < 0 and active_universes.size() > 0:
		_selected_universe = int(active_universes[0])

	var selected_text: String = "none"
	if _selected_universe >= 0:
		selected_text = str(_selected_universe)
	_state_label.text = "Active universes: %d | Selected universe: %s" % [active_universes.size(), selected_text]

	var now_msec: int = Time.get_ticks_msec()
	if now_msec - _last_channel_refresh_msec < CHANNEL_REFRESH_INTERVAL_MSEC:
		return
	_last_channel_refresh_msec = now_msec
	var channel_refresh_start: int = Time.get_ticks_usec()
	var data: PackedByteArray = PackedByteArray()
	if _selected_universe >= 0:
		data = _receiver.get_universe_data(_selected_universe)

	for channel_idx in range(CHANNEL_COUNT):
		var channel_value: int = 0
		if channel_idx < data.size():
			channel_value = int(data[channel_idx])
		_update_channel_cell(channel_idx, channel_value)
	_realtime_metrics["ui_monitor_refresh_usec"] = max(Time.get_ticks_usec() - channel_refresh_start, 0)
	_update_metrics_panel()

func _update_metrics_panel() -> void:
	if _metrics_text == null:
		return
	var metrics_json: Dictionary = _build_metrics_json()
	_metrics_text.text = JSON.stringify(metrics_json, "  ")
	if _metrics_log_file != null:
		_metrics_log_file.store_line(JSON.stringify(metrics_json))

func _build_metrics_json() -> Dictionary:
	var receiver: Dictionary = _realtime_metrics.get("receiver", {}) if _realtime_metrics.has("receiver") else {}
	return {
		"branch": "codex/refactor-peraviz-dmx-visual-apply-architecture",
		"timestamp_ms": Time.get_ticks_msec(),
		"receiver": {
			"last_packet_ms_ago": int(receiver.get("last_packet_ms_ago", receiver.get("native_receiver_last_packet_ms", -1))),
			"native_receiver_last_packet_ms": int(receiver.get("native_receiver_last_packet_ms", -1)),
			"main_thread_status_refresh_gap_ms": int(receiver.get("main_thread_status_refresh_gap_ms", 0)),
			"packets_per_sec": int(receiver.get("packets_per_sec", 0)),
			"overload_dropped": int(receiver.get("overload_dropped", 0)),
			"active_universes": _to_int_array(receiver.get("active_universes", PackedInt32Array())),
		},
		"worker": {
			"decode_usec": int(_realtime_metrics.get("decode_usec", 0)),
			"native_visual_filter_usec": int(_realtime_metrics.get("native_visual_filter_usec", 0)),
			"dmx_worker_loop_gap_ms": int(_realtime_metrics.get("dmx_worker_loop_gap_ms", 0)),
		},
		"apply": {
			"apply_batch_usec": int(_realtime_metrics.get("apply_batch_usec", 0)),
			"visual_apply_block_ms": float(_realtime_metrics.get("apply_batch_usec", 0)) / 1000.0,
			"fixtures_in_batch": int(_realtime_metrics.get("fixtures_in_batch", 0)),
			"fixtures_applied": int(_realtime_metrics.get("fixtures_applied", 0)),
			"batch_rows_received": int(_realtime_metrics.get("batch_rows_received", 0)),
			"batch_rows_applied": int(_realtime_metrics.get("batch_rows_applied", 0)),
			"legacy_controls_generated": int(_realtime_metrics.get("legacy_controls_generated", 0)),
			"legacy_controls_applied": int(_realtime_metrics.get("legacy_controls_applied", 0)),
			"render_server_calls": int(_realtime_metrics.get("render_server_calls", 0)),
			"render_server_calls_attempted": int(_realtime_metrics.get("render_server_calls_attempted", 0)),
			"render_server_calls_applied": int(_realtime_metrics.get("render_server_calls_applied", 0)),
			"node_property_writes": int(_realtime_metrics.get("node_property_writes", 0)),
			"node_property_writes_attempted": int(_realtime_metrics.get("node_property_writes_attempted", 0)),
			"node_property_writes_applied": int(_realtime_metrics.get("node_property_writes_applied", 0)),
			"material_param_writes_attempted": int(_realtime_metrics.get("material_param_writes_attempted", 0)),
			"material_param_writes_applied": int(_realtime_metrics.get("material_param_writes_applied", 0)),
			"shader_param_writes_attempted": int(_realtime_metrics.get("shader_param_writes_attempted", 0)),
			"shader_param_writes_applied": int(_realtime_metrics.get("shader_param_writes_applied", 0)),
			"skipped_unchanged_values": int(_realtime_metrics.get("skipped_unchanged_values", 0)),
			"coalesced_batches": int(_realtime_metrics.get("coalesced_batches", 0)),
			"coalesced_rows": int(_realtime_metrics.get("coalesced_rows", 0)),
			"latest_state_replacements": int(_realtime_metrics.get("latest_state_replacements", 0)),
			"no_op_rows_skipped": int(_realtime_metrics.get("no_op_rows_skipped", 0)),
			"visual_batch_rows_by_mask": _realtime_metrics.get("visual_batch_rows_by_mask", {}),
			"ui_monitor_refresh_usec": int(_realtime_metrics.get("ui_monitor_refresh_usec", 0)),
			"frame_budget_exceeded": bool(_realtime_metrics.get("frame_budget_exceeded", false)),
			"fixtures_initialized_from_first_dmx": int(_realtime_metrics.get("fixtures_initialized_from_first_dmx", 0)),
			"missing_light_handles": int(_realtime_metrics.get("missing_light_handles", 0)),
			"missing_material_handles": int(_realtime_metrics.get("missing_material_handles", 0)),
			"missing_beam_handles": int(_realtime_metrics.get("missing_beam_handles", 0)),
			"rebuilt_visual_handles": int(_realtime_metrics.get("rebuilt_visual_handles", 0)),
		},
		"attributes": {
			"dimmer": int(_realtime_metrics.get("attributes_applied_dimmer", 0)),
			"pan_tilt": int(_realtime_metrics.get("attributes_applied_pan_tilt", 0)),
			"color": int(_realtime_metrics.get("attributes_applied_color", 0)),
			"zoom": int(_realtime_metrics.get("attributes_applied_zoom", 0)),
			"gobo": int(_realtime_metrics.get("attributes_applied_gobo", 0)),
			"prism": int(_realtime_metrics.get("attributes_applied_prism", 0)),
			"strobe": int(_realtime_metrics.get("attributes_applied_strobe", 0)),
		},
	}

func _to_int_array(value: Variant) -> Array:
	var out: Array = []
	if value is PackedInt32Array:
		for item in value:
			out.append(int(item))
	elif value is Array:
		for item in value:
			out.append(int(item))
	return out

func _update_universe_buttons(active_universes: PackedInt32Array) -> void:
	var active_map: Dictionary = {}
	for universe in active_universes:
		active_map[int(universe)] = true

	for universe_id in _universe_buttons.keys():
		var button: Button = _universe_buttons[universe_id]
		var is_active: bool = active_map.has(universe_id)
		button.modulate = Color(0.35, 1.0, 0.35) if is_active else Color(0.35, 0.35, 0.35)
		button.button_pressed = (int(universe_id) == _selected_universe)

	for universe in active_universes:
		var uni_id: int = int(universe)
		if _universe_buttons.has(uni_id):
			continue
		var button: Button = Button.new()
		button.toggle_mode = true
		button.text = "U%d" % uni_id
		button.custom_minimum_size = Vector2(74, 34)
		button.modulate = Color(0.35, 1.0, 0.35)
		button.pressed.connect(func() -> void:
			_selected_universe = uni_id
			for btn_uni in _universe_buttons.keys():
				var btn: Button = _universe_buttons[btn_uni]
				btn.button_pressed = (int(btn_uni) == _selected_universe)
		)
		_universe_buttons[uni_id] = button
		_universes_flow.add_child(button)

func _update_channel_cell(channel_idx: int, channel_value: int, force: bool = false) -> void:
	if not force and int(_channel_values[channel_idx]) == channel_value:
		return
	var normalized: float = clamp(float(channel_value) / 255.0, 0.0, 1.0)
	var style: StyleBoxFlat = _channel_styles[channel_idx]
	style.bg_color = Color(0.08, 0.16 + (0.84 * normalized), 0.08)
	_channel_panels[channel_idx].add_theme_stylebox_override("panel", style)
	_channel_labels[channel_idx].text = "%03d:%03d" % [channel_idx + 1, channel_value]
	_channel_values[channel_idx] = channel_value
	_channel_panels[channel_idx].visible = (channel_value > 0) if _show_only_active_channels else true


func _on_copy_metrics_pressed() -> void:
	DisplayServer.clipboard_set(JSON.stringify(_build_metrics_json(), "  "))
	_metrics_status_label.text = "Metrics copied"

func _on_reset_metrics_pressed() -> void:
	_realtime_metrics["max_apply_spike_usec"] = 0
	_realtime_metrics["moving_average_apply_usec"] = 0
	_update_metrics_panel()
	_metrics_status_label.text = "Local max metrics reset"

func _on_log_metrics_toggled(enabled: bool) -> void:
	if not enabled:
		if _metrics_log_file != null:
			_metrics_log_file.close()
		_metrics_log_file = null
		_metrics_status_label.text = "Metrics logging stopped"
		return
	var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "").replace("-", "").replace(" ", "_")
	_metrics_log_path = "user://dmx_metrics_%s.jsonl" % stamp
	_metrics_log_file = FileAccess.open(_metrics_log_path, FileAccess.WRITE)
	_metrics_status_label.text = "Logging to %s" % _metrics_log_path if _metrics_log_file != null else "Metric log open failed"

func _on_close_requested() -> void:
	hide()

func _on_active_channels_toggled(enabled: bool) -> void:
	_show_only_active_channels = enabled
	for channel_idx in range(CHANNEL_COUNT):
		var channel_value: int = int(_channel_values[channel_idx])
		_channel_panels[channel_idx].visible = (channel_value > 0) if _show_only_active_channels else true
