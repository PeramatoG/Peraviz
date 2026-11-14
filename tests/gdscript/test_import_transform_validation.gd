extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
const Validation = preload("res://scripts/scene_loading/transform_validation.gd")
var test = TestCase.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var factory := NodeFactory.new()
	var cache := PeravizRuntimeAssetCache.new()
	var cases: Array[Basis] = [Basis.IDENTITY, Basis.from_scale(Vector3.ONE * 0.001), Basis.from_scale(Vector3(0.0001,0.002,0.003)), Basis(Vector3.UP,0.71).scaled(Vector3(0.001,0.002,0.003)), Basis.from_scale(Vector3(-0.001,0.002,0.003))]
	for basis in cases:
		test.check(Validation.is_basis_valid(basis), "Invertible identity/small/nonuniform/rotated/reflected basis accepted")
		var data := {"has_basis":true,"basis_x":basis.x,"basis_y":basis.y,"basis_z":basis.z,"pos":Vector3(1,2,3),"type":"group","node_id":"parent"}
		var parent: Node3D = factory.create_scene_node(data,null,cache)
		root.add_child(parent)
		var child: Node3D = factory.create_scene_node({"has_basis":true,"basis_x":Vector3(0.002,0,0),"basis_y":Vector3(0,0.003,0),"basis_z":Vector3(0,0,-0.004),"pos":Vector3(2,3,4),"type":"group"},null,cache)
		parent.add_child(child)
		test.check(parent.transform == Transform3D(basis,Vector3(1,2,3)), "Exact authored parent transform survives construction")
		var expected := Transform3D(basis,Vector3(1,2,3)) * Transform3D(Basis.from_scale(Vector3(0.002,0.003,-0.004)),Vector3(2,3,4))
		test.check(child.global_transform.is_equal_approx(expected), "Nested world basis and translation match composed authored values")
		parent.free()
	for basis in [Basis.from_scale(Vector3(0,1,1)),Basis(Vector3.RIGHT,Vector3.RIGHT,Vector3.BACK),Basis(Vector3(INF,0,0),Vector3.UP,Vector3.BACK),Basis(Vector3(NAN,0,0),Vector3.UP,Vector3.BACK),Basis(Vector3.RIGHT,Vector3(1,0.00000001,0),Vector3.BACK)]:
		test.check(not Validation.is_basis_valid(basis), "Singular/nonfinite/numerically dependent input rejected")
	var euler_scale := Vector3(0.000001,0.000002,-0.000003)
	test.check(factory._safe_scale_from_data({"scale":euler_scale},"regression") == euler_scale,"Euler compatibility path also preserves nonzero small scales")
	test.check(factory.invalid_basis_fallbacks == 0, "Valid small bases never fall back")
	var invalid_data := {"type":"group","has_basis":true,"basis_x":Vector3(INF,0,0)}
	var fallback: Node3D = factory.create_scene_node(invalid_data,null,cache)
	test.check(fallback.transform == Transform3D.IDENTITY and factory.invalid_basis_fallbacks == 1,"Non-finite construction falls back once to a finite transform")
	test.check(is_finite(factory._extract_visual_scale_hint(invalid_data)),"Non-finite source basis cannot poison fallback visual dimensions")
	fallback.free()
	cache.clear()
	test.finish(self)
