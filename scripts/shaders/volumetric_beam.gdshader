shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

instance uniform vec4 beam_dynamic_state : source_color = vec4(1.0, 0.95, 0.85, 0.0);
instance uniform float intensity_max = 100.0;
instance uniform float cone_height = 75.0;
instance uniform float gobo_projection_radius = 1.0;
instance uniform float topology_near_radius = 0.03;
instance uniform float topology_far_radius = 1.0;
instance uniform bool use_normalized_gobo_topology = false;
instance uniform float longitudinal_falloff = 1.1;
instance uniform float haze_density = 0.22;
// x = resolved exponent, y = coefficient, zw = rectangle half extents (or zero).
instance uniform vec4 profile_parameters = vec4(8.0, 6.2146081, 0.0, 0.0);

varying vec3 optical_position;
varying flat vec3 optical_camera;
varying flat float intensity_response;

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
	float intensity = max(beam_dynamic_state.a, 0.0);
	float overdrive = clamp((intensity - 20.0) / max(intensity_max - 20.0, 0.001), 0.0, 1.0);
	intensity_response = intensity / 20.0 * mix(1.0, 4.0, overdrive);
}

void fragment() {
	// One analytic closest-axis sample estimates the smooth column envelope of
	// the shell. Sampling density only at shell vertices would give r=1 everywhere.
	// No geometric normals, shells, slices, ray marching or per-pixel loops.
	vec3 ray = optical_position - optical_camera;
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
	radial *= 1.0 - smoothstep(0.96, 1.0, radius);
	float d = optical_position.y;
	float strength = max(longitudinal_falloff, 0.0);
	float decay = exp2(-0.02596851 * strength * d) / (1.0 + 0.002 * strength * d * d);
	float tail = 1.0 - smoothstep(0.72, 0.98, d / cone_height);
	float density = radial * decay * tail * max(haze_density, 0.0) * intensity_response;
	// Additive blending multiplies emission by alpha; split density equally so
	// the displayed radial envelope retains the shared photometric anchors.
	float response = sqrt(max(density, 0.0));
	ALBEDO = beam_dynamic_state.rgb * response * 2.0;
	EMISSION = ALBEDO;
	ALPHA = clamp(response, 0.0, 1.0);
}
