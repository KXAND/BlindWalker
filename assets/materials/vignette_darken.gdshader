shader_type canvas_item;

uniform float darkness : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = UV;
	vec2 center_vec = uv - vec2(0.5, 0.5);

	// 椭圆距离，补偿 16:9 宽高比，使晕影在屏幕上呈正圆
	float aspect = 16.0 / 9.0;
	vec2 ellipse = center_vec * vec2(aspect, 1.0);
	float dist = length(ellipse);

	// darkness 从 0→1，内部可见半径从 0.7→-0.05
	// darkness=0: inner=0.7（只遮四个角，大部分画面可见）
	// darkness=1: inner=-0.05（全屏黑）
	float inner_radius = mix(0.7, -0.05, darkness);
	float outer_radius = inner_radius + 0.05;

	// direct smoothstep: 中心透明(0)，边缘不透明(1)
	float vignette = smoothstep(inner_radius, outer_radius, dist);
	COLOR = vec4(0.0, 0.0, 0.0, vignette);
}
