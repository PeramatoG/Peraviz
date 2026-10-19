extends RefCounted

# All sampling and Dictionary creation in this helper belongs to the trace report boundary.
const APPLY_COLLECTIONS: PackedStringArray = [
	"_target_states", "_committed_output_states", "_beam_optics_signatures",
	"_light_desired_state", "_material_state_by_rid", "_visible_beam_ids",
	"_visible_light_ids", "_snapshot_output_commits", "_diagnostic_warning_keys",
	"_diagnostic_info_keys",
]
const REGISTRY_COLLECTIONS: PackedStringArray = [
	"_beam_output_records_by_id", "_lens_material_cache", "_target_resolution_failures",
]
const GOBO_COLLECTIONS: PackedStringArray = [
	"_assets", "_composition_cache", "_selections_by_target", "_rotation_states",
	"_active_continuous_layers",
]

const MESH_COLLECTIONS: PackedStringArray = ["_shape_cache", "_mesh_cache", "_normalized_polygon_cache"]
const PROXY_COLLECTIONS: PackedStringArray = ["_allocated_ids", "_visible_ids"]

var _viewport: WeakRef
var _sampled_high_water: Dictionary = {}

func configure(viewport: Viewport) -> void:
	_disable_measurement()
	_viewport = weakref(viewport) if viewport != null else null
	if viewport != null:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		var viewport: Viewport = _viewport.get_ref() as Viewport if _viewport != null else null
		if viewport != null:
			RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), false)

func _disable_measurement() -> void:
	var viewport: Viewport = _viewport.get_ref() as Viewport if _viewport != null else null
	if viewport != null:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), false)

func collect(owner: Node, native_runtime: Object) -> Dictionary:
	var result: Dictionary = {
		"static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"message_buffer_max_bytes": int(Performance.get_monitor(Performance.MEMORY_MESSAGE_BUFFER_MAX)),
		"objects_total": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"render_setup_cpu_ms": RenderingServer.get_frame_setup_time_cpu(),
		"viewport_cpu_ms": 0.0, "viewport_gpu_ms": 0.0,
	}
	var viewport: Viewport = _viewport.get_ref() as Viewport if _viewport != null else null
	if viewport != null:
		var rid: RID = viewport.get_viewport_rid()
		result["viewport_cpu_ms"] = RenderingServer.viewport_get_measured_render_time_cpu(rid)
		result["viewport_gpu_ms"] = RenderingServer.viewport_get_measured_render_time_gpu(rid)
	var sizes: Dictionary = {}
	if owner != null:
		var service: Object = owner.get("_fixture_light_apply_service")
		_sample_collections(sizes, service, APPLY_COLLECTIONS, "apply")
		if service != null:
			sizes["snapshot_commit_high_water"] = int(service.get("_snapshot_commit_high_water"))
		var registry: Object = owner.get("_native_target_registry")
		_sample_collections(sizes, registry, REGISTRY_COLLECTIONS, "registry")
		if registry != null:
			var gobos: Object = registry.get("_gobo_resources")
			_sample_collections(sizes, gobos, GOBO_COLLECTIONS, "gobo")
			_sample_collections(sizes, gobos.get("_mesh_builder"), MESH_COLLECTIONS, "gobo_mesh")
		var renderers: Dictionary = owner.get("_beam_renderers")
		for renderer_id in renderers:
			var renderer: Object = renderers[renderer_id]
			var prefix: String = "renderer_" + str(renderer_id)
			if renderer is LegacyConeBeamRenderer:
				_sample_collections(sizes, renderer._mesh_builder, MESH_COLLECTIONS, prefix)
			elif renderer is VolumetricBeamRenderer:
				_sample_collections(sizes, renderer._proxy_controller, PROXY_COLLECTIONS, prefix + "_proxy")
				for provider in renderer._shape_providers.values():
					if provider is VolumetricGoboPrismShapeProvider:
						_sample_collections(sizes, provider._mesh_builder, MESH_COLLECTIONS, prefix)

	if native_runtime != null:
		var native_sizes: Dictionary = native_runtime.get_state_sizes()
		for key in native_sizes:
			sizes["native_" + str(key)] = int(native_sizes[key])
	for key in sizes:
		_sampled_high_water[key] = maxi(int(_sampled_high_water.get(key, 0)), int(sizes[key]))
	result["sizes"] = sizes
	result["sampled_high_water"] = _sampled_high_water.duplicate()
	return result

func _sample_collections(result: Dictionary, source: Object, names: PackedStringArray, prefix: String) -> void:
	if source == null:
		return
	for collection_name in names:
		var collection: Dictionary = source.get(collection_name)
		result[prefix + collection_name] = collection.size()
