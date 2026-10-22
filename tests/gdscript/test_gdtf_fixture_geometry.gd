extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()
var app: Node

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path: String = ProjectSettings.globalize_path("user://synthetic_fixture_geometryñ.mvr")
	var generated: int = OS.execute("python3", PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_gdtf_geometry_fixture.py"), path]))
	test.check(generated == 0, "Synthetic nested geometry fixture generates")
	app = load("res://test.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var result: Dictionary = await app._load_mvr_scene(path, "mvr", false)
	test.check(result.get("ok", false), "Full production scene setup completes")
	await process_frame
	if not result.get("ok", false):
		app.queue_free()
		await process_frame
		test.finish(self)
		return
	var index: Dictionary = app._node_index
	var base: Node3D = _geometry(index, "complete-one/Base")
	var yoke: Node3D = _geometry(index, "complete-one/Base/Yoke")
	var head: Node3D = _geometry(index, "complete-one/Base/Yoke/Head")
	var referenced: Node3D = _geometry(index, "complete-one/Base/Copy/Module")
	test.check(base != null and yoke != null and head != null and referenced != null, "Selected root, nested axis/head and GeometryReference keep exact geometry keys")
	if base != null and yoke != null and head != null and referenced != null:
		_check_bounds(base, Vector3(0.4, 0.2, 0.3), Vector3(-0.2, -0.1, -0.15))
		_check_bounds(yoke, Vector3(0.2, 0.6, 0.4), Vector3(1.0 / 15.0, 0.6, 0.5))
		_check_bounds(head, Vector3(0.1, 0.3, 0.2), Vector3(-0.05, -0.15, -0.1))
		_check_bounds(referenced, Vector3(0.1, 0.3, 0.2), Vector3(-0.05, -0.15, -0.1))
		test.check(base.position.is_equal_approx(Vector3(0.1, 0.3, -0.2)), "GDTF source meters and axis mapping are applied once")
		test.check(base.global_position.is_equal_approx(Vector3(1.1, 3.3, -2.2)), "MVR placement and GDTF local placement compose once")
		test.check(yoke.global_position.is_equal_approx(Vector3(1.1, 3.6, -2.2)), "Nested Yoke remains relative to Base")
		test.check(head.global_position.is_equal_approx(Vector3(1.1, 3.6, -2.4)), "Head placement survives full registration")
		test.check(referenced.position.is_equal_approx(Vector3(0.5, 0.1, 0)), "Reference placement composes with referenced geometry placement")
		var embedded: Array[Node] = yoke.find_children("EmbeddedRoot", "Node3D", true, false)
		var rotated: Array[Node] = yoke.find_children("EmbeddedRotation", "Node3D", true, false)
		var mirrored: Array[Node] = yoke.find_children("EmbeddedMirror", "Node3D", true, false)
		test.check(embedded.size() == 1 and rotated.size() == 1 and mirrored.size() == 1, "GLB scene hierarchy remains attached")
		if embedded.size() == 1:
			test.check(embedded[0].scale.is_equal_approx(Vector3.ONE * 0.001) and embedded[0].position == Vector3(1, 2, 3), "Embedded GLB scale/translation are retained")
		if mirrored.size() == 1: test.check(mirrored[0].scale.x < 0, "Embedded negative scale survives")
		var base_meshes: Array[MeshInstance3D] = _meshes(base)
		var head_meshes: Array[MeshInstance3D] = _meshes(head)
		var repeated_meshes: Array[MeshInstance3D] = _meshes(_geometry(index, "complete-two/Base"))
		if not base_meshes.is_empty() and not head_meshes.is_empty() and not repeated_meshes.is_empty():
			test.check(base_meshes[0].mesh == head_meshes[0].mesh and base_meshes[0].mesh == repeated_meshes[0].mesh, "Different dimensions and instances share unmodified raw 3DS meshes")
	for uuid: String in ["partial-one", "partial-two"]:
		var missing: Node3D = _geometry(index, uuid + "/Base")
		var partial_head: Node3D = _geometry(index, uuid + "/Base/Yoke/Head")
		var fallback: Node3D = missing.get_meta("peraviz_model_visual", null)
		test.check(fallback != null and fallback.is_visible_in_tree() and fallback.get_meta("peraviz_model_fallback", false), "Missing Base remains represented beside its successfully loaded children")
		if fallback is MeshInstance3D:
			test.check(fallback.material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and fallback.material_override.albedo_color.a < 0.25, "Partial fallback is translucent so loaded children remain visible")
		test.check(not _meshes(partial_head).is_empty(), "Partial fixture retains actual child geometry")
	var primitive: Node3D = _geometry(index, "primitive/Base")
	_check_bounds(primitive, Vector3(0.1, 0.3, 0.2), Vector3(-0.05, -0.15, -0.1))
	test.check(not primitive.get_meta("peraviz_model_visual").get_meta("peraviz_model_fallback", false), "Declared primitive-only fixture is real geometry, not a failure fallback")
	for id: String in index:
		var node: Node3D = index[id]
		if id.begins_with("stage/") or id.begins_with("truss/"):
			_check_bounds(node, Vector3(0.2, 0.6, 0.4), Vector3(-0.1, -0.3, -0.2))
		if id.begins_with("stage-glb/") or id.begins_with("truss-glb/"):
			_check_bounds(node, Vector3(3, 2, 2), Vector3(1, 2, 2.5))
	var groups: Array = app._node_factory.asset_diagnostics.failure_groups()
	test.check(groups.size() == 1, "Repeated missing resource creates one diagnostic group")
	if groups.size() == 1:
		var failure: Dictionary = groups[0]
		test.check(failure.model == "Body" and failure.reference == "genuinely_missing.1" and failure.stage == "resolution" and failure.reason == "resource_not_found", "Failure carries original model, reference, stage and reason")
		test.check(not failure.source.is_empty() and failure.fixture_type == "Synthetic Geometry" and failure.fixture_instances.size() == 2 and failure.occurrences == 2, "Failure identifies source/type and counts distinct affected instances")
	var summary: Dictionary = app._node_factory.asset_load_summary
	test.check(summary.failure == 2 and summary.fallback == 2 and summary.fixtures_renderable == 5 and summary.fixtures_missing == 0 and summary.fixtures_visible == 5 and summary.invalid_world_bounds == 0 and summary.visibility_audited_after_activation, "Full scene setup reports actual model and per-fixture outcomes")
	app._clear_scene()
	app.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(path)
	test.finish(self)

func _geometry(index: Dictionary, key: String) -> Node3D:
	for node: Node3D in index.values():
		if str(node.get_meta("peraviz_gdtf_geometry_key", "")) == key: return node
	return null

func _meshes(node: Node3D) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node == null: return result
	for child in node.get_children():
		if child.has_meta("peraviz_type"): continue
		if child is MeshInstance3D and child.mesh != null and not child.get_meta("peraviz_dummy_placeholder", false): result.append(child)
		if child is Node3D: result.append_array(_meshes(child))
	return result

# Independent expectations use known fixture dimensions and explicit accumulated transforms.
func _check_bounds(node: Node3D, expected_size: Vector3, expected_position: Vector3) -> void:
	test.check(node != null, "Expected geometry is present")
	if node == null: return
	var meshes: Array[MeshInstance3D] = _meshes(node)
	test.check(not meshes.is_empty(), "Expected geometry has actual renderable surfaces")
	var bounds := AABB()
	var first: bool = true
	for mesh: MeshInstance3D in meshes:
		test.check(mesh.is_visible_in_tree() and mesh.mesh.get_surface_count() > 0, "Mesh remains attached and visible after full scene setup")
		var local_bounds: AABB = (node.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		bounds = local_bounds if first else bounds.merge(local_bounds)
		first = false
	test.check((bounds.size - expected_size).length() < 0.0001, "Geometry size matches declared meters: %s expected=%s actual=%s" % [node.name, expected_size, bounds.size])
	test.check((bounds.position - expected_position).length() < 0.0001, "Authored model origin and embedded transforms are preserved: %s expected=%s actual=%s" % [node.name, expected_position, bounds.position])
