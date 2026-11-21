extends PanelContainer
class_name FixtureInspectionPanel

var show_object_uuids: bool = false
var _selection: SceneSelection
var _provider: FixtureRowProvider
var _details: RichTextLabel
var _document: RefCounted
var _inversion_box: VBoxContainer
var _inversion_rows: Array = []
var _patch_panel: VBoxContainer

func _ready() -> void:
	build_ui()

func build_ui() -> void:
	if _details != null: return
	_details = RichTextLabel.new()
	_details.selection_enabled = true
	_details.bbcode_enabled = false
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details.custom_minimum_size = Vector2(220, 100)
	var layout := VBoxContainer.new()
	add_child(layout)
	layout.add_child(_details)

	_inversion_box = VBoxContainer.new()
	layout.add_child(_inversion_box)
	for axis in range(2):
		var row := HBoxContainer.new()
		_inversion_box.add_child(row)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button := Button.new()
		button.text = "OFF"
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size.x = 48
		row.add_child(button)
		button.toggled.connect(func(value: bool) -> void:
			if _document != null: _document.apply(_selection.ids,axis,value)
			_render())
		_inversion_rows.append({"label": label, "button": button})
	_render()

func configure(selection: SceneSelection, provider: FixtureRowProvider, document: RefCounted = null) -> void:
	_selection = selection
	_provider = provider
	_document = document
	if _document != null: _document.changed.connect(_render)
	_selection.changed.connect(_render)
	build_ui()
	if _document != null and _patch_panel == null:
		_patch_panel = preload("res://scripts/ui/fixture_patch_panel.gd").new()
		_details.get_parent().add_child(_patch_panel)
		_details.get_parent().move_child(_patch_panel, 1)
		_patch_panel.configure(_document, _selection)
	_render()

# The import hook refreshes the selected object only. It never creates fixture rows.
func refresh(_rows: Array) -> void:
	if is_node_ready(): _render()

func finish_visible_refresh(budget: SceneLoadBudget) -> bool:
	return budget.valid()

func _render() -> void:
	if _details == null: return
	_render_inversions()
	_details.text = "INSPECTOR\n\nSelect an object in the scene or explorer.\n\nSelect canonical fixtures to edit MVR inversion. Other properties remain read-only."
	if _selection == null or _selection.ids.is_empty(): return
	if _selection.ids.size() > 1:
		_details.text = "INSPECTOR\n\n%d objects selected\n\nPan/Tilt inversion applies atomically to the complete validated fixture selection. Other properties remain read-only." % _selection.ids.size()
		return
	var id: String = _selection.ids[0]
	var node := _selection.node_for(id)
	if node == null: return
	var kind: String = str(node.get_meta("peraviz_type", "Object"))
	var row: Dictionary = _provider.get_fixture_row(id) if kind == "fixture" else {}
	var text := "INSPECTOR\n\nIdentification\n%s\n%s\n" % [row.get("fixture_name", node.get_meta("peraviz_name", node.name)), kind.capitalize()]
	if show_object_uuids: text += "UUID: %s\n" % id
	if kind == "fixture":
		text += "Fixture ID: %s\n\nFixture / GDTF\n%s\n\nDMX Mode\n%s\n\nAuthored patch · edit below\nPrimary universe: %s\nPrimary address: %s\n" % [_value(row, "fixture_id"), _value(row, "fixture_type"), _value(row, "dmx_mode"), _value(row, "universe"), _value(row, "address")]
	text += "\nTransform · local Godot coordinates\nPosition (m): %s\nRotation (°): %s\nScale: %s\n" % [node.position, node.rotation_degrees, node.scale]
	if kind == "fixture":
		var info: Dictionary = _document.fixture(id) if _document != null else {}
		text += "\nPan/Tilt inversion · MVR\n%s\n\nDiagnostics / compatibility\n%s\n%s" % ["Canonical MVR inversion controls below." if info.get("editable",false) else info.get("reason","Unavailable in this preview."), row.get("binding_status", "—"), row.get("binding_detail", "")]
	_details.text = text

func _value(row: Dictionary, key: String) -> String:
	var value: String = str(row.get(key, "")).strip_edges()
	return value if not value.is_empty() and value != "-1" else "Unavailable"

# Mixed selections explicitly offer ON for the whole selection before becoming an ordinary toggle.
func _render_inversions() -> void:
	var ids := _selection.ids if _selection != null else PackedStringArray()
	_inversion_box.visible = not ids.is_empty()
	var entries: Array = []
	var reason := ""
	for id in ids:
		var node := _selection.node_for(id)
		var entry: Dictionary = _document.fixture(id) if _document != null else {"editable": false,"reason":"No canonical MVR document"}
		if node == null or str(node.get_meta("peraviz_type","")) != "fixture": reason = "Select canonical fixtures only."
		elif not entry.get("editable",false): reason = str(entry.get("reason","Source identity is unavailable"))
		entries.append(entry)
	for axis in range(2):
		var field: String = "pan" if axis == 0 else "tilt"
		var row: Dictionary = _inversion_rows[axis]
		var first: bool = bool(entries[0].get(field,false)) if not entries.is_empty() else false
		var mixed := false
		for entry in entries: mixed = mixed or bool(entry.get(field,false)) != first
		row.label.text = "Invert %s" % field.capitalize()
		var button: Button = row.button
		button.set_pressed_no_signal(reason.is_empty() and not mixed and first)
		button.disabled = not reason.is_empty() or ids.is_empty()
		button.text = "Unavailable" if not reason.is_empty() else "Mixed → ON" if mixed else "ON" if first else "OFF"
		button.tooltip_text = reason if not reason.is_empty() else ("Mixed values; enable %s inversion on all %d selected fixtures" % [field,ids.size()] if mixed else "Set %s inversion %s on all %d selected fixtures" % [field,"off" if first else "on",ids.size()])
