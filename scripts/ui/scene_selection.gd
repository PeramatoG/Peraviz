extends RefCounted
class_name SceneSelection

signal changed

# IDs refer directly to the published node index, never to a second scene model.
var ids := PackedStringArray()
var _nodes: Dictionary = {}
var _node_ids: Dictionary = {}

func publish(nodes: Dictionary) -> void:
	clear()
	_nodes = nodes
	_node_ids.clear()
	for id in nodes:
		var node: Node = nodes[id]
		if is_instance_valid(node): _node_ids[node.get_instance_id()] = str(id)

func clear() -> void:
	ids = PackedStringArray()
	changed.emit()

func retire() -> void:
	clear()
	_nodes = {}
	_node_ids.clear()

func select(values: PackedStringArray) -> void:
	var valid := PackedStringArray()
	for id in values:
		if is_instance_valid(_nodes.get(id)) and not valid.has(id): valid.append(id)
	if ids == valid: return
	ids = valid
	changed.emit()

func node_for(id: String) -> Node3D:
	var node: Node3D = _nodes.get(id)
	return node if is_instance_valid(node) else null

func id_for(node: Node) -> String:
	while node != null:
		var id: String = _node_ids.get(node.get_instance_id(), "")
		if not id.is_empty():
			# Select fixture ownership before internal GDTF geometry.
			var fixture: String = str(node.get_meta("peraviz_fixture_uuid", ""))
			return fixture if _nodes.has(fixture) else id
		node = node.get_parent()
	return ""

func bounds() -> AABB:
	var result := AABB()
	var found: bool = false
	for id in ids:
		var node := node_for(id)
		if node == null: continue
		var box := object_bounds(node)
		result = result.merge(box) if found else box
		found = true
	return result

static func object_bounds(node: Node3D) -> AABB:
	var result := AABB(node.global_position - Vector3.ONE * 0.1, Vector3.ONE * 0.2)
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var child: Node = pending.pop_back()
		# Runtime beam meshes live under lights; they are presentation, not object extent.
		if child is Light3D or child.has_meta(&"peraviz_selection_overlay"): continue
		if child is MeshInstance3D and child.mesh != null:
			result = result.merge(child.global_transform * child.get_aabb())
		for descendant in child.get_children(): pending.append(descendant)
	return result
