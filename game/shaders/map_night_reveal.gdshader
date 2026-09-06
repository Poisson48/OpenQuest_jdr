shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

// Mode nuit façon brouillard : base = texture nuit, masque lumière = révélation jour.
uniform sampler2D day_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D night_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D light_mask : hint_default_black, filter_linear, repeat_disable;
uniform float night_ambient : hint_range(0.05, 1.0) = 0.22;
uniform float reveal_gamma : hint_range(0.5, 2.0) = 1.15;

void fragment() {
	vec3 day = texture(day_tex, UV).rgb;
	vec3 night = texture(night_tex, UV).rgb * night_ambient;
	float mask = texture(light_mask, UV).r;
	mask = clamp(pow(mask, reveal_gamma), 0.0, 1.0);
	ALBEDO = mix(night, day, mask);
}
