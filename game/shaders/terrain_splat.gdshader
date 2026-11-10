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
// BERGE : texture construite par la couche d'eau (1 = eau, dégradé = bande
// de terre mouillée). `shore_enabled` évite tout effet quand la carte n'a
// pas d'eau (l'échantillonneur non lié renvoie du blanc).
uniform sampler2D shore_tex : filter_linear, repeat_disable;
uniform vec4 shore_tint : source_color = vec4(0.30, 0.26, 0.18, 1.0);
uniform float shore_enabled : hint_range(0.0, 1.0) = 0.0;

// Deux lectures décalées pour les matières autres que l'herbe.
vec3 sample_anti_tile(sampler2D tex, vec2 uv) {
	vec2 b = vec2(uv.x * 0.82 - uv.y * 0.57, uv.x * 0.57 + uv.y * 0.82) * 1.17 + vec2(0.37, 0.11);
	return texture(tex, uv).rgb * 0.78
		+ texture(tex, b).rgb * 0.22;
}

vec2 grass_hash(vec2 cell) {
	vec2 seed = vec2(dot(cell, vec2(127.1, 311.7)), dot(cell, vec2(269.5, 183.3)));
	return fract(sin(seed) * 43758.5453);
}

vec3 sample_grass(vec2 uv) {
	// Trois offsets pseudo-aléatoires sur une grille triangulaire. Deux
	// triangles voisins partagent les mêmes échantillons à leur frontière.
	vec2 grid = vec2(uv.x - uv.y * 0.5773503, uv.y * 1.1547005) * 0.83;
	vec2 cell = floor(grid);
	vec2 f = fract(grid);
	float diagonal = f.x + f.y - 1.0;
	vec2 corner = diagonal > 0.0 ? vec2(1.0) : vec2(0.0);
	vec3 weights = vec3(abs(diagonal), min(f.x, 1.0 - f.y), min(f.y, 1.0 - f.x));
	weights *= weights;
	weights /= dot(weights, vec3(1.0));
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec3 a = textureGrad(grass_tex, uv + grass_hash(cell + corner), dx, dy).rgb;
	vec3 b = textureGrad(grass_tex, uv + grass_hash(cell + vec2(1.0, 0.0)), dx, dy).rgb;
	vec3 c = textureGrad(grass_tex, uv + grass_hash(cell + vec2(0.0, 1.0)), dx, dy).rgb;
	// Teinte à l'échelle de plusieurs cases, indépendante de la tuile.
	vec2 broad = uv * 0.26;
	vec2 p = floor(broad);
	vec2 t = smoothstep(vec2(0.0), vec2(1.0), fract(broad));
	float patch = mix(mix(grass_hash(p).x, grass_hash(p + vec2(1.0, 0.0)).x, t.x),
		mix(grass_hash(p + vec2(0.0, 1.0)).x, grass_hash(p + vec2(1.0)).x, t.x), t.y);
	return (a * weights.x + b * weights.y + c * weights.z)
		* mix(vec3(0.86, 0.95, 0.90), vec3(1.13, 1.04, 0.94), patch);
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
	vec3 grass = sample_grass(UV);
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
	albedo *= mix(0.92 + 0.08 * macro, 1.0, weights.r);
	// BERGE MOUILLÉE : assombrit et brunit la terre au bord de l'eau.
	if (shore_enabled > 0.001) {
		float shore = texture(shore_tex, UV2).r;
		shore = smoothstep(0.10, 0.75, shore) * shore_enabled;
		albedo = mix(albedo, mix(albedo * 0.55, shore_tint.rgb, 0.45), shore);
	}
	ALBEDO = albedo * albedo_tint.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
