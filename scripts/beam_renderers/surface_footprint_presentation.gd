extends RefCounted

# Cold gobo bridge: consumes existing optical state and light ownership only.
static func refresh(loader: Node, light: SpotLight3D, texture: Texture2D = null) -> void:
	if loader._fixture_gobo_projector == null:
		return
	var params: Dictionary = light.get_meta("peraviz_beam_last_params", {})
	var active: bool = loader._fixture_light_apply_service._render_diagnostic_mode == "full" and bool(loader._fixture_light_apply_service._light_desired_for(light).get("visible", false)) if loader._fixture_light_apply_service != null else false
	var resolved_texture: Texture2D = texture
	if resolved_texture == null and light.has_meta("peraviz_gobo_texture"):
		resolved_texture = light.get_meta("peraviz_gobo_texture") as Texture2D
	if loader._active_beam_renderer != null and loader._active_beam_renderer.has_method("refresh_surface_profile"):
		loader._active_beam_renderer.refresh_surface_profile(light)
	var projection: RefCounted = light.get_meta(&"peraviz_optical_projection_state") if light.has_meta(&"peraviz_optical_projection_state") else null
	var surface: Texture2D = projection.surface_texture if projection != null and projection.smooth_profile_enabled and int(loader._visual_settings.get("beam_presentation", 1)) == 1 else null
	var desired_texture: Texture2D = (surface if surface != null else resolved_texture) if active else null
	if light.light_projector != desired_texture:
		loader._fixture_gobo_projector._set_light_projector_texture(light, desired_texture)
	loader._fixture_gobo_projector.set_shadow_mask_enabled(light, active and resolved_texture != null and int(loader._visual_settings.get("beam_presentation", 1)) == 2)
	if loader._fixture_light_apply_service._render_diagnostic_mode == "full":
		loader._fixture_gobo_projector.set_presentation_rotation(light, float(params.get("gobo_rotation_deg", 0.0)) if resolved_texture != null else 0.0)
	if loader._fixture_light_apply_service != null:
		loader._fixture_light_apply_service._apply_desired_light_state(loader, light)
