extends BeamRendererBase
class_name LegacyConeBeamRenderer

const BeamGeometryCalculatorScript = preload("res://scripts/beam_geometry_calculator.gd")
const GoboRotationPresentationScript = preload("res://scripts/runtime/gobo_indexed_rotation_presentation.gd")

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
var _last_parameter_write_count: int = 0

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
	BoundBeamState.invalidate_resource(prism)

	var intensity_max: float = max(float(params.get("intensity_max", 100.0)), 0.01)
	var scaled_intensity: float = clamp(float(params.get("scaled_intensity", 0.0)), 0.0, intensity_max)
	var threshold: float = float(params.get("intensity_visibility_threshold", 0.015))
	var beam_range: float = BeamGeometryCalculatorScript.clamp_visual_length(float(params.get("beam_visual_length_m", params.get("beam_range", 75.0))))
	var beam_angle: float = max(float(params.get("beam_angle", 1.0)), 0.1)
	var beam_color: Color = params.get("beam_color", Color.WHITE)
	var lens_radius: float = max(float(params.get("lens_radius", 0.03)), 0.005)
	var beam_visible: bool = scaled_intensity > threshold

	_set_bound_visibility(prism, beam_visible)
	if not beam_visible:
		_sync_debug_axis(light, false)
		return
	_sync_debug_axis(light, bool(params.get("beam_debug_optics", false)))

	var geometry: Dictionary = BeamGeometryCalculatorScript.far_radius_for_full_angle(lens_radius, beam_angle, beam_range)
	var bottom_radius: float = float(geometry.get("far_radius_m", lens_radius))
	if bool(params.get("beam_debug_optics", false)):
		print("[PeravizBeamOptics] angle_deg=", beam_angle, " range_m=", beam_range, " radius_end_m=", bottom_radius)

	var lens_offset_m: float = max(float(params.get("lens_offset_m", params.get("near_offset", 0.0))), 0.0)
	var lens_shift_x: float = float(params.get("lens_shift_x", 0.0))
	var lens_shift_y: float = float(params.get("lens_shift_y", 0.0))

	var gobo_texture: Texture2D = null
	if light.has_meta(GOBO_TEXTURE_META_KEY):
		gobo_texture = light.get_meta(GOBO_TEXTURE_META_KEY) as Texture2D
	var alignment_rotation_deg: float = float(params.get("beam_gobo_alignment_rotation_deg", 0.0))
	# The light node already carries gobo wheel/index rotation via FixtureGoboProjector.
	# Keep only local alignment on the prism node to avoid double-rotating versus the footprint.
	var beam_rotation_deg: float = wrapf(alignment_rotation_deg + 180.0, 0.0, 360.0)
	var mirror_x: bool = bool(params.get("beam_gobo_mirror_x", DEFAULT_MIRROR_BEAM_SHAPE_X))
	var mirror_z: bool = bool(params.get("beam_gobo_mirror_z", DEFAULT_MIRROR_BEAM_SHAPE_Z))
	var aperture_profile: Dictionary = _aperture_profile_from_params(params)
	if str(aperture_profile.get("shape", "")) == "no_projected_beam":
		_set_bound_visibility(prism, false)
		light.set_meta("peraviz_beam_optics_state", _beam_optics_state(prism, 0.0, 0.0, beam_range, beam_angle, aperture_profile, false, false))
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
	GoboRotationPresentationScript.reapply_after_base_alignment(prism)

	var color_alpha := Color(beam_color.r, beam_color.g, beam_color.b, 1.0)
	var beam_softness: float = clamp(float(params.get("beam_softness", 0.35)), 0.02, 1.0)
	var radial_falloff: float = max(float(params.get("beam_radial_falloff", 1.1)), 0.05)
	var longitudinal_falloff: float = max(float(params.get("beam_longitudinal_falloff", 1.0)), 0.05)
	var haze_density: float = max(float(params.get("haze_density", params.get("haze_density_multiplier", 0.22))), 0.01)
	_update_prism_material(prism, color_alpha, scaled_intensity, intensity_max, beam_range, bottom_radius, beam_softness, radial_falloff, longitudinal_falloff, haze_density)
	_apply_prism_optics_parameters(prism, lens_radius, bottom_radius)
	light.set_meta("peraviz_beam_optics_state", _beam_optics_state(prism, lens_radius, bottom_radius, beam_range, beam_angle, aperture_profile, false, true))


func _apply_beam_axis_rotation(node: Node3D, beam_rotation_deg: float) -> void:
	if node == null:
		return
	node.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	node.rotate_object_local(Vector3.UP, deg_to_rad(-beam_rotation_deg))

func update_beam_intensity(light: SpotLight3D, params: Dictionary) -> int:
	_last_parameter_write_count = 0
	if not light.has_meta(MAIN_KEY):
		return INTENSITY_UNRESOLVED
	var prism: MeshInstance3D = light.get_meta(MAIN_KEY) as MeshInstance3D
	if prism == null or not is_instance_valid(prism):
		return INTENSITY_UNRESOLVED
	if prism.has_meta(BoundBeamState.META_KEY):
		return update_bound_intensity(light, prism, params, BoundBeamState.resolve(prism))

	var intensity_max: float = max(float(params.get("intensity_max", 100.0)), 0.01)
	var scaled_intensity: float = clamp(float(params.get("scaled_intensity", 0.0)), 0.0, intensity_max)
	var threshold: float = float(params.get("intensity_visibility_threshold", 0.015))
	var beam_visible: bool = scaled_intensity > threshold
	if beam_visible and not is_beam_dynamic_ready(light):
		return INTENSITY_UNRESOLVED
	var signature: Array = [beam_visible, scaled_intensity, intensity_max, params.get("beam_color", Color.WHITE)]
	if prism.get_meta("peraviz_intensity_signature", []) == signature:
		return INTENSITY_UNCHANGED
	prism.set_meta("peraviz_intensity_signature", signature)
	_set_bound_visibility(prism, beam_visible)
	if not beam_visible:
		_sync_debug_axis(light, false)
		return INTENSITY_CHANGED

	var beam_range: float = BeamGeometryCalculatorScript.clamp_visual_length(float(params.get("beam_visual_length_m", params.get("beam_range", 75.0))))
	var gobo_projection_radius: float = max(float(params.get("gobo_projection_radius", 0.1)), 0.001)
	var beam_color: Color = params.get("beam_color", Color.WHITE)
	var beam_softness: float = clamp(float(params.get("beam_softness", 0.35)), 0.02, 1.0)
	var radial_falloff: float = max(float(params.get("beam_radial_falloff", 1.1)), 0.05)
	var longitudinal_falloff: float = max(float(params.get("beam_longitudinal_falloff", 1.0)), 0.05)
	var haze_density: float = max(float(params.get("haze_density", params.get("haze_density_multiplier", 0.22))), 0.01)
	_update_prism_material(prism, Color(beam_color.r, beam_color.g, beam_color.b, 1.0), scaled_intensity, intensity_max, beam_range, gobo_projection_radius, beam_softness, radial_falloff, longitudinal_falloff, haze_density)
	_last_parameter_write_count = 15
	return INTENSITY_CHANGED

func get_last_parameter_write_count() -> int:
	return _last_parameter_write_count

func is_beam_dynamic_ready(light: SpotLight3D) -> bool:
	var prism: MeshInstance3D = get_beam_resource(light)
	return prism != null and prism.mesh != null

func apply_beam_optics(light: SpotLight3D, params: Dictionary) -> Dictionary:
	ensure_beam(light)
	var prism: MeshInstance3D = light.get_meta(MAIN_KEY) as MeshInstance3D
	if prism == null or not is_instance_valid(prism):
		return {"applied": false, "beam_instance_resolved": false, "failure_reason": "beam instance missing"}
	_attach_if_needed(light, prism)
	var previous_mesh: Mesh = prism.mesh
	var previous_material: Material = prism.material_override
	var beam_range: float = BeamGeometryCalculatorScript.clamp_visual_length(float(params.get("beam_visual_length_m", params.get("beam_range", 75.0))))
	var near_radius: float = max(float(params.get("lens_radius", params.get("render_near_radius_m", 0.03))), 0.001)
	var beam_angle: float = clamp(float(params.get("beam_angle", 1.0)), 0.0, 179.0)
	var far_radius: float = _far_radius_for_angle(near_radius, beam_angle, beam_range)
	var aperture_profile: Dictionary = _aperture_profile_from_params(params)
	if str(aperture_profile.get("shape", "")) == "no_projected_beam":
		_set_bound_visibility(prism, false)
		light.set_meta("peraviz_beam_optics_state", _beam_optics_state(prism, 0.0, 0.0, beam_range, beam_angle, aperture_profile, false, false))
		return {"applied": true, "beam_instance_resolved": true, "optics_state_changed": true, "parametric_update_performed": false, "topology_rebuilt": false}
	var needs_topology: bool = prism.mesh == null or str((light.get_meta("peraviz_beam_optics_state", {}) as Dictionary).get("shape", "")) != str(aperture_profile.get("shape", "circle"))
	if needs_topology:
		var mesh: ArrayMesh = _mesh_builder.build_aperture_beam_mesh(aperture_profile, beam_range)
		if mesh != null:
			prism.mesh = mesh
	_apply_prism_optics_parameters(prism, near_radius, far_radius)
	prism.extra_cull_margin = max(far_radius, near_radius) + beam_range
	light.set_meta("peraviz_beam_optics_state", _beam_optics_state(prism, near_radius, far_radius, beam_range, beam_angle, aperture_profile, needs_topology and previous_mesh != prism.mesh, true))
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
	var beam_type: String = str(params.get("beam_type", "Wash")).to_lower()
	if beam_type == "none" or beam_type == "glow":
		return {"shape": "no_projected_beam"}
	if beam_type == "rectangle":
		return {"shape": "rectangle", "rectangle_ratio": max(float(params.get("rectangle_ratio", 1.7777)), 0.01), "source": "official_beam_type"}
	return {"shape": "circle", "source": "official_beam_type"}

func _far_radius_for_angle(near_radius: float, beam_angle: float, beam_range: float) -> float:
	return float(BeamGeometryCalculatorScript.far_radius_for_full_angle(near_radius, beam_angle, beam_range).get("far_radius_m", near_radius))

func _apply_prism_optics_parameters(prism: MeshInstance3D, near_radius: float, far_radius: float) -> void:
	_set_bound_shader_parameter(prism, "beam_radius_params", Vector2(max(near_radius, 0.001), max(far_radius, 0.001)))

func _beam_optics_state(prism: MeshInstance3D, near_radius: float, far_radius: float, beam_range: float, beam_angle: float, aperture_profile: Dictionary, topology_rebuilt: bool, parametric_update: bool) -> Dictionary:
	var half_height: float = beam_range * 0.5
	var near_world: Vector3 = prism.to_global(Vector3(0.0, half_height, 0.0)) if prism != null else Vector3.ZERO
	var far_world: Vector3 = prism.to_global(Vector3(0.0, -half_height, 0.0)) if prism != null else Vector3.ZERO
	return {
		"near_radius": near_radius,
		"far_radius": far_radius,
		"beam_range": beam_range,
		"beam_angle": beam_angle,
		"shape": str(aperture_profile.get("shape", "circle")),
		"rectangle_ratio": float(aperture_profile.get("rectangle_ratio", 1.7777)),
		"topology_rebuilt": topology_rebuilt,
		"parametric_update": parametric_update,
		"near_local_y": half_height,
		"far_local_y": -half_height,
		"near_world_position": near_world,
		"far_world_position": far_world,
		"near_axial": 1.0,
		"far_axial": 0.0,
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
	_cleanup_debug_axis(light)

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
	_set_bound_visibility(prism, false)
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
	_set_bound_shader_parameter(prism, "beam_color", beam_color)
	_set_bound_shader_parameter(prism, "near_alpha", lerp(0.0, EMITTER_CONE_NEAR_ALPHA, perceptual_intensity) * overdrive_gain)
	_set_bound_shader_parameter(prism, "far_alpha", lerp(0.0, EMITTER_CONE_FAR_ALPHA, perceptual_intensity) * overdrive_gain)
	_set_bound_shader_parameter(prism, "near_emission", lerp(0.0, EMITTER_CONE_NEAR_EMISSION, perceptual_intensity) * overdrive_gain)
	_set_bound_shader_parameter(prism, "far_emission", lerp(0.0, EMITTER_CONE_FAR_EMISSION, perceptual_intensity) * overdrive_gain)
	_set_bound_shader_parameter(prism, "cone_height", max(beam_range, 0.001))
	_set_bound_shader_parameter(prism, "gobo_projection_radius", max(gobo_projection_radius, 0.001))
	_set_bound_shader_parameter(prism, "fade_end_ratio", EMITTER_CONE_FADE_END_RATIO)
	_set_bound_shader_parameter(prism, "lateral_softness", clamp(lateral_softness, 0.02, 1.0))
	_set_bound_shader_parameter(prism, "lateral_emission_boost", 0.22)
	_set_bound_shader_parameter(prism, "volumetric_noise_strength", 0.06)
	_set_bound_shader_parameter(prism, "radial_falloff", radial_falloff)
	_set_bound_shader_parameter(prism, "longitudinal_falloff", longitudinal_falloff)
	_set_bound_shader_parameter(prism, "haze_density", haze_density)
	var prism_material: ShaderMaterial = prism.material_override as ShaderMaterial
	if prism_material != null:
		_set_bound_material_parameter(prism_material, "use_gobo", false)
		_set_bound_material_parameter(prism_material, "gobo_invert", false)

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
	_set_debug_visibility(axis, false)
	light.add_child(axis)
	light.set_meta(DEBUG_AXIS_KEY, axis)
	return axis

func _sync_debug_axis(light: SpotLight3D, enabled: bool) -> void:
	var axis: MeshInstance3D = null
	if enabled:
		axis = _ensure_debug_axis(light)
	elif light.has_meta(DEBUG_AXIS_KEY):
		axis = light.get_meta(DEBUG_AXIS_KEY) as MeshInstance3D
	if axis != null and is_instance_valid(axis):
		_set_debug_visibility(axis, enabled)

func _cleanup_debug_axis(light: SpotLight3D) -> void:
	if not light.has_meta(DEBUG_AXIS_KEY):
		return
	var axis: MeshInstance3D = light.get_meta(DEBUG_AXIS_KEY) as MeshInstance3D
	if axis != null and is_instance_valid(axis):
		axis.queue_free()
	light.remove_meta(DEBUG_AXIS_KEY)

func reset_scene_state() -> void:
	_mesh_builder.clear_cache()

# Uses the existing prism material implementation with setup-bound resources.
func update_bound_intensity(_light: SpotLight3D, prism: MeshInstance3D, params: Dictionary, bound: BoundBeamState = null) -> int:
	_last_parameter_write_count = 0
	_last_visibility_write_count = 0
	if not is_instance_valid(prism):
		return INTENSITY_UNRESOLVED
	var intensity_max: float = maxf(float(params.get("intensity_max", 100.0)), 0.01)
	var intensity: float = clampf(float(params.get("scaled_intensity", 0.0)), 0.0, intensity_max)
	var visible: bool = intensity > float(params.get("intensity_visibility_threshold", 0.015))
	if visible and prism.mesh == null:
		return INTENSITY_UNRESOLVED
	var state: BoundBeamState = BoundBeamState.resolve(prism, bound)
	if prism.visible != visible:
		_set_bound_visibility(prism, visible)
		_last_visibility_write_count = 1
	if not visible:
		return INTENSITY_CHANGED if _last_visibility_write_count > 0 else INTENSITY_UNCHANGED
	var color: Color = params.get("beam_color", Color.WHITE)
	var dynamic := Color(color.r, color.g, color.b, intensity)
	var shader_before: int = renderer_shader_parameter_writes
	var response: Color = _bound_intensity_response(intensity, intensity_max)
	if state.applied_max < 0.0:
		_update_prism_material(prism, color, intensity, intensity_max,
			BeamGeometryCalculatorScript.clamp_visual_length(float(params.get("beam_visual_length_m", params.get("beam_range", 75.0)))),
			maxf(float(params.get("gobo_projection_radius", 0.1)), 0.001),
			clampf(float(params.get("beam_softness", 0.35)), 0.02, 1.0),
			maxf(float(params.get("beam_radial_falloff", 1.1)), 0.05),
			maxf(float(params.get("beam_longitudinal_falloff", 1.0)), 0.05),
			maxf(float(params.get("haze_density", params.get("haze_density_multiplier", 0.22))), 0.01))
	else:
		if Color(state.applied_dynamic.r,state.applied_dynamic.g,state.applied_dynamic.b) != Color(color.r,color.g,color.b):
			_set_bound_shader_parameter(prism, "beam_color", color)
		if state.applied_response.r != response.r: _set_bound_shader_parameter(prism,"near_alpha",response.r)
		if state.applied_response.g != response.g: _set_bound_shader_parameter(prism,"far_alpha",response.g)
		if state.applied_response.b != response.b: _set_bound_shader_parameter(prism,"near_emission",response.b)
		if state.applied_response.a != response.a: _set_bound_shader_parameter(prism,"far_emission",response.a)
	state.applied_dynamic = dynamic
	state.applied_max = intensity_max
	state.applied_response = response
	_last_parameter_write_count = renderer_shader_parameter_writes - shader_before
	return INTENSITY_CHANGED if _last_visibility_write_count + _last_parameter_write_count > 0 else INTENSITY_UNCHANGED

# Same established prism response, cached at the effective float shader boundary.
func _bound_intensity_response(intensity: float, intensity_max: float) -> Color:
	var reference_max: float = maxf(INTENSITY_REFERENCE_MAX, 0.01)
	var perceptual: float = pow(clampf(intensity/reference_max,0.0,1.0),LEGACY_INTENSITY_RESPONSE_EXPONENT)
	var overdrive: float = clampf((intensity-reference_max)/(intensity_max-reference_max),0.0,1.0) if intensity_max > reference_max else 0.0
	var gain: float = lerpf(1.0,LEGACY_OVERDRIVE_GAIN_MAX,overdrive)
	return Color(lerpf(0.0,EMITTER_CONE_NEAR_ALPHA,perceptual)*gain,lerpf(0.0,EMITTER_CONE_FAR_ALPHA,perceptual)*gain,lerpf(0.0,EMITTER_CONE_NEAR_EMISSION,perceptual)*gain,lerpf(0.0,EMITTER_CONE_FAR_EMISSION,perceptual)*gain)
