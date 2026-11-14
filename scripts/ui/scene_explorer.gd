extends VBoxContainer
class_name SceneExplorer

var tree: Tree
var search: LineEdit
var show_object_uuids: bool = false
var _selection: SceneSelection
var _items: Dictionary = {}
var _syncing: bool = false

func configure(selection: SceneSelection) -> void:
	_selection = selection
	var title := Label.new()
	title.text = "SCENE EXPLORER"
	add_child(title)
	search = LineEdit.new()
	search.placeholder_text = "Search name or fixture ID…"
	search.clear_button_enabled = true
	search.text_changed.connect(_filter)
	add_child(search)
	tree = Tree.new()
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_MULTI
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.multi_selected.connect(_picked)
	add_child(tree)
	_selection.changed.connect(_sync)

# TreeItems are lightweight; there is no Control per property or live packet refresh.
func publish(nodes: Dictionary, provider: FixtureRowProvider) -> void:
	tree.clear()
	_items.clear()
	var root := tree.create_item()
	for id in nodes:
		var node: Node3D = nodes[id]
		if str(node.get_meta("peraviz_type", "")) in ["fixture_geometry", "geometry", "symbol"]: continue
		var item := tree.create_item(root)
		_items[str(id)] = item
		var row: Dictionary = provider.get_fixture_row(str(id)) if node.get_meta("peraviz_type", "") == "fixture" else {}
		item.set_text(0, str(row.get("fixture_name", node.get_meta("peraviz_name", node.name))))
		item.set_metadata(0, str(id))
		item.set_tooltip_text(0, "%s\nFixture ID: %s" % [node.get_meta("peraviz_type", "Object"), row.get("fixture_id", "—")])
		if show_object_uuids: item.set_tooltip_text(0, item.get_tooltip_text(0) + "\nUUID: " + str(id))
	# Follow actual reconstructed parents; skip presentation-only geometry shells.
	for id in _items:
		var parent: Node = nodes[id].get_parent()
		while parent != null:
			var parent_id: String = str(parent.get_meta("peraviz_object_id", ""))
			if _items.has(parent_id):
				var item: TreeItem = _items[id]
				root.remove_child(item)
				_items[parent_id].add_child(item)
				break
			parent = parent.get_parent()
	_filter(search.text)
	_sync()

func _picked(_item: TreeItem, _column: int, _selected: bool) -> void:
	if _syncing: return
	var selected := PackedStringArray()
	var item: TreeItem = tree.get_next_selected(null)
	while item != null:
		selected.append(str(item.get_metadata(0)))
		item = tree.get_next_selected(item)
	_selection.select(selected)

func _sync() -> void:
	_syncing = true
	tree.deselect_all()
	for id in _selection.ids:
		if _items.has(id):
			var item: TreeItem = _items[id]
			item.select(0)
			var parent := item.get_parent()
			while parent != null:
				parent.collapsed = false
				parent = parent.get_parent()
	if not _selection.ids.is_empty() and _items.has(_selection.ids[0]): tree.scroll_to_item(_items[_selection.ids[0]])
	_syncing = false

func _filter(query: String) -> void:
	query = query.to_lower().strip_edges()
	for item: TreeItem in _items.values():
		item.visible = query.is_empty() or (item.get_text(0) + " " + item.get_tooltip_text(0) + " " + str(item.get_metadata(0))).to_lower().contains(query)
	if query.is_empty(): return
	for item: TreeItem in _items.values():
		if not item.visible: continue
		var parent := item.get_parent()
		while parent != null:
			parent.visible = true
			parent.collapsed = false
			parent = parent.get_parent()

func set_technical_identity(enabled: bool) -> void:
	show_object_uuids = enabled
	for id in _items:
		var item: TreeItem = _items[id]
		var tooltip: String = item.get_tooltip_text(0).split("\nUUID: ")[0]
		item.set_tooltip_text(0, tooltip + ("\nUUID: " + str(id) if enabled else ""))
