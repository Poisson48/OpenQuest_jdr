shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// BRUME DE PIED DE CASCADE (finition « qualité Cities: Skylines II ») :
// voile bas animé accroché au pied de chaque ressaut. La géométrie est
// construite par `MapWater3D` (deux quads par chute, budget borné) :
//   • un VOILE vertical, du pied vers le haut — la colonne de brume qui
//     remonte le long de la paroi ;
//   • une NAPPE horizontale basse qui déborde vers l'aval — la brume plaquée
//     au sol, lisible même avec la caméra quasi zénithale de la carte.
//
// UV : u = 0..1 en travers du voile ; v = 0 au CONTACT (pied / impact) et
// v = 1 au sommet du voile (ou au loin sur la nappe). L'alpha se DISSIPE avec
// v : maximum au pied, extinction rapide vers le haut — exactement la
// signature d'une éclaboussure qui retombe.
//
// Aucun asset : tout est procédural (bruit de valeur + fbm), comme les autres
// shaders d'eau. `mist_enabled = 0` → ALPHA 0 et discard : le rendu est
// EXACTEMENT l'état précédent (A/B réversible, mesuré par captures off/on).
//
// Coût : non éclairé (unshaded), pas d'écriture de profondeur, un seul draw
// call par bassin de rivière (tous les quads sont dans le même maillage), au
// plus `MapWater3D.MIST_MAX_QUADS` quads par carte.

uniform vec4 mist_color : source_color = vec4(0.82, 0.89, 0.92, 1.0);
uniform float mist_density : hint_range(0.0, 1.5) = 0.55;
uniform float mist_speed : hint_range(0.0, 2.0) = 0.35;
uniform float mist_scale : hint_range(0.5, 8.0) = 2.4;
uniform float night_tint : hint_range(0.0, 1.0) = 0.0;
// A/B réversible : 0 = aucune brume (rendu strictement identique à l'état
// précédent de la finition).
uniform float mist_enabled : hint_range(0.0, 1.0) = 1.0;

// Bruits procéduraux (aucune texture) — mêmes primitives que les autres
// shaders d'eau pour rester cohérent visuellement.
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
	if (mist_enabled < 0.5) {
		discard;
	}
	float h = clamp(UV.y, 0.0, 1.0);
	float u = clamp(UV.x, 0.0, 1.0);
	// Dissipation avec la hauteur : maximum près du pied (h = 0), extinction
	// rapide — la brume retombe au lieu de monter comme une colonne pleine.
	float height_fade = pow(1.0 - h, 1.75);
	// Amorce douce AU CONTACT : aucun liseré horizontal net à la base.
	float base_fade = smoothstep(0.0, 0.12, h);
	// Bords latéraux fondus : le voile n'a pas de bords de panneau.
	float side_fade = smoothstep(0.0, 0.24, u) * smoothstep(0.0, 0.24, 1.0 - u);

	// Deux nappes de bruit animées (large + fine) qui MONTENT le long du
	// voile : la brume se renouvelle au lieu de défiler en bloc.
	float t = TIME * mist_speed;
	float n1 = fbm(vec2(u * 4.6 * mist_scale + t * 0.35,
		h * 3.0 * mist_scale - t * 0.95));
	float n2 = value_noise(vec2(u * 17.0 * mist_scale - t * 0.60,
		h * 9.0 * mist_scale - t * 1.55));
	float density = mix(n1, n2, 0.32);

	// Opacité : seuil doux sur le bruit (lacunaire, jamais un voile uniforme),
	// cœur un peu plus dense que les volutes.
	float a = mist_density * height_fade * base_fade * side_fade
		* smoothstep(0.20, 0.86, density);
	a *= 0.72 + 0.48 * n1;
	vec3 col = mist_color.rgb * (0.90 + 0.20 * n1);
	col *= mix(vec3(1.0), vec3(0.48, 0.56, 0.68), night_tint);

	// Unshaded : la brume diffuse sa propre lumière (elle ne doit pas
	// s'éteindre à l'ombre comme un panneau opaque).
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 0.85);
}
