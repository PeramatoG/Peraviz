extends RefCounted
class_name SceneImportService

func clear_scene(scene_registry: SceneRegistry,
		proxies_root: Node3D,
		node_index: Dictionary,
		asset_cache: PeravizRuntimeAssetCache,
		fixture_emissive_cache: Dictionary,
		fixture_emitter_light_cache: Dictionary,
		fixture_emitter_photometrics: Dictionary,
		fixture_gobo_projector: FixtureGoboProjector,
		clear_selected_fixture: Callable,
		clear_debug_gizmos: Callable,
		set_has_loaded_bounds: Callable) -> void:
	scene_registry.clear("scene_reload")
	clear_selected_fixture.call("scene_clear")
	for child in proxies_root.get_children():
		child.queue_free()
	node_index.clear()
	asset_cache.clear()
	fixture_emissive_cache.clear()
	fixture_emitter_light_cache.clear()
	fixture_emitter_photometrics.clear()
	if fixture_gobo_projector != null:
		fixture_gobo_projector.clear_cache()
	set_has_loaded_bounds.call(false)
	clear_debug_gizmos.call()

func import_scene(path: String,
		loader: PeravizLoader,
		node_factory: NodeFactory,
		fixture_binding_service: FixtureBindingService,
		asset_cache: PeravizRuntimeAssetCache,
		proxies_root: Node3D,
		node_index: Dictionary,
		refresh_dmx_fixture_bindings: Callable,
		populate_fixture_list: Callable,
		sync_selection_state: Callable,
		rebuild_debug_gizmos: Callable,
		focus_loaded_scene: Callable,
		update_debug_legend: Callable,
		refresh_emitter_light_scalars: Callable,
		extract_emitter_photometrics: Callable,
		rebuild_loaded_bounds: Callable,
		set_has_loaded_bounds: Callable,
		debug_coords_enabled: bool,
		debug_asset_cache_enabled: bool,
		scene_registry: SceneRegistry,
		fixture_row_provider: FixtureRowProvider,
		budget: SceneLoadBudget = null, universe_offset: int = -1) -> Dictionary:
	if path.is_empty():
		return {
			"ok": false,
			"error": "empty file path",
			"node_count": 0,
		}
	if not FileAccess.file_exists(path):
		return {
			"ok": false,
			"error": "file does not exist",
			"node_count": 0,
		}
	var load_start := Time.get_ticks_usec()
	var phases: Dictionary = {}
	var phase_start := load_start
	var native_path: String = ProjectSettings.globalize_path(path)
	var peraviz_debug_baseline: bool = bool(ProjectSettings.get_setting("peraviz_debug_baseline", false))
	var nodes: Array
	if budget != null and not peraviz_debug_baseline and not debug_coords_enabled:
		if not loader.begin_load_mvr(native_path, universe_offset):
			return {"ok": false, "error": "native import already running", "node_count": 0}
		while not loader.is_load_mvr_ready():
			budget.phase = loader.get_load_phase()
			await budget.checkpoint(true)
		# Drain the owned task even after cancellation, before another load can begin.
		budget.phase = "node_payload"
		nodes = loader.finish_load_mvr()
	else:
		nodes = loader.load_mvr(native_path, peraviz_debug_baseline, debug_coords_enabled)
	if budget != null and not await budget.checkpoint(true):
		return {"ok": false, "error": "scene import cancelled", "node_count": 0}
	phases["native_load_ms"] = (Time.get_ticks_usec() - phase_start) / 1000.0
	if nodes.is_empty():
		return {
			"ok": false,
			"error": "MVR returned no nodes",
			"node_count": 0,
		}
	print("[Peraviz] Loaded render nodes: ", nodes.size(), " baseline_debug=", peraviz_debug_baseline, " coords_debug=", debug_coords_enabled)
	set_has_loaded_bounds.call(false)

	phase_start = Time.get_ticks_usec()
	if budget != null: budget.phase = "node_resources"
	if not await node_factory.build_node_tree(nodes, proxies_root, node_index, rebuild_loaded_bounds, loader, asset_cache, budget):
		return {"ok": false, "error": "scene import cancelled", "node_count": 0}
	phases["node_resources_ms"] = (Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()
	if budget != null: budget.phase = "fixture_registration"
	await fixture_binding_service.register_fixture_registry(nodes, node_index, scene_registry, extract_emitter_photometrics, budget)
	if budget != null and not await budget.checkpoint(true):
		return {"ok": false, "error": "scene import cancelled", "node_count": 0}
	if fixture_row_provider != null:
		fixture_row_provider.set_loaded_nodes(nodes)
	phases["fixture_registration_ms"] = (Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()
	if budget != null:
		budget.phase = "patch_binding"
		# Present feedback before the main-thread resource transaction starts.
		await budget.checkpoint(true)
		await budget.checkpoint(true)
		if not budget.valid(): return {"ok": false, "error": "scene import cancelled", "node_count": 0}
		budget.breadcrumb("renderer_binding_transaction_begin")
	# Match main's resource publication order: individual materials, shared control
	# materials, aggregate handles and native RID bindings commit in one turn.
	# Rendering intermediate resources across frames can prepare materials which
	# are immediately replaced/suppressed. Native CPU preparation is already done.
	var binding_started := Time.get_ticks_usec()
	var registered: Variant = await refresh_dmx_fixture_bindings.call(null)
	phases["renderer_binding_transaction_ms"] = (Time.get_ticks_usec() - binding_started) / 1000.0
	if budget != null: budget.breadcrumb("renderer_binding_transaction_end")
	if registered is bool and not registered:
		return {"ok": false, "error": "renderer target installation failed", "node_count": 0}
	if budget != null and not await budget.checkpoint(true):
		return {"ok": false, "error": "scene import cancelled", "node_count": 0}
	phases["runtime_registration_ms"] = (Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()
	if budget != null:
		budget.phase = "finalize"
		budget.breadcrumb("scene_navigation_begin")
	populate_fixture_list.call()
	sync_selection_state.call("scene_reload")
	rebuild_debug_gizmos.call()
	focus_loaded_scene.call()
	if debug_asset_cache_enabled:
		_print_asset_cache_summary(asset_cache)
	update_debug_legend.call()
	if budget != null:
		budget.phase = "final_light_defaults"
		budget.breadcrumb("scene_light_defaults_begin")
		if not await refresh_emitter_light_scalars.call(budget):
			return {"ok": false, "error": "scene import cancelled", "node_count": 0}
		budget.breadcrumb("scene_light_defaults_end")
	else:
		refresh_emitter_light_scalars.call()
	phases["finalize_ms"] = (Time.get_ticks_usec() - phase_start) / 1000.0
	phases["total_ms"] = (Time.get_ticks_usec() - load_start) / 1000.0
	phases.merge(loader.get_load_metrics())

	return {
		"load_metrics": phases,
		"ok": true,
		"error": "",
		"node_count": nodes.size(),
		"geometry_summary": node_factory.asset_load_summary.duplicate(true),
		"asset_failures": node_factory.asset_diagnostics.failure_groups(),
	}

func _print_asset_cache_summary(asset_cache: PeravizRuntimeAssetCache) -> void:
	var cache_summary: Dictionary = asset_cache.debug_summary()
	var hit_by_kind: Dictionary = cache_summary.get("hits_by_kind", {})
	var miss_by_kind: Dictionary = cache_summary.get("misses_by_kind", {})
	print("[PeravizAssetCache] summary hits=", cache_summary.get("hits", 0),
		" misses=", cache_summary.get("misses", 0),
		" unique=", cache_summary.get("unique_resources", 0),
		" mesh(hit/miss)=", hit_by_kind.get("mesh", 0), "/", miss_by_kind.get("mesh", 0),
		" scene(hit/miss)=", hit_by_kind.get("scene", 0), "/", miss_by_kind.get("scene", 0),
		" material(hit/miss)=", hit_by_kind.get("material", 0), "/", miss_by_kind.get("material", 0))
