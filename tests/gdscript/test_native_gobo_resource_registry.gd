extends SceneTree

const RegistryScript = preload("res://scripts/runtime/native_gobo_resource_registry.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

func _init() -> void:
	var failures := PackedStringArray()
	var registry: RefCounted = RegistryScript.new()
	var paths := [_write_mask("gobo_a.png", false), _write_mask("gobo_b.png", true)]
	registry.install_assets([
		{"gobo_asset_id": 101, "wheel_id": 11, "slot_index": 1, "extracted_media_path": paths[0], "media_valid": true},
		{"gobo_asset_id": 102, "wheel_id": 12, "slot_index": 1, "extracted_media_path": paths[1], "media_valid": true},
	])
	var beam := MeshInstance3D.new()
	var light := SpotLight3D.new()
	var target := {"beam_instances": [beam], "emitter_anchors": [light]}
	var first: Dictionary = registry.apply_selection(77, 11, 1, 1, 101, 0, target)
	var first_mesh: Mesh = beam.mesh
	_check(bool(first.get("applied", false)) and first_mesh != null, "One native asset should install a normalized prism.", failures)
	var unchanged: Dictionary = registry.apply_selection(77, 11, 1, 1, 101, 0, target)
	_check(bool(unchanged.get("unchanged", false)) and beam.mesh == first_mesh, "Unchanged selection should preserve topology identity.", failures)
	registry.apply_selection(77, 12, 2, 1, 102, 0, target)
	var composed_mesh: Mesh = beam.mesh
	_check(composed_mesh != null and composed_mesh != first_mesh, "Two static wheels should create one composed topology.", failures)
	registry.apply_selection(88, 11, 1, 1, 101, 0, target)
	registry.apply_selection(88, 12, 2, 1, 102, 0, target)
	_check(beam.mesh == composed_mesh, "Equivalent fixtures should reuse composed topology.", failures)
	var counters: Dictionary = registry.counters()
	_check(int(counters.get("composed_png_generations", 0)) == 1 and int(counters.get("composed_vectorizations", 0)) == 1 and int(counters.get("composed_mesh_creations", 0)) == 1, "A unique composition should generate, vectorize, and mesh exactly once.", failures)
	_check(int(counters.get("composition_cache_hits", 0)) == 1 and int(counters.get("composed_topology_reuse", 0)) == 1, "Equivalent composition should hit both resource and topology caches.", failures)
	registry.apply_selection(77, 11, 1, 2, 0, 0, target)
	registry.apply_selection(77, 12, 2, 2, 0, 0, target)
	_check(beam.mesh == null, "Open slots should deterministically clear the prism.", failures)
	beam.free()
	light.free()
	for path in paths:
		DirAccess.remove_absolute(path)
	if failures.is_empty():
		print("Native gobo resource registry checks passed: ", counters)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _write_mask(file_name: String, invert: bool) -> String:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in range(16):
		for x in range(16):
			var inside: bool = Vector2(x - 7.5, y - 7.5).length() < (4.0 if invert else 6.0)
			var value: float = 1.0 if inside else 0.0
			image.set_pixel(x, y, Color(value, value, value, 1.0))
	var path: String = ProjectSettings.globalize_path("user://" + file_name)
	image.save_png(path)
	return path

func _check(condition: bool, message: String, failures: PackedStringArray) -> void:
	if not condition:
		failures.append(message)
