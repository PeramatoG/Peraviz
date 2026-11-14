extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var factory := NodeFactory.new()
	var cache := PeravizRuntimeAssetCache.new()
	var source := StandardMaterial3D.new()
	var texture := GradientTexture1D.new()
	source.albedo_texture = texture
	var shared := BoxMesh.new()
	shared.material = source
	var instances: Array[MeshInstance3D] = []
	for i in range(4):
		var instance := MeshInstance3D.new()
		instance.mesh = shared
		instance.position = Vector3(i,0,0)
		factory._force_double_sided_materials(instance,cache if i < 2 else null)
		instances.append(instance)
	var prepared: Material = instances[0].get_active_material(0)
	test.check(prepared == instances[1].get_active_material(0) and prepared != source,"Ordinary scenery shares a separately prepared material")
	test.check(prepared.albedo_texture == texture and source.cull_mode != BaseMaterial3D.CULL_DISABLED,"Immutable texture remains shared and authored source material remains untouched")
	test.check(instances[2].get_active_material(0) != instances[3].get_active_material(0),"Fixture/default path retains independent material state")
	instances[2].get_active_material(0).albedo_color = Color.RED
	test.check(instances[3].get_active_material(0).albedo_color != Color.RED and prepared.albedo_color != Color.RED,"Independent material changes do not affect other fixtures or scenery")
	var facts := cache.geometry_facts
	var inspector = preload("res://scripts/scene_loading/model_geometry.gd")
	var first: Dictionary = inspector.inspect(instances[0],facts)
	instances[0].position = Vector3(5,2,1)
	instances[0].visible = false
	var moved: Dictionary = inspector.inspect(instances[0],facts)
	test.check(first.bounds != moved.bounds and moved.locally_visible_meshes == 0 and facts.size() == 1,"Mesh facts reuse preserves current per-instance transform and visibility inspection")
	source.emission_enabled = true
	test.check(cache.static_double_sided(source) == null,"Optical/emissive materials cannot enter immutable scenery preparation")
	cache.clear()
	test.check(facts.is_empty() and cache.debug_summary().static_material_unique == 0,"Scene retirement releases mesh facts and prepared material resources")
	for instance in instances: instance.free()
	test.finish(self)
