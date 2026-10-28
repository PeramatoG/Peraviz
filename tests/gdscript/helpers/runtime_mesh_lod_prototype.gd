extends "res://scripts/scene_loading/runtime_mesh_lod_cache.gd"

# Audit-only limits; the application always uses the bounded production cache.
func _init() -> void:
	vertex_limit = 400000
	total_vertex_limit = 2000000
	processing_limit_us = 10000000
	triangle_limit = 400000
	total_triangle_limit = 2000000
	generation_limit = 32

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
