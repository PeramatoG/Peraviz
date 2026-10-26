shader_type spatial;
// Exact opaque, double-sided default StandardMaterial slice admitted by InstancedLensBatches.
// No shaft/optical formulas are implemented here. Unsupported material options use the reference.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;
varying flat vec4 lens_emission;
void vertex() {
	lens_emission = INSTANCE_CUSTOM;
}
void fragment() {
	ALBEDO = vec3(1.0);
	METALLIC = 0.0;
	ROUGHNESS = 1.0;
	SPECULAR = 0.5;
	// Match StandardMaterial's source_color uniform conversion in linear renderers.
	vec3 color = lens_emission.rgb;
	if (!OUTPUT_IS_SRGB) {
		color = mix(pow((color + vec3(0.055)) / vec3(1.055), vec3(2.4)), color / vec3(12.92), lessThan(color, vec3(0.04045)));
	}
	EMISSION = color * lens_emission.a;
}
