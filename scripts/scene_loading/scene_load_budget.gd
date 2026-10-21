extends RefCounted
class_name SceneLoadBudget

# One import generation, main thread only. Wall time includes yielded frames;
# max_block_ms records actual uninterrupted main-thread work, including finalization.
var tree: SceneTree
var current: Callable
var slice_start: int = Time.get_ticks_usec()
var max_block_us: int = 0
var yields: int = 0
var phase: String = "loading_feedback"
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
	var elapsed: int = Time.get_ticks_usec() - slice_start
	if elapsed > max_block_us:
		max_block_us = elapsed
		max_block_phase = phase
