shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

instance uniform vec4 beam_dynamic_state : source_color = vec4(1.0, 0.95, 0.85, 0.0);
instance uniform float intensity_max = 100.0;
instance uniform float cone_height = 75.0;
instance uniform float gobo_projection_radius = 1.0;
instance uniform float topology_near_radius = 0.03;
instance uniform float topology_far_radius = 1.0;
instance uniform bool use_normalized_gobo_topology = false;
instance uniform float longitudinal_falloff = 1.0;
instance uniform float haze_density = 0.22;
// x = resolved exponent, y = coefficient, zw = rectangle half extents (or zero).
instance uniform vec4 profile_parameters = vec4(8.0, 2.606038, 0.0, 0.0);

uniform sampler2D gobo_coverage : filter_linear, repeat_disable;
uniform sampler2D gobo_mask : filter_nearest, repeat_disable;
uniform bool has_gobo_energy = false;
instance uniform float gobo_transmission = 1.0;
instance uniform float profile_feather_start = 0.86;

varying vec3 optical_position;
varying flat vec3 optical_camera;
varying flat float intensity_response;
varying flat float inside_volume;

void vertex() {
	float axial = use_normalized_gobo_topology ? clamp(0.5 - VERTEX.y, 0.0, 1.0) : clamp(0.5 - VERTEX.y / cone_height, 0.0, 1.0);
	if (use_normalized_gobo_topology) {
		VERTEX.xz *= mix(topology_near_radius, topology_far_radius, axial);
	}
	// Cached topology Y is normalized; all attenuation coordinates are metres.
	optical_position = vec3(VERTEX.x, axial * cone_height, VERTEX.z);
	vec3 camera_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	float camera_axial = use_normalized_gobo_topology ? (0.5 - camera_local.y) * cone_height : 0.5 * cone_height - camera_local.y;
	optical_camera = vec3(camera_local.x, camera_axial, camera_local.z);
	float camera_radius = mix(topology_near_radius, topology_far_radius, camera_axial / cone_height);
	vec2 camera_point = optical_camera.xz / max(camera_radius, 0.0001);
	float camera_metric = length(camera_point);
	if (profile_parameters.z > 0.0) {
		vec2 rectangle_point = abs(camera_point / profile_parameters.zw);
		camera_metric = max(rectangle_point.x, rectangle_point.y);
	}
	inside_volume = camera_axial >= 0.0 && camera_axial <= cone_height && camera_metric < 1.0 ? 1.0 : 0.0;
	if (has_gobo_energy && inside_volume > 0.5) {
		vec4 mask = textureLod(gobo_mask, camera_point * 0.5 + 0.5, 0.0);
		inside_volume = dot(mask.rgb, vec3(0.299, 0.587, 0.114)) * mask.a >= 0.5 ? 1.0 : 0.0;
	}
	float intensity = max(beam_dynamic_state.a, 0.0);
	intensity_response = intensity / 20.0;
}

void fragment() {
	// One analytic closest-axis sample estimates the smooth column envelope of
	// the shell. Sampling density only at shell vertices would give r=1 everywhere.
	// No geometric normals, shells, slices, ray marching or per-pixel loops.
	vec3 ray = optical_position - optical_camera;
	float spread = (topology_far_radius - topology_near_radius) / cone_height;
	float camera_radius = topology_near_radius + spread * optical_camera.y;
	// Godot's clockwise front faces are the inward-facing exit walls. Outside
	// cameras use entry walls so the cap-free terminal opening cannot occlude
	// the shaft; inside cameras use exit walls. Never accumulate both orientations.
	if (FRONT_FACING != (inside_volume > 0.5)) { discard; }
	float topology_gain = 1.0;
	if (has_gobo_energy) {
		vec2 direction = ray.xz * camera_radius - optical_camera.xz * spread * ray.y;
		vec2 normal = vec2(-direction.y, direction.x) / max(length(direction), 0.000001);
		float angle = atan(normal.y, normal.x);
		if (angle < 0.0) { normal = -normal; angle += 3.14159265; }
		float fragment_radius = topology_near_radius + spread * optical_position.y;
		float offset = dot(normal, optical_position.xz / max(fragment_radius, 0.0001));
		topology_gain = texture(gobo_coverage, vec2(offset / 3.0 + 0.5, angle / 3.14159265)).r;
	}
	float transverse_sq = dot(ray.xz, ray.xz);
	float t = max(-dot(optical_camera.xz, ray.xz) / max(transverse_sq, 0.000001), 0.0);
	if (abs(ray.y) > 0.0001) {
		float t0 = -optical_camera.y / ray.y;
		float t1 = (cone_height - optical_camera.y) / ray.y;
		t = max(clamp(t, min(t0, t1), max(t0, t1)), 0.0);
	}
	vec3 sample_pos = optical_camera + ray * t;
	float axial = clamp(sample_pos.y, 0.0, cone_height);
	float section_radius = mix(topology_near_radius, topology_far_radius, axial / cone_height);
	if (!use_normalized_gobo_topology) {
		section_radius = mix(topology_near_radius, gobo_projection_radius, axial / cone_height);
	}
	vec2 point = sample_pos.xz / max(section_radius, 0.0001);
	float radius = length(point);
	if (profile_parameters.z > 0.0) {
		point /= profile_parameters.zw;
		radius = max(abs(point.x), abs(point.y));
	}
	float radial = exp2(-1.44269504 * profile_parameters.y * pow(clamp(radius, 0.0, 1.0), profile_parameters.x));
	radial *= 1.0 - smoothstep(profile_feather_start, 1.0, radius);
	float d = axial;
	float strength = max(longitudinal_falloff, 0.0);
	float decay = exp2(-0.07934823 * strength * d) / (1.0 + 0.015 * strength * d * d);
	float tail = (1.0 - smoothstep(0.72, 0.98, d / cone_height)) * (1.0 - smoothstep(0.72, 0.98, optical_position.y / cone_height));
	if (!has_gobo_energy) { topology_gain = sqrt(max(1.0 - radius * radius, 0.0)); }
	float density = radial * decay * tail * max(haze_density, 0.0) * intensity_response * 0.8 * gobo_transmission * topology_gain;
	// Additive blending multiplies emission by alpha; split density equally so
	// the displayed radial envelope retains the shared photometric anchors.
	float response = sqrt(max(density, 0.0));
	ALBEDO = beam_dynamic_state.rgb * response;
	EMISSION = ALBEDO;
	ALPHA = clamp(response, 0.0, 1.0);
}
