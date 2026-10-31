shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// Mélange des matières du sol (herbe / terre / pierre) du terrain 3D 2.5D.
//
// - UV   : UV tuilé du maillage (une répétition toutes les 2 cases) pour les
//          textures seamless `game/assets/terrain/*.png` ;
// - UV2  : 0..1 sur toute la carte, pour la texture de splat (une case = un
//          texel ; filtrage linéaire → transitions douces entre matières) ;
// - COLOR: ombrage de pente cuit dans les vertex colors du maillage.
//
// Le shader reste **éclairé** (spatial) : la lumière de la scène module
// l'albédo comme les autres objets 2.5D. `albedo_tint` porte la nuit.

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D splat_tex : source_color, filter_linear, repeat_disable;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float vertex_color_strength : hint_range(0.0, 1.0) = 1.0;
// 1.0 = mélange linéaire (doux) ; > 1 accentue la matière dominante.
uniform float blend_sharpness : hint_range(0.001, 4.0) = 1.0;

void fragment() {
	vec3 weights = texture(splat_tex, UV2).rgb;
	float total = max(weights.r + weights.g + weights.b, 0.0001);
	weights /= total;
	if (abs(blend_sharpness - 1.0) > 0.0001) {
		weights = pow(weights, vec3(blend_sharpness));
		weights /= max(weights.r + weights.g + weights.b, 0.0001);
	}
	vec3 grass = texture(grass_tex, UV).rgb;
	vec3 dirt = texture(dirt_tex, UV).rgb;
	vec3 stone = texture(stone_tex, UV).rgb;
	vec3 albedo = grass * weights.r + dirt * weights.g + stone * weights.b;
	albedo *= mix(vec3(1.0), COLOR.rgb, vertex_color_strength);
	ALBEDO = albedo * albedo_tint.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
