extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var state := SceneSelection.new()
	var scene := Node3D.new()
	root.add_child(scene)
	var fixture := Node3D.new()
	scene.add_child(fixture)
	fixture.set_meta("peraviz_fixture_uuid", "uuid-fixture")
	var geometry := MeshInstance3D.new()
	geometry.mesh = BoxMesh.new()
	fixture.add_child(geometry)
	geometry.set_meta("peraviz_fixture_uuid", "uuid-fixture")
	var light := SpotLight3D.new()
	fixture.add_child(light)
	var shaft := MeshInstance3D.new()
	shaft.mesh = BoxMesh.new()
	shaft.scale = Vector3.ONE * 100.0
	light.add_child(shaft)
	state.publish({"uuid-fixture": fixture, "uuid-fixture/geometry": geometry})
	test.check(state.id_for(geometry) == "uuid-fixture", "Internal geometry resolves to stable fixture ownership")
	state.select(PackedStringArray(["missing", "uuid-fixture", "uuid-fixture"]))
	test.check(state.ids == PackedStringArray(["uuid-fixture"]), "Selection rejects invalid IDs and duplicate members")
	test.check(state.bounds().size.length() < 4.0, "Frame selection excludes runtime shaft extent")
	state.select(PackedStringArray(["uuid-fixture", "uuid-fixture/geometry"]))
	test.check(state.ids.size() == 2, "Selection contract supports multiple stable IDs")
	var explorer := SceneExplorer.new()
	root.add_child(explorer)
	explorer.configure(state)
	var nodes: Dictionary = {"uuid-fixture": fixture}
	for i in range(5000):
		var node := Node3D.new()
		node.set_meta("peraviz_type", "scene_object")
		node.set_meta("peraviz_name", "Scenery %d" % i)
		scene.add_child(node)
		nodes[str(i)] = node
	state.publish(nodes)
	var provider := FixtureRowProvider.new()
	explorer.publish(nodes, provider)
	test.check(explorer._items.size() == 5001 and explorer.tree.get_child_count() < 5, "Thousands of objects use lightweight TreeItems without per-row Controls")
	explorer.search.text = "Scenery 4242"
	explorer._filter(explorer.search.text)
	test.check(explorer._items["4242"].visible and not explorer._items["4241"].visible, "Search filters by identifying text")
	state.select(PackedStringArray(["uuid-fixture"]))
	state.retire()
	test.check(state.ids.is_empty() and state.node_for("uuid-fixture") == null, "Retirement releases node references and stale selection")
	explorer.free()
	scene.free()
	await process_frame
	test.finish(self)
