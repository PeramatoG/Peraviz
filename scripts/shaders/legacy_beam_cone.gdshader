shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_prepass_alpha, shadows_disabled;

instance uniform vec4 beam_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
instance uniform float near_alpha = 0.16;
instance uniform float far_alpha = 0.004;
instance uniform float near_emission = 0.45;
instance uniform float far_emission = 0.04;
instance uniform float cone_height = 15.0;
instance uniform float fade_end_ratio = 0.82;
instance uniform float lateral_softness = 0.35;
instance uniform float lateral_emission_boost = 0.16;
instance uniform float volumetric_noise_strength = 0.06;
instance uniform float volumetric_noise_scale = 14.0;
instance uniform float gobo_projection_radius = 1.0;
instance uniform vec2 beam_radius_params = vec2(0.03, 1.0);
instance uniform float radial_falloff = 1.1;
instance uniform float longitudinal_falloff = 1.0;
instance uniform vec2 gobo_transform = vec2(1.0, 0.0);
instance uniform vec2 appearance_core_field = vec2(0.7, 1.0);
instance uniform vec2 appearance_edge_exp = vec2(0.1, 1.1);
instance uniform vec2 appearance_gain_floor = vec2(1.0, 0.08);
instance uniform vec4 appearance_extinction = vec4(0.01, 1.0, 1.0, 0.12);
instance uniform int appearance_shape = 0;
instance uniform vec2 appearance_rect_half_extents = vec2(1.0, 1.0);

uniform float haze_density = 0.35;
uniform sampler2D gobo_texture : source_color;
uniform bool use_gobo = false;
uniform float gobo_contrast : hint_range(0.1, 4.0) = 1.0;
uniform bool gobo_invert = false;
uniform float gobo_min_transmission : hint_range(0.0, 1.0) = 0.12;
uniform float gobo_contribution : hint_range(0.0, 1.0) = 0.85;
uniform float beam_alpha_floor : hint_range(0.0, 0.2) = 0.03;

varying float beam_axial;
varying vec3 beam_local;

void vertex() {
	float normalized_y = (VERTEX.y / max(cone_height, 0.0001)) + 0.5;
	beam_axial = clamp(normalized_y, 0.0, 1.0);
	float beam_radius = mix(max(beam_radius_params.y, 0.0001), max(beam_radius_params.x, 0.0001), beam_axial);
	VERTEX.xz *= beam_radius;
	beam_local = VERTEX;
}

vec2 project_gobo_uv(vec3 local_pos) {
	float source_y = 0.5 * cone_height;
	float axial_dist = max(abs(source_y - local_pos.y), 0.001);
	float projection_scale = cone_height / axial_dist;
	float projection_radius = max(gobo_projection_radius, 0.001);
	vec2 projected = local_pos.xz * projection_scale;
	float rotation_rad = radians(gobo_transform.y);
	float cos_r = cos(rotation_rad);
	float sin_r = sin(rotation_rad);
	vec2 rotated = vec2(
		(projected.x * cos_r) - (projected.y * sin_r),
		(projected.x * sin_r) + (projected.y * cos_r)
	);
	float safe_scale = max(gobo_transform.x, 0.05);
	return vec2(0.5) + ((rotated / safe_scale) / (2.0 * projection_radius));
}


float normalized_radius_from_local(vec3 local_pos) {
	float local_radius = mix(max(beam_radius_params.y, 0.0001), max(beam_radius_params.x, 0.0001), clamp((local_pos.y / max(cone_height, 0.0001)) + 0.5, 0.0, 1.0));
	if (appearance_shape == 1) {
		return max(abs(local_pos.x) / max(local_radius * appearance_rect_half_extents.x, 0.0001), abs(local_pos.z) / max(local_radius * appearance_rect_half_extents.y, 0.0001));
	}
	return length(local_pos.xz) / max(local_radius, 0.0001);
}

float radial_profile_from_local(vec3 local_pos) {
	float radius_norm = clamp(normalized_radius_from_local(local_pos), 0.0, 1.0);
	float core = clamp(appearance_core_field.x, 0.0, 0.98);
	float field = clamp(max(appearance_core_field.y, core + 0.01), core + 0.01, 1.0);
	float edge_t = smoothstep(core, field, radius_norm);
	float envelope = mix(1.0, clamp(appearance_gain_floor.y, 0.0, 0.5), edge_t);
	if (radius_norm > field) {
		envelope *= 1.0 - smoothstep(field, 1.0, radius_norm);
	}
	return max(pow(clamp(envelope, 0.0, 1.0), max(appearance_edge_exp.y, 0.05)) * max(appearance_gain_floor.x, 1.0), 0.0);
}

float longitudinal_visibility_from_axial(float axial_from_near) {
	float distance_m = clamp(axial_from_near, 0.0, 1.0) * max(cone_height, 0.0001);
	float transmittance = exp(-max(appearance_extinction.x, 0.0) * distance_m);
	float shaped = pow(clamp(transmittance, 0.0, 1.0), max(appearance_extinction.y, 0.05)) * max(appearance_extinction.z, 0.0);
	return clamp(max(shaped, clamp(appearance_extinction.w, 0.0, 0.5)), 0.0, 1.0);
}

float sample_gobo_mask(vec2 uv) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.0;
	}
	vec4 texel = texture(gobo_texture, uv);
	float luma = clamp(dot(texel.rgb, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
	float alpha = clamp(texel.a, 0.0, 1.0);
	float open_amount = luma;
	if (gobo_invert) {
		open_amount = 1.0 - luma;
	}
	float optical_mask = pow(clamp(open_amount * alpha, 0.0, 1.0), gobo_contrast);
	return mix(1.0, max(optical_mask, gobo_min_transmission), clamp(gobo_contribution, 0.0, 1.0));
}

void fragment() {
	float near_factor = beam_axial;
	float far_progress = 1.0 - beam_axial;
	float end_fade = longitudinal_visibility_from_axial(far_progress);
	float view_alignment = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float view_fade = smoothstep(0.0, clamp(lateral_softness, 0.02, 1.0), view_alignment);
	float radial_fade = radial_profile_from_local(beam_local);
	float lateral_fade = view_fade * radial_fade;
	float axial_noise = sin((beam_axial * volumetric_noise_scale) + (TIME * 0.9));
	float beam_noise = 1.0 + (axial_noise * volumetric_noise_strength);
	float center_boost = (1.0 + (lateral_emission_boost * lateral_fade)) * beam_noise;
	float gobo_mask = 1.0;
	if (use_gobo) {
		vec2 gobo_uv = project_gobo_uv(beam_local);
		gobo_mask = sample_gobo_mask(gobo_uv);
	}
	ALBEDO = beam_color.rgb * gobo_mask;
	float beam_alpha = mix(far_alpha, near_alpha, near_factor) * end_fade * lateral_fade * gobo_mask * max(haze_density, 0.01);
	beam_alpha = max(beam_alpha, beam_alpha_floor * max(haze_density, 0.01));
	if (beam_alpha < 0.0001) {
		discard;
	}
	ALPHA = clamp(beam_alpha, 0.0, 1.0);
	EMISSION = beam_color.rgb * (mix(far_emission, near_emission, near_factor) * end_fade * center_boost * gobo_mask * max(haze_density, 0.05));
}
