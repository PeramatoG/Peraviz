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
	factory.build_node_tree(nodes, root, node_index, func() -> void: pass, loader, asset_cache)
	if fixture_asset_paths.size() < 4 or int(asset_cache.debug_summary().get("scene_unique", 0)) < 2:
		push_error("Production NodeFactory did not instantiate every repeated fixture model.")
		quit(1)
		return
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
	if valid_gobos < 2 or int(asset_cache.debug_summary().get("scene_unique", 0)) < 2:
		push_error("Runtime compilation or gobo installation invalidated fixture models.")
		quit(1)
		return
	print("MVR/GDTF active-scene asset lifetime smoke test passed. models=", fixture_asset_paths.size(), " gobos=", valid_gobos)
	root.queue_free()
	quit(0)

func _argument_value(name: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == name:
			return args[index + 1]
	return ""
