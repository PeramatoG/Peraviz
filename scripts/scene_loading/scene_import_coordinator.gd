extends RefCounted

# Owns one asynchronous application import, keeping publication and generation retirement together.
static func load_scene(app: Node, path: String, loaded_file_type: String, remember_loaded_file: bool, render_readiness: RefCounted = null, project_context: Dictionary = {}) -> Dictionary:
	if app._scene_loading:
		return {"ok": false, "error": "scene import already running", "node_count": 0}
	var load_started := Time.get_ticks_usec()
	if app._status_presenter != null:
		app._status_presenter.set_scene_state_loading(path)
	app._clear_scene()
	app._scene_loading = true
	var detail: String = app._user_preferences.gdtf_model_detail if app._user_preferences != null else "default"
	app._loader.set_gdtf_model_detail(detail)
	app._node_factory.fixture_casing_lod = app._user_preferences != null and app._user_preferences.fixture_casing_lod
	if project_context.is_empty() and loaded_file_type == "mvr":
		# A new MVR document has no saved presentation policy. PVZ restoration
		# below instead preserves explicit and migrated legacy settings.
		app._apply_visual_settings({"beam_render_mode": 0, "beam_presentation": 1, "footprint_backend": "custom", "enable_realtime_spotlights": false, "footprint_multiplier": 0.6, "footprint_softness": 0.10, "wash_intersection_width_m": 0.5, "lens_emission_multiplier": 1.0})
		if app.visual_settings_window != null: app.visual_settings_window.configure(app._visual_settings)
	app._scene_load_failed = false
	app._scene_setup_resource_metrics.clear()
	var loading_overlay := preload("res://scripts/scene_loading/scene_loading_overlay.gd").new()
	app.add_child(loading_overlay)
	app.proxies_root.hide()
	var generation: int = app._scene_load_generation
	var budget := SceneLoadBudget.new()
	budget.tree = app.get_tree()
	budget.phase_changed.connect(loading_overlay.set_phase)
	budget.render_progress_changed.connect(loading_overlay.set_render_progress)
	budget.observe_frames()
	budget.current = Callable(app, "_is_scene_load_current").bind(generation)
	# Two event-loop turns let the loading status draw before CPU preparation starts.
	await budget.checkpoint(true)
	await budget.checkpoint(true)
	var project_settings_ms: float = 0.0
	if not project_context.is_empty() and budget.valid():
		budget.phase = "project_settings"
		budget.breadcrumb("project_settings_begin")
		await budget.checkpoint(true)
		if budget.valid():
			var settings_started := Time.get_ticks_usec()
			app._restore_visual_project_settings(project_context.get("visual_settings", {}))
			var saved_dmx: Dictionary = project_context.get("dmx_settings", {})
			if saved_dmx.has("universe_offset"):
				app._dmx_controller.set_universe_offset(int(saved_dmx["universe_offset"]), false)
			project_settings_ms = (Time.get_ticks_usec() - settings_started) / 1000.0
		budget.breadcrumb("project_settings_end")
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
	if render_readiness == null:
		render_readiness = preload("res://scripts/scene_loading/scene_render_readiness.gd").new()
	var first_render_started := Time.get_ticks_usec()
	if bool(import_result.get("ok", false)) and budget.valid():
		budget.phase = "first_render"
		# Draw this phase before exposing a large scene to the rendering backend.
		await budget.checkpoint(true)
		await budget.checkpoint(true)
		if budget.valid() and not await render_readiness.prepare_scene(app.proxies_root, budget):
			import_result["ok"] = false
			import_result["error"] = render_readiness.error_message if not render_readiness.error_message.is_empty() else "scene import cancelled"
	if bool(import_result.get("ok", false)) and budget.valid():
		budget.phase = "geometry_visibility_audit"
		if not await app._node_factory.refresh_scene_visibility(app._node_index, budget):
			import_result["ok"] = false
			import_result["error"] = "scene import cancelled"
		else:
			import_result["geometry_summary"] = app._node_factory.asset_load_summary.duplicate(true)
	var first_render_ms := (Time.get_ticks_usec() - first_render_started) / 1000.0
	if not budget.valid():
		import_result = {"ok": false, "error": "scene import cancelled", "node_count": 0}
	if bool(import_result.get("ok", false)):
		budget.phase = "publish_scene"
		budget.breadcrumb("scene_publish_begin")
		await budget.checkpoint(true)
		if not budget.valid():
			import_result = {"ok": false, "error": "scene import cancelled", "node_count": 0}
	if bool(import_result.get("ok", false)):
		budget.phase = "fixture_inspector"
		budget.breadcrumb("fixture_inspector_begin")
		await budget.checkpoint(true)
		if budget.valid():
			app._refresh_fixture_inspection_panel()
			if is_instance_valid(app._fixture_inspection_panel):
				await app._fixture_inspection_panel.finish_visible_refresh(budget)
		budget.breadcrumb("fixture_inspector_end")
		if not budget.valid():
			import_result = {"ok": false, "error": "scene import cancelled", "node_count": 0}
	if bool(import_result.get("ok", false)) and remember_loaded_file:
		budget.phase = "save_preferences"
		budget.breadcrumb("session_preferences_begin")
		await budget.checkpoint(true)
		if budget.valid(): app._remember_loaded_file(str(project_context.get("source_path", path)), loaded_file_type)
		else: import_result = {"ok": false, "error": "scene import cancelled", "node_count": 0}
		budget.breadcrumb("session_preferences_end")
	if bool(import_result.get("ok", false)) and not project_context.is_empty():
		# The offset is already installed; starting a saved receiver stays behind the loading gate.
		budget.phase = "project_completion"
		budget.breadcrumb("project_completion_begin")
		var saved_dmx: Dictionary = project_context.get("dmx_settings", {}).duplicate()
		saved_dmx.erase("universe_offset")
		app._restore_dmx_project_settings(saved_dmx)
		budget.breadcrumb("project_completion_end")
	if bool(import_result.get("ok", false)):
		app._loaded_mvr_path = path
		app.last_loaded_file_type = loaded_file_type
		if app._status_presenter != null:
			app._status_presenter.set_scene_state_loaded(int(import_result.get("node_count", 0)))
	else:
		if app._status_presenter != null:
			var error_message: String = str(import_result.get("error", "unknown error"))
			app._status_presenter.set_scene_state_load_error(error_message)
	if not bool(import_result.get("ok", false)):
		app._clear_scene()
	budget.breadcrumb("scene_publish_end", {"ok": bool(import_result.get("ok", false))})
	# Only remove feedback after scene registration and real rendered frames complete.
	var metrics: Dictionary = import_result.get("load_metrics", {})
	metrics["project_settings_ms"] = project_settings_ms
	metrics["loaded_file_type"] = loaded_file_type
	metrics.merge(render_readiness.metrics)
	metrics["first_render_ms"] = first_render_ms
	budget.phase = "resource_summary"
	budget.breadcrumb("scene_resources_sample_begin")
	metrics.merge(app._scene_setup_resource_metrics)
	if is_instance_valid(app._fixture_inspection_panel):
		metrics["inspector_row_controls"] = app._fixture_inspection_panel._row_labels.size()
	if app._fixture_light_apply_service.is_dense_presentation_active():
		var counts: Dictionary = app._fixture_light_apply_service._dense_adapter.diagnostics()
		for key in ["physical_outputs", "final_render_rows", "allocated_member_shafts", "aggregate_shaft_resources", "unique_lens_material_rids"]:
			metrics[key] = counts.get(key, 0)
	budget.breadcrumb("scene_resources_sampled")
	loading_overlay.queue_free()
	budget.finish()
	metrics["max_event_loop_gap_phase"] = budget.max_event_loop_gap_phase
	metrics["max_event_loop_gap_ms"] = budget.max_event_loop_gap_us / 1000.0
	metrics["total_ms"] = (Time.get_ticks_usec() - load_started) / 1000.0
	metrics["max_main_thread_block_ms"] = budget.max_block_us / 1000.0
	metrics["max_main_thread_block_phase"] = budget.max_block_phase
	metrics["yielded_frames"] = budget.yields
	app._scene_load_failed = not bool(import_result.get("ok", false))
	app._scene_loading = false
	import_result["load_metrics"] = metrics
	if budget.trace_enabled:
		print("[peraviz-load] ", JSON.stringify(metrics))
	return import_result

