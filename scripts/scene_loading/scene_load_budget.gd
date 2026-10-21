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
	_previous_frame_us = now
