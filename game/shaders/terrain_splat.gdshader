shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// Mélange des cinq matières du sol (herbe / terre / pierre / neige / sable) du
// terrain 3D 2.5D.
//
// - UV    : UV tuilé du maillage (une répétition toutes les 2 cases) pour les
//           textures seamless `game/assets/terrain/*.png` ;
// - UV2   : 0..1 sur toute la carte, pour les textures de splat (une case = un
//           texel ; filtrage linéaire → transitions douces entre matières) ;
// - COLOR : ombrage de pente cuit dans les vertex colors du maillage.
//
// Deux textures de poids (RGBA 8 bits sur GPU) :
//   • `splat_tex`  : R = herbe, G = terre, B = pierre (A inutilisé, = 1) ;
//   • `splat2_tex` : R = neige, G = sable (B/A inutilisés, = 1).
// Les trois premières matières gardent exactement leur poids/rendu d'avant :
// `splat2_tex` vaut (0, 0) partout tant qu'on ne peint pas de neige/sable.
//
// Le shader reste **éclairé** (spatial) : la lumière de la scène module
// l'albédo comme les autres objets 2.5D. `albedo_tint` porte la nuit.

uniform sampler2D grass_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D splat_tex : source_color, filter_linear, repeat_disable;
uniform sampler2D splat2_tex : source_color, filter_linear, repeat_disable;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float vertex_color_strength : hint_range(0.0, 1.0) = 1.0;
// 1.0 = mélange linéaire (doux) ; > 1 accentue la matière dominante.
uniform float blend_sharpness : hint_range(0.001, 4.0) = 1.0;

// Échantillonnage « anti-tiling » : trois lectures tournées/décalées de la même
// texture. Le motif ne se répète plus de façon lisible, pour un coût de 3
// échantillons par matière (très inférieur à un vrai triplanar multi-textures).
vec3 sample_anti_tile(sampler2D tex, vec2 uv) {
	vec2 b = vec2(uv.x * 0.82 - uv.y * 0.57, uv.x * 0.57 + uv.y * 0.82) * 1.17 + vec2(0.37, 0.11);
	return texture(tex, uv).rgb * 0.78
		+ texture(tex, b).rgb * 0.22;
}

void fragment() {
	vec3 weights = texture(splat_tex, UV2).rgb;
	vec2 extra = texture(splat2_tex, UV2).rg;
	float total = max(weights.r + weights.g + weights.b + extra.r + extra.g, 0.0001);
	weights /= total;
	extra /= total;
	if (abs(blend_sharpness - 1.0) > 0.0001) {
		weights = pow(weights, vec3(blend_sharpness));
		extra = pow(extra, vec2(blend_sharpness));
		float sharp_total = max(
			weights.r + weights.g + weights.b + extra.r + extra.g,
			0.0001
		);
		weights /= sharp_total;
		extra /= sharp_total;
	}
	vec3 grass = sample_anti_tile(grass_tex, UV);
	vec3 dirt = sample_anti_tile(dirt_tex, UV);
	vec3 stone = sample_anti_tile(stone_tex, UV);
	vec3 snow = sample_anti_tile(snow_tex, UV);
	vec3 sand = sample_anti_tile(sand_tex, UV);
	vec3 albedo =
		grass * weights.r
		+ dirt * weights.g
		+ stone * weights.b
		+ snow * extra.r
		+ sand * extra.g;
	albedo *= mix(vec3(1.0), COLOR.rgb, vertex_color_strength);
	// Légère variation macro pour casser les répétitions lointaines.
	float macro = sin(UV.x * 7.7 + UV.y * 11.3) * sin(UV.y * 6.1 - UV.x * 9.7);
	albedo *= 0.92 + 0.08 * macro;
	ALBEDO = albedo * albedo_tint.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
