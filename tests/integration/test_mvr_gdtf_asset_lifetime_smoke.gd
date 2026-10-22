extends SceneTree

const NodeFactoryScript = preload("res://scripts/scene_loading/node_factory.gd")
const AssetCacheScript = preload("res://scripts/asset_runtime_cache.gd")
const GoboRegistryScript = preload("res://scripts/runtime/native_gobo_resource_registry.gd")

func _init() -> void:
	var mvr_path: String = _argument_value("--mvr")
	if mvr_path.is_empty():
		push_error("Usage: Godot --headless --path . --script res://tests/integration/test_mvr_gdtf_asset_lifetime_smoke.gd -- --mvr <fixture.mvr>")
		quit(2)
		return
	var loader := PeravizLoader.new()
	var nodes: Array = loader.load_mvr(mvr_path, false, false)
	var fixture_asset_paths: PackedStringArray = []
	for item in nodes:
		if item is Dictionary:
			var path: String = str(item.get("asset_path", ""))
			if not path.is_empty():
				fixture_asset_paths.append(path)
				if not FileAccess.file_exists(path):
					push_error("path_missing_before_godot_load: %s" % path)
					quit(1)
					return
	var root := Node3D.new()
	get_root().add_child(root)
	var node_index: Dictionary = {}
	var factory: RefCounted = NodeFactoryScript.new()
	var asset_cache: RefCounted = AssetCacheScript.new()
	await factory.build_node_tree(nodes, root, node_index, func() -> void: pass, loader, asset_cache)
	if fixture_asset_paths.size() < 4 or int(asset_cache.debug_summary().get("scene_unique", 0)) < 1:
		push_error("Production NodeFactory did not instantiate every repeated fixture model.")
		quit(1)
		return
	if not _verify_models(nodes, node_index):
		quit(1)
		return
	var direct: Dictionary = loader.load_3ds_mesh_data(mvr_path.get_base_dir().path_join("directñ模型.3ds"))
	if not direct.get("ok", false) or direct.vertices.size() != 6 or direct.indices != PackedInt32Array([0, 1, 2, 3, 4, 5]) or direct.vertices[1] != Vector3(1, 0, 0) or not str(direct.texture_path).ends_with("texturañ.png") or direct.texcoords.size() != 6 or not direct.has_material_base_color:
		push_error("Direct Unicode 3DS geometry or multi-object offsets are wrong: %s" % direct)
		quit(1)
		return
	var ascii_direct: Dictionary = loader.load_3ds_mesh_data(mvr_path.get_base_dir().path_join("direct.3ds"))
	if not ascii_direct.get("ok", false) or ascii_direct.vertices != direct.vertices or ascii_direct.indices != direct.indices:
		push_error("Direct ASCII and Unicode 3DS geometry differ")
		quit(1)
		return
	var expected_failures: Dictionary = {"absent.3ds": "file_missing", "corrupt.3ds": "invalid_3ds", "empty.3ds": "no_renderable_geometry", "truncated.3ds": "invalid_3ds", "short_chunk.3ds": "invalid_3ds"}
	for failure: String in expected_failures:
		var result: Dictionary = loader.load_3ds_mesh_data(mvr_path.get_base_dir().path_join(failure))
		if result.get("ok", true) or result.get("error", "") != expected_failures[failure]:
			push_error("Incorrect 3DS failure: %s" % result)
			quit(1)
			return
	var failed_root := Node3D.new()
	get_root().add_child(failed_root)
	var failed_path: String = mvr_path.get_base_dir().path_join("corrupt.3ds")
	await factory.build_node_tree([
		{"node_id": "failure-one", "asset_path": failed_path},
		{"node_id": "failure-two", "asset_path": failed_path}], failed_root, {}, func() -> void: pass, loader, asset_cache)
	if (factory.asset_load_summary.success != 0 or factory.asset_load_summary.failure != 2 or factory.asset_load_summary.fallback != 2) or asset_cache.failure_reason(failed_path) != "invalid_3ds":
		push_error("Repeated failures were not aggregated with native reasons")
		quit(1)
		return
	failed_root.free()
	var compiled: Dictionary = loader.compile_visual_runtime_scene(0)
	var gobo_assets: Array = compiled.get("gobo_assets", [])
	var valid_gobos: int = 0
	for item in gobo_assets:
		if item is Dictionary and int(item.get("gobo_asset_id", 0)) > 0:
			var path: String = str(item.get("extracted_media_path", ""))
			if not FileAccess.file_exists(path):
				push_error("Native gobo path disappeared during runtime compilation: %s" % path)
				quit(1)
				return
			valid_gobos += 1
	var gobo_registry: RefCounted = GoboRegistryScript.new()
	gobo_registry.install_assets(gobo_assets)
	if valid_gobos < 2 or int(asset_cache.debug_summary().get("scene_unique", 0)) < 1:
		push_error("Runtime compilation or gobo installation invalidated fixture models.")
		quit(1)
		return
	if not _verify_models(nodes, node_index):
		quit(1)
		return
	print("MVR/GDTF active-scene asset lifetime smoke test passed. models=", fixture_asset_paths.size(), " gobos=", valid_gobos)
	var signature: Array = []
	for item: Dictionary in nodes:
		signature.append([item.node_id, item.parent_id, item.name, item.asset_reference, item.gdtf_geometry_key, item.pos])
	if not str(signature).contains("Escena ñ 模型") or not str(signature).contains("baseñ模型"):
		push_error("UTF-8 metadata did not round-trip through GDExtension")
		quit(1)
		return
	print("Geometry identity signature=", signature)
	var replacement: Array = loader.load_mvr(mvr_path, false, false)
	if replacement.size() != nodes.size() or not _verify_models(nodes, node_index):
		push_error("Equivalent scene replacement invalidated instantiated meshes")
		quit(1)
		return
	for item: Dictionary in replacement:
		if not str(item.asset_path).is_empty() and not fixture_asset_paths.has(item.asset_path):
			push_error("Equivalent scene replacement failed to share extracted identity")
			quit(1)
			return
	loader.free()
	for path: String in fixture_asset_paths:
		if FileAccess.file_exists(path):
			push_error("Unload retained extracted resources without an owner")
			quit(1)
			return
	if not _verify_models(nodes, node_index):
		quit(1)
		return
	gobo_registry = null
	asset_cache.clear()
	root.free()
	quit(0)

func _collect_visual_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	for child in node.get_children():
		if child.has_meta("peraviz_type"):
			continue
		if child is MeshInstance3D:
			meshes.append(child)
		_collect_visual_meshes(child, meshes)

func _verify_models(nodes: Array, node_index: Dictionary) -> bool:
	var checked: int = 0
	var shared: Dictionary = {}
	for item: Dictionary in nodes:
		var path: String = item.get("asset_path", "")
		if path.is_empty():
			continue
		var node: Node3D = node_index[item.node_id]
		var meshes: Array[MeshInstance3D] = []
		_collect_visual_meshes(node, meshes)
		if meshes.is_empty():
			push_error("Expected embedded geometry is absent: %s" % path)
			return false
		for mesh_node: MeshInstance3D in meshes:
			if mesh_node.get_meta("peraviz_dummy_placeholder", false) or mesh_node.mesh == null or mesh_node.mesh.get_surface_count() < 1 or mesh_node.mesh.surface_get_array_len(0) < 3:
				push_error("Expected real renderable surface, got placeholder/empty mesh: %s" % path)
				return false
			if path.ends_with(".3ds"):
				if shared.has(path) and shared[path] != mesh_node.mesh:
					push_error("Repeated model failed to share its ArrayMesh")
					return false
				shared[path] = mesh_node.mesh
		checked += 1
	if checked != 5:
		push_error("Expected four fixture models and one Geometry3D, got %d" % checked)
		return false
	return true

func _argument_value(name: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return ""
