extends SceneTree

const Factory = preload("res://scripts/scene_loading/node_factory.gd")
const Cache = preload("res://scripts/asset_runtime_cache.gd")

func _init() -> void:
	_run.call_deferred()

func _arg(key: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == key: return args[i + 1]
	return ""

func _run() -> void:
	var app: Node = null
	var loader: PeravizLoader
	var records: Array
	var root: Node3D
	var factory: RefCounted
	var cache: RefCounted
	var index: Dictionary = {}
	if OS.get_cmdline_user_args().has("--full-setup"):
		app = load("res://test.tscn").instantiate()
		get_root().add_child(app)
		await process_frame
		var result: Dictionary = await app._load_mvr_scene(_arg("--mvr"), "mvr", false)
		if not result.get("ok", false):
			push_error("Full application setup failed: %s" % result.get("error", ""))
			quit(1)
			return
		loader = app._loader
		records = app._fixture_row_provider._loaded_nodes
		root = app.proxies_root
		factory = app._node_factory
		cache = app._asset_cache
		index = app._node_index
	else:
		loader = PeravizLoader.new()
		records = loader.load_mvr(_arg("--mvr"), false, false)
		root = Node3D.new()
		get_root().add_child(root)
		factory = Factory.new()
		cache = Cache.new()
		await factory.build_node_tree(records, root, index, func() -> void: pass, loader, cache)
	await process_frame
	var patches: Array = loader.get_fixtures_patch()
	var families: Dictionary = {}
	for patch: Dictionary in patches:
		var source: String = str(patch.gdtf_path)
		if not families.has(source): families[source] = {"instances": 0, "renderable": 0, "visible": 0, "bounds": [], "asset_failures": [], "asset_parts": 0, "real_parts": 0, "dimension_mismatches": []}
		var family: Dictionary = families[source]
		family.instances += 1
		var fixture: Node3D = index.get(str(patch.fixture_uuid))
		if fixture == null: continue
		var report: Dictionary = _inspect(fixture, false)
		if report.meshes > 0 and report.valid:
			family.renderable += 1
			if report.visible > 0: family.visible += 1
			family.bounds.append({"position": _vector(report.bounds.position), "size": _vector(report.bounds.size)})
		for record: Dictionary in records:
			if not str(record.get("gdtf_geometry_key", "")).begins_with(str(patch.fixture_uuid) + "/"): continue
			if str(record.get("asset_path", "")).is_empty() and str(record.get("primitive_type", "")).is_empty() and str(record.get("asset_error", "")).is_empty(): continue
			family.asset_parts += 1
			var geometry: Node3D = index.get(str(record.node_id))
			var part: Dictionary = _inspect(geometry, true) if geometry != null else {"meshes": 0, "valid": false}
			if part.meshes > 0 and part.valid:
				family.real_parts += 1
				var dimensions: Vector3 = record.get("model_dimensions", Vector3.ZERO)
				var expected := Vector3(dimensions.x, dimensions.z, dimensions.y)
				var local_part: Dictionary = _inspect(geometry, true, geometry.global_transform.affine_inverse())
				for axis in range(3):
					if expected[axis] > 0 and abs(local_part.bounds.size[axis] - expected[axis]) > maxf(0.0001, expected[axis] * 0.001):
						family.dimension_mismatches.append({"model": str(record.get("gdtf_model_name", "")), "expected": _vector(expected), "actual": _vector(local_part.bounds.size)})
						break
			var error: String = str(record.get("asset_error", ""))
			var path: String = str(record.get("asset_path", ""))
			if error.is_empty() and not path.is_empty() and part.meshes == 0: error = cache.failure_reason(path)
			if not error.is_empty(): family.asset_failures.append({"model": str(record.get("gdtf_model_name", record.name)), "reference": str(record.get("asset_reference", "")), "path": path, "reason": error})
	var structures: Dictionary = {}
	for record: Dictionary in records:
		if record.get("type", "") != "model_part": continue
		var object_node: Node3D = index.get(str(record.node_id))
		if object_node == null: continue
		var object_report: Dictionary = _inspect(object_node, true)
		if object_report.meshes > 0:
			structures[str(record.node_id)] = {"position": _vector(object_report.bounds.position), "size": _vector(object_report.bounds.size), "meshes": object_report.meshes}
	var report: Dictionary = {"structures": structures, "families": families, "node_count": records.size(), "cache": cache.debug_summary()}
	if factory.get("asset_load_summary") != null: report["geometry_summary"] = factory.asset_load_summary
	if factory.get("asset_diagnostics") != null: report["failure_groups"] = factory.asset_diagnostics.failure_groups()
	var output := FileAccess.open(_arg("--report"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t"))
		output.close()
	var verified: bool = not families.is_empty()
	var family_index: int = 0
	for family: Dictionary in families.values():
		family_index += 1
		verified = verified and family.visible == family.instances and family.dimension_mismatches.is_empty() and family.asset_failures.is_empty()
		print("Fixture audit family=", family_index, " instances=", family.instances, " renderable=", family.renderable, " visible=", family.visible, " real_parts=", family.real_parts, "/", family.asset_parts, " failed_parts=", family.asset_failures.size(), " dimension_mismatches=", family.dimension_mismatches.size())
	if app != null:
		app._clear_scene()
		app.queue_free()
		await process_frame
		await process_frame
	else:
		root.free()
		loader.free()
	quit(0 if verified or OS.get_cmdline_user_args().has("--allow-missing") else 1)

func _vector(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

# Independent test-side bounds use actual attached mesh global transforms.
func _inspect(node: Node3D, stop_at_geometry: bool, frame: Transform3D = Transform3D.IDENTITY) -> Dictionary:
	var result: Dictionary = {"meshes": 0, "visible": 0, "valid": true, "bounds": AABB()}
	for child in node.get_children():
		if child is not Node3D or (stop_at_geometry and child.has_meta("peraviz_type")): continue
		if child is MeshInstance3D and child.mesh != null and not child.get_meta("peraviz_dummy_placeholder", false) and child.mesh.get_surface_count() > 0:
			var aabb: AABB = (frame * child.global_transform) * child.get_aabb()
			if not aabb.position.is_finite() or not aabb.size.is_finite() or aabb.size.length_squared() == 0: result.valid = false
			result.bounds = aabb if result.meshes == 0 else result.bounds.merge(aabb)
			result.meshes += 1
			if child.is_visible_in_tree(): result.visible += 1
		var nested: Dictionary = _inspect(child, stop_at_geometry, frame)
		if nested.meshes > 0:
			result.bounds = nested.bounds if result.meshes == 0 else result.bounds.merge(nested.bounds)
			result.meshes += nested.meshes
			result.visible += nested.visible
			result.valid = result.valid and nested.valid
	return result
