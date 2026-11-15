shader_type spatial;
render_mode unshaded, blend_mix, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

// Expand the inverted hull in screen pixels, independent of scene/model scale.
void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 view_normal = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 projected_normal = (PROJECTION_MATRIX * vec4(view_normal, 0.0)).xy;
	vec2 direction = projected_normal / max(length(projected_normal), 0.0001);
	clip.xy += direction * vec2(2.0) / VIEWPORT_SIZE * clip.w * 2.0;
	POSITION = clip;
}

void fragment() {
	ALBEDO = vec3(1.0, 0.65, 0.0);
	ALPHA = 0.95;
}
