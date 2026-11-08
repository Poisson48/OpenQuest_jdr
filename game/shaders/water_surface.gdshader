shader_type spatial;
render_mode blend_mix, cull_disabled;

// Surface d'eau translucide animée (lacs, étangs, douves) de la carte 2.5D.
//
// Objectif « qualité Cities: Skylines II » : la surface n'est pas un aplat teal
// mais une eau lisible, vivante et structurée.
//
// - UV2 : 0..1 sur l'emprise de la carte ; sert à échantillonner la texture de
//   profondeur générée par MapWater3D (R = profondeur normalisée, 0 à la rive,
//   1 au plus profond ; G = masque d'eau, 1 = case visible, 0 = case masquée —
//   ex. sol d'une grotte sèche au-dessus du niveau). Une case = un texel,
//   filtrage linéaire.
// - MICRO-VAGUES À DEUX ÉCHELLES (houle + rides) : le champ de hauteur est
//   construit dans le repère du courant (« along » le long de `flow_dir`,
//   « across » perpendiculaire) à partir de bruits procéduraux — jamais de
//   sinusoïdes pures, qui produiraient des bandes régulières visibles. Le
//   gradient du champ donne la pente locale (normale ondulée). Le tout dérive
//   vers l'aval à `flow_speed` ; `flow_strength = 0` ramène l'animation
//   historique (repère UV d'origine, sans dérive).
// - MOUSSE DE CONTACT : liseré de rive FIN et continu au contact exact
//   terre/eau (sonde du masque d'eau), prolongé par une dentelle lacunaire
//   étirée par le courant. La ligne de rive ondule (bruit basse fréquence) et
//   les filigranes dérivent avec le flux — aucun motif périodique, aucun trait
//   peint. Les hauts-fonds portent aussi la mousse (bancs de sable).
// - BORDS D'EAU NATURELS : le masque d'eau ne tranche plus au discard — l'alpha
//   s'amenuise sur le dernier texel (feuille), la marge est assombrie et teintée
//   « terre mouillée » côté eau. La coupe terre/eau devient un dégradé.
// - LISIBILITÉ DU LIT : teinte « fond vu à travers la lame d'eau », alpha plus
//   bas dans les hauts-fonds (on lit le fond), caustiques discrètes, et fosses
//   plus denses et plus sombres.
// - Scintillement solaire STRUCTURÉ : quelques paillettes rares et fines sur
//   les crêtes des micro-vagues (masque de bruit très haute fréquence, seuil
//   haut), étirées par le courant — jamais un voile de plaques blanches.
// - RÉFLEXION DE CIEL (Fresnel) : `horizon_color` au ras de l'eau (angles
//   rasants), `sky_color` vers la verticale ; le reflet ondule avec la pente
//   des micro-vagues. Intensité pilotée par `sky_reflect`.
// - FLOW MAP À DEUX PHASES : deux advections décalées d'une demi-période,
//   fondues par une fonction triangle — le courant défile sans couture.
// - `night_tint` assombrit l'eau la nuit (même logique que le sol).
//
// Le shader reste éclairé (spatial) : la lumière de la scène module l'albédo.

uniform sampler2D depth_map : filter_linear, repeat_disable;
uniform vec4 shallow_color : source_color = vec4(0.20, 0.47, 0.48, 1.0);
uniform vec4 deep_color : source_color = vec4(0.05, 0.20, 0.28, 1.0);
uniform vec4 foam_color : source_color = vec4(0.78, 0.88, 0.88, 1.0);
uniform vec4 night_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Teinte du LIT vu à travers les hauts-fonds (sable, gravier, algues) : c'est
// elle qui donne la sensation de profondeur « à la CS2 ».
uniform vec4 bed_color : source_color = vec4(0.46, 0.50, 0.34, 1.0);
// Reflet de CIEL : `horizon_color` au ras de l'eau (angles rasants, teinte
// laiteuse), `sky_color` vers le zénith (bleu plus dense).
uniform vec4 sky_color : source_color = vec4(0.52, 0.66, 0.76, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.80, 0.86, 0.88, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.78;
uniform float alpha_depth : hint_range(0.0, 0.3) = 0.10;
uniform float wave_strength : hint_range(0.0, 0.5) = 0.08;
uniform float wave_speed : hint_range(0.0, 4.0) = 0.9;
uniform float foam_strength : hint_range(0.0, 2.0) = 1.0;
uniform float foam_width : hint_range(0.01, 0.5) = 0.12;
// Flux directionnel : les vagues glissent le long de `flow_dir` (UV2).
uniform vec2 flow_dir = vec2(1.0, 0.0);   // direction d'écoulement normalisée (UV2)
uniform float flow_speed = 0.12;          // vitesse de dérive du motif (UV/s)
// 0 = animation isotrope historique (repère UV d'origine, sans dérive) ;
// 1 = pleine dérive des vagues le long de `flow_dir`.
uniform float flow_strength : hint_range(0.0, 1.0) = 1.0;
// Adoucissement des bords de ruban (rivières) : l'alpha s'atténue sur les
// bords latéraux du maillage pour fondre la nappe dans les berges
// (0 = désactivé — lacs et plan d'eau historique inchangés).
uniform float edge_softness : hint_range(0.0, 1.0) = 0.0;
// Fréquence des filigranes de mousse : > 1 = mousse plus fine (petits cours
// d'eau), < 1 = plaques plus larges (grand lac).
uniform float foam_scale : hint_range(0.25, 4.0) = 1.0;
// Intensité du scintillement solaire structuré.
uniform float glint_strength : hint_range(0.0, 2.0) = 1.0;
// Intensité des caustiques (réseau lumineux qui danse sur le lit).
uniform float caustic_strength : hint_range(0.0, 1.0) = 0.35;
// Coefficient d'EXTINCTION par profondeur (courbe `1 - exp(-k * depth)`).
uniform float depth_extinction : hint_range(0.5, 8.0) = 2.4;
// Décalage de la profondeur « perçue » : une rivière peu profonde doit rester
// lisible et claire même si sa profondeur normalisée est proche de 1.
uniform float depth_bias : hint_range(-0.6, 0.6) = 0.0;
// Taille d'un texel de `depth_map` en UV : sert à sonder le MASQUE d'eau pour
// trouver le contact terre/eau (la profondeur normalisée, elle, peut sauter de
// 1 à 0 sur une case — inutilisable seule pour placer la mousse de rive).
uniform vec2 depth_texel = vec2(0.01, 0.01);
// Rayon de la sonde de contact en TEXELS de `depth_map` : la résolution du
// masque diffère entre lac (1 texel/case) et rivière (4 texels/case) — ce
// rayon égalise la largeur du liseré de mousse en unités monde.
uniform float shore_texels : hint_range(0.1, 4.0) = 0.6;
// Intensité du reflet de ciel (Fresnel) : teinte laiteuse au ras de l'eau sur
// les vues inclinées, reflet plus dense vers la verticale.
uniform float sky_reflect : hint_range(0.0, 1.0) = 0.32;

// ===========================================================================
// Bruits procéduraux (aucune texture, aucun asset)
// ===========================================================================

// Hachage 2D → [0, 1) : base du bruit de valeur.
float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Bruit de valeur 2D lissé (interpolation cubique) — pas de motif périodique
// visible contrairement à une somme de sinusoïdes.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Bruit fractal à deux octaves : plus de détail qu'un simple bruit de valeur,
// pour des filigranes de mousse et des ondulations crédibles.
float fbm2(vec2 p) {
	return value_noise(p) * 0.65 + value_noise(p * 2.03 + vec2(17.3, 5.1)) * 0.35;
}

// Champ de HAUTEUR des micro-vagues, à trois échelles (houle lente, rides
// moyennes, micro-clapot). `q` est déjà dans le repère du courant et dérive
// avec lui ; `t` fait évoluer les formes (la mer ne translate pas, elle ondule).
float wave_field(vec2 q, float t) {
	float big = value_noise(q * 6.0 + vec2(t * 0.035, -t * 0.021));
	float mid = value_noise(q * 21.0 + vec2(-t * 0.085, t * 0.060));
	float micro = value_noise(q * 64.0 + vec2(t * 0.160, -t * 0.120));
	return big * 0.50 + mid * 0.30 + micro * 0.20;
}

void fragment() {
	vec2 uv = UV2;
	vec4 depth_sample = texture(depth_map, uv);
	float depth01 = depth_sample.r;

	// Masque d'eau (canal G de la même texture) : les cases dont le sol visible
	// n'est pas sous le niveau (creusements fermés, grottes sèches) ne rendent
	// aucune eau — le plan ne traverse pas le terrain creusé. Le découpage est
	// ADOUCI : au lieu d'un trait net au discard, l'alpha s'amenuise sur le
	// dernier texel du masque (`edge_fade`) pour un bord de nappe fondu.
	if (depth_sample.g < 0.18) {
		discard;
	}
	float edge_fade = smoothstep(0.18, 0.62, depth_sample.g);
	// Profondeur « perçue » : `depth_bias` permet de rendre une eau peu
	// profonde (rivière) plus claire sans toucher à la géométrie — les usages
	// géométriques (mousse de rive, calme des hauts-fonds) gardent `depth01`.
	float depth_tint = clamp(depth01 + depth_bias, 0.0, 1.0);

	// --- Repère du COURANT ---------------------------------------------------
	vec2 flow = flow_dir;
	float flow_len = length(flow);
	if (flow_len < 0.0001) {
		// Direction nulle (ou non normalisée) : repli sur l'axe X.
		flow = vec2(1.0, 0.0);
	} else {
		flow /= flow_len;
	}
	vec2 across_dir = vec2(-flow.y, flow.x);
	vec2 flow_frame = vec2(
		dot(uv, flow) - TIME * flow_speed,
		dot(uv, across_dir)
	);
	// `flow_strength` : 0 = repère historique (uv, sans dérive), 1 = repère du
	// courant entièrement dérivé ; les valeurs intermédiaires mélangent les
	// deux repères (le mélange reste une rotation + homothétie douce).
	vec2 wuv = mix(uv, flow_frame, flow_strength);
	float t = TIME * wave_speed;
	// Coordonnées dans le repère du courant : `along` suit le flux (les
	// motifs s'y étirent et y dérivent), `across` lui est perpendiculaire.
	float along = dot(wuv, flow);
	float across = dot(wuv, across_dir);

	// --- FLOW MAP À DEUX PHASES ---------------------------------------------
	// Détail fin de surface advecté dans le sens du courant par DEUX voies
	// décalées d'une demi-période, fondues par une fonction triangle : la voie
	// qui se raccorde est à poids nul, donc le motif défile en continu, sans
	// saut ni couture (méthode classique des flow maps, utilisée par CS2).
	float famp = TIME * flow_speed * 2.5;
	float fa = fract(famp);
	float fb = fract(famp + 0.5);
	float w_a = 1.0 - abs(2.0 * fa - 1.0);        // 0 → 1 → 0 (poids voie A)
	vec2 drift_a = flow * (0.35 * fa);
	vec2 drift_b = flow * (0.35 * fb);
	float detail_a = fbm2((wuv - drift_a) * 58.0);
	float detail_b = fbm2((wuv - drift_b) * 58.0);
	float detail = mix(detail_a, detail_b, w_a);

	// --- Micro-vagues à deux échelles ---------------------------------------
	// Pente locale = gradient du champ de hauteur (différences finies). Elle
	// est amortie dans les hauts-fonds : l'eau y est plus calme qu'au large.
	float h0 = wave_field(wuv, t);
	float eps = 0.0022;
	vec2 slope = vec2(
		wave_field(wuv + vec2(eps, 0.0), t) - h0,
		wave_field(wuv + vec2(0.0, eps), t) - h0
	) / eps;
	float shoal = smoothstep(0.0, 0.25, depth01);
	vec2 tilt = slope * (wave_strength * 0.17 * mix(0.45, 1.0, shoal));
	// Le détail advecté casse l'échelle des grandes vagues : rides fines
	// supplémentaires, orientées par le courant.
	float detail_slope = (detail_a - detail_b) * wave_strength * 0.9;
	tilt += vec2(detail_slope, detail_slope * 0.7);

	// Normale ondulée : petits reflets en mouvement. (NORMAL est en espace
	// vue ; vue quasi zénithale de la carte, la perturbation UV reste plausible.)
	NORMAL = normalize(NORMAL + vec3(-tilt.x, 0.0, -tilt.y));
	vec3 wave_normal = normalize(vec3(-tilt.x, 1.0, -tilt.y));

	// --- Scintillement solaire STRUCTURÉ (rare et filigrané) -----------------
	// Deux bruits fins très haute fréquence, seuillés HAUT : quelques éclats
	// isolés sur les crêtes des micro-vagues, jamais un voile de plaques. Les
	// paillettes sont étirées le long du courant (fréquence transversale >
	// longitudinale) et dérivent avec lui.
	// Le demi-vecteur se prend entre le soleil et la verticale du plan d'eau
	// (vue quasi zénithale de la carte 2.5D).
	vec3 sun = normalize(vec3(0.35, 0.85, 0.4));
	vec3 half_v = normalize(sun + vec3(0.0, 1.0, 0.0));
	float ndh = clamp(dot(wave_normal, half_v), 0.0, 1.0);
	vec2 glint_uv = vec2(along * 190.0, across * 260.0) + vec2(-t * 0.30, t * 0.11);
	float sparkle = value_noise(glint_uv);
	float sparkle2 = value_noise(glint_uv * 1.83 + vec2(t * 0.19, -t * 0.24));
	float glitter = smoothstep(0.74, 0.93, sparkle * 0.55 + sparkle2 * 0.45);
	// Le scintillement n'allume que les crêtes : c'est ce qui le rend
	// « structuré » au lieu d'un mouchetis uniforme.
	glitter *= smoothstep(0.42, 0.72, h0);
	float glint = glitter * (0.30 + 0.70 * pow(ndh, 12.0)) * 0.55;
	glint *= glint_strength * mix(0.55, 1.0, shoal);

	// --- Couleur : lisibilité de la PROFONDEUR ------------------------------
	// Hauts-fonds clairs → fosses sombres.
	vec3 water = mix(shallow_color.rgb, deep_color.rgb,
		smoothstep(0.06, 0.92, depth_tint));
	// Lit visible à travers la lame d'eau des hauts-fonds (sable/algues) : la
	// teinte du fond transparaît d'autant plus que l'eau est mince.
	float bed = 1.0 - smoothstep(0.0, 0.38, depth_tint);
	water = mix(water, bed_color.rgb, bed * 0.26);
	// Variation macro douce : casse l'aplat uniforme de la surface.
	float mottle = fbm2(wuv * 9.0 + vec2(t * 0.017, -t * 0.013));
	water *= 0.94 + 0.12 * mottle;
	// Relief de surface : les crêtes prennent la lumière, les creux
	// s'assombrissent — l'ondulation se lit même sans reflet solaire. Les
	// rides FINES (détail advecté) dominent : l'eau ondule sans « nuages ».
	float relief = smoothstep(0.32, 0.78, h0);
	water *= 0.88 + 0.20 * relief + 0.28 * (detail - 0.5);
	// Caustiques : réseau lumineux irrégulier sur le lit des hauts-fonds (le
	// produit de deux bruits donne des mailles, pas des rayures).
	vec2 cq = wuv * 33.0;
	float caustic = value_noise(cq) * value_noise(cq * 1.73 + vec2(9.2, 4.1));
	caustic = smoothstep(0.42, 0.72, caustic);
	water += vec3(0.30, 0.36, 0.20) * caustic * caustic_strength * bed;

	// Filaments de COURANT : rides d'advection très étirées le long du flux,
	// obtenues par bruit (pas de sinusoïde → pas de stries régulières).
	float streak_freq = 16.0 + 28.0 * flow_speed;
	vec2 streak_uv = vec2(along * streak_freq, across * 95.0);
	float filament = fbm2(streak_uv + vec2(-t * 0.20, 0.0));
	float streak = smoothstep(0.52, 0.82, filament);
	water *= 0.94 + 0.12 * streak * (0.35 + 0.65 * (1.0 - depth_tint));

	// --- Terre mouillée (côté eau) ------------------------------------------
	// Avant la berge, la lame d'eau s'amenuise : marge plus sombre et teintée
	// par le lit (sable/algues) — la coupe terre/eau devient un dégradé au
	// lieu d'un trait franc.
	float wet = 1.0 - smoothstep(0.0, 0.30, depth01);
	water *= mix(1.0, 0.60, wet * 0.9);
	water = mix(water, bed_color.rgb * 0.72, wet * 0.20);

	// --- RÉFLEXION DE CIEL (Fresnel) ---------------------------------------
	// L'eau prend la teinte du ciel d'autant plus qu'on la regarde de biais :
	// `horizon_color` au ras de l'eau, `sky_color` vers la verticale. La pente
	// des micro-vagues fait onduler le reflet (zénith ↔ horizon) : le reflet
	// varie en distance au lieu d'être un aplat. (CS2 a de vrais reflets ; ici
	// le ciel est un simple dégradé, sans réflexion coûteuse.)
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 2.2);
	vec3 sky_grad = mix(sky_color.rgb, horizon_color.rgb, pow(1.0 - ndv, 1.35));
	sky_grad = mix(sky_grad, horizon_color.rgb,
		clamp(tilt.y * 1.4 + 0.5, 0.0, 1.0) * 0.30);
	water = mix(water, sky_grad, fres * sky_reflect);

	// Le scintillement se pose sur la surface réfléchie.
	water += vec3(glint) * 0.22;

	// --- Mousse de CONTACT --------------------------------------------------
	// La ligne de rive ondule (bruit basse fréquence) : la mousse avance et
	// recule au gré du clapot.
	float shore_noise = fbm2(wuv * 13.0 + vec2(t * 0.12, -t * 0.09));
	// Proximité du MASQUE d'eau : un anneau de HUIT sondes (décalé par le
	// clapot) mesure la fraction de l'anneau côté terre. Une vraie berge en
	// couvre la moitié ; un TROU de masque (berge qui affleure, texel de bord
	// manquant) n'en touche qu'un huitième — le contact reste donc collé à la
	// ligne de rive et ne s'allume jamais au bord des trous. Le rayon
	// (`shore_texels`, en texels) compense la résolution du masque pour
	// égaler la largeur du liseré en unités monde (lac 1 texel/case,
	// rivière 4 texels/case).
	vec2 jit = (vec2(shore_noise, 1.0 - shore_noise) - 0.5)
		* depth_texel * shore_texels;
	float ring = max(shore_texels, 0.15);
	vec2 rx = vec2(depth_texel.x * ring, 0.0);
	vec2 ry = vec2(0.0, depth_texel.y * ring);
	vec2 rd = (rx + ry) * 0.7071;
	vec2 rdx = vec2(rx.x, -ry.y) * 0.7071;
	float land = 0.0;
	land += step(texture(depth_map, uv + jit + rx).g, 0.5);
	land += step(texture(depth_map, uv + jit - rx).g, 0.5);
	land += step(texture(depth_map, uv + jit + ry).g, 0.5);
	land += step(texture(depth_map, uv + jit - ry).g, 0.5);
	land += step(texture(depth_map, uv + jit + rd).g, 0.5);
	land += step(texture(depth_map, uv + jit - rd).g, 0.5);
	land += step(texture(depth_map, uv + jit + rdx).g, 0.5);
	land += step(texture(depth_map, uv + jit - rdx).g, 0.5);
	land *= 0.125;
	// Profil de contact : 1 sur la ligne de rive (moitié de l'anneau côté
	// terre), 0 dès que l'anneau est entièrement dans l'eau. Le seuil
	// EXTÉRIEUR varie avec le clapot (la dentelle ondule au lieu de suivre au
	// pas les texels du masque) mais le sommet reste à 1 au contact exact.
	float contact = smoothstep(0.16 + 0.16 * shore_noise, 0.42, land);
	// Liseré de PROFONDEUR : la mousse s'étale aussi dans les hauts-fonds,
	// même loin du bord du masque (bancs de sable, hauts-fonds de lac).
	float depth_contact = 1.0 - smoothstep(0.0, max(foam_width, 0.003), depth01);
	contact = max(contact, depth_contact * 0.8);
	// Filigranes étirés le long du courant (fréquence transversale > 2× la
	// longitudinale) : la mousse file avec le flux, jamais en damier.
	vec2 lace_uv = vec2(
		along * (30.0 * foam_scale) - t * 0.22,
		across * (82.0 * foam_scale) + shore_noise * 1.6);
	float lace = fbm2(lace_uv) * 0.62
		+ value_noise(lace_uv * 2.31 + vec2(5.1, 8.7)) * 0.38;
	// Liseré FIN et nerveux au contact exact (seuil haut : le liseré reste
	// étroit quel que soit le rayon de sonde) + dentelle lacunaire un peu plus
	// large : la ligne de rive est blanche et vivante, jamais peinte au
	// pochoir. La modulation par la dentelle garde la couverture LACUNAIRE.
	float rim = smoothstep(0.72, 0.98, contact);
	float band = contact * contact;
	float lace_mod = smoothstep(0.35, 0.82, lace);
	float foam = foam_strength * (rim * (0.45 + 0.55 * lace_mod)
		+ band * lace_mod * 0.35);
	// Écume de clapot : quelques filaments épars au large, vraiment rares —
	// et jamais ces plaques blanches « éclaboussures » d'un voile trop dense.
	float crest = smoothstep(0.905, 0.985, h0)
		* smoothstep(0.58, 0.82, lace) * (1.0 - depth_tint);
	foam = clamp(foam + crest * 0.10, 0.0, 0.92);
	// La mousse passe PAR-DESSUS le reflet de ciel : elle reste blanche.
	water = mix(water, foam_color.rgb, foam);

	ALBEDO = water * night_tint.rgb;
	// Un peu d'émission pour que la mousse et les éclats restent lisibles sans
	// lumière directe.
	EMISSION = vec3(glint) * 0.06 * night_tint.rgb
		+ vec3(0.035, 0.045, 0.040) * foam * night_tint.rgb;

	// --- PROFONDEUR : extinction exponentielle -------------------------------
	// La lumière est absorbée en profondeur (`1 - exp(-k * depth)`). Peu
	// profond = presque transparent (le lit transparaît) ; profond = dense.
	float extinction = 1.0 - exp(-depth_extinction * depth_tint);
	float depth_alpha = base_alpha + alpha_depth * extinction;
	depth_alpha *= mix(0.55, 1.0, smoothstep(0.01, 0.45, depth_tint));
	// --- Bords de nappe ------------------------------------------------------
	// Opacité par SOMMET (couleur de sommet, canal R, rivières) : elle fond la
	// LAME d'eau là où elle affleure le sol rendu (nappe qui s'amenuise avant
	// de passer sous le maillage de terrain) mais laisse l'ÉCUME intacte — le
	// liseré de rive reste lisible même là où la nappe devient transparente.
	float vertex_fade = 1.0;
	if (edge_softness > 0.001) {
		vertex_fade = clamp(COLOR.r, 0.0, 1.0);
	}
	// Bords de nappe : l'eau s'amenuise sur le bord du masque (feuille) et
	// s'affine encore au contact exact (lame d'eau qui lappe la berge) ; la
	// mousse reste OPAQUE (elle masque le fond au lieu de se laver).
	float lapping = mix(1.0, 0.72, smoothstep(0.60, 1.0, contact));
	ALPHA = clamp(mix(depth_alpha * edge_fade * lapping * vertex_fade, 0.94, foam), 0.0, 0.97);
	// Bords de ruban fondus (rivières) : atténuation latérale de l'alpha.
	if (edge_softness > 0.001) {
		float edge = smoothstep(0.0, 0.20, UV.x) * smoothstep(0.0, 0.20, 1.0 - UV.x);
		ALPHA *= mix(1.0, edge, edge_softness);
	}
	ROUGHNESS = 0.12;
	METALLIC = 0.15;
}
