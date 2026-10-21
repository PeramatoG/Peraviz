extends SceneTree

# Developer benchmark, deliberately separate from deterministic test pass/fail timing.
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
		print("SETUP_BENCHMARK ", JSON.stringify({"cache": "session-cold" if run == 0 else "same-content-reload", "metrics": result["load_metrics"]}))
		await process_frame
	app._clear_scene()
	app.queue_free()
	await process_frame
	await process_frame
	quit()
