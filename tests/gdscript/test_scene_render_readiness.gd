extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
const Readiness = preload("res://scripts/scene_loading/scene_render_readiness.gd")
const Budget = preload("res://scripts/scene_loading/scene_load_budget.gd")
var test = TestCase.new()
var _binding_transaction_frames: int = 0

class LostDraws extends RefCounted:
	@warning_ignore("unused_signal")
	signal acknowledged

func _initialize() -> void:
	call_deferred("_run")

func _budget(generation: Dictionary) -> SceneLoadBudget:
	var budget := Budget.new()
	budget.tree = self
	budget.current = func() -> bool: return generation.valid
	return budget

func _scene() -> Node3D:
	var scene := Node3D.new()
	root.add_child(scene)
	scene.hide()
	var mesh := BoxMesh.new()
	for i in range(33):
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.position = Vector3(i % 6, 0, float(i) / 6.0)
		scene.add_child(visual)
	return scene

func _inspector_contract() -> void:
	var panel := preload("res://scripts/ui/fixture_inspection_panel.gd").new()
	panel.hide()
	root.add_child(panel)
	var rows: Array = []
	for i in range(82): rows.append({"fixture_uuid": str(i), "fixture_name": "Generic fixture " + str(i)})
	panel.refresh(rows)
	test.check(panel._row_labels.is_empty() and panel._pending_rows.size() == 82, "Hidden inspector stores all fixture data without allocating row Controls")
	panel.show()
	test.check(panel._row_labels.size() == 64, "Visible inspector constructs only eight rows before yielding")
	await process_frame
	panel.refresh([{"fixture_name": "Replacement"}])
	await process_frame
	test.check(panel._row_labels.size() == 8 and not panel._dirty, "A replacement generation cancels old UI batches without stale rows")
	panel.refresh(rows)
	panel.hide()
	await process_frame
	test.check(not panel._building and panel._dirty, "Hiding the inspector interrupts construction safely")
	panel.show()
	var budget := _budget({"valid": true})
	test.check(await panel.finish_visible_refresh(budget), "Import can await all visible details through the normal event loop")
	test.check(panel._row_labels.size() == 656 and not panel._dirty, "All 82 fixtures retain their eight final inspection fields")
	var retained_label: Label = panel._row_labels[0]
	panel.hide()
	panel.show()
	test.check(panel._row_labels[0] == retained_label and not panel._dirty, "Reopening completed inspection data reuses existing Controls")
	panel.queue_free()
	await process_frame

func _run() -> void:
	await _inspector_contract()
	# Normal production import, graphical when launched without --headless.
	var path := ProjectSettings.globalize_path("user://generated_readiness.mvr")
	test.check(OS.execute("python3", PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_render_group_fixture.py"), path, "--instances=1", "--wheel=basic", "--mode=BasicControls"])) == 0, "Generate one generic production fixture")
	var app: Node = load("res://test.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var observe_binding: Callable = func() -> void:
		for child in app.get_children():
			if child.get_script() == preload("res://scripts/scene_loading/scene_loading_overlay.gd"):
				if child._phase_label.text in ["Preparing renderer bindings…", "Preparing lights and lenses…", "Binding lighting resources…", "Preparing shared materials…", "Preparing combined beams…", "Installing fixture controls…"]:
					_binding_transaction_frames += 1
	process_frame.connect(observe_binding)
	var result: Dictionary = await app._load_mvr_scene(path, "mvr", false)
	process_frame.disconnect(observe_binding)
	# Only the two explicit feedback turns and the post-commit checkpoint yield.
	test.check(_binding_transaction_frames <= 4, "Renderer resources commit without yielding intermediate grouping/material state")
	var metrics: Dictionary = result.get("load_metrics", {})
	test.check(result.get("ok", false) and not app._scene_loading and not app._scene_load_failed, "Normal graphical scene readiness completes")
	test.check(metrics.get("physical_outputs", 0) == 51 and metrics.get("aggregate_shaft_resources", 0) == 1 and metrics.get("final_render_rows", 0) == 2, "Readiness preserves aggregate and physical bindings")
	if DisplayServer.get_name() != "headless":
		test.check(metrics.get("final_render_acks", 0) >= 3 and metrics.get("render_batches_acknowledged", 0) == metrics.get("render_activation_batches", -1), "Every visual batch and final barrier receive actual post-draw acknowledgments")
	# The coordinator must propagate a failed graphics barrier, not publish success.
	var never_draws := LostDraws.new()
	var failed_readiness := Readiness.new()
	failed_readiness.require_draw_ack = true
	failed_readiness.draw_ack_signal = never_draws.acknowledged
	failed_readiness.can_present = func() -> bool: return true
	failed_readiness.no_ack_timeout_us = 50000
	result = await preload("res://scripts/scene_loading/scene_import_coordinator.gd").load_scene(app, path, "mvr", false, failed_readiness)
	test.check(not result.get("ok", true) and result.get("error", "") == failed_readiness.error_message, "Coordinator propagates lost graphical readiness as failure")
	test.check(app._node_index.is_empty() and not app._scene_loading and app._scene_load_failed and not app._fixture_light_apply_service.is_dense_presentation_active(), "Failed readiness retires targets and releases loading ownership")
	app._clear_scene()
	app.queue_free()
	await process_frame

	# Model a lost callback while the real event loop keeps processing frames.
	var generation := {"valid": true}
	var budget := _budget(generation)
	var lost := LostDraws.new()
	var readiness := Readiness.new()
	readiness.require_draw_ack = true
	readiness.draw_ack_signal = lost.acknowledged
	readiness.can_present = func() -> bool: return true
	readiness.no_ack_timeout_us = 50000
	var scene := _scene()
	var heartbeats: Array[int] = [0]
	var heartbeat: Callable = func() -> void: heartbeats[0] += 1
	process_frame.connect(heartbeat)
	test.check(not await readiness.prepare_scene(scene, budget), "Missing draw acknowledgment fails instead of declaring success")
	process_frame.disconnect(heartbeat)
	test.check(heartbeats[0] > 0 and not scene.visible and not readiness.error_message.is_empty(), "Lost readiness remains responsive and hides failed generation")
	test.check(readiness.metrics.render_batches_acknowledged == 0 and lost.acknowledged.get_connections().is_empty(), "Unacknowledged batches are not complete and callback ownership is retired")
	scene.queue_free()
	await process_frame

	# A hidden/minimized window explicitly defers, and can still be cancelled.
	generation = {"valid": true}
	budget = _budget(generation)
	readiness = Readiness.new()
	readiness.require_draw_ack = true
	readiness.draw_ack_signal = lost.acknowledged
	readiness.can_present = func() -> bool: return false
	readiness.no_ack_timeout_us = 1
	var deferred: Array[bool] = [false]
	budget.phase_changed.connect(func(value: String) -> void:
		if value == "render_window_deferred":
			deferred[0] = true
			generation.valid = false)
	scene = _scene()
	test.check(not await readiness.prepare_scene(scene, budget), "Unavailable window can retire loading generation")
	test.check(deferred[0] and readiness.error_message.is_empty() and not scene.visible, "Window deferral is distinct from a drawable-window callback failure")
	scene.queue_free()
	await process_frame
	test.finish(self)
