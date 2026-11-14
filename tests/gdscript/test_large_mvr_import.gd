extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var path: String = ProjectSettings.globalize_path("user://large_import_%d.mvr" % OS.get_process_id())
	test.check(OS.execute("python3",PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_large_mvr_fixture.py"),path])) == 0,"Generate 10,000-object mixed scenery archive")
	var app: Node = load("res://test.tscn").instantiate()
	root.add_child(app)
	await process_frame
	for run in range(2):
		var result: Dictionary = await app._load_mvr_scene(path,"mvr",false)
		test.check(result.get("ok",false),"Large scene/reload publishes successfully")
		if not result.get("ok",false): break
		var parent_basis := Basis(Vector3(0,0,-0.001),Vector3(0,-0.003,0),Vector3(0.002,0,0))
		var meshes: Dictionary = {}
		var materials: Dictionary = {}
		var parts: int = 0
		for i in range(10000):
			var group: int = int(i / 100.0)
			var node: Node3D = app._node_index.get("object-%d" % i)
			test.check(node != null,"Every SceneObject has its exact identity")
			if node == null: continue
			test.check(node.get_parent() == app._node_index.get("group-%d" % group),"Exact GroupObject hierarchy survives")
			var expected := Transform3D(parent_basis,Vector3(1,3,-group*0.001)) * Transform3D(Basis.IDENTITY,Vector3(i%100,0,0))
			test.check(node.global_transform.is_equal_approx(expected),"Mapped small/reflected/rotated nested world transform matches expected values")
			for child in node.get_children():
				if child.get_meta("peraviz_type","") != "model_part": continue
				parts += 1
				var visual: Node3D = child.get_meta("peraviz_model_visual",null)
				test.check(visual != null and visual.is_visible_in_tree(),"Every direct/Symdef model has an attached visible instance")
				if visual == null: continue
				var instances: Array = visual.find_children("*","MeshInstance3D",true,false)
				if visual is MeshInstance3D: instances.append(visual)
				for instance: MeshInstance3D in instances:
					meshes[instance.mesh] = true
					materials[instance.get_active_material(0)] = true
		test.check(parts == 10000 and meshes.size() <= 3 and materials.size() <= 3,"10k Symdef/3DS/GLB models reuse immutable meshes/materials")
		test.check(app.proxies_root.visible and not app._scene_loading,"Published scene is visible after rendering readiness")
		test.check(result.load_metrics.extraction_count < 20 and result.load_metrics.archive_entries >= 4500,"Unrelated padding assets do not extract")
		test.check(app._loader.get_fixtures_patch().size() == 3,"All fixtures retain patch records")
		print("LARGE_IMPORT_REGRESSION ",JSON.stringify({"run":run,"parts":parts,"mesh_resources":meshes.size(),"material_resources":materials.size(),"metrics":result.load_metrics}))
	app._clear_scene()
	app.queue_free()
	await process_frame
	await process_frame
	DirAccess.remove_absolute(path)
	test.finish(self)
