shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D gobo_texture : source_color, repeat_disable;
instance uniform vec4 beam_dynamic_state : source_color = vec4(1.0);
instance uniform float intensity_max = 100.0;
instance uniform float near_radius_ratio = 0.02;
instance uniform float gobo_rotation_deg = 0.0;
instance uniform float gobo_scale = 1.0;
instance uniform bool use_gobo = false;
instance uniform int sample_tier = 8;

varying float proxy_view_depth;
varying float slice_index;

void vertex() {
	float axial = 0.5 - VERTEX.z;
	float radius_ratio = mix(near_radius_ratio, 1.0, axial);
	VERTEX.xy *= radius_ratio * 2.0;
	proxy_view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	slice_index = UV2.y;
}

void fragment() {
	int stride = 12 / max(sample_tier, 1);
	if ((int(slice_index + 0.5) % max(stride, 1)) != 0) { discard; }
	vec2 centered = UV - vec2(0.5);
	float radial = length(centered) * 2.0;
	float edge = 1.0 - smoothstep(0.72, 1.0, radial);
	float longitudinal = pow(clamp(1.0 - UV2.x * 0.65, 0.0, 1.0), 0.8);
	float transmission = 1.0;
	if (use_gobo) {
		float angle = radians(gobo_rotation_deg);
		mat2 rotation = mat2(vec2(cos(angle), -sin(angle)), vec2(sin(angle), cos(angle)));
		vec2 gobo_uv = rotation * centered / max(gobo_scale, 0.05) + vec2(0.5);
		vec4 gobo_sample = texture(gobo_texture, clamp(gobo_uv, vec2(0.0), vec2(1.0)));
		transmission = dot(gobo_sample.rgb, vec3(0.299, 0.587, 0.114)) * gobo_sample.a;
	}
	float raw_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	float scene_depth = -scene_view.z / max(scene_view.w, 0.00001);
	float depth_fade = smoothstep(-0.04, 0.08, scene_depth - proxy_view_depth);
	float intensity = clamp(beam_dynamic_state.a / max(intensity_max, 0.001), 0.0, 1.0);
	ALBEDO = beam_dynamic_state.rgb;
	ALPHA = edge * longitudinal * transmission * intensity * 0.08 * depth_fade;
}
