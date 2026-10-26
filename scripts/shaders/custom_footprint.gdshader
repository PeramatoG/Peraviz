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
uniform float edge_softness = 0.10;
uniform bool profile_anchored = false;
uniform bool soft_open_profile = false;
uniform bool has_artwork = false;
uniform vec2 artwork_aspect = vec2(1.0);
// Updated directly from canonical native physical outputs, independently of shafts.
uniform vec4 emission : source_color = vec4(1.0);
uniform float emission_energy = 0.0;

// Camera-dependent work is shared by the volume vertices, never script playback.
varying flat vec4 projector_view_row0;
varying flat vec4 projector_view_row1;
varying flat vec4 projector_view_row2;
varying flat vec3 projector_origin_view;

float radial_power(float radius, float exponent) {
	// Exact common profile exponents avoid a general log/exp power per pixel.
	float squared = radius * radius;
	if (exponent == 2.0) { return squared; }
	if (exponent == 8.0) { float fourth = squared * squared; return fourth * fourth; }
	return pow(radius, exponent);
}

float footprint_feather(float metric) {
	// One terminal feather. Valid Beam/Field anchors stay primary; only the
	// type fallback receives Peraviz's wider Wash / moderate Spot treatment.
	float feather = profile_feather_start;
	if (profile_anchored) {
		feather = max(feather, 1.0 - edge_softness);
	} else {
		float width = edge_softness * (has_artwork ? 1.0 : (soft_open_profile ? 5.0 : 2.5));
		feather = min(feather, 1.0 - clamp(width, 0.0001, 0.9));
	}
	return 1.0 - smoothstep(feather, 1.0, metric);
}

void vertex() {
	mat4 view_to_projector = world_to_projector * INV_VIEW_MATRIX;
	projector_view_row0 = vec4(view_to_projector[0][0], view_to_projector[1][0], view_to_projector[2][0], view_to_projector[3][0]);
	projector_view_row1 = vec4(view_to_projector[0][1], view_to_projector[1][1], view_to_projector[2][1], view_to_projector[3][1]);
	projector_view_row2 = vec4(view_to_projector[0][2], view_to_projector[1][2], view_to_projector[2][2], view_to_projector[3][2]);
	projector_origin_view = (VIEW_MATRIX * vec4(projector_origin, 1.0)).xyz;
}

vec3 projector_position(vec3 view_position) {
	vec4 point = vec4(view_position, 1.0);
	return vec3(dot(projector_view_row0, point), dot(projector_view_row1, point), dot(projector_view_row2, point));
}

vec3 toward_projector(vec3 view_position) {
	return projector_origin_view - view_position;
}

void fragment() {
	if (emission_energy <= 0.0) { discard; }
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	// Forward+/Vulkan Reverse-Z: background is zero; NDC Z stays in [0,1].
	if (depth <= 0.0) { discard; }
	vec4 view_h = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec3 view_position = view_h.xyz / view_h.w;
	vec3 local = projector_position(view_position);
	float axial_distance = -local.z;
	if (axial_distance <= 0.001 || axial_distance >= projection_range) { discard; }
	// Genuine perspective from the shared optical origin, along emitted -Z.
	vec2 point = local.xy / (axial_distance * aperture_tangent);
	float metric = profile_parameters.z > 0.0
		? max(abs(point.x) / profile_parameters.z, abs(point.y) / profile_parameters.w)
		: length(point);
	if (metric >= 1.0) { discard; }
	// The existing Euclidean fade is exactly zero outside this sphere. Reject
	// before either normal or artwork sampling, including wide-cone end corners.
	vec3 toward_source_view = toward_projector(view_position);
	float distance_squared = dot(toward_source_view, toward_source_view);
	if (distance_squared >= projection_range * projection_range) { discard; }
	float inverse_distance = inversesqrt(max(distance_squared, 0.000001));
	vec4 artwork = vec4(1.0);
	if (has_artwork) {
		// Godot spotlight reference maps +projector X to +U and +Y to -V.
		vec2 uv = point * vec2(1.0, -1.0) / artwork_aspect * 0.5 + 0.5;
		if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { discard; }
		artwork = texture(pattern_texture, uv);
		if (artwork.a == 0.0 || all(equal(artwork.rgb, vec3(0.0)))) { discard; }
	}
	// Normals and both positions are in view space. Their difference is a
	// direction, with no translation or row-vector inverse correction.
	vec3 normal_view = normalize(textureLod(normal_texture, SCREEN_UV, 0.0).xyz * 2.0 - 1.0);
	float incidence = max(dot(normal_view, toward_source_view * inverse_distance), 0.0);
	if (incidence == 0.0) { discard; }
	float radial = exp(-profile_parameters.y * radial_power(metric, profile_parameters.x)) * footprint_feather(metric);
	float distance_m = distance_squared * inverse_distance;
	float fade = 1.0 - smoothstep(projection_range * 0.8, projection_range, distance_m);
	float attenuation = fade / max(distance_squared, 0.01);
	ALBEDO = artwork.rgb * artwork.a * emission.rgb * emission_energy * radial * incidence * attenuation;
	ALPHA = 1.0;
}
