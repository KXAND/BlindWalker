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

// 与主球数组同序的固定标记；固定球内部亮度按 PINNED_BRIGHTNESS_BOOST 提升。
uniform float sphere_pinned[64];

// 固定环专用数组：按 memory_id 去重（活动球优先），每个记忆点只画一个环。
uniform int pinned_sphere_count = 0;
uniform vec3 pinned_sphere_positions[64];
uniform float pinned_sphere_radii[64];
uniform float pinned_sphere_strengths[64];
uniform vec4 ring_color : source_color = vec4(1.0, 0.75, 0.25, 1.0);
uniform float ring_width = 0.10;

uniform float debug_mode = 0.0;
uniform float debug_afterglow_strength = 0.35;

uniform float camera_near = 0.05;
uniform float camera_far = 100.0;
uniform mat4 inv_view_matrix;
uniform vec2 viewport_size = vec2(1280.0, 720.0);

uniform float depth_threshold = 0.003;
uniform float surface_alpha = 0.16;
uniform vec4 edge_color : source_color = vec4(0.4, 0.75, 1.0, 1.0);

const float PINNED_BRIGHTNESS_BOOST = 1.2;

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


vec4 get_pixel_feedback(vec3 world_pos) {
	float max_strength = 0.0;
	vec3 best_color = edge_color.rgb;

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
			if (sphere_pinned[i] > 0.5) {
				// 固定球内部提亮约 20%，但保留原材质颜色。
				strength *= PINNED_BRIGHTNESS_BOOST;
			}
			if (strength >= max_strength) {
				max_strength = strength;
				best_color = sphere_colors[i].rgb;
			}
		}
	}

	return vec4(best_color, max_strength);
}


/// 固定环：只在显影球覆盖的真实表面像素上，沿外缘约 ring_width 宽度绘制暖金色环。
/// 独立于普通显影计算，较新的临时显影不会覆盖它。
vec4 get_pinned_ring_feedback(vec3 world_pos) {
	float max_ring_strength = 0.0;

	for (int i = 0; i < 64; i++) {
		if (i >= pinned_sphere_count) {
			break;
		}

		float radius = pinned_sphere_radii[i];
		if (radius <= 0.0) {
			continue;
		}

		float dist = distance(world_pos, pinned_sphere_positions[i]);
		if (dist <= radius) {
			float falloff = 1.0 - smoothstep(radius * 0.88, radius, dist);
			float ring_mask = smoothstep(radius * (1.0 - ring_width), radius, dist);
			float strength = pinned_sphere_strengths[i] * falloff * ring_mask;
			max_ring_strength = max(max_ring_strength, strength);
		}
	}

	return vec4(ring_color.rgb, max_ring_strength);
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
	if (dc >= 1.0) {
		discard;
	}

	vec3 world_pos = reconstruct_world_pos(dc);
	vec4 ring_feedback = get_pinned_ring_feedback(world_pos);

	vec3 final_color;
	float alpha;

	if (debug_mode > 0.5) {
		// 调试模式保留固定环，便于识别哪些记忆点已被保留。
		final_color = edge_color.rgb;
		alpha = debug_afterglow_strength;
		if (ring_feedback.a > 0.01) {
			final_color = mix(final_color, ring_feedback.rgb, clamp(ring_feedback.a, 0.0, 1.0));
			alpha = max(alpha, ring_feedback.a);
		}
	} else {
		vec4 center_feedback = get_pixel_feedback(world_pos);
		float center_strength = center_feedback.a;
		if (center_strength <= 0.01) {
			discard;
		}

		float edge = get_depth_edge(uv, texel);
		float fill_alpha = surface_alpha * center_strength * edge_color.a;
		float edge_alpha = edge * 0.92 * center_strength * edge_color.a;
		alpha = max(fill_alpha, edge_alpha);

		final_color = center_feedback.rgb;
		if (ring_feedback.a > 0.01) {
			// 固定环独立合成：环色覆盖显影色，alpha 不被普通显影压低。
			final_color = mix(final_color, ring_feedback.rgb, clamp(ring_feedback.a, 0.0, 1.0));
			alpha = max(alpha, ring_feedback.a * edge_color.a);
		}
	}

	ALBEDO = final_color;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
