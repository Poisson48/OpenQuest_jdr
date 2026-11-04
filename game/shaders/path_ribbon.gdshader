shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, shadows_disabled;

// Chemin 2.5D : ruban conforme au terrain, UV le long du tracé, bords alpha
// irréguliers portés par la couleur de sommet (COLOR.a).
//
// blend_mix + depth_draw_opaque : le centre opaque écrit le tampon de
// profondeur (le terrain dessous ne transparaît plus), tandis que les bords
// semi-transparents se fondent proprement dans l'herbe sans être triés
// derrière le sol.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float tex_scale : hint_range(0.25, 8.0) = 1.0;

void fragment() {
	vec2 uv = UV * tex_scale;
	vec3 a = texture(albedo_tex, uv).rgb;
	// Deuxième lecture tournée/décalée pour casser le carrelage, sans flou :
	// le poids dominant (0.62) garde le détail de la texture.
	vec2 b = vec2(uv.x * 0.82 - uv.y * 0.57, uv.x * 0.57 + uv.y * 0.82) * 1.17 + vec2(0.37, 0.11);
	vec3 c = texture(albedo_tex, b).rgb;
	vec3 base = (a * 0.62 + c * 0.38) * tint;
	ALBEDO = base * COLOR.rgb;
	ROUGHNESS = 0.94;
	SPECULAR = 0.0;
	ALPHA = COLOR.a;
}
