shader_type spatial;
render_mode blend_mix, unshaded, cull_back, depth_draw_never;

uniform vec4 sphere_data[128];
uniform float sphere_strengths[128];
uniform int sphere_count = 0;
uniform bool debug_mode = false;
uniform float debug_min_strength : hint_range(0.0, 1.0) = 0.35;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float max_strength = 0.0;

	for (int i = 0; i < 128; i++) {
		if (i >= sphere_count) {
			break;
		}

		vec3 sphere_center = sphere_data[i].xyz;
		float sphere_radius = sphere_data[i].w;
		float distance_to_sphere = distance(world_position, sphere_center);

		if (distance_to_sphere <= sphere_radius) {
			max_strength = max(max_strength, sphere_strengths[i]);
		}
	}

	if (debug_mode) {
		max_strength = max(max_strength, debug_min_strength);
	}

	if (max_strength <= 0.01) {
		discard;
	}

	ALBEDO = vec3(max_strength);
	ALPHA = 1.0;
}
