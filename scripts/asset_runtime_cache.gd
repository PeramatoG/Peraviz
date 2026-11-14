extends RefCounted
class_name PeravizRuntimeAssetCache

var derived_lods = preload("res://scripts/scene_loading/runtime_mesh_lod_cache.gd").new()

# Raw imported meshes/materials are immutable during setup. Instance optics retain
# their existing independent material path; these caches retire with the scene.
var geometry_facts: Dictionary = {}
var model_inspection_metrics: Dictionary = {}
var _static_double_sided: Dictionary = {}
var _mesh_cache: Dictionary = {}
var _scene_cache: Dictionary = {}
var _material_cache: Dictionary = {}
var _failed_paths: Dictionary = {}

var _hit_count: int = 0
var _miss_count: int = 0

var _hit_by_kind: Dictionary = {
	"mesh": 0,
	"scene": 0,
	"material": 0,
}
var _miss_by_kind: Dictionary = {
	"mesh": 0,
	"scene": 0,
	"material": 0,
}

var _debug_logging_enabled: bool = false
var _debug_log_interval: int = 50

func configure_debug_logging(enabled: bool, log_interval: int = 50) -> void:
	_debug_logging_enabled = enabled
	_debug_log_interval = max(log_interval, 1)

func clear() -> void:
	derived_lods.clear()
	geometry_facts.clear()
	model_inspection_metrics.clear()
	_static_double_sided.clear()
	_mesh_cache.clear()
	_scene_cache.clear()
	_material_cache.clear()
	_failed_paths.clear()
	_hit_count = 0
	_miss_count = 0
	for kind in _hit_by_kind.keys():
		_hit_by_kind[kind] = 0
	for kind in _miss_by_kind.keys():
		_miss_by_kind[kind] = 0

# Only ordinary opaque scenery can reuse this prepared material. Returning null
# keeps the existing per-instance preparation for mutable/special material state.
func static_double_sided(source: Material) -> Material:
	if source != null and (not source is StandardMaterial3D or source.resource_local_to_scene or source.emission_enabled or source.next_pass != null or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED): return null
	var key: Variant = source if source != null else "default"
	if _static_double_sided.has(key): return _static_double_sided[key]
	if source != null:
		for slot in range(BaseMaterial3D.TEXTURE_MAX):
			var texture: Texture2D = source.get_texture(slot)
			if texture != null and (texture.resource_local_to_scene or texture is ViewportTexture or texture is AnimatedTexture): return null
	var prepared: StandardMaterial3D = source.duplicate(false) if source != null else StandardMaterial3D.new()
	prepared.cull_mode = BaseMaterial3D.CULL_DISABLED
	_static_double_sided[key] = prepared
	return prepared

func get_mesh(asset_path: String) -> Mesh:
	if _failed_paths.has(asset_path):
		_register_miss("mesh", asset_path)
		return null
	var cached: Variant = _mesh_cache.get(asset_path)
	if cached is Mesh:
		_register_hit("mesh", asset_path)
		return cached
	_register_miss("mesh", asset_path)
	return null

func store_mesh(asset_path: String, mesh: Mesh) -> void:
	if asset_path.is_empty() or mesh == null:
		return
	_mesh_cache[asset_path] = mesh

func instantiate_scene(asset_path: String) -> Node3D:
	if _failed_paths.has(asset_path):
		_register_miss("scene", asset_path)
		return null
	var cached: Variant = _scene_cache.get(asset_path)
	if cached is PackedScene:
		_register_hit("scene", asset_path)
		var instance: Node = cached.instantiate()
		if instance is Node3D:
			return instance
		instance.free()
	_register_miss("scene", asset_path)
	return null

func store_scene(asset_path: String, packed_scene: PackedScene) -> void:
	if asset_path.is_empty() or packed_scene == null:
		return
	_scene_cache[asset_path] = packed_scene

func get_material(asset_path: String, clone_for_instance: bool = true) -> Material:
	if _failed_paths.has(asset_path):
		_register_miss("material", asset_path)
		return null
	var cached: Variant = _material_cache.get(asset_path)
	if cached is Material:
		_register_hit("material", asset_path)
		if clone_for_instance:
			return cached.duplicate(true)
		return cached
	_register_miss("material", asset_path)
	return null

func store_material(asset_path: String, material: Material) -> void:
	if asset_path.is_empty() or material == null:
		return
	_material_cache[asset_path] = material

func is_failed(asset_path: String) -> bool:
	return _failed_paths.has(asset_path)

func failure_reason(asset_path: String) -> String:
	return str(_failed_paths.get(asset_path, {}).get("reason", ""))

func failure_stage(asset_path: String) -> String:
	return str(_failed_paths.get(asset_path, {}).get("stage", "decoding"))

func mark_failed(asset_path: String, reason: String = "resource_load_failed", stage: String = "decoding") -> void:
	if not asset_path.is_empty():
		_failed_paths[asset_path] = {"reason": reason, "stage": stage}

func debug_summary() -> Dictionary:
	return {
		"hits": _hit_count,
		"misses": _miss_count,
		"hits_by_kind": _hit_by_kind.duplicate(true),
		"misses_by_kind": _miss_by_kind.duplicate(true),
		"unique_resources": _mesh_cache.size() + _scene_cache.size() + _material_cache.size() + _static_double_sided.size(),
		"static_material_unique": _static_double_sided.size(),
		"inspected_mesh_unique": geometry_facts.size(),
		"mesh_unique": _mesh_cache.size(),
		"failed_unique": _failed_paths.size(),
		"scene_unique": _scene_cache.size(),
		"material_unique": _material_cache.size(),
	}

func _register_hit(kind: String, asset_path: String) -> void:
	_hit_count += 1
	_hit_by_kind[kind] = int(_hit_by_kind.get(kind, 0)) + 1
	_log_lookup_event("hit", kind, asset_path)

func _register_miss(kind: String, asset_path: String) -> void:
	_miss_count += 1
	_miss_by_kind[kind] = int(_miss_by_kind.get(kind, 0)) + 1
	_log_lookup_event("miss", kind, asset_path)

func _log_lookup_event(event_kind: String, asset_kind: String, asset_path: String) -> void:
	if not _debug_logging_enabled:
		return

	var should_log: bool = (_hit_count + _miss_count) % _debug_log_interval == 0
	if not should_log and _failed_paths.has(asset_path):
		should_log = true
	if not should_log:
		return

	print("[PeravizAssetCache] event=", event_kind,
		" kind=", asset_kind,
		" key=", asset_path,
		" hits=", _hit_count,
		" misses=", _miss_count,
		" interval=", _debug_log_interval)
