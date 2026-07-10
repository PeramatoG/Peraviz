extends BeamRendererBase

class_name LegacyConeBeamRenderer

const EMITTER_CONE_MAX_BASE_RADIUS_M: float = 10.0
const EMITTER_CONE_FADE_END_RATIO: float = 0.82
const EMITTER_CONE_NEAR_ALPHA: float = 0.16
const EMITTER_CONE_FAR_ALPHA: float = 0.004
const EMITTER_CONE_NEAR_EMISSION: float = 0.45
const EMITTER_CONE_FAR_EMISSION: float = 0.04
const LEGACY_INTENSITY_RESPONSE_EXPONENT: float = 2.2
const INTENSITY_REFERENCE_MAX: float = 20.0
const LEGACY_OVERDRIVE_GAIN_MAX: float = 5.0

const MAIN_KEY: String = "peraviz_beam_prism"
const GOBO_TEXTURE_META_KEY: String = "peraviz_gobo_texture"
const FALLBACK_GOBO_META_KEY: String = "peraviz_is_vector_fallback_gobo"
const DEBUG_AXIS_KEY: String = "peraviz_beam_debug_axis"
const LEGACY_MID_KEY: String = "peraviz_beam_cone_mid"
const LEGACY_CORE_KEY: String = "peraviz_beam_cone_core"
const DEFAULT_MIRROR_BEAM_SHAPE_X: bool = true
const DEFAULT_MIRROR_BEAM_SHAPE_Z: bool = true

var _material_template: ShaderMaterial
var _mesh_builder: GoboPrismMeshBuilder

func _init() -> void:
	_material_template = ShaderMaterial.new()
	_material_template.shader = load("res://scripts/shaders/legacy_beam_cone.gdshader")
	_mesh_builder = GoboPrismMeshBuilder.new()

func ensure_beam(light: SpotLight3D) -> void:
	_cleanup_legacy_cones(light)
	if not light.has_meta(MAIN_KEY):
		light.set_meta(MAIN_KEY, _create_prism("PeravizBeamPrism"))

func update_beam(light: SpotLight3D, params: Dictionary) -> void:
	ensure_beam(light)
	var prism: MeshInstance3D = light.get_meta(MAIN_KEY) as MeshInstance3D
	if prism == null:
		return
	_attach_if_needed(light, prism)

	var intensity_max: float = max(float(params.get("intensity_max", 100.0)), 0.01)
	var scaled_intensity: float = clamp(float(params.get("scaled_intensity", 0.0)), 0.0, intensity_max)
	var threshold: float = float(params.get("intensity_visibility_threshold", 0.015))
	var beam_range: float = max(float(params.get("beam_range", 0.1)), 0.01)
	var beam_angle: float = max(float(params.get("beam_angle", 1.0)), 0.1)
	var beam_color: Color = params.get("beam_color", Color.WHITE)
	var lens_radius: float = max(float(params.get("lens_radius", 0.03)), 0.005)
	var beam_visible: bool = scaled_intensity > threshold

	prism.visible = beam_visible
	if not beam_visible:
		var hidden_axis: MeshInstance3D = _ensure_debug_axis(light)
		if hidden_axis != null:
			hidden_axis.visible = false
		return
	var debug_axis: MeshInstance3D = _ensure_debug_axis(light)
	if debug_axis != null:
		debug_axis.visible = bool(params.get("beam_debug_optics", false))

	var beam_half_angle_deg: float = beam_angle * 0.5
	var radius: float = tan(deg_to_rad(beam_half_angle_deg)) * beam_range
	var bottom_radius: float = clamp(radius, 0.03, EMITTER_CONE_MAX_BASE_RADIUS_M)
	if bool(params.get("beam_debug_optics", false)):
		print("[PeravizBeamOptics] angle_deg=", beam_angle, " range_m=", beam_range, " radius_end_m=", bottom_radius)

	var lens_offset_m: float = max(float(params.get("lens_offset_m", params.get("near_offset", 0.0))), 0.0)
	var lens_shift_x: float = float(params.get("lens_shift_x", 0.0))
	var lens_shift_y: float = float(params.get("lens_shift_y", 0.0))

	var gobo_texture: Texture2D = null
	if light.has_meta(GOBO_TEXTURE_META_KEY):
		gobo_texture = light.get_meta(GOBO_TEXTURE_META_KEY) as Texture2D
	var gobo_scale: float = max(float(params.get("gobo_scale", 1.0)), 0.05)
	var alignment_rotation_deg: float = float(params.get("beam_gobo_alignment_rotation_deg", 0.0))
	# The light node already carries gobo wheel/index rotation via FixtureGoboProjector.
	# Keep only local alignment on the prism node to avoid double-rotating versus the footprint.
	var beam_rotation_deg: float = wrapf(alignment_rotation_deg + 180.0, 0.0, 360.0)
	var mirror_x: bool = bool(params.get("beam_gobo_mirror_x", DEFAULT_MIRROR_BEAM_SHAPE_X))
	var mirror_z: bool = bool(params.get("beam_gobo_mirror_z", DEFAULT_MIRROR_BEAM_SHAPE_Z))
	var aperture_profile: Dictionary = _aperture_profile_from_params(params)
	if str(aperture_profile.get("shape", "")) == "no_projected_beam":
		prism.visible = false
		light.set_meta("peraviz_beam_optics_state", _beam_optics_state(0.0, 0.0, beam_range, beam_angle, aperture_profile, false, false))
		return
	var prism_mesh: ArrayMesh = _mesh_builder.build_aperture_beam_mesh(aperture_profile, beam_range)
	light.set_meta("peraviz_last_beam_gobo_consumed", gobo_texture != null)
	light.set_meta("peraviz_last_beam_renderer_mode", "legacy_cone")
	if prism_mesh != null:
		prism.mesh = prism_mesh
	prism.extra_cull_margin = max(bottom_radius, lens_radius) + beam_range
	prism.position = Vector3(lens_shift_x, lens_shift_y, -(beam_range * 0.5 + lens_offset_m))
	prism.scale = Vector3(-1.0 if mirror_x else 1.0, 1.0, -1.0 if mirror_z else 1.0)
	_apply_beam_axis_rotation(prism, beam_rotation_deg)

	var color_alpha := Color(beam_color.r, beam_color.g, beam_color.b, 1.0)
	var beam_softness: float = clamp(float(params.get("beam_softness", 0.35)), 0.02, 1.0)
	var radial_falloff: float = max(float(params.get("beam_radial_falloff", 1.1)), 0.05)
	var longitudinal_falloff: float = max(float(params.get("beam_longitudinal_falloff", 1.0)), 0.05)
	var haze_density: float = max(float(params.get("haze_density", params.get("haze_density_multiplier", 0.22))), 0.01)
	_update_prism_material(prism, color_alpha, scaled_intensity, intensity_max, beam_range, bottom_radius, beam_softness, radial_falloff, longitudinal_falloff, haze_density)
	_apply_prism_optics_parameters(prism, lens_radius, bottom_radius)
	light.set_meta("peraviz_beam_optics_state", _beam_optics_state(lens_radius, bottom_radius, beam_range, beam_angle, aperture_profile, false, true))


func _apply_beam_axis_rotation(node: Node3D, beam_rotation_deg: float) -> void:
	if node == null:
		return
	node.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	node.rotate_object_local(Vector3.UP, deg_to_rad(-beam_rotation_deg))

func update_beam_intensity(light: SpotLight3D, params: Dictionary) -> bool:
	if not light.has_meta(MAIN_KEY):
		return false
	var prism: MeshInstance3D = light.get_meta(MAIN_KEY) as MeshInstance3D
	if prism == null or not is_instance_valid(prism):
		return false

	var intensity_max: float = max(float(params.get("intensity_max", 100.0)), 0.01)
	var scaled_intensity: float = clamp(float(params.get("scaled_intensity", 0.0)), 0.0, intensity_max)
	var threshold: float = float(params.get("intensity_visibility_threshold", 0.015))
	var beam_visible: bool = scaled_intensity > threshold
	prism.visible = beam_visible
	if not beam_visible:
		return true

	var beam_range: float = max(float(params.get("beam_range", 0.1)), 0.01)
	var gobo_projection_radius: float = max(float(params.get("gobo_projection_radius", 0.1)), 0.001)
	var beam_color: Color = params.get("beam_color", Color.WHITE)
	var beam_softness: float = clamp(float(params.get("beam_softness", 0.35)), 0.02, 1.0)
	var radial_falloff: float = max(float(params.get("beam_radial_falloff", 1.1)), 0.05)
	var longitudinal_falloff: float = max(float(params.get("beam_longitudinal_falloff", 1.0)), 0.05)
	var haze_density: float = max(float(params.get("haze_density", params.get("haze_density_multiplier", 0.22))), 0.01)
	_update_prism_material(prism, Color(beam_color.r, beam_color.g, beam_color.b, 1.0), scaled_intensity, intensity_max, beam_range, gobo_projection_radius, beam_softness, radial_falloff, longitudinal_falloff, haze_density)
	return true

func apply_beam_optics(light: SpotLight3D, params: Dictionary) -> Dictionary:
	ensure_beam(light)
	var prism: MeshInstance3D = light.get_meta(MAIN_KEY) as MeshInstance3D
	if prism == null or not is_instance_valid(prism):
		return {"applied": false, "beam_instance_resolved": false, "failure_reason": "beam instance missing"}
	_attach_if_needed(light, prism)
	var previous_mesh: Mesh = prism.mesh
	var previous_material: Material = prism.material_override
	var beam_range: float = max(float(params.get("beam_range", 0.1)), 0.01)
	var near_radius: float = max(float(params.get("lens_radius", params.get("render_near_radius_m", 0.03))), 0.001)
	var beam_angle: float = clamp(float(params.get("beam_angle", 1.0)), 0.0, 179.0)
	var far_radius: float = _far_radius_for_angle(near_radius, beam_angle, beam_range)
	var aperture_profile: Dictionary = _aperture_profile_from_params(params)
	if str(aperture_profile.get("shape", "")) == "no_projected_beam":
		prism.visible = false
		light.set_meta("peraviz_beam_optics_state", _beam_optics_state(0.0, 0.0, beam_range, beam_angle, aperture_profile, false, false))
		return {"applied": true, "beam_instance_resolved": true, "optics_state_changed": true, "parametric_update_performed": false, "topology_rebuilt": false}
	var needs_topology: bool = prism.mesh == null or str((light.get_meta("peraviz_beam_optics_state", {}) as Dictionary).get("shape", "")) != str(aperture_profile.get("shape", "circle"))
	if needs_topology:
		var mesh: ArrayMesh = _mesh_builder.build_aperture_beam_mesh(aperture_profile, beam_range)
		if mesh != null:
			prism.mesh = mesh
	_apply_prism_optics_parameters(prism, near_radius, far_radius)
	prism.extra_cull_margin = max(far_radius, near_radius) + beam_range
	light.set_meta("peraviz_beam_optics_state", _beam_optics_state(near_radius, far_radius, beam_range, beam_angle, aperture_profile, needs_topology and previous_mesh != prism.mesh, true))
	return {
		"applied": true,
		"beam_instance_resolved": true,
		"optics_state_changed": true,
		"near_aperture_changed": true,
		"far_spread_changed": true,
		"topology_rebuilt": needs_topology and previous_mesh != prism.mesh,
		"parametric_update_performed": true,
		"same_mesh_instance": true,
		"same_material": previous_material == prism.material_override,
	}

func get_beam_optics_state(light: SpotLight3D) -> Dictionary:
	if light == null or not light.has_meta("peraviz_beam_optics_state"):
		return {}
	return light.get_meta("peraviz_beam_optics_state", {}) as Dictionary

func _aperture_profile_from_params(params: Dictionary) -> Dictionary:
	var beam_type: String = str(params.get("beam_type", "Spot")).to_lower()
	if beam_type == "none" or beam_type == "glow":
		return {"shape": "no_projected_beam"}
	if beam_type == "rectangle":
		return {"shape": "rectangle", "rectangle_ratio": max(float(params.get("rectangle_ratio", 1.0)), 0.01), "source": "official_beam_type"}
	return {"shape": "circle", "source": "official_beam_type"}

func _far_radius_for_angle(near_radius: float, beam_angle: float, beam_range: float) -> float:
	var half_angle_deg: float = beam_angle * 0.5
	return clamp(near_radius + tan(deg_to_rad(half_angle_deg)) * beam_range, near_radius, EMITTER_CONE_MAX_BASE_RADIUS_M)

func _apply_prism_optics_parameters(prism: MeshInstance3D, near_radius: float, far_radius: float) -> void:
	prism.set_instance_shader_parameter("beam_near_radius", max(near_radius, 0.001))
	prism.set_instance_shader_parameter("beam_far_radius", max(far_radius, 0.001))

func _beam_optics_state(near_radius: float, far_radius: float, beam_range: float, beam_angle: float, aperture_profile: Dictionary, topology_rebuilt: bool, parametric_update: bool) -> Dictionary:
	return {
		"near_radius": near_radius,
		"far_radius": far_radius,
		"beam_range": beam_range,
		"beam_angle": beam_angle,
		"shape": str(aperture_profile.get("shape", "circle")),
		"rectangle_ratio": float(aperture_profile.get("rectangle_ratio", 1.0)),
		"topology_rebuilt": topology_rebuilt,
		"parametric_update": parametric_update,
	}

func get_beam_resource(light: SpotLight3D) -> MeshInstance3D:
	if not light.has_meta(MAIN_KEY):
		return null
	var prism: MeshInstance3D = light.get_meta(MAIN_KEY) as MeshInstance3D
	return prism if prism != null and is_instance_valid(prism) else null

func cleanup_beam(light: SpotLight3D) -> void:
	if light.has_meta(MAIN_KEY):
		var prism: MeshInstance3D = light.get_meta(MAIN_KEY) as MeshInstance3D
		if prism != null and is_instance_valid(prism):
			prism.queue_free()
		light.remove_meta(MAIN_KEY)
	_cleanup_legacy_cones(light)

func _cleanup_legacy_cones(light: SpotLight3D) -> void:
	for meta_key in [LEGACY_MID_KEY, LEGACY_CORE_KEY, "peraviz_beam_cone"]:
		if not light.has_meta(meta_key):
			continue
		var legacy_cone: MeshInstance3D = light.get_meta(meta_key) as MeshInstance3D
		if legacy_cone != null and is_instance_valid(legacy_cone):
			legacy_cone.queue_free()
		light.remove_meta(meta_key)

func _attach_if_needed(light: SpotLight3D, prism: MeshInstance3D) -> void:
	if prism != null and prism.get_parent() == null:
		light.add_child(prism)

func _create_prism(prism_name: String) -> MeshInstance3D:
	var prism := MeshInstance3D.new()
	prism.name = prism_name
	prism.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	prism.material_override = _material_template.duplicate(true)
	prism.rotation_degrees.x = 90.0
	prism.visible = false
	return prism

func _update_prism_material(prism: MeshInstance3D, beam_color: Color, scaled_intensity: float, intensity_max: float, beam_range: float, gobo_projection_radius: float, lateral_softness: float, radial_falloff: float, longitudinal_falloff: float, haze_density: float) -> void:
	if prism == null:
		return
	var reference_max: float = max(INTENSITY_REFERENCE_MAX, 0.01)
	var normalized_scaled_intensity: float = clamp(scaled_intensity / reference_max, 0.0, 1.0)
	var perceptual_intensity: float = pow(normalized_scaled_intensity, LEGACY_INTENSITY_RESPONSE_EXPONENT)
	var overdrive_norm: float = 0.0
	if intensity_max > reference_max:
		overdrive_norm = clamp((scaled_intensity - reference_max) / (intensity_max - reference_max), 0.0, 1.0)
	var overdrive_gain: float = lerp(1.0, LEGACY_OVERDRIVE_GAIN_MAX, overdrive_norm)
	prism.set_instance_shader_parameter("beam_color", beam_color)
	prism.set_instance_shader_parameter("near_alpha", lerp(0.0, EMITTER_CONE_NEAR_ALPHA, perceptual_intensity) * overdrive_gain)
	prism.set_instance_shader_parameter("far_alpha", lerp(0.0, EMITTER_CONE_FAR_ALPHA, perceptual_intensity) * overdrive_gain)
	prism.set_instance_shader_parameter("near_emission", lerp(0.0, EMITTER_CONE_NEAR_EMISSION, perceptual_intensity) * overdrive_gain)
	prism.set_instance_shader_parameter("far_emission", lerp(0.0, EMITTER_CONE_FAR_EMISSION, perceptual_intensity) * overdrive_gain)
	prism.set_instance_shader_parameter("cone_height", max(beam_range, 0.001))
	prism.set_instance_shader_parameter("gobo_projection_radius", max(gobo_projection_radius, 0.001))
	prism.set_instance_shader_parameter("fade_end_ratio", EMITTER_CONE_FADE_END_RATIO)
	prism.set_instance_shader_parameter("lateral_softness", clamp(lateral_softness, 0.02, 1.0))
	prism.set_instance_shader_parameter("lateral_emission_boost", 0.22)
	prism.set_instance_shader_parameter("volumetric_noise_strength", 0.06)
	prism.set_instance_shader_parameter("radial_falloff", radial_falloff)
	prism.set_instance_shader_parameter("longitudinal_falloff", longitudinal_falloff)
	prism.set_instance_shader_parameter("haze_density", haze_density)
	var prism_material: ShaderMaterial = prism.material_override as ShaderMaterial
	if prism_material != null:
		prism_material.set_shader_parameter("use_gobo", false)
		prism_material.set_shader_parameter("gobo_invert", false)

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
