extends RefCounted

const Binding = preload("res://scripts/runtime/presentation_transform_binding.gd")
const ARGUMENT: String = "--peraviz-transform-diagnostic="
const ACTIVE_ONLY: String = "active-only"
var mode: String = ACTIVE_ONLY
var trace: bool = false
var audit_dirty: bool = false
var _audit_pans: Dictionary = {}
var _audit_tilts: Dictionary = {}
var _audit_records: Array = []
var bindings: Array[Binding] = []
var _active: Array[Binding] = []
var _fixture_bindings: Dictionary = {}
var _axis_bindings: Dictionary = {} # Setup-only ownership, lookup once per moved axis.
var _axis_nodes: Dictionary = {}
var _axis_fixtures: Dictionary = {}
var _moved_axes: Dictionary = {}
var _moved_fixtures: Dictionary = {}
var _pending: Array[Binding] = []
var _affected: Dictionary = {}
var _audit_nodes: Dictionary = {}
var _audit_categories: Dictionary = {}
var _pan_writes: int = 0
var _tilt_writes: int = 0
var _written: int = 0
var _unchanged: int = 0
var _dark: int = 0
var _shaft_moves: int = 0
var _projector_moves: int = 0
var _sync_us: int = 0
var _mechanical_us: int = 0
var audit_builds: int = 0
var _shaft_nodes: Dictionary = {}
var _debug_nodes: Dictionary = {}
var _gobo_nodes: Dictionary = {}
var _lens_materials: Dictionary = {}
var _node_lens_materials: Dictionary = {}

static func from_arguments(arguments: PackedStringArray) -> String:
	var result: String = ACTIVE_ONLY
	for argument in arguments:
		if argument.begins_with(ARGUMENT):
			var value: String = argument.trim_prefix(ARGUMENT)
			if value in ["normal", "mechanical-only", ACTIVE_ONLY]:
				result = value
			else:
				result = ACTIVE_ONLY
				push_warning("Unknown Peraviz transform diagnostic; using active-only.")
	return result

func bind(light: SpotLight3D, canonical_id: int, dense_index: int) -> Binding:
	var binding := Binding.new()
	binding.install(light, canonical_id, dense_index, mode != "normal")
	bindings.append(binding)
	return binding

# Swap removal keeps dark outputs completely out of the production sync loop.
func set_active(binding: Binding, shaft: bool, projector: bool, diagnostic: bool) -> void:
	binding.shaft_active = shaft
	binding.projector_active = projector
	binding.diagnostic_active = diagnostic
	var enabled: bool = (shaft or projector or diagnostic) and mode == ACTIVE_ONLY
	if enabled == (binding.active_index >= 0): return
	if enabled:
		binding.active_index = _active.size()
		_active.append(binding)
	else:
		var index: int = binding.active_index
		var last: Binding = _active.back()
		_active[index] = last
		last.active_index = index
		_active.pop_back()
		binding.active_index = -1

func synchronize() -> void:
	if trace and audit_dirty: install_audit(_audit_pans, _audit_tilts, _audit_records)
	var started: int = Time.get_ticks_usec() if trace else 0
	for binding in _active:
		var changed: bool = binding.synchronize()
		if trace:
			if changed:
				_written += 1
				if binding.shaft_active: _shaft_moves += 1
				if binding.projector_active: _projector_moves += 1
			else: _unchanged += 1
	if trace:
		for binding in _pending:
			if not binding.shaft_active and not binding.projector_active and not binding.diagnostic_active: _dark += 1
			binding.pending_trace = false
		_pending.clear()
		_sync_us += Time.get_ticks_usec() - started

func clear() -> void:
	for binding in bindings: binding.release()
	bindings.clear()
	_active.clear()
	_pending.clear()
	_fixture_bindings.clear()
	_axis_bindings.clear()
	_axis_nodes.clear()
	_axis_fixtures.clear()
	_audit_nodes.clear()
	_audit_categories.clear()
	_shaft_nodes.clear()
	_debug_nodes.clear()
	_gobo_nodes.clear()
	_lens_materials.clear()
	_node_lens_materials.clear()
	_audit_pans = {}
	_audit_tilts = {}
	_audit_records = []
	audit_dirty = false
	audit_builds = 0
	consume_diagnostics()

# Called only during setup/rebind; no live SceneTree enumeration.
func install_audit(pans: Dictionary, tilts: Dictionary, records: Array) -> void:
	_audit_pans = pans
	_audit_tilts = tilts
	_audit_records = records
	audit_dirty = false
	if not trace: return
	audit_builds += 1
	_fixture_bindings.clear()
	_axis_bindings.clear()
	_axis_nodes.clear()
	_axis_fixtures.clear()
	_audit_nodes.clear()
	_audit_categories.clear()
	_shaft_nodes.clear()
	_debug_nodes.clear()
	_gobo_nodes.clear()
	_lens_materials.clear()
	_node_lens_materials.clear()
	for record in records:
		for entry in record.get("lens_material_targets", []):
			var material: Material = entry.get("material") if entry is Dictionary else entry as Material
			if material != null: _lens_materials[material.get_instance_id()] = true
	for binding in bindings:
		var light: SpotLight3D = binding.anchor
		var fixture: String = _fixture_for_node(binding.source)
		if not _fixture_bindings.has(fixture): _fixture_bindings[fixture] = []
		_fixture_bindings[fixture].append(binding)
		for key in ["peraviz_volumetric_beam", "peraviz_beam_prism", "peraviz_shader_beam_proxy"]:
			var beam: Node = light.get_meta(key) as Node if light.has_meta(key) else null
			if is_instance_valid(beam): _shaft_nodes[beam.get_instance_id()] = true
		var debug: Node = light.get_meta("peraviz_beam_debug_axis") as Node if light.has_meta("peraviz_beam_debug_axis") else null
		if is_instance_valid(debug): _debug_nodes[debug.get_instance_id()] = true
		var gobo: Node = light.get_meta("peraviz_gobo_plane") as Node if light.has_meta("peraviz_gobo_plane") else null
		if is_instance_valid(gobo): _gobo_nodes[gobo.get_instance_id()] = true
	for targets in [pans, tilts]:
		for axis in targets.values():
			var axis_id: int = axis.get_instance_id()
			if _axis_nodes.has(axis_id): continue
			_axis_nodes[axis_id] = axis
			_axis_fixtures[axis_id] = _fixture_for_node(axis)
			var owned: Array[Binding] = []
			for binding in bindings:
				if axis.is_ancestor_of(binding.anchor): owned.append(binding)
			_axis_bindings[axis_id] = owned
			var nodes: Array[Node] = []
			_collect_descendants(axis, nodes, false)
			_audit_nodes[axis_id] = nodes

func _fixture_for_node(node: Node) -> String:
	var current: Node = node
	while current != null:
		var fixture: String = str(current.get_meta("peraviz_fixture_uuid", ""))
		if not fixture.is_empty(): return fixture
		var key: String = str(current.get_meta("peraviz_gdtf_geometry_key", ""))
		if not key.is_empty(): return key.get_slice("/", 0)
		current = current.get_parent()
	return "unidentified"

func _collect_descendants(node: Node, result: Array[Node], presentation: bool) -> void:
	for child in node.get_children():
		var id: int = child.get_instance_id()
		var inside: bool = presentation or child is SpotLight3D
		var category: String = "mechanical_helpers"
		if child is Node3D and child.has_meta("peraviz_presentation_transform_carrier"):
			category = "presentation_helpers"
			inside = true
		if child is SpotLight3D: category = "spotlight_anchors"
		elif _shaft_nodes.has(id): category = "beam_meshes"
		elif _debug_nodes.has(id): category = "debug_axes"
		elif _gobo_nodes.has(id): category = "gobo_projector_resources"
		elif child is CollisionObject3D or child is CollisionShape3D: category = "collision_picking_objects"
		elif child is MeshInstance3D:
			category = "presentation_helpers" if inside else "fixture_body_meshes"
			var mesh: MeshInstance3D = child
			var material_ids: Array[int] = []
			if mesh.material_override != null and _lens_materials.has(mesh.material_override.get_instance_id()):
				category = "lens_meshes"
				material_ids.append(mesh.material_override.get_instance_id())
			if mesh.mesh != null:
				for surface in range(mesh.mesh.get_surface_count()):
					var material: Material = mesh.get_active_material(surface)
					if material != null and _lens_materials.has(material.get_instance_id()):
						category = "lens_meshes"
						material_ids.append(material.get_instance_id())
			if not material_ids.is_empty(): _node_lens_materials[id] = material_ids
		elif inside: category = "presentation_helpers"
		_audit_categories[id] = category
		result.append(child)
		_collect_descendants(child, result, inside)

# Trace only. Both axes of one fixture deduplicate pending output handles.
func moved(axis: Node3D, pan: bool) -> void:
	if not trace: return
	if pan: _pan_writes += 1
	else: _tilt_writes += 1
	var id: int = axis.get_instance_id()
	_moved_axes[id] = true
	_moved_fixtures[_axis_fixtures.get(id, id)] = true
	for binding in _axis_bindings.get(id, []):
		_affected[binding.anchor.get_instance_id()] = binding
		if not binding.pending_trace:
			binding.pending_trace = true
			_pending.append(binding)

func add_mechanical_time(elapsed: int) -> void:
	if trace: _mechanical_us += elapsed

# Interval-only allocation. Counts are unique axes/resources; write counts are events.
func consume_diagnostics() -> Dictionary:
	var result := {"mode": mode, "fixtures_moved": _moved_fixtures.size(), "pan_writes": _pan_writes, "tilt_writes": _tilt_writes,
		"moved_pan_tilt_axes": _moved_axes.size(), "presentation_bindings_affected": _affected.size(),
		"presentation_transforms_written": _written, "presentation_transforms_skipped_dark": _dark,
		"presentation_transforms_skipped_unchanged": _unchanged, "active_shafts_moved": _shaft_moves,
		"active_projectors_moved": _projector_moves, "presentation_transform_us": _sync_us, "mechanical_transform_writes_us": _mechanical_us,
		"bindings": bindings.size(), "active_bindings": _active.size(), "hierarchy_audit_builds": audit_builds}
	for category in ["spotlight_anchors", "beam_meshes", "dark_beam_meshes", "active_beam_meshes", "gobo_projector_resources", "debug_axes", "collision_picking_objects", "lens_meshes", "fixture_body_meshes", "presentation_helpers", "mechanical_helpers"]:
		result[category + "_under_moved_axes"] = 0
	var fixture_emitters: Dictionary = {}
	var fixture_active: int = 0
	var fixture_projectors: int = 0
	var fixture_shafts: int = 0
	for fixture in _moved_fixtures:
		for binding in _fixture_bindings.get(fixture, []):
			fixture_emitters[binding.anchor.get_instance_id()] = binding
	for binding in fixture_emitters.values():
		if binding.shaft_active or binding.projector_active or binding.diagnostic_active: fixture_active += 1
		if binding.shaft_active: fixture_shafts += 1
		if binding.projector_active: fixture_projectors += 1
	result["presentation_emitter_handles_on_moved_fixtures"] = fixture_emitters.size()
	result["active_emitters_on_moved_fixtures"] = fixture_active
	result["dark_emitters_on_moved_fixtures"] = fixture_emitters.size() - fixture_active
	result["active_projectors_on_moved_fixtures"] = fixture_projectors
	result["visible_shafts_on_moved_fixtures"] = fixture_shafts
	var descendants: Dictionary = {}
	for id in _moved_axes:
		for node in _audit_nodes.get(id, []):
			if is_instance_valid(node): descendants[node.get_instance_id()] = node
	var moved_lens_materials: Dictionary = {}
	var presentation_count: int = 0
	for id in descendants:
		for material_id in _node_lens_materials.get(id, []): moved_lens_materials[material_id] = true
		var category: String = _audit_categories.get(id, "presentation_helpers")
		var key: String = category + "_under_moved_axes"
		result[key] = int(result.get(key, 0)) + 1
		if category in ["spotlight_anchors", "beam_meshes", "gobo_projector_resources", "debug_axes", "presentation_helpers"]: presentation_count += 1
		if category == "beam_meshes":
			var key_active: String = "active_beam_meshes_under_moved_axes" if descendants[id].is_visible_in_tree() else "dark_beam_meshes_under_moved_axes"
			result[key_active] = int(result.get(key_active, 0)) + 1
	result["lens_material_resources_under_moved_axes"] = moved_lens_materials.size()
	result["presentation_descendants_under_moved_axes"] = presentation_count
	var active: int = 0
	for binding in _affected.values():
		if binding.shaft_active or binding.projector_active or binding.diagnostic_active: active += 1
	result["dark_outputs_ignored"] = _affected.size() - active
	result["ownership_note"] = "under counts describe SceneTree ownership; top-level carriers block transform inheritance"
	_pan_writes = 0
	_tilt_writes = 0
	_written = 0
	_unchanged = 0
	_dark = 0
	_shaft_moves = 0
	_projector_moves = 0
	_sync_us = 0
	_mechanical_us = 0
	_moved_axes.clear()
	_moved_fixtures.clear()
	_affected.clear()
	return result
