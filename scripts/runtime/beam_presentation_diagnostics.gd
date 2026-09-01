extends RefCounted
class_name BeamPresentationDiagnostics

var _ids: Dictionary = {"vector": {}, "fog": {}, "mask": {}, "projector": {}, "shadow": {}, "gobo_visible": {}, "open_visible": {}}

func update(loader: Node, light: SpotLight3D) -> Dictionary:
	var light_id: int = light.get_instance_id()
	var beam: MeshInstance3D = light.get_meta("peraviz_volumetric_beam") as MeshInstance3D if light.has_meta("peraviz_volumetric_beam") else null
	var beam_visible: bool = beam != null and is_instance_valid(beam) and beam.visible
	var flags: Dictionary = {
		"vector": beam_visible,
		"fog": light.get_node_or_null("PeravizFogVolumeGoboBeam") != null,
		"mask": light.has_meta("peraviz_gobo_plane"),
		"projector": light.light_projector != null,
		"shadow": light.shadow_enabled,
		"gobo_visible": light.has_meta("peraviz_gobo_texture") and beam_visible,
		"open_visible": not light.has_meta("peraviz_gobo_texture") and beam_visible,
	}
	for key in flags.keys():
		var category: Dictionary = _ids[key]
		if bool(flags[key]):
			category[light_id] = true
		else:
			category.erase(light_id)
	var settings: Variant = loader.get("_visual_settings") if loader != null else null
	return {
		"beam_presentation": int((settings as Dictionary).get("beam_presentation", 1)) if settings is Dictionary else 1,
		"active_vector_prisms": (_ids["vector"] as Dictionary).size(),
		"active_fog_volumes": (_ids["fog"] as Dictionary).size(),
		"active_shadow_masks": (_ids["mask"] as Dictionary).size(),
		"active_light_projectors": (_ids["projector"] as Dictionary).size(),
		"shadow_enabled_spotlights": (_ids["shadow"] as Dictionary).size(),
		"gobo_visible_beams": (_ids["gobo_visible"] as Dictionary).size(),
		"open_visible_beams": (_ids["open_visible"] as Dictionary).size(),
	}
