extends RefCounted

const MAX_BATCH_SIZE: int = 16
var _presented_frames: int = 0
var metrics: Dictionary = {"render_activation_instances": 0, "render_activation_batches": 0, "max_render_activation_batch_ms": 0.0}

# Activate bounded visual batches, rather than sending the entire hidden scene to
# the graphics backend in one frame. Local visibility is restored exactly; no
# fixture/control/optical data or permanent render resources are replaced.
func prepare_scene(scene: Node3D, budget: SceneLoadBudget) -> bool:
	budget.phase = "first_render"
	var visuals: Array[VisualInstance3D] = []
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is VisualInstance3D and node.visible:
			visuals.append(node)
			node.hide()
		for child in node.get_children(): pending.append(child)
		if not await budget.checkpoint():
			_restore_hidden(scene, visuals)
			return false
	metrics["render_activation_instances"] = visuals.size()
	if not budget.valid():
		_restore_hidden(scene, visuals)
		return false
	scene.show()
	var cursor: int = 0
	while cursor < visuals.size() and budget.valid():
		var batch_started := Time.get_ticks_usec()
		var end := mini(cursor + MAX_BATCH_SIZE, visuals.size())
		while cursor < end:
			if is_instance_valid(visuals[cursor]): visuals[cursor].show()
			cursor += 1
		budget.render_progress_changed.emit(cursor, visuals.size())
		if not await _wait_for_frames(budget, 1): break
		var batch_ms := (Time.get_ticks_usec() - batch_started) / 1000.0
		metrics["render_activation_batches"] += 1
		metrics["max_render_activation_batch_ms"] = maxf(metrics["max_render_activation_batch_ms"], batch_ms)
	if not budget.valid():
		_restore_hidden(scene, visuals)
		return false
	return await _wait_for_frames(budget, 3)

# Cancellation hides the retired generation before restoring its local flags.
func _restore_hidden(scene: Node3D, visuals: Array[VisualInstance3D]) -> void:
	if is_instance_valid(scene): scene.hide()
	for visual in visuals:
		if is_instance_valid(visual): visual.show()

# process_frame precedes rendering, so graphical batches use actual submissions.
# Poll through the event loop to retain cancellation even for a minimized window.
func _wait_for_frames(budget: SceneLoadBudget, count: int) -> bool:
	if DisplayServer.get_name() == "headless":
		return await budget.checkpoint(true)
	_presented_frames = 0
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	while _presented_frames < count and budget.valid():
		await budget.checkpoint(true)
	RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	return budget.valid()

func _on_frame_post_draw() -> void:
	_presented_frames += 1
