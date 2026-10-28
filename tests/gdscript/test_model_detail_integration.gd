extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
const Cache = preload("res://scripts/scene_loading/runtime_mesh_lod_cache.gd")
var test = TestCase.new()
var app: Node

func _initialize() -> void: call_deferred("run")

func generate(options: Array[String] = []) -> String:
	var path := ProjectSettings.globalize_path("user://model_detail_integration_%d.mvr" % OS.get_process_id())
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

func load_case(path: String, quality: String, enabled: Variant = null) -> void:
	app._user_preferences.gdtf_model_detail = quality
	if enabled != null: app._user_preferences.fixture_casing_lod = enabled
	var package_hash: String = FileAccess.get_sha256(path)
	var start := Time.get_ticks_usec()
	var loaded: Dictionary = await app._load_mvr_scene(path,"mvr",false)
	test.check(FileAccess.get_sha256(path) == package_hash,"Import never modifies the original package")
	test.check(loaded.get("ok",false),"Production import completes with requested model/LOD policy")
	var records: Array = []
	for node in housings(): records.append({"source":node.get_meta("peraviz_asset_archive_path"),"quality":node.get_meta("peraviz_model_quality"),"geometry":Cache.buffers(meshes(node)[0].mesh),"lod":node.get_meta("peraviz_housing_lod") if node.has_meta("peraviz_housing_lod") else "original"})
	print("MODEL_DETAIL_IMPORT ",JSON.stringify({"requested":quality,"casing_lod":app._user_preferences.fixture_casing_lod,"setup_us":Time.get_ticks_usec()-start,"records":records,"cache_generations":app._asset_cache.derived_lods.generations,"skips":app._asset_cache.derived_lods.skips}))

func run() -> void:
	check_preference_defaults()
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
	for node in housings(): test.check(node.get_meta("peraviz_asset_archive_path") == "models/gltf_high/housing.glb" and node.get_meta("peraviz_housing_lod").excluded in ["simple_mesh","optical_transparent_or_unknown_material","nonindexed_or_missing_normals"],"Small authored GLB keeps original; its exact identity remains independent")
	await check_glb_routes()
	path = generate()
	app._user_preferences.fixture_casing_lod = UserPreferences.new().fixture_casing_lod
	await load_case(path,"high")
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
	check_source_fidelity(cache)
	var geometry_tab: Node = app.visual_settings_window._tabs.get_node("Geometry")
	test.check(geometry_tab != null and geometry_tab.get_node("SourceQuality") != null,"Geometry controls are in Settings independently of hidden Advanced module")
	var automatic_control: OptionButton = geometry_tab.get_node("AutomaticLOD")
	automatic_control.item_selected.emit(1)
	test.check(app.get_viewport().mesh_lod_threshold == 0.0 and not app._user_preferences.fixture_casing_lod,"Original mode updates viewport and saved preference immediately")
	for node in housings(): test.check(meshes(node)[0].mesh == original,"Original mode restores the exact retained source resource")
	automatic_control.item_selected.emit(0)
	for node in housings(): test.check(meshes(node)[0].mesh == derived,"Automatic mode immediately reuses the derived resource without rebuilding")
	test.check(app.get_viewport().mesh_lod_threshold == 1.0,"Automatic comparison uses Godot's normal viewport threshold")
	var report: Dictionary = cache.report(app.get_viewport())
	test.check(report.generated_resources == 1 and report.cache_hits == 2 and report.mesh_resources == 2 and report.mesh_instances == 6,"On-demand report distinguishes unique resources, instances and cache reuse")
	test.check(report.reasons.has("optical_or_mixed_ownership") and report.derived_packed_bytes > 0,"Diagnostics include optical exclusions and retained mesh storage")
	print("MODEL_DETAIL_DIAGNOSTICS ",JSON.stringify(report))
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
	test.check(app._asset_cache.derived_lods.generations == 1,"A 16k-triangle housing now benefits from one shared bounded generation")
	path = generate(["--oversized","--scenery"])
	await load_case(path,"default",true)
	var large_report: Dictionary = app._asset_cache.derived_lods.report(app.get_viewport())
	test.check(int(large_report.reasons.get("scenery_deferred",0)) == 1,"Scenery deferral reports actual unique excluded source count")
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

	cache.clear(); cache.generation_limit = 32; cache.processing_limit_us = 0
	test.check(cache.derive(source).excluded == "load_budget" and cache.generations == 0,"Exhausted cumulative setup budget skips without a hardware timing assertion")
	cache.processing_limit_us = 100000
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
	cache.minimum_triangles = 0
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

func check_preference_defaults() -> void:
	var preferences := UserPreferences.new()
	test.check(preferences.fixture_casing_lod and preferences.gdtf_model_detail == "default","New preference defaults enable safe LOD independently of authored detail")
	var previous: String = FileAccess.get_file_as_string(UserPreferences.SETTINGS_FILE_PATH) if FileAccess.file_exists(UserPreferences.SETTINGS_FILE_PATH) else ""
	var config := ConfigFile.new()
	config.save(UserPreferences.SETTINGS_FILE_PATH)
	preferences.load_from_disk()
	test.check(preferences.fixture_casing_lod,"Missing preference migrates to automatic LOD enabled")
	config.set_value("ui","fixture_casing_lod",false)
	config.save(UserPreferences.SETTINGS_FILE_PATH)
	preferences.load_from_disk()
	test.check(not preferences.fixture_casing_lod,"Explicit saved Original preference remains disabled")
	FileAccess.open(UserPreferences.SETTINGS_FILE_PATH,FileAccess.WRITE).store_string(previous)

func check_glb_routes() -> void:
	var path: String = generate(["--formats=glb","--lod-glb"])
	await load_case(path,"high",true)
	var cache: RefCounted = app._asset_cache.derived_lods
	test.check(cache.generations == 1 and cache.cache_hits == 2,"Opaque static multi-surface runtime GLB reuses the same derived service")
	check_source_fidelity(cache)
	for node in housings():
		var instances: Array = meshes(node)
		test.check(instances.size() == 1 and instances[0].name == "EmbeddedMirror" and instances[0].transform.basis.determinant() < 0,"Runtime glTF retains embedded hierarchy and mirrored local transform")
		var pick_shape: CollisionShape3D = instances[0].get_node("FixturePickBody").get_child(0)
		var source_bounds: AABB = instances[0].get_meta("peraviz_source_mesh_bounds")
		test.check(pick_shape.shape.size == source_bounds.size and pick_shape.position == source_bounds.get_center(),"GLB picking uses exact original-source bounds despite derived position re-encoding")
		for surface in range(instances[0].mesh.get_surface_count()):
			test.check(instances[0].get_active_material(surface).cull_mode == BaseMaterial3D.CULL_DISABLED,"Existing per-instance double-sided material compatibility survives LOD")
	if "--render-model-detail-probe" in OS.get_cmdline_user_args():
		for entry: Dictionary in cache.entries.values():
			if entry.excluded.is_empty(): await preload("res://tests/gdscript/helpers/runtime_mesh_lod_graphics.gd").run(self,entry.source,entry.mesh,0.05)
	path = generate(["--formats=glb","--lod-glb","--transparent"])
	await load_case(path,"high",true)
	test.check(app._asset_cache.derived_lods.generations == 0,"Transparent runtime GLB retains original resource")
	path = generate(["--formats=glb","--lod-glb","--animated"])
	await load_case(path,"high",true)
	test.check(app._asset_cache.derived_lods.generations == 0,"Animated runtime GLB retains original resource")
	var report: Dictionary = app._asset_cache.derived_lods.report(app.get_viewport())
	test.check(report.reasons.has("animated_scene"),"Animation exclusion is visible in the real scene report")

func check_source_fidelity(cache: RefCounted) -> void:
	for entry: Dictionary in cache.entries.values():
		if not entry.excluded.is_empty(): continue
		var source: ArrayMesh = entry.source
		var derived: ArrayMesh = entry.mesh
		for surface in range(source.get_surface_count()):
			var a: Array = source.surface_get_arrays(surface)
			var b: Array = derived.surface_get_arrays(surface)
			var position_delta: float = 0.0
			for index in range(a[Mesh.ARRAY_VERTEX].size()): position_delta = maxf(position_delta,a[Mesh.ARRAY_VERTEX][index].distance_to(b[Mesh.ARRAY_VERTEX][index]))
			print("MODEL_DETAIL_POSITION_DELTA ",position_delta)
			test.check(position_delta < source.get_aabb().size.length()*0.0001,"Actual imported derived positions stay within bounded re-encoding tolerance")
			for channel in [Mesh.ARRAY_INDEX,Mesh.ARRAY_TEX_UV]:
				test.check(a[channel] == b[channel],"Actual imported highest-detail channel %d remains exact" % channel)
			var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			for index in range(normals.size()):
				test.check(normals[index].distance_to(b[Mesh.ARRAY_NORMAL][index]) < 0.001,"Actual imported normals preserve facing within re-encoding tolerance")
			test.check(source.surface_get_name(surface) == derived.surface_get_name(surface) and source.surface_get_material(surface) == derived.surface_get_material(surface),"Actual source surface identities and material/texture references remain shared")
