shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

// Web-compatible touch reveal shader.
// It avoids normal_roughness_texture, which is unavailable in the Web Compatibility renderer.

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

uniform vec3 sphere_positions[64];
uniform float sphere_radii[64];
uniform float sphere_strengths[64];
uniform vec4 sphere_colors[64];
uniform int sphere_count;

uniform float debug_mode = 0.0;
uniform float debug_afterglow_strength = 0.35;

uniform float camera_near = 0.05;
uniform float camera_far = 100.0;
uniform mat4 inv_view_matrix;
uniform vec2 viewport_size = vec2(1280.0, 720.0);

uniform float depth_threshold = 0.003;
uniform float surface_alpha = 0.16;
uniform vec4 edge_color : source_color = vec4(0.4, 0.75, 1.0, 1.0);

varying vec3 view_ray;


void vertex() {
	view_ray = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


float linearize_depth(float d) {
	float ndc = d * 2.0 - 1.0;
	float denominator = (camera_far - camera_near) * ndc + camera_far + camera_near;
	return (2.0 * camera_near * camera_far) / denominator;
}


vec3 reconstruct_world_pos(float d) {
	float lin_depth = linearize_depth(d);
	vec3 ray_dir = normalize(view_ray);
	float dist = lin_depth / abs(ray_dir.z);
	vec3 view_pos = ray_dir * dist;

	vec4 world = inv_view_matrix * vec4(view_pos, 1.0);
	return world.xyz;
}


vec4 get_pixel_feedback(vec2 uv, float d) {
	if (d >= 1.0) {
		return vec4(edge_color.rgb, 0.0);
	}

	if (debug_mode > 0.5) {
		return vec4(edge_color.rgb, debug_afterglow_strength);
	}

	float max_strength = 0.0;
	vec3 best_color = edge_color.rgb;
	vec3 world_pos = reconstruct_world_pos(d);

	for (int i = 0; i < 64; i++) {
		if (i >= sphere_count) {
			break;
		}

		float radius = sphere_radii[i];
		if (radius <= 0.0) {
			continue;
		}

		float dist = distance(world_pos, sphere_positions[i]);
		if (dist <= radius) {
			float falloff = 1.0 - smoothstep(radius * 0.88, radius, dist);
			float strength = sphere_strengths[i] * falloff;
			if (strength >= max_strength) {
				max_strength = strength;
				best_color = sphere_colors[i].rgb;
			}
		}
	}

	return vec4(best_color, max_strength);
}


float get_depth_edge_scale(vec2 uv, vec2 texel, float scale) {
	float dc = texture(depth_tex, uv).r;
	if (dc >= 1.0) {
		return 0.0;
	}

	vec2 offset = texel * scale;
	float lc = linearize_depth(dc);
	float d0 = linearize_depth(texture(depth_tex, uv + vec2( offset.x,  0.0)).r);
	float d1 = linearize_depth(texture(depth_tex, uv + vec2(-offset.x,  0.0)).r);
	float d2 = linearize_depth(texture(depth_tex, uv + vec2( 0.0,  offset.y)).r);
	float d3 = linearize_depth(texture(depth_tex, uv + vec2( 0.0, -offset.y)).r);

	float raw_diff = max(
		max(abs(lc - d0), abs(lc - d1)),
		max(abs(lc - d2), abs(lc - d3))
	);

	float threshold = depth_threshold * scale;
	return smoothstep(threshold, threshold + depth_threshold * scale * 2.0, raw_diff);
}


float get_depth_edge(vec2 uv, vec2 texel) {
	float edge_small = get_depth_edge_scale(uv, texel, 1.0);
	float edge_medium = get_depth_edge_scale(uv, texel, 2.0) * 0.75;
	float edge_large = get_depth_edge_scale(uv, texel, 4.0) * 0.45;
	return clamp(max(max(edge_small, edge_medium), edge_large), 0.0, 1.0);
}


void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 texel = 1.0 / viewport_size;

	float dc = texture(depth_tex, uv).r;
	vec4 center_feedback = get_pixel_feedback(uv, dc);
	float center_strength = center_feedback.a;
	if (center_strength <= 0.01) {
		discard;
	}

	float edge = get_depth_edge(uv, texel);
	float fill_alpha = surface_alpha * center_strength * edge_color.a;
	float edge_alpha = edge * 0.92 * center_strength * edge_color.a;
	float alpha = max(fill_alpha, edge_alpha);

	ALBEDO = center_feedback.rgb;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
