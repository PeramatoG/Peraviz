extends VolumetricBeamShapeProvider
class_name VolumetricGoboPrismShapeProvider

const OpticalProjectionScript = preload("res://scripts/runtime/optical_projection_state.gd")


const GOBO_TEXTURE_META_KEY: String = "peraviz_gobo_texture"

var _mesh_builder: GoboPrismMeshBuilder = GoboPrismMeshBuilder.new()

func shape_mode() -> String:
	return "gobo_prism"

func apply_shape(beam: MeshInstance3D, light: SpotLight3D, params: Dictionary) -> Dictionary:
	var projection = OpticalProjectionScript.resolve(light)
	var gobo_texture: Texture2D = light.get_meta(GOBO_TEXTURE_META_KEY) as Texture2D if light.has_meta(GOBO_TEXTURE_META_KEY) else null
	if not projection.configured:
		projection.set_roll(float(beam.get_meta("peraviz_gobo_indexed_rotation_deg", params.get("gobo_rotation_deg", 0.0))))
	projection.configure(params, gobo_texture)
	projection.apply_footprint(light)
	var beam_range: float = projection.visual_range
	var lens_radius: float = projection.lens_radius
	var bottom_radius: float = projection.far_radius
	var gobo_scale: float = projection.gobo_scale
	var beam_rotation_deg: float = projection.alignment_roll_deg
	var mirror_x: bool = projection.mirror_x
	var mirror_z: bool = projection.mirror_z
	if int(beam.get_meta("peraviz_projection_geometry_revision", -1)) != projection.geometry_revision:
		var prism_mesh: ArrayMesh
		if projection.radial_profile.rectangular and gobo_texture == null:
			prism_mesh = _mesh_builder.build_aperture_beam_mesh({"shape": "rectangle", "rectangle_ratio": float(params.get("rectangle_ratio", 1.0))}, 1.0)
		else:
			prism_mesh = _mesh_builder.build_normalized_beam_mesh(gobo_texture)
		light.set_meta("peraviz_last_beam_gobo_consumed", gobo_texture != null)
		light.set_meta("peraviz_last_beam_renderer_mode", shape_mode())
		if prism_mesh != null:
			beam.mesh = prism_mesh
		var scaled_near: float = max(lens_radius * gobo_scale, 0.001)
		var scaled_far: float = max(bottom_radius, 0.001)
		beam.set_instance_shader_parameter("use_normalized_gobo_topology", true)
		beam.set_instance_shader_parameter("topology_near_radius", scaled_near)
		beam.set_instance_shader_parameter("topology_far_radius", scaled_far)
		beam.set_meta("peraviz_gobo_normalized_near_ratio", scaled_near / scaled_far)
		# CPU culling must include the shader-expanded shoulder, including Rectangle.
		var aspect: Vector2 = projection.radial_profile.aspect
		var extent := Vector2(maxf(scaled_near, scaled_far), maxf(scaled_near, scaled_far)) * aspect
		beam.custom_aabb = AABB(Vector3(-extent.x, -0.5, -extent.y), Vector3(extent.x * 2.0, 1.0, extent.y * 2.0))
		beam.set_meta("peraviz_projection_geometry_revision", projection.geometry_revision)
	projection.apply_shaft(beam)
	return {
		"gobo_projection_radius": max(bottom_radius, 0.001),
		"beam_rotation_deg": beam_rotation_deg,
		"mirror_x": mirror_x,
		"mirror_z": mirror_z,
	}

func clear_cache() -> void:
	_mesh_builder.clear_cache()
