extends SceneTree

# The pre-fix built-in path, kept only as a differential/performance reference.
# Authored imported materials never pass through this descriptor constructor.
class LegacyFactory extends NodeFactory:
	var reference_cache := PeravizRuntimeAssetCache.new()
	func _create_dummy_mesh(is_fixture: bool, visual_scale_hint: float, _asset_cache: PeravizRuntimeAssetCache = null) -> Node3D:
		setup_metrics["dummy_instances_created"] = int(setup_metrics.get("dummy_instances_created",0)) + 1
		var visual := MeshInstance3D.new()
		visual.set_meta("peraviz_dummy_placeholder",true)
		var multiplier: float = 0.35/max(visual_scale_hint,0.0001)
		if is_fixture:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.15*multiplier
			cone.height = 0.4*multiplier
			visual.mesh = cone
		else:
			var box := BoxMesh.new()
			box.size = Vector3.ONE*(0.3*multiplier)
			visual.mesh = box
		var material_started := Time.get_ticks_usec() if _profile_setup else 0
		var key := "fixture" if is_fixture else "object"
		var material: Material = reference_cache.get_material(key,true)
		if material == null:
			var prototype := StandardMaterial3D.new()
			prototype.albedo_color = Color(1.0,0.5,0.1) if is_fixture else Color(0.2,0.8,1.0)
			reference_cache.store_material(key,prototype)
			material = reference_cache.get_material(key,true)
		visual.material_override = material
		_record_setup("dummy_material_ms",material_started)
		_force_double_sided_materials(visual)
		return visual

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var count: int = 1000
	for arg: String in args:
		if arg.begins_with("--count="): count = int(arg.trim_prefix("--count="))
	var factory: NodeFactory = LegacyFactory.new() if args.has("--reference") else NodeFactory.new()
	var cache := PeravizRuntimeAssetCache.new()
	var loader: Object = ClassDB.instantiate("PeravizLoader")
	var parent := Node3D.new()
	parent.hide()
	root.add_child(parent)
	var nodes: Array = []
	for i in range(count):
		nodes.append({"node_id":str(i),"type":"scene_object","name":"Object","pos":Vector3(i,0,0)})
	var index: Dictionary = {}
	var budget := SceneLoadBudget.new()
	budget.tree = self
	budget.current = func() -> bool: return true
	budget.trace_enabled = true
	var started := Time.get_ticks_usec()
	var ok: bool = await factory.build_node_tree(nodes,parent,index,func() -> void: pass,loader,cache,budget)
	print("BUILTIN_PLACEHOLDER_BENCHMARK ",JSON.stringify({"reference":args.has("--reference"),"instances":count,"ok":ok,"wall_ms":(Time.get_ticks_usec()-started)/1000.0,"yielded_frames":budget.yields,"yield_wait_ms":budget.yield_wait_us/1000.0,"metrics":factory.setup_metrics,"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name()}))
	parent.queue_free()
	cache.clear()
	loader.free()
	await process_frame
	quit(0 if ok else 1)
