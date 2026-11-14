extends SceneTree

# Setup microbenchmark; reports observations, with no hardware timing assertion.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var factory := NodeFactory.new()
	var cache := PeravizRuntimeAssetCache.new()
	var shared := BoxMesh.new()
	var material := StandardMaterial3D.new()
	shared.material = material
	var instances: Array[MeshInstance3D] = []
	for i in range(10000):
		var instance := MeshInstance3D.new()
		instance.mesh = shared
		instances.append(instance)
	var started := Time.get_ticks_usec()
	for instance in instances:
		factory._force_double_sided_materials(instance,cache if not OS.get_cmdline_user_args().has("--reference") else null)
	var material_ms := (Time.get_ticks_usec()-started)/1000.0
	var materials: Dictionary = {}
	for instance in instances: materials[instance.get_active_material(0)] = true
	started = Time.get_ticks_usec()
	for iteration in range(3):
		for instance in instances:
			preload("res://scripts/scene_loading/model_geometry.gd").inspect(instance,cache.geometry_facts if not OS.get_cmdline_user_args().has("--reference") else {})
	var inspect_ms := (Time.get_ticks_usec()-started)/1000.0
	print("MODEL_PREPARATION_BENCHMARK ",JSON.stringify({"instances":instances.size(),"material_ms":material_ms,"unique_materials":materials.size(),"inspect_ms":inspect_ms,"inspections":instances.size()*3}))
	for instance in instances: instance.free()
	cache.clear()
	quit()
