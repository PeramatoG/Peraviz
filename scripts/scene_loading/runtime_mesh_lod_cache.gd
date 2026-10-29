extends RefCounted

# Cold, scene-owned presentation cache. Callers must prove geometry ownership first.
const POLICY_VERSION := 2
var triangle_limit: int = 32768
var total_triangle_limit: int = 131072
var vertex_limit: int = 65536
var total_vertex_limit: int = 262144
var processing_limit_us: int = 100000
var processed_vertices: int = 0
var processing_us: int = 0
var generation_limit: int = 32
var minimum_triangles: int = 1024
var cache_hits: int = 0
var inventory: Dictionary = {}
var bindings: Array = []
var automatic: bool = true
var requested_quality: String = "default"
var entries: Dictionary = {}
var generations: int = 0
var processed_triangles: int = 0
var skips: Dictionary = {}

func clear() -> void:
	entries.clear()
	inventory.clear()
	bindings.clear()
	cache_hits = 0
	generations = 0
	processed_triangles = 0
	processed_vertices = 0
	processing_us = 0
	skips.clear()

func derive(source: ArrayMesh, merge_angle: float = 60.0, source_revision: Variant = 0) -> Dictionary:
	var engine: Dictionary = Engine.get_version_info()
	var key: Array = [source.get_instance_id(), source_revision, merge_angle, POLICY_VERSION, engine.get("hash", engine.hex)]
	if entries.has(key):
		cache_hits += 1
		return entries[key]
	var reason: String = _exclusion(source)
	var vertices: int = 0
	var triangles: int = 0
	for surface in range(source.get_surface_count()):
		triangles += int(source.surface_get_array_index_len(surface) / 3.0)
		vertices += source.surface_get_array_len(surface)
	if reason.is_empty() and triangles < minimum_triangles: reason = "simple_mesh"
	if reason.is_empty() and (triangles > triangle_limit or vertices > vertex_limit or source.get_surface_count() > 4 or processed_vertices + vertices > total_vertex_limit or processed_triangles + triangles > total_triangle_limit or generations >= generation_limit or processing_us >= processing_limit_us): reason = "load_budget"
	if reason.is_empty():
		for method in ["from_mesh","generate_lods","get_mesh","get_surface_lod_count","get_surface_lod_size","get_surface_lod_indices"]:
			if not ClassDB.class_exists("ImporterMesh") or not ClassDB.class_has_method("ImporterMesh",method): reason = "engine_capability"
	if not reason.is_empty(): return _skip(key,source,reason)
	if buffers(source).lod_levels > 0: return _skip(key,source,"imported_lods")
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
				if index < 0 or index >= source.surface_get_array_len(surface): return _skip(key,source,"invalid_levels",Time.get_ticks_usec()-generated)
			var size: float = importer.call("get_surface_lod_size",surface,lod)
			if size > 0.0 and count > 0 and count % 3 == 0 and count < source.surface_get_array_index_len(surface):
				indices.append({"size":size,"indices":count})
				useful = true
		levels.append(indices)
	if not useful: return _skip(key,source,"no_useful_levels",Time.get_ticks_usec()-generated)
	var derived: ArrayMesh = importer.call("get_mesh") # No base_mesh: source must never be mutated.
	if derived == null or derived.get_surface_count() != source.get_surface_count(): return _skip(key,source,"conversion",Time.get_ticks_usec()-generated)
	if not _compatible_copy(source,derived): return _skip(key,source,"conversion_fidelity",Time.get_ticks_usec()-generated)
	for surface in range(source.get_surface_count()): derived.surface_set_name(surface,source.surface_get_name(surface))
	derived.shadow_mesh = source.shadow_mesh
	derived.lightmap_size_hint = source.lightmap_size_hint
	derived.resource_name = source.resource_name
	for name in source.get_meta_list(): derived.set_meta(name,source.get_meta(name))
	var source_buffers: Dictionary = buffers(source)
	var derived_buffers: Dictionary = buffers(derived)
	var finished := Time.get_ticks_usec()
	processing_us += finished-generated
	importer = null
	var result := {"source":source,"mesh":derived,"levels":levels,"excluded":"","copy_us":copied-started,
		"generate_us":generated-copied,"finalize_us":finished-generated,"total_us":finished-started,
		"generation_static_bytes_delta":memory_generated-memory_before,"retained_static_bytes_delta":OS.get_static_memory_usage()-memory_before,
		"source_buffers":source_buffers,"derived_buffers":derived_buffers}
	entries[key] = result
	return result

func _skip(key: Array, source: ArrayMesh, reason: String, additional_us: int = 0) -> Dictionary:
	processing_us += additional_us
	skips[reason] = int(skips.get(reason,0)) + 1
	var result := {"mesh":source,"excluded":reason}
	entries[key] = result
	return result

static func _exclusion(source: ArrayMesh) -> String:
	if source.custom_aabb != AABB(): return "custom_bounds"
	if source.get_blend_shape_count() != 0: return "blend_shapes"
	for surface in range(source.get_surface_count()):
		var format: int = source.surface_get_format(surface)
		if source.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES or (format & Mesh.ARRAY_FORMAT_INDEX) == 0 or (format & Mesh.ARRAY_FORMAT_NORMAL) == 0: return "nonindexed_or_missing_normals"
		if format & (Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS | Mesh.ARRAY_FORMAT_CUSTOM0 | Mesh.ARRAY_FORMAT_CUSTOM1 | Mesh.ARRAY_FORMAT_CUSTOM2 | Mesh.ARRAY_FORMAT_CUSTOM3): return "deformed_or_custom"
		var material: Material = source.surface_get_material(surface)
		if not material is StandardMaterial3D or material.next_pass != null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.emission_enabled or material.grow or material.proximity_fade_enabled or material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED: return "optical_transparent_or_unknown_material"
	return ""

# Packed renderer buffer sizes, not RSS, peak allocator or driver memory.
static func buffers(mesh: ArrayMesh) -> Dictionary:
	var result := {"vertices":0,"triangles":0,"base_bytes":0,"lod_bytes":0,"lod_levels":0}
	for surface in range(mesh.get_surface_count()):
		var data: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(),surface)
		result.vertices += mesh.surface_get_array_len(surface)
		result.triangles += int(mesh.surface_get_array_index_len(surface) / 3.0)
		for field in ["vertex_data","attribute_data","skin_data","index_data"]:
			if data.has(field): result.base_bytes += data[field].size()
		for lod in data.get("lods",[]):
			result.lod_bytes += lod.index_data.size()
			result.lod_levels += 1
	return result

# Keep weak instance bindings: the scene owns nodes; the cache owns only mesh resources.
func bind_instance(instance: MeshInstance3D, original: ArrayMesh, derived: ArrayMesh) -> void:
	instance.set_meta("peraviz_source_mesh_bounds",original.get_aabb())
	bindings.append({"instance":weakref(instance),"source":original,"derived":derived})
	instance.mesh = derived if automatic else original

# Authoritative Original mode restores the exact retained source, not a re-encoded copy.
func set_automatic(enabled: bool, viewport: Viewport) -> void:
	automatic = enabled
	viewport.mesh_lod_threshold = 1.0 if enabled else 0.0
	for binding: Dictionary in bindings:
		var instance: MeshInstance3D = binding.instance.get_ref()
		if instance != null: instance.mesh = binding.derived if enabled else binding.source

# Diagnostics must not become mesh owners. Packed-buffer inspection is on demand.
func record(instance: MeshInstance3D, data: Dictionary, route: String, reason: String) -> void:
	var source: Mesh = instance.mesh
	if source == null: return
	var key: int = source.get_instance_id()
	var asset: String = str(data.get("asset_archive_path",""))
	if asset.is_empty(): asset = str(data.get("asset_reference",data.get("asset_path","")))
	if not inventory.has(key):
		inventory[key] = {"mesh":weakref(source),"instances":0,"route":route,"source":asset,"quality":data.get("model_quality",""),"format":str(data.get("asset_path","")).get_extension(),"excluded":reason}
	inventory[key].instances += 1

func report(viewport: Viewport) -> Dictionary:
	var records: Array = []
	var reasons: Dictionary = {}
	var instances: int = 0
	var retained_derived: int = 0
	var derived_bytes: int = 0
	var source_bytes: int = 0
	for value: Dictionary in inventory.values():
		var row: Dictionary = value.duplicate()
		var source: Mesh = row.mesh.get_ref()
		if source == null: continue
		row.erase("mesh")
		instances += row.instances
		for entry: Dictionary in entries.values():
			if entry.get("source") == source and entry.excluded.is_empty():
				row.generated_lods = entry.levels
				row.generation_us = entry.total_us
				row.derived = entry.derived_buffers
		if source is ArrayMesh: row.original = buffers(source)
		else:
			row.original = {"vertices":0,"triangles":0,"lod_levels":0}
			for surface in range(source.get_surface_count()):
				var arrays: Array = source.surface_get_arrays(surface)
				row.original.vertices += arrays[Mesh.ARRAY_VERTEX].size()
				row.original.triangles += int(arrays[Mesh.ARRAY_INDEX].size()/3.0) if arrays[Mesh.ARRAY_INDEX] != null else int(arrays[Mesh.ARRAY_VERTEX].size()/3.0)
		source_bytes += int(row.original.get("base_bytes",0)) + int(row.original.get("lod_bytes",0))
		reasons[row.excluded] = int(reasons.get(row.excluded,0)) + 1
		records.append(row)
	for value: Dictionary in entries.values():
		if not value.excluded.is_empty(): continue
		retained_derived += 1
		derived_bytes += value.derived_buffers.base_bytes + value.derived_buffers.lod_bytes
	return {"scope":"imported model geometry (procedural optical renderer resources not inventoried)","automatic":automatic,"requested_gdtf_quality":requested_quality,"viewport_lod_threshold":viewport.mesh_lod_threshold,"mesh_resources":records.size(),"mesh_instances":instances,"eligible_resources":generations+int(reasons.get("load_budget",0))+int(reasons.get("simple_mesh",0))+int(reasons.get("imported_lods",0)),"generated_resources":retained_derived,"excluded_resources":records.size()-retained_derived-int(reasons.get("imported_lods",0)),"reasons":reasons,"generation_attempts":generations,"cache_hits":cache_hits,"processing_us":processing_us,"retained_derived_resources":retained_derived,"derived_packed_bytes":derived_bytes,"inventoried_source_packed_bytes":source_bytes,"memory_note":"Packed buffers only; retained source resources remain shared. Driver/RSS not measured.","rendered_primitives_viewport_total":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"assets":records}

# Godot may re-encode compressed positions/normals. Reject incompatible conversions
# before binding; Original always uses the untouched source resource.
static func _compatible_copy(source: ArrayMesh, derived: ArrayMesh) -> bool:
	var tolerance: float = source.get_aabb().size.length() * 0.0001
	for surface in range(source.get_surface_count()):
		if source.surface_get_material(surface) != derived.surface_get_material(surface): return false
		var a: Array = source.surface_get_arrays(surface)
		var b: Array = derived.surface_get_arrays(surface)
		for channel in [Mesh.ARRAY_INDEX,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_COLOR]:
			if a[channel] != b[channel]: return false
		var positions: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		if positions.size() != b[Mesh.ARRAY_VERTEX].size(): return false
		for index in range(positions.size()):
			if positions[index].distance_to(b[Mesh.ARRAY_VERTEX][index]) > tolerance: return false
		var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		if normals.size() != b[Mesh.ARRAY_NORMAL].size(): return false
		for index in range(normals.size()):
			if normals[index].distance_to(b[Mesh.ARRAY_NORMAL][index]) > 0.001: return false
		if a[Mesh.ARRAY_TANGENT] == null and b[Mesh.ARRAY_TANGENT] == null: continue
		if a[Mesh.ARRAY_TANGENT] == null or b[Mesh.ARRAY_TANGENT] == null or a[Mesh.ARRAY_TANGENT].size() != b[Mesh.ARRAY_TANGENT].size(): return false
		for index in range(a[Mesh.ARRAY_TANGENT].size()):
			if absf(a[Mesh.ARRAY_TANGENT][index]-b[Mesh.ARRAY_TANGENT][index]) > 0.001: return false
	return true
