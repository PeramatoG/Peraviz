extends VBoxContainer

var _document: RefCounted
var _uuid: String
var _current: String
var _modes: Array = []
var _choice := OptionButton.new()
var _hint := Label.new()
var _apply := Button.new()
var _cancel := Button.new()

func configure(document: RefCounted) -> void:
	_document = document
	var label := Label.new()
	label.text = "DMX Mode"
	add_child(label)
	_choice.fit_to_longest_item = false
	_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_choice)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint)
	var actions := HBoxContainer.new()
	add_child(actions)
	_apply.text = "Apply"
	_cancel.text = "Cancel"
	actions.add_child(_apply)
	actions.add_child(_cancel)
	_choice.item_selected.connect(_describe)
	_apply.pressed.connect(_confirm)
	_cancel.pressed.connect(func() -> void: show_fixture(_uuid))

func show_fixture(uuid: String) -> void:
	_uuid = uuid
	visible = not uuid.is_empty()
	if not visible: return
	var info: Dictionary = _document.mode_fixture(uuid)
	_current = info.get("dmx_mode", "")
	_modes = info.get("modes", [])
	_choice.clear()
	var current_index := -1
	for mode: Dictionary in _modes:
		var index := _choice.item_count
		var supported: bool = mode.get("semantic_supported", false)
		var label: String = mode.name if not mode.name.is_empty() else "Unnamed mode"
		if not supported: label += " (unavailable)"
		_choice.add_item(label)
		var tip := _footprint(mode)
		if not mode.description.is_empty(): tip += "\n" + mode.description
		if not mode.diagnostic.is_empty(): tip += "\n" + mode.diagnostic
		_choice.set_item_tooltip(index, tip)
		_choice.set_item_disabled(index, not supported)
		if current_index < 0 and mode.name == _current: current_index = index
	if current_index < 0:
		current_index = _choice.item_count
		_choice.add_item("No authored mode" if _current.is_empty() else _current + " (unavailable)")
		_choice.set_item_disabled(current_index, true)
	_choice.select(current_index)
	var reason: String = info.get("mode_reason", "")
	_choice.disabled = not info.get("editable", false) or not reason.is_empty() or _modes.is_empty()
	_describe(current_index)
	if not reason.is_empty(): _hint.text = reason

func _footprint(mode: Dictionary) -> String:
	if not mode.get("footprint_known", false): return "Footprint unavailable"
	var breaks := PackedStringArray()
	for entry: Dictionary in mode.breaks:
		breaks.append("%d slots on MVR break %d" % [entry.footprint, entry["break"]])
	return ", ".join(breaks) if not breaks.is_empty() else "No physical DMX slots"

func _describe(index: int) -> void:
	var valid := index >= 0 and index < _modes.size()
	var pending: bool = valid and _modes[index].name != _current and not _choice.disabled and not _choice.is_item_disabled(index)
	_apply.visible = pending
	_cancel.visible = pending
	_hint.text = _footprint(_modes[index]) if valid else ""
	if not pending: return
	var info: Dictionary = _document.fixture(_uuid)
	var target: Dictionary = _modes[index]
	for mode: Dictionary in _modes:
		if mode.name != _current: continue
		_hint.text = "%s → %s" % [_footprint(mode), _footprint(target)]
		if mode.geometry != target.geometry:
			_hint.text += "\nGeometry changes to " + target.geometry
		break
	var assigned: Dictionary = {}
	for entry: Dictionary in info.get("addresses", []): assigned[entry["break"]] = entry
	_apply.disabled = false
	for entry: Dictionary in target.breaks:
		var number: int = entry["break"]
		if not assigned.has(number):
			_hint.text += "\nAssign MVR break %d before applying." % number
			_apply.disabled = true
			continue
		var patch: Dictionary = assigned[number]
		var last: int = patch.address + entry.footprint - 1
		if last > 512:
			_hint.text += "\nBreak %d crosses the universe boundary. Auto Span policy applies." % number

func _confirm() -> void:
	var index := _choice.selected
	if index < 0 or index >= _modes.size() or _choice.disabled: return
	var id := _uuid
	if not await _document.apply_mode(id, _modes[index].name) and id == _uuid:
		show_fixture(id)
		_hint.text = _document.mode_error
