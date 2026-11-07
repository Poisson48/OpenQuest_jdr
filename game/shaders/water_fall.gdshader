shader_type spatial;
render_mode blend_mix, cull_disabled;

// Nappe d'eau qui tombe (cascade / chute) de la carte 2.5D : plan vertical
// translucide strié, animé vers le bas, avec écume en haut et en bas.
//
// - UV : UV du maillage vertical — UV.y = 0 en bas (réception de la chute),
//   UV.y = 1 en haut (bord où le courant quitte le plateau) ; UV.x = 0..1 en
//   travers de la nappe.
// - Chute : stries verticales procédurales (fréquence haute en X, lissées en
//   Y) qui glissent vers le bas — la phase contient TIME * fall_speed — avec
//   un léger scintillement pour l'aspect « eau vive ».
// - Écume : accumulation en bas (impact de la chute) et liseré en haut (saut
//   du courant), animée elle aussi vers le bas.
// - Translucidité : ALPHA autour de 0.8, un peu plus opaque dans l'écume.
// - `night_tint` assombrit l'eau la nuit (0 = jour, 1 = nuit).
//
// Le shader reste éclairé (spatial) : la lumière de la scène module l'albédo.
// Tout le motif est généré procéduralement (comme water_surface.gdshader) :
// `fall_noise` est déclaré pour compatibilité avec le moteur mais inutilisé.

uniform sampler2D fall_noise : source_color;   // inutilisé (bruit 100 % procédural)
uniform float fall_speed = 1.6;        // vitesse de chute du motif
uniform vec4 water_tint : source_color = vec4(0.55, 0.75, 0.85, 1.0);
uniform vec4 foam_color : source_color = vec4(0.9, 0.95, 1.0, 1.0);
uniform float night_tint : hint_range(0.0, 1.0) = 0.0;   // 0 jour, 1 nuit (assombrit)

void fragment() {
	// Chute du motif : la phase verticale croît avec le temps, donc le motif
	// glisse vers le bas (UV.y décroissant). Fréquence verticale faible pour
	// des stries continues sur toute la hauteur de la nappe.
	float fy = UV.y * 2.0 + TIME * fall_speed;
	// Étincelles : couche rapide (descente ~2x) juste devant la nappe.
	float fy_fast = UV.y * 1.5 + TIME * fall_speed * 1.5;

	// Stries verticales : trois sinus de fréquences X différentes, déformés
	// par la chute (turbulence légère).
	float s1 = sin(UV.x * 21.0 + sin(fy * 1.7) * 1.2);
	float s2 = sin(UV.x * 37.0 - fy * 1.3 + 1.7);
	float s3 = sin(UV.x * 9.0 + fy * 2.1 + 4.2);
	float streaks = s1 * 0.5 + s2 * 0.3 + s3 * 0.2;   // -1..1
	float streak01 = streaks * 0.5 + 0.5;             // 0..1

	// Scintillement : étincelles fines qui filent elles aussi vers le bas.
	float sparkle = pow(
		max(sin(UV.x * 63.0 + fy_fast * 3.1) * sin(UV.x * 29.0 - fy_fast * 1.9 + 2.2), 0.0),
		6.0
	);

	// Couleur : eau teintée entrecoupée de LAMES BLANCHES (les stries portent
	// l'écume) — une chute se lit en blanc/bleu, jamais en aplat sombre.
	float white = clamp(streak01 * 0.75 + sparkle * 0.5, 0.0, 1.0);
	vec3 water = mix(water_tint.rgb, foam_color.rgb, white);
	water = mix(water, foam_color.rgb, foam);

	// Écume : accumulation en bas (réception de la chute) et liseré en haut
	// (saut du courant) ; elle bout avec le motif qui tombe.
	float foam_bottom = 1.0 - smoothstep(0.0, 0.20, UV.y);
	float foam_top = smoothstep(0.86, 1.0, UV.y);
	float foam_zone = max(foam_bottom * 0.9, foam_top * 0.55);
	float foam = clamp(foam_zone * (0.55 + 0.45 * streak01), 0.0, 1.0);
	water = mix(water, foam_color.rgb, foam);

	// Nuit : assombrissement progressif de la nappe entière.
	vec3 night = mix(vec3(1.0), vec3(0.42, 0.50, 0.62), night_tint);
	ALBEDO = water * night;

	// Normale frémissante : les reflets dansent avec les stries.
	NORMAL = normalize(NORMAL + vec3(streaks * 0.10, sparkle * 0.12, 0.0));

	// Translucidité : l'eau qui tombe laisse voir la paroi derrière elle, avec
	// des BORDS FONDUS (le maillage ne doit pas se voir comme un panneau).
	float edge_fade = smoothstep(0.0, 0.16, UV.x) * smoothstep(0.0, 0.16, 1.0 - UV.x);
	ALPHA = clamp(0.60 + streaks * 0.06 + foam * 0.18, 0.0, 0.90) * edge_fade;
	ROUGHNESS = 0.12;
	METALLIC = 0.10;
}
