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
// **PROJECTION TRIPLANAIRE** — chaque matière est échantillonnée selon TROIS
// projections (ZY / XZ / XY) pondérées par la normale du monde : à plat la
// projection XZ garde exactement l'UV historique (poids 1), sur une paroi les
// projections verticales prennent le relais et le motif garde ses proportions.
// Le repère de projection est reconstruit depuis la position MONDE (uniforme
// `tile_world_size` = pas du tuilage en unités monde) : les clusters de
// creusement, qui ont leurs propres UV, restent alignés sur le terrain.
//
// **CORRECTION D'ÉTIREMENT** (méthode CS2) — une projection étire toujours sa
// texture le long de la pente (facteur 1/|N·axe| : la projection XZ sur une
// paroi à 75° étire le motif ~3,8× en traînées). Chaque projection est donc
// recalée à l'échelle 1:1 selon l'azimut local de la pente (`stretch_fix`).
// À plat le facteur vaut 1 : le rendu historique est strictement conservé.
// Comme les trois projections deviennent alors à la même échelle, leur fondu
// ne produit plus de fantômes étirés — d'où des parois nettes SANS traînées.
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
// `triplanar_lo` la projection latérale domine (parois), au-dessus de
// `triplanar_hi` la projection XZ reprend la main (plaines et pentes douces).
// Zone resserrée et décalée vers le haut : une paroi aux normales lissées
// (|N.y| jusqu'à ~0.6) reste intégralement en projection latérale, nette.
uniform float triplanar_lo : hint_range(0.0, 1.0) = 0.60;
uniform float triplanar_hi : hint_range(0.0, 1.0) = 0.88;
// Amplitude du micro-détail procédural (0 = grain désactivé).
uniform float detail_strength : hint_range(0.0, 1.0) = 0.30;
// Fréquence du micro-détail (en répétitions de texture, donc haute fréquence).
uniform float detail_freq : hint_range(1.0, 32.0) = 7.0;
// Amplitude de la variation macro de teinte (casse les répétitions lointaines).
uniform float macro_strength : hint_range(0.0, 0.4) = 0.07;
// Occlusion approximée : assombrissement des creux (courbure) et des pentes.
uniform float cavity_strength : hint_range(0.0, 1.0) = 0.16;
uniform float slope_ao_strength : hint_range(0.0, 1.0) = 0.08;
// Bruit des frontières de splat peintes (0 = arêtes nettes géométriques) :
// déforme légèrement la lecture des textures de poids pour que les bords des
// zones peintes (chemins, coins) deviennent organiques. L'intérieur des
// patches (poids plein) reste strictement inchangé.
uniform float splat_edge_noise : hint_range(0.0, 1.0) = 0.6;

// AUTO-MATÉRIAU PAR PENTE ET ALTITUDE (méthode Cities: Skylines II) : sans
// peinture manuelle, la roche envahit les pentes raides, la terre les
// contreforts, la neige les sommets — avec des frontières bruitées
// irrégulières, sans bandes ni strates. Les SPLATS PEINTS gardent la priorité
// (une matière peinte non herbe n'est jamais remplacée) ; l'auto-matériau ne
// complète que les zones neutres (herbe = matière par défaut).
// `auto_material_strength` = 0 → rendu précédent exactement (A/B et
// réversibilité).
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

// Recale une projection à l'échelle 1:1 sur la surface : on étire l'UV le long
// de l'azimut local de la pente (`axis`, normalisé dans le plan de projection)
// par le facteur `s` = 1/|N·axe projeté|. `s = 1` (surface plane) = no-op
// strict, donc le rendu historique des zones plates est intact.
vec2 stretch_fix(vec2 uv, vec2 axis, float s) {
	return uv + axis * (dot(uv, axis) * (s - 1.0));
}

// Projection triplanaire d'une matière : ZY (paroi face X), XZ (sol) et XY
// (paroi face Z), pondérées par la normale monde. Les trois projections sont
// passées par `stretch_fix` en amont : même échelle partout, aucun fondu en
// traînées. La projection XZ réutilise l'anti-tiling historique — MAIS
// uniquement à plat (`anti` < 1 sur les pentes) : sur une pente, le warp de
// correction d'étirement déforme l'image DÉDOUBLÉE de l'anti-tiling en
// traînées le long de la pente (le « dédoublement de motif »). Les parois
// se contentent d'un échantillon (net, et le triplanar casse déjà la
// répétition).
vec3 sample_triplanar(sampler2D tex, vec2 uv_sx, vec2 uv_top, vec2 uv_sz, vec3 w, float anti) {
	vec3 side_x = texture(tex, uv_sx).rgb;
	vec3 top = mix(texture(tex, uv_top).rgb, sample_anti_tile(tex, uv_top), anti);
	vec3 side_z = texture(tex, uv_sz).rgb;
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

// Bruit « 3D » (0..1) : deux bruits 2D décalés le long de Y, décorrelés.
// Varie selon x, y ET z — indispensable pour les frontières d'auto-matériau :
// un bruit 2D seul reste constant le long d'une paroi et produit des strates
// horizontales régulières (le « strate peinte » à proscrire).
float noise3(vec3 q) {
	float a = value_noise(vec2(q.x + q.y * 1.27, q.z + q.y * 0.59));
	float b = value_noise(vec2(q.z - q.y * 0.83, q.x + q.y * 0.41) + vec2(19.1, 7.3));
	return a * 0.55 + b * 0.45;
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
// Renvoie (herbe, terre, pierre) et la neige par `snow_out`, normalisés à 1.
// Les frontières sont déformées par du bruit 3D monde (varie aussi avec
// l'altitude) : irrégulières et organiques, sans bande horizontale régulière.
vec3 auto_material_weights(vec3 p, vec3 n, out float snow_out) {
	snow_out = 0.0;
	// Altitude normalisée 0..1 sur l'amplitude du relief de la carte (0 sur une
	// carte plate : aucun effet neige/roche automatique).
	float span = terrain_max_height - terrain_min_height;
	float h = 0.0;
	if (span > 0.01) {
		h = clamp((world_pos.y - terrain_min_height) / span, 0.0, 1.0);
	}
	// Irrégularité des frontières : deux échelles de bruit 3D. L'amplitude
	// s'ouvre avec l'altitude (`open`) : les plaines basses restent
	// strictement en herbe — règle d'or, terrain plat/peint inchangé.
	float open = smoothstep(0.0, 0.16, h);
	float n_lo = noise3(p * 1.3) - 0.5;
	float n_mid = noise3(p * 3.3 + vec3(11.7, 41.3, 7.9)) - 0.5;
	// Composante BASSE fréquence (longueur d'onde ~4 cases) : réservée à la
	// ligne de neige — une composante plus fine y produisait des micro-taches
	// sombres (trous de neige) le long de la ligne.
	float n_far = noise3(p * 0.5 + vec3(3.1, 7.7, 13.9)) - 0.5;
	float h_jit = (n_lo * 0.26 + n_mid * 0.13) * open;
	float hb = clamp(h + h_jit, 0.0, 1.0);
	float flat_n = abs(n.y);
	// Roche : pentes raides (le motif de base demandé) ou altitude moyenne.
	float rock_auto = smoothstep(0.55, 0.30, flat_n);
	rock_auto = max(rock_auto, smoothstep(0.34, 0.66, hb) * 0.92);
	// Terre : contreforts et pied de pente (altitude intermédiaire), en
	// TACHES irrégulières — jamais en bande continue le long de l'iso-hauteur.
	float patch = smoothstep(0.30, 0.70, noise3(p * 2.2 + vec3(51.0, 13.0, 29.0)));
	float dirt_auto = smoothstep(0.14, 0.48, hb) * (1.0 - rock_auto)
		* smoothstep(0.38, 0.72, flat_n) * (0.25 + 0.75 * patch);
	// Neige : sommets, ligne douce et organique — BRUIT BASSE FRÉQUENCE
	// UNIQUEMENT (la frontière ondule à l'échelle du paysage, ~4 cases) :
	// une composante fine y laissait des micro-taches sombres (trous de
	// neige). Transition resserrée (zone mixte étroite) et neige qui tient
	// aussi sur les pentes marquées : la roche ne perce plus en taches.
	float snow_line = 0.64 + n_far * 0.24 * open;
	float snow_auto = smoothstep(snow_line - 0.14, snow_line + 0.08, h)
		* smoothstep(0.12, 0.45, flat_n + n_far * 0.20);
	// La neige RECOUVRE la roche/terre dès qu'elle se forme (couverture
	// renforcée, au cube) : sinon la roche/terre sombre transparaît en
	// micro-taches le long de la ligne de neige. Les poids restent
	// normalisés ensuite.
	float snow_cover = (1.0 - snow_auto) * (1.0 - snow_auto) * (1.0 - snow_auto);
	rock_auto *= snow_cover;
	dirt_auto *= snow_cover;
	// Anti-mouchetures : on écrase les micro-poids résiduels (mélanges à 2 %
	// = « bruit numérique » autour des frontières) puis on renormalise.
	vec4 w = vec4(
		max(0.0, 1.0 - rock_auto - dirt_auto - snow_auto),
		dirt_auto, rock_auto, snow_auto);
	w = smoothstep(vec4(0.05), vec4(0.26), w);
	w /= max(w.x + w.y + w.z + w.w, 0.0001);
	snow_out = w.w;
	return w.xyz;
}

void fragment() {
	// --- Repère triplanaire + correction d'étirement ---------------------
	vec3 n = normalize(world_normal);
	float tile = max(tile_world_size, 0.0001);
	vec3 p = world_pos / tile;
	float amt = clamp(triplanar_amount, 0.0, 1.0);
	// Correction d'étirement « au besoin » : elle n'apporte rien sur les
	// pentes douces/intermédiaires (facteur proche de 1) alors que la normale
	// y varie vite et fait onduler l'UV — la texture se déforme en traînées
	// le long de la pente (le « dédoublement »). On ne corrige que les
	// surfaces VRAIMENT raides (facteur > ~1.4) : les parois gardent leur
	// correction intégrale validée (nettes, sans traînées). Ailleurs la
	// projection reste non déformée — l'étirement résiduel est borné
	// (~1,4× au maximum de la zone de fondu) et inapparent sur les matières
	// de sol, en échange de l'absence totale de fantôme.
	float need_t = smoothstep(1.35, 1.75, 1.0 / max(abs(n.y), 0.40));
	float need_sz = smoothstep(1.35, 1.75, 1.0 / max(abs(n.z), 0.40));
	float need_sx = smoothstep(1.35, 1.75, 1.0 / max(abs(n.x), 0.40));
	// Azimut de la pente dans chaque plan de projection, puis facteur de
	// recadrage 1/|N·axe| (plafonné à 2.5 pour rester stable). À plat tous
	// les facteurs valent 1 : strictement le rendu historique.
	float len_t = length(n.xz);
	vec2 dir_t = len_t > 0.001 ? n.xz / len_t : vec2(1.0, 0.0);
	float s_top = mix(1.0, 1.0 / max(abs(n.y), 0.40), amt * need_t);
	float len_sz = length(n.xy);
	vec2 dir_sz = len_sz > 0.001 ? n.xy / len_sz : vec2(1.0, 0.0);
	float s_sz = mix(1.0, 1.0 / max(abs(n.z), 0.40), amt * need_sz);
	float len_sx = length(n.zy);
	vec2 dir_sx = len_sx > 0.001 ? n.zy / len_sx : vec2(1.0, 0.0);
	float s_sx = mix(1.0, 1.0 / max(abs(n.x), 0.40), amt * need_sx);
	vec2 uv_top = stretch_fix(p.xz, dir_t, s_top);
	vec2 uv_sz = stretch_fix(p.xy, dir_sz, s_sz);
	vec2 uv_sx = stretch_fix(p.zy, dir_sx, s_sx);
	// Poids de la projection « du dessus » : 1 à plat (rendu historique
	// exact), 0 sur les parois. Les projections latérales se partagent le
	// reste selon |N.x| / |N.z| (paroi orientée X ou Z).
	// Fondu CONTRASTÉ et BIAISÉ VERS LE DESSUS : sur une pente
	// intermédiaire, un fondu 50/50 montre les deux projections du motif en
	// même temps (le « dédoublement », en traînées le long de la pente). La
	// projection XZ est la mieux recalée à l'échelle 1:1 (sa direction de
	// correction est exacte) : elle domine dès que la surface n'est plus une
	// paroi raide, qui seule garde les projections latérales. La limite du
	// fondu ondule avec du bruit monde (aucune bande régulière). À plat `up`
	// reste exactement 1 : rendu historique strictement conservé.
	float seam_jit = (noise3(p * 0.9 + vec3(7.3, 19.1, 3.7)) - 0.5) * 0.07;
	float up = smoothstep(triplanar_lo + seam_jit, triplanar_hi + seam_jit, abs(n.y));
	up = clamp((up - 0.22) * 6.0 + 0.5, 0.0, 1.0);
	vec2 side_w = vec2(abs(n.x), abs(n.z));
	// Forte dominance d'une projection latérale sur l'autre : réduit aussi
	// le dédoublement sur les parois orientées à 45°.
	side_w = pow(side_w, vec2(2.5));
	side_w /= max(side_w.x + side_w.y, 0.0001);
	vec3 tpw = vec3(side_w.x * (1.0 - up), up, side_w.y * (1.0 - up));
	// Fondu A/B : à 0 on retrouve exactement la projection UV historique (et
	// donc un terrain plat strictement inchangé).
	tpw = mix(vec3(0.0, 1.0, 0.0), tpw, amt);
	// --- Splat peints : frontières organiques ----------------------------
	// Léger déplacement de la lecture des textures de poids : les arêtes
	// géométriques des zones peintes (chemins, coins) deviennent ondulées et
	// naturelles ; l'intérieur d'un patch (poids plein) est inchangé.
	vec2 splat_uv = UV2;
	if (splat_edge_noise > 0.001) {
		vec2 texels = max(vec2(textureSize(splat_tex, 0)), vec2(1.0));
		vec2 warp = vec2(
			value_noise(p.xz * 2.3 + vec2(23.0, 51.0)),
			value_noise(p.xz * 2.3 + vec2(87.0, 13.0))) - 0.5;
		splat_uv += warp * (splat_edge_noise * 0.7 / texels);
	}
	vec3 weights = texture(splat_tex, splat_uv).rgb;
	vec2 extra = texture(splat2_tex, splat_uv).rg;
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
	// Anti-tuillage : pleinement actif à plat (s_top = 1, rendu historique
	// strict), coupé franchement dès que la correction d'étirement étire la
	// projection du dessus — sinon son image DÉDOUBLÉE devient des traînées
	// le long de la pente (le « dédoublement de motif »).
	float anti_amt = 1.0 - clamp((s_top - 1.0) * 2.5, 0.0, 1.0);
	vec3 grass = sample_triplanar(grass_tex, uv_sx, uv_top, uv_sz, tpw, anti_amt);
	vec3 dirt = sample_triplanar(dirt_tex, uv_sx, uv_top, uv_sz, tpw, anti_amt);
	vec3 stone = sample_triplanar(stone_tex, uv_sx, uv_top, uv_sz, tpw, anti_amt);
	vec3 snow = sample_triplanar(snow_tex, uv_sx, uv_top, uv_sz, tpw, anti_amt);
	vec3 sand = sample_triplanar(sand_tex, uv_sx, uv_top, uv_sz, tpw, anti_amt);
	float snow_w = clamp(extra.r, 0.0, 1.0);
	vec3 albedo =
		grass * weights.r
		+ dirt * weights.g
		+ stone * weights.b
		+ snow * extra.r
		+ sand * extra.g;
	albedo *= mix(vec3(1.0), COLOR.rgb, vertex_color_strength);
	// --- Micro-détail procédural ------------------------------------------
	// Bruit projeté comme les matières (chaque projection a sa propre
	// fréquence : sur une paroi le grain ne s'étire pas non plus). Quasi
	// supprimé sur la neige (elle doit rester propre et lisse, sans
	// mouchetures).
	float micro = detail_height(p, tpw);
	albedo *= mix(1.0, 0.80 + 0.40 * micro, detail_strength * (1.0 - 0.85 * snow_w));
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
		// Plus marqué sur la roche que sur la neige ou l'herbe ; le relief
		// procédural s'efface sur la neige (micro-taches de lumière/sombre).
		float rockiness = clamp(weights.b * (1.0 - 0.8 * snow_w) + snow_w * 0.10, 0.0, 1.0);
		float bump = normal_detail_strength * (0.55 + 0.75 * rockiness)
			* (1.0 - 0.7 * snow_w);
		vec3 wn = normalize(n - vec3(dx, dy, dz) * (3.0 * bump));
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	}
	// --- Variation macro de teinte ----------------------------------------
	// Deux échelles de bruit (organique, sans bandes régulières) : casse les
	// répétitions lointaines sans dessiner de rayures périodiques.
	float macro = (value_noise(p.xz * 0.9) * 2.0 - 1.0) * 0.7
		+ (value_noise(p.xz * 2.3 + vec2(31.7, 9.4)) * 2.0 - 1.0) * 0.3;
	albedo *= 1.0 + macro_strength * macro * (1.0 - 0.6 * snow_w);
	// --- Neige propre -----------------------------------------------------
	// Éclaircissement renforcé dès que la neige apparaît : les grains sombres
	// de la pierre/terre qui transparaissent dans le mélange partiel sont
	// blanchis — la ligne de neige reste propre, sans micro-taches.
	albedo = mix(albedo, albedo * 1.10 + vec3(0.035),
		clamp(snow_w * 1.35, 0.0, 1.0) * 0.7);
	// --- Occlusion approximée (cavité + pente) ----------------------------
	// Courbure locale : dérivée écran de la normale monde. Les creux (normale
	// qui tourne vite) s'assombrissent, les surfaces plates restent claires.
	// La cavité est fortement atténuée sur la neige (pas de taches sombres
	// au sommet ni sur la ligne de neige).
	float curvature = length(dFdx(n)) + length(dFdy(n));
	float cavity = smoothstep(0.10, 0.75, curvature) * cavity_strength
		* (1.0 - 0.8 * snow_w);
	float sky = 1.0 - slope_ao_strength * (1.0 - smoothstep(0.15, 0.85, abs(n.y)));
	float occlusion = clamp(1.0 - cavity - sky, 0.35, 1.0);
	albedo *= occlusion;
	// --- BERGE MOUILLÉE : terre assombrie/brunie AU BORD de l'eau --------
	// `shore_tex` (construite par la couche d'eau) encode une distance à la
	// rive : 1 dans l'eau, puis décroissance par paliers (≈ ×0.72 par case).
	// On la REDÉCODE en distance (en cases) pour obtenir un dégradé
	// PROGRESSIF — et non le liseré brut à deux cases des paliers — avec :
	//   • un bord ONDULÉ par du bruit monde (jamais un liseré régulier) ;
	//   • une bande PLUS LARGE sur les faibles pentes (l'eau s'infiltre plus
	//     loin dans une berge douce que dans une berge raide) ;
	//   • un assombrissement/brunissement maximal tout au bord de l'eau,
	//     qui s'estompe vers l'extérieur.
	if (shore_enabled > 0.001) {
		vec2 shore_uv = UV2;
		vec2 stp = 1.0 / max(vec2(textureSize(shore_tex, 0)), vec2(1.0));
		// Passe de dilatation virtuelle (×0.72, même pas que la couche
		// d'eau) : étale la donnée d'une case de plus, pour que la bande
		// garde un dégradé continu jusqu'à son extérieur.
		float sv = texture(shore_tex, shore_uv).r;
		float snx = max(texture(shore_tex, shore_uv + vec2(stp.x, 0.0)).r,
			texture(shore_tex, shore_uv - vec2(stp.x, 0.0)).r);
		float snz = max(texture(shore_tex, shore_uv + vec2(0.0, stp.y)).r,
			texture(shore_tex, shore_uv - vec2(0.0, stp.y)).r);
		sv = max(sv, max(snx, snz) * 0.72);
		// Distance à la rive, en cases (décodage logarithmique du palier).
		float dist = log(max(sv, 0.02)) / log(0.72);
		// Bord ondulé : deux échelles de bruit monde déplacent la limite de
		// la bande mouillée (±0,8 case) — jamais un liseré régulier. Le
		// déplacement s'annule dans l'eau (il ne concerne que la terre).
		float wob = (value_noise(p.xz * 0.55 + vec2(41.0, 7.0)) - 0.5) * 1.2
			+ (value_noise(p.xz * 1.9 + vec2(87.0, 13.0)) - 0.5) * 0.5;
		float dd = max(dist, 0.0) + wob * smoothstep(0.0, 1.0, dist);
		// Largeur de la bande selon la pente : ~0.5 case sur une berge
		// raide, ~3 cases sur une faible pente.
		float bank = mix(0.5, 3.0, smoothstep(0.80, 0.99, abs(n.y)));
		float wet = (1.0 - smoothstep(0.0, bank, dd)) * shore_enabled;
		albedo = mix(albedo, mix(albedo * 0.55, shore_tint.rgb, 0.45), wet);
	}
	ALBEDO = albedo * albedo_tint.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
