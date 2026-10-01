extends Node3D
class_name TableEnvironment3D

## Décor « table de taverne » : la carte devient le plan de jeu **posé sur la
## table**, et la salle entoure le plateau (chaises, sol, murs, suspension,
## bougies). Tout est construit en code, comme les autres calques 3D.
##
## Repères monde : la carte occupe [0..extent.x] × [0..extent.y] à y=0
## (cf. `map_ground_3d.gd`). Le plateau affleure juste en dessous (y=-0.02),
## une moulure borde le plan de jeu, le sol est à `TABLE_DROP` plus bas.
##
## Textures optionnelles (générées via Gemini — `tools/generate_tabletop_gemini.py`) :
## `res://assets/tabletop/*.png`. Absentes → matériaux procéduraux bois/feutre.

const TEX_WOOD_TOP := "res://assets/tabletop/table_wood.png"
const TEX_WOOD_TRIM := "res://assets/tabletop/table_trim.png"
const TEX_FLOOR := "res://assets/tabletop/floor_planks.png"
const TEX_WALL := "res://assets/tabletop/wall_plaster.png"
const TEX_FELT := "res://assets/tabletop/felt_rim.png"

## Table réelle (Meshy AI « Ironbound Oak Table ») — remplace le plateau
## procédural quand le modèle est présent. Mise à l'échelle auto sur le
## plan de jeu + marge (voir `_build_table_from_model`).
const TableLoaderScript := preload("res://scripts/maps/table_model_loader.gd")
const MODEL_OBJ := "res://assets/tabletop/models/ironbound_oak_table.obj"
const MODEL_TEX := "res://assets/tabletop/models/ironbound_oak_table.png"

const SEAT_LABELS := ["Place Sud", "Place Est", "Place Nord", "Place Ouest"]
const TABLE_DROP := 2.6      # plateau → sol (hauteur de table)
const TOP_THICK := 0.45      # épaisseur du plateau
const TOP_GAP := 0.02        # la carte flotte au-dessus du bois (anti z-fight)
const RIM_HEIGHT := 0.14     # hauteur de la moulure autour du plan de jeu
const ROOM_LIFT := 9.0       # hauteur de plafond au-dessus du sol
const CHAIR_SEAT := 1.55     # hauteur d'assise au-dessus du sol

var _extent := Vector2.ZERO
var _margin := 1.2
var _floor_y := -2.6
var _has_model := false
## Empreinte du plateau en XZ monde (position = x/z, size = w/d) — sert aux
## zones de lancer des dés (les « creux » / rectangles noirs) et aux murets.
var _top_rect := Rect2()
## Échelle du mobilier (chaises, déco) relative à la hauteur de table :
## 1.0 pour le plateau procédural, suit le modèle réel sinon.
var _furn := 1.0
var _chairs: Array = []
var _active_seat := -1
## Libellés par place (« Kael — joueur », « MJ »…), posés par la session.
var _seat_labels: Array = []

var _mat_top: StandardMaterial3D
var _mat_trim: StandardMaterial3D
var _mat_felt: StandardMaterial3D
var _mat_floor: StandardMaterial3D
var _mat_wall: StandardMaterial3D
var _mat_wall_wood: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _mat_candle: StandardMaterial3D
var _mat_flame: StandardMaterial3D

# ===========================================================================
# Construction
# ===========================================================================

## `map_extent` : étendue monde du plan de jeu (cf. MapGround3D.get_map_extent).
func configure(map_extent: Vector2) -> void:
	_extent = Vector2(maxf(map_extent.x, 1.0), maxf(map_extent.y, 1.0))
	_margin = clampf(minf(_extent.x, _extent.y) * 0.10, 0.8, 2.4)
	_top_rect = playfield_rim_rect()
	_active_seat = -1
	_chairs.clear()
	for child in get_children():
		child.queue_free()
	_build_materials()
	# Table : modèle 3D réel si présent, sinon plateau procédural.
	_has_model = _build_table_from_model()
	if not _has_model:
		_floor_y = -TOP_GAP - TOP_THICK - TABLE_DROP
		_build_table_procedural()
	_furn = clampf((-TOP_GAP - _floor_y) / (TOP_THICK + TABLE_DROP), 0.5, 3.5)
	_build_chairs()
	_build_room()
	_build_lights()
	_build_decor()
	_build_collision()

func table_rect() -> Rect2:
	# Plan de jeu (la carte) — repères monde au sol.
	return Rect2(Vector2.ZERO, _extent)

func playfield_rim_rect() -> Rect2:
	# Bordure bois autour du plan de jeu.
	return Rect2(Vector2(-_margin, -_margin), _extent + Vector2(_margin, _margin) * 2.0)

func table_size_with_margin() -> Vector2:
	return _extent + Vector2(_margin, _margin) * 2.0

func table_center() -> Vector3:
	return Vector3(_extent.x * 0.5, 0.0, _extent.y * 0.5)

func seat_count() -> int:
	return SEAT_LABELS.size()

## Libellés des places (index 0..3) — ex. prénoms des joueurs + MJ.
func set_seat_labels(labels: Array) -> void:
	_seat_labels = labels.duplicate()

func seat_label(index: int) -> String:
	if index >= 0 and index < _seat_labels.size():
		var custom := str(_seat_labels[index]).strip_edges()
		if not custom.is_empty():
			return custom
	if index < 0 or index >= SEAT_LABELS.size():
		return ""
	return SEAT_LABELS[index]

## Cache la chaise de la place occupée (on ne se regarde pas soi-même).
func set_active_seat(index: int) -> void:
	_active_seat = index
	for i in range(_chairs.size()):
		var chair: Node3D = _chairs[i]
		if chair != null and is_instance_valid(chair):
			chair.visible = i != _active_seat

# --------------------------------------------------------------------------
# Matériaux
# --------------------------------------------------------------------------

func _build_materials() -> void:
	_mat_top = _material(Color(0.36, 0.24, 0.13), 0.55, TEX_WOOD_TOP, 2.0)
	_mat_trim = _material(Color(0.26, 0.16, 0.08), 0.5, TEX_WOOD_TRIM, 3.0)
	_mat_felt = _material(Color(0.20, 0.10, 0.09), 0.95, TEX_FELT, 1.0)
	_mat_floor = _material(Color(0.17, 0.12, 0.08), 0.85, TEX_FLOOR, 8.0)
	_mat_wall = _material(Color(0.24, 0.18, 0.13), 0.9, TEX_WALL, 4.0)
	_mat_wall_wood = _material(Color(0.16, 0.10, 0.06), 0.7, TEX_WOOD_TRIM, 4.0)
	_mat_dark = _material(Color(0.07, 0.05, 0.04), 0.9, "", 1.0)
	_mat_candle = _material(Color(0.85, 0.76, 0.55), 0.6, "", 1.0)
	_mat_flame = StandardMaterial3D.new()
	_mat_flame.albedo_color = Color(1.0, 0.72, 0.32)
	_mat_flame.emission_enabled = true
	_mat_flame.emission = Color(1.0, 0.65, 0.25)
	_mat_flame.emission_energy_multiplier = 2.4

func _material(color: Color, roughness: float, tex_path: String, repeat: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.0
	if not tex_path.is_empty():
		var tex := _load_png_texture(tex_path)
		if tex != null:
			mat.albedo_texture = tex
			mat.albedo_color = Color.WHITE
			mat.uv1_triplanar = true
			mat.uv1_scale = Vector3(repeat, repeat, repeat)
	return mat

## Charge une texture optionnelle : via le cache d'import Godot, sinon lecture
## brute du PNG (run CLI sans import préalable).
func _load_png_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res: Texture2D = load(path)
		if res != null:
			return res
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return null
	var img := Image.load_from_file(abs_path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)

# --------------------------------------------------------------------------
# Géométrie
# --------------------------------------------------------------------------

## Table réelle (modèle Meshy) : remplace le plateau procédural.
## Échelle uniforme couvrant le plan de jeu + marge ; le dessus affleure sous
## la carte (y=-TOP_GAP) et les pieds posent sur le sol (pilote `_floor_y`).
func _build_table_from_model() -> bool:
	var mesh := TableLoaderScript.load_obj(MODEL_OBJ)
	if mesh == null:
		return false
	var aabb := TableLoaderScript.mesh_aabb(mesh)
	if aabb.size.x < 0.001 or aabb.size.z < 0.001:
		return false
	var want := table_size_with_margin()
	var s := maxf(want.x / aabb.size.x, want.y / aabb.size.z)
	var root := Node3D.new()
	root.name = "Table"
	add_child(root)
	var mi := MeshInstance3D.new()
	mi.name = "IronboundOakTable"
	mi.mesh = mesh
	mi.scale = Vector3(s, s, s)
	var mat := StandardMaterial3D.new()
	var tex := TableLoaderScript.load_texture(MODEL_TEX)
	if tex != null:
		mat.albedo_texture = tex
	else:
		mat.albedo_color = Color(0.30, 0.19, 0.10)
	mat.roughness = 0.55
	mat.metallic = 0.0
	# Winding OBJ garanti côté double face.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var c := table_center()
	var top_local := aabb.position.y + aabb.size.y
	mi.position = Vector3(
		c.x - (aabb.position.x + aabb.size.x * 0.5) * s,
		-TOP_GAP - top_local * s,
		c.z - (aabb.position.z + aabb.size.z * 0.5) * s
	)
	# Les pieds du modèle déterminent le niveau du sol (chaises, salle).
	_floor_y = mi.position.y + aabb.position.y * s
	_top_rect = Rect2(
		Vector2(c.x - aabb.size.x * s * 0.5, c.z - aabb.size.z * s * 0.5),
		Vector2(aabb.size.x * s, aabb.size.z * s)
	)
	root.add_child(mi)
	return true

func _build_table_procedural() -> void:
	var root := Node3D.new()
	root.name = "Table"
	add_child(root)
	var ts := table_size_with_margin()
	var cx := _extent.x * 0.5
	var cz := _extent.y * 0.5

	# Plateau : le bois affleure sous la carte.
	_box(root, Vector3(ts.x, TOP_THICK, ts.y),
		Vector3(cx, -TOP_GAP - TOP_THICK * 0.5, cz), _mat_top)

	# Moulure : bordure bois autour du plan de jeu (effet « plan posé »).
	var rim_w := _margin * 0.42
	var rim_y := -TOP_GAP + RIM_HEIGHT * 0.5
	var rim_out := playfield_rim_rect()
	# Bandes nord/sud (le long de X).
	_box(root, Vector3(rim_out.size.x + rim_w * 2.0, RIM_HEIGHT + TOP_GAP, rim_w),
		Vector3(cx, rim_y, -rim_w * 0.5), _mat_trim)
	_box(root, Vector3(rim_out.size.x + rim_w * 2.0, RIM_HEIGHT + TOP_GAP, rim_w),
		Vector3(cx, rim_y, _extent.y + rim_w * 0.5), _mat_trim)
	# Bandes est/ouest (le long de Z).
	_box(root, Vector3(rim_w, RIM_HEIGHT + TOP_GAP, rim_out.size.y),
		Vector3(-rim_w * 0.5, rim_y, cz), _mat_trim)
	_box(root, Vector3(rim_w, RIM_HEIGHT + TOP_GAP, rim_out.size.y),
		Vector3(_extent.x + rim_w * 0.5, rim_y, cz), _mat_trim)

	# Tapis de feutre sous la moulure (liseré sombre autour du plan de jeu).
	_box(root, Vector3(ts.x * 0.995, 0.02, ts.y * 0.995),
		Vector3(cx, -TOP_GAP - TOP_THICK - 0.01, cz), _mat_felt)

	# Pieds.
	var leg := 0.55
	var inset := maxf(_margin + leg * 0.6, 0.9)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var lx: float = cx + sx * (ts.x * 0.5 - inset)
			var lz: float = cz + sz * (ts.y * 0.5 - inset)
			_box(root, Vector3(leg, TABLE_DROP, leg),
				Vector3(lx, -TOP_GAP - TOP_THICK - TABLE_DROP * 0.5, lz), _mat_trim)
	# Traverse basse entre les pieds (côté long).
	_box(root, Vector3(ts.x - inset * 2.0, 0.22, 0.22),
		Vector3(cx, -TABLE_DROP * 0.72, cz - ts.y * 0.5 + inset), _mat_trim)
	_box(root, Vector3(ts.x - inset * 2.0, 0.22, 0.22),
		Vector3(cx, -TABLE_DROP * 0.72, cz + ts.y * 0.5 - inset), _mat_trim)

func _build_chairs() -> void:
	var root := Node3D.new()
	root.name = "Chairs"
	add_child(root)
	var cx := _extent.x * 0.5
	var cz := _extent.y * 0.5
	var seat := Vector2(1.5, 1.5) * _furn
	var gap := _margin + 0.9 * _furn
	# 0=sud, 1=est, 2=nord, 3=ouest (mêmes yaw que les places caméra).
	# yaw place le dossier (+Z local) à l'opposé de la table.
	var places := [
		{"pos": Vector3(cx, 0.0, _extent.y + gap), "yaw": 0.0},
		{"pos": Vector3(_extent.x + gap, 0.0, cz), "yaw": 90.0},
		{"pos": Vector3(cx, 0.0, -gap), "yaw": 180.0},
		{"pos": Vector3(-gap, 0.0, cz), "yaw": -90.0},
	]
	for i in range(places.size()):
		var p: Dictionary = places[i]
		var chair := _make_chair(seat)
		chair.position = p["pos"]
		chair.rotation_degrees = Vector3(0.0, float(p["yaw"]), 0.0)
		root.add_child(chair)
		_chairs.append(chair)

func _make_chair(seat: Vector2) -> Node3D:
	var chair := Node3D.new()
	chair.name = "Chair"
	var floor_y := _floor_y
	var k := _furn
	var seat_y := CHAIR_SEAT * k + floor_y
	# Assise.
	_box(chair, Vector3(seat.x, 0.14 * k, seat.y), Vector3(0.0, seat_y, 0.0), _mat_trim)
	# Dossier (vers l'extérieur : +Z local = derrière).
	_box(chair, Vector3(seat.x, 1.15 * k, 0.12 * k),
		Vector3(0.0, seat_y + 0.6 * k, seat.y * 0.5), _mat_trim)
	# Pieds.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(chair, Vector3(0.12 * k, CHAIR_SEAT * k, 0.12 * k),
				Vector3(sx * (seat.x * 0.5 - 0.1 * k), floor_y + CHAIR_SEAT * k * 0.5, sz * (seat.y * 0.5 - 0.1 * k)),
				_mat_dark)
	return chair

func _build_room() -> void:
	var root := Node3D.new()
	root.name = "Room"
	add_child(root)
	var ts := table_size_with_margin()
	var cx := _extent.x * 0.5
	var cz := _extent.y * 0.5
	var floor_y := _floor_y
	var ref := maxf(ts.x, ts.y)
	# La salle doit englober TOUTES les positions caméra (orbite + zoom
	# arrière) — sinon on regarde le dos des murs depuis l'extérieur.
	var reach := ref * 2.6 + 4.0
	var room := ts + Vector2(reach, reach) * 2.0
	var wall_top := maxf(ROOM_LIFT, ref * 1.1)

	# Sol (planches).
	_box(root, Vector3(room.x, 0.2, room.y), Vector3(cx, floor_y - 0.1, cz), _mat_floor)

	# Murs (pas de plafond : au-dessus reste sombre, la caméra passe au-dessus).
	var shell_h := wall_top - floor_y
	_box(root, Vector3(room.x + 1.0, shell_h, 0.4),
		Vector3(cx, floor_y + shell_h * 0.5, -room.y * 0.5 - 0.2), _mat_wall)
	_box(root, Vector3(room.x + 1.0, shell_h, 0.4),
		Vector3(cx, floor_y + shell_h * 0.5, room.y * 0.5 + 0.2), _mat_wall)
	_box(root, Vector3(0.4, shell_h, room.y + 1.0),
		Vector3(-room.x * 0.5 - 0.2, floor_y + shell_h * 0.5, cz), _mat_wall)
	_box(root, Vector3(0.4, shell_h, room.y + 1.0),
		Vector3(room.x * 0.5 + 0.2, floor_y + shell_h * 0.5, cz), _mat_wall)

	# Lambris bois le long des murs (côté intérieur).
	var band := 1.4 * _furn
	for offset: Vector3 in [
		Vector3(cx, floor_y + band * 0.5, -room.y * 0.5 + 0.1),
		Vector3(cx, floor_y + band * 0.5, room.y * 0.5 - 0.1),
		Vector3(-room.x * 0.5 + 0.1, floor_y + band * 0.5, cz),
		Vector3(room.x * 0.5 - 0.1, floor_y + band * 0.5, cz),
	]:
		var horizontal := absf(offset.z - cz) > absf(offset.x - cx)
		var size := Vector3(room.x, band, 0.15) if horizontal else Vector3(0.15, band, room.y)
		_box(root, size, offset, _mat_wall_wood)

func _build_lights() -> void:
	var root := Node3D.new()
	root.name = "Lights"
	add_child(root)
	var cx := _extent.x * 0.5
	var cz := _extent.y * 0.5

	# Suspension au-dessus de la table : cordage fin + petit abat-jour,
	# volontairement haut et discret (ne doit pas encadrer le plateau).
	var lamp_y := 5.2
	_cyl(root, 0.02, ROOM_LIFT - lamp_y, Vector3(cx, lamp_y + (ROOM_LIFT - lamp_y) * 0.5, cz), _mat_dark)
	_cyl(root, 0.32, 0.3, Vector3(cx, lamp_y, cz), _mat_trim)
	_cyl(root, 0.07, 0.08, Vector3(cx, lamp_y - 0.2, cz), _mat_flame)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(cx, lamp_y - 0.35, cz)
	lamp.light_color = Color(1.0, 0.78, 0.5)
	lamp.light_energy = 5.5
	lamp.omni_range = maxf(ts_hypot(), 8.0)
	lamp.omni_attenuation = 1.1
	lamp.shadow_enabled = true
	root.add_child(lamp)

	# Bougies aux coins du plateau (posées sur le plan de jeu).
	for corner: Vector2 in [Vector2(0.10, 0.10), Vector2(0.90, 0.90)]:
		var px: float = _extent.x * corner.x
		var pz: float = _extent.y * corner.y
		_cyl(root, 0.08, 0.3, Vector3(px, 0.17, pz), _mat_candle)
		_cyl(root, 0.04, 0.08, Vector3(px, 0.36, pz), _mat_flame)
		var glow := OmniLight3D.new()
		glow.position = Vector3(px, 0.5, pz)
		glow.light_color = Color(1.0, 0.62, 0.3)
		glow.light_energy = 1.4
		glow.omni_range = 4.0
		root.add_child(glow)

	# Lueur de cheminée (près du mur sud, ambiance taverne).
	var ts := table_size_with_margin()
	var reach_h := maxf(ts.x, ts.y) * 2.6 + 4.0
	var hearth := OmniLight3D.new()
	hearth.position = Vector3(_extent.x * 0.5, _floor_y + 1.4, _extent.y * 0.5 + ts.y * 0.5 + reach_h - 3.0)
	hearth.light_color = Color(1.0, 0.45, 0.18)
	hearth.light_energy = 3.0
	hearth.omni_range = 10.0
	root.add_child(hearth)

func ts_hypot() -> float:
	return sqrt(pow(table_size_with_margin().x, 2.0) + pow(table_size_with_margin().y, 2.0))

func _build_decor() -> void:
	var root := Node3D.new()
	root.name = "Decor"
	add_child(root)
	var floor_y := _floor_y
	var ts := table_size_with_margin()
	# Tonnelles dans un coin de la salle.
	for offset: Vector2 in [Vector2(1.2, 0.6), Vector2(1.2, 1.4), Vector2(0.7, 1.0)]:
		var bx: float = _extent.x * 0.5 + ts.x * 0.5 + offset.x * _furn
		var bz: float = _extent.y * 0.5 - ts.y * 0.5 - offset.y * _furn
		_cyl(root, 0.45 * _furn, 0.9 * _furn, Vector3(bx, floor_y + 0.45 * _furn, bz), _mat_trim)
	# Un tabouret bas près de la cheminée.
	_box(root, Vector3(1.0, 0.12, 1.0) * _furn,
		Vector3(_extent.x * 0.5 - ts.x * 0.3, floor_y + 0.8 * _furn, _extent.y * 0.5 + ts.y * 0.5 + 3.2 * _furn),
		_mat_trim)

# --------------------------------------------------------------------------
# Dés — creux du plateau (rectangles noirs) et collisions
# --------------------------------------------------------------------------

## Zones de lancer VALIDES : les « creux » (rectangles noirs) du plateau —
## les panneaux des ailerons entre le plan de jeu et le bord de la table.
## Deux creux par aileron large, un par aileron étroit. Rect2 = (x, z).
## On lance où l'on veut ; le lancer ne **compte** que s'il atterrit là.
func dice_zones() -> Array:
	var top := _top_rect
	if top.size.x <= 0.0:
		top = playfield_rim_rect()
	var map_r := Rect2(Vector2.ZERO, _extent)
	var zones: Array = []
	var edge := 0.45   # marge bord de table (moulure fer)
	var gap := 0.35    # séparation entre deux creux
	# Ailerons gauche / droit (en X).
	for x_pair: Array in [
		[top.position.x, map_r.position.x],
		[map_r.end.x, top.end.x],
	]:
		var outer: float = float(x_pair[0]) + edge
		var inner: float = float(x_pair[1]) - 0.05
		if inner - outer < 0.8:
			continue
		var z0 := top.position.y + edge
		var z1 := top.end.y - edge
		var half := (z1 - z0 - gap) * 0.5
		if half < 0.8:
			zones.append(Rect2(outer, z0, inner - outer, z1 - z0))
		else:
			zones.append(Rect2(outer, z0, inner - outer, half))
			zones.append(Rect2(outer, z0 + half + gap, inner - outer, half))
	# Ailerons nord / sud (en Z) s'ils sont assez profonds.
	for z_pair: Array in [
		[top.position.y, map_r.position.y],
		[map_r.end.y, top.end.y],
	]:
		var outer_z: float = float(z_pair[0]) + edge
		var inner_z: float = float(z_pair[1]) - 0.05
		if inner_z - outer_z < 0.8:
			continue
		var x0 := map_r.position.x + gap
		var x1 := map_r.end.x - gap
		var third := (x1 - x0 - gap * 2.0) / 3.0
		if third < 0.8:
			zones.append(Rect2(x0, outer_z, x1 - x0, inner_z - outer_z))
		else:
			for i in range(3):
				zones.append(Rect2(
					x0 + float(i) * (third + gap), outer_z, third, inner_z - outer_z
				))
	return zones

## Un lancer ne compte que si chaque dé repose dans un creux (rectangle noir).
## Tolérance d'un demi-pied de dé : le pion doit être essentiellement posé sur
## le rectangle, sans excès de zèle sur les bords.
func is_on_valid_zone(pos: Vector3) -> bool:
	var p := Vector2(pos.x, pos.z)
	for zone_variant in dice_zones():
		if (zone_variant as Rect2).grow(0.15).has_point(p):
			return true
	return false

## Collisions du plateau : les dés se posent sur le bois et peuvent **tomber
## par terre** (règle : un dé compte s'il finit droit, où qu'il soit) — le sol
## de la salle les rattrape, pas de muret au bord.
func _build_collision() -> void:
	var root := Node3D.new()
	root.name = "TablePhysics"
	add_child(root)
	var top := _top_rect
	if top.size.x <= 0.0:
		top = playfield_rim_rect()
	var cx := top.position.x + top.size.x * 0.5
	var cz := top.position.y + top.size.y * 0.5
	var body := StaticBody3D.new()
	body.name = "TableTop"
	_box_collider(body, Vector3(top.size.x, 0.3, top.size.y), Vector3(cx, -TOP_GAP - 0.15, cz))
	# Sol de la salle (les dés qui tombent de la table s'y posent).
	var reach := maxf(top.size.x, top.size.y) * 2.6 + 4.0
	_box_collider(body, Vector3(top.size.x + reach * 2.0, 0.3, top.size.y + reach * 2.0),
		Vector3(cx, _floor_y - 0.15, cz))
	root.add_child(body)

func _box_collider(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	body.add_child(shape)

# --------------------------------------------------------------------------
# Primitives
# --------------------------------------------------------------------------

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
