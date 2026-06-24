shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D mask_texture : filter_linear;
uniform vec4 background_color : source_color = vec4(0.039216, 0.039216, 0.078431, 1.0);
uniform float blur_radius : hint_range(0.0, 0.02) = 0.004;
uniform bool debug_mode = false;

void fragment() {
	vec4 original = texture(screen_texture, SCREEN_UV);
	float intensity = texture(mask_texture, SCREEN_UV).r;
	if (debug_mode) {
		vec4 debug_tint = vec4(1.0, 0.82, 0.24, 1.0);
		float debug_mask = clamp(intensity * 1.5, 0.0, 1.0);
		COLOR = mix(original, debug_tint, debug_mask);
	} else {
		COLOR = mix(background_color, original, intensity);
	}
}
