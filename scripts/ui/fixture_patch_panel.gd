extends VBoxContainer

var _document: RefCounted
var _selection: SceneSelection
var _rows := VBoxContainer.new()
var _message := Label.new()
var _remove_dialog := ConfirmationDialog.new()
var _pending_remove: Callable

func configure(document: RefCounted, selection: SceneSelection) -> void:
	_document = document
	_selection = selection
	var heading := Label.new()
	heading.text = "Patch · authored MVR"
	add_child(heading)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_font_size_override("font_size", 12)
	add_child(_rows)
	add_child(_message)
	add_child(_remove_dialog)
	_remove_dialog.title = "Remove authored DMX assignment"
	_remove_dialog.confirmed.connect(func() -> void:
		if _pending_remove.is_valid(): _pending_remove.call()
		_pending_remove = Callable())
	_remove_dialog.canceled.connect(func() -> void: _pending_remove = Callable())
	_document.changed.connect(refresh)
	_selection.changed.connect(refresh)
	refresh()

# Rebuild compact forms on explicit document/selection events, never per frame.
func refresh() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_remove_dialog.hide()
	_pending_remove = Callable()
	visible = not _selection.ids.is_empty()
	_message.text = ""
	if _selection.ids.is_empty(): return
	if _selection.ids.size() != 1:
		var first: Array = _document.fixture(_selection.ids[0]).get("addresses", [])
		var mixed := false
		for id in _selection.ids: mixed = mixed or _document.fixture(id).get("addresses", []) != first
		_message.text = ("Mixed authored patches. " if mixed else "Shared authored assignments. ") + "Patch is read-only for multiple selections: each fixture keeps its own addresses. Select one fixture to edit."
		return
	var id: String = _selection.ids[0]
	var info: Dictionary = _document.patch_fixture(id)
	var enabled: bool = info.get("patch_editable", false)
	var entries: Array = info.get("addresses", [])
	var footprints: Dictionary = {}
	for item in info.get("breaks", []): footprints[int(item["break"])] = int(item.footprint)
	if not enabled: _message.text = str(info.get("patch_reason", info.get("reason", "Canonical patch is unavailable")))
	elif entries.is_empty(): _message.text = "Unpatched: no authored MVR Address entries."
	for entry in entries:
		_add_row(id, int(entry["break"]), int(entry.universe), int(entry.address), enabled, "set", footprints.get(int(entry["break"]), 0))
	if enabled:
		var add := Button.new()
		add.text = "Add break…"
		add.tooltip_text = "Explicitly insert a missing MVR break assignment; GDTF break n corresponds to MVR break n−1."
		_rows.add_child(add)
		add.pressed.connect(func() -> void:
			add.disabled = true
			_add_row(id, -1, 1, 1, true, "insert", 0))

func _number(value: int, minimum: int, maximum: int, hint: String) -> LineEdit:
	var input := LineEdit.new()
	input.text = str(value)
	input.max_length = 10
	input.set_meta("minimum", minimum)
	input.set_meta("maximum", maximum)
	input.custom_minimum_size.x = 64
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.tooltip_text = hint
	return input

func _add_row(id: String, break_id: int, universe: int, address: int, enabled: bool, operation: String, footprint: int) -> void:
	var box := VBoxContainer.new()
	_rows.add_child(box)
	var heading := Label.new()
	heading.text = ("MVR break %d" % break_id if break_id >= 0 else "New MVR break") + (" · footprint %d slots" % footprint if footprint > 0 else " · footprint unknown")
	box.add_child(heading)
	var row := HBoxContainer.new()
	box.add_child(row)
	var number: LineEdit
	if operation == "insert":
		number = _number(0, 0, 2147483647, "Unique MVR break identifier (GDTF break minus one).")
		row.add_child(number)
	var u := _number(universe, 1, 32768, "Authored MVR universe, starting at 1. Art-Net offset is a separate runtime setting.")
	var a := _number(address, 1, 512, "DMX address (slot), 1–512.")
	for pair in [["Universe", u], ["Address", a]]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(column)
		var caption := Label.new()
		caption.text = pair[0]
		column.add_child(caption)
		column.add_child(pair[1])
	u.editable = enabled
	a.editable = enabled
	var apply := Button.new()
	apply.text = "Add" if operation == "insert" else "Apply"
	apply.disabled = not enabled
	row.add_child(apply)
	apply.pressed.connect(func() -> void:
		# Validate complete decimal text only on Apply; typing or Enter never submits a patch.
		for input in ([number, u, a] if number != null else [u, a]):
			var raw: String = input.text.strip_edges()
			if not raw.is_valid_int() or int(raw) < int(input.get_meta("minimum")) or int(raw) > int(input.get_meta("maximum")):
				_message.text = "Fixture %s, break %s: enter complete integers in the displayed ranges." % [id, break_id]
				return
		var target: int = int(number.text) if number != null else break_id
		if not _document.apply_patch(id, target, int(u.text), int(a.text), operation): _message.text = _document.patch_error
		elif not _document.patch_warnings.is_empty(): _message.text = "\n".join(_document.patch_warnings))
	if operation == "set":
		var remove := Button.new()
		remove.text = "×"
		remove.tooltip_text = "Explicitly remove this authored assignment. Required or unsafe removals are rejected."
		remove.disabled = not enabled
		row.add_child(remove)
		remove.pressed.connect(func() -> void:
			_pending_remove = func() -> void:
				if not _document.apply_patch(id, break_id, 0, 0, "remove"): _message.text = _document.patch_error
			_remove_dialog.dialog_text = "Remove MVR break %d from fixture %s?" % [break_id, id]
			_remove_dialog.popup_centered())
