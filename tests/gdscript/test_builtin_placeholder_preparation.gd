extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
const Reference = preload("res://tests/integration/benchmark_builtin_placeholders.gd")
var test = TestCase.new()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var factory := NodeFactory.new()
	var reference := Reference.LegacyFactory.new()
	for fixture in [false,true]:
		for scale in [0.001,1.0,1000.0]:
			var actual: MeshInstance3D = factory._create_dummy_mesh(fixture,scale)
			var expected: MeshInstance3D = reference._create_dummy_mesh(fixture,scale)
			test.check(actual.mesh.get_aabb().is_equal_approx(expected.mesh.get_aabb()),"Built-in shape retains exact legacy dimensions across scales")
			for pair in [[actual.material_override,expected.material_override],[actual.get_surface_override_material(0),expected.get_surface_override_material(0)]]:
				var a: Material = pair[0]
				var b: Material = pair[1]
				for property: Dictionary in b.get_property_list():
					if int(property.usage) & PROPERTY_USAGE_STORAGE:
						test.check(a.get(property.name) == b.get(property.name),"Built-in stored material state matches legacy: "+property.name)
			if OS.get_cmdline_user_args().has("--render-placeholder-probe") and scale == 1.0:
				await _compare_pixels(actual,expected)
			actual.queue_free()
			expected.queue_free()
	await process_frame
	var loader: Object = ClassDB.instantiate("PeravizLoader")
	var data: Array = [{"node_id":"group","type":"group","has_basis":true,"basis_x":Vector3(-0.001,0,0),"basis_y":Vector3(0,0.002,0),"basis_z":Vector3(0,0,0.003),"pos":Vector3(1,2,3)}]
	for i in range(10000):
		data.append({"node_id":str(i),"parent_id":"group","type":"scene_object","name":"Object","pos":Vector3(i,2,3)})
	for generation in range(2):
		var owner := Node3D.new()
		owner.hide()
		root.add_child(owner)
		var cache := PeravizRuntimeAssetCache.new()
		var index: Dictionary = {}
		var budget := SceneLoadBudget.new()
		budget.tree = self
		budget.current = func() -> bool: return true
		test.check(await factory.build_node_tree(data,owner,index,func() -> void: pass,loader,cache,budget),"Ten thousand placeholder owners build and reload")
		test.check(index.size() == 10001 and factory.setup_metrics.dummy_instances_created == 10000,"All semantic owners and required placeholders survive")
		var resources: Dictionary = {}
		for i in range(10000):
			var node: Node3D = index[str(i)]
			var visual: MeshInstance3D = node.get_meta("peraviz_model_visual")
			resources[visual.get_active_material(0)] = true
			test.check(node.get_parent() == index.group and node.global_position.is_equal_approx(Vector3(1-i*0.001,2.004,3.009)),"Nested small reflected transform and parent identity remain correct")
			test.check(visual.get_active_material(0).albedo_color == Color(0.2,0.8,1.0) and visual.get_active_material(0).cull_mode == BaseMaterial3D.CULL_DISABLED,"Placeholder presentation retains color and double-sided drawing")
		test.check(resources.size() == 10000,"Placeholder materials retain independent state")
		var first: MeshInstance3D = index["0"].get_meta("peraviz_model_visual")
		first.material_override.albedo_color = Color.RED
		var second: MeshInstance3D = index["1"].get_meta("peraviz_model_visual")
		test.check(second.material_override.albedo_color == Color(0.2,0.8,1.0),"Per-instance material edits do not propagate")
		owner.queue_free()
		index.clear()
		resources.clear()
		cache.clear()
		await process_frame
	# Cancel after the first placeholder; no partial shell may be published.
	var owner := Node3D.new()
	root.add_child(owner)
	var cache := PeravizRuntimeAssetCache.new()
	var index: Dictionary = {}
	var budget := SceneLoadBudget.new()
	budget.tree = self
	budget.current = func() -> bool: return int(factory.setup_metrics.get("dummy_instances_created",0)) == 0
	test.check(not await factory.build_node_tree(data,owner,index,func() -> void: pass,loader,cache,budget),"Placeholder construction honors generation cancellation")
	test.check(owner.get_child_count() == 0,"Cancelled placeholder generation remains unpublished")
	for node in index.values(): test.check(not is_instance_valid(node),"Cancelled detached shells are released")
	index.clear()
	cache.clear()
	owner.queue_free()
	loader.free()
	await process_frame
	test.finish(self)

func _capture(viewport: SubViewport) -> Image:
	for i in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _compare_pixels(actual: MeshInstance3D, expected: MeshInstance3D) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256,256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0.7,0.5,1)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-30,0)
	viewport.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02,0.02,0.02)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	viewport.add_child(env)
	viewport.add_child(expected)
	var before: Image = await _capture(viewport)
	viewport.remove_child(expected)
	viewport.add_child(actual)
	var after: Image = await _capture(viewport)
	viewport.remove_child(actual)
	test.check(before.get_data() == after.get_data(),"Forward+ placeholder pixels match legacy material/shape")
	var foreground: int = 0
	var background: Color = after.get_pixel(0,0)
	for y in range(after.get_height()):
		for x in range(after.get_width()):
			if after.get_pixel(x,y) != background: foreground += 1
	test.check(foreground > 100,"Graphical comparison contains actual geometry coverage")
	print("PLACEHOLDER_RENDER_PROBE foreground_pixels=",foreground," exact_match=",before.get_data()==after.get_data())
	viewport.queue_free()
	await process_frame
