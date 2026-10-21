extends SceneTree

# Developer benchmark, deliberately separate from deterministic test pass/fail timing.
var _previous_frame_us: int = 0
var _post_ready_gap_us: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var app: Node = load("res://test.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path: String = OS.get_cmdline_user_args()[0]
	for run in range(2):
		var result: Dictionary = await app._load_mvr_scene(path, "mvr", false)
		if not result.get("ok", false):
			push_error("Generated setup benchmark import failed")
			quit(1)
			return
		# Exercise the first focused click and DMX start separately from structural import.
		_previous_frame_us = Time.get_ticks_usec()
		_post_ready_gap_us = 0
		process_frame.connect(_observe_post_ready_frame)
		for frame in range(5): await process_frame
		root.grab_focus()
		var click := InputEventMouseButton.new()
		click.position = Vector2(450, 300)
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		Input.parse_input_event(click)
		await process_frame
		click.pressed = false
		Input.parse_input_event(click)
		var dmx_started := Time.get_ticks_usec()
		app._dmx_controller.start_dmx()
		var dmx_start_ms := (Time.get_ticks_usec() - dmx_started) / 1000.0
		for frame in range(5): await process_frame
		app._dmx_controller.stop_dmx()
		process_frame.disconnect(_observe_post_ready_frame)
		print("SETUP_BENCHMARK ", JSON.stringify({"cache": "session-cold" if run == 0 else "same-content-reload", "metrics": result["load_metrics"], "post_ready_max_event_loop_gap_ms": _post_ready_gap_us / 1000.0, "dmx_start_ms": dmx_start_ms}))
		await process_frame
	app._clear_scene()
	app.queue_free()
	await process_frame
	await process_frame
	quit()

func _observe_post_ready_frame() -> void:
	var now := Time.get_ticks_usec()
	_post_ready_gap_us = maxi(_post_ready_gap_us, now - _previous_frame_us)
	_previous_frame_us = now
