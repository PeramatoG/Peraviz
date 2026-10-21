extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()
var app: Node
var loading_frames: int = 0
var cancel_after: int = -1
var cancel_during_render: bool = false
var rejected_overlap: bool = false
var observed_phases: Dictionary = {}
var rendering_kept_gated: bool = true

func _initialize() -> void:
	call_deferred("_run")

func _heartbeat() -> void:
	if not is_instance_valid(app) or not app._scene_loading: return
	loading_frames += 1
	for child in app.get_children():
		if child.get_script() == preload("res://scripts/scene_loading/scene_loading_overlay.gd"):
			observed_phases[child._phase_label.text] = true
			if child._phase_label.text == "Activating scene visuals…":
				rendering_kept_gated = rendering_kept_gated and app._scene_loading and child.get_child(0).color.a == 1.0
				if cancel_during_render:
					cancel_during_render = false
					app._clear_scene()
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
	test.check(efficient.get_load_phase() == "node_payload", "Completed native worker exposes final atomic progress phase")
	var nodes: Array = efficient.finish_load_mvr()
	var compiled: Dictionary = efficient.compile_visual_runtime_scene(-1)
	test.check(nodes == reference_nodes, "Exact scene graph, transforms, optics, models and UUIDs match reference")
	test.check(compiled == reference_scene, "Exact native controls, renderer manifests, resources, groups and diagnostics match reference")
	var metrics: Dictionary = efficient.get_load_metrics()
	test.check(metrics["geometry_definitions"] == 1 and metrics["geometry_template_hits"] == 19, "Twenty fixtures expand one definition")
	test.check(efficient.finish_load_mvr().is_empty(), "Completed preparation cannot be transferred twice")
	efficient.free()
	reference.free()


func _render_activation_contract() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	scene.hide()
	var shared_mesh := BoxMesh.new()
	var originals: Dictionary = {}
	for i in range(39):
		var mesh := MeshInstance3D.new()
		mesh.mesh = shared_mesh
		mesh.position = Vector3(i, i * 0.1, 0)
		mesh.visible = i != 2
		scene.add_child(mesh)
		originals[mesh] = {"visible": mesh.visible, "transform": mesh.transform, "mesh": mesh.mesh}
	var hidden_parent := Node3D.new()
	hidden_parent.hide()
	scene.add_child(hidden_parent)
	var nested := MeshInstance3D.new()
	nested.mesh = shared_mesh
	hidden_parent.add_child(nested)
	originals[nested] = {"visible": true, "transform": nested.transform, "mesh": nested.mesh}
	var budget := SceneLoadBudget.new()
	budget.tree = self
	var generation := {"valid": true}
	budget.current = func() -> bool: return generation.valid
	var steps: Array[int] = []
	budget.render_progress_changed.connect(func(completed: int, _total: int) -> void: steps.append(completed))
	var readiness := preload("res://scripts/scene_loading/scene_render_readiness.gd").new()
	test.check(await readiness.prepare_scene(scene, budget), "Staged graphics activation completes")
	test.check(steps == [16, 32, 39] and readiness.metrics.render_activation_batches == 3, "Actual visual resources activate in bounded batches")
	for node in originals:
		var state: Dictionary = originals[node]
		test.check(node.visible == state.visible and node.transform == state.transform and node.mesh == state.mesh, "Activation preserves exact local visibility, transform and resource identity")
	test.check(not hidden_parent.visible and not nested.is_visible_in_tree(), "Originally hidden ancestors remain hidden")
	scene.hide()
	budget.render_progress_changed.connect(func(_completed: int, _total: int) -> void: generation.valid = false)
	readiness = preload("res://scripts/scene_loading/scene_render_readiness.gd").new()
	test.check(not await readiness.prepare_scene(scene, budget) and not scene.visible, "Mid-activation cancellation hides the retired scene")
	for node in originals:
		test.check(node.visible == originals[node].visible, "Cancellation restores local visibility before generation cleanup")
	scene.queue_free()
	await process_frame

func _run() -> void:
	await _render_activation_contract()
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
	test.check(observed_phases.size() >= 3 and observed_phases.has("Activating scene visuals…"), "Loading feedback names changing setup and graphics phases")
	test.check(rendering_kept_gated and result["load_metrics"]["first_render_ms"] > 0, "Rendering prepares behind modal feedback before DMX readiness")
	test.check(result["load_metrics"]["max_event_loop_gap_ms"] > 0, "Telemetry includes complete render/event-loop intervals")
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
	cancel_during_render = true
	result = await app._load_mvr_scene(path, "mvr", false)
	test.check(not result.get("ok", true) and not app._scene_loading and app._node_index.is_empty(), "Cancellation during initial rendering retires partial resources and releases loading gate")
	_generate(path, "BrokenControls")
	await _equivalence(path)
	result = await app._load_mvr_scene(path, "mvr", false)
	test.check(result.get("ok", false) and result["load_metrics"]["aggregate_shaft_resources"] == 0, "Same-name revised archive and selected mode rebuild conservative unresolved-resource fallback")
	app._clear_scene()
	app.queue_free()
	await process_frame
	await process_frame
	test.finish(self)
