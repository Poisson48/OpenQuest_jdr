shader_type spatial;
render_mode blend_mix, cull_disabled;

// Surface d'eau translucide animée (lacs, étangs, douves) de la carte 2.5D.
//
// - UV2 : 0..1 sur l'emprise de la carte ; sert à échantillonner la texture de
//   profondeur générée par MapWater3D (R = profondeur normalisée, 0 à la rive,
//   1 au plus profond ; G = masque d'eau, 1 = case visible, 0 = case masquée —
//   ex. sol d'une grotte sèche au-dessus du niveau). Une case = un texel,
//   filtrage linéaire.
// - Ondulations : petites vagues procédurales animées par TIME qui perturbent
//   la normale (reflets doux) et font scintiller l'albédo.
// - Flux : les vagues sont construites dans le repère du courant (« along » le
//   long de `flow_dir`, « across » perpendiculaire) et glissent vers l'aval à
//   la vitesse `flow_speed`, pour animer une rivière dans son sens
//   d'écoulement ; `flow_strength = 0` ramène l'animation historique (repère
//   UV d'origine, sans dérive).
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

void fragment() {
	vec2 uv = UV2;
	vec4 depth_sample = texture(depth_map, uv);
	float depth01 = depth_sample.r;

	// Masque d'eau (canal G de la même texture) : les cases dont le sol visible
	// n'est pas sous le niveau (creusements fermés, grottes sèches) ne rendent
	// aucune eau — le plan ne traverse pas le terrain creusé.
	if (depth_sample.g < 0.5) {
		discard;
	}

	// Vagues procédurales douces (pas de texture nécessaire). Le motif est
	// construit dans le repère du courant et glisse vers l'aval : la phase
	// contient dot(uv, flow_dir) - TIME * flow_speed. Avec `flow_dir` égal à
	// vec2(1, 0) (défaut), le repère coïncide avec l'UV d'origine : seules les
	// formes des vagues et leur douceur sont conservées à l'identique, seule
	// s'ajoute la dérive lente vers l'aval.
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
	// deux repères (le mélange reste une rotation + homothétie douce, sans
	// cisaillement).
	vec2 wuv = mix(uv, flow_frame, flow_strength);
	float t = TIME * wave_speed;
	vec2 p = wuv * 40.0;
	float w1 = sin(p.x + t) * cos(p.y * 1.3 - t * 0.7);
	float w2 = sin((p.x + p.y) * 1.7 + t * 1.4);
	float w3 = sin(p.x * 0.7 - p.y * 1.1 + t * 0.5);
	float waves = w1 * 0.5 + w2 * 0.3 + w3 * 0.2;

	// Normale légèrement ondulée : petits reflets en mouvement.
	NORMAL = normalize(NORMAL + vec3(waves * wave_strength, 0.0, w2 * wave_strength * 0.7));

	// Couleur : turquoise clair à la rive, bleu-vert profond au large.
	vec3 water = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.05, 0.85, depth01));
	water += vec3(waves * 0.03 * (1.0 - depth01));
	// Stries de COURANT : filaments allongés dans le sens de l'écoulement —
	// une rivière montre son mouvement, pas une surface uniforme.
	float along = dot(uv, flow);
	float across = dot(uv, across_dir);
	float streak = sin(along * 60.0 - t * 2.4 + sin(across * 14.0) * 0.8);
	streak = smoothstep(0.2, 1.0, streak * 0.5 + 0.5);
	water *= 0.93 + 0.10 * streak * (0.5 + 0.5 * (1.0 - depth01));

	// Liseré de rive : terre mouillée plus sombre juste avant la berge.
	float wet_edge = 1.0 - smoothstep(0.0, 0.06, depth01);
	water *= mix(1.0, 0.55, wet_edge);

	// Écume de rive : très discrète sur une rivière calme (fine ligne claire).
	float shore = 1.0 - smoothstep(0.0, foam_width, depth01);
	float foam = clamp(shore * (0.35 + 0.65 * max(waves, 0.0)) * foam_strength, 0.0, 1.0);
	foam *= smoothstep(0.0, 0.03, depth01);
	water = mix(water, foam_color.rgb, foam);

	// Reflet du SOLEIL simulé (indépendant des lumières de la scène) : calculé
	// sur une ondulation FINE (scintillement irrégulier) et non sur les
	// grandes vagues — sinon le reflet forme des bandes régulières.
	vec3 sun = normalize(vec3(0.35, 0.85, 0.4));
	vec3 fine_n = normalize(vec3(
		sin(p.x * 1.7 + t * 1.3) * 0.09,
		1.0,
		cos(p.y * 1.7 - t * 0.9) * 0.09
	));
	float glint = pow(clamp(dot(fine_n, normalize(sun + vec3(0.0, 0.0, 1.0))), 0.0, 1.0), 64.0);
	glint *= 0.55 + 0.45 * w3;
	water += vec3(glint) * 0.16;

	ALBEDO = water * night_tint.rgb;
	// Un peu d'émission pour que le reflet reste lisible même sans lumières.
	EMISSION = vec3(glint) * 0.06 * (1.0 - depth01 * 0.5) * night_tint.rgb;

	ALPHA = clamp(
		mix(base_alpha, base_alpha + alpha_depth, smoothstep(0.0, 0.8, depth01))
			- foam * 0.30,
		0.0,
		0.95
	);
	// Bords de ruban fondus (rivières) : atténuation latérale de l'alpha.
	if (edge_softness > 0.001) {
		float edge = smoothstep(0.0, 0.20, UV.x) * smoothstep(0.0, 0.20, 1.0 - UV.x);
		ALPHA *= mix(1.0, edge, edge_softness);
	}
	ROUGHNESS = 0.15;
	METALLIC = 0.15;
}
