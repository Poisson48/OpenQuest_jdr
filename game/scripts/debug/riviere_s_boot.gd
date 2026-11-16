extends Node

## Démo « **Rivière en S** » : une carte 40 × 24 ouverte dans l'éditeur de
## cartes, avec une rivière **sinueuse en forme de S** creusée dans le terrain.
##
## La rivière est créée par les **vrais chemins de l'éditeur** (les mêmes que
## l'outil Eau → Rivière) : `_carve_river_bed()` creuse le lit le long du tracé,
## puis `doc.add_water_body({kind: "river"})` ajoute le cours d'eau (courant,
## largeur, profondeur). L'eau utilise le rendu CS2 : profondeur lisible,
## mousse de rive, reflets, micro-vagues — et le preset qualité « cinéma »
## (ombres des rochers/arbres, sol ancré par AO de contact).
##
## La carte est agrémentée de berges sableuses, de roseaux, de quelques arbres,
## rochers et d'un pont de bois au centre du S.
##
## Lancer (Windows) :
##   .\scripts\play-godot.ps1 res://scenes/debug/riviere_s_boot.tscn

const MAP_NAME := "Rivière en S"
const MAP_WIDTH := 40
const MAP_HEIGHT := 24
const WORLD_ID := "demo-riviere-s"

## Réglages de la rivière (unités cases).
const RIVER_WIDTH := 2.2
const RIVER_BED := 0.45
const RIVER_DEPTH := 0.34
const RIVER_FLOW_SPEED := 0.45
## Amplitude et nombre de méandres : 1.0 = un S complet sur la largeur.
const S_AMPLITUDE := 6.0
const S_PERIODS := 1.0
const PATH_POINTS := 48

## Matières du terrain (MapData.MATERIAL_*).
const MATERIAL_GRASS := 0
const MATERIAL_STONE := 2
const MATERIAL_SAND := 4

var _editor: Control
var _md: Node


func _ready() -> void:
	_md = get_tree().root.get_node("MapData")
	var map := build_map(_md)
	if map.is_empty():
		push_error("[RIVIÈRE S] Impossible de créer la carte.")
		get_tree().quit(1)
		return

	DisplayServer.window_set_title("OpenQuest — Rivière en S (démo eau)")
	_editor = (load("res://scenes/map_editor/map_editor.tscn") as PackedScene).instantiate()
	_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_editor)
	await get_tree().process_frame
	_editor.load_map(map)
	await get_tree().process_frame
	apply_river(_editor)
	await get_tree().process_frame
	if _editor._engine != null:
		_editor._engine.reset_editor_camera()
	# Vue propre : aucun élément sélectionné (pas de gizmo au lancement).
	_editor.doc.clear_selection()
	_editor._set_tool("select")
	_editor._refresh_panels()
	_editor._set_status("Rivière en S — lit creusé, berges sableuses, reflets. Outils : Eau (peindre), Relief (U), Objets (Q), Échap = menu.")
	_add_hint()
	print("[RIVIÈRE S] Démo prête — %d × %d cases, %d points de tracé." % [
		MAP_WIDTH, MAP_HEIGHT, PATH_POINTS])


## Tracé en S : une sinusoïde d'un demi-tour sur la largeur de la carte.
## Renvoie des points `[x, hauteur_monde, y_grille]` (format attendu par
## `_carve_river_bed` et `add_water_body`).
static func build_s_path() -> Array:
	var path: Array = []
	var x0 := 3.0
	var x1 := float(MAP_WIDTH) - 3.0
	var center_y := float(MAP_HEIGHT) * 0.5
	for i in range(PATH_POINTS):
		var t := float(i) / float(PATH_POINTS - 1)
		var x := lerpf(x0, x1, t)
		var y := center_y + sin(t * TAU * S_PERIODS) * S_AMPLITUDE
		path.append([x, 0.0, y])
	return path


## Construit la carte : sol d'herbe, relief plat au cœur, buttes douces dans
## les marges, berges sableuses et lit de pierre le long du S, décor (roseaux,
## arbres, rochers, pont).
static func build_map(md: Node) -> Dictionary:
	if md == null:
		return {}
	for map_variant in md.maps.duplicate():
		if map_variant is Dictionary and str((map_variant as Dictionary).get("worldId", "")) == WORLD_ID:
			md.delete_map(str((map_variant as Dictionary).get("id", "")))
	var map: Dictionary = md.create_complex_map(MAP_NAME, "general", "local",
		MAP_WIDTH, MAP_HEIGHT)
	if map.is_empty():
		return {}
	var path := build_s_path()

	# --- Relief : plat, avec de légères ondulations seulement dans les marges.
	var heights: Array = []
	heights.resize(MAP_WIDTH * MAP_HEIGHT)
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			var in_core := x >= 2 and x <= MAP_WIDTH - 3 and y >= 2 and y <= MAP_HEIGHT - 3
			var value := 0.0
			if not in_core:
				value = 0.10 * sin(float(x) * 0.55) * cos(float(y) * 0.5) + 0.03
			heights[y * MAP_WIDTH + x] = value

	# --- Matières : herbe partout, sable sur les berges, pierre dans le lit.
	var materials: Array = []
	materials.resize(MAP_WIDTH * MAP_HEIGHT)
	materials.fill(MATERIAL_GRASS)
	for y in range(MAP_HEIGHT):
		for x in range(MAP_WIDTH):
			var d := _distance_to_path(Vector2(x + 0.5, y + 0.5), path)
			var idx := y * MAP_WIDTH + x
			if d <= RIVER_WIDTH * 0.5 + 0.35:
				materials[idx] = MATERIAL_STONE
			elif d <= RIVER_WIDTH * 0.5 + 1.65:
				materials[idx] = MATERIAL_SAND

	map["renderStyle"] = "2.5d"
	map["groundMode"] = "terrain3d"
	map["backgroundImage"] = ""
	map["fogEnabled"] = false
	map["lighting"] = {"enabled": true, "preset": "jour", "direction": "nw",
		"intensity": 0.35, "sources": []}
	map["qualityPreset"] = "cinema"
	map["atmosphericFog"] = {"enabled": true, "density": 0.04, "heightDensity": 0.0}
	map["terrainHeights"] = heights
	map["terrainMaterials"] = materials
	map["waterLevel"] = -1.0
	map["waterBodies"] = []
	map["meshes"] = _river_decor(path)
	map["zoneX"] = 0
	map["zoneY"] = 0
	map["zoneW"] = MAP_WIDTH
	map["zoneH"] = MAP_HEIGHT
	map["worldId"] = WORLD_ID
	md.update_map(map)
	return md.get_by_id(str(map.get("id", "")))


## Applique la rivière par les APIs réelles de l'éditeur (lit + corps d'eau),
## puis rafraîchit le terrain. Utilisé par la démo et par le test de capture.
static func apply_river(editor: Control) -> void:
	if editor == null:
		return
	var path := build_s_path()
	editor._water_river_width = RIVER_WIDTH
	editor._water_river_bed = RIVER_BED
	editor._water_river_depth = RIVER_DEPTH
	editor._water_flow_speed = RIVER_FLOW_SPEED
	editor._carve_river_bed(path)
	editor.doc.add_water_body({
		"kind": "river",
		"width": RIVER_WIDTH,
		"flow_speed": RIVER_FLOW_SPEED,
		"depth": RIVER_DEPTH,
		"path": path,
	}, "Rivière en S")
	if editor._engine != null and editor._engine.has_method("refresh_terrain"):
		editor._engine.refresh_terrain(editor.doc.map_data)


## Décor : roseaux le long des berges, arbres et rochers à distance, et un pont
## de bois au centre du S (le cours d'eau est très peu incliné ici : pont plat).
static func _river_decor(path: Array) -> Array:
	var meshes: Array = []
	var reeds := [
		Vector2(7.0, 6.2), Vector2(8.2, 17.4), Vector2(16.5, 4.6),
		Vector2(17.8, 19.6), Vector2(27.0, 6.4), Vector2(28.4, 17.2),
		Vector2(34.0, 8.0), Vector2(34.6, 16.0),
	]
	for i in range(reeds.size()):
		var p: Vector2 = reeds[i]
		meshes.append(_mesh("roseaux_%d" % i, "res://assets/objects3d/vegetation/roseaux.glb",
			p.x, p.y, 1.05, float(i) * 47.0))
	var trees := [
		Vector2(4.5, 4.2), Vector2(6.0, 20.0), Vector2(13.5, 21.0),
		Vector2(21.0, 4.0), Vector2(26.0, 21.0), Vector2(33.0, 4.5),
		Vector2(36.5, 19.5),
	]
	for i in range(trees.size()):
		var p: Vector2 = trees[i]
		var asset := "res://assets/objects3d/vegetation/arbre.glb" if i % 2 == 0 \
			else "res://assets/objects3d/vegetation/arbre_automne.glb"
		meshes.append(_mesh("arbre_%d" % i, asset, p.x, p.y, 1.0, float(i) * 63.0))
	var rocks := [
		Vector2(10.0, 9.0), Vector2(15.0, 16.0), Vector2(24.0, 8.0),
		Vector2(30.0, 15.5),
	]
	for i in range(rocks.size()):
		var p: Vector2 = rocks[i]
		meshes.append(_mesh("rocher_%d" % i, "res://assets/objects3d/terrain/rocher.glb",
			p.x, p.y, 0.9, float(i) * 71.0))
	# Pont de bois au centre du S : le cours d'eau y passe à y ≈ 12.
	meshes.append(_mesh("pont_s", "res://assets/objects3d/props/pont.glb",
		20.6, 12.0, 1.0, 90.0, 2.6, 1.3))
	return meshes


static func _mesh(id: String, asset: String, x: float, y: float, scale_v: float,
		rotation: float, w: float = 1.0, h: float = 1.0) -> Dictionary:
	return {
		"id": id, "kind": "mesh", "x": x, "y": y,
		"w": w, "h": h, "asset": asset,
		"elevation": 0.0, "followTerrain": true, "tiltToTerrain": false,
		"label": id.capitalize(), "layer": 1,
		"display": {"rotation": rotation, "scale": scale_v},
	}


## Distance d'un point de grille au tracé (en cases).
static func _distance_to_path(point: Vector2, path: Array) -> float:
	var best := INF
	for i in range(path.size() - 1):
		var a := Vector2(float(path[i][0]), float(path[i][2]))
		var b := Vector2(float(path[i + 1][0]), float(path[i + 1][2]))
		var ab := b - a
		var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		best = minf(best, point.distance_to(a.lerp(b, t)))
	return best


func _add_hint() -> void:
	var hint := Label.new()
	hint.text = "RIVIÈRE EN S — eau CS2 : lit creusé, profondeur, mousse de rive, reflets · Outil Eau (peindre l'eau) · U = relief · Q = objets 3D · Échap = menu"
	hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hint.offset_left = 200
	hint.offset_right = -420
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_color_override("font_color", Color(1.0, 0.94, 0.80))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("outline_size", 5)
	hint.add_theme_font_size_override("font_size", 14)
	add_child(hint)
