extends PanelContainer
class_name FixtureInspectionPanel

const EMPTY_VALUE: String = "—"

var _grid: GridContainer
var _empty_label: Label
var _row_labels: Array[Label] = []

func _ready() -> void:
	build_ui()

func build_ui() -> void:
	if _grid != null:
		return
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var layout := VBoxContainer.new()
	margin.add_child(layout)

	var header := Label.new()
	header.text = "Fixture Inspection"
	layout.add_child(header)

	_empty_label = Label.new()
	_empty_label.text = "Load an MVR or PVZ scene to inspect fixtures."
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_empty_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 220)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	layout.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = 8
	scroll.add_child(_grid)
	_add_headers()

func refresh(rows: Array) -> void:
	build_ui()
	_clear_rows()
	_empty_label.visible = rows.is_empty()
	if rows.is_empty():
		return
	for row_value in rows:
		if row_value is not Dictionary:
			continue
		var row: Dictionary = row_value
		_add_row(row)

func _add_headers() -> void:
	for header_text in ["Name", "ID / No.", "Type", "Universe", "Address", "Patch / Binding", "Position", "Rotation"]:
		var label := Label.new()
		label.text = header_text
		label.tooltip_text = header_text
		_grid.add_child(label)

func _add_row(row: Dictionary) -> void:
	_add_cell(_display_value(row.get("fixture_name", "")), _uuid_tooltip(row))
	_add_cell(_display_value(row.get("fixture_id", "")), _uuid_tooltip(row))
	_add_cell(_display_value(row.get("fixture_type", "")), _uuid_tooltip(row))
	_add_cell(_display_value(row.get("universe", "")), _uuid_tooltip(row))
	_add_cell(_display_value(row.get("address", "")), _uuid_tooltip(row))
	_add_cell(_display_value(row.get("binding_status", "")), _binding_tooltip(row))
	_add_cell(_display_value(row.get("position_label", "")), _uuid_tooltip(row))
	_add_cell(_display_value(row.get("rotation_label", "")), _uuid_tooltip(row))

func _add_cell(text: String, tooltip: String) -> void:
	var label := Label.new()
	label.text = text
	label.tooltip_text = tooltip
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.custom_minimum_size = Vector2(90, 0)
	_grid.add_child(label)
	_row_labels.append(label)

func _clear_rows() -> void:
	for label in _row_labels:
		if label != null and is_instance_valid(label):
			_grid.remove_child(label)
			label.queue_free()
	_row_labels.clear()

func _display_value(value: Variant) -> String:
	var text: String = str(value).strip_edges()
	return text if not text.is_empty() and text != "-1" else EMPTY_VALUE

func _uuid_tooltip(row: Dictionary) -> String:
	var fixture_uuid: String = str(row.get("fixture_uuid", "")).strip_edges()
	return "Fixture UUID: %s" % fixture_uuid if not fixture_uuid.is_empty() else ""

func _binding_tooltip(row: Dictionary) -> String:
	var parts := PackedStringArray()
	var detail: String = str(row.get("binding_detail", "")).strip_edges()
	if not detail.is_empty():
		parts.append(detail)
	var uuid_tooltip: String = _uuid_tooltip(row)
	if not uuid_tooltip.is_empty():
		parts.append(uuid_tooltip)
	return "\n".join(parts)
