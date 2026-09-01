extends RefCounted
class_name FogVolumeGoboBeamController

const FOG_VOLUME_NODE_NAME: String = "PeravizFogVolumeGoboBeam"
const FOG_SHADER_PATH: String = "res://scripts/shaders/fog_volume_gobo_beam.gdshader"
const STATE_META_KEY: String = "peraviz_fog_volume_state"

var _open_texture: Texture2D

func update_for_light(light: SpotLight3D, beam_params: Dictionary, gobo_texture: Texture2D, visual_settings: Dictionary) -> Dictionary:
	var result := {"changed": false, "resource_created": false, "visibility_changed": false, "parameter_write_count": 0}
	if light == null or not is_instance_valid(light):
		return result
	var beam_type: String = str(beam_params.get("beam_type", "Wash")).to_lower()
	var intensity_max: float = max(float(beam_params.get("intensity_max", 100.0)), 0.01)
	var scaled_intensity: float = clamp(float(beam_params.get("scaled_intensity", beam_params.get("beam_intensity", 0.0))), 0.0, intensity_max)
	var threshold: float = float(beam_params.get("intensity_visibility_threshold", 0.015))
	var active: bool = beam_type != "none" and beam_type != "glow" and scaled_intensity > threshold
	var fog_volume: FogVolume = light.get_node_or_null(FOG_VOLUME_NODE_NAME) as FogVolume
	if not active:
		if fog_volume != null and fog_volume.visible:
			fog_volume.visible = false
			result["changed"] = true
			result["visibility_changed"] = true
		_record_counters(light, result)
		return result
	if fog_volume == null:
		fog_volume = _create_volume(light)
		result["changed"] = true
		result["resource_created"] = true
	if not fog_volume.visible:
		fog_volume.visible = true
		result["changed"] = true
		result["visibility_changed"] = true

	var beam_range: float = max(float(beam_params.get("beam_range", light.spot_range)), 0.1)
	var beam_angle: float = max(float(beam_params.get("beam_angle", light.spot_angle * 2.0)), 0.1)
	var lens_radius: float = max(float(beam_params.get("lens_radius", 0.03)), 0.001)
	var cone_radius: float = lens_radius + tan(deg_to_rad(beam_angle * 0.5)) * beam_range
	var values := {
		"size": Vector3(max(cone_radius * 2.0, 0.1), max(cone_radius * 2.0, 0.1), beam_range),
		"position": Vector3(0.0, 0.0, -beam_range * 0.5),
		"gobo_texture": gobo_texture if gobo_texture != null else _get_open_texture(),
		"use_gobo": gobo_texture != null,
		"light_color": Color(beam_params.get("beam_color", Color.WHITE)),
		"intensity": clamp(scaled_intensity / min(intensity_max, 20.0), 0.0, 1.0),
		"density_scale": float(visual_settings.get("fog_volume_density_scale", 1.1)) * max(float(beam_params.get("haze_density_multiplier", 0.22)), 0.01),
		"emission_strength": float(visual_settings.get("fog_volume_emission_strength", 1.5)),
		"edge_softness": float(visual_settings.get("fog_volume_edge_softness", 0.72)),
		"invert_gobo": bool(visual_settings.get("fog_volume_invert_gobo", false)),
		"gobo_scale": max(float(beam_params.get("gobo_scale", 1.0)), 0.05),
		"gobo_rotation_deg": float(beam_params.get("gobo_rotation_deg", 0.0)),
		"near_radius_ratio": clamp(lens_radius / max(cone_radius, 0.001), 0.0, 1.0),
		"radial_falloff": max(float(beam_params.get("beam_radial_falloff", 1.25)), 0.05),
		"longitudinal_falloff": max(float(beam_params.get("beam_longitudinal_falloff", 1.1)), 0.05),
	}
	var previous: Dictionary = fog_volume.get_meta(STATE_META_KEY, {})
	if previous.get("size") != values["size"]:
		fog_volume.size = values["size"]
		result["changed"] = true
	if previous.get("position") != values["position"]:
		fog_volume.position = values["position"]
		result["changed"] = true
	var material: ShaderMaterial = fog_volume.material as ShaderMaterial
	for key in values.keys():
		if key == "size" or key == "position" or previous.get(key) == values[key]:
			continue
		material.set_shader_parameter(key, values[key])
		result["parameter_write_count"] = int(result["parameter_write_count"]) + 1
		result["changed"] = true
	fog_volume.set_meta(STATE_META_KEY, values)
	_record_counters(light, result)
	return result

func _record_counters(light: SpotLight3D, result: Dictionary) -> void:
	light.set_meta("peraviz_fog_volume_creations", int(light.get_meta("peraviz_fog_volume_creations", 0)) + (1 if bool(result.get("resource_created", false)) else 0))
	light.set_meta("peraviz_fog_parameter_writes", int(light.get_meta("peraviz_fog_parameter_writes", 0)) + int(result.get("parameter_write_count", 0)))

func clear_for_light(light: SpotLight3D) -> void:
	if light == null or not is_instance_valid(light):
		return
	var existing: Node = light.get_node_or_null(FOG_VOLUME_NODE_NAME)
	if existing != null:
		light.remove_child(existing)
		existing.queue_free()

func _create_volume(light: SpotLight3D) -> FogVolume:
	var fog_volume := FogVolume.new()
	fog_volume.name = FOG_VOLUME_NODE_NAME
	fog_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	fog_volume.material = ShaderMaterial.new()
	(fog_volume.material as ShaderMaterial).shader = load(FOG_SHADER_PATH)
	fog_volume.visible = false
	light.add_child(fog_volume)
	return fog_volume

func _get_open_texture() -> Texture2D:
	if _open_texture != null:
		return _open_texture
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_open_texture = ImageTexture.create_from_image(image)
	return _open_texture
