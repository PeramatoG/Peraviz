extends RefCounted

const VisualSettingsMigration = preload("res://scripts/visual_settings_migration.gd")

# Only listed value domains bypass the controlled structural lifecycle. Unknown
# optical/experimental settings retain the established replacement fallback.
const ATMOSPHERE = preload("res://scripts/runtime/shared_fake_smoke.gd")

const GAINS := ["lens_emission_multiplier", "beam_multiplier", "footprint_multiplier", "spot_multiplier"]
const PROFILES := ["wash_intersection_width_m", "beam_softness", "beam_radial_falloff", "beam_longitudinal_falloff", "haze_density_multiplier", "footprint_softness", "footprint_max_range", "light_volumetric_fog_energy"]
const ENVIRONMENT := ["ambient_multiplier", "bloom_multiplier", "background_color", "ambient_fog_density", "volumetric_fog_density", "volumetric_fog_length", "volumetric_fog_fade", "shared_haze_density", "shared_haze_margin"]

static func changed(previous: Dictionary, current: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in current:
		if previous.get(key) != current[key]: result[key] = current[key]
	return result

static func environment_changed(changes: Dictionary) -> bool:
	for key in changes:
		if str(key).begins_with("environment_") or key in ENVIRONMENT or key == "beam_presentation": return true
	return false

static func structural(changes: Dictionary) -> bool:
	for key in changes:
		if key not in ATMOSPHERE.KEYS and key not in GAINS and key not in PROFILES and key not in ENVIRONMENT and not str(key).begins_with("environment_"): return true
	return false

static func refresh_shaft_optics(changes: Dictionary) -> bool:
	for key in changes:
		if key in ["lens_emission_multiplier", "footprint_backend", "enable_realtime_spotlights", "footprint_multiplier", "spot_multiplier", "light_volumetric_fog_energy"]: continue
		if key in ATMOSPHERE.KEYS or key in ENVIRONMENT or str(key).begins_with("environment_"): continue
		return true
	return false

static func apply_values(loader: Node, changes: Dictionary) -> void:
	var service: RefCounted = loader._fixture_light_apply_service
	var adapter: RefCounted = service._dense_adapter
	var lenses: bool = changes.has("lens_emission_multiplier")
	var shafts: bool = changes.has("beam_multiplier")
	var surfaces: bool = changes.has("footprint_multiplier") or changes.has("spot_multiplier")
	var profiles: bool = false
	for key in PROFILES:
		if changes.has(key): profiles = true
	if not profiles and not shafts and not surfaces and not lenses: return
	if profiles:
		loader._beam_params_template_cache.clear()
		var renderer_profile: bool = false
		for key in ["wash_intersection_width_m", "beam_softness", "beam_radial_falloff", "beam_longitudinal_falloff", "haze_density_multiplier"]:
			if changes.has(key): renderer_profile = true
		if renderer_profile:
			for renderer in loader._beam_renderers.values(): renderer.configure(loader.camera, loader._visual_settings)
		if adapter != null:
			for output in adapter._outputs + adapter._render_bindings.aggregate_outputs():
				for handle in output.lights: _profile(loader, handle.light, changes)
		else:
			for lights in loader._fixture_emitter_light_cache.values():
				for light in lights: _profile(loader, light, changes)
	if adapter != null and (shafts or surfaces or lenses):
		# Finish any main-thread payload first; a worker's pending snapshot is
		# never consumed, cancelled or waited on by a settings edit.
		adapter.apply()
		if lenses:
			var writes: int = adapter._native.set_lens_emission_gain(float(loader._visual_settings.get("lens_emission_multiplier", 1.0)))
			adapter._record_mutation(&"material_parameter_writes", writes)
		adapter._update_native_beam_policy()
		var replay: Dictionary = adapter._native.replay_presentation_gains(shafts, surfaces, VisualSettingsMigration.surface_multiplier(loader._visual_settings), adapter._trace)
		if shafts:
			adapter._record_mutation(&"beam_shader_parameter_writes", int(replay.get("native_beam_parameter_writes", 0)))
			adapter._record_mutation(&"beam_visibility_writes", int(replay.get("native_beam_visibility_writes", 0)))
			adapter._payload = replay
			adapter.apply()
		if surfaces and (str(loader._visual_settings.get("footprint_backend", "custom")) == "native" or bool(loader._visual_settings.get("enable_realtime_spotlights", false)) or adapter._diagnostic_open_surface_lights):
			for output in adapter._outputs:
				for handle in output.lights: adapter.apply_light_state(handle.light)
		if adapter._trace:
			for key in ["gain_replay_us", "native_beam_parameter_writes", "native_beam_visibility_writes", "surface_gain_writes"]:
				loader._live_settings_trace[key] = replay.get(key, 0)
	elif adapter == null:
		for lights in loader._fixture_emitter_light_cache.values():
			for light in lights:
				if shafts:
					var params: Dictionary = light.get_meta("peraviz_beam_last_params", {})
					loader._update_beam_intensity_for_light(light, float(light.get_meta("peraviz_beam_base_intensity", params.get("normalized_dimmer", 0.0))), params.get("beam_color", Color.WHITE))
				if surfaces: loader._apply_light_scalars_to_light(light)

static func _profile(loader: Node, light: SpotLight3D, changes: Dictionary) -> void:
	if not is_instance_valid(light): return
	var params: Dictionary = light.get_meta("peraviz_beam_last_params", {})
	if params.is_empty(): return
	var beam_profile: bool = false
	for key in changes:
		if key in PROFILES: params[key] = changes[key]
		if key in ["wash_intersection_width_m", "beam_softness", "beam_radial_falloff", "beam_longitudinal_falloff", "haze_density_multiplier"]: beam_profile = true
	if changes.has("haze_density_multiplier"): params["haze_density"] = changes.haze_density_multiplier
	if beam_profile:
		if loader._active_beam_renderer.has_method("update_profile_uniforms"):
			loader._active_beam_renderer.update_profile_uniforms(light, params)
		else:
			loader._active_beam_renderer.update_beam(light, params)
	elif changes.has("footprint_softness"):
		var projection: RefCounted = light.get_meta("peraviz_optical_projection_state") if light.has_meta("peraviz_optical_projection_state") else null
		if projection != null:
			projection.footprint_softness = clampf(float(changes.footprint_softness), 0.0, 0.25)
			if str(loader._visual_settings.get("footprint_backend", "custom")) == "native" and loader._active_beam_renderer.has_method("refresh_surface_profile"):
				loader._active_beam_renderer.refresh_surface_profile(light)
	var volume: MeshInstance3D = light.get_meta("peraviz_custom_footprint") if light.has_meta("peraviz_custom_footprint") else null
	if volume != null:
		if changes.has("footprint_max_range"): volume.configure(volume.projection, float(changes.footprint_max_range))
		elif beam_profile: volume.sync()
		elif changes.has("footprint_softness"): volume.sync_softness()
	if changes.has("light_volumetric_fog_energy"):
		var rid: RID = loader._get_light_base_rid(light)
		if rid.is_valid(): RenderingServer.light_set_param(rid, RenderingServer.LIGHT_PARAM_VOLUMETRIC_FOG_ENERGY, float(changes.light_volumetric_fog_energy))

# Constant-time ownership counters; never call scene/resource inventory diagnostics
# from the slider. The normal trace flag governs both these reads and timing.
static func counters(loader: Node) -> Dictionary:
	var result := {"registry_calls": loader._native_target_registry.shaft_registry_calls, "registry_scans": loader._native_target_registry.shaft_registry_scans}
	var renderer: BeamRendererBase = loader._active_beam_renderer
	if renderer != null:
		result["script_beam_parameter_writes"] = renderer.renderer_shader_parameter_writes
		if renderer.has_method("shaft_resource_counters"): result.merge(renderer.shaft_resource_counters())
	var adapter: RefCounted = loader._fixture_light_apply_service._dense_adapter
	if adapter != null:
		result["lens_batches_created"] = adapter._lens_batches.created
		result["lens_batches_retired"] = adapter._lens_batches.retired
		result["footprint_volumes_created"] = adapter._footprints.created
		result["footprint_volumes_retired"] = adapter._footprints.retired
		result["footprint_binding_installs"] = adapter._footprints.installs
	return result
