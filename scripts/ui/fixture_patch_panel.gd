extends VBoxContainer

var _document: RefCounted
var _selection: SceneSelection
var _rows := VBoxContainer.new()
var _message := Label.new()

func configure(document: RefCounted, selection: SceneSelection) -> void:
	_document = document
	_selection = selection
	var heading := Label.new()
	heading.text = "Patch"
	add_child(heading)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_font_size_override("font_size", 12)
	add_child(_rows)
	add_child(_message)
	_document.changed.connect(refresh)
	_selection.changed.connect(refresh)
	refresh()

# Rebuild compact forms on explicit document/selection events, never per frame.
func refresh() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	visible = not _selection.ids.is_empty()
	_message.text = ""
	if _selection.ids.is_empty(): return
	if _selection.ids.size() != 1:
		var first: Array = _document.fixture(_selection.ids[0]).get("addresses", [])
		var mixed := false
		for id in _selection.ids: mixed = mixed or _document.fixture(id).get("addresses", []) != first
		_message.text = ("Mixed patches. " if mixed else "Shared patch. ") + "Select one fixture to edit."
		return
	var id: String = _selection.ids[0]
	var info: Dictionary = _document.patch_fixture(id)
	var enabled: bool = info.get("patch_editable", false)
	var entries: Array = info.get("addresses", [])
	var footprints: Dictionary = {}
	for item in info.get("breaks", []): footprints[int(item["break"])] = int(item.footprint)
	if not enabled: _message.text = str(info.get("patch_reason", info.get("reason", "Patch is unavailable")))
	elif entries.is_empty(): _message.text = "Unpatched."
	for entry in entries:
		_add_row(id, entry, enabled, footprints.get(int(entry["break"]), 0))

func _add_row(id: String, entry: Dictionary, enabled: bool, footprint: int) -> void:
	var box := VBoxContainer.new()
	_rows.add_child(box)
	var heading := Label.new()
	heading.text = "Footprint: %d slots" % footprint if footprint > 0 else "Footprint: unknown"
	box.add_child(heading)
	var row := HBoxContainer.new()
	box.add_child(row)
	for field in ["universe", "address"]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		var caption := Label.new()
		caption.text = field.capitalize()
		column.add_child(caption)
		var input := LineEdit.new()
		input.text = str(entry[field])
		input.max_length = 10
		input.custom_minimum_size.x = 64
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.editable = enabled
		input.tooltip_text = "Press Enter to apply. Leaving the field discards unconfirmed changes."
		column.add_child(input)
		input.focus_exited.connect(func() -> void: input.text = str(entry[field]))
		input.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
				input.text = str(entry[field])
				input.accept_event()
				input.release_focus())
		input.text_submitted.connect(func(text: String) -> void:
			# Submit only this field; another field's unconfirmed draft never enters a document command.
			var raw := text.strip_edges()
			var maximum := 32768 if field == "universe" else 512
			input.text = str(entry[field])
			if not raw.is_valid_int() or int(raw) < 1 or int(raw) > maximum:
				_message.text = "%s must be a whole number from 1 to %d." % [field.capitalize(), maximum]
				return
			var universe: int = int(raw) if field == "universe" else int(entry.universe)
			var address: int = int(raw) if field == "address" else int(entry.address)
			if not _document.apply_patch(id, int(entry["break"]), universe, address): _message.text = _document.patch_error
			elif not _document.patch_warnings.is_empty(): _message.text = "\n".join(_document.patch_warnings))
