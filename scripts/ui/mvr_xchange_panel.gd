extends PanelContainer
class_name MvrXchangePanel

signal start_requested(group: String, bind_ip: String)
signal stop_requested
signal preferences_changed(group: String, bind_ip: String)

var _group_input: LineEdit
var _bind_ip_input: LineEdit
var _toggle_button: Button
var _station_list: ItemList
var _status_label: Label
var _running: bool = false

func _ready() -> void:
	_build_ui()

func set_preferences(group: String, bind_ip: String) -> void:
	_ensure_ui()
	_group_input.text = group if not group.is_empty() else "Default"
	_bind_ip_input.text = bind_ip

func set_available(available: bool) -> void:
	_ensure_ui()
	_toggle_button.disabled = not available
	if not available:
		_status_label.text = "Unavailable in this native build"

func set_status(is_running: bool, station_count: int, message: String) -> void:
	_ensure_ui()
	_running = is_running
	_toggle_button.text = "Stop discovery" if _running else "Start discovery"
	_status_label.text = "%s · %d station%s" % [message, station_count, "" if station_count == 1 else "s"]

func set_stations(stations: Array) -> void:
	_ensure_ui()
	_station_list.clear()
	for station in stations:
		var item: Dictionary = station as Dictionary
		var name: String = str(item.get("station_name", "Unnamed"))
		var address: String = str(item.get("address", item.get("host", "")))
		var port: int = int(item.get("port", 0))
		_station_list.add_item("%s  %s:%d" % [name, address, port])

func _build_ui() -> void:
	if _group_input != null:
		return
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)
	var vbox := VBoxContainer.new()
	margin.add_child(vbox)
	var title := Label.new()
	title.text = "MVR-xchange"
	vbox.add_child(title)
	_group_input = LineEdit.new()
	_group_input.placeholder_text = "Group"
	_group_input.text = "Default"
	vbox.add_child(_group_input)
	_bind_ip_input = LineEdit.new()
	_bind_ip_input.placeholder_text = "Bind/interface IP (automatic when empty)"
	vbox.add_child(_bind_ip_input)
	_toggle_button = Button.new()
	_toggle_button.text = "Start discovery"
	vbox.add_child(_toggle_button)
	_toggle_button.pressed.connect(_on_toggle_pressed)
	_station_list = ItemList.new()
	_station_list.custom_minimum_size = Vector2(0, 96)
	vbox.add_child(_station_list)
	var update_button := Button.new()
	update_button.text = "Update"
	update_button.disabled = true
	update_button.tooltip_text = "Available in next phase"
	vbox.add_child(update_button)
	_status_label = Label.new()
	_status_label.text = "OFF"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status_label)

func _ensure_ui() -> void:
	if _group_input == null:
		_build_ui()

func _on_toggle_pressed() -> void:
	preferences_changed.emit(_group_input.text, _bind_ip_input.text)
	if _running:
		stop_requested.emit()
	else:
		start_requested.emit(_group_input.text, _bind_ip_input.text)
