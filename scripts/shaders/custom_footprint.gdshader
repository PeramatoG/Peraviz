// Adapted mechanisms: BluntBSE, Compatibility-Friendly Texture Projection (CC0),
// and Rytelier, Fake light projection (MIT). See custom_footprint.LICENSE.txt.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_front, fog_disabled;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_texture : hint_normal_roughness_texture, repeat_disable, filter_nearest;
uniform sampler2D pattern_texture : source_color, repeat_disable, filter_linear_mipmap;
uniform mat4 world_to_projector;
uniform vec3 projector_origin;
uniform float aperture_tangent = 0.2;
uniform float projection_range = 40.0;
uniform vec4 profile_parameters = vec4(8.0, 0.693147, 0.0, 0.0);
uniform float profile_feather_start = 0.86;
uniform float edge_softness = 0.04;
uniform bool has_artwork = false;
uniform vec2 artwork_aspect = vec2(1.0);
// Updated directly from canonical native physical outputs, independently of shafts.
uniform vec4 emission : source_color = vec4(1.0);
uniform float emission_energy = 0.0;

void fragment() {
	if (emission_energy <= 0.0) { discard; }
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	// Forward+/Vulkan Reverse-Z: background is zero; NDC Z stays in [0,1].
	if (depth <= 0.0) { discard; }
	vec4 view_h = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec3 view_position = view_h.xyz / view_h.w;
	vec3 world_position = (INV_VIEW_MATRIX * vec4(view_position, 1.0)).xyz;
	vec3 local = (world_to_projector * vec4(world_position, 1.0)).xyz;
	float axial_distance = -local.z;
	if (axial_distance <= 0.001 || axial_distance >= projection_range) { discard; }
	// Genuine perspective from the shared optical origin, along emitted -Z.
	vec2 point = local.xy / (axial_distance * aperture_tangent);
	float metric = profile_parameters.z > 0.0
		? max(abs(point.x) / profile_parameters.z, abs(point.y) / profile_parameters.w)
		: length(point);
	if (metric >= 1.0) { discard; }
	float radial = exp(-profile_parameters.y * pow(metric, profile_parameters.x));
	radial *= 1.0 - smoothstep(profile_feather_start, 1.0, metric);
	vec4 artwork = vec4(1.0);
	if (has_artwork) {
		// Godot spotlight reference maps +projector X to +U and +Y to -V.
		vec2 uv = point * vec2(1.0, -1.0) / artwork_aspect * 0.5 + 0.5;
		if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { discard; }
		artwork = texture(pattern_texture, uv);
	}
	radial *= 1.0 - smoothstep(1.0 - max(edge_softness, 0.0001), 1.0, metric);
	// Normals are view-space. Transform the world incident vector as a
	// direction (w=0), never as a translated point or a row-vector inverse.
	vec3 normal_view = normalize(textureLod(normal_texture, SCREEN_UV, 0.0).xyz * 2.0 - 1.0);
	vec3 toward_source_world = projector_origin - world_position;
	vec3 toward_source_view = normalize(mat3(VIEW_MATRIX) * toward_source_world);
	float incidence = max(dot(normal_view, toward_source_view), 0.0);
	float distance_m = length(toward_source_world);
	float fade = 1.0 - smoothstep(projection_range * 0.8, projection_range, distance_m);
	float attenuation = fade / max(distance_m * distance_m, 0.01);
	ALBEDO = artwork.rgb * artwork.a * emission.rgb * emission_energy * radial * incidence * attenuation;
	ALPHA = 1.0;
}
