extends PanelContainer
class_name FixtureInspectionPanel

const EMPTY_VALUE: String = "—"

var _grid: GridContainer
var _empty_label: Label
var _row_labels: Array[Label] = []
var _pending_rows: Array = []
var _revision: int = 0
var _dirty: bool = true
var _building: bool = false

func _ready() -> void:
	visibility_changed.connect(_visibility_updated)
	_visibility_updated()

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

# Hidden inspectors retain data only; they do not allocate hundreds of Labels.
func refresh(rows: Array) -> void:
	_revision += 1
	_pending_rows = rows.duplicate(true)
	_dirty = true
	_building = false
	_clear_rows()
	if is_inside_tree(): _visibility_updated()

func _visibility_updated() -> void:
	if not is_visible_in_tree():
		if _building:
			_revision += 1
			_dirty = true
			_building = false
		return
	if _dirty and not _building: _build_pending_rows()

# Each row has eight cells. Spread visible UI construction across event-loop turns.
func _build_pending_rows() -> void:
	build_ui()
	var revision: int = _revision
	var rows: Array = _pending_rows
	_building = true
	_clear_rows()
	_empty_label.text = "Preparing fixture details…" if not rows.is_empty() else "Load an MVR or PVZ scene to inspect fixtures."
	_empty_label.show()
	var count: int = 0
	for row_value in rows:
		if revision != _revision or not is_visible_in_tree(): return
		if row_value is Dictionary:
			_add_row(row_value)
			count += 1
		if count > 0 and count % 8 == 0: await get_tree().process_frame
	if revision == _revision:
		_dirty = false
		_building = false
		_empty_label.visible = rows.is_empty()

# Loading waits only for visible details; hidden details are prepared on opening.
func finish_visible_refresh(budget: SceneLoadBudget) -> bool:
	while _dirty and is_visible_in_tree():
		if not await budget.checkpoint(true): return false
	return budget.valid()

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
