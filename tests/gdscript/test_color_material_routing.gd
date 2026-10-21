extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()
var state: Object
var generation: int

func _init() -> void:
	call_deferred("_run")

func _compose(section: int, target: int, mask: int, values: PackedFloat32Array, trace: bool = true) -> Dictionary:
	return state.compose(generation, PackedInt32Array([section,1,0,0,0]), PackedInt32Array([1,target,mask]), values, trace)

# Compare real native RID setters with identical physical/reduction work under the dummy renderer.
func _measure_lenses(shared: bool) -> void:
	state = ClassDB.instantiate("PeravizPresentationState")
	var ids := PackedInt32Array()
	var scales := PackedFloat32Array()
	var routes := PackedInt32Array()
	var mapping := PackedInt32Array()
	var classes := PackedInt32Array()
	var material_routes := PackedInt32Array()
	var owners := PackedInt32Array()
	var material_scales := PackedFloat32Array()
	var materials: Array = []
	var rids: Array = []
	for row in range(20): classes.append(1)
	for index in range(1000):
		ids.append(index+1)
		scales.append(1)
		routes.append_array(PackedInt32Array([2,10,index,3,20,index]))
		mapping.append(floori(index/50.0))
		var material_index: int = floori(index/50.0) if shared else index
		material_routes.append_array(PackedInt32Array([index,material_index]))
		if not shared or index%50 == 0:
			var material := StandardMaterial3D.new()
			materials.append(material)
			rids.append(material.get_rid())
			owners.append(index)
			material_scales.append(1)
	generation = state.install(ids,scales,routes)
	state.install_render_rows(mapping,classes)
	state.install_materials(rids,owners,material_scales,material_routes)
	_compose(2,10,2,PackedFloat32Array([1,1,1,1,1]))
	var totals: Dictionary = {"shared": shared, "ticks": 60}
	for tick in range(60):
		var batch: Dictionary = _compose(3,20,4,PackedFloat32Array([float(tick)/60,0.3,0.6,1]))
		test.check(batch["physical_color_outputs"] == 1000 and batch["count"] == 20, "Lens comparison retains 1000 exact physical outputs and 20 render rows")
		test.check(batch["lens_material_writes"] == (20 if shared else 1000), "Lens setter count follows unique compatible RIDs")
		for key in ["native_physical_us", "native_reduction_us", "native_material_us", "lens_material_writes", "lens_writes_avoided"]:
			totals[key] = int(totals.get(key,0)) + int(batch[key])
	print("COLOR_AUDIT_LENSES ", JSON.stringify(totals))
	state.clear()
	state = null

func _run() -> void:
	var saved: String = OS.get_environment("PERAVIZ_DIAGNOSTIC_SKIP_LENS_WRITES")
	OS.set_environment("PERAVIZ_DIAGNOSTIC_SKIP_LENS_WRITES", "0")
	state = ClassDB.instantiate("PeravizPresentationState")
	generation = state.install(PackedInt32Array([1,2,3]), PackedFloat32Array([1,1,1]),
		PackedInt32Array([2,10,0,2,10,1,2,10,2,3,20,0,3,20,1,3,21,2,4,30,0,4,30,1,4,30,2]))
	test.check(state.install_render_rows(PackedInt32Array([0,1,2]), PackedInt32Array([0,0,0])), "Individual inverse membership installs")
	var shared := StandardMaterial3D.new()
	var independent := StandardMaterial3D.new()
	var rids: Array = [shared.get_rid(), independent.get_rid()]
	test.check(state.install_materials(rids, PackedInt32Array([0,2]), PackedFloat32Array([1,1]), PackedInt32Array([0,0,1,0,2,1])), "Shared and independent RIDs retain exact owners")
	_compose(2,10,2,PackedFloat32Array([1,1,1,1,1]))
	var batch: Dictionary = _compose(3,20,4,PackedFloat32Array([1,0,0,1]))
	test.check(batch["physical_color_outputs"] == 2 and batch["lens_rids_affected"] == 1 and batch["lens_material_writes"] == 1 and batch["lens_writes_avoided"] == 1, "Two shared Color outputs mutate one RID once")
	test.check(state.material_values(independent.get_rid())[0] == 1 and state.material_values(independent.get_rid())[1] == 1, "Independent lens retains its white state")
	batch = _compose(4,30,8,PackedFloat32Array([15,30,0]))
	test.check(batch["lens_rids_affected"] == 0 and batch["lens_material_writes"] == 0, "Zoom-only snapshots never visit lens RIDs")
	batch = _compose(3,20,4,PackedFloat32Array([1,0,0,1]))
	test.check(batch["lens_rids_affected"] == 1 and batch["lens_rids_unchanged"] == 1 and batch["lens_material_writes"] == 0 and batch["count"] == 0, "Equivalent Color frames emit no lens setters or render rows")
	_compose(2,10,2,PackedFloat32Array([0,0,0,0,0]))
	_compose(3,21,4,PackedFloat32Array([0,0,1,0.5]))
	_compose(2,10,2,PackedFloat32Array([1,1,1,1,1]))
	var held: PackedFloat32Array = state.material_values(independent.get_rid())
	test.check(held[0] == 0 and held[2] == 1 and is_equal_approx(held[3],0.5), "Independent held Color gain restores through blackout")
	OS.set_environment("PERAVIZ_DIAGNOSTIC_SKIP_LENS_WRITES", "1")
	state.install_materials(rids, PackedInt32Array([0,2]), PackedFloat32Array([1,1]), PackedInt32Array([0,0,1,0,2,1]))
	batch = _compose(3,21,4,PackedFloat32Array([0,1,0,1]))
	test.check(batch["diagnostic_skip_lens_writes"] and batch["lens_material_writes"] == 0 and state.physical_values(2)[2] == 1, "Trace-only lens isolation preserves canonical independent Color")
	batch = state.compose(generation,PackedInt32Array(),PackedInt32Array(),PackedFloat32Array(),false)
	test.check(state.material_values(independent.get_rid())[1] == 1, "Trace-off production ignores requested diagnostic isolation")
	OS.set_environment("PERAVIZ_DIAGNOSTIC_SKIP_LENS_WRITES", "0")
	state.clear()
	state = null
	_measure_lenses(true)
	_measure_lenses(false)
	OS.set_environment("PERAVIZ_DIAGNOSTIC_SKIP_LENS_WRITES", saved)
	test.finish(self)
