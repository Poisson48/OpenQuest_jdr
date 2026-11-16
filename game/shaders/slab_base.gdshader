shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// SOCLE DE DIORAMA (finitions « qualité CS2 ») — matériau de la dalle qui
// remplace le rendu de l'ancienne jupe de falaise autour du terrain 3D.
//
// Le maillage (construit par `MapGround3D._make_slab_mesh`) porte des MASQUES
// dans la couleur de sommet, pas des couleurs :
//   R = couverture HERBEUSE (débord d'arête, racines) — 1 sur le dessus ;
//   B = OCCLUSION simulée (1 = dégagé ; < 1 = sous le débord d'arête, pied) ;
//   A = poids de TERRE / contact (salissure et sol tassé au pied de paroi).
//
// Ce que le shader ajoute :
//  • STRATES GÉOLOGIQUES lisibles : bandes horizontales (sin) déformées par
//    deux échelles de bruit → jamais de rayures droites ni régulières ; des
//    strates portent de la mousse humide ;
//  • bruit MACRO de teinte et micro-motif haute fréquence : casse l'aplat et
//    la répétition (aucune texture externe) ;
//  • ARÊTE HERBEUSE : la couverture (ROUGE) est cassée par le micro-motif pour
//    que la limite herbe/roche ondule au lieu d'être un trait net ;
//  • RACCORD SOL/PAROI : terre + salissure en pied (ALPHA) et AO verticale
//    (BLEU) sous le débord, pour que la dalle « repose ».
//
// Le shader reste ÉCLAIRÉ (spatial) : le soleil, les ombres et l'AO du preset
// qualité CS2 modulent la dalle ; en classique elle est simplement éclairée
// comme l'ancienne jupe. `slab_strata = 0` rend une roche unie (A/B de
// l'option strates), les autres intensités se règlent sans reconstruire.

uniform vec4 rock_dark : source_color = vec4(0.30, 0.26, 0.21, 1.0);
uniform vec4 rock_light : source_color = vec4(0.57, 0.51, 0.43, 1.0);
uniform vec4 moss_color : source_color = vec4(0.28, 0.36, 0.20, 1.0);
uniform vec4 grass_color : source_color = vec4(0.36, 0.52, 0.27, 1.0);
uniform vec4 earth_color : source_color = vec4(0.42, 0.33, 0.22, 1.0);
uniform vec4 night_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Option STRATES (A/B) : 1 = bandes géologiques, 0 = roche unie.
uniform float slab_strata : hint_range(0.0, 1.0) = 1.0;
// Intensité de l'AO simulée (canal B de la couleur de sommet).
uniform float slab_ao_strength : hint_range(0.0, 1.0) = 1.0;
// Intensité de la terre/salissure de pied (canal A).
uniform float slab_contact_strength : hint_range(0.0, 1.0) = 1.0;
// Couverture herbeuse de l'arête (canal R).
uniform float slab_grass_cover : hint_range(0.0, 1.0) = 1.0;
// Taille d'une case monde : garde les fréquences de bruit relatives à la carte.
uniform float slab_cell_size = 1.0;

varying vec3 world_pos;

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

float fbm2(vec2 p) {
	return value_noise(p) * 0.65 + value_noise(p * 2.03 + vec2(17.3, 5.1)) * 0.35;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float cell = max(slab_cell_size, 0.001);
	vec3 wp = world_pos;
	float yn = wp.y / cell;
	// Déformation des strates par deux échelles de bruit : les bandes ondulent
	// et s'effilent sans jamais devenir des rayures horizontales régulières.
	// Fréquence ≈ 1 bande par case : 3 strates lisibles sur la jupe (2,5 cases).
	float warp = (value_noise(wp.xz * (0.30 / cell) + vec2(7.3, 3.1)) - 0.5) * 0.9
		+ (value_noise(wp.xz * (0.95 / cell) + vec2(21.7, 9.4)) - 0.5) * 0.35;
	float band = sin(yn * 6.8 + warp * 1.6 + wp.x * 0.03) * 0.5 + 0.5;
	band = smoothstep(0.20, 0.80, band);
	float band2 = sin(yn * 3.1 + warp * 1.2 + 2.3) * 0.5 + 0.5;
	// Roche : bandes sombres/claires, puis deux autres matières en strates —
	// TERRE (brun chaud) sur certaines bandes basses, MOUSSE humide sur les
	// crêtes de bandes : la jupe se lit comme une coupe géologique.
	vec3 rock = mix(rock_dark.rgb, rock_light.rgb, band);
	float moss_band = smoothstep(0.60, 0.90, band2)
		* smoothstep(0.30, 0.75, band);
	rock = mix(rock, moss_color.rgb, moss_band * 0.55);
	float earth_band = smoothstep(0.55, 0.90,
		sin(yn * 2.35 + warp * 0.8 + 4.6) * 0.5 + 0.5);
	rock = mix(rock, earth_color.rgb * 0.85,
		earth_band * 0.35 * (1.0 - moss_band));
	// Option : strates coupées → roche unie intermédiaire (A/B lisible).
	rock = mix(mix(rock_dark.rgb, rock_light.rgb, 0.45), rock,
		clamp(slab_strata, 0.0, 1.0));
	// Bruit macro (teinte) + micro-motif haute fréquence : aucun aplat, aucune
	// répétition visible, pas de texture externe.
	float macro = fbm2(wp.xz * (0.30 / cell) + vec2(wp.y * 0.13, 5.7));
	float micro = value_noise(wp.xz * (2.2 / cell) + vec2(3.1, wp.y * 0.8));
	rock *= 0.90 + 0.20 * macro;
	rock *= 0.95 + 0.10 * micro;
	// Laminations fines (micro-strates) : cassent les bandes larges sans
	// introduire de motif répétitif (fréquence élevée + bruit de déformation).
	float fine = sin(yn * 23.0 + warp * 3.1 + wp.x * 0.9) * 0.5 + 0.5;
	rock *= 0.96 + 0.08 * fine * clamp(slab_strata, 0.0, 1.0);
	// ARÊTE HERBEUSE : couverture (ROUGE) cassée par le micro-motif pour que la
	// limite herbe/roche ondule au lieu d'être un trait net.
	float grass = clamp(COLOR.r * slab_grass_cover, 0.0, 1.0);
	grass *= smoothstep(0.10, 0.60,
		value_noise(wp.xz * (1.6 / cell) + vec2(11.3, 2.9)) * 0.55 + grass * 0.65);
	// Teinte herbeuse vivante : herbe grasse / herbe sèche selon le macro-bruit,
	// avec un peu de terre sur le bord usé (là où la couverture s'amenuise).
	vec3 grass_col = grass_color.rgb * (0.86 + 0.34 * macro);
	grass_col = mix(grass_col,
		grass_color.rgb * 1.18 + vec3(0.06, 0.05, 0.0), micro * 0.45);
	grass_col = mix(grass_col, earth_color.rgb,
		smoothstep(0.45, 0.95, 1.0 - grass) * 0.30);
	vec3 albedo = mix(rock, grass_col, grass);
	// RACCORD SOL/PAROI : terre tassée + salissure au pied (ALPHA de sommet).
	float contact = clamp(COLOR.a * slab_contact_strength, 0.0, 1.0);
	albedo = mix(albedo, earth_color.rgb * (0.88 + 0.24 * macro), contact * 0.85);
	// AO SIMULÉE : le débord assombrit l'arête, le pied s'assombrit vers le bas.
	albedo *= mix(1.0, clamp(COLOR.b, 0.0, 1.0),
		clamp(slab_ao_strength, 0.0, 1.0));
	ALBEDO = albedo * night_tint.rgb;
	ROUGHNESS = mix(0.95, 0.82, grass);
	METALLIC = 0.0;
}
