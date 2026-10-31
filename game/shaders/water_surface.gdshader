shader_type spatial;
render_mode blend_mix, cull_disabled;

// Surface d'eau translucide animée (lacs, étangs, douves) de la carte 2.5D.
//
// - UV2 : 0..1 sur l'emprise de la carte ; sert à échantillonner la texture de
//   profondeur générée par MapWater3D (R = profondeur normalisée, 0 à la rive,
//   1 au plus profond). Une case = un texel, filtrage linéaire.
// - Ondulations : petites vagues procédurales animées par TIME qui perturbent
//   la normale (reflets doux) et font scintiller l'albédo.
// - Rive : écume claire sur les faibles profondeurs, animée elle aussi.
// - Transparence : ALPHA légèrement plus opaque au large, plus claire à la rive.
// - `night_tint` assombrit l'eau la nuit (même logique que le sol).
//
// Le shader reste éclairé (spatial) : la lumière de la scène module l'albédo.

uniform sampler2D depth_map : filter_linear, repeat_disable;
uniform vec4 shallow_color : source_color = vec4(0.20, 0.47, 0.48, 1.0);
uniform vec4 deep_color : source_color = vec4(0.05, 0.20, 0.28, 1.0);
uniform vec4 foam_color : source_color = vec4(0.78, 0.88, 0.88, 1.0);
uniform vec4 night_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.78;
uniform float alpha_depth : hint_range(0.0, 0.3) = 0.10;
uniform float wave_strength : hint_range(0.0, 0.5) = 0.08;
uniform float wave_speed : hint_range(0.0, 4.0) = 0.9;
uniform float foam_strength : hint_range(0.0, 2.0) = 1.0;
uniform float foam_width : hint_range(0.01, 0.5) = 0.12;

void fragment() {
	vec2 uv = UV2;
	float depth01 = texture(depth_map, uv).r;

	// Vagues procédurales douces (pas de texture nécessaire).
	float t = TIME * wave_speed;
	vec2 p = uv * 24.0;
	float w1 = sin(p.x + t) * cos(p.y * 1.3 - t * 0.7);
	float w2 = sin((p.x + p.y) * 1.7 + t * 1.4);
	float w3 = sin(p.x * 0.7 - p.y * 1.1 + t * 0.5);
	float waves = w1 * 0.5 + w2 * 0.3 + w3 * 0.2;

	// Normale légèrement ondulée : petits reflets en mouvement.
	NORMAL = normalize(NORMAL + vec3(waves * wave_strength, 0.0, w2 * wave_strength * 0.7));

	// Couleur : turquoise clair à la rive, bleu-vert profond au large.
	vec3 water = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.05, 0.85, depth01));
	water += vec3(waves * 0.03 * (1.0 - depth01));

	// Écume de rive : bande claire animée sur les faibles profondeurs.
	float shore = 1.0 - smoothstep(0.0, foam_width, depth01);
	float foam = clamp(shore * (0.55 + 0.45 * waves) * foam_strength, 0.0, 1.0);
	water = mix(water, foam_color.rgb, foam);

	ALBEDO = water * night_tint.rgb;
	ALPHA = clamp(
		mix(base_alpha, base_alpha + alpha_depth, smoothstep(0.0, 0.8, depth01))
			- foam * 0.30,
		0.0,
		0.95
	);
	ROUGHNESS = 0.15;
	METALLIC = 0.15;
}
