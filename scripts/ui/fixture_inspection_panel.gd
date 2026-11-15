extends PanelContainer
class_name FixtureInspectionPanel

var show_object_uuids: bool = false
var _selection: SceneSelection
var _provider: FixtureRowProvider
var _details: RichTextLabel

func _ready() -> void:
	build_ui()

func build_ui() -> void:
	if _details != null: return
	_details = RichTextLabel.new()
	_details.selection_enabled = true
	_details.bbcode_enabled = false
	_details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details.custom_minimum_size = Vector2(220, 100)
	add_child(_details)
	_render()

func configure(selection: SceneSelection, provider: FixtureRowProvider) -> void:
	_selection = selection
	_provider = provider
	_selection.changed.connect(_render)
	build_ui()
	_render()

# The import hook refreshes the selected object only. It never creates fixture rows.
func refresh(_rows: Array) -> void:
	if is_node_ready(): _render()

func finish_visible_refresh(budget: SceneLoadBudget) -> bool:
	return budget.valid()

func _render() -> void:
	if _details == null: return
	_details.text = "INSPECTOR\n\nSelect an object in the scene or explorer.\n\nProperties are read-only in this preview."
	if _selection == null or _selection.ids.is_empty(): return
	if _selection.ids.size() > 1:
		_details.text = "INSPECTOR\n\n%d objects selected\n\nMulti-object editing is reserved for the MVR document editing milestone." % _selection.ids.size()
		return
	var id: String = _selection.ids[0]
	var node := _selection.node_for(id)
	if node == null: return
	var kind: String = str(node.get_meta("peraviz_type", "Object"))
	var row: Dictionary = _provider.get_fixture_row(id) if kind == "fixture" else {}
	var text := "INSPECTOR · READ ONLY\n\nIdentification\n%s\n%s\n" % [row.get("fixture_name", node.get_meta("peraviz_name", node.name)), kind.capitalize()]
	if show_object_uuids: text += "UUID: %s\n" % id
	if kind == "fixture":
		text += "Fixture ID: %s\n\nFixture / GDTF\n%s\n\nDMX Mode\n%s\n\nPatch\nUniverse: %s\nAddress: %s\n" % [_value(row, "fixture_id"), _value(row, "fixture_type"), _value(row, "dmx_mode"), _value(row, "universe"), _value(row, "address")]
	text += "\nTransform · local Godot coordinates\nPosition (m): %s\nRotation (°): %s\nScale: %s\n" % [node.position, node.rotation_degrees, node.scale]
	if kind == "fixture":
		text += "\nPan/Tilt inversion · MVR\nPan inversion: Unavailable\nTilt inversion: Unavailable\nUnavailable in this preview.\n\nDiagnostics / compatibility\n%s\n%s" % [row.get("binding_status", "—"), row.get("binding_detail", "")]
	_details.text = text

func _value(row: Dictionary, key: String) -> String:
	var value: String = str(row.get(key, "")).strip_edges()
	return value if not value.is_empty() and value != "-1" else "Unavailable"
