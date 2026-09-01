shader_type fog;

uniform sampler2D gobo_texture : source_color;
uniform bool use_gobo = false;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float density_scale : hint_range(0.0, 10.0) = 0.9;
uniform float emission_strength : hint_range(0.0, 10.0) = 0.55;
uniform vec4 light_color : source_color = vec4(1.0);
uniform float edge_softness : hint_range(0.1, 1.0) = 0.72;
uniform bool invert_gobo = false;
uniform float gobo_scale : hint_range(0.05, 8.0) = 1.0;
uniform float gobo_rotation_deg : hint_range(-360.0, 360.0) = 0.0;
uniform float radial_falloff : hint_range(0.05, 4.0) = 1.25;
uniform float longitudinal_falloff : hint_range(0.05, 4.0) = 1.1;
uniform float near_radius_ratio : hint_range(0.0, 1.0) = 0.0;

vec2 rotate2d(vec2 point, float angle_rad) {
	float c = cos(angle_rad);
	float s = sin(angle_rad);
	return vec2((point.x * c) - (point.y * s), (point.x * s) + (point.y * c));
}

void fog() {
	float depth_t = clamp(1.0 - UVW.z, 0.001, 1.0);
	vec2 transverse = (UVW.xy - vec2(0.5)) * 2.0;
	float radius_at_depth = mix(near_radius_ratio, 1.0, depth_t);
	vec2 projected = transverse / max(radius_at_depth, 0.001);
	projected = rotate2d(projected / max(gobo_scale, 0.05), radians(gobo_rotation_deg));
	vec2 projected_uv = projected * 0.5 + vec2(0.5);
	float projected_bounds = float(projected_uv.x >= 0.0 && projected_uv.x <= 1.0 && projected_uv.y >= 0.0 && projected_uv.y <= 1.0);
	vec4 gobo_sample = texture(gobo_texture, clamp(projected_uv, vec2(0.0), vec2(1.0)));
	float gobo_intensity = use_gobo ? clamp(dot(gobo_sample.rgb, vec3(0.299, 0.587, 0.114)) * gobo_sample.a, 0.0, 1.0) : 1.0;
	if (invert_gobo) {
		gobo_intensity = 1.0 - gobo_intensity;
	}

	float radial = length(projected);
	float radial_mask = pow(clamp(1.0 - radial, 0.0, 1.0), max(radial_falloff, 0.05));
	float edge_start = clamp(edge_softness - 0.1, 0.0, 0.99);
	float edge_end = max(edge_softness, edge_start + 0.001);
	float edge_mask = 1.0 - smoothstep(edge_start, edge_end, radial);
	float longitudinal_mask = pow(depth_t, max(longitudinal_falloff, 0.05));
	float final_mask = radial_mask * edge_mask * longitudinal_mask * projected_bounds;

	// A small density keeps Godot's fog integration active while black albedo prevents unrelated lights from coloring this volume.
	DENSITY = 0.01 * final_mask;
	ALBEDO = vec3(0.0);
	EMISSION = light_color.rgb * emission_strength * intensity * gobo_intensity * final_mask * density_scale;
}
