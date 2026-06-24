shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

// ---- 深度/法线纹理 ----
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;

// ---- 触摸命中点 ----
uniform vec3 touch_world_pos = vec3(0.0);
uniform float world_radius = 2.0;

// ---- 摄像机参数（线性化深度用） ----
uniform float camera_near = 0.05;
uniform float camera_far = 100.0;

// 视口空间 → 世界空间（Godot 4.0-4.2 没有 INV_VIEW_MATRIX 内置变量，从 GDScript 传）
uniform mat4 inv_view_matrix;

// ---- 阈值与外观 ----
uniform float depth_threshold = 0.003;
uniform float normal_threshold = 0.25;
uniform vec4 edge_color : source_color = vec4(0.4, 0.75, 1.0, 1.0);
uniform float alpha_multiplier = 0.0;

// ---- 顶点 → 片段 传递 ----
varying vec3 view_ray;


// ══════════════════════════════════════════════
//  顶点着色器：将相机局部空间的顶点方向传出
// ══════════════════════════════════════════════

void vertex() {
	// Quad 挂在摄像机下，MODELVIEW_MATRIX = VIEW * MODEL
	// 即：quad 本地坐标 → 视口空间（view space）
	// 摄像机在视口空间原点 (0,0,0)，因此 view_ray 即从摄像机
	// 穿过该顶点的方向射线
	view_ray = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


// ══════════════════════════════════════════════
//  深度线性化（Godot 4 reverse-z 专用）
// ══════════════════════════════════════════════

float linearize_depth(float d) {
	// depth_texture [0,1]:  0 = 远平面, 1 = 近平面 (reverse-z)
	// NDC z = d * 2 - 1  ∈ [1, -1] (near=1, far=-1)
	float ndc = d * 2.0 - 1.0;

	// 正确公式（已验证）：
	// linear_depth = 2*near*far / ((far-near)*ndc + (far+near))
	float denominator = (camera_far - camera_near) * ndc + camera_far + camera_near;
	return (2.0 * camera_near * camera_far) / denominator;
}


// ══════════════════════════════════════════════
//  世界坐标重建（基于视线方向，不依赖 inv_proj）
// ══════════════════════════════════════════════

vec3 reconstruct_world_pos(vec2 screen_uv, float d) {
	if (d >= 1.0) return vec3(0.0);

	// 1. 线性深度（沿摄像机前向的距离，单位：米）
	float lin_depth = linearize_depth(d);

	// 2. 视线方向（已归一化）
	vec3 ray_dir = normalize(view_ray);

	// 3. 沿射线到达 lin_depth 深度所需的距离
	//   ray_dir.z = 射线在 -Z（摄像机前向）上的分量
	//   沿射线走 dist 米，在 -Z 方向上前进 lin_depth 米
	float dist = lin_depth / abs(ray_dir.z);

	// 4. 视口空间坐标
	vec3 view_pos = ray_dir * dist;

	// 5. 视口空间 → 世界空间（使用 GDScript 传入的逆观察矩阵）
	vec4 world = inv_view_matrix * vec4(view_pos, 1.0);
	return world.xyz;
}


// ══════════════════════════════════════════════
//  区域判断
// ══════════════════════════════════════════════

bool is_in_touch_region(vec2 uv, float d) {
	if (d >= 1.0) return false;
	vec3 wp = reconstruct_world_pos(uv, d);
	return length(wp - touch_world_pos) <= world_radius;
}


// ══════════════════════════════════════════════
//  边缘检测
// ══════════════════════════════════════════════

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


// ══════════════════════════════════════════════
//  主函数
// ══════════════════════════════════════════════

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 texel = 2.0 / vec2(VIEWPORT_SIZE);

	float dc = texture(depth_tex, uv).r;
	float d0 = texture(depth_tex, uv + vec2( texel.x,  0.0)).r;
	float d1 = texture(depth_tex, uv + vec2(-texel.x,  0.0)).r;
	float d2 = texture(depth_tex, uv + vec2( 0.0,  texel.y)).r;
	float d3 = texture(depth_tex, uv + vec2( 0.0, -texel.y)).r;

	// 中心 + 4 邻居必须在球内（杜绝球体边界伪影）
	if (!is_in_touch_region(uv, dc)) { discard; }
	if (!is_in_touch_region(uv + vec2( texel.x,  0.0), d0)) { discard; }
	if (!is_in_touch_region(uv + vec2(-texel.x,  0.0), d1)) { discard; }
	if (!is_in_touch_region(uv + vec2( 0.0,  texel.y), d2)) { discard; }
	if (!is_in_touch_region(uv + vec2( 0.0, -texel.y), d3)) { discard; }

	float depth_edge = get_depth_edge(uv, texel);
	float normal_edge = get_normal_edge(uv, texel);
	float edge = max(depth_edge, normal_edge);

	// 径向消退
	vec3 wp = reconstruct_world_pos(uv, dc);
	float dist = length(wp - touch_world_pos);
	float radial_falloff = 1.0 - smoothstep(world_radius * 0.3, world_radius, dist);

	ALBEDO = edge_color.rgb;
	ALPHA = edge * edge_color.a * alpha_multiplier * radial_falloff;
}
