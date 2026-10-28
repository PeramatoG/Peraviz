extends RefCounted

# Audit-only derived resources. No application path preloads this prototype.
# The caller must nominate static opaque housing/scenery, never optical geometry.
const POLICY_VERSION := 1
var entries: Dictionary = {}
var generations: int = 0

func clear() -> void:
	entries.clear()

func derive(source: ArrayMesh, merge_angle: float = 60.0, source_revision: int = 0) -> Dictionary:
	var key: Array = [source.get_instance_id(), source_revision, merge_angle, POLICY_VERSION, Engine.get_version_info().hex]
	if entries.has(key): return entries[key]
	if source.get_blend_shape_count() != 0: return {"mesh": source, "excluded": "blend_shapes"}
	for surface in range(source.get_surface_count()):
		var material: Material = source.surface_get_material(surface)
		var arrays: Array = source.surface_get_arrays(surface)
		if source.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES or arrays[Mesh.ARRAY_INDEX] == null or arrays[Mesh.ARRAY_NORMAL] == null:
			return {"mesh": source, "excluded": "nonindexed_or_missing_normals"}
		if arrays[Mesh.ARRAY_BONES] != null or arrays[Mesh.ARRAY_WEIGHTS] != null:
			return {"mesh": source, "excluded": "skinning"}
		if not material is StandardMaterial3D or material.next_pass != null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.emission_enabled:
			return {"mesh": source, "excluded": "optical_transparent_or_unknown_material"}
	var started := Time.get_ticks_usec()
	var memory_before := OS.get_static_memory_usage()
	var importer := ImporterMesh.from_mesh(source)
	var copied := Time.get_ticks_usec()
	importer.generate_lods(merge_angle, 25.0, []) # Second angle is unused in Godot 4.7.1.
	var generated := Time.get_ticks_usec()
	var memory_generated := OS.get_static_memory_usage()
	var levels: Array = []
	for surface in range(importer.get_surface_count()):
		var indices: Array = []
		for lod in range(importer.get_surface_lod_count(surface)):
			indices.append({"size": importer.get_surface_lod_size(surface, lod), "indices": importer.get_surface_lod_indices(surface, lod).size()})
		levels.append(indices)
	var derived: ArrayMesh = importer.get_mesh() # Never pass source as base_mesh: that would mutate it.
	# get_mesh does not forward ImporterMesh metadata in this engine; preserve provenance explicitly.
	derived.resource_name = source.resource_name
	for name in source.get_meta_list(): derived.set_meta(name,source.get_meta(name))
	var finished := Time.get_ticks_usec()
	importer = null # Do not retain the CPU import representation in the derived cache.
	var result := {"source": source, "mesh": derived, "levels": levels, "excluded": "", "copy_us": copied-started,
		"generate_us": generated-copied, "finalize_us": finished-generated, "total_us": finished-started,
		"generation_static_bytes_delta": memory_generated-memory_before, "retained_static_bytes_delta": OS.get_static_memory_usage()-memory_before,
		"source_buffers": buffers(source), "derived_buffers": buffers(derived)}
	entries[key] = result
	generations += 1
	return result

# Exact packed RenderingServer buffer sizes; not process RSS, transient peak or driver memory.
static func buffers(mesh: ArrayMesh) -> Dictionary:
	var result := {"vertices": 0, "triangles": 0, "base_bytes": 0, "lod_bytes": 0}
	for surface in range(mesh.get_surface_count()):
		var data: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), surface)
		result.vertices += mesh.surface_get_array_len(surface)
		result.triangles += mesh.surface_get_array_index_len(surface) / 3
		for field in ["vertex_data", "attribute_data", "skin_data", "index_data"]:
			if data.has(field): result.base_bytes += data[field].size()
		for lod in data.get("lods", []): result.lod_bytes += lod.index_data.size()
	return result

# A synthetic two-material fixture casing/collar, not a substitute for a real fixture corpus.
static func fixture_mesh(segments: int, rings: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radial_segments = segments
	sphere.rings = rings
	sphere.radius = 0.45
	sphere.height = 0.9
	var collar := CylinderMesh.new()
	collar.radial_segments = segments
	collar.rings = maxi(1, rings / 4)
	collar.top_radius = 0.28
	collar.bottom_radius = 0.32
	collar.height = 0.14
	var mesh := ArrayMesh.new()
	for part in [sphere, collar]:
		var arrays: Array = part.get_mesh_arrays()
		if part == collar:
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for index in range(vertices.size()): vertices[index].y -= 0.47
			arrays[Mesh.ARRAY_VERTEX] = vertices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var image := Image.create(16,16,false,Image.FORMAT_RGBA8)
	for y in range(16):
		for x in range(16): image.set_pixel(x,y,Color(0.25,0.4,0.6) if (x/4+y/4)%2 == 0 else Color(0.7,0.7,0.7))
	var casing := StandardMaterial3D.new()
	casing.albedo_texture = ImageTexture.create_from_image(image)
	var base := StandardMaterial3D.new()
	base.albedo_color = Color(0.2,0.2,0.23)
	mesh.surface_set_material(0, casing)
	mesh.surface_set_name(0, "Casing")
	mesh.surface_set_material(1, base)
	mesh.surface_set_name(1, "Collar")
	mesh.set_meta("provenance", "synthetic-fixture-casing")
	return mesh
