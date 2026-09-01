extends SceneTree

const Topology = preload("res://scripts/beam_renderers/gobo_compound_topology.gd")
const Builder = preload("res://scripts/beam_renderers/gobo_prism_mesh_builder.gd")
const HeadlessTestCaseScript = preload("res://tests/gdscript/headless_test_case.gd")

var test = HeadlessTestCaseScript.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_hierarchy_and_hole_caps()
	_test_concave_and_budget_simplification()
	_test_orientation_and_cache()
	test.finish(self)

func _test_hierarchy_and_hole_caps() -> void:
	var outer := PackedVector2Array([Vector2(-5, -5), Vector2(5, -5), Vector2(5, 5), Vector2(-5, 5)])
	var hole := PackedVector2Array([Vector2(-3, -3), Vector2(-3, 3), Vector2(3, 3), Vector2(3, -3)])
	var island := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	var disconnected := PackedVector2Array([Vector2(8, 0), Vector2(10, 0), Vector2(10, 2), Vector2(8, 2)])
	var components: Array[Dictionary] = Topology.build([hole, disconnected, island, outer])
	test.check(components.size() == 3, "outer-hole-island nesting and disconnected fills must create three filled components")
	var donut: Dictionary = components.filter(func(component: Dictionary) -> bool: return (component["holes"] as Array).size() == 1)[0]
	test.check(Topology.signed_area(donut["outer"]) > 0.0 and Topology.signed_area(donut["holes"][0]) < 0.0, "outer and hole winding must follow explicit ring roles")
	var triangles: Array[Dictionary] = Topology.triangulate(donut)
	test.check(not triangles.is_empty(), "hole-aware clipping must produce cap triangles")
	test.check(not _triangles_cover(triangles, Vector2(2, 0)), "cap triangles must not cover a point inside the donut hole")
	test.check(_triangles_cover(triangles, Vector2(4, 0)), "cap triangles must cover the illuminated donut body")

func _test_concave_and_budget_simplification() -> void:
	var crescent := PackedVector2Array([Vector2(4, 0), Vector2(2, 1), Vector2(0, 4), Vector2(-4, 1), Vector2(-3, -3), Vector2(0, -1), Vector2(2, -2)])
	var simplified: PackedVector2Array = Topology.simplify_closed_ring(crescent, 5)
	test.check(simplified.size() <= 5 and not Topology.has_self_intersections(simplified), "closed concave simplification must preserve cyclic topology without a seam crossing")
	test.check((Topology.signed_area(simplified) > 0.0) == (Topology.signed_area(crescent) > 0.0), "closed simplification must preserve winding")
	var curved := PackedVector2Array()
	for index in range(160):
		var angle: float = TAU * float(index) / 160.0
		var radius: float = 4.0 + 0.35 * sin(angle * 7.0)
		curved.append(Vector2(cos(angle), sin(angle)) * radius)
	var budgeted: PackedVector2Array = Topology.simplify_closed_ring(curved, 40)
	test.check(budgeted.size() == 40 and not Topology.has_self_intersections(budgeted), "high-point curved contours must meet their budget without crossings")
	var narrow_hole := PackedVector2Array([Vector2(-0.2, -3), Vector2(-0.2, 3), Vector2(0.2, 3), Vector2(0.2, -3)])
	var narrow_components: Array[Dictionary] = Topology.build([outer_square(5.0), narrow_hole])
	test.check((narrow_components[0]["holes"] as Array).size() == 1, "a narrow meaningful cut-out must remain a distinct hole")

func _test_orientation_and_cache() -> void:
	var builder = Builder.new()
	var source := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 1), Vector2(1, 1), Vector2(1, 4), Vector2(0, 4)])
	var normalized: PackedVector2Array = builder._normalize_polygon_to_local_space(source, 0.25, 0.25)
	test.check(normalized[0].is_equal_approx(Vector2(-1, -1)) and normalized[2].is_equal_approx(Vector2(1, -0.5)), "asymmetric source coordinates must not be vertically inverted during normalization")
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(5, 27):
		for x in range(5, 12):
			image.set_pixel(x, y, Color.WHITE)
	for y in range(20, 27):
		for x in range(5, 25):
			image.set_pixel(x, y, Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var first: ArrayMesh = builder.build_normalized_beam_mesh(texture, false)
	var second: ArrayMesh = builder.build_normalized_beam_mesh(texture, false)
	var counters: Dictionary = builder.get_counters()
	test.check(first == second and int(counters["normalized_topology_creations"]) == 1 and int(counters["normalized_topology_cache_hits"]) == 1, "fixture reuse and live optical changes must reuse cached topology")

func outer_square(radius: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-radius, -radius), Vector2(radius, -radius), Vector2(radius, radius), Vector2(-radius, radius)])

func _triangles_cover(triangles: Array[Dictionary], point: Vector2) -> bool:
	for triangle in triangles:
		if Geometry2D.is_point_in_polygon(point, PackedVector2Array([triangle["a"], triangle["b"], triangle["c"]])):
			return true
	return false
