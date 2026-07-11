shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

// ---- 深度/法线纹理 ----
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;

// ---- 多球显影/残影系统 ----
uniform vec3 sphere_positions[64];
uniform float sphere_radii[64];
uniform float sphere_strengths[64];
uniform int sphere_count;

// ---- 调试模式 ----
uniform float debug_mode = 0.0;               // 1.0 表示显示全局残影
uniform float debug_afterglow_strength = 0.35;

// ---- 摄像机参数 ----
uniform float camera_near = 0.05;
uniform float camera_far = 100.0;
uniform mat4 inv_view_matrix;

// ---- 阈值与外观 ----
uniform float depth_threshold = 0.003;
uniform float normal_threshold = 0.25;
uniform float surface_alpha = 0.16;
uniform vec4 edge_color : source_color = vec4(0.4, 0.75, 1.0, 1.0);

// ---- 顶点 → 片段 传递 ----
varying vec3 view_ray;


// ---- 顶点着色器：传视线方向 ----

void vertex() {
	view_ray = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


// ---- 深度线性化（Godot 4 reverse-z） ----

float linearize_depth(float d) {
	float ndc = d * 2.0 - 1.0;
	float denominator = (camera_far - camera_near) * ndc + camera_far + camera_near;
	return (2.0 * camera_near * camera_far) / denominator;
}


// ---- 世界坐标重建 ----

vec3 reconstruct_world_pos(vec2 screen_uv, float d) {
	if (d >= 1.0) return vec3(0.0);

	float lin_depth = linearize_depth(d);
	vec3 ray_dir = normalize(view_ray);
	float dist = lin_depth / abs(ray_dir.z);
	vec3 view_pos = ray_dir * dist;

	vec4 world = inv_view_matrix * vec4(view_pos, 1.0);
	return world.xyz;
}


// ---- 像素强度：取所有包含该像素世界坐标的球的最大强度 ----

float get_pixel_strength(vec2 uv, float d) {
	if (d >= 1.0) return 0.0;

	vec3 wp = reconstruct_world_pos(uv, d);
	float max_strength = 0.0;

	for (int i = 0; i < 64; i++) {
		if (i >= sphere_count) break;

		float dist = distance(wp, sphere_positions[i]);
		if (dist <= sphere_radii[i]) {
			max_strength = max(max_strength, sphere_strengths[i]);
		}
	}

	// ★ 调试模式：所有几何体至少显示 debug_afterglow_strength 的残影强度
	if (debug_mode > 0.5) {
		max_strength = max(max_strength, debug_afterglow_strength);
	}

	return max_strength;
}


// ---- 边缘检测 ----

float get_depth_edge(vec2 uv, vec2 texel) {
	float dc = texture(depth_tex, uv).r;
	float d0 = texture(depth_tex, uv + vec2( texel.x,  0.0)).r;
	float d1 = texture(depth_tex, uv + vec2(-texel.x,  0.0)).r;
	float d2 = texture(depth_tex, uv + vec2( 0.0,  texel.y)).r;
	float d3 = texture(depth_tex, uv + vec2( 0.0, -texel.y)).r;

	float diff = max(
		max(abs(dc - d0), abs(dc - d1)),
		max(abs(dc - d2), abs(dc - d3))
	);
	return smoothstep(depth_threshold, depth_threshold + 0.002, diff);
}

float get_normal_edge(vec2 uv, vec2 texel) {
	vec3 nc = normalize(texture(normal_tex, uv).xyz * 2.0 - 1.0);
	vec3 n0 = normalize(texture(normal_tex, uv + vec2( texel.x,  0.0)).xyz * 2.0 - 1.0);
	vec3 n1 = normalize(texture(normal_tex, uv + vec2(-texel.x,  0.0)).xyz * 2.0 - 1.0);
	vec3 n2 = normalize(texture(normal_tex, uv + vec2( 0.0,  texel.y)).xyz * 2.0 - 1.0);
	vec3 n3 = normalize(texture(normal_tex, uv + vec2( 0.0, -texel.y)).xyz * 2.0 - 1.0);

	float d0 = 1.0 - abs(dot(nc, n0));
	float d1 = 1.0 - abs(dot(nc, n1));
	float d2 = 1.0 - abs(dot(nc, n2));
	float d3 = 1.0 - abs(dot(nc, n3));
	float diff = max(max(d0, d1), max(d2, d3));

	return smoothstep(normal_threshold, normal_threshold + 0.08, diff);
}


// ---- 主函数 ----

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 texel = 2.0 / vec2(VIEWPORT_SIZE);

	float dc = texture(depth_tex, uv).r;
	float d0 = texture(depth_tex, uv + vec2( texel.x,  0.0)).r;
	float d1 = texture(depth_tex, uv + vec2(-texel.x,  0.0)).r;
	float d2 = texture(depth_tex, uv + vec2( 0.0,  texel.y)).r;
	float d3 = texture(depth_tex, uv + vec2( 0.0, -texel.y)).r;

	// 中心像素必须在某个球内
	float center_strength = get_pixel_strength(uv, dc);
	if (center_strength <= 0.01) { discard; }

	// 四个邻居也必须在某个球内，否则说明中心在球体边界，丢弃（避免伪影）
	float s0 = get_pixel_strength(uv + vec2( texel.x,  0.0), d0);
	float s1 = get_pixel_strength(uv + vec2(-texel.x,  0.0), d1);
	float s2 = get_pixel_strength(uv + vec2( 0.0,  texel.y), d2);
	float s3 = get_pixel_strength(uv + vec2( 0.0, -texel.y), d3);
	if (s0 <= 0.01 || s1 <= 0.01 || s2 <= 0.01 || s3 <= 0.01) { discard; }

	// 边缘检测
	float depth_edge = get_depth_edge(uv, texel);
	float normal_edge = get_normal_edge(uv, texel);
	float edge = max(depth_edge, normal_edge);
	float visibility = max(edge, surface_alpha);

	ALBEDO = edge_color.rgb;
	ALPHA = visibility * edge_color.a * center_strength;
}
