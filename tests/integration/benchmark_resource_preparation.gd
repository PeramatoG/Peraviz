extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var loader: Object = ClassDB.instantiate("PeravizLoader")
	var source: String = OS.get_cmdline_user_args()[0]
	var nodes: Array = loader.load_mvr(source,false,false)
	var parent := Node3D.new()
	root.add_child(parent)
	parent.hide()
	var cache := PeravizRuntimeAssetCache.new()
	var factory := NodeFactory.new()
	var index: Dictionary = {}
	var budget := SceneLoadBudget.new()
	budget.tree = self
	budget.current = func() -> bool: return true
	budget.trace_enabled = true
	var started := Time.get_ticks_usec()
	var ok: bool = await factory.build_node_tree(nodes,parent,index,func() -> void: pass,loader,cache,budget)
	var textures: Dictionary = {}
	for node: Node3D in index.values():
		if not node.has_meta("peraviz_model_visual"): continue
		var visual: Node3D = node.get_meta("peraviz_model_visual")
		if visual == null or visual.get_meta("peraviz_dummy_placeholder",false): continue
		var instances: Array = visual.find_children("*","MeshInstance3D",true,false)
		if visual is MeshInstance3D: instances.append(visual)
		for instance: MeshInstance3D in instances:
			for surface in range(instance.mesh.get_surface_count()):
				var material: Material = instance.get_active_material(surface)
				if material is BaseMaterial3D and material.albedo_texture != null: textures[material.albedo_texture] = true

	print("RESOURCE_PREPARATION_BENCHMARK ",JSON.stringify({"ok":ok,"nodes":nodes.size(),"wall_ms":(Time.get_ticks_usec()-started)/1000.0,"yielded_frames":budget.yields,"budget_yield_wait_ms":budget.yield_wait_us/1000.0,"metrics":factory.setup_metrics,"cache":cache.debug_summary(),"texture_resources":textures.size()}))
	parent.queue_free()
	cache.clear()
	loader.free()
	await process_frame
	quit(0 if ok else 1)
