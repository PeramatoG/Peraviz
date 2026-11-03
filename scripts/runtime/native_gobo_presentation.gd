extends RefCounted

# Selection uses NAN; angular callbacks retain the same projection/resource owners.
# Still detect a resource/optical change caused by renderer refresh, even on an angular callback.
static func present(owner: Node, light: SpotLight3D, texture: Texture2D, angle: float) -> void:
	if not is_instance_valid(light): return
	var beam: MeshInstance3D = owner._get_beam_resource_for_light(light)
	var mesh: Mesh = beam.mesh if is_instance_valid(beam) else null
	var material: Material = beam.material_override if is_instance_valid(beam) else null
	var projector: Texture2D = light.light_projector
	var projection: RefCounted = light.get_meta(&"peraviz_optical_projection_state", null)
	var geometry_revision: int = projection.geometry_revision if projection != null else -1
	if not is_nan(angle):
		var params: Dictionary = light.get_meta("peraviz_beam_last_params", {})
		params["gobo_rotation_deg"] = angle
		light.set_meta("peraviz_beam_last_params", params)
	# Optical roll must not overwrite retained native shutter-modulated energy.
	# Selection/changed ownership still takes the full photometric path below.
	owner._refresh_native_gobo_presentation(light, texture, is_nan(angle))
	if owner._fixture_light_apply_service._render_diagnostic_mode == "full" and owner._active_beam_presentation == preload("res://scripts/beam_renderers/volumetric_beam_renderer.gd").PRESENTATION_SHADER_PROXY and owner._active_beam_renderer != null:
		owner._active_beam_renderer.update_beam(light, light.get_meta("peraviz_beam_last_params", {}))
	var current: MeshInstance3D = owner._get_beam_resource_for_light(light)
	var resources_changed: bool = current != beam or light.light_projector != projector or (is_instance_valid(current) and (current.mesh != mesh or current.material_override != material))
	var current_projection: RefCounted = light.get_meta(&"peraviz_optical_projection_state", null)
	var optics_changed: bool = current_projection != projection or (current_projection != null and current_projection.geometry_revision != geometry_revision)
	if is_nan(angle) or resources_changed or optics_changed:
		if not is_nan(angle): owner._fixture_light_apply_service._apply_desired_light_state(owner, light)
		owner._fixture_light_apply_service.rebind_dense_light(light)
