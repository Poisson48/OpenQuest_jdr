extends RefCounted
class_name EditorToolHandlers

## Dispatch des actions de création d'éléments par outil.
##
## Chaque handler crée un élément via `MapEditDocument.add_element()`.
## Extraite de `map_complex_editor.gd`.

const DocumentScript := preload("res://scripts/maps/editor/map_edit_document.gd")
const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")
const MapEffectPresetsScript := preload("res://scripts/maps/map_effect_presets.gd")
const AssetLibraryScript := preload("res://scripts/maps/map_asset_library.gd")
const MapRenderStyleScript := preload("res://scripts/maps/map_render_style.gd")

# --- Options courantes (synchronisées par l'éditeur principal) -----------------
var token_label: String = ""
var token_size: float = 1.0
var member_index: int = 0
var marker_type: String = "npc"
var effect_preset: String = "fire"
var effect_radius: float = 1.0
var zone_radius: float = 1.5
var zone_label: String = "Zone"
var area_category: String = "building"
var area_label: String = ""
var prop_asset: String = ""
var prop_size: float = 2.0
var prop_standing: bool = true
var prop_rotation: float = 0.0
var light_place_radius: float = 3.0

# --- Callbacks injectés --------------------------------------------------------
var on_status: Callable = Callable()
var on_right_tab: Callable = Callable()

## Dispatch principal : place l'élément correspondant à l'outil courant.
func place_pose_element(doc, tool_id: String, grid: Vector2) -> void:
	match tool_id:
		ToolsScript.TOKEN:
			create_token(doc, grid)
		ToolsScript.MARKER:
			create_marker(doc, grid)
		ToolsScript.EFFECT:
			create_effect(doc, grid)
		ToolsScript.ZONE:
			create_circle_zone(doc, grid)
		ToolsScript.NOTE:
			create_note(doc, grid)
		ToolsScript.LIGHT:
			create_light(doc, grid)
		ToolsScript.PROP:
			create_prop(doc, grid)

## Crée un token joueur/PNJ.
func create_token(doc, grid: Vector2) -> void:
	var label := token_label
	if label.is_empty():
		label = "Token %d" % (doc.count_of_kind(DocumentScript.KIND_TOKEN) + 1)
	var color: String = str(MapData.MEMBER_COLOR_HEX[member_index % MapData.MEMBER_COLOR_HEX.size()])
	var emoji: String = str(MapData.MEMBER_PLAYER_EMOJIS_GENERAL[member_index % MapData.MEMBER_PLAYER_EMOJIS_GENERAL.size()])
	var portrait := _default_token_portrait()
	var id: String = doc.add_element({
		"x": grid.x, "y": grid.y,
		"w": token_size, "h": token_size,
		"tokenKind": "member",
		"memberId": "editor-mock-%d" % member_index,
		"memberIndex": member_index,
		"label": label,
		"emoji": emoji,
		"color": color,
		"image": portrait,
		"scale": maxf(token_size, 1.0),
		"layer": 4,
	}, DocumentScript.KIND_TOKEN, "Token")
	doc.select_only(id)

## Crée un marqueur narratif (PNJ, indice, danger…).
func create_marker(doc, grid: Vector2) -> void:
	var id: String = doc.add_element({
		"x": grid.x, "y": grid.y,
		"markerType": marker_type,
		"label": MapData.get_marker_label(marker_type),
		"layer": 3,
	}, DocumentScript.KIND_MARKER, "Marqueur")
	doc.select_only(id)

## Crée un effet de particules (feu, fumée, magie, pluie).
func create_effect(doc, grid: Vector2) -> void:
	var preset := MapEffectPresetsScript.get_preset(effect_preset)
	var id: String = doc.add_element({
		"x": grid.x, "y": grid.y,
		"w": effect_radius * 2.0, "h": effect_radius * 2.0,
		"type": "particles",
		"preset": effect_preset,
		"radius": effect_radius,
		"triggered": true,
		"label": str(preset.get("label", effect_preset)),
		"layer": 3,
	}, DocumentScript.KIND_EFFECT, "Effet")
	doc.select_only(id)

## Crée une zone circulaire (sort, piège, aura).
func create_circle_zone(doc, grid: Vector2) -> void:
	var id: String = doc.add_element({
		"x": grid.x, "y": grid.y,
		"shape": "circle",
		"radius": zone_radius,
		"w": zone_radius * 2.0, "h": zone_radius * 2.0,
		"label": zone_label,
		"color": "#c9a227",
		"layer": 3,
	}, DocumentScript.KIND_ZONE, "Zone")
	doc.select_only(id)

## Crée une note textuelle.
func create_note(doc, grid: Vector2) -> void:
	var id: String = doc.add_element({
		"x": grid.x, "y": grid.y,
		"label": "Note",
		"text": "",
		"layer": 5,
	}, DocumentScript.KIND_NOTE, "Note")
	doc.select_only(id)
	on_right_tab.call(0)

## Crée une source lumineuse.
func create_light(doc, grid: Vector2) -> void:
	var id: String = doc.add_element({
		"x": grid.x, "y": grid.y,
		"radius": light_place_radius,
		"energy": 1.6,
		"color": "#ffb35c",
		"elevation": 0.6,
		"flicker": true,
		"label": "Lumière",
		"layer": 2,
	}, DocumentScript.KIND_LIGHT, "Lumière")
	doc.select_only(id)
	doc.rebuild_light_reveal_from_lights("Pose lumière")

## Crée un décor (prop) à l'échelle de son asset.
func create_prop(doc, grid: Vector2) -> void:
	if prop_asset.is_empty():
		on_status.call("Choisissez d'abord un décor dans la bibliothèque.")
		return
	var ratio := AssetLibraryScript.aspect_ratio(prop_asset)
	var height := maxf(0.25, prop_size)
	var width := maxf(0.25, height * ratio)
	var asset := AssetLibraryScript.get_asset(prop_asset)
	var standing := prop_standing and not MapRenderStyleScript.prefer_flat_props(doc.map_data)
	var id: String = doc.add_element({
		"x": grid.x, "y": grid.y,
		"w": width, "h": height,
		"asset": prop_asset,
		"standing": standing,
		"billboard": standing,
		"lit": false,
		"elevation": 0.0,
		"label": str(asset.get("name", prop_asset.get_file().get_basename())),
		"layer": 1,
		"display": {"rotation": prop_rotation},
	}, DocumentScript.KIND_PROP, "Décor")
	doc.select_only(id)

## Retourne le portrait par défaut pour les tokens.
func _default_token_portrait() -> String:
	var known: Array = MapData.list_token_images()
	if not known.is_empty():
		return str(known[0])
	var shipped := "res://assets/portraits/voleur_kael.png"
	if ResourceLoader.exists(shipped) or FileAccess.file_exists(ProjectSettings.globalize_path(shipped)):
		var imported := MapData.import_token_image(ProjectSettings.globalize_path(shipped))
		return imported if not imported.is_empty() else shipped
	return ""
