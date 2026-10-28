extends SceneTree

const Prototype = preload("res://tests/gdscript/helpers/runtime_mesh_lod_prototype.gd")
const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var cache := Prototype.new()
	var source: ArrayMesh
	var derived: ArrayMesh
	for density in [[16,8], [64,32], [256,128], [512,256]]:
		var reference_started := Time.get_ticks_usec()
		source = Prototype.fixture_mesh(density[0], density[1])
		var reference_us: int = Time.get_ticks_usec()-reference_started
		var before: Array = []
		for surface in range(source.get_surface_count()): before.append(source.surface_get_arrays(surface))
		var result: Dictionary = cache.derive(source)
		derived = result.mesh
		test.check(derived != source and result.excluded.is_empty(), "LOD is a separate presentation resource")
		var count: int = 0
		var max_normal_delta: float = 0.0
		var max_tangent_delta: float = 0.0
		for surface in range(source.get_surface_count()):
			var arrays: Array = derived.surface_get_arrays(surface)
			test.check(before[surface] == source.surface_get_arrays(surface), "Canonical source arrays never change")
			for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_INDEX,Mesh.ARRAY_TEX_UV]:
				test.check(before[surface][channel] == arrays[channel], "Highest-detail positions, triangle winding and UVs remain exact")
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			for index in range(tangents.size()): max_tangent_delta = maxf(max_tangent_delta,absf(tangents[index]-before[surface][Mesh.ARRAY_TANGENT][index]))
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for index in range(normals.size()): max_normal_delta = maxf(max_normal_delta,normals[index].distance_to(before[surface][Mesh.ARRAY_NORMAL][index]))
			test.check(derived.surface_get_name(surface) == source.surface_get_name(surface) and derived.surface_get_material(surface) == source.surface_get_material(surface), "Material slots, textures, culling and surface identity are retained")
			for lod in result.levels[surface]:
				test.check(lod.indices > 0 and lod.indices < before[surface][Mesh.ARRAY_INDEX].size() and lod.indices % 3 == 0, "Generated LODs reduce valid triangle index counts")
				count += 1
			test.check(result.derived_buffers.vertices == result.source_buffers.vertices, "LODs share original vertex count rather than simplify canonical vertices")
		test.check(count > 0 and max_normal_delta < 0.001 and max_tangent_delta < 0.001, "Native meshoptimizer produces LODs with bounded normal re-encoding error")
		test.check(derived.get_meta("provenance") == source.get_meta("provenance"), "Source provenance is copied")
		var generations: int = cache.generations
		for instance in range(20): test.check(cache.derive(source).mesh == derived, "Repeated fixtures reuse one derived resource")
		test.check(cache.generations == generations, "Cache hits perform no regeneration")
		print("RUNTIME_MESH_LOD ", JSON.stringify({"density":density,"reference_build_us":reference_us,"source":result.source_buffers,"derived":result.derived_buffers,"levels":result.levels,"copy_us":result.copy_us,"generate_us":result.generate_us,"finalize_us":result.finalize_us,"static_after_generation_delta":result.generation_static_bytes_delta,"static_retained_delta":result.retained_static_bytes_delta,"max_normal_delta":max_normal_delta,"max_tangent_delta":max_tangent_delta}))
		if density[0] == 256 and "--render-mesh-lod-probe" in OS.get_cmdline_user_args():
			await preload("res://tests/gdscript/helpers/runtime_mesh_lod_graphics.gd").run(self, source, derived)
		cache.clear()
	check_factory_and_identity(cache)
	check_material_exclusions(cache)
	check_explicit_lods()
	check_runtime_gltf(source)
	cache.clear()
	test.finish(self)

func check_material_exclusions(cache: RefCounted) -> void:
	var source: ArrayMesh = Prototype.fixture_mesh(16,8)
	var material: StandardMaterial3D = source.surface_get_material(1)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	test.check(cache.derive(source).mesh == source and cache.generations == 0, "Transparent surfaces retain exact original resources")
	material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	cache.clear()
	material.emission_enabled = true
	test.check(cache.derive(source).mesh == source and cache.generations == 0, "Mixed optical/emissive meshes are conservatively excluded")
	cache.clear()
	material.emission_enabled = false
	var first: Dictionary = cache.derive(source,60,0)
	var second: Dictionary = cache.derive(source,30,0)
	var third: Dictionary = cache.derive(source,60,1)
	test.check(cache.entries.size() == 3 and first.mesh != second.mesh and first.mesh != third.mesh, "Derived identity includes merge policy and source revision")
	var weak_mesh: WeakRef = weakref(third.mesh)
	first.clear(); second.clear(); third.clear(); cache.clear()
	test.check(weak_mesh.get_ref() == null, "Cache retirement releases derived meshes without retaining an ImporterMesh")

func check_explicit_lods() -> void:
	var source: ArrayMesh = Prototype.fixture_mesh(64,32)
	var importer := ImporterMesh.from_mesh(source)
	importer.generate_lods(60,25,[])
	var lods: Dictionary = {}
	for lod in range(importer.get_surface_lod_count(0)):
		lods[importer.get_surface_lod_size(0,lod)] = importer.get_surface_lod_indices(0,lod)
	var explicit := ArrayMesh.new()
	explicit.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(0), [], lods)
	explicit.surface_set_material(0,StandardMaterial3D.new())
	var cache := preload("res://scripts/scene_loading/runtime_mesh_lod_cache.gd").new()
	cache.minimum_triangles = 0
	test.check(cache.derive(explicit).excluded == "imported_lods" and cache.generations == 0,"Production service retains pre-existing imported LODs without regeneration")
	test.check(ImporterMesh.from_mesh(explicit).get_surface_lod_count(0) == lods.size() and lods.size() > 0, "Public ArrayMesh LOD dictionaries round-trip through native mesh resources")

func check_runtime_gltf(source: ArrayMesh) -> void:
	var node := MeshInstance3D.new()
	node.mesh = source
	var writer := GLTFDocument.new()
	var state := GLTFState.new()
	var path := ProjectSettings.globalize_path("user://runtime_lod_audit.glb")
	test.check(writer.append_from_scene(node,state) == OK and writer.write_to_filesystem(state,path) == OK, "Synthetic source is exported to GLB")
	node.free()
	var reader := GLTFDocument.new()
	var loaded := GLTFState.new()
	test.check(reader.append_from_file(path,loaded) == OK, "Runtime GLTFDocument reads embedded-style GLB")
	var scene := reader.generate_scene(loaded)
	var meshes: Array = scene.find_children("*","MeshInstance3D",true,false)
	if scene is MeshInstance3D: meshes.append(scene)
	test.check(not meshes.is_empty(), "Runtime GLB creates graphical meshes")
	for mesh in meshes:
		var importer := ImporterMesh.from_mesh(mesh.mesh)
		for surface in range(importer.get_surface_count()): test.check(importer.get_surface_lod_count(surface) == 0, "Runtime glTF conversion does not run editor import LOD generation")
	scene.free()
	DirAccess.remove_absolute(path)

# Exercise the active 3DS ArrayMesh builder, then preserve a canonical node/picking boundary.
func check_factory_and_identity(cache: RefCounted) -> void:
	var factory := preload("res://scripts/scene_loading/node_factory.gd").new()
	var synthetic: ArrayMesh = Prototype.fixture_mesh(64,32)
	var arrays: Array = synthetic.surface_get_arrays(0)
	var source: ArrayMesh = factory._build_3ds_mesh({"vertices":arrays[Mesh.ARRAY_VERTEX],"normals":arrays[Mesh.ARRAY_NORMAL],"texcoords":arrays[Mesh.ARRAY_TEX_UV],"indices":arrays[Mesh.ARRAY_INDEX]})
	test.check(ImporterMesh.from_mesh(source).get_surface_lod_count(0) == 0, "Actual 3DS construction path creates no automatic LOD")
	var result: Dictionary = cache.derive(source)
	test.check(not result.levels[0].is_empty(), "Actual factory ArrayMesh supports native derived LOD")
	var before_mirror: PackedInt32Array = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate()
	var mirrored: ArrayMesh = factory._build_3ds_mesh({"vertices":arrays[Mesh.ARRAY_VERTEX],"normals":arrays[Mesh.ARRAY_NORMAL],"texcoords":arrays[Mesh.ARRAY_TEX_UV],"indices":arrays[Mesh.ARRAY_INDEX]},true)
	var mirrored_result: Dictionary = cache.derive(mirrored)
	var mirrored_indices: PackedInt32Array = mirrored.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	test.check(mirrored_indices[1] == before_mirror[2] and mirrored_indices == mirrored_result.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX], "Derived LOD retains the active factory's reflected winding correction")
	var axis := Node3D.new()
	axis.name = "Pan"
	axis.rotation.y = 0.4
	var geometry := Node3D.new()
	geometry.name = "FixtureHousing"
	geometry.set_meta("peraviz_gdtf_geometry_key","uuid/Base/Pan/Housing")
	geometry.position = Vector3(0.1,0.2,0.3)
	axis.add_child(geometry)
	var visual := MeshInstance3D.new()
	visual.mesh = source
	geometry.add_child(visual)
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = source.get_aabb().size
	collider.shape = shape
	visual.add_child(body)
	body.add_child(collider)
	var local: Transform3D = geometry.transform
	visual.mesh = result.mesh
	test.check(geometry.transform == local and geometry.get_parent() == axis and axis.name == "Pan" and geometry.get_meta("peraviz_gdtf_geometry_key") == "uuid/Base/Pan/Housing", "Derived visual binding preserves mechanical nodes, transforms and UUID provenance")
	test.check(collider.shape == shape and shape.size == source.get_aabb().size and visual.mesh.get_aabb() == source.get_aabb(), "Picking retains the original bounds and collider identity")
	axis.free()
	cache.clear()
