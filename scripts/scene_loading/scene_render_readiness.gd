extends RefCounted

var _presented_frames: int = 0

# SceneTree process_frame precedes rendering; it cannot establish graphics readiness.
# Keep the modal shield and DMX generation gate through actual frame submissions.
func wait_for_initial_frames(budget: SceneLoadBudget) -> bool:
	budget.phase = "first_render"
	if DisplayServer.get_name() == "headless":
		await budget.checkpoint(true)
		return await budget.checkpoint(true)
	_presented_frames = 0
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	while _presented_frames < 3 and budget.valid():
		await budget.checkpoint(true)
	RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	# Observe the complete final render interval before publishing readiness.
	return await budget.checkpoint(true)

func _on_frame_post_draw() -> void:
	_presented_frames += 1
