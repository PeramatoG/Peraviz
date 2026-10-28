extends RefCounted

# Setup only, after winding correction and before picking/optical renderer installation.
static func install(nodes: Array, node_index: Dictionary, cache: RefCounted, budget: SceneLoadBudget = null) -> bool:
	var optical_sources: Dictionary = {}
	for data: Dictionary in nodes:
		if data.get("is_beam",false) or data.get("is_emitter",false) or data.get("is_lens",false) or (data.get("type","") == "fixture_geometry" and not data.get("is_model_lod_candidate",false)):
			optical_sources[str(data.get("asset_path",""))] = true
	for data: Dictionary in nodes:
		if budget != null and not await budget.checkpoint(): return false
		var path: String = str(data.get("asset_path",""))
		# Scenery, primitives and nested glTF scenes retain their independent future policy.
		if not data.get("is_model_lod_candidate",false) or str(data.get("type","")) != "fixture_geometry" or path.get_extension().to_lower() != "3ds" or optical_sources.has(path) or not str(data.get("asset_error","")).is_empty(): continue
		var owner: Node3D = node_index.get(str(data.get("node_id","")))
		if owner == null or not owner.has_meta("peraviz_model_visual"): continue
		var visual: Node3D = owner.get_meta("peraviz_model_visual")
		var meshes: Array = visual.find_children("*","MeshInstance3D",true,false)
		if visual is MeshInstance3D: meshes.append(visual)
		for mesh: MeshInstance3D in meshes:
			if not mesh.mesh is ArrayMesh or mesh.skin != null or mesh.material_override != null or mesh.material_overlay != null or mesh.transparency != 0.0 or mesh.get_blend_shape_count() != 0: continue
			var safe: bool = true
			for surface in range(mesh.mesh.get_surface_count()):
				var material: Material = mesh.get_active_material(surface)
				if not material is StandardMaterial3D or material.emission_enabled or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.next_pass != null or material.grow: safe = false
			if not safe: continue
			var identity: String = JSON.stringify([path,data.get("model_quality","default"),"3ds",mesh.get_meta("peraviz_flip_orientation_applied",false),FileAccess.get_modified_time(path)])
			var result: Dictionary = cache.derive(mesh.mesh,60.0,identity)
			owner.set_meta("peraviz_housing_lod",{"source":data.get("asset_archive_path",path),"quality":data.get("model_quality","default"),"excluded":result.excluded})
			if result.excluded.is_empty():
				mesh.mesh = result.mesh
				owner.set_meta("peraviz_housing_lod",{"source":data.get("asset_archive_path",path),"quality":data.get("model_quality","default"),"levels":result.levels,"processing_us":result.total_us,"original":result.source_buffers,"derived":result.derived_buffers})
	print("[PeravizHousingLOD] ",JSON.stringify({"generated":cache.generations,"source_triangles_processed":cache.processed_triangles,"skips":cache.skips}))
	return true
