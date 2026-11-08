shader_type spatial;
render_mode blend_mix, cull_disabled;

// Rideau de CHUTE d'eau (cascade) de la carte 2.5D.
//
// La nappe est un quad accroché à la paroi visible, du bord du plateau (crête)
// jusqu'au pied (bassin). UV : UV.y = 0 au pied, UV.y = 1 à la crête ;
// UV.x = 0..1 en travers du rideau.
//
// Ce qui fait « eau qui tombe » plutôt qu'un panneau plat :
//  • des LAMES VERTICALES (bruit blanc très étiré en Y) qui filent vers le bas
//    à `fall_speed`, de plusieurs échelles (larges lames + filaments fins) ;
//  • des LAMES BLANCHES nettes sur les crêtes du bruit (écume entraînée) ;
//  • l'écume de CRÊTE (l'eau bascule par-dessus le bord) et de PIED (impact) ;
//  • une BRUME au pied (nappe douce, animée, qui déborde du rideau) ;
//  • une TRANSPARENCE de fond : la roche se lit derrière le rideau, plus
//    opaque dans l'écume que dans le cœur de la lame ;
//  • des BORDS FONDUS sur les quatre côtés (aucune arête de panneau) ;
//  • une légère émission sur l'écume : elle reste blanche même à l'ombre.
//
// Le shader reste éclairé (spatial) : la lumière de la scène module l'albédo.
// `fall_noise` est conservé pour compatibilité avec le moteur mais inutilisé
// (tout le motif est procédural, comme `water_surface.gdshader`).

uniform sampler2D fall_noise : source_color;   // inutilisé (bruit procédural)
uniform float fall_speed = 1.8;                // vitesse de chute du motif
uniform vec4 water_tint : source_color = vec4(0.55, 0.75, 0.85, 1.0);
uniform vec4 foam_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform float night_tint : hint_range(0.0, 1.0) = 0.0;   // 0 jour, 1 nuit

// Bruit de valeur 2D lissé (déterministe, sans texture).
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Fractal de 3 octaves, normalisé ~0..1.
float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 3; i++) {
		v += amp * value_noise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v / 0.875;
}

void fragment() {
	// t = 0 au pied, 1 à la crête. `flow` fait DESCENDRE le motif (un motif
	// échantillonné en t + flow remonte en t quand le temps croît).
	float t = UV.y;
	float flow = TIME * fall_speed;

	// --- Lames d'eau verticales : bruit étiré en Y, à trois échelles --------
	// Les lames larges donnent le corps du rideau ; les filaments fins la
	// texture « filante » de l'eau qui accélère en tombant.
	float n1 = fbm(vec2(UV.x * 13.0, t * 1.5 + flow * 1.05));
	float n2 = fbm(vec2(UV.x * 31.0 + 2.7, t * 2.2 + flow * 1.85));
	float n3 = value_noise(vec2(UV.x * 67.0 + 5.3, t * 3.2 + flow * 2.7));
	float streak = clamp(n1 * 0.48 + n2 * 0.34 + n3 * 0.30, 0.0, 1.0);
	// Contraste : les creux restent bien bleus, les crêtes franchement blanches.
	streak = smoothstep(0.18, 0.86, streak);

	// LAMES BLANCHES : les crêtes du bruit s'éclairent en écume entraînée ;
	// des filaments plus fins accélèrent la lecture « eau qui file ».
	float blades = smoothstep(0.56, 0.90, streak);
	float filaments = smoothstep(0.74, 0.97,
		value_noise(vec2(UV.x * 113.0 + 9.1, t * 1.8 + flow * 3.2)));

	// --- Écume de crête : le courant bascule par-dessus le bord -------------
	float lip = smoothstep(0.78, 1.0, t);
	float lip_foam = lip * smoothstep(0.18, 0.72,
		value_noise(vec2(UV.x * 21.0, t * 7.0 - flow * 2.4)) + lip * 0.40);

	// --- Écume de pied : impact, ébullition, brume qui déborde --------------
	float foot_band = 1.0 - smoothstep(0.02, 0.34, t);
	float boiling = value_noise(vec2(UV.x * 11.0, t * 9.0 - flow * 2.6));
	float mist = value_noise(vec2(UV.x * 5.5 + 3.0, t * 3.5 - flow * 0.9));
	float foot_foam = foot_band * (0.50 + 0.50 * boiling);
	float haze = (1.0 - smoothstep(0.0, 0.45, t)) * (0.30 + 0.70 * mist);
	float foam = clamp(max(max(foot_foam, lip_foam * 0.85), blades * 0.30), 0.0, 1.0);
	// Bande de CRÊTE : l'eau s'aère en basculant par-dessus le seuil — rideau
	// dense et blanc qui masque la surface du bief amont. Plus bas, le rideau
	// redevient limpide et laisse lire la paroi.
	float crest = smoothstep(0.62, 0.84, t);
	foam = clamp(max(foam, crest * (0.60 + 0.40 * streak)), 0.0, 1.0);

	// --- Couleur : cœur bleu-vert, lames et écume blanches ------------------
	vec3 deep = water_tint.rgb * (0.66 + 0.34 * streak);
	vec3 col = mix(deep, foam_color.rgb, clamp(blades * 0.55 + filaments * 0.30 + foam * 0.85, 0.0, 1.0));
	// Brume au pied : voile blanc diffus qui s'ajoute par-dessus la nappe.
	col = mix(col, foam_color.rgb, haze * foot_band * 0.27);
	// L'eau s'aère en basculant : la crête s'éclaircit et s'opacifie.
	col = mix(col, foam_color.rgb, lip * 0.28 + crest * 0.30);
	// Nuit : assombrissement progressif de la nappe entière.
	vec3 night = mix(vec3(1.0), vec3(0.42, 0.50, 0.62), night_tint);
	ALBEDO = col * night;
	// L'écume reste lumineuse (sinon la chute s'écrase en aplat sombre).
	EMISSION = foam_color.rgb * (foam * 0.28 + haze * foot_band * 0.10)
		* (1.0 - 0.55 * night_tint);

	// Normale frémissante : les lames et l'ébullition font danser les reflets.
	NORMAL = normalize(NORMAL + vec3((streak - 0.5) * 0.34, (boiling - 0.5) * 0.22, 0.0));

	// --- Transparence : on voit la paroi derrière le rideau -----------------
	// Bords latéraux FONDUS et IRREGULIERS : la largeur du fondu ondule avec
	// les lames (bruits lents le long de la chute) — le rideau ne se termine
	// plus par deux droites verticales ni par un rectangle de translucidité.
	float side_n = value_noise(vec2(t * 4.5, UV.x * 6.0 + 2.7));
	float side_n2 = value_noise(vec2(t * 2.1 + 4.4, UV.x * 3.0));
	float sx = min(UV.x, 1.0 - UV.x);
	float edge_x = smoothstep(0.0, 0.13 + 0.17 * side_n + 0.08 * side_n2, sx);
	// Bords haut/bas fondus : la crête rejoint la rivière (effilochée par le
	// courant), le pied rejoint le bassin — aucune arête franche de panneau.
	float top_wisp = smoothstep(0.80, 1.0, t)
		* value_noise(vec2(UV.x * 19.0, t * 9.0 - flow * 2.5));
	float edge_top = clamp(1.0 - top_wisp * 0.85 - smoothstep(0.965, 1.0, t) * 0.65, 0.0, 1.0);
	float foot_n = value_noise(vec2(UV.x * 6.5 + 1.3, t * 2.0 + flow * 0.4));
	float edge_bottom = smoothstep(0.0, 0.035 + 0.055 * foot_n, t);
	float body_alpha = mix(0.26, 0.74, clamp(foam + blades * 0.26 + filaments * 0.12, 0.0, 1.0));
	body_alpha = clamp(body_alpha + crest * 0.14, 0.0, 0.97);
	// Le voile translucide du cœur s'amenuise lui aussi vers les bords : plus
	// aucun rectangle de lavage autour des lames.
	body_alpha *= mix(0.30, 1.0, edge_x);
	ALPHA = clamp(body_alpha * edge_x * edge_top * edge_bottom, 0.0, 0.97);
	// La brume du pied reste plus transparente, mais déborde jusqu'en bas.
	ALPHA = max(ALPHA, haze * 0.24 * edge_x * smoothstep(0.0, 0.10, t));

	ROUGHNESS = 0.10;
	METALLIC = 0.0;
	SPECULAR = 0.55;
}
