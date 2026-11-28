extends RefCounted

# The staged subtree and installed fixture root have separate lifetimes until publication.
static func install(owner: Node, document: RefCounted, candidate: Dictionary) -> String:
	var uuid: String = candidate.fixture_uuid
	var runtime = owner._dmx_controller._dmx_fixture_runtime
	var service = owner._fixture_light_apply_service
	var adapter = service._dense_adapter
	var registry: NativeRendererTargetRegistry = owner._native_target_registry
	var root: Node3D = owner._scene_registry.get_fixture(uuid)
	if root == null or runtime == null or adapter == null or not adapter.is_installed():
		return "The installed fixture presentation is unavailable."
	var current_failure := registry.mode_target_failure(uuid)
	if not current_failure.is_empty():
		return "The current renderer targets cannot be restored by Undo. " + current_failure
	var started := Time.get_ticks_usec()
	var index: Dictionary = owner._node_index
	var previous_manifest := registry.installed_manifest
	var previous_nodes: Dictionary = {}
	var replacement: Dictionary = {}
	var staged_root: Node3D
	if not candidate.reuse_geometry:
		staged_root = Node3D.new()
		staged_root.transform = root.global_transform
		for id in index:
			var node: Node3D = index[id]
			if str(node.get_meta("peraviz_gdtf_geometry_key", "")).begins_with(uuid + "/"):
				previous_nodes[id] = node
		var factory := NodeFactory.new()
		factory.fixture_casing_lod = owner._node_factory.fixture_casing_lod
		if not await factory.build_node_tree(candidate.geometry, staged_root, replacement, func() -> void: pass, owner._loader, owner._asset_cache):
			staged_root.free()
			return "The replacement fixture geometry could not be prepared."
		for id in replacement:
			if index.has(id) and not previous_nodes.has(id):
				staged_root.free()
				return "Replacement fixture geometry has a conflicting scene identity."

	var geometry_keys: Dictionary = {}
	var nodes: Dictionary = index if candidate.reuse_geometry else replacement
	for node: Node3D in nodes.values():
		var key: String = node.get_meta("peraviz_gdtf_geometry_key", "")
		if key.begins_with(uuid + "/"):
			if geometry_keys.has(key):
				if staged_root != null: staged_root.free()
				return "The fixture has ambiguous geometry targets."
			geometry_keys[key] = true
	for row: Dictionary in candidate.payload.renderer_manifest:
		if row.fixture_uuid != uuid: continue
		for target: Dictionary in row.targets:
			if not geometry_keys.has(target.geometry_key):
				if staged_root != null: staged_root.free()
				return "Missing renderer geometry for " + str(target.geometry_key)
		break

	var previous_outputs: Array = []
	for record: Dictionary in registry._beam_output_records_by_id.values():
		if record.fixture_uuid == uuid: previous_outputs.append(record)
	var previous_roots: Array[Node] = []
	var previous_positions: Dictionary = {}
	var new_roots: Array[Node] = []
	var previous_lens_cache: Dictionary = {}
	adapter._native.pause_for_mode_edit()
	if staged_root != null:
		for node: Node in root.get_children():
			if previous_nodes.has(node.get_meta("peraviz_object_id", "")):
				previous_roots.append(node)
				previous_positions[node] = node.get_index()
		for node in previous_roots: root.remove_child(node)
		for node: Node in staged_root.get_children():
			staged_root.remove_child(node)
			root.add_child(node)
			new_roots.append(node)
		staged_root.free()
		for id in previous_nodes: index.erase(id)
		index.merge(replacement, true)
		previous_lens_cache = registry.take_fixture_lens_cache(uuid)
		_clear_fixture_caches(owner, uuid)

	await registry.install_manifest(candidate.payload.renderer_manifest, null, true)
	var error := registry.mode_target_failure(uuid)
	var adapter_changed := false
	if error.is_empty():
		if candidate.reuse_geometry: registry.restore_individual_lenses(uuid)
		adapter_changed = true
		if not await adapter.rebind_mode(owner, service, registry, uuid):
			error = "The native renderer rejected the candidate binding layout."
		elif not adapter._native.apply_document_mode(runtime._native_visual_runtime, adapter._generation, owner._loader, document):
			error = "The staged document and native runtime could not be published together."
	if not error.is_empty():
		var rollback_outputs: Array = []
		if not new_roots.is_empty():
			for record: Dictionary in registry._beam_output_records_by_id.values():
				if record.fixture_uuid == uuid: rollback_outputs.append(record)
			for node in new_roots: root.remove_child(node)
			for node in previous_roots:
				root.add_child(node)
				root.move_child(node, int(previous_positions[node]))
			for id in replacement: index.erase(id)
			index.merge(previous_nodes, true)
			registry.take_fixture_lens_cache(uuid)
			registry._lens_material_cache.merge(previous_lens_cache, true)
			_clear_fixture_caches(owner, uuid)
		await registry.install_manifest(previous_manifest, null, true)
		if adapter_changed:
			await adapter.rebind_mode(owner, service, registry, uuid)
		adapter._native.restore_mode_physical(PackedInt32Array())
		adapter._native.resume_mode_layout(runtime._native_visual_runtime)
		for record: Dictionary in rollback_outputs: _retire_lights(owner, record)
		for node in new_roots: node.free()
		if not new_roots.is_empty(): _prune_geometry_bindings(owner)
		runtime.apply_visual_frame(owner._dmx_controller._dmx_receiver, owner, service, 0.0)
		return error

	var edited_outputs := PackedInt32Array()
	for record: Dictionary in registry._beam_output_records_by_id.values():
		if record.fixture_uuid == uuid: edited_outputs.append(record.beam_render_target_id)
	adapter._native.restore_mode_physical(edited_outputs)
	service._resetting_mode_effects = true
	registry.reset_fixture_mode_effects(uuid, previous_outputs, candidate.reuse_geometry)
	service._resetting_mode_effects = false
	registry.install_mode_gobo_assets(candidate.payload.gobo_assets)
	if not new_roots.is_empty():
		for record: Dictionary in previous_outputs: _retire_lights(owner, record)
		var anchors: Dictionary = {"axis": [], "emitters": [], "lens": [], "geometry_nodes": [], "emitter_photometrics": []}
		for row: Dictionary in candidate.geometry:
			var node: Node3D = replacement[row.node_id]
			anchors.geometry_nodes.append(node)
			if row.is_axis: anchors.axis.append(node)
			if row.is_lens: anchors.lens.append(node)
			if row.is_emitter:
				anchors.emitters.append(node)
				anchors.emitter_photometrics.append(owner._extract_emitter_photometrics(row))
		owner._scene_registry.register_fixture(uuid, root, anchors)
		for node in new_roots:
			owner._fixture_binding_service._attach_fixture_pick_colliders_recursive(uuid, node)
		owner.app_shell._highlight._refresh()
		for node in previous_roots: node.free()
		_prune_geometry_bindings(owner)
		owner._rebuild_loaded_bounds()

	runtime.refresh_after_mode_edit(candidate.payload, uuid, registry.get_summary())
	runtime.apply_visual_frame(owner._dmx_controller._dmx_receiver, owner, service, 0.0)
	owner._scene_setup_resource_metrics["mode_geometry_created"] = replacement.size()
	owner._scene_setup_resource_metrics["mode_geometry_retired"] = previous_nodes.size()
	owner._scene_setup_resource_metrics["mode_install_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	return ""

static func _clear_fixture_caches(owner: Node, uuid: String) -> void:
	for cache: Dictionary in [owner._fixture_geometry_nodes_cache, owner._fixture_emitter_nodes_cache,
			owner._fixture_axis_nodes_cache, owner._fixture_emissive_cache, owner._fixture_emitter_light_cache]:
		for key: String in cache.keys():
			if key == uuid or key.begins_with(uuid + "/"): cache.erase(key)

static func _retire_lights(owner: Node, record: Dictionary) -> void:
	for light: SpotLight3D in record.emitter_anchors:
		if is_instance_valid(light):
			owner._fixture_emitter_last_state.erase(light.get_instance_id())
			owner._cleanup_light_beam_renderers(light)

static func _prune_geometry_bindings(owner: Node) -> void:
	var cache = owner._asset_cache.derived_lods
	cache.bindings = cache.bindings.filter(func(binding: Dictionary) -> bool: return binding.instance.get_ref() != null)
