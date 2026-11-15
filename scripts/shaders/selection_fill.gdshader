shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

// A separate, selection-only instance keeps native lens/material ownership intact.
void vertex() {
	VERTEX += NORMAL * 0.0001;
}

void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	ALBEDO = mix(vec3(1.0, 0.32, 0.0), vec3(1.0, 0.86, 0.12), rim);
	ALPHA = 0.38 + 0.48 * rim;
}
