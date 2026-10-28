extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
const Cache = preload("res://scripts/scene_loading/runtime_mesh_lod_cache.gd")
var test = TestCase.new()
var app: Node

func _initialize() -> void: call_deferred("run")

func generate(options: Array[String] = []) -> String:
	var path := ProjectSettings.globalize_path("user://model_detail_integration.mvr")
	var arguments := PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_model_detail_fixture.py"),path])
	arguments.append_array(PackedStringArray(options))
	test.check(OS.execute("python3",arguments) == 0,"Generate public authored quality archive")
	return path

func housings() -> Array:
	var result: Array = []
	for node: Node3D in app._node_index.values():
		if str(node.get_meta("peraviz_gdtf_geometry_path","")).ends_with("/Housing"): result.append(node)
	return result

func meshes(root_node: Node3D) -> Array:
	var result: Array = root_node.find_children("*","MeshInstance3D",true,false)
	if root_node is MeshInstance3D: result.append(root_node)
	return result

func load_case(path: String, quality: String, enabled: bool) -> void:
	app._user_preferences.gdtf_model_detail = quality
	app._user_preferences.fixture_casing_lod = enabled
	var package_hash: String = FileAccess.get_sha256(path)
	var start := Time.get_ticks_usec()
	var loaded: Dictionary = await app._load_mvr_scene(path,"mvr",false)
	test.check(FileAccess.get_sha256(path) == package_hash,"Import never modifies the original package")
	test.check(loaded.get("ok",false),"Production import completes with requested model/LOD policy")
	var records: Array = []
	for node in housings(): records.append({"source":node.get_meta("peraviz_asset_archive_path"),"quality":node.get_meta("peraviz_model_quality"),"geometry":Cache.buffers(meshes(node)[0].mesh),"lod":node.get_meta("peraviz_housing_lod") if node.has_meta("peraviz_housing_lod") else "original"})
	print("MODEL_DETAIL_IMPORT ",JSON.stringify({"requested":quality,"casing_lod":enabled,"setup_us":Time.get_ticks_usec()-start,"records":records,"cache_generations":app._asset_cache.derived_lods.generations,"skips":app._asset_cache.derived_lods.skips}))

func run() -> void:
	var path: String = generate()
	app = load("res://test.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app._user_preferences.auto_load_last_file = false
	for quality in ["default","low","high"]:
		await load_case(path,quality,false)
		test.check(housings().size() == 3,"Repeated fixtures retain distinct canonical housing nodes")
		var suffix: String = "" if quality == "default" else "_"+quality
		var first_mesh: Mesh = meshes(housings()[0])[0].mesh
		for node in housings():
			test.check(node.get_meta("peraviz_asset_archive_path") == "models/3ds%s/housing.3ds" % suffix and node.get_meta("peraviz_model_quality") == quality,"Selected authored archive identity and quality are exact")
			var dimensions: Dictionary = preload("res://scripts/scene_loading/model_geometry.gd").inspect(node.get_meta("peraviz_model_visual"))
			test.check(dimensions.bounds.size.is_equal_approx(Vector3.ONE*0.9),"Every authored quality retains declared GDTF dimensions")
			test.check(meshes(node)[0].mesh == first_mesh,"Repeated fixtures share the chosen source mesh")
			test.check(node.get_parent().name.contains("Tilt") and str(node.get_meta("peraviz_gdtf_geometry_key")).contains("/Pan/Tilt/Housing"),"Mechanical hierarchy and canonical geometry keys remain exact")
	path = generate(["--tiers=default"])
	for quality in ["low","high"]:
		await load_case(path,quality,false)
		for node in housings(): test.check(node.get_meta("peraviz_asset_archive_path") == "models/3ds/housing.3ds" and node.get_meta("peraviz_model_quality") == "default","Missing optional quality falls back to the exact Default source")
	path = generate(["--formats=glb"])
	await load_case(path,"high",true)
	for node in housings(): test.check(node.get_meta("peraviz_asset_archive_path") == "models/gltf_high/housing.glb" and not node.has_meta("peraviz_housing_lod"),"Authored GLB remains separate; nested scenes are not auto simplified")
	path = generate()
	await load_case(path,"high",true)
	var cache: RefCounted = app._asset_cache.derived_lods
	test.check(cache.generations == 1,"One unique source/winding/policy produces one derived mesh")
	var original: Mesh
	var derived: Mesh
	for value: Dictionary in cache.entries.values():
		if value.excluded.is_empty(): original = value.source; derived = value.mesh
	test.check(original != null and derived != null and original != derived,"Source and derived resources remain separate")
	for node in housings():
		var mesh: MeshInstance3D = meshes(node)[0]
		test.check(mesh.mesh == derived and node.has_meta("peraviz_housing_lod"),"Eligible housing binds the reused derived mesh")
		var body: Node3D = mesh.get_node_or_null("FixturePickBody")
		test.check(body != null and body.get_child(0).shape.size == original.get_aabb().size,"Selection collider retains original model bounds")
		test.check(mesh.global_basis.determinant() < 0 and mesh.get_meta("peraviz_flip_orientation_applied",false),"Reflected orientation remains installed before LOD derivation")
	if "--render-model-detail-probe" in OS.get_cmdline_user_args():
		await preload("res://tests/gdscript/helpers/runtime_mesh_lod_graphics.gd").run(self,original,derived,0.05)
	check_dmx_and_lens(cache)
	var generated: int = cache.generations
	app.camera.position += Vector3(2,1,2)
	await process_frame
	test.check(cache.generations == generated,"Camera movement performs no simplification")
	var weak: WeakRef = weakref(derived)
	original = null; derived = null
	await load_case(path,"default",false)
	test.check(cache.entries.is_empty() and weak.get_ref() == null,"Reload retires the old derived cache and scene resources")
	path = generate(["--mixed"])
	await load_case(path,"default",true)
	test.check(app._asset_cache.derived_lods.generations == 0,"An asset also used by a Beam is excluded from housing LOD")
	path = generate(["--special"])
	await load_case(path,"default",true)
	test.check(app._asset_cache.derived_lods.generations == 0,"Special GDTF optical geometry types are never nominated as casing")
	path = generate(["--dense"])
	await load_case(path,"default",true)
	test.check(app._asset_cache.derived_lods.generations == 0 and app._asset_cache.derived_lods.skips.has("load_budget"),"Oversized sources retain original rendering without running the expensive simplifier")
	check_materials_and_budget()
	# Cancellation at the first checkpoint must install nothing.
	var budget := SceneLoadBudget.new()
	budget.tree = self
	budget.current = func() -> bool: return false
	var count: int = app._asset_cache.derived_lods.generations
	var accepted: bool = await preload("res://scripts/scene_loading/housing_lod_installation.gd").install([{ "node_id":"cancel", "type":"fixture_geometry", "asset_path":"cancel.3ds" }],{},app._asset_cache.derived_lods,budget)
	test.check(not accepted and app._asset_cache.derived_lods.generations == count,"Cancelled generation allocates no LOD resources")
	app._user_preferences.gdtf_model_detail = "default"
	app._user_preferences.fixture_casing_lod = false
	app._clear_scene()
	app.queue_free()
	await process_frame
	test.finish(self)

func check_materials_and_budget() -> void:
	var cache := Cache.new()
	var source: ArrayMesh = preload("res://tests/gdscript/helpers/runtime_mesh_lod_prototype.gd").fixture_mesh(64,32)
	var material: StandardMaterial3D = source.surface_get_material(0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	test.check(cache.derive(source).excluded == "optical_transparent_or_unknown_material","Alpha-tested material is excluded")
	cache.clear(); material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED; material.emission_enabled = true
	test.check(cache.derive(source).mesh == source,"Emissive lens material remains original")
	cache.clear(); material.emission_enabled = false; material.grow = true
	test.check(cache.derive(source).mesh == source,"Vertex deformation remains original")
	cache.clear(); material.grow = false; cache.generation_limit = 0
	test.check(cache.derive(source).excluded == "load_budget" and cache.generations == 0,"Per-scene generation budget skips preprocessing")

	cache.clear()
	var triangle := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2])
	triangle.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	triangle.surface_set_material(0,StandardMaterial3D.new())
	cache.generation_limit = 8
	test.check(cache.derive(triangle).mesh == triangle and cache.derive(triangle).excluded == "no_useful_levels","No useful native LOD retains the original mesh and caches the decision")

func check_dmx_and_lens(cache: RefCounted) -> void:
	var runtime: RefCounted = app._dmx_controller._dmx_fixture_runtime
	var service: RefCounted = app._fixture_light_apply_service
	var adapter: RefCounted = service._dense_adapter
	var dmx := PackedByteArray()
	dmx.resize(512); dmx.fill(255)
	runtime._native_visual_runtime.submit_universe_frame(0,dmx)
	var frame: Dictionary = runtime._native_visual_runtime.consume_latest_visual_frame()
	runtime._sectioned_visual_frame_applier.apply_snapshot(frame,app,service,0.016,runtime,runtime._native_fixture_uuids_by_id,runtime._fixture_nodes)
	var before: PackedFloat32Array = adapter._native.physical_values(0)
	var generations: int = cache.generations
	app._apply_visual_settings({"lens_emission_multiplier":0.5})
	test.check(before[0] > 0.99 and before == adapter._native.physical_values(0),"Chosen authored detail and lens gain retain canonical native Dimmer/Color state")
	for output in adapter._outputs:
		var physical: PackedFloat32Array = adapter._native.physical_values(output.index)
		for material in output.materials:
			test.check(is_equal_approx(adapter._native.material_values(material.rid)[3],physical[7]*material.scale*0.5),"Optical lens materials remain exact while casing uses generated LOD")
	test.check(cache.generations == generations,"DMX and held presentation gain never regenerate LOD")
