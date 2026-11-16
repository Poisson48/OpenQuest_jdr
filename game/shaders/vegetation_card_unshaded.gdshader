// Végétation en cartouches alpha — variante NON ÉCLAIRÉE (preset `classique`,
// rendu illustration 2.5D). La planche peinte porte déjà la lumière, l'ombre et
// le modelé ; on garde le balancement au vent pour que ça respire.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_cutoff : hint_range(0.05, 0.95) = 0.5;
uniform float card_height = 1.0;
uniform float wind_strength : hint_range(0.0, 0.4) = 0.05;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.6;
uniform float wind_enabled : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	float height_ref = max(card_height, 0.001);
	float weight = clamp(VERTEX.y / height_ref, 0.0, 1.0);
	weight = pow(weight, 1.6) * wind_enabled;
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = TIME * wind_speed + origin.x * 0.9 + origin.z * 1.2;
	float sway = sin(phase) * 0.62 + sin(phase * 0.37 + 1.7) * 0.38;
	VERTEX.x += sway * wind_strength * weight;
	VERTEX.z += cos(phase * 0.83 + 0.6) * wind_strength * 0.55 * weight;
}

void fragment() {
	vec4 texel = texture(albedo_tex, UV);
	ALBEDO = texel.rgb * tint.rgb;
	ALPHA = texel.a * tint.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
