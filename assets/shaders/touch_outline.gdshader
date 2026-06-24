shader_type spatial;
render_mode cull_front, unshaded, blend_mix;

// 轮廓颜色与宽度，alpha 由脚本动态控制实现淡入淡出
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float outline_width : hint_range(0.0, 0.08) = 0.02;

void vertex() {
	// 沿法线方向扩展顶点，形成外轮廓壳
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
