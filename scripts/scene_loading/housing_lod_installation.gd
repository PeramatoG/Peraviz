extends RefCounted

# Setup only, after import/winding corrections and before picking/optical bindings.
static func install(nodes: Array, node_index: Dictionary, cache: RefCounted, budget: SceneLoadBudget = null) -> bool:
	var optical_sources: Dictionary = {}
	var optical_meshes: Dictionary = {}
	# Resolve mixed ownership before deriving anything, independent of traversal order.
	for data: Dictionary in nodes:
		if budget != null and not await budget.checkpoint(): return false
		var path: String = str(data.get("asset_path",""))
		var optical: bool = _optical(data)
		var owner: Node3D = node_index.get(str(data.get("node_id","")))
		if owner != null and owner.has_meta("peraviz_model_visual"):
			var visual: Node3D = owner.get_meta("peraviz_model_visual")
			for instance: MeshInstance3D in _instances(visual):
				if instance.mesh == null: continue
				var emitting: bool = false
				for surface in range(instance.mesh.get_surface_count()):
					var material: Material = instance.get_active_material(surface)
					if material is BaseMaterial3D and material.emission_enabled: emitting = true
				if optical or emitting: optical_meshes[instance.mesh.get_instance_id()] = true
				if emitting: optical = true
		if optical and not path.is_empty(): optical_sources[path] = true
	for data: Dictionary in nodes:
		if budget != null and not await budget.checkpoint(): return false
		var owner: Node3D = node_index.get(str(data.get("node_id","")))
		if owner == null or not owner.has_meta("peraviz_model_visual"): continue
		var visual: Node3D = owner.get_meta("peraviz_model_visual")
		var path: String = str(data.get("asset_path",""))
		var extension: String = path.get_extension().to_lower()
		var route: String = "3ds" if extension == "3ds" else "runtime_gltf" if extension in ["glb","gltf"] else "primitive" if path.is_empty() else "resource_loader"
		var reason: String = ""
		if data.get("type","") != "fixture_geometry": reason = "scenery_deferred"
		elif _optical(data) or optical_sources.has(path): reason = "optical_or_mixed_ownership"
		elif not str(data.get("asset_error","")).is_empty(): reason = "asset_error"
		elif extension not in ["3ds","glb","gltf"]: reason = "primitive_or_unsupported_route"
		elif not visual.find_children("*","AnimationPlayer",true,false).is_empty() or not visual.find_children("*","Skeleton3D",true,false).is_empty(): reason = "animated_scene"
		var instances: Array = _instances(visual)
		for instance: MeshInstance3D in instances:
			var exclusion: String = reason
			if instance.mesh != null and optical_meshes.has(instance.mesh.get_instance_id()): exclusion = "optical_or_mixed_ownership"
			if exclusion.is_empty() and (not instance.mesh is ArrayMesh or instance.skin != null or instance.material_overlay != null or instance.transparency != 0.0 or instance.get_blend_shape_count() != 0): exclusion = "deformed_or_instance_effect"
			if exclusion.is_empty():
				for surface in range(instance.mesh.get_surface_count()):
					var material: Material = instance.get_active_material(surface)
					if not material is StandardMaterial3D or material.emission_enabled or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.next_pass != null or material.grow or material.proximity_fade_enabled or material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED: exclusion = "incompatible_active_material"
			if exclusion.is_empty() and not cache.automatic: exclusion = "disabled_at_import"
			var result: Dictionary = {}
			if exclusion.is_empty():
				var identity: String = JSON.stringify([path,data.get("model_quality","default"),extension,instance.get_meta("peraviz_flip_orientation_applied",false),FileAccess.get_modified_time(path)])
				result = cache.derive(instance.mesh,60.0,identity)
				exclusion = result.excluded
			cache.record(instance,data,route,"generated" if exclusion.is_empty() else exclusion)
			owner.set_meta("peraviz_housing_lod",{"source":data.get("asset_archive_path",path),"quality":data.get("model_quality","default"),"route":route,"excluded":exclusion})
			if not exclusion.is_empty(): continue
			cache.bind_instance(instance,instance.mesh,result.mesh)
			owner.set_meta("peraviz_housing_lod",{"source":data.get("asset_archive_path",path),"quality":data.get("model_quality","default"),"route":route,"levels":result.levels,"processing_us":result.total_us,"original":result.source_buffers,"derived":result.derived_buffers})
	return true

static func _instances(visual: Node3D) -> Array:
	var result: Array = visual.find_children("*","MeshInstance3D",true,false)
	if visual is MeshInstance3D: result.append(visual)
	return result

static func _optical(data: Dictionary) -> bool:
	return data.get("is_beam",false) or data.get("is_emitter",false) or data.get("is_lens",false) or (data.get("type","") == "fixture_geometry" and not data.get("is_model_lod_candidate",false))
