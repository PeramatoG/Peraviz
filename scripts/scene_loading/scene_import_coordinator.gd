extends RefCounted

# Owns one asynchronous application import, keeping publication and generation retirement together.
static func load_scene(app: Node, path: String, loaded_file_type: String, remember_loaded_file: bool) -> Dictionary:
	if app._scene_loading:
		return {"ok": false, "error": "scene import already running", "node_count": 0}
	var load_started := Time.get_ticks_usec()
	if app._status_presenter != null:
		app._status_presenter.set_scene_state_loading(path)
	app._clear_scene()
	app._scene_loading = true
	app._scene_setup_resource_metrics.clear()
	var loading_overlay := preload("res://scripts/scene_loading/scene_loading_overlay.gd").new()
	app.add_child(loading_overlay)
	app.proxies_root.hide()
	var generation: int = app._scene_load_generation
	var budget := SceneLoadBudget.new()
	budget.tree = app.get_tree()
	budget.phase_changed.connect(loading_overlay.set_phase)
	budget.observe_frames()
	budget.current = Callable(app, "_is_scene_load_current").bind(generation)
	# Two event-loop turns let the loading status draw before CPU preparation starts.
	await budget.checkpoint(true)
	await budget.checkpoint(true)
	var import_result: Dictionary = await app._scene_import_service.import_scene(
		path,
		app._loader,
		app._node_factory,
		app._fixture_binding_service,
		app._asset_cache,
		app.proxies_root,
		app._node_index,
		Callable(app, "_refresh_dmx_fixture_bindings"),
		Callable(app, "_populate_fixture_list"),
		Callable(app, "_sync_selection_state"),
		Callable(app, "_rebuild_debug_gizmos"),
		Callable(app, "_focus_loaded_scene"),
		Callable(app, "_update_debug_legend"),
		Callable(app, "_refresh_emitter_light_scalars"),
		Callable(app, "_extract_emitter_photometrics"),
		Callable(app, "_rebuild_loaded_bounds"),
		Callable(app, "_set_has_loaded_bounds"),
		app._debug_coords_enabled,
		app._debug_asset_cache_enabled,
		app._scene_registry,
		app._fixture_row_provider,
		budget,
		app._dmx_controller.get_universe_offset()
	)
	var first_render_started := Time.get_ticks_usec()
	if bool(import_result.get("ok", false)) and budget.valid():
		budget.phase = "first_render"
		# Draw this phase before exposing a large scene to the rendering backend.
		await budget.checkpoint(true)
		await budget.checkpoint(true)
		# Submit the completed scene behind feedback, before publishing readiness.
		if budget.valid(): app.proxies_root.show()
		await preload("res://scripts/scene_loading/scene_render_readiness.gd").new().wait_for_initial_frames(budget)
	var first_render_ms := (Time.get_ticks_usec() - first_render_started) / 1000.0
	if not budget.valid():
		import_result = {"ok": false, "error": "scene import cancelled", "node_count": 0}
	if bool(import_result.get("ok", false)):
		app._refresh_fixture_inspection_panel()
		app._loaded_mvr_path = path
		app._last_loaded_file_type = loaded_file_type
		if remember_loaded_file:
			app._remember_loaded_file(path, loaded_file_type)
		if app._status_presenter != null:
			app._status_presenter.set_scene_state_loaded(int(import_result.get("node_count", 0)))
	else:
		if app._status_presenter != null:
			var error_message: String = str(import_result.get("error", "unknown error"))
			app._status_presenter.set_scene_state_load_error(error_message)
	if not bool(import_result.get("ok", false)):
		app._clear_scene()
	# Only remove feedback after scene registration and real rendered frames complete.
	loading_overlay.queue_free()
	budget.finish()
	app._scene_loading = false
	var metrics: Dictionary = import_result.get("load_metrics", {})
	metrics["first_render_ms"] = first_render_ms
	metrics["max_event_loop_gap_phase"] = budget.max_event_loop_gap_phase
	metrics["max_event_loop_gap_ms"] = budget.max_event_loop_gap_us / 1000.0
	metrics["total_ms"] = (Time.get_ticks_usec() - load_started) / 1000.0
	metrics["max_main_thread_block_ms"] = budget.max_block_us / 1000.0
	metrics["max_main_thread_block_phase"] = budget.max_block_phase
	metrics["yielded_frames"] = budget.yields
	metrics.merge(app._scene_setup_resource_metrics)
	if app._fixture_light_apply_service.is_dense_presentation_active():
		var counts: Dictionary = app._fixture_light_apply_service._dense_adapter.diagnostics()
		for key in ["physical_outputs", "final_render_rows", "allocated_member_shafts", "aggregate_shaft_resources", "unique_lens_material_rids"]:
			metrics[key] = counts.get(key, 0)
	import_result["load_metrics"] = metrics
	if OS.get_environment("PERAVIZ_LOAD_TELEMETRY") == "1":
		print("[peraviz-load] ", JSON.stringify(metrics))
	return import_result

