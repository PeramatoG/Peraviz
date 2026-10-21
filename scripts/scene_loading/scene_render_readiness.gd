extends RefCounted

const MAX_BATCH_SIZE: int = 16
# An absent callback must fail while drawable, never publish false readiness.
# This watchdog cannot interrupt an engine/driver call blocking the main thread.
var no_ack_timeout_us: int = 15000000
var require_draw_ack: bool = DisplayServer.get_name() != "headless"
var draw_ack_signal: Signal = RenderingServer.frame_post_draw
var can_present: Callable = DisplayServer.window_can_draw
var error_message: String = ""
var _acknowledgments: int = 0
var _budget: SceneLoadBudget
var _trace_next_draw: bool = false
var _trace_next_ack: bool = false
var _waiting_final: bool = false
var _final_draw_breadcrumbs: int = 0
var _window_breadcrumbs: int = 0
var metrics: Dictionary = {
	"render_activation_instances": 0, "render_instances_activated": 0,
	"render_ack_required": false, "render_headless_batches": 0,
	"render_draw_submissions": 0, "render_window_deferred_ms": 0.0,
	"render_activation_batches": 0, "render_batches_acknowledged": 0,
	"render_post_draw_acks": 0, "max_render_activation_batch_ms": 0.0,
	"final_render_wait_ms": 0.0, "final_render_acks": 0,
}

# Keep local visibility and resources intact while distributing first visibility.
# Counts of activated instances and submitted batches are not render completion.
func prepare_scene(scene: Node3D, budget: SceneLoadBudget) -> bool:
	budget.phase = "first_render"
	budget.breadcrumb("render_collect_begin")
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
	metrics["render_ack_required"] = require_draw_ack
	budget.breadcrumb("render_root_show_begin", metrics)
	if not budget.valid():
		_restore_hidden(scene, visuals)
		return false
	if require_draw_ack:
		_budget = budget
		RenderingServer.frame_pre_draw.connect(_on_frame_pre_draw)
		draw_ack_signal.connect(_on_frame_post_draw)
	scene.show()
	budget.breadcrumb("render_root_show_end")
	var cursor: int = 0
	var next_breadcrumb: int = 0
	while cursor < visuals.size() and budget.valid():
		var batch_started := Time.get_ticks_usec()
		var end := mini(cursor + MAX_BATCH_SIZE, visuals.size())
		# First, midpoint and final batch only; never per-node logging.
		var trace_batch: bool = cursor >= next_breadcrumb or end == visuals.size()
		if trace_batch:
			next_breadcrumb = end + maxi(1, (visuals.size() >> 1))
			budget.breadcrumb("render_batch_activate_begin", metrics)
		while cursor < end:
			if is_instance_valid(visuals[cursor]): visuals[cursor].show()
			cursor += 1
		metrics["render_instances_activated"] = cursor
		metrics["render_activation_batches"] += 1
		# Display only the last acknowledged batch, never queued work as 100%.
		if trace_batch:
			budget.breadcrumb("render_batch_wait_begin", metrics)
			_trace_next_draw = true
		if not await _wait_for_frames(budget, 1): break
		var batch_ms := (Time.get_ticks_usec() - batch_started) / 1000.0
		metrics["max_render_activation_batch_ms"] = maxf(metrics["max_render_activation_batch_ms"], batch_ms)
		if require_draw_ack: metrics["render_batches_acknowledged"] += 1
		else: metrics["render_headless_batches"] += 1
		budget.report_render_progress(cursor, visuals.size())
		if trace_batch: budget.breadcrumb("render_batch_ack", metrics)
	var ready: bool = budget.valid() and error_message.is_empty()
	if ready:
		budget.phase = "render_completion"
		budget.breadcrumb("render_final_wait_begin", metrics)
		_trace_next_draw = true
		var final_started := Time.get_ticks_usec()
		var initial_acks: int = _acknowledgments
		_waiting_final = true
		ready = await _wait_for_frames(budget, 3)
		_waiting_final = false
		metrics["final_render_wait_ms"] = (Time.get_ticks_usec() - final_started) / 1000.0
		metrics["final_render_acks"] = _acknowledgments - initial_acks
		budget.breadcrumb("render_final_wait_end", metrics)
	if require_draw_ack:
		draw_ack_signal.disconnect(_on_frame_post_draw)
		RenderingServer.frame_pre_draw.disconnect(_on_frame_pre_draw)
		_budget = null
	if not ready: _restore_hidden(scene, visuals)
	return ready

# Retired resources cannot become visible during restoration or failure cleanup.
func _restore_hidden(scene: Node3D, visuals: Array[VisualInstance3D]) -> void:
	if is_instance_valid(scene): scene.hide()
	for visual in visuals:
		if is_instance_valid(visual): visual.show()

# A global post-draw acknowledgment follows the engine's draw/end_frame path;
# it is not a GPU fence. Hidden/minimized windows explicitly defer readiness.
func _wait_for_frames(budget: SceneLoadBudget, count: int) -> bool:
	if not require_draw_ack:
		return await budget.checkpoint(true)
	var first_ack: int = _acknowledgments
	var remaining_us: int = no_ack_timeout_us
	var previous_us: int = Time.get_ticks_usec()
	var previous_ack: int = first_ack
	var deferred: bool = false
	var wait_phase: String = budget.phase
	while _acknowledgments - first_ack < count and budget.valid():
		var drawable: bool = bool(can_present.call())
		var now: int = Time.get_ticks_usec()
		if drawable:
			remaining_us -= now - previous_us
			if _acknowledgments != previous_ack: remaining_us = no_ack_timeout_us
			if remaining_us <= 0:
				error_message = "No render acknowledgment while the window was drawable; scene readiness was not confirmed."
				budget.breadcrumb("render_wait_failed", metrics)
				return false
		else:
			metrics["render_window_deferred_ms"] += (now - previous_us) / 1000.0
		if deferred == drawable:
			deferred = not drawable
			budget.phase = "render_window_deferred" if deferred else wait_phase
			if _window_breadcrumbs < 4:
				_window_breadcrumbs += 1
				budget.breadcrumb("render_window_deferred" if deferred else "render_window_resumed", metrics)
		previous_us = now
		previous_ack = _acknowledgments
		await budget.checkpoint(true)
	if deferred: budget.phase = wait_phase
	return budget.valid()

func _on_frame_post_draw() -> void:
	if bool(can_present.call()):
		_acknowledgments += 1
		metrics["render_post_draw_acks"] = _acknowledgments
		if _waiting_final: metrics["final_render_acks"] += 1
		if _trace_next_ack or (_waiting_final and metrics["final_render_acks"] == 3):
			_trace_next_ack = false
			_budget.breadcrumb("render_frame_post_draw_ack", metrics)

# Godot emits pre_draw after Main::iteration's RenderingServer::sync and before
# RenderingServerDefault::_draw. A missing post_draw after this marker bounds a
# stall to the engine draw/end_frame path, rather than a GDScript completion loop.
func _on_frame_pre_draw() -> void:
	metrics["render_draw_submissions"] += 1
	if _trace_next_draw or (_waiting_final and _final_draw_breadcrumbs < 3):
		_trace_next_draw = false
		_trace_next_ack = true
		if _waiting_final: _final_draw_breadcrumbs += 1
		_budget.breadcrumb("render_frame_draw_begin", metrics)
