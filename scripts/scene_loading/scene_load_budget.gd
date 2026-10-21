extends RefCounted
class_name SceneLoadBudget

# One import generation, main thread only. Wall time includes yielded frames;
# max_block_ms records actual uninterrupted main-thread work, including finalization.
var tree: SceneTree
var current: Callable
var slice_start: int = Time.get_ticks_usec()
var max_block_us: int = 0
var yields: int = 0
signal phase_changed(value: String)
signal render_progress_changed(completed: int, total: int)

var phase: String = "loading_feedback":
	set(value):
		if value == phase: return
		phase = value
		phase_changed.emit(value)
var max_event_loop_gap_us: int = 0
var max_event_loop_gap_phase: String = "loading_feedback"
var _previous_frame_us: int = 0
var _observing: bool = false
var max_block_phase: String = "loading_feedback"
var frame_budget_us: int = 8000
var trace_enabled: bool = OS.get_environment("PERAVIZ_LOAD_TELEMETRY") == "1" or OS.get_cmdline_user_args().has("--peraviz-load-trace")
var _gap_breadcrumbs: int = 0

func valid() -> bool:
	return current.is_valid() and bool(current.call())

func checkpoint(force: bool = false) -> bool:
	var elapsed: int = Time.get_ticks_usec() - slice_start
	if force or elapsed >= frame_budget_us:
		if elapsed > max_block_us:
			max_block_us = elapsed
			max_block_phase = phase
		yields += 1
		await tree.process_frame
		slice_start = Time.get_ticks_usec()
	return valid()

func finish() -> void:
	if _observing:
		tree.process_frame.disconnect(_observe_frame)
		_observing = false
	var elapsed: int = Time.get_ticks_usec() - slice_start
	if elapsed > max_block_us:
		max_block_us = elapsed
		max_block_phase = phase

# Records whole event-loop gaps as well as import chunks; render/physics work occurs between awaits.
func observe_frames() -> void:
	_previous_frame_us = Time.get_ticks_usec()
	tree.process_frame.connect(_observe_frame)
	_observing = true

func _observe_frame() -> void:
	var now: int = Time.get_ticks_usec()
	var gap := now - _previous_frame_us
	if gap > max_event_loop_gap_us:
		max_event_loop_gap_us = gap
		max_event_loop_gap_phase = phase
	if trace_enabled and gap >= 1000000 and _gap_breadcrumbs < 4:
		_gap_breadcrumbs += 1
		breadcrumb("event_loop_gap", {"gap_ms": gap / 1000.0})
	_previous_frame_us = now

# Setup-only breadcrumbs leave evidence before a blocked draw prevents a summary.
func breadcrumb(event: String, values: Dictionary = {}) -> void:
	if not trace_enabled: return
	var record: Dictionary = {"event": event, "phase": phase, "monotonic_ms": Time.get_ticks_msec()}
	record.merge(values)
	print("[peraviz-load-progress] ", JSON.stringify(record))

# Keep signal emission local so the script compiler can verify the declaration.
func report_render_progress(completed: int, total: int) -> void:
	render_progress_changed.emit(completed, total)
