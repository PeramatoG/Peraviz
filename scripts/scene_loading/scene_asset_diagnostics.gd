extends RefCounted

const ModelGeometry = preload("res://scripts/scene_loading/model_geometry.gd")
var counts: Dictionary = {}
var _failures: Dictionary = {}
var _fixtures: Dictionary = {}

func reset(nodes: Array) -> void:
	counts = {"success": 0, "failure": 0, "fallback": 0, "extracted": 0, "decoded": 0, "mesh_created": 0, "attached": 0, "renderable": 0, "visible": 0}
	_failures.clear()
	_fixtures.clear()
	for item: Dictionary in nodes:
		if item.get("type", "") == "fixture":
			_fixtures[str(item.node_id)] = {"renderable": false, "fallback": false}

# Audit asset outcomes after attachment. A decoded Node3D alone is never a success.
func observe(data: Dictionary, node: Node3D, asset_cache: PeravizRuntimeAssetCache) -> void:
	var path: String = str(data.get("asset_path", ""))
	var reason: String = str(data.get("asset_error", ""))
	var kind: String = str(data.get("asset_kind", ""))
	if path.is_empty() and reason.is_empty() and kind != "primitive" and str(data.get("gdtf_model_name", "")).is_empty():
		return
	var visual: Node3D = node.get_meta("peraviz_model_visual") if node.has_meta("peraviz_model_visual") else null
	var fallback: bool = visual != null and bool(visual.get_meta("peraviz_model_fallback", false))
	var stage: String = str(data.get("asset_error_stage", "resolution"))
	if reason.contains("extract") or reason == "archive_open_failed" or reason.contains("description") or reason == "invalid_gdtf_xml": stage = "extraction"
	if not path.is_empty():
		if FileAccess.file_exists(path): counts.extracted += 1
		if asset_cache.is_failed(path):
			reason = asset_cache.failure_reason(path)
			stage = asset_cache.failure_stage(path)
	var report: Dictionary = ModelGeometry.inspect(visual) if visual != null else {}
	var real: bool = not fallback and report.get("meshes", 0) > 0 and report.get("has_bounds", false) and report.get("valid", false)
	var attached: bool = visual != null and visual.is_inside_tree() and node.is_inside_tree()
	if real:
		if not path.is_empty(): counts.decoded += 1
		counts.mesh_created += 1
		if attached: counts.attached += 1
		var world_bounds: AABB = node.global_transform * report.bounds if node.is_inside_tree() else report.bounds
		if not world_bounds.position.is_finite() or not world_bounds.size.is_finite() or world_bounds.size.length_squared() == 0:
			real = false
			reason = "invalid_world_bounds"
			stage = "attachment"
		elif not attached:
			reason = "model_not_attached"
			stage = "attachment"
		elif report.locally_visible_meshes == 0:
			reason = "model_locally_hidden"
			stage = "visibility"
		else:
			counts.renderable += 1
			if report.visible_meshes > 0: counts.visible += 1
	if reason.is_empty() and not real:
		reason = "no_renderable_geometry"
		stage = "scene_instantiation"
	if fallback: counts.fallback += 1
	if reason.is_empty(): counts.success += 1
	else:
		counts.failure += 1
		_add_failure(data, path, kind, stage, reason)
	var uuid: String = str(data.get("gdtf_fixture_uuid", ""))
	if _fixtures.has(uuid):
		_fixtures[uuid].renderable = _fixtures[uuid].renderable or (real and attached and report.get("locally_visible_meshes", 0) > 0)
		_fixtures[uuid].fallback = _fixtures[uuid].fallback or fallback

func _add_failure(data: Dictionary, path: String, kind: String, stage: String, reason: String) -> void:
	var format: String = path.get_extension().to_lower() if not path.is_empty() else kind
	if format.is_empty() or format == "none": format = "unresolved"
	var source: String = str(data.get("gdtf_source", ""))
	var model: String = str(data.get("gdtf_model_name", ""))
	var reference: String = str(data.get("asset_reference", ""))
	var key: String = JSON.stringify([source, model, reference, path, format, stage, reason])
	if not _failures.has(key):
		_failures[key] = {"source": source, "fixture_type": str(data.get("gdtf_fixture_type", "")), "model": model, "reference": reference, "path": path, "format": format, "stage": stage, "reason": reason, "occurrences": 0, "fixture_instances": {}}
	var row: Dictionary = _failures[key]
	row.occurrences += 1
	var uuid: String = str(data.get("gdtf_fixture_uuid", ""))
	if not uuid.is_empty(): row.fixture_instances[uuid] = true

# Detailed rows remain available to diagnostics/tests; normal logs contain one row per cause.
func failure_groups() -> Array:
	return _failures.values().duplicate(true)

func finish() -> void:
	var renderable: int = 0
	var fallback_only: int = 0
	for fixture: Dictionary in _fixtures.values():
		if fixture.renderable: renderable += 1
		elif fixture.fallback: fallback_only += 1
	counts["fixtures"] = _fixtures.size()
	counts["fixtures_renderable"] = renderable
	counts["fixtures_fallback_only"] = fallback_only
	counts["fixtures_missing"] = _fixtures.size() - renderable - fallback_only
	for row: Dictionary in _failures.values():
		print("[Peraviz] Asset failure source=", row.source, " type=", row.fixture_type, " model=", row.model, " reference=", row.reference, " path=", row.path, " format=", row.format, " stage=", row.stage, " reason=", row.reason, " occurrences=", row.occurrences, " affected_fixtures=", row.fixture_instances.size())
	print("[Peraviz] Scene geometry summary ", counts, " (visibility is a scene-tree/bounds check, not a pixel/occlusion test)")
