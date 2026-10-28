extends RefCounted

# Cold, scene-owned presentation cache. Callers must prove geometry ownership first.
const POLICY_VERSION := 1
var triangle_limit: int = 8192
var total_triangle_limit: int = 32768
var vertex_limit: int = 16384
var total_vertex_limit: int = 65536
var processing_limit_us: int = 32000
var processed_vertices: int = 0
var processing_us: int = 0
var generation_limit: int = 8
var entries: Dictionary = {}
var generations: int = 0
var processed_triangles: int = 0
var skips: Dictionary = {}

func clear() -> void:
	entries.clear()
	generations = 0
	processed_triangles = 0
	processed_vertices = 0
	processing_us = 0
	skips.clear()

func derive(source: ArrayMesh, merge_angle: float = 60.0, source_revision: Variant = 0) -> Dictionary:
	var engine: Dictionary = Engine.get_version_info()
	var key: Array = [source.get_instance_id(), source_revision, merge_angle, POLICY_VERSION, engine.get("hash", engine.hex)]
	if entries.has(key): return entries[key]
	var reason: String = _exclusion(source)
	var vertices: int = 0
	var triangles: int = 0
	for surface in range(source.get_surface_count()):
		triangles += source.surface_get_array_index_len(surface) / 3
		vertices += source.surface_get_array_len(surface)
	if reason.is_empty() and (triangles > triangle_limit or vertices > vertex_limit or source.get_surface_count() > 4 or processed_vertices + vertices > total_vertex_limit or processed_triangles + triangles > total_triangle_limit or generations >= generation_limit or processing_us >= processing_limit_us): reason = "load_budget"
	if reason.is_empty():
		for method in ["from_mesh","generate_lods","get_mesh","get_surface_lod_count","get_surface_lod_size","get_surface_lod_indices"]:
			if not ClassDB.class_exists("ImporterMesh") or not ClassDB.class_has_method("ImporterMesh",method): reason = "engine_capability"
	if not reason.is_empty(): return _skip(key,source,reason)
	var started := Time.get_ticks_usec()
	var memory_before := OS.get_static_memory_usage()
	# Dynamic invocation keeps the original path usable in stripped engine builds.
	var importer: Object = ClassDB.instantiate("ImporterMesh")
	importer = importer.call("from_mesh",source)
	var copied := Time.get_ticks_usec()
	importer.call("generate_lods",merge_angle,25.0,[])
	var generated := Time.get_ticks_usec()
	var memory_generated := OS.get_static_memory_usage()
	generations += 1
	processed_triangles += triangles
	processed_vertices += vertices
	processing_us += generated-started
	var levels: Array = []
	var useful: bool = false
	for surface in range(source.get_surface_count()):
		var indices: Array = []
		for lod in range(importer.call("get_surface_lod_count",surface)):
			var lod_indices: PackedInt32Array = importer.call("get_surface_lod_indices",surface,lod)
			var count: int = lod_indices.size()
			for index in lod_indices:
				if index < 0 or index >= source.surface_get_array_len(surface): return _skip(key,source,"invalid_levels")
			var size: float = importer.call("get_surface_lod_size",surface,lod)
			if size > 0.0 and count > 0 and count % 3 == 0 and count < source.surface_get_array_index_len(surface):
				indices.append({"size":size,"indices":count})
				useful = true
		levels.append(indices)
	if not useful: return _skip(key,source,"no_useful_levels")
	var derived: ArrayMesh = importer.call("get_mesh") # No base_mesh: source must never be mutated.
	if derived == null or derived.get_surface_count() != source.get_surface_count(): return _skip(key,source,"conversion")
	derived.resource_name = source.resource_name
	for name in source.get_meta_list(): derived.set_meta(name,source.get_meta(name))
	var finished := Time.get_ticks_usec()
	processing_us += finished-generated
	importer = null
	var result := {"source":source,"mesh":derived,"levels":levels,"excluded":"","copy_us":copied-started,
		"generate_us":generated-copied,"finalize_us":finished-generated,"total_us":finished-started,
		"generation_static_bytes_delta":memory_generated-memory_before,"retained_static_bytes_delta":OS.get_static_memory_usage()-memory_before,
		"source_buffers":buffers(source),"derived_buffers":buffers(derived)}
	entries[key] = result
	return result

func _skip(key: Array, source: ArrayMesh, reason: String) -> Dictionary:
	skips[reason] = int(skips.get(reason,0)) + 1
	var result := {"mesh":source,"excluded":reason}
	entries[key] = result
	return result

static func _exclusion(source: ArrayMesh) -> String:
	if source.get_blend_shape_count() != 0: return "blend_shapes"
	for surface in range(source.get_surface_count()):
		var format: int = source.surface_get_format(surface)
		if source.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES or not format & Mesh.ARRAY_FORMAT_INDEX or not format & Mesh.ARRAY_FORMAT_NORMAL: return "nonindexed_or_missing_normals"
		if format & (Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS | Mesh.ARRAY_FORMAT_CUSTOM0 | Mesh.ARRAY_FORMAT_CUSTOM1 | Mesh.ARRAY_FORMAT_CUSTOM2 | Mesh.ARRAY_FORMAT_CUSTOM3): return "deformed_or_custom"
		var material: Material = source.surface_get_material(surface)
		if not material is StandardMaterial3D or material.next_pass != null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.emission_enabled or material.grow or material.proximity_fade_enabled: return "optical_transparent_or_unknown_material"
	return ""

# Packed renderer buffer sizes, not RSS, peak allocator or driver memory.
static func buffers(mesh: ArrayMesh) -> Dictionary:
	var result := {"vertices":0,"triangles":0,"base_bytes":0,"lod_bytes":0}
	for surface in range(mesh.get_surface_count()):
		var data: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(),surface)
		result.vertices += mesh.surface_get_array_len(surface)
		result.triangles += mesh.surface_get_array_index_len(surface) / 3
		for field in ["vertex_data","attribute_data","skin_data","index_data"]:
			if data.has(field): result.base_bytes += data[field].size()
		for lod in data.get("lods",[]): result.lod_bytes += lod.index_data.size()
	return result
