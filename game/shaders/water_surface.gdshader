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
// - RÉFLEXION ÉCRAN (screen-space, méthode « Cities: Skylines II ») : la
//   surface reflète le DÉCOR rendu (terrain, falaises, berges) en lisant la
//   copie de l'écran opaque (`screen_tex`) avec un décalage UV perturbé par
//   la normale des micro-vagues — le reflet est « wavey », pas un miroir
//   figé. Poids : le Fresnel existant (rasant = fort, vertical = faible),
//   mixé avec le dégradé de ciel. `reflection_enabled = 0` rend EXACTEMENT
//   l'ancien rendu (A/B réversible), `reflection_strength` dose le mélange.
// - RÉFRACTION ÉCRAN (screen-space, méthode « Cities: Skylines II ») : le LIT
//   déjà rendu (terrain sous la nappe, dans la copie opaque `screen_tex`)
//   transparaît dans les hauts-fonds, légèrement déformé par les micro-vagues
//   (`refr_uv = SCREEN_UV + normale_xz * refraction_scale * facteur_depth`).
//   Le lit réfracté DOMINE en très faible profondeur et s'efface avec
//   l'absorption ; il est cuit dans l'albédo à hauteur de la transmittance
//   restante, donc mousse de rive, réflexions et glint gardent exactement
//   leur poids. `refraction_enabled = 0` rend EXACTEMENT l'état précédent
//   (A/B réversible), `refraction_strength` dose la distorsion.
// - FLOW MAP À DEUX PHASES : deux advections décalées d'une demi-période,
//   fondues par une fonction triangle — le courant défile sans couture.
// - `night_tint` assombrit l'eau la nuit (même logique que le sol).
//
// Le shader reste éclairé (spatial) : la lumière de la scène module l'albédo.

uniform sampler2D depth_map : filter_linear, repeat_disable;
// Copie de l'écran OPAQUE (terrain, falaises, berges derrière la nappe) :
// l'eau est transparente (blend_mix + ALPHA), elle peut donc se mirer dans
// le décor déjà rendu — c'est la base des réflexions screen-space.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
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
// RIVIÈRES : l'espace de dérive est le RUBAN (UV : u en travers, v le long du
// tracé), remis à l'échelle des coordonnées monde normalisées de la carte
// (mêmes fréquences de motif qu'un lac). `flow_ribbon = 0` = espace UV2
// historique (lacs, plans d'eau) : aucun changement.
uniform float flow_ribbon : hint_range(0.0, 1.0) = 0.0;
uniform float flow_ribbon_u_scale = 1.0;
uniform float flow_ribbon_v_scale = 1.0;
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
// --- RÉFLEXION ÉCRAN (screen-space) ---------------------------------------
// 0 = coupe le reflet d'écran et rend EXACTEMENT l'ancien rendu (A/B) ;
// 1 = le décor se mire dans la surface avec le poids Fresnel.
uniform float reflection_enabled : hint_range(0.0, 1.0) = 1.0;
// Force du mélange du reflet d'écran (défaut doux : la surface reste de
// l'eau, le décor n'y apparaît qu'en reflet).
uniform float reflection_strength : hint_range(0.0, 1.0) = 0.35;
// --- RÉFRACTION ÉCRAN (screen-space) ---------------------------------------
// 0 = coupe la réfraction du lit et rend EXACTEMENT l'état précédent (A/B) ;
// 1 = le lit déjà rendu transparaît, déformé par les micro-vagues.
uniform float refraction_enabled : hint_range(0.0, 1.0) = 1.0;
// Force de la distorsion du lit réfracté (défaut doux : 0.35 — la déformation
// reste naturelle, jamais une loupe qui tord le fond).
uniform float refraction_strength : hint_range(0.0, 1.0) = 0.35;
// --- ÉCLAIRAGE DOUBLE DU LIT RÉFRACTÉ (approximation CS2) ------------------
// Le lit vu à travers la lame d'eau reçoit (1) la lumière DIRECTE (réseau de
// caustiques projeté sur le fond) et (2) une AMBIANCE/DIFFUSION d'eau (lumière
// du ciel diffusée par la colonne d'eau, d'autant plus forte que l'eau est
// mince). Sans ce second terme, les hauts-fonds restent un aplat sombre.
// 1 = finition active (défaut) ; 0 = rendu EXACTEMENT précédent (A/B).
uniform float bed_ambient_lift : hint_range(0.0, 2.0) = 1.0;
// --- ADOUCISSEMENT DES NEZ DE RUBAN VUS DE TRÈS HAUT ----------------------
// `COLOR.b` (rivières) porte le masque de pointe posé par MapWater3D. Quand la
// caméra est très haute / la carte vue entière, l'empreinte écran d'un pixel
// devient grande en unités monde (`fwidth` de la position) : l'alpha s'éteint
// alors sur la pointe, le nez effilé ne se dessine plus en aiguille. Vrai en
// perspective comme en orthographique (aucun uniform caméra nécessaire).
// 1 = finition active (défaut) ; 0 = rendu EXACTEMENT précédent (A/B).
uniform float tip_soften_distance : hint_range(0.0, 1.0) = 1.0;
// Empreinte écran (unités monde par pixel) où commence / s'achève l'extinction
// des pointes : en deçà la carte est vue de près (aucun effet), au-delà elle
// est vue de très haut (pointe pleinement adoucie).
uniform float tip_soften_lo : hint_range(0.0, 1.0) = 0.025;
uniform float tip_soften_hi : hint_range(0.0, 1.0) = 0.075;

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

// Position MONDE interpolée : sert à mesurer l'empreinte écran d'un pixel
// (`fwidth`) pour l'adoucissement des nez de ruban vus de très haut.
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV2;
	// Espace de dérive du motif : UV2 (monde normalisé) pour les lacs, ou le
	// RUBAN le long du tracé pour les rivières (v = aval). La profondeur, la
	// berge et les reflets restent TOUJOURS échantillonnés en UV2.
	vec2 flow_uv = uv;
	if (flow_ribbon > 0.5) {
		flow_uv = vec2(UV.x * flow_ribbon_u_scale, UV.y * flow_ribbon_v_scale);
	}
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
		dot(flow_uv, flow) - TIME * flow_speed,
		dot(flow_uv, across_dir)
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

	// --- RÉFRACTION ÉCRAN : échantillonnage du LIT (screen-space) -----------
	// Le LIT déjà rendu (terrain sous la nappe — `screen_tex` est la copie
	// OPAQUE, l'eau n'y est jamais présente) transparaît dans les hauts-fonds,
	// déformé par la normale des micro-vagues. Facteur de PROFONDEUR : nul au
	// contact exact (la mousse de rive garde la berge) et dès que l'absorption
	// domine, plein sur la plage des hauts-fonds où le lit réfracté domine
	// (depth01 < ~0.35) — la distorsion et le mélange suivent le même facteur.
	float refr_depth = smoothstep(0.015, 0.09, depth01)
		* (1.0 - smoothstep(0.30, 0.62, depth01));
	vec3 refr_bed = vec3(0.0);
	float refr_act = 0.0;
	if (refraction_enabled > 0.5 && refr_depth > 0.001) {
		// Distorsion BORNÉE (jamais plus de 0.045 UV écran) : pas de
		// « ghosting » du lit qui traverserait la berge, jamais de déformation
		// criarde.
		vec2 refr_shift = clamp(
			wave_normal.xz * (refraction_strength * 0.14) * refr_depth,
			vec2(-0.045), vec2(0.045));
		vec2 refr_uv = SCREEN_UV + refr_shift;
		// Clampé, repli sur la couleur d'eau si hors écran (le poids tombe à 0).
		vec2 refr_safe = clamp(refr_uv, vec2(0.0), vec2(1.0));
		float refr_inside = smoothstep(0.0, 0.02, refr_uv.x)
			* smoothstep(0.0, 0.02, 1.0 - refr_uv.x)
			* smoothstep(0.0, 0.02, refr_uv.y)
			* smoothstep(0.0, 0.02, 1.0 - refr_uv.y);
		// LOD 0 : on veut le lit NET (les réflexions, elles, restent floues).
		refr_bed = textureLod(screen_tex, refr_safe, 0.0).rgb;
		refr_act = refr_depth * refr_inside * edge_fade;
		// --- ÉCLAIRAGE DOUBLE DU LIT RÉFRACTÉ (approximation CS2) ----------
		// Le lit arrive déjà éclairé par le terrain (caustiques directes +
		// absorption cuites dans la carte d'eau). Côté eau, on complète :
		//  (1) la lumière DIRECTE est rendue STRUCTURÉE par un réseau de
		//      caustiques projeté sur le lit — le fond n'est plus un aplat ;
		//  (2) l'AMBIANCE/DIFFUSION de la colonne d'eau (lumière du ciel
		//      diffusée par la lame) se dépose sur le lit, d'autant plus que
		//      l'eau est mince : c'est ce terme qui « décolle » le fond.
		// `bed_ambient_lift = 0` → aucun de ces termes, rendu EXACTEMENT
		// précédent (A/B réversible).
		if (bed_ambient_lift > 0.001) {
			float lift = clamp(bed_ambient_lift, 0.0, 2.0);
			float shallow_bed = 1.0 - smoothstep(0.08, 0.46, depth01);
			// (1) DIRECT : mailles de caustiques (produit de deux bruits →
			// cellules irrégulières, jamais des rayures), animées lentement.
			float bed_caustic = value_noise(wuv * 46.0 + vec2(t * 0.05, -t * 0.04))
				* value_noise(wuv * 79.0 + vec2(-t * 0.06, t * 0.03));
			bed_caustic = smoothstep(0.32, 0.74, bed_caustic);
			refr_bed *= 1.0 + bed_caustic * 0.60 * lift * shallow_bed;
			// (2) AMBIANCE : lumière du ciel diffusée dans la lame d'eau.
			vec3 bed_ambient = mix(sky_color.rgb, shallow_color.rgb, 0.45);
			refr_bed = mix(refr_bed, refr_bed + bed_ambient * 0.15,
				clamp(lift * shallow_bed * refr_depth * 0.9, 0.0, 1.0));
		}
	}

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
	// --- RÉFRACTION : le lit réfracté DOMINE la lame d'eau claire ----------
	// En très faible profondeur (depth01 < ~0.35) le corps d'eau n'est presque
	// plus qu'une vitre : la couleur du corps devient le LIT réfracté, qui
	// disparaît avec la profondeur (absorption). La teinte plate `bed_color`
	// ci-dessus ne reste qu'un support teinté sous le lit réel. Les couches
	// SUPÉRIEURES (relief, réflexions, glint, mousse) sont posées APRÈS :
	// la réfraction ne les écrase jamais.
	if (refraction_enabled > 0.5 && refr_act > 0.001) {
		// Domination pondérée par (1 - depth01) et bornée par la force de
		// réfraction : le lit domine sans effacer totalement l'eau.
		float refr_body = refr_act * (1.0 - smoothstep(0.05, 0.38, depth01))
			* clamp(refraction_strength * 1.7, 0.0, 0.85);
		water = mix(water, refr_bed, refr_body);
	}
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

	// --- RÉFLEXION ÉCRAN (screen-space, méthode « Cities: Skylines II ») ---
	// La surface reflète le décor RENDU derrière elle (terrain, falaises,
	// berges) : `screen_tex` est échantillonné avec un décalage UV perturbé
	// par la normale des micro-vagues (reflet « wavey » qui ondule avec le
	// clapot). Bloc conditionné par `reflection_enabled` : à 0, le rendu est
	// strictement l'état historique (A/B réversible).
	if (reflection_enabled > 0.5) {
		// Perturbation de surface : les micro-vagues déplacent le point
		// échantillonné. Amplitude BORNÉE (jamais plus de 0.07 UV écran) pour
		// éviter le « ghosting » qui traverse la berge.
		vec2 refl_shift = clamp(wave_normal.xz * 0.5, vec2(-0.07), vec2(0.07));
		// Le reflet vient de l'au-delà du point d'eau : il MONTe vers le haut
		// de l'écran (berge opposée, falaises), d'autant plus que la vue est
		// rasante (Fresnel haut).
		vec2 refl_uv = SCREEN_UV + refl_shift
			+ vec2(0.0, -(0.05 + 0.26 * fres));
		// Hors écran → repli sur le dégradé de ciel (jamais de bord noir).
		vec2 refl_safe = clamp(refl_uv, vec2(0.0), vec2(1.0));
		float inside = smoothstep(0.0, 0.03, refl_uv.x)
			* smoothstep(0.0, 0.03, 1.0 - refl_uv.x)
			* smoothstep(0.0, 0.03, refl_uv.y)
			* smoothstep(0.0, 0.03, 1.0 - refl_uv.y);
		vec3 screen_col = textureLod(screen_tex, refl_safe, 1.0).rgb;
		// Couleur réfléchie : le décor écran, mixé avec la couleur de CIEL
		// Fresnel actuelle (repli hors écran, teinte d'ambiance au centre).
		vec3 refl_col = mix(sky_grad, screen_col, inside * 0.85);
		// Poids : le Fresnel existant (rasant = fort reflet, vertical =
		// faible), avec un plancher doux pour la vue quasi zénithale de la
		// carte. Atténué dans les TRÈS FAIBLES profondeurs (la mousse de
		// rive et la berge restent opaques, aucun reflet qui les traverse)
		// et sur la coupe du masque (pas de fantôme au bord de la nappe).
		float refl_w = reflection_strength * (0.35 + 0.65 * fres)
			* smoothstep(0.02, 0.18, depth01) * edge_fade;
		water = mix(water, refl_col, refl_w);
	}

	// Le scintillement se pose sur la surface réfléchie.
	water += vec3(glint) * 0.22;

	// --- Mousse de CONTACT --------------------------------------------------
	// La ligne de rive ondule (bruit basse fréquence) : la mousse avance et
	// recule au gré du clapot.
	float shore_noise = fbm2(wuv * 13.0 + vec2(t * 0.12, -t * 0.09));
	// Mousse de rive sur MAILLAGE LIBRE : sans tranchée de terrain pour
	// refermer la nappe, la coupe du masque est un bord franchement visible —
	// la mousse de rive y allumait des bandes pâles ÉCHELONNÉES (les paliers
	// des texels du masque). Le canal VERT de la couleur de sommet, posé par
	// MapWater3D d'après la fermeture du terrain au-delà du bord du maillage
	// (0 = bord libre, 1 = berge qui masque la coupe), éteint fortement la
	// mousse de contact sur ces bords. Les lacs (sans couleur de sommet) et
	// les rivières en tranchée gardent la mousse de rive.
	float shore_gate = 1.0;
	if (edge_softness > 0.001) {
		shore_gate = clamp(COLOR.g, 0.0, 1.0);
	}
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
	float contact = smoothstep(0.16 + 0.16 * shore_noise, 0.42, land) * shore_gate;
	// Liseré de PROFONDEUR à largeur LOCALE : la mousse ne couvre que la
	// tranche d'eau vraiment peu profonde — sa largeur en cases suit donc la
	// pente locale du fond (jamais un anneau de largeur constante), et son
	// seuil ondule avec le clapot (`shore_noise`) pour un liseré irrégulier.
	float shore_w = max(foam_width * (0.35 + 0.90 * shore_noise), 0.004);
	float depth_contact = (1.0 - smoothstep(0.0, shore_w, depth01)) * shore_gate;
	// Le liseré de contact est lui aussi BORNÉ par la profondeur locale : il
	// s'amenuise dès que l'eau reprend de la profondeur — la ligne de rive
	// reste fine et lisible, jamais un donut épais.
	contact = max(contact * (1.0 - smoothstep(shore_w * 0.5, shore_w * 2.4, depth01)),
		depth_contact * 0.55);
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
	float rim = smoothstep(0.78, 0.985, contact);
	float band = contact * contact * contact;
	float lace_mod = smoothstep(0.32, 0.85, lace);
	// Couverture LACUNAIRE et ANIMÉE : des trous de mousse dérivent avec le
	// flux (bruit lent dédié) — le liseré est irrégulier, jamais un anneau
	// blanc continu et uniforme.
	float gaps = smoothstep(0.30, 0.68, lace * 0.72
		+ value_noise(vec2(along * 9.0, across * 22.0)
			+ vec2(t * 0.05, -t * 0.07)) * 0.48);
	float foam = foam_strength * (rim * (0.35 + 0.65 * lace_mod)
		+ band * lace_mod * 0.22) * (0.40 + 0.60 * gaps);
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
	// s'affine encore au contact exact (lame d'eau qui lappe la berge).
	float lapping = mix(1.0, 0.72, smoothstep(0.60, 1.0, contact));
	// La mousse reste plutôt opaque (elle masque le fond au lieu de se laver)
	// mais ne force plus l'opacité PLEINE là où la nappe s'amenuise : sans
	// quoi la coupe du masque devenait un liseré franc (bandes pâles
	// échelonnées sur maillage libre, silhouette dure vue de dessus).
	float foam_op = 0.35 + 0.65 * max(edge_fade, vertex_fade);
	ALPHA = clamp(mix(depth_alpha * edge_fade * lapping * vertex_fade, 0.94,
		foam * foam_op), 0.0, 0.97);
	// Bords de ruban fondus (rivières) : atténuation latérale de l'alpha sur
	// le dernier tiers de la largeur — la silhouette vue de dessus s'achève
	// en lame d'eau douce sans toucher au cœur du chenal (continuité intacte).
	if (edge_softness > 0.001) {
		float edge = smoothstep(0.0, 0.30, UV.x) * smoothstep(0.0, 0.30, 1.0 - UV.x);
		ALPHA *= mix(1.0, edge, edge_softness);
	}

	// --- RÉFRACTION ÉCRAN : composite final ---------------------------------
	// Le fond transmis (la transmittance `1 - alpha`) est REMPLACÉ par le lit
	// réfracté : cuite dans l'albédo à hauteur de la transmittance gagnée,
	// l'image de fond non déformée ne double donc jamais la réfraction (aucun
	// ghosting). Aucune réfraction au contact (mousse de rive), sur les bords
	// de nappe (`edge_fade`, `vertex_fade`) ni sur les bords latéraux du ruban
	// — la réfraction ne touche jamais les bords. Mousse, réflexions et glint
	// (déjà composés dans `water`) gardent leur poids : seul le fond transmis
	// est remplacé.
	if (refraction_enabled > 0.5 && refr_act > 0.001) {
		float refr_gate = (1.0 - smoothstep(0.10, 0.70, contact)) * vertex_fade;
		if (edge_softness > 0.001) {
			refr_gate *= mix(1.0,
				smoothstep(0.0, 0.30, UV.x) * smoothstep(0.0, 0.30, 1.0 - UV.x),
				edge_softness);
		}
		float refr_w = refr_act * refr_gate;
		if (refr_w > 0.001) {
			float a0 = ALPHA;
			float a1 = min(0.97, a0 + (1.0 - a0) * refr_w);
			// Part « lit réfracté » cuite dans l'albédo = transmittance gagnée.
			float baked = a1 - a0;
			ALBEDO = (a0 * ALBEDO + baked * refr_bed) / max(a1, 0.001);
			ALPHA = a1;
		}
	}
	// --- ADOUCISSEMENT DES NEZ DE RUBAN VUS DE TRÈS HAUT -------------------
	// `COLOR.b` (rivières uniquement, posé par MapWater3D) porte le masque de
	// pointe : 1 au nez effilé, 0 au cœur du chenal. La vue de très haut est
	// détectée SANS uniform caméra : `fwidth` de la position monde donne
	// l'empreinte écran d'un pixel en unités monde — elle grandit quand la
	// caméra monte ou que la carte est dézoomée, en perspective comme en
	// orthographique. L'alpha s'éteint alors progressivement sur la pointe :
	// le nez ne se dessine plus en aiguille, sans toucher au centre du chenal
	// (continuité de la rivière intacte). `tip_soften_distance = 0` → rendu
	// EXACTEMENT précédent (A/B réversible).
	if (tip_soften_distance > 0.001 && edge_softness > 0.001) {
		float footprint = max(fwidth(world_pos.x), fwidth(world_pos.z));
		float far_view = smoothstep(clamp(tip_soften_lo, 0.0, 2.0),
			max(tip_soften_hi, tip_soften_lo + 0.001), footprint);
		float tip = clamp(COLOR.b, 0.0, 1.0);
		ALPHA *= 1.0 - tip * far_view
			* clamp(tip_soften_distance, 0.0, 1.0) * 0.95;
	}

	ROUGHNESS = 0.12;
	METALLIC = 0.15;
}
