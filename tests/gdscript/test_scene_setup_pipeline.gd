extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()
var app: Node
var loading_frames: int = 0
var cancel_after: int = -1
var rejected_overlap: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _heartbeat() -> void:
	if not is_instance_valid(app) or not app._scene_loading: return
	loading_frames += 1
	if cancel_after > 0 and loading_frames >= cancel_after:
		cancel_after = -1
		app._clear_scene()

func _overlap(path: String) -> void:
	var result: Dictionary = await app._load_mvr_scene(path, "mvr", false)
	rejected_overlap = not result.get("ok", true) and result.get("error", "") == "scene import already running"

func _generate(path: String, mode: String = "BasicControls") -> void:
	var args := PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_render_group_fixture.py"), path, "--instances=20", "--transforms", "--wheel=basic", "--mode="+mode])
	test.check(OS.execute("python3", args) == 0, "Generic scalable MVR is generated")

func _equivalence(path: String) -> void:
	var reference: Object = ClassDB.instantiate("PeravizLoader")
	OS.set_environment("PERAVIZ_SETUP_REFERENCE_GEOMETRY", "1")
	OS.set_environment("PERAVIZ_SETUP_REFERENCE_INDEXES", "1")
	var reference_nodes: Array = reference.load_mvr(path, false, false)
	var reference_scene: Dictionary = reference.compile_visual_runtime_scene(-1)
	OS.unset_environment("PERAVIZ_SETUP_REFERENCE_GEOMETRY")
	OS.unset_environment("PERAVIZ_SETUP_REFERENCE_INDEXES")
	var efficient: Object = ClassDB.instantiate("PeravizLoader")
	test.check(efficient.begin_load_mvr(path, -1), "CPU preparation starts exactly once")
	test.check(not efficient.begin_load_mvr(path, -1), "Concurrent task on one native loader is rejected")
	while not efficient.is_load_mvr_ready(): await process_frame
	var nodes: Array = efficient.finish_load_mvr()
	var compiled: Dictionary = efficient.compile_visual_runtime_scene(-1)
	test.check(nodes == reference_nodes, "Exact scene graph, transforms, optics, models and UUIDs match reference")
	test.check(compiled == reference_scene, "Exact native controls, renderer manifests, resources, groups and diagnostics match reference")
	var metrics: Dictionary = efficient.get_load_metrics()
	test.check(metrics["geometry_definitions"] == 1 and metrics["geometry_template_hits"] == 19, "Twenty fixtures expand one definition")
	test.check(efficient.finish_load_mvr().is_empty(), "Completed preparation cannot be transferred twice")
	efficient.free()
	reference.free()

func _run() -> void:
	var path: String = ProjectSettings.globalize_path("user://generated_scene_setup.mvr")
	_generate(path)
	await _equivalence(path)
	app = load("res://test.tscn").instantiate()
	root.add_child(app)
	await process_frame
	process_frame.connect(_heartbeat)
	call_deferred("_overlap", path)
	var result: Dictionary = await app._load_mvr_scene(path, "mvr", false)
	test.check(result.get("ok", false) and rejected_overlap, "Normal import completes and rejects overlapping scene requests")
	test.check(loading_frames >= 10 and result["load_metrics"]["yielded_frames"] >= 10, "Main event loop processes frames throughout import")
	test.check(result["load_metrics"]["physical_outputs"] == 1020 and result["load_metrics"]["final_render_rows"] == 40, "Physical projected and emission-only outputs survive normal aggregate binding")
	test.check(app.proxies_root.visible and not app._scene_loading, "Ready scene becomes visible only after registration")
	var registry: RefCounted = app._native_target_registry
	for key in registry._geometry_targets_by_key:
		registry._indexed_setup = true
		var indexed: Array = registry._collect_descendant_emitters(key)
		registry._indexed_setup = false
		test.check(indexed == registry._collect_descendant_emitters(key), "Godot ancestry index preserves exact ordered emitter bindings")
	registry._indexed_setup = true
	var fixture: Node3D = app._node_index["source-20"]
	test.check(is_equal_approx(fixture.position.length(), Vector3(19,1.9,0).length()), "MVR instance translation remains distinct from geometry-local template transforms")
	loading_frames = 0
	cancel_after = 5
	result = await app._load_mvr_scene(path, "mvr", false)
	test.check(not result.get("ok", true) and app._node_index.is_empty(), "Cancellation drains CPU preparation and retires partial targets")
	_generate(path, "BrokenControls")
	await _equivalence(path)
	result = await app._load_mvr_scene(path, "mvr", false)
	test.check(result.get("ok", false) and result["load_metrics"]["aggregate_shaft_resources"] == 0, "Same-name revised archive and selected mode rebuild conservative unresolved-resource fallback")
	app._clear_scene()
	app.queue_free()
	await process_frame
	await process_frame
	test.finish(self)
