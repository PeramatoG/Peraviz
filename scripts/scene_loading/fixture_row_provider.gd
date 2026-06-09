extends RefCounted
class_name FixtureRowProvider

var _loader = null
var _scene_registry: SceneRegistry = null
var _loaded_nodes: Array = []
var _fixture_node_lookup: Dictionary = {}
var _fixture_patch_lookup: Dictionary = {}
var _bindings: Array = []
var _unbound: Array = []

func configure(loader, scene_registry: SceneRegistry) -> void:
	_loader = loader
	_scene_registry = scene_registry
	_rebuild_fixture_patch_lookup()

func clear() -> void:
	_loaded_nodes.clear()
	_fixture_node_lookup.clear()
	_fixture_patch_lookup.clear()
	_bindings.clear()
	_unbound.clear()

func set_loaded_nodes(nodes: Array) -> void:
	_loaded_nodes = nodes.duplicate(true)
	_rebuild_fixture_node_lookup()
	_rebuild_fixture_patch_lookup()

func set_dmx_state(bindings: Array, unbound: Array) -> void:
	_bindings = bindings.duplicate(true)
	_unbound = unbound.duplicate(true)
	_rebuild_fixture_patch_lookup()

func get_fixture_rows() -> Array:
	var rows: Array = []
	for fixture_uuid in _collect_known_fixture_uuids():
		rows.append(get_fixture_row(str(fixture_uuid)))
	rows.sort_custom(Callable(self, "_sort_fixture_rows"))
	return rows

func get_fixture_row(fixture_uuid: String) -> Dictionary:
	if fixture_uuid.is_empty():
		return {}
	var node_data: Dictionary = _fixture_node_lookup.get(fixture_uuid, {})
	var patch: Dictionary = _fixture_patch_lookup.get(fixture_uuid, {})
	var binding: Dictionary = _find_binding_for_fixture(fixture_uuid)
	var unbound: Dictionary = _find_unbound_for_fixture(fixture_uuid)
	var fixture_node: Node = _scene_registry.get_fixture(fixture_uuid) if _scene_registry != null else null
	return {
		"fixture_uuid": fixture_uuid,
		"fixture_name": _resolve_fixture_name(node_data, patch, binding, fixture_node),
		"fixture_id": _resolve_fixture_id(node_data, patch, binding, fixture_node),
		"fixture_type": _resolve_fixture_type(node_data, patch, binding, fixture_node),
		"universe": _resolve_fixture_universe(patch, binding),
		"address": _resolve_fixture_address(patch, binding),
		"binding_status": _resolve_fixture_binding_status(binding, unbound, patch),
		"binding_detail": _resolve_fixture_binding_detail(binding, unbound, patch),
		"position": _resolve_vector3(node_data, ["pos", "position"]),
		"rotation": _resolve_vector3(node_data, ["rot", "rotation", "rotation_degrees"]),
		"position_label": _resolve_vector3_label(node_data, ["pos", "position"]),
		"rotation_label": _resolve_vector3_label(node_data, ["rot", "rotation", "rotation_degrees"]),
	}

func get_fixture_patch_lookup() -> Dictionary:
	_rebuild_fixture_patch_lookup()
	return _fixture_patch_lookup.duplicate(true)

func _rebuild_fixture_node_lookup() -> void:
	_fixture_node_lookup.clear()
	for node_value in _loaded_nodes:
		if node_value is not Dictionary:
			continue
		var node_data: Dictionary = node_value
		if str(node_data.get("type", "")) != "fixture":
			continue
		var fixture_uuid: String = str(node_data.get("node_id", ""))
		if fixture_uuid.is_empty():
			continue
		_fixture_node_lookup[fixture_uuid] = node_data

func _rebuild_fixture_patch_lookup() -> void:
	_fixture_patch_lookup.clear()
	if _loader == null or not _loader.has_method("get_fixtures_patch"):
		return
	var patches: Array = _loader.get_fixtures_patch()
	for patch_value in patches:
		if patch_value is not Dictionary:
			continue
		var patch: Dictionary = patch_value
		var fixture_uuid: String = str(patch.get("fixture_uuid", ""))
		if fixture_uuid.is_empty():
			continue
		_fixture_patch_lookup[fixture_uuid] = patch

func _collect_known_fixture_uuids() -> PackedStringArray:
	var uuid_lookup: Dictionary = {}
	for fixture_uuid in _fixture_node_lookup.keys():
		uuid_lookup[str(fixture_uuid)] = true
	for fixture_uuid in _fixture_patch_lookup.keys():
		uuid_lookup[str(fixture_uuid)] = true
	for binding in _bindings:
		if binding is Dictionary:
			var bound_uuid: String = str(binding.get("fixture_uuid", ""))
			if not bound_uuid.is_empty():
				uuid_lookup[bound_uuid] = true
	for row in _unbound:
		if row is Dictionary:
			var unbound_uuid: String = str(row.get("fixture_uuid", ""))
			if not unbound_uuid.is_empty():
				uuid_lookup[unbound_uuid] = true
	if _scene_registry != null:
		for fixture_uuid in _scene_registry.list_fixture_uuids():
			uuid_lookup[str(fixture_uuid)] = true

	var uuids := PackedStringArray()
	for fixture_uuid in uuid_lookup.keys():
		uuids.append(str(fixture_uuid))
	uuids.sort()
	return uuids

func _find_binding_for_fixture(fixture_uuid: String) -> Dictionary:
	for binding in _bindings:
		if binding is Dictionary and str(binding.get("fixture_uuid", "")) == fixture_uuid:
			return binding
	return {}

func _find_unbound_for_fixture(fixture_uuid: String) -> Dictionary:
	for row in _unbound:
		if row is Dictionary and str(row.get("fixture_uuid", "")) == fixture_uuid:
			return row
	return {}

func _resolve_fixture_name(node_data: Dictionary, patch: Dictionary, binding: Dictionary, fixture_node: Node) -> String:
	var fixture_name: String = _first_non_empty_string(node_data, ["fixture_name", "fixture_label", "name", "label"])
	if fixture_name.is_empty():
		fixture_name = _first_non_empty_string(binding, ["fixture_name", "fixture_label", "name", "label"])
	if fixture_name.is_empty():
		fixture_name = _first_non_empty_string(patch, ["fixture_name", "fixture_label", "name", "label"])
	if fixture_name.is_empty() and fixture_node != null:
		fixture_name = _first_non_empty_node_meta(fixture_node, ["peraviz_fixture_name", "fixture_name", "name"])
	if fixture_name.is_empty() and fixture_node != null:
		fixture_name = _clean_fixture_node_name(fixture_node.name)
	return fixture_name

func _resolve_fixture_id(node_data: Dictionary, patch: Dictionary, binding: Dictionary, fixture_node: Node) -> String:
	var fixture_id: String = _first_non_empty_string(node_data, ["fixture_id", "fixture_number", "fixture_no", "unit_number", "mvr_fixture_id"])
	if fixture_id.is_empty():
		fixture_id = _first_non_empty_string(binding, ["fixture_id", "fixture_number", "fixture_no", "unit_number", "mvr_fixture_id"])
	if fixture_id.is_empty():
		fixture_id = _first_non_empty_string(patch, ["fixture_id", "fixture_number", "fixture_no", "unit_number", "mvr_fixture_id"])
	if fixture_id.is_empty() and fixture_node != null:
		fixture_id = _first_non_empty_node_meta(fixture_node, ["peraviz_fixture_id", "peraviz_fixture_number", "fixture_id", "fixture_number", "unit_number"])
	return fixture_id

func _resolve_fixture_type(node_data: Dictionary, patch: Dictionary, binding: Dictionary, fixture_node: Node) -> String:
	var fixture_type: String = _first_non_empty_string(node_data, ["fixture_type", "type_label", "gdtf_name", "gdtf_spec"])
	if fixture_type.is_empty():
		fixture_type = _first_non_empty_string(binding, ["fixture_type", "type", "gdtf_name", "gdtf_spec"])
	if fixture_type.is_empty():
		fixture_type = _first_non_empty_string(patch, ["fixture_type", "type", "gdtf_name", "gdtf_spec"])
	if fixture_type.is_empty() and fixture_node != null:
		fixture_type = _first_non_empty_node_meta(fixture_node, ["peraviz_fixture_type", "fixture_type", "gdtf_name", "gdtf_spec"])
	if fixture_type.is_empty():
		fixture_type = _gdtf_path_basename(_first_non_empty_string(binding, ["gdtf_path"]))
	if fixture_type.is_empty():
		fixture_type = _gdtf_path_basename(_first_non_empty_string(patch, ["gdtf_path"]))
	if fixture_type == "fixture":
		fixture_type = ""
	return fixture_type

func _resolve_fixture_universe(patch: Dictionary, binding: Dictionary) -> String:
	var universe: String = _first_non_empty_string(patch, ["universe", "mvr_universe"])
	if universe.is_empty():
		universe = _first_non_empty_string(binding, ["universe", "mvr_universe", "artnet_universe_id"])
	return universe

func _resolve_fixture_address(patch: Dictionary, binding: Dictionary) -> String:
	var address: String = _first_non_empty_string(patch, ["address", "mvr_address", "dmx_address"])
	if address.is_empty():
		address = _first_non_empty_string(binding, ["address", "mvr_address", "dmx_address"])
	return address

func _resolve_fixture_binding_status(binding: Dictionary, unbound: Dictionary, patch: Dictionary) -> String:
	var universe: String = _resolve_fixture_universe(patch, binding)
	var address: String = _resolve_fixture_address(patch, binding)
	var is_patched: bool = not universe.is_empty() and not address.is_empty()
	if not binding.is_empty():
		return "Patched / Bound" if is_patched else "Bound"
	if not unbound.is_empty():
		return "Patched / Unbound" if is_patched else "Unpatched / Unbound"
	if not is_patched:
		return "Unpatched"
	return "Patched / Not bound"

func _resolve_fixture_binding_detail(binding: Dictionary, unbound: Dictionary, patch: Dictionary) -> String:
	if not binding.is_empty():
		var artnet_universe: String = _first_non_empty_string(binding, ["artnet_universe_id"])
		return "Bound to Art-Net universe %s" % artnet_universe if not artnet_universe.is_empty() else "Bound to DMX controls"
	if not unbound.is_empty():
		return _format_unbound_reason(str(unbound.get("reason", "unspecified")))
	var universe: String = _resolve_fixture_universe(patch, binding)
	var address: String = _resolve_fixture_address(patch, binding)
	if universe.is_empty() or address.is_empty():
		return "Missing MVR universe or address"
	return "No DMX binding has been built for this fixture"

func _resolve_vector3(source: Dictionary, keys: Array) -> Variant:
	for key in keys:
		if not source.has(key):
			continue
		var value: Variant = source.get(key, null)
		if value is Vector3:
			return value
	return null

func _resolve_vector3_label(source: Dictionary, keys: Array) -> String:
	var value: Variant = _resolve_vector3(source, keys)
	if value is not Vector3:
		return ""
	var vector: Vector3 = value
	return "%.2f, %.2f, %.2f" % [vector.x, vector.y, vector.z]

func _first_non_empty_string(source: Dictionary, keys: Array) -> String:
	for key in keys:
		if not source.has(key):
			continue
		var value: String = str(source.get(key, "")).strip_edges()
		if value.is_empty() or value == "-1":
			continue
		return value
	return ""

func _first_non_empty_node_meta(node: Node, keys: Array) -> String:
	for key in keys:
		if not node.has_meta(key):
			continue
		var value: String = str(node.get_meta(key, "")).strip_edges()
		if value.is_empty() or value == "-1":
			continue
		return value
	return ""

func _clean_fixture_node_name(node_name: String) -> String:
	var value: String = node_name.strip_edges()
	if value.begins_with("fixture_") and value.length() > "fixture_".length():
		value = value.substr("fixture_".length()).strip_edges()
	if value == "fixture" or value == "Fixture":
		return ""
	return value

func _gdtf_path_basename(gdtf_path: String) -> String:
	var value: String = gdtf_path.strip_edges()
	if value.is_empty():
		return ""
	return value.get_file().get_basename()

func _format_unbound_reason(reason: String) -> String:
	var value: String = reason.strip_edges()
	if value.is_empty():
		return "Unspecified"
	if value == "No Dimmer/Pan/Tilt/Zoom/CMY/Gobo attributes found in mode DMX channels":
		return "No controllable Dimmer/Pan/Tilt/Zoom/CMY/Gobo attributes found in the selected DMX mode"
	return value.substr(0, 1).to_upper() + value.substr(1)

func _sort_fixture_rows(a: Dictionary, b: Dictionary) -> bool:
	var a_name: String = str(a.get("fixture_name", "")).to_lower()
	var b_name: String = str(b.get("fixture_name", "")).to_lower()
	if a_name == b_name:
		return str(a.get("fixture_uuid", "")) < str(b.get("fixture_uuid", ""))
	return a_name < b_name
