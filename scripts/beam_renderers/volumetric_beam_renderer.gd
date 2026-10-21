extends BeamRendererBase

class_name VolumetricBeamRenderer

const BoundBeamStateScript = preload("res://scripts/beam_renderers/bound_beam_state.gd")

const GoboRotationPresentationScript = preload("res://scripts/runtime/gobo_indexed_rotation_presentation.gd")
const BEAM_META_KEY: String = "peraviz_volumetric_beam"
const DEBUG_AXIS_KEY: String = "peraviz_beam_debug_axis"
const SHAPE_MODE_GOBO_PRISM: String = "gobo_prism"
const SHAPE_MODE_CONE: String = "cone"
const DYNAMIC_STATE_META_KEY: String = "peraviz_beam_dynamic_state"
const DYNAMIC_STATE_APPLIED_META_KEY: String = "peraviz_beam_dynamic_state_applied"
const INTENSITY_MAX_DESIRED_META_KEY: String = "peraviz_beam_intensity_max_desired"
const INTENSITY_MAX_META_KEY: String = "peraviz_beam_intensity_max"
const PRESENTATION_FOG_VOLUME: int = 0
const PRESENTATION_VECTOR_PRISM: int = 1
const PRESENTATION_NATIVE_SHADOW: int = 2
const PRESENTATION_SHADER_PROXY: int = 3
const FogVolumeControllerScript = preload("res://scripts/fog_volume_gobo_beam_controller.gd")
const ShaderBeamProxyControllerScript = preload("res://scripts/beam_renderers/shader_beam_proxy_controller.gd")

const OpticalProjection = preload("res://scripts/runtime/optical_projection_state.gd")
const FootprintCache = preload("res://scripts/beam_renderers/footprint_profile_cache.gd")
const SurfacePolicy = preload("res://scripts/runtime/surface_light_policy.gd")
var _diagnostic_open_surface_lights: bool = SurfacePolicy.open_lights_from_arguments(OS.get_cmdline_user_args())
var _footprint_cache: RefCounted = FootprintCache.new()

var _beam_material_template: ShaderMaterial
var _camera: Camera3D
var _settings: Dictionary = {}
var _beam_settings_hash: int = 0
var _shape_providers: Dictionary = {}
var _active_shape_provider: VolumetricBeamShapeProvider
var _last_parameter_write_count: int = 0
var _presentation_mode: int = PRESENTATION_VECTOR_PRISM
var _fog_controller: FogVolumeGoboBeamController = FogVolumeControllerScript.new()
var _proxy_controller: ShaderBeamProxyController = ShaderBeamProxyControllerScript.new()

func _init() -> void:
	_beam_material_template = ShaderMaterial.new()
	_beam_material_template.shader = load("res://scripts/shaders/volumetric_beam.gdshader")
	_shape_providers[SHAPE_MODE_GOBO_PRISM] = VolumetricGoboPrismShapeProvider.new()
	_shape_providers[SHAPE_MODE_CONE] = VolumetricConeShapeProvider.new()
	_active_shape_provider = _shape_providers[SHAPE_MODE_GOBO_PRISM] as VolumetricBeamShapeProvider

func configure(view_camera: Camera3D, settings: Dictionary) -> void:
	_camera = view_camera
	_settings = settings.duplicate(true)
	_presentation_mode = int(settings.get("beam_presentation", PRESENTATION_VECTOR_PRISM))
	_beam_settings_hash = _compute_beam_settings_hash()
	_active_shape_provider = _select_shape_provider()

func ensure_beam(light: SpotLight3D) -> void:
	if _presentation_mode != PRESENTATION_VECTOR_PRISM:
		return
	if light.has_meta(BEAM_META_KEY):
		return
	var beam := MeshInstance3D.new()
	beam.name = "PeravizVolumetricBeam"
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.material_override = _beam_material_template.duplicate(true)
	beam.rotation_degrees.x = 90.0
	_set_bound_visibility(beam, false)
	light.add_child(beam)
	light.set_meta(BEAM_META_KEY, beam)
	_apply_static_beam_params(beam, {})

func update_beam(light: SpotLight3D, params: Dictionary) -> void:
	if _presentation_mode != PRESENTATION_VECTOR_PRISM:
		_update_experimental_beam(light, params)
		return
	ensure_beam(light)
	var beam: MeshInstance3D = light.get_meta(BEAM_META_KEY) as MeshInstance3D
	if beam == null:
		return
	params["smooth_light_profile"] = true
	BoundBeamStateScript.invalidate_resource(beam)
	var beam_type: String = str(params.get("beam_type", "Wash")).to_lower()
	if beam_type == "none" or beam_type == "glow":
		_set_bound_visibility(beam, false)
		_sync_debug_axis(light, false)
		return

	# Surface geometry/photometry must resolve even when the shaft gain is zero.
	var projection: RefCounted = OpticalProjection.resolve(light)
	projection.configure(params, light.get_meta("peraviz_gobo_texture") as Texture2D if light.has_meta("peraviz_gobo_texture") else null)
	if not params.has("profile_beam_angle"): params["profile_beam_angle"] = projection.base_beam_angle_deg
	projection.apply_footprint(light)
	refresh_surface_profile(light)
	if bool(params.get("beam_debug_optics", false)): print("[PeravizOpticalProfile] ", projection.diagnostic(params))

	var intensity_max: float = max(float(params.get("intensity_max", 100.0)), 0.01)
	var intensity: float = clamp(float(params.get("scaled_intensity", 0.0)), 0.0, intensity_max)
	var threshold: float = float(params.get("intensity_visibility_threshold", 0.015))
	var beam_range: float = max(float(params.get("beam_range", 0.1)), 0.01)
	var beam_angle: float = max(float(params.get("beam_angle", 1.0)), 0.1)

	# Keep cold dark emitters lazy; an already-initialized shaft must still
	# consume optical changes while black so intensity-only reactivation is safe.
	if intensity <= threshold and beam.mesh == null:
		_set_bound_visibility(beam, false)
		_store_dynamic_state(beam, params.get("beam_color", Color.WHITE), intensity)
		beam.set_meta(INTENSITY_MAX_DESIRED_META_KEY, intensity_max)
		_sync_debug_axis(light, false)
		return
	_sync_debug_axis(light, bool(params.get("beam_debug_optics", false)))

	var beam_color: Color = params.get("beam_color", Color.WHITE)
	if not params.has("profile_beam_angle"):
		params["profile_beam_angle"] = beam_angle
	var shape_result: Dictionary = _active_shape_provider.apply_shape(beam, light, params)
	var gobo_projection_radius: float = max(float(shape_result.get("gobo_projection_radius", 0.1)), 0.001)
	params["gobo_projection_radius"] = gobo_projection_radius
	var beam_rotation_deg: float = float(shape_result.get("beam_rotation_deg", 0.0))

	if bool(params.get("beam_debug_optics", false)):
		print("[PeravizBeamOptics] mode=", _active_shape_provider.shape_mode(), " angle_deg=", beam_angle, " range_m=", beam_range, " radius_end_m=", gobo_projection_radius)

	_set_bound_visibility(beam, intensity > threshold)
	if intensity <= threshold: _sync_debug_axis(light, false)

	_apply_intensity_max(beam, intensity_max)
	_store_dynamic_state(beam, beam_color, intensity)
	_apply_dynamic_state(beam, beam_color, intensity)
	_apply_static_beam_params(beam, params)
	if not beam.has_meta(&"peraviz_optical_projection_state"):
		GoboRotationPresentationScript.reapply_after_base_alignment(beam, beam_rotation_deg)
	_set_bound_shader_parameter(beam, "cone_height", max(beam_range, 0.001))
	_set_bound_shader_parameter(beam, "gobo_projection_radius", gobo_projection_radius)
	if light.has_meta(&"peraviz_optical_projection_state"):
		var profile: RefCounted = projection.radial_profile
		_set_bound_shader_parameter(beam, "profile_parameters", profile.signature)
		_set_bound_shader_parameter(beam, "profile_feather_start", profile.feather_start)
		refresh_surface_profile(light)

# Cold gobo/setup bridge; roll and repeated Zoom only compare typed identities.
func refresh_surface_profile(light: SpotLight3D) -> void:
	if _presentation_mode != PRESENTATION_VECTOR_PRISM or not light.has_meta(&"peraviz_optical_projection_state"): return
	var projection: RefCounted = light.get_meta(&"peraviz_optical_projection_state")
	if not projection.configured: return
	var source: Texture2D = light.get_meta("peraviz_gobo_texture") as Texture2D if light.has_meta("peraviz_gobo_texture") else null
	var source_id: int = source.get_instance_id() if source != null else 0
	var open_owner: bool = SurfacePolicy.owns_realtime_light(bool(_settings.get("enable_realtime_spotlights", false)), _presentation_mode, false, _diagnostic_open_surface_lights, projection.has_projected_surface_profile)
	var uses_projector: bool = source != null or (projection.radial_profile.rectangular and open_owner)
	if projection.surface_source_id == source_id and projection.surface_profile_revision == projection.profile_revision and projection.surface_softness == projection.footprint_softness and projection.surface_uses_projector == uses_projector: return
	projection.surface_source_id = source_id
	projection.surface_profile_revision = projection.profile_revision
	projection.surface_softness = projection.footprint_softness
	projection.surface_uses_projector = uses_projector
	# Circular open profiles use native unshadowed angular attenuation. Rectangle
	# needs a mask because a native circular cone cannot represent its corners.
	projection.surface_texture = _footprint_cache.texture_for(projection.radial_profile, source, projection.footprint_softness) if uses_projector else null
	if source == null:
		if light.has_meta("peraviz_pre_projector_shadow_enabled"):
			light.shadow_enabled = bool(light.get_meta("peraviz_pre_projector_shadow_enabled"))
			light.remove_meta("peraviz_pre_projector_shadow_enabled")
		if uses_projector:
			light.set_meta("peraviz_pre_projector_shadow_enabled", light.shadow_enabled)
			light.shadow_enabled = true
		light.light_projector = projection.surface_texture
	if source != null and light.light_projector != null:
		light.light_projector = projection.surface_texture

func _compute_beam_settings_hash() -> int:
	var hash_value: int = 2166136261
	for key in ["beam_softness", "beam_radial_falloff", "beam_longitudinal_falloff"]:
		hash_value = int((hash_value ^ hash(_settings.get(key, null))) * 16777619)
	return hash_value

func _apply_static_beam_params(beam: MeshInstance3D, params: Dictionary) -> void:
	var haze_density: float = max(float(params.get("haze_density", params.get("haze_density_multiplier", 0.22))), 0.0)
	var static_hash: int = _beam_settings_hash
	static_hash = int((static_hash ^ hash(haze_density)) * 16777619)
	static_hash = int((static_hash ^ hash(float(params.get("beam_radial_falloff", 1.0)))) * 16777619)
	static_hash = int((static_hash ^ hash(float(params.get("beam_longitudinal_falloff", 1.0)))) * 16777619)
	static_hash = int((static_hash ^ hash(float(params.get("beam_softness", 0.32)))) * 16777619)
	if int(beam.get_meta("peraviz_static_beam_hash", 0)) == static_hash:
		return
	beam.set_meta("peraviz_static_beam_hash", static_hash)
	_set_bound_shader_parameter(beam, "haze_density", haze_density)
	_set_bound_shader_parameter(beam, "longitudinal_falloff", max(float(params.get("beam_longitudinal_falloff", 1.0)), 0.0))

func update_beam_intensity(light: SpotLight3D, params: Dictionary) -> int:
	_last_parameter_write_count = 0
	if _presentation_mode != PRESENTATION_VECTOR_PRISM:
		var result: Dictionary = _update_experimental_beam(light, params)
		_last_parameter_write_count = int(result.get("parameter_write_count", 0))
		return INTENSITY_CHANGED if bool(result.get("changed", false)) else INTENSITY_UNCHANGED
	if not light.has_meta(BEAM_META_KEY):
		return INTENSITY_UNRESOLVED
	var beam: MeshInstance3D = light.get_meta(BEAM_META_KEY) as MeshInstance3D
	if beam == null or not is_instance_valid(beam):
		return INTENSITY_UNRESOLVED
	if beam.has_meta(BoundBeamStateScript.META_KEY):
		return update_bound_intensity(light, beam, params, BoundBeamStateScript.resolve(beam))

	var intensity_max: float = max(float(params.get("intensity_max", 100.0)), 0.01)
	var intensity: float = clamp(float(params.get("scaled_intensity", 0.0)), 0.0, intensity_max)
	var threshold: float = float(params.get("intensity_visibility_threshold", 0.015))
	var beam_type: String = str(params.get("beam_type", "Wash")).to_lower()
	if beam_type == "none" or beam_type == "glow":
		_set_bound_visibility(beam, false)
		_sync_debug_axis(light, false)
		return INTENSITY_UNCHANGED
	if intensity > threshold and not is_beam_dynamic_ready(light):
		return INTENSITY_UNRESOLVED
	var beam_color: Color = params.get("beam_color", Color.WHITE)
	var dynamic_state := Color(beam_color.r, beam_color.g, beam_color.b, intensity)
	var signature := Color(dynamic_state.r, dynamic_state.g, dynamic_state.b, threshold)
	if beam.get_meta("peraviz_intensity_signature", Color(-1.0, -1.0, -1.0, -1.0)) == signature and float(beam.get_meta(DYNAMIC_STATE_META_KEY, Color(0.0, 0.0, 0.0, 0.0)).a) == intensity and float(beam.get_meta(INTENSITY_MAX_DESIRED_META_KEY, -1.0)) == intensity_max:
		return INTENSITY_UNCHANGED
	beam.set_meta("peraviz_intensity_signature", signature)
	_store_dynamic_state(beam, beam_color, intensity)
	beam.set_meta(INTENSITY_MAX_DESIRED_META_KEY, intensity_max)
	if intensity <= threshold:
		_set_bound_visibility(beam, false)
		_sync_debug_axis(light, false)
		return INTENSITY_CHANGED

	_apply_intensity_max(beam, intensity_max)
	_set_bound_visibility(beam, true)
	_apply_dynamic_state(beam, beam_color, intensity)
	return INTENSITY_CHANGED

func _store_dynamic_state(beam: MeshInstance3D, color: Color, intensity: float) -> void:
	beam.set_meta(DYNAMIC_STATE_META_KEY, Color(color.r, color.g, color.b, intensity))

func _apply_dynamic_state(beam: MeshInstance3D, color: Color, intensity: float) -> void:
	if beam.has_meta(&"peraviz_control_group_material"): return
	var dynamic_state := Color(color.r, color.g, color.b, intensity)
	if beam.has_meta(BoundBeamStateScript.META_KEY):
		var bound := BoundBeamStateScript.resolve(beam)
		if bound.applied_dynamic == dynamic_state: return
		bound.applied_dynamic = dynamic_state
	else:
		if beam.get_meta(DYNAMIC_STATE_APPLIED_META_KEY, Color(-1.0, -1.0, -1.0, -1.0)) == dynamic_state: return
		beam.set_meta(DYNAMIC_STATE_APPLIED_META_KEY, dynamic_state)
	_set_bound_shader_parameter(beam, "beam_dynamic_state", dynamic_state)
	renderer_dynamic_parameter_writes += 1
	_last_parameter_write_count += 1

func _apply_intensity_max(beam: MeshInstance3D, intensity_max: float) -> void:
	if beam.has_meta(BoundBeamStateScript.META_KEY):
		var bound := BoundBeamStateScript.resolve(beam)
		if is_equal_approx(bound.applied_max, intensity_max): return
		bound.applied_max = intensity_max
	else:
		if is_equal_approx(float(beam.get_meta(INTENSITY_MAX_META_KEY, -1.0)), intensity_max): return
		beam.set_meta(INTENSITY_MAX_META_KEY, intensity_max)
	_set_bound_shader_parameter(beam, "intensity_max", intensity_max)
	_last_parameter_write_count += 1

func get_last_parameter_write_count() -> int:
	return _last_parameter_write_count

func is_beam_dynamic_ready(light: SpotLight3D) -> bool:
	var beam: MeshInstance3D = get_beam_resource(light)
	return beam != null and beam.mesh != null

func apply_beam_optics(light: SpotLight3D, params: Dictionary) -> Dictionary:
	update_beam(light, params)
	return {"applied": true, "beam_instance_resolved": get_beam_resource(light) != null, "topology_rebuilt": true, "parametric_update_performed": false, "failure_reason": "volumetric backend rebuilds optics as a compatibility path"}

func get_beam_optics_state(light: SpotLight3D) -> Dictionary:
	if light != null and light.has_meta("peraviz_beam_optics_state"):
		return light.get_meta("peraviz_beam_optics_state", {}) as Dictionary
	return {}

func get_beam_resource(light: SpotLight3D) -> MeshInstance3D:
	if _presentation_mode == PRESENTATION_SHADER_PROXY:
		return _proxy_controller.get_proxy(light)
	if not light.has_meta(BEAM_META_KEY):
		return null
	var beam: MeshInstance3D = light.get_meta(BEAM_META_KEY) as MeshInstance3D
	return beam if beam != null and is_instance_valid(beam) else null

func cleanup_beam(light: SpotLight3D) -> void:
	_fog_controller.clear_for_light(light)
	_proxy_controller.clear_for_light(light)
	if light.has_meta(BEAM_META_KEY):
		var beam: MeshInstance3D = light.get_meta(BEAM_META_KEY) as MeshInstance3D
		if beam != null and is_instance_valid(beam):
			beam.queue_free()
		light.remove_meta(BEAM_META_KEY)
	_cleanup_debug_axis(light)

func _update_experimental_beam(light: SpotLight3D, params: Dictionary) -> Dictionary:
	params["smooth_light_profile"] = false
	if light.has_meta(&"peraviz_optical_projection_state"):
		var projection: RefCounted = light.get_meta(&"peraviz_optical_projection_state")
		projection.configure(params, light.get_meta("peraviz_gobo_texture") as Texture2D if light.has_meta("peraviz_gobo_texture") else null)
		projection.apply_footprint(light)
	var visibility_before: int = _proxy_controller.renderer_visibility_writes
	var shader_before: int = _proxy_controller.renderer_shader_parameter_writes
	var result := {"changed": false, "resource_created": false, "visibility_changed": false, "parameter_write_count": 0}
	var existing: MeshInstance3D = get_beam_resource(light)
	# Only hide the vector resource when an experimental renderer owns the current update.
	if _presentation_mode != PRESENTATION_SHADER_PROXY and existing != null and existing.visible:
		_set_bound_visibility(existing, false)
		result["changed"] = true
		result["visibility_changed"] = true
	_fog_controller.clear_for_light(light)
	if _presentation_mode == PRESENTATION_SHADER_PROXY:
		var texture: Texture2D = light.get_meta("peraviz_gobo_texture") as Texture2D if light.has_meta("peraviz_gobo_texture") else null
		result = _proxy_controller.update_for_light(light, params, texture)
	else:
		_proxy_controller.hide_for_light(light)
	light.set_meta("peraviz_beam_last_params", params)
	_last_parameter_write_count = int(result.get("parameter_write_count", 0))
	renderer_visibility_writes += _proxy_controller.renderer_visibility_writes - visibility_before
	renderer_shader_parameter_writes += _proxy_controller.renderer_shader_parameter_writes - shader_before
	return result

func get_proxy_diagnostics() -> Dictionary:
	return _proxy_controller.counters()

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
	for provider in _shape_providers.values():
		provider.clear_cache()
	_proxy_controller.reset_scene_state()
	_footprint_cache.clear()

# Retains Vector Gobo Prism shading with directly bound beam resources.
func update_bound_intensity(light: SpotLight3D, beam: MeshInstance3D, params: Dictionary, bound: RefCounted = null) -> int:
	_last_visibility_write_count = 0
	if _presentation_mode != PRESENTATION_VECTOR_PRISM:
		var before: bool = is_instance_valid(beam) and beam.visible
		var result: int = update_beam_intensity(light, params)
		var current: MeshInstance3D = get_beam_resource(light)
		_last_visibility_write_count = 1 if is_instance_valid(current) and current.visible != before else 0
		return result
	_last_parameter_write_count = 0
	if not is_instance_valid(beam):
		return INTENSITY_UNRESOLVED
	var intensity_max: float = maxf(float(params.get("intensity_max", 100.0)), 0.01)
	var intensity: float = clampf(float(params.get("scaled_intensity", 0.0)), 0.0, intensity_max)
	var visible: bool = intensity > float(params.get("intensity_visibility_threshold", 0.015))
	if visible and beam.mesh == null:
		return INTENSITY_UNRESOLVED
	var state: RefCounted = BoundBeamStateScript.resolve(beam, bound)
	if beam.visible != visible:
		_set_bound_visibility(beam, visible)
		_last_visibility_write_count = 1
	if not visible:
		return INTENSITY_CHANGED if _last_visibility_write_count > 0 else INTENSITY_UNCHANGED
	var color: Color = params.get("beam_color", Color.WHITE)
	var dynamic := Color(color.r, color.g, color.b, intensity)
	if state.applied_max != intensity_max:
		_set_bound_shader_parameter(beam, "intensity_max", intensity_max)
		state.applied_max = intensity_max
		_last_parameter_write_count += 1
	if not beam.has_meta(&"peraviz_control_group_material") and state.applied_dynamic != dynamic:
		_set_bound_shader_parameter(beam, "beam_dynamic_state", dynamic)
		renderer_dynamic_parameter_writes += 1
		state.applied_dynamic = dynamic
		_last_parameter_write_count += 1
	return INTENSITY_CHANGED if _last_visibility_write_count + _last_parameter_write_count > 0 else INTENSITY_UNCHANGED

# Setup-only resource binding. Geometry and all static optical instance uniforms stay physical.
func bind_control_group(beams: Array) -> ShaderMaterial:
	if _presentation_mode != PRESENTATION_VECTOR_PRISM or beams.size() < 2: return null
	for beam in beams:
		if not is_instance_valid(beam) or not beam.material_override is ShaderMaterial: return null
		if beam.material_override.shader != _beam_material_template.shader: return null
		if beam.material_override.next_pass != null: return null
		if beam.material_override.render_priority != beams[0].material_override.render_priority: return null
		if beam.material_override.get_shader_parameter("has_gobo_energy") == true: return null
		if beam.material_override.get_shader_parameter("gobo_coverage") != null: return null
		if beam.material_override.get_shader_parameter("gobo_mask") != null: return null
	var material: ShaderMaterial = beams[0].material_override.duplicate(false)
	material.set_shader_parameter("use_control_group_state", true)
	for beam in beams:
		beam.material_override = material
		beam.set_meta(&"peraviz_control_group_material", material)
	return material

# Retires sharing before renderer/settings replacement; normal independent APIs remain valid.
func unbind_control_group(beam: MeshInstance3D) -> void:
	if not is_instance_valid(beam) or not beam.has_meta(&"peraviz_control_group_material"): return
	var material: ShaderMaterial = beam.material_override.duplicate(false)
	material.set_shader_parameter("use_control_group_state", false)
	beam.material_override = material
	beam.remove_meta(&"peraviz_control_group_material")
	BoundBeamStateScript.invalidate_resource(beam)
