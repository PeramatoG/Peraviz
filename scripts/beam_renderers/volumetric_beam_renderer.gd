extends BeamRendererBase

class_name VolumetricBeamRenderer

const BEAM_META_KEY: String = "peraviz_volumetric_beam"
const CORE_BEAM_META_KEY: String = "peraviz_volumetric_beam_core_layer"
const VOLUMETRIC_INTENSITY_SCALE: float = 4.0
const VOLUMETRIC_INTENSITY_RESPONSE_EXPONENT: float = 2.2
const INTENSITY_REFERENCE_MAX: float = 20.0
const VOLUMETRIC_OVERDRIVE_BRIGHTNESS_MAX: float = 30.0
const DEBUG_AXIS_KEY: String = "peraviz_beam_debug_axis"
const SHAPE_MODE_GOBO_PRISM: String = "gobo_prism"
const SHAPE_MODE_CONE: String = "cone"
const BeamAppearanceProfileScript = preload("res://scripts/beam_appearance_profile.gd")

var _beam_material_template: ShaderMaterial
var _camera: Camera3D
var _settings: Dictionary = {}
var _beam_settings_hash: int = 0
var _shape_providers: Dictionary = {}
var _active_shape_provider: VolumetricBeamShapeProvider

func _init() -> void:
	_beam_material_template = ShaderMaterial.new()
	_beam_material_template.shader = load("res://scripts/shaders/volumetric_beam.gdshader")
	_shape_providers[SHAPE_MODE_GOBO_PRISM] = VolumetricGoboPrismShapeProvider.new()
	_shape_providers[SHAPE_MODE_CONE] = VolumetricConeShapeProvider.new()
	_active_shape_provider = _shape_providers[SHAPE_MODE_GOBO_PRISM] as VolumetricBeamShapeProvider

func configure(view_camera: Camera3D, settings: Dictionary) -> void:
	_camera = view_camera
	_settings = settings.duplicate(true)
	_beam_settings_hash = _compute_beam_settings_hash()
	_active_shape_provider = _select_shape_provider()

func ensure_beam(light: SpotLight3D) -> void:
	if not light.has_meta(BEAM_META_KEY):
		var beam := _create_beam_instance("PeravizVolumetricBeamField")
		light.add_child(beam)
		light.set_meta(BEAM_META_KEY, beam)
		_apply_static_beam_params(beam, {})
	if not light.has_meta(CORE_BEAM_META_KEY):
		var core_beam := _create_beam_instance("PeravizVolumetricBeamCore")
		light.add_child(core_beam)
		light.set_meta(CORE_BEAM_META_KEY, core_beam)
		_apply_static_beam_params(core_beam, {})
	_ensure_debug_axis(light)

func update_beam(light: SpotLight3D, params: Dictionary) -> void:
	ensure_beam(light)
	var beam: MeshInstance3D = light.get_meta(BEAM_META_KEY) as MeshInstance3D
	var core_beam: MeshInstance3D = light.get_meta(CORE_BEAM_META_KEY) as MeshInstance3D
	if beam == null:
		return

	var intensity_max: float = max(float(params.get("intensity_max", 100.0)), 0.01)
	var intensity: float = clamp(float(params.get("scaled_intensity", 0.0)), 0.0, intensity_max)
	var reference_max: float = max(INTENSITY_REFERENCE_MAX, 0.01)
	var beam_intensity_norm: float = clamp(intensity / reference_max, 0.0, 1.0)
	var perceptual_intensity: float = pow(beam_intensity_norm, VOLUMETRIC_INTENSITY_RESPONSE_EXPONENT)
	var overdrive_norm: float = 0.0
	if intensity_max > reference_max:
		overdrive_norm = clamp((intensity - reference_max) / (intensity_max - reference_max), 0.0, 1.0)
	var threshold: float = float(params.get("intensity_visibility_threshold", 0.015))
	var beam_range: float = max(float(params.get("beam_range", 0.1)), 0.01)
	var beam_angle: float = max(float(params.get("beam_angle", 1.0)), 0.1)

	if intensity <= threshold:
		beam.visible = false
		beam.set_instance_shader_parameter("beam_visibility", 0.0)
		if core_beam != null:
			core_beam.visible = false
			core_beam.set_instance_shader_parameter("beam_visibility", 0.0)
		var hidden_axis: MeshInstance3D = _ensure_debug_axis(light)
		if hidden_axis != null:
			hidden_axis.visible = false
		return
	var debug_axis: MeshInstance3D = _ensure_debug_axis(light)
	if debug_axis != null:
		debug_axis.visible = bool(params.get("beam_debug_optics", false))

	var beam_color: Color = params.get("beam_color", Color.WHITE)
	var output_weight: float = max(float(params.get("photometric_output_weight", 1.0)), 0.0)
	var shape_result: Dictionary = _active_shape_provider.apply_shape(beam, light, params)
	var appearance_profile: Dictionary = _appearance_profile_from_params(params)
	var core_ratio: float = clamp(float(appearance_profile.get("core_radius_ratio", 0.7)), 0.05, 1.0)
	var core_shape_result: Dictionary = {}
	if core_beam != null:
		var core_params: Dictionary = params.duplicate(false)
		core_params["beam_radius_scale"] = core_ratio
		core_shape_result = _active_shape_provider.apply_shape(core_beam, light, core_params)
	var gobo_projection_radius: float = max(float(shape_result.get("gobo_projection_radius", 0.1)), 0.001)
	params["gobo_projection_radius"] = gobo_projection_radius
	var beam_rotation_deg: float = float(shape_result.get("beam_rotation_deg", 0.0))

	if bool(params.get("beam_debug_optics", false)):
		print("[PeravizBeamOptics] mode=", _active_shape_provider.shape_mode(), " angle_deg=", beam_angle, " range_m=", beam_range, " radius_end_m=", gobo_projection_radius)

	beam.visible = true
	if core_beam != null:
		core_beam.visible = true

	var intensity_alpha: float = clamp((intensity / reference_max) * VOLUMETRIC_INTENSITY_SCALE, 0.0, 3.6)
	beam.set_instance_shader_parameter("base_color", Color(beam_color.r * output_weight, beam_color.g * output_weight, beam_color.b * output_weight, intensity_alpha))
	beam.set_instance_shader_parameter("beam_visibility", output_weight)
	var overdrive_brightness_gain: float = lerp(1.0, VOLUMETRIC_OVERDRIVE_BRIGHTNESS_MAX, overdrive_norm)
	beam.set_instance_shader_parameter("max_brightness", lerp(8.0, 120.0, beam_intensity_norm) * overdrive_brightness_gain)
	_apply_static_beam_params(beam, params)
	beam.set_instance_shader_parameter("gobo_scale", max(float(params.get("gobo_scale", 1.0)), 0.05))
	beam.set_instance_shader_parameter("gobo_rotation_deg", beam_rotation_deg)
	beam.set_instance_shader_parameter("cone_height", max(beam_range, 0.001))
	beam.set_instance_shader_parameter("gobo_projection_radius", gobo_projection_radius)
	beam.set_instance_shader_parameter("beam_intensity", perceptual_intensity)
	beam.set_instance_shader_parameter("beam_overdrive", overdrive_norm)
	_apply_appearance_profile_params(beam, appearance_profile)
	_apply_beam_material_params(beam, beam_range, shape_result)
	if core_beam != null:
		_apply_static_beam_params(core_beam, params)
		core_beam.set_instance_shader_parameter("base_color", Color(beam_color.r * output_weight, beam_color.g * output_weight, beam_color.b * output_weight, intensity_alpha * 0.55))
		core_beam.set_instance_shader_parameter("beam_visibility", output_weight)
		core_beam.set_instance_shader_parameter("max_brightness", lerp(8.0, 120.0, beam_intensity_norm) * overdrive_brightness_gain)
		core_beam.set_instance_shader_parameter("gobo_scale", max(float(params.get("gobo_scale", 1.0)), 0.05))
		core_beam.set_instance_shader_parameter("gobo_rotation_deg", beam_rotation_deg)
		core_beam.set_instance_shader_parameter("cone_height", max(beam_range, 0.001))
		core_beam.set_instance_shader_parameter("gobo_projection_radius", max(float(core_shape_result.get("gobo_projection_radius", gobo_projection_radius * core_ratio)), 0.001))
		core_beam.set_instance_shader_parameter("beam_intensity", perceptual_intensity)
		core_beam.set_instance_shader_parameter("beam_overdrive", overdrive_norm)
		_apply_appearance_profile_params(core_beam, appearance_profile)
		_apply_beam_material_params(core_beam, beam_range, core_shape_result if not core_shape_result.is_empty() else shape_result)

func _appearance_profile_from_params(params: Dictionary) -> Dictionary:
	var profile_value: Variant = params.get("appearance_profile", {})
	if profile_value is Dictionary and not (profile_value as Dictionary).is_empty():
		return BeamAppearanceProfileScript.sanitize(profile_value as Dictionary)
	return BeamAppearanceProfileScript.resolve(params, params)

func _apply_appearance_profile_params(beam: MeshInstance3D, appearance_profile: Dictionary) -> void:
	var beam_material: ShaderMaterial = beam.material_override as ShaderMaterial
	if beam_material == null:
		return
	beam_material.set_shader_parameter("appearance_core_field", Vector2(float(appearance_profile.get("core_radius_ratio", 0.7)), float(appearance_profile.get("field_radius_ratio", 1.0))))
	beam_material.set_shader_parameter("appearance_edge_exp", Vector2(float(appearance_profile.get("edge_softness", 0.1)), float(appearance_profile.get("radial_exponent", 1.1))))
	beam_material.set_shader_parameter("appearance_gain_floor", Vector2(float(appearance_profile.get("center_intensity_gain", 1.0)), float(appearance_profile.get("edge_intensity_floor", 0.08))))
	beam_material.set_shader_parameter("appearance_extinction", Vector4(float(appearance_profile.get("extinction_coefficient", 0.01)), float(appearance_profile.get("longitudinal_exponent", 1.0)), float(appearance_profile.get("near_visibility", 1.0)), float(appearance_profile.get("far_visibility_floor", 0.12))))
	beam_material.set_shader_parameter("appearance_shape", 1 if str(appearance_profile.get("shape", "circle")) == "rectangle" else 0)
	var rect_ratio: float = max(float(appearance_profile.get("rectangle_ratio", appearance_profile.get("rectangleRatio", 1.0))), 0.01)
	beam_material.set_shader_parameter("appearance_rect_half_extents", Vector2(sqrt(rect_ratio), 1.0 / max(sqrt(rect_ratio), 0.01)))

func _create_beam_instance(beam_name: String) -> MeshInstance3D:
	var beam := MeshInstance3D.new()
	beam.name = beam_name
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.material_override = _beam_material_template.duplicate(true)
	beam.rotation_degrees.x = 90.0
	beam.visible = false
	return beam

func _compute_beam_settings_hash() -> int:
	var hash_value: int = 2166136261
	for key in ["beam_noise_amount", "beam_noise_scale", "beam_haze_density", "beam_anisotropy", "beam_quality"]:
		hash_value = int((hash_value ^ hash(_settings.get(key, null))) * 16777619)
	return hash_value

func _apply_static_beam_params(beam: MeshInstance3D, params: Dictionary) -> void:
	var haze_density: float = max(float(params.get("haze_density", params.get("haze_density_multiplier", 0.22))), 0.01)
	var static_hash: int = _beam_settings_hash
	static_hash = int((static_hash ^ hash(haze_density)) * 16777619)
	static_hash = int((static_hash ^ hash(float(params.get("beam_radial_falloff", 1.1)))) * 16777619)
	static_hash = int((static_hash ^ hash(float(params.get("beam_longitudinal_falloff", 1.0)))) * 16777619)
	static_hash = int((static_hash ^ hash(float(params.get("beam_softness", 0.35)))) * 16777619)
	if int(beam.get_meta("peraviz_static_beam_hash", 0)) == static_hash:
		return
	beam.set_meta("peraviz_static_beam_hash", static_hash)
	beam.set_instance_shader_parameter("beam_noise_amount", float(_settings.get("beam_noise_amount", 0.06)))
	beam.set_instance_shader_parameter("beam_noise_scale", float(_settings.get("beam_noise_scale", 1.4)))
	beam.set_instance_shader_parameter("beam_haze_density", float(_settings.get("beam_haze_density", 0.17)) * haze_density)
	beam.set_instance_shader_parameter("haze_density", max(haze_density, 0.2))
	beam.set_instance_shader_parameter("beam_anisotropy", float(_settings.get("beam_anisotropy", 0.62)))
	beam.set_instance_shader_parameter("beam_quality", int(_settings.get("beam_quality", 1)))
	beam.set_instance_shader_parameter("radial_falloff", max(float(params.get("beam_radial_falloff", 1.1)), 0.05))
	beam.set_instance_shader_parameter("longitudinal_falloff", max(float(params.get("beam_longitudinal_falloff", 1.0)), 0.05))
	beam.set_instance_shader_parameter("beam_softness", clamp(float(params.get("beam_softness", 0.35)), 0.02, 1.0))

func _apply_beam_material_params(beam: MeshInstance3D, beam_range: float, shape_result: Dictionary) -> void:
	var far_fade_end: float = max(400.0, beam_range * 12.0)
	var material_signature: String = "%s|%s|%s|%s|%s" % [str(beam_range), str(shape_result.get("mirror_x", true)), str(shape_result.get("mirror_z", false)), str(far_fade_end), str(_active_shape_provider.shape_mode())]
	if str(beam.get_meta("peraviz_beam_material_signature", "")) == material_signature:
		return
	beam.set_meta("peraviz_beam_material_signature", material_signature)
	var beam_material: ShaderMaterial = beam.material_override as ShaderMaterial
	if beam_material == null:
		return
	beam_material.set_shader_parameter("near_fade_end", max(2.0, beam_range * 0.2))
	beam_material.set_shader_parameter("far_fade_start", far_fade_end * 0.6)
	beam_material.set_shader_parameter("far_fade_end", far_fade_end)
	beam_material.set_shader_parameter("use_gobo", false)
	beam_material.set_shader_parameter("gobo_invert", false)
	beam_material.set_shader_parameter("gobo_mirror_x", bool(shape_result.get("mirror_x", true)))
	beam_material.set_shader_parameter("gobo_mirror_z", bool(shape_result.get("mirror_z", false)))
	beam_material.set_shader_parameter("depth_feather_enabled", false)

func update_beam_intensity(light: SpotLight3D, params: Dictionary) -> bool:
	if not light.has_meta(BEAM_META_KEY):
		return false
	var beam: MeshInstance3D = light.get_meta(BEAM_META_KEY) as MeshInstance3D
	var core_beam: MeshInstance3D = light.get_meta(CORE_BEAM_META_KEY) as MeshInstance3D
	if beam == null or not is_instance_valid(beam):
		return false

	var intensity_max: float = max(float(params.get("intensity_max", 100.0)), 0.01)
	var intensity: float = clamp(float(params.get("scaled_intensity", 0.0)), 0.0, intensity_max)
	var threshold: float = float(params.get("intensity_visibility_threshold", 0.015))
	if intensity <= threshold:
		beam.visible = false
		beam.set_instance_shader_parameter("beam_visibility", 0.0)
		if core_beam != null:
			core_beam.visible = false
			core_beam.set_instance_shader_parameter("beam_visibility", 0.0)
		return true

	var reference_max: float = max(INTENSITY_REFERENCE_MAX, 0.01)
	var beam_intensity_norm: float = clamp(intensity / reference_max, 0.0, 1.0)
	var perceptual_intensity: float = pow(beam_intensity_norm, VOLUMETRIC_INTENSITY_RESPONSE_EXPONENT)
	var overdrive_norm: float = 0.0
	if intensity_max > reference_max:
		overdrive_norm = clamp((intensity - reference_max) / (intensity_max - reference_max), 0.0, 1.0)
	var beam_color: Color = params.get("beam_color", Color.WHITE)
	var output_weight: float = max(float(params.get("photometric_output_weight", 1.0)), 0.0)
	var intensity_alpha: float = clamp((intensity / reference_max) * VOLUMETRIC_INTENSITY_SCALE, 0.0, 3.6)
	var overdrive_brightness_gain: float = lerp(1.0, VOLUMETRIC_OVERDRIVE_BRIGHTNESS_MAX, overdrive_norm)
	beam.visible = true
	if core_beam != null:
		core_beam.visible = true
	beam.set_instance_shader_parameter("base_color", Color(beam_color.r * output_weight, beam_color.g * output_weight, beam_color.b * output_weight, intensity_alpha))
	beam.set_instance_shader_parameter("beam_visibility", output_weight)
	beam.set_instance_shader_parameter("max_brightness", lerp(8.0, 120.0, beam_intensity_norm) * overdrive_brightness_gain)
	beam.set_instance_shader_parameter("beam_intensity", perceptual_intensity)
	beam.set_instance_shader_parameter("beam_overdrive", overdrive_norm)
	if core_beam != null:
		core_beam.set_instance_shader_parameter("base_color", Color(beam_color.r * output_weight, beam_color.g * output_weight, beam_color.b * output_weight, intensity_alpha * 0.55))
		core_beam.set_instance_shader_parameter("beam_visibility", output_weight)
		core_beam.set_instance_shader_parameter("max_brightness", lerp(8.0, 120.0, beam_intensity_norm) * overdrive_brightness_gain)
		core_beam.set_instance_shader_parameter("beam_intensity", perceptual_intensity)
		core_beam.set_instance_shader_parameter("beam_overdrive", overdrive_norm)
	return true

func apply_beam_optics(light: SpotLight3D, params: Dictionary) -> Dictionary:
	update_beam(light, params)
	return {"applied": true, "beam_instance_resolved": get_beam_resource(light) != null, "topology_rebuilt": true, "parametric_update_performed": false, "failure_reason": "volumetric backend rebuilds optics as a compatibility path"}

func get_beam_optics_state(light: SpotLight3D) -> Dictionary:
	if light != null and light.has_meta("peraviz_beam_optics_state"):
		return light.get_meta("peraviz_beam_optics_state", {}) as Dictionary
	return {}

func get_beam_resource(light: SpotLight3D) -> MeshInstance3D:
	if not light.has_meta(BEAM_META_KEY):
		return null
	var beam: MeshInstance3D = light.get_meta(BEAM_META_KEY) as MeshInstance3D
	return beam if beam != null and is_instance_valid(beam) else null

func cleanup_beam(light: SpotLight3D) -> void:
	for key in [BEAM_META_KEY, CORE_BEAM_META_KEY]:
		if not light.has_meta(key):
			continue
		var beam: MeshInstance3D = light.get_meta(key) as MeshInstance3D
		if beam != null and is_instance_valid(beam):
			beam.queue_free()
		light.remove_meta(key)

func _select_shape_provider() -> VolumetricBeamShapeProvider:
	var requested_mode: String = str(_settings.get("volumetric_shape_mode", SHAPE_MODE_GOBO_PRISM)).to_lower()
	if _shape_providers.has(requested_mode):
		return _shape_providers[requested_mode] as VolumetricBeamShapeProvider
	return _shape_providers[SHAPE_MODE_GOBO_PRISM] as VolumetricBeamShapeProvider

func _ensure_debug_axis(light: SpotLight3D) -> MeshInstance3D:
	if light.has_meta(DEBUG_AXIS_KEY):
		var existing: MeshInstance3D = light.get_meta(DEBUG_AXIS_KEY) as MeshInstance3D
		if existing != null and is_instance_valid(existing):
			return existing
	var axis := MeshInstance3D.new()
	axis.name = "PeravizBeamDebugAxis"
	axis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.03, 2.0)
	axis.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.1, 0.1, 0.95)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.0, 0.0, 1.0)
	axis.material_override = material
	axis.position = Vector3(0.0, 0.0, -1.0)
	light.add_child(axis)
	light.set_meta(DEBUG_AXIS_KEY, axis)
	return axis
