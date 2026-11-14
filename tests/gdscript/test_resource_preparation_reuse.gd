extends SceneTree

const TestCase = preload("res://tests/gdscript/headless_test_case.gd")
var test = TestCase.new()
var loader: Object

func _initialize() -> void:
	call_deferred("_run")

func _generate(path: String, kind: String, count: int, repeated: bool = false, animated: bool = false) -> Array:
	var args := PackedStringArray([ProjectSettings.globalize_path("res://tests/integration/generate_resource_preparation_fixture.py"),path,"--count",str(count),"--kind",kind])
	if repeated: args.append("--repeated")
	if animated: args.append("--animated")
	test.check(OS.execute("python3",args) == 0,"Generate public cold model resources")
	return loader.load_mvr(path,false,false)

func _build(nodes: Array, mirrored_proxy: bool = false) -> Dictionary:
	var parent := Node3D.new()
	if mirrored_proxy: parent.scale.x = -1
	root.add_child(parent)
	parent.hide()
	var index: Dictionary = {}
	var factory := NodeFactory.new()
	var cache := PeravizRuntimeAssetCache.new()
	test.check(await factory.build_node_tree(nodes,parent,index,func() -> void: pass,loader,cache),"Model preparation completes")
	return {"parent":parent,"index":index,"factory":factory,"cache":cache}

func _dispose(context: Dictionary) -> void:
	context.parent.queue_free()
	context.index.clear()
	context.cache.clear()
	test.check(context.cache.debug_summary().texture_unique == 0,"Retirement releases decoded texture cache")
	await process_frame

func _run() -> void:
	loader = ClassDB.instantiate("PeravizLoader")
	var path: String = ProjectSettings.globalize_path("user://resource_reuse_%d.mvr" % OS.get_process_id())
	var nodes: Array = _generate(path,"3ds",8)
	# Reverse order proves winding planning does not assume parents arrive first.
	nodes.reverse()
	for mirrored_proxy in [false,true]:
		var context: Dictionary = await _build(nodes,mirrored_proxy)
		test.check(context.factory.setup_metrics.mesh_decode_calls == 8 and context.cache.debug_summary().mesh_unique == 8,"Exactly the required winding variant decodes for each distinct model")
		test.check(context.factory.setup_metrics.texture_decode_calls == 1 and context.cache.debug_summary().texture_unique == 1,"Distinct meshes share one decoded albedo texture")
		test.check(context.cache.debug_summary().hits_by_kind.texture == 7 and context.cache.debug_summary().misses_by_kind.texture == 1,"Texture cache hits and misses describe actual image reuse")
		var textures: Dictionary = {}
		for data: Dictionary in nodes:
			if data.get("type","") != "model_part": continue
			var node: Node3D = context.index[data.node_id]
			var visual: MeshInstance3D = node.get_meta("peraviz_model_visual")
			var expected_flip: bool = not mirrored_proxy
			test.check(visual.get_meta("peraviz_flip_orientation_applied") == expected_flip,"Inherited and double reflection winding is correct before late repair")
			var raw: Dictionary = loader.load_3ds_mesh_data(data.asset_path)
			var reference: ArrayMesh = NodeFactory.new()._build_3ds_mesh(raw,expected_flip)
			var actual: Array = visual.mesh.surface_get_arrays(0)
			var expected: Array = reference.surface_get_arrays(0)
			for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_INDEX]:
				test.check(actual[channel] == expected[channel],"Cold planned winding preserves exact mesh buffers")
			textures[visual.get_active_material(0).albedo_texture] = true
			var owner: Node3D = node.get_parent()
			var local_index: int = int(str(data.parent_id).get_slice("-",1))
			var expected_position := Vector3(1-local_index,3,-2)
			if mirrored_proxy: expected_position.x = -expected_position.x
			test.check(owner.global_position.is_equal_approx(expected_position),"Parent hierarchy and world translation remain exact")
		test.check(textures.size() == 1,"Physical instances use the shared texture resource")
		await _dispose(context)
	var image_path: String = ""
	for data: Dictionary in nodes:
		if data.get("type","") == "model_part":
			image_path = loader.load_3ds_mesh_data(data.asset_path).texture_path
			break
	var other_path: String = ProjectSettings.globalize_path("user://resource_texture_other_%d/shared.png" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(other_path.get_base_dir())
	test.check(DirAccess.copy_absolute(image_path,other_path) == OK,"Create same-name texture in another directory")
	var texture_cache := PeravizRuntimeAssetCache.new()
	var texture_factory := NodeFactory.new()
	texture_cache.mark_texture_failed(image_path)
	test.check(texture_factory._load_3ds_texture(image_path,texture_cache) == null and texture_factory.setup_metrics.get("texture_decode_calls",0) == 0,"Failed image state prevents repeated decoding within the generation")
	texture_cache.clear()
	var first: Texture2D = texture_factory._load_3ds_texture(image_path,texture_cache)
	var second: Texture2D = texture_factory._load_3ds_texture(other_path,texture_cache)
	test.check(first != null and second != null and first != second and first.get_width() == 16,"Retry after retirement preserves distinct resolved texture identities")
	texture_cache.clear()
	DirAccess.remove_absolute(other_path)
	DirAccess.remove_absolute(other_path.get_base_dir())
	# Cancellation after the first decode must dispose every detached native shell.
	var cancelled_root := Node3D.new()
	root.add_child(cancelled_root)
	var cancelled_cache := PeravizRuntimeAssetCache.new()
	var cancelled_factory := NodeFactory.new()
	var cancelled_index: Dictionary = {}
	var budget := SceneLoadBudget.new()
	budget.tree = self
	budget.current = func() -> bool: return int(cancelled_factory.setup_metrics.get("mesh_decode_calls",0)) == 0
	test.check(not await cancelled_factory.build_node_tree(nodes,cancelled_root,cancelled_index,func() -> void: pass,loader,cancelled_cache,budget),"Cancellation interrupts model preparation before attachment")
	test.check(cancelled_root.get_child_count() == 0,"Cancelled generation never publishes detached shells")
	for node in cancelled_index.values(): test.check(not is_instance_valid(node),"Unattached cancelled nodes are freed")
	cancelled_index.clear()
	cancelled_cache.clear()
	cancelled_root.queue_free()
	await process_frame
	for animated in [false,true]:
		nodes = _generate(path,"glb",1,false,animated)
		var context: Dictionary = await _build(nodes)
		test.check(context.factory.setup_metrics.scene_decode_calls == 1 and context.factory.setup_metrics.scene_pack_calls == 1 and context.factory.setup_metrics.scene_clone_calls == 1,"Singleton glTF retains the established PackedScene lifecycle")
		var part: Node3D
		for data: Dictionary in nodes:
			if data.get("type","") == "model_part": part = context.index[data.node_id]
		var visual: Node3D = part.get_meta("peraviz_model_visual")
		var animations: Array = visual.find_children("*","AnimationPlayer",true,false)
		test.check((not animations.is_empty()) == animated,"Singleton retains imported animation hierarchy")
		if animated: _check_animation(animations[0])
		await _dispose(context)
	nodes = _generate(path,"glb",2,true,true)
	var context: Dictionary = await _build(nodes)
	test.check(context.factory.setup_metrics.scene_decode_calls == 1 and context.factory.setup_metrics.scene_pack_calls == 1 and context.factory.setup_metrics.scene_clone_calls == 2,"Repeated animated glTF keeps the PackedScene route with one decode")
	var visuals: Array[Node3D] = []
	for data: Dictionary in nodes:
		if data.get("type","") == "model_part": visuals.append(context.index[data.node_id].get_meta("peraviz_model_visual"))
	test.check(visuals.size() == 2 and visuals[0] != visuals[1],"Repeated models retain independent scene node instances")
	var second_player: AnimationPlayer = visuals[1].find_children("*","AnimationPlayer",true,false)[0]
	var second_target: Node3D = _animation_target(second_player)
	var second_position: Vector3 = second_target.position
	_check_animation(visuals[0].find_children("*","AnimationPlayer",true,false)[0])
	test.check(second_target.position == second_position,"Playback state belongs to the individual glTF instance")
	var second_transform: Transform3D = visuals[1].transform
	visuals[0].position += Vector3.ONE
	test.check(visuals[1].transform == second_transform,"Instance transform edits never affect another model")
	await _dispose(context)
	loader.free()
	DirAccess.remove_absolute(path)
	test.finish(self)

func _animation_target(player: AnimationPlayer) -> Node3D:
	var animation: Animation = player.get_animation("MovingHousing")
	var animation_root: Node = player.get_node(player.root_node)
	return animation_root.get_node(NodePath(animation.track_get_path(0).get_concatenated_names()))

func _check_animation(player: AnimationPlayer) -> void:
	test.check(player.has_animation("MovingHousing"),"Authored animation remains available")
	var target: Node3D = _animation_target(player)
	player.play("MovingHousing")
	player.seek(0.5,true)
	test.check(is_equal_approx(target.position.x,0.15),"Imported translation track still produces its authored pose")
