shader_type spatial;
render_mode specular_disabled;

uniform vec4 ground_color : source_color = vec4(0.4, 0.4, 0.4, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.3, 0.3, 0.3, 1.0);
uniform float horizon_energy = 1.0;
uniform bool horizon_enabled = true;
uniform float horizon_begin = 600.0;
uniform float horizon_end = 1800.0;
uniform vec2 stage_min = vec2(-100.0);
uniform vec2 stage_max = vec2(100.0);
varying vec3 ground_world_position;

void vertex() {
	ground_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float blend = horizon_enabled ? smoothstep(horizon_begin, horizon_end,
		length(ground_world_position - CAMERA_POSITION_WORLD)) : 0.0;
	vec2 outside_stage = max(max(stage_min - ground_world_position.xz,
		ground_world_position.xz - stage_max), vec2(0.0));
	// Protect the entire imported show and its margin, even when viewed from far away.
	blend *= smoothstep(0.0, 200.0, length(outside_stage));
	// Opaque lit receiver near the stage; converge to the sky's linear radiance far away.
	// No ALPHA, discard, vertex displacement, depth override or normal override.
	ALBEDO = ground_color.rgb * (1.0 - blend);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	EMISSION = horizon_color.rgb * horizon_energy * blend;
}
