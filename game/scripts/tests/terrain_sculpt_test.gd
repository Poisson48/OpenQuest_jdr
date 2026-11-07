extends SceneTree

## Tests de la **sculpture volumétrique** (déplacement lissé — le vrai
## terraforming, sans « boules ») :
##   • un tampon déplace la surface en cloche douce (pas de bosse parasite) ;
##   • deux tampons enchaînés forment UNE crête unique (pas deux boules) ;
##   • ajout/retrait accumulatifs, lissage local ;
##   • sol visible (`top_surface_at`) et clusters MC cohérents ;
##   • undo/redo du document, sérialisation JSON.

const FieldScript := preload("res://scripts/maps/terrain/terrain_carve_field.gd")
const ChunksScript := preload("res://scripts/maps/terrain/terrain_carve_chunks.gd")
const GroundScript := preload("res://scripts/maps/map_layers/map_ground_3d.gd")

const W := 16
const H := 12

var DocScript: GDScript
var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	DocScript = load("res://scripts/maps/editor/map_edit_document.gd")
	_test_stamp_profile()
	_test_chained_stamps()
	_test_accumulate_and_smooth()
	_test_flatten_plateau()
	_test_scrape_fill_pinch()
	_test_clay_kernels()
	_test_layer_cap()
	_test_deform_brushes()
	_test_family3_brushes()
	_test_falloff_and_autosmooth()
	_test_mountain_grows()
	_test_doc_undo_serialize()
	await _test_ground_clusters()
	if _failed:
		print("terrain_sculpt_test:FAIL")
		quit(1)
		return
	print("terrain_sculpt_test:PASS")
	quit(0)

func _flat_heights(value: float = 0.5) -> Array:
	var heights: Array = []
	heights.resize(W * H)
	heights.fill(value)
	return heights

## Profil de surface le long de y = z0, de x0 à x1 (pas de 0.25 case).
func _profile(field, x0: float, x1: float, z0: float) -> Array:
	var out: Array = []
	var x := x0
	while x <= x1 + 0.001:
		out.append(field.top_surface_at(x, z0))
		x += 0.25
	return out

# ===========================================================================

func _test_stamp_profile() -> void:
	var field = FieldScript.new(_flat_heights(), W, H, [], {})
	# Un tampon « remblayer » : la surface monte en cloche douce.
	field.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 2.0, 0.6)
	var prof := _profile(field, 2.0, 10.0, 6.0)
	var peak := -INF
	var peak_x := 2.0
	for i in range(prof.size()):
		if float(prof[i]) > peak:
			peak = float(prof[i])
			peak_x = 2.0 + float(i) * 0.25
	_assert("stamp_raises", peak > 0.9, "pic=%.3f" % peak)
	_assert("stamp_centered", absf(peak_x - 6.0) < 0.4, "pic_x=%.2f" % peak_x)
	# Monotonie stricte de chaque côté du pic (cloche unique — pas de bosse
	# parasite, c'est ça qui distinguait les vieilles « boules »).
	var rising := true
	var monotone := true
	for i in range(1, prof.size()):
		var d := float(prof[i]) - float(prof[i - 1])
		if rising and d < -0.012:
			rising = false
		elif not rising and d > 0.012:
			monotone = false
			break
	_assert("stamp_single_bell", monotone)

func _test_chained_stamps() -> void:
	var field = FieldScript.new(_flat_heights(), W, H, [], {})
	# Trois tampons en chaîne à l'espacement réel de la brosse (0.35 × rayon,
	# comme l'éditeur) : UNE crête continue, sans onde de bosses.
	var spacing := 1.6 * 0.35
	field.sculpt_stamp(Vector3(5.0, 0.5, 6.0), 1.6, 0.5)
	field.sculpt_stamp(Vector3(5.0 + spacing, 0.5, 6.0), 1.6, 0.5)
	field.sculpt_stamp(Vector3(5.0 + spacing * 2.0, 0.5, 6.0), 1.6, 0.5)
	var prof := _profile(field, 3.0, 9.4, 6.0)
	var local_max := 0
	for i in range(1, prof.size() - 1):
		if float(prof[i]) > float(prof[i - 1]) + 0.012 \
				and float(prof[i]) > float(prof[i + 1]) + 0.012:
			local_max += 1
	_assert("chain_single_ridge", local_max <= 1, "pics=%d" % local_max)
	# La crête est pleine : les tampons se fondent (pas de vallée entre).
	var mid_min := INF
	for i in range(prof.size()):
		var x := 3.0 + float(i) * 0.25
		if x >= 5.2 and x <= 5.9:
			mid_min = minf(mid_min, float(prof[i]))
	_assert("chain_no_valley", mid_min > 0.85, "creux=%.3f" % mid_min)

func _test_accumulate_and_smooth() -> void:
	var field = FieldScript.new(_flat_heights(), W, H, [], {})
	# Creuser : la surface descend sous la base.
	field.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.6, -0.5)
	field.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.6, -0.5)
	var dug: float = field.top_surface_at(6.0, 6.0)
	_assert("dig_lowers", dug < 0.1, "h=%.3f" % dug)
	# Remblayer par-dessus : accumule.
	field.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.6, 0.8)
	var raised: float = field.top_surface_at(6.0, 6.0)
	_assert("fill_accumulates", raised > dug + 0.4, "h=%.3f" % raised)
	# Lissage : réduit les variations locales.
	var rough = FieldScript.new(_flat_heights(), W, H, [], {})
	rough.sculpt_stamp(Vector3(4.0, 0.5, 6.0), 1.2, 0.6)
	rough.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.2, -0.6)
	var before_var := _variation(rough, 3.0, 7.0, 6.0)
	rough.sculpt_smooth(Vector3(5.0, 0.5, 6.0), 2.2)
	rough.sculpt_smooth(Vector3(5.0, 0.5, 6.0), 2.2)
	var after_var := _variation(rough, 3.0, 7.0, 6.0)
	_assert("smooth_reduces", after_var < before_var * 0.75,
		"avant=%.3f après=%.3f" % [before_var, after_var])

func _test_flatten_plateau() -> void:
	var field = FieldScript.new(_flat_heights(), W, H, [], {})
	# Une butte sculptée...
	for sx in [5.0, 6.2, 7.4]:
		field.sculpt_stamp(Vector3(sx, 0.5, 6.0), 1.6, 0.7)
	var hill_top: float = field.top_surface_at(6.2, 6.0)
	_assert("flatten_base_hill", hill_top > 0.9, "h=%.3f" % hill_top)
	# ...puis aplanie vers 0.9 : le sommet devient un PLATEAU (brosse Aplatir,
	# cible = niveau du point de départ du trait).
	for _i in range(4):
		field.sculpt_flatten(Vector3(6.2, hill_top, 6.0), 2.0, 0.9, 0.9)
	var vmin := INF
	var vmax := -INF
	for dx in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var v := field.top_surface_at(6.2 + dx, 6.0)
		vmin = minf(vmin, v)
		vmax = maxf(vmax, v)
	_assert("flatten_plateau_level", absf((vmin + vmax) * 0.5 - 0.9) < 0.12,
		"moyenne=%.3f" % ((vmin + vmax) * 0.5))
	_assert("flatten_plateau_flat", vmax - vmin < 0.18,
		"delta=%.3f" % (vmax - vmin))

## Une VRAIE montagne : la croissance doit être **LINÉAIRE** (chaque passage
## ajoute sa force — pas de rendement décroissant : le bug « encore et encore
## et ça ne monte pas »), survivre aux allers-retours de sérialisation, et
## rester visible dans le rendu.
func _test_mountain_grows() -> void:
	var md = get_root().get_node("MapData")
	var base: Dictionary = md.create_complex_map("Test montagne", "general", "local", W, H)
	var doc = DocScript.new()
	doc.load_map(base)
	var top_5 := 0.0
	var top_15 := 0.0
	for i in range(15):
		doc.sculpt_stamp(Vector3(6.0, 0.0, 6.0), 1.8, 0.6, "Remblai")
		if i == 4:
			top_5 = doc._sculpt_support().top_surface_at(6.0, 6.0)
		if i == 14:
			top_15 = doc._sculpt_support().top_surface_at(6.0, 6.0)
	_assert("mountain_height", top_15 > 8.0, "h=%.2f" % top_15)
	_assert("mountain_linear", absf(top_15 - top_5 * 3.0) < 0.4,
		"5 pas=%.2f cases, 15 pas=%.2f cases" % [top_5, top_15])
	# Rechargement depuis la forme stockée : perte < 15 cm (quantification
	# 1/127 de l'échelle du chunk — l'ancien bug, lui, rognait plusieurs cases).
	# Mêmes hauteurs de base que la carte de test (à zéro).
	var reloaded = FieldScript.new(_flat_heights(0.0), W, H, [],
		doc.map_data.get("terrainSculpt", {}))
	var top_doc: float = doc._sculpt_support().top_surface_at(6.0, 6.0)
	var top_reload: float = reloaded.top_surface_at(6.0, 6.0)
	_assert("mountain_serialize_exact", absf(top_reload - top_doc) < 0.15,
		"relu=%.2f doc=%.2f" % [top_reload, top_doc])

## Brosses « famille but » : Scrape n'abaisse que les hauts, Fill ne relève
## que les bas, Pinch attire vers la hauteur centrale.
func _test_scrape_fill_pinch() -> void:
	var field = FieldScript.new(_flat_heights(), W, H, [], {})
	# Une butte ET une cuvette voisines.
	field.sculpt_stamp(Vector3(5.0, 0.5, 6.0), 1.5, 0.9)
	field.sculpt_stamp(Vector3(8.5, 0.5, 6.0), 1.5, -0.9)
	var hill0: float = field.top_surface_at(5.0, 6.0)
	var pit0: float = field.top_surface_at(8.5, 6.0)
	# Raboter la butte vers 0.9 : le sommet descend, la cuvette ne bouge pas.
	field.sculpt_scrape(Vector3(5.0, hill0, 6.0), 1.6, 0.9, 0.8)
	var hill1: float = field.top_surface_at(5.0, 6.0)
	var pit1: float = field.top_surface_at(8.5, 6.0)
	_assert("scrape_lowers_top", hill1 < hill0 - 0.25, "avant=%.2f apres=%.2f" % [hill0, hill1])
	_assert("scrape_keeps_pit", absf(pit1 - pit0) < 0.01, "%.2f -> %.2f" % [pit0, pit1])
	# Remplir la cuvette vers 0.9 : elle remonte, la butte ne bouge pas.
	field.sculpt_fill(Vector3(8.5, pit0, 6.0), 1.6, 0.9, 0.8)
	var hill2: float = field.top_surface_at(5.0, 6.0)
	var pit2: float = field.top_surface_at(8.5, 6.0)
	_assert("fill_raises_pit", pit2 > pit0 + 0.25, "avant=%.2f apres=%.2f" % [pit0, pit2])
	_assert("fill_keeps_top", absf(hill2 - hill1) < 0.01, "%.2f -> %.2f" % [hill1, hill2])
	# Pincer sur la butte : le pourtour converge vers la hauteur centrale.
	var ring0: float = field.top_surface_at(3.8, 6.0)
	field.sculpt_pinch(Vector3(5.0, field.top_surface_at(5.0, 6.0), 6.0), 1.4, 0.8)
	var ring1: float = field.top_surface_at(3.8, 6.0)
	var center_h: float = field.top_surface_at(5.0, 6.0)
	_assert("pinch_pulls_rail", absf(ring1 - center_h) < absf(ring0 - center_h),
		"avant=%.2f apres=%.2f (centre=%.2f)" % [ring0, ring1, center_h])

## Noyaux : Argile (plateau) dépose plus franc au centre ; Bandes d'argile
## (rectangle) s'étirent le long de l'orientation.
func _test_clay_kernels() -> void:
	var clay_f = FieldScript.new(_flat_heights(), W, H, [], {})
	clay_f.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.6, 0.6, 1)
	var clay_c: float = clay_f.top_surface_at(6.0, 6.0)
	var clay_e: float = clay_f.top_surface_at(6.0, 7.3)
	_assert("clay_flat_top", clay_c > clay_e + 0.25, "centre=%.2f bord=%.2f" % [clay_c, clay_e])
	# Bandes orientées : plus de matière le long de l'axe (angle 0 = axe X).
	var strips = FieldScript.new(_flat_heights(), W, H, [], {})
	strips.sculpt_clay_strips(Vector3(6.0, 0.5, 6.0), 1.6, 0.6, 0.0)
	var along: float = strips.top_surface_at(7.2, 6.0)
	var across: float = strips.top_surface_at(6.0, 7.2)
	_assert("strips_anisotropic", along > across + 0.15,
		"le long=%.2f travers=%.2f" % [along, across])

## Couche : la surface atteint la cible mais ne la dépasse jamais.
func _test_layer_cap() -> void:
	var field = FieldScript.new(_flat_heights(), W, H, [], {})
	for _i in range(5):
		field.sculpt_layer(Vector3(6.0, 0.5, 6.0), 1.5, 1.1, 0.9)
	var top: float = field.top_surface_at(6.0, 6.0)
	_assert("layer_caps_at_target", absf(top - 1.1) < 0.03, "h=%.2f" % top)

## Brosses de déformation : Grab déplace la butte, Inflate l'élargit, Blob
## gonfle le volume, Snake étire le long du geste, Élastique tire le centre.
func _test_deform_brushes() -> void:
	var g = FieldScript.new(_flat_heights(), W, H, [], {})
	g.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.6, 0.8)
	var h0: float = g.top_surface_at(6.0, 6.0)
	g.sculpt_warp(Vector3(6.0, 0.5, 6.0), 1.6, Vector3(1.2, 0.0, 0.0), 0)
	var peak_x: float = _profile_peak_x(g, 6.0, 2.0, 10.0)
	_assert("grab_moves_peak", peak_x > 6.6, "pic_x=%.2f" % peak_x)
	_assert("grab_keeps_height", g.top_surface_at(peak_x, 6.0) > h0 - 0.25)
	# Inflate : la butte s'élargit.
	var inf = FieldScript.new(_flat_heights(), W, H, [], {})
	inf.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.4, 0.8)
	var w0: float = _width_at_half(inf, 6.0, 6.0)
	inf.sculpt_inflate(Vector3(6.0, 0.5, 6.0), 1.6, 0.5)
	var w1: float = _width_at_half(inf, 6.0, 6.0)
	_assert("inflate_widens", w1 > w0 + 0.2, "%.2f -> %.2f" % [w0, w1])
	# Blob : le volume gonfle (le sommet monte).
	var bl = FieldScript.new(_flat_heights(), W, H, [], {})
	bl.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.4, 0.8)
	var bh0: float = bl.top_surface_at(6.0, 6.0)
	bl.sculpt_blob(Vector3(6.0, 0.5, 6.0), 1.6, 0.5)
	_assert("blob_grows", bl.top_surface_at(6.0, 6.0) > bh0 + 0.15,
		"%.2f -> %.2f" % [bh0, bl.top_surface_at(6.0, 6.0)])
	# Snake : la matière s'étire le long du segment [anchor → centre].
	var sn = FieldScript.new(_flat_heights(), W, H, [], {})
	sn.sculpt_stamp(Vector3(5.0, 0.5, 6.0), 1.2, 0.8)
	sn.sculpt_snake(Vector3(7.4, 0.5, 6.0), 1.2,
		Vector3(2.2, 0.0, 0.0), Vector3(5.2, 0.5, 6.0))
	_assert("snake_pulls", sn.top_surface_at(7.0, 6.0) > 0.65,
		"h=%.2f" % sn.top_surface_at(7.0, 6.0))
	# Élastique : le centre bouge plus que les bords.
	var el = FieldScript.new(_flat_heights(), W, H, [], {})
	el.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.6, 0.8)
	el.sculpt_warp(Vector3(6.0, 0.5, 6.0), 1.6, Vector3(1.4, 0.0, 0.0), 2)
	_assert("elastic_moves", el.top_surface_at(7.0, 6.0) > el.top_surface_at(5.2, 6.0),
		"centre=%.2f bord=%.2f" % [el.top_surface_at(7.0, 6.0), el.top_surface_at(5.2, 6.0)])

## Dernière famille : Dessin net (plus étroit que Draw), Bords (lissage
## latéral), Simplifier (détail réduit), Pivoter (le pic tourne), Drapé (les
## bosses s'affaissent).
func _test_family3_brushes() -> void:
	# Dessin net : crête plus fine qu'un Draw à force égale.
	var sharp = FieldScript.new(_flat_heights(), W, H, [], {})
	sharp.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.5, 0.6, 3)
	var round_f = FieldScript.new(_flat_heights(), W, H, [], {})
	round_f.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.5, 0.6)
	var ws: float = _width_at_half(sharp, 6.0, 6.0)
	var wr: float = _width_at_half(round_f, 6.0, 6.0)
	_assert("sharp_narrower", ws < wr - 0.3, "net=%.2f rond=%.2f" % [ws, wr])
	# Bords : le lissage est latéral (la hauteur du pic est bien conservée).
	var bord = FieldScript.new(_flat_heights(), W, H, [], {})
	bord.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.5, 0.8)
	var bh: float = bord.top_surface_at(6.0, 6.0)
	bord.sculpt_boundary(Vector3(6.0, 0.5, 6.0), 1.8)
	_assert("boundary_keeps_height", absf(bord.top_surface_at(6.0, 6.0) - bh) < 0.12,
		"%.2f -> %.2f" % [bh, bord.top_surface_at(6.0, 6.0)])
	# Simplifier : le détail diminue (variation du profil).
	var rough = FieldScript.new(_flat_heights(), W, H, [], {})
	rough.sculpt_stamp(Vector3(5.0, 0.5, 6.0), 1.2, 0.6)
	rough.sculpt_stamp(Vector3(6.6, 0.5, 6.0), 1.2, -0.6)
	var v0: float = _variation(rough, 4.0, 7.5, 6.0)
	rough.sculpt_simplify(Vector3(6.0, 0.5, 6.0), 2.2)
	_assert("simplify_reduces", _variation(rough, 4.0, 7.5, 6.0) < v0 * 0.8,
		"avant=%.2f apres=%.2f" % [v0, _variation(rough, 4.0, 7.5, 6.0)])
	# Pivoter : le relief d'appoint tourne autour du centre (position 2D).
	var pose = FieldScript.new(_flat_heights(), W, H, [], {})
	pose.sculpt_stamp(Vector3(7.0, 0.5, 6.0), 1.0, 0.8)
	var peak0 := _peak_2d(pose, 4.5, 7.5, 4.5, 7.5)
	pose.sculpt_pose(Vector3(6.0, 0.5, 6.0), 1.8, 1.2)
	var peak1 := _peak_2d(pose, 4.5, 7.5, 4.5, 7.5)
	_assert("pose_rotates", (peak1 - peak0).length() > 0.4,
		"%s -> %s" % [str(peak0), str(peak1)])
	# Drapé : les bosses s'affaissent.
	var sag = FieldScript.new(_flat_heights(), W, H, [], {})
	sag.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.4, 0.8)
	var sh: float = sag.top_surface_at(6.0, 6.0)
	sag.sculpt_cloth(Vector3(6.0, 0.5, 6.0), 1.6, 0.8)
	_assert("cloth_sags", sag.top_surface_at(6.0, 6.0) < sh - 0.08,
		"%.2f -> %.2f" % [sh, sag.top_surface_at(6.0, 6.0)])

## Position 2D du pic dans une zone.
func _peak_2d(field, x0: float, x1: float, z0: float, z1: float) -> Vector2:
	var best := Vector2(x0, z0)
	var best_v := -INF
	var z := z0
	while z <= z1:
		var x := x0
		while x <= x1:
			var v: float = field.top_surface_at(x, z)
			if v > best_v:
				best_v = v
				best = Vector2(x, z)
			x += 0.25
		z += 0.25
	return best

## Position du pic le long de z0 entre x0 et x1.
func _profile_peak_x(field, z0: float, x0: float, x1: float) -> float:
	var best_x := x0
	var best := -INF
	var x := x0
	while x <= x1:
		var v: float = field.top_surface_at(x, z0)
		if v > best:
			best = v
			best_x = x
		x += 0.25
	return best_x

## Largeur à mi-hauteur d'une butte centrée en (cx, cz).
func _width_at_half(field, cx: float, cz: float) -> float:
	var peak: float = field.top_surface_at(cx, cz)
	var half := 0.5 + (peak - 0.5) * 0.5
	var left := cx
	while left > cx - 4.0 and field.top_surface_at(left, cz) > half:
		left -= 0.1
	var right := cx
	while right < cx + 4.0 and field.top_surface_at(right, cz) > half:
		right += 0.1
	return right - left

## Dégradés (falloff) façon Blender : Constant > Doux > Net en largeur à
## mi-hauteur. Auto-lissage : le pourtour du tampon est lissé dans le même undo.
func _test_falloff_and_autosmooth() -> void:
	var const_f = FieldScript.new(_flat_heights(), W, H, [], {})
	const_f.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.5, 0.6, 0, 0.0, 5)
	var smooth_f = FieldScript.new(_flat_heights(), W, H, [], {})
	smooth_f.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.5, 0.6, 0, 0.0, 0)
	var sharp_f = FieldScript.new(_flat_heights(), W, H, [], {})
	sharp_f.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.5, 0.6, 0, 0.0, 3)
	var wc: float = _width_at_half(const_f, 6.0, 6.0)
	var ws: float = _width_at_half(smooth_f, 6.0, 6.0)
	var wn: float = _width_at_half(sharp_f, 6.0, 6.0)
	_assert("falloff_order", wc > ws + 0.2 and ws > wn + 0.2,
		"constant=%.2f doux=%.2f net=%.2f" % [wc, ws, wn])
	var rough = FieldScript.new(_flat_heights(), W, H, [], {})
	rough.sculpt_stamp(Vector3(5.0, 0.5, 6.0), 1.1, 0.6)
	rough.sculpt_stamp(Vector3(6.4, 0.5, 6.0), 1.1, -0.6)
	var v0: float = _variation(rough, 4.0, 7.4, 6.0)
	rough.sculpt_stamp(Vector3(6.0, 0.5, 6.0), 1.8, 0.05, 0, 0.0, 0, 1.0)
	_assert("autosmooth_reduces", _variation(rough, 4.0, 7.4, 6.0) < v0 * 0.9,
		"avant=%.2f apres=%.2f" % [v0, _variation(rough, 4.0, 7.4, 6.0)])

## Variation du profil (somme des |différences|) — rugosité.
func _variation(field, x0: float, x1: float, z0: float) -> float:
	var prof := _profile(field, x0, x1, z0)
	var total := 0.0
	for i in range(1, prof.size()):
		total += absf(float(prof[i]) - float(prof[i - 1]))
	return total

func _test_doc_undo_serialize() -> void:
	var md = get_root().get_node("MapData")
	var base: Dictionary = md.create_complex_map("Test sculpt", "general", "local", W, H)
	var doc = DocScript.new()
	doc.load_map(base)
	_assert("doc_sculpt_default", doc.map_data.get("terrainSculpt") is Dictionary)
	doc.sculpt_stamp(Vector3(5.0, 0.5, 5.0), 1.5, 0.5, "Remblai")
	doc.sculpt_stamp(Vector3(6.5, 0.5, 5.0), 1.5, 0.5, "Remblai")
	_assert("doc_sculpt_stamped", not (doc.map_data.get("terrainSculpt") as Dictionary).is_empty())
	_assert("doc_sculpt_undo_one", doc.undo() and not _sculpt_empty(doc))
	_assert("doc_sculpt_undo_all", doc.undo() and _sculpt_empty(doc))
	_assert("doc_sculpt_redo", doc.redo() and not _sculpt_empty(doc))
	# Sérialisation : aller-retour JSON sans perte.
	var out: Dictionary = doc.to_map_data()
	var json_text := JSON.stringify(out.get("terrainSculpt", {}))
	var parsed = JSON.parse_string(json_text)
	_assert("doc_sculpt_json", parsed is Dictionary and not (parsed as Dictionary).is_empty())
	var doc2 = DocScript.new()
	doc2.load_map(out)
	_assert("doc_sculpt_reload", not _sculpt_empty(doc2))
	doc2.clear_sculpt()
	_assert("doc_sculpt_clear", _sculpt_empty(doc2))
	_assert("doc_sculpt_clear_undo", doc2.undo() and not _sculpt_empty(doc2))

func _sculpt_empty(doc) -> bool:
	var s = doc.map_data.get("terrainSculpt", {})
	return not (s is Dictionary) or (s as Dictionary).is_empty()

func _test_ground_clusters() -> void:
	var heights := _flat_heights(0.3)
	var ground = GroundScript.new()
	get_root().add_child(ground)
	ground.configure(null, W, H, 1.0, true, null, false, [], [], 0.22,
		heights, "terrain3d", [], 1, [], {})
	var plain := _indices(ground)
	# Sculpture d'une butte : le heightfield est découpé, un cluster MC apparaît.
	var field = FieldScript.new(heights, W, H, [], {})
	field.sculpt_stamp(Vector3(6.0, 0.3, 6.0), 2.2, 1.2)
	ground.set_terrain_sculpt(field.get_sculpt())
	_assert("ground_sculpt_cluster", ground.get_carve_cluster_count() >= 1,
		"n=%d" % ground.get_carve_cluster_count())
	_assert("ground_sculpt_cut", _indices(ground) < plain,
		"n=%d plain=%d" % [_indices(ground), plain])
	# Le sommet sculpté est visible depuis le dessus (le déplacement est maximal
	# à la hauteur du tampon : la butte s'élève d'environ la force du tampon).
	var top: float = ground.get_carve_field().top_surface_at(6.0, 6.0)
	_assert("ground_sculpt_top", top > 0.85, "h=%.3f" % top)
	ground.queue_free()
	await process_frame

func _indices(ground) -> int:
	var mesh = ground._mesh_instance.mesh
	if mesh == null or mesh.get_surface_count() == 0:
		return -1
	var idx = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
	return idx.size() if idx != null else -1

func _assert(name: String, cond: bool, detail: String = "") -> void:
	if not cond:
		_failed = true
		print("  [FAIL] %s %s" % [name, detail])
