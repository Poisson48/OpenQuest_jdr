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
// **PROJECTION TRIPLANAIRE** — le gain qualité principal : une projection UV
// classique écrase les textures sur les pentes raides (une falaise quasi
// verticale ne fait que quelques texels de haut → motifs étirés en traînées).
// Ici chaque matière est échantillonnée selon TROIS projections (XY / XZ / ZY)
// pondérées par la normale du monde : à plat la projection XZ garde exactement
// l'UV historique (poids 1), sur une paroi seules les projections verticales
// comptent et le motif garde ses proportions. Le repère de projection est
// reconstruit depuis la position MONDE (uniforme `tile_world_size` = pas du
// tuilage en unités monde) : les clusters de creusement, qui ont leurs propres
// UV, restent alignés sur le terrain.
//
// **MICRO-DÉTAIL** : bruit procédural haute fréquence (aucune texture
// supplémentaire) projeté de la même façon que les matières, qui casse la
// répétition et donne une sensation de grain au sol.
//
// **OCCLUSION** : approximation de cavité par la courbure locale (dérivées de
// la normale monde) + léger assombrissement des pentes — pas de SSAO.
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

// Taille en unités monde d'une répétition de texture (cell_size × 2 cases).
// Sert à reconstruire les coordonnées de projection depuis la position monde,
// pour que terrain ET clusters de creusement partagent le même repère.
uniform float tile_world_size = 1.4;
// 0 = projection UV historique (XZ seule) ; 1 = triplanar complet. Sert de
// référence A/B aux captures de validation ; toujours 1.0 en jeu.
uniform float triplanar_amount : hint_range(0.0, 1.0) = 1.0;
// Bornes du poids de la projection « du dessus » selon |N.y|. En dessous de
// `triplanar_lo` la projection latérale domine, au-dessus de `triplanar_hi` la
// projection XZ reprend la main : entre les deux, fondu doux.
uniform float triplanar_lo : hint_range(0.0, 1.0) = 0.35;
uniform float triplanar_hi : hint_range(0.0, 1.0) = 0.80;
// Amplitude du micro-détail procédural (0 = grain désactivé).
uniform float detail_strength : hint_range(0.0, 1.0) = 0.30;
// Fréquence du micro-détail (en répétitions de texture, donc haute fréquence).
uniform float detail_freq : hint_range(1.0, 32.0) = 7.0;
// Amplitude de la variation macro de teinte (casse les répétitions lointaines).
uniform float macro_strength : hint_range(0.0, 0.4) = 0.07;
// Occlusion approximée : assombrissement des creux (courbure) et des pentes.
uniform float cavity_strength : hint_range(0.0, 1.0) = 0.16;
uniform float slope_ao_strength : hint_range(0.0, 1.0) = 0.08;

// AUTO-MATÉRIAU PAR PENTE ET ALTITUDE (méthode Cities: Skylines II) : sans
// peinture manuelle, la roche envahit les pentes raides, la terre les
// contreforts, la neige les sommets — avec des frontières bruitées irrégulières.
// Les SPLATS PEINTS gardent la priorité (une matière peinte non herbe n'est
// jamais remplacée) ; l'auto-matériau ne complète que les zones neutres
// (herbe = matière par défaut). `auto_material_strength` = 0 → rendu précédent
// exactement (A/B et réversibilité).
uniform float auto_material_strength : hint_range(0.0, 1.0) = 1.0;
// Altitude basse (unités monde) : origine de la normalisation de l'altitude.
uniform float terrain_min_height = 0.0;
// Altitude haute (unités monde) : sommet de la normalisation.
uniform float terrain_max_height = 0.0;
// Force du relief de normale procédural (0 = normales de la géométrie seule).
uniform float normal_detail_strength : hint_range(0.0, 4.0) = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	// Position/normale en espace monde : le repère des projections ne dépend
	// pas de l'orientation du nœud (terrain comme clusters de creusement).
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Échantillonnage « anti-tiling » : deux lectures tournées/décalées de la même
// texture. À plat, c'est exactement le rendu historique (la projection XZ est
// la seule active, avec un poids de 1).
vec3 sample_anti_tile(sampler2D tex, vec2 uv) {
	vec2 b = vec2(uv.x * 0.82 - uv.y * 0.57, uv.x * 0.57 + uv.y * 0.82) * 1.17 + vec2(0.37, 0.11);
	return texture(tex, uv).rgb * 0.78
		+ texture(tex, b).rgb * 0.22;
}

// Projection triplanaire d'une matière : XY (paroi face Z), XZ (sol) et ZY
// (paroi face X), pondérées par la normale monde. La projection XZ réutilise
// l'anti-tiling historique ; les parois se contentent d'un échantillon (elles
// ne représentent qu'une fraction de l'écran et le triplanar casse déjà la
// répétition).
vec3 sample_triplanar(sampler2D tex, vec3 p, vec3 w) {
	vec3 side_x = texture(tex, p.zy).rgb;
	vec3 top = sample_anti_tile(tex, p.xz);
	vec3 side_z = texture(tex, p.xy).rgb;
	return side_x * w.x + top * w.y + side_z * w.z;
}

// Bruit de valeur 2D bon marché (déterministe, sans texture) : sert au
// micro-détail et à la variation macro.
float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Hauteur du micro-détail : bruit procédural projeté exactement comme les
// matières (triplanar). Réutilisée pour le grain d'albédo ET pour la
// perturbation de normale (le relief donne du corps à la roche et à l'herbe).
float detail_height(vec3 p, vec3 w) {
	return value_noise(p.xz * detail_freq) * w.y
		+ value_noise(p.zy * detail_freq * 1.07 + vec2(13.7, 5.1)) * w.x
		+ value_noise(p.xy * detail_freq * 0.93 + vec2(4.2, 27.9)) * w.z;
}

// Poids automatiques des matières d'après la pente et l'altitude (méthode CS2).
// Renvoie (herbe, terre, pierre) et la neige par `snow_out`. Les frontières sont
// déformées par du bruit monde pour éviter toute bande horizontale régulière.
vec3 auto_material_weights(vec3 p, vec3 n, out float snow_out) {
	snow_out = 0.0;
	// Altitude normalisée 0..1 sur l'amplitude du relief de la carte (0 sur une
	// carte plate : aucun effet neige/roche automatique).
	float span = terrain_max_height - terrain_min_height;
	float h = 0.0;
	if (span > 0.01) {
		h = clamp((world_pos.y - terrain_min_height) / span, 0.0, 1.0);
	}
	// Bruit d'irrégularité : deux échelles pour des frontières naturelles.
	float n_rock = value_noise(p.xz * 1.9) * 0.65
		+ value_noise(p.xz * 5.3 + vec2(11.7, 41.3)) * 0.35;
	float n_edge = value_noise(p.xz * 3.1 + vec2(7.2, 19.5)) - 0.5;
	float hb = clamp(h + (n_rock - 0.5) * 0.24 + n_edge * 0.08, 0.0, 1.0);
	float flat_n = abs(n.y);
	// Roche : pentes raides (le motif de base demandé) ou altitude moyenne.
	float rock_auto = smoothstep(0.55, 0.30, flat_n);
	rock_auto = max(rock_auto, smoothstep(0.30, 0.62, hb) * 0.90);
	// Terre : contreforts doux (altitude intermédiaire, pas encore la roche).
	float dirt_auto = smoothstep(0.14, 0.40, hb) * (1.0 - rock_auto)
		* smoothstep(0.40, 0.78, flat_n);
	// Neige : sommets, mais elle ne tient pas sur les parois raides.
	float snow_auto = smoothstep(0.60, 0.88, hb)
		* smoothstep(0.28, 0.60, flat_n + (n_rock - 0.5) * 0.20);
	snow_out = clamp(snow_auto, 0.0, 1.0);
	// Herbe : ce qui reste (plaines et replats).
	float grass_auto = max(0.0, 1.0 - rock_auto - dirt_auto - snow_auto);
	return vec3(grass_auto, dirt_auto, rock_auto);
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
	// --- Repère triplanaire ------------------------------------------------
	vec3 n = normalize(world_normal);
	float tile = max(tile_world_size, 0.0001);
	vec3 p = world_pos / tile;
	// Poids de la projection « du dessus » : 1 à plat (rendu historique exact),
	// 0 sur les parois. Les projections latérales se partagent le reste selon
	// |N.x| / |N.z| (paroi orientée X ou Z).
	float up = smoothstep(triplanar_lo, triplanar_hi, abs(n.y));
	vec2 side_w = vec2(abs(n.x), abs(n.z));
	side_w /= max(side_w.x + side_w.y, 0.0001);
	vec3 tpw = vec3(side_w.x * (1.0 - up), up, side_w.y * (1.0 - up));
	// Fondu A/B : à 0 on retrouve exactement la projection UV historique (et
	// donc un terrain plat strictement inchangé).
	tpw = mix(vec3(0.0, 1.0, 0.0), tpw, triplanar_amount);
	// --- Auto-matériau par pente et altitude (méthode CS2) -----------------
	// Les splats peints ont la priorité : une cellule peinte d'une matière
	// autre que l'herbe (matière par défaut) n'est jamais remplacée. L'auto ne
	// complète que les zones neutres.
	float auto_strength = clamp(auto_material_strength, 0.0, 1.0);
	float painted_special = clamp(1.0 - weights.r, 0.0, 1.0);
	float auto_gate = (1.0 - smoothstep(0.0, 0.18, painted_special)) * auto_strength;
	if (auto_gate > 0.001) {
		float auto_snow = 0.0;
		vec3 auto_w = auto_material_weights(p, n, auto_snow);
		weights = mix(weights, auto_w, auto_gate);
		extra = mix(extra, vec2(auto_snow, 0.0), auto_gate);
	}
	vec3 grass = sample_triplanar(grass_tex, p, tpw);
	vec3 dirt = sample_triplanar(dirt_tex, p, tpw);
	vec3 stone = sample_triplanar(stone_tex, p, tpw);
	vec3 snow = sample_triplanar(snow_tex, p, tpw);
	vec3 sand = sample_triplanar(sand_tex, p, tpw);
	vec3 albedo =
		grass * weights.r
		+ dirt * weights.g
		+ stone * weights.b
		+ snow * extra.r
		+ sand * extra.g;
	albedo *= mix(vec3(1.0), COLOR.rgb, vertex_color_strength);
	// --- Micro-détail procédural ------------------------------------------
	// Bruit projeté comme les matières (chaque projection a sa propre
	// fréquence : sur une paroi le grain ne s'étire pas non plus).
	float micro = detail_height(p, tpw);
	albedo *= mix(1.0, 0.80 + 0.40 * micro, detail_strength);
	// --- Détail de normale procédural -------------------------------------
	// Gradient du même bruit (différences finies) projeté en espace monde :
	// la roche et l'herbe gagnent un micro-relief cohérent avec le triplanar,
	// sans normal map ni texture supplémentaire.
	if (normal_detail_strength > 0.001) {
		float e = 0.22 / max(detail_freq, 1.0);
		float d0 = micro;
		float dx = detail_height(p + vec3(e, 0.0, 0.0), tpw) - d0;
		float dy = detail_height(p + vec3(0.0, e, 0.0), tpw) - d0;
		float dz = detail_height(p + vec3(0.0, 0.0, e), tpw) - d0;
		// Plus marqué sur la roche/neige que sur l'herbe.
		float rockiness = clamp(weights.b + extra.r, 0.0, 1.0);
		float bump = normal_detail_strength * (0.55 + 0.75 * rockiness);
		vec3 wn = normalize(n - vec3(dx, dy, dz) * (3.0 * bump));
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	}
	// --- Variation macro de teinte ----------------------------------------
	// Deux échelles de bruit (organique, sans bandes régulières) : casse les
	// répétitions lointaines sans dessiner de rayures périodiques.
	float macro = (value_noise(p.xz * 0.9) * 2.0 - 1.0) * 0.7
		+ (value_noise(p.xz * 2.3 + vec2(31.7, 9.4)) * 2.0 - 1.0) * 0.3;
	albedo *= 1.0 + macro_strength * macro;
	// --- Occlusion approximée (cavité + pente) ----------------------------
	// Courbure locale : dérivée écran de la normale monde. Les creux (normale
	// qui tourne vite) s'assombrissent, les surfaces plates restent claires.
	float curvature = length(dFdx(n)) + length(dFdy(n));
	float cavity = smoothstep(0.10, 0.75, curvature) * cavity_strength;
	float sky = 1.0 - slope_ao_strength * (1.0 - smoothstep(0.15, 0.85, abs(n.y)));
	float occlusion = clamp(1.0 - cavity - sky, 0.35, 1.0);
	albedo *= occlusion;
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
