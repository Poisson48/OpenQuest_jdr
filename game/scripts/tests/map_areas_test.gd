extends SceneTree

## Tests des cartes illustrées à plusieurs échelles : lieux nommés, cartes
## enfants, fil d'Ariane et navigation en session (village → place → taverne).

const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")

const K_AREA := "area"
const K_TOKEN := "token"

var DocScript: GDScript
var ComplexEditorScript: GDScript

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	DocScript = load("res://scripts/maps/editor/map_edit_document.gd")
	ComplexEditorScript = load("res://scripts/maps/map_complex_editor.gd")
	var md = get_root().get_node("MapData")
	var gd = get_root().get_node("GameData")

	_test_area_model(md)
	_test_hit_testing(md)
	_test_child_maps(md)
	_test_breadcrumb(md)
	_test_session_navigation(md, gd)
	await _test_editor_area_tool(md)

	if _failed:
		quit(1)
		return
	print("map_areas_test:PASS")
	quit(0)

# ===========================================================================

func _test_area_model(md) -> void:
	var map: Dictionary = md.create_complex_map("Valbois", "general", "local", 40, 32)
	var doc: Variant = DocScript.new()
	doc.load_map(map)

	var id: String = doc.add_element({
		"x": 10.0, "y": 8.0, "w": 6.0, "h": 4.0,
		"label": "Taverne du Cerf", "category": "shop",
	}, K_AREA, "Lieu")
	_assert("area_added", doc.count_of_kind(K_AREA) == 1)

	var area: Dictionary = doc.get_element(id)
	_assert("area_label", str(area.get("label", "")) == "Taverne du Cerf")
	_assert("area_layer", int(area.get("layer", -1)) == 5)

	# Aller-retour de sérialisation : les lieux vivent dans `areas`.
	var snapshot: Dictionary = doc.to_map_data()
	_assert("area_serialised", (snapshot.get("areas", []) as Array).size() == 1)
	_assert("area_kept_label", str((snapshot["areas"][0] as Dictionary).get("label", "")) == "Taverne du Cerf")

	var reloaded: Variant = DocScript.new()
	reloaded.load_map(snapshot)
	_assert("area_roundtrip", reloaded.count_of_kind(K_AREA) == 1)

	# Catégories et icônes.
	_assert("cat_lookup", str(md.area_category("shop").get("label", "")) == "Commerce / Service")
	_assert("cat_fallback", str(md.area_category("inexistante").get("id", "")) == "building")
	_assert("icon_from_category", md.area_icon({"category": "poi"}) == "⭐")
	_assert("icon_explicit", md.area_icon({"category": "poi", "icon": "🍺"}) == "🍺")

	# Un lieu par défaut fait 3 × 3 cases.
	var default_id: String = doc.add_element({"x": 2.0, "y": 2.0}, K_AREA, "Lieu")
	_assert("area_default_size", float(doc.get_element(default_id).get("w", 0)) == 3.0)

func _test_hit_testing(md) -> void:
	var map := {
		"id": "hit-map", "width": 40, "height": 32,
		"areas": [
			{"id": "a-grand", "x": 10.0, "y": 10.0, "w": 20.0, "h": 20.0, "label": "Village"},
			{"id": "a-petit", "x": 10.0, "y": 10.0, "w": 4.0, "h": 4.0, "label": "Place"},
			{"id": "a-rond", "x": 30.0, "y": 10.0, "w": 6.0, "h": 6.0, "shape": "circle", "label": "Bosquet"},
		],
	}
	_assert("hit_none", (md.get_area_at(map, 39.0, 31.0) as Dictionary).is_empty())
	# Le plus petit lieu l'emporte : un lieu imbriqué reste cliquable.
	_assert("hit_smallest", str(md.get_area_at(map, 10.0, 10.0).get("id", "")) == "a-petit")
	_assert("hit_outer", str(md.get_area_at(map, 17.0, 17.0).get("id", "")) == "a-grand")
	_assert("hit_circle_in", str(md.get_area_at(map, 31.0, 10.0).get("id", "")) == "a-rond")
	_assert("hit_circle_out", (md.get_area_at(map, 34.5, 13.5) as Dictionary).is_empty())
	_assert("get_area_by_id", str(md.get_area(map, "a-rond").get("label", "")) == "Bosquet")
	_assert("get_area_missing", (md.get_area(map, "inconnu") as Dictionary).is_empty())

func _test_child_maps(md) -> void:
	var village: Dictionary = md.create_complex_map("Valbois enfants", "general", "local", 40, 32)
	var village_id: String = village.get("id", "")
	village["areas"] = [
		{"id": "area-marche", "x": 20.0, "y": 16.0, "w": 8.0, "h": 8.0,
			"label": "Place du Marché", "category": "poi", "targetMapId": ""},
	]
	md.update_map(village)

	var child: Dictionary = md.create_child_map_for_area(village_id, "area-marche")
	_assert("child_created", not child.is_empty())
	var child_id: String = child.get("id", "")
	_assert("child_title", str(child.get("title", "")) == "Place du Marché")
	_assert("child_parent", str(child.get("parentMapId", "")) == village_id)
	_assert("child_complex", md.is_complex_map(child))

	# Le lien retour est écrit côté parent.
	var reloaded_village: Dictionary = md.get_by_id(village_id)
	_assert("area_points_to_child",
		str(md.get_area(reloaded_village, "area-marche").get("targetMapId", "")) == child_id)

	# Rappeler la création ne duplique pas la carte.
	var again: Dictionary = md.create_child_map_for_area(village_id, "area-marche")
	_assert("child_idempotent", str(again.get("id", "")) == child_id)

	_assert("children_listed", (md.get_child_maps(village_id) as Array).size() == 1)
	_assert("child_of_unknown_area", (md.create_child_map_for_area(village_id, "inconnu") as Dictionary).is_empty())
	_assert("child_of_unknown_map", (md.create_child_map_for_area("inconnu", "area-marche") as Dictionary).is_empty())

func _test_breadcrumb(md) -> void:
	var village: Dictionary = md.create_complex_map("Fil Village", "general", "local", 40, 32)
	var village_id: String = village.get("id", "")
	village["areas"] = [{"id": "a-place", "x": 5.0, "y": 5.0, "w": 4.0, "h": 4.0, "label": "Place"}]
	md.update_map(village)

	var place: Dictionary = md.create_child_map_for_area(village_id, "a-place")
	var place_id: String = place.get("id", "")
	place["areas"] = [{"id": "a-taverne", "x": 3.0, "y": 3.0, "w": 3.0, "h": 3.0, "label": "Taverne"}]
	md.update_map(place)
	var taverne: Dictionary = md.create_child_map_for_area(place_id, "a-taverne")

	var chain: Array = md.get_map_breadcrumb(str(taverne.get("id", "")))
	_assert("breadcrumb_depth", chain.size() == 3)
	_assert("breadcrumb_root", str((chain[0] as Dictionary).get("title", "")) == "Fil Village")
	_assert("breadcrumb_leaf", str((chain[2] as Dictionary).get("title", "")) == "Taverne")
	_assert("breadcrumb_single", (md.get_map_breadcrumb(village_id) as Array).size() == 1)

func _test_session_navigation(md, gd) -> void:
	var village: Dictionary = md.create_complex_map("Session Village", "general", "local", 40, 32)
	var village_id: String = village.get("id", "")
	village["areas"] = [{"id": "a-marche", "x": 20.0, "y": 16.0, "w": 8.0, "h": 8.0, "label": "Place du Marché"}]
	md.update_map(village)
	var marche: Dictionary = md.create_child_map_for_area(village_id, "a-marche")
	var marche_id: String = marche.get("id", "")

	# Un lieu imbriqué dans la place, pour vérifier la profondeur.
	var marche_full: Dictionary = md.get_by_id(marche_id)
	marche_full["areas"] = [{"id": "a-taverne", "x": 4.0, "y": 4.0, "w": 3.0, "h": 3.0, "label": "Taverne"}]
	md.update_map(marche_full)
	var taverne: Dictionary = md.create_child_map_for_area(marche_id, "a-taverne")
	var taverne_id: String = taverne.get("id", "")

	gd.active_game = {
		"id": "test-areas", "status": "playing", "scenarioId": "demo-couronne-fracturee",
		"mapIds": [village_id], "gmType": "ai",
		"party": [{"id": "hero-1", "name": "Aria", "hp": 12, "isPlayer": true}],
		"mapPlayState": {}, "mapNavigation": {"view": "world"}, "mapModeOverrides": {},
	}
	gd.ensure_map_play_state()

	_assert("nav_root", gd.get_current_area_map_id(village_id) == village_id)
	_assert("nav_stack_empty", (gd.get_area_stack() as Array).is_empty())

	_assert("nav_enter", gd.enter_area(village_id, "a-marche"))
	_assert("nav_now_marche", gd.get_current_area_map_id(village_id) == marche_id)
	_assert("nav_map_registered", (gd.active_game["mapIds"] as Array).has(marche_id))

	# La carte affichée en session suit la pile.
	var display: Dictionary = gd.get_session_display_map(village_id)
	_assert("nav_display_map", str((display["displayMap"] as Dictionary).get("id", "")) == marche_id)
	_assert("nav_display_mode", str((display["navContext"] as Dictionary).get("mode", "")) == "area")
	_assert("nav_display_label", str((display["navContext"] as Dictionary).get("areaLabel", "")) == "Place du Marché")

	# Profondeur 2.
	_assert("nav_enter_deep", gd.enter_area(marche_id, "a-taverne"))
	_assert("nav_now_taverne", gd.get_current_area_map_id(village_id) == taverne_id)
	_assert("nav_stack_depth", (gd.get_area_stack() as Array).size() == 2)

	# On place un personnage à cette échelle : c'est le but du zoom.
	gd.place_complex_member_token(taverne_id, 5.0, 5.0, "hero-1")
	_assert("nav_token_placed", gd.get_map_play_tokens(taverne_id).size() == 1)

	# Remontée.
	_assert("nav_exit", gd.exit_area())
	_assert("nav_back_to_marche", gd.get_current_area_map_id(village_id) == marche_id)
	_assert("nav_exit_again", gd.exit_area())
	_assert("nav_back_to_root", gd.get_current_area_map_id(village_id) == village_id)
	_assert("nav_exit_empty", not gd.exit_area())

	# Un lieu sans carte n'ouvre rien.
	var orphan: Dictionary = md.get_by_id(village_id)
	orphan["areas"].append({"id": "a-vide", "x": 2.0, "y": 2.0, "w": 2.0, "h": 2.0, "label": "Ruelle"})
	md.update_map(orphan)
	_assert("nav_enter_without_map", not gd.enter_area(village_id, "a-vide"))
	_assert("nav_enter_unknown", not gd.enter_area(village_id, "inconnu"))

	# Clic session : hit-test lieu → enter_area (même chemin que area_clicked).
	gd.clear_area_stack()
	var hit: Dictionary = md.get_area_at(md.get_by_id(village_id), 20.0, 16.0)
	_assert("click_hit_area", str(hit.get("id", "")) == "a-marche")
	_assert("click_has_target", not str(hit.get("targetMapId", "")).is_empty())
	_assert("click_enter", gd.enter_area(village_id, str(hit.get("id", ""))))
	_assert("click_display", str((gd.get_session_display_map(village_id)["displayMap"] as Dictionary).get("id", "")) == marche_id)
	_assert("click_exit", gd.exit_area())

	gd.clear_area_stack()
	_assert("nav_cleared", (gd.get_area_stack() as Array).is_empty())

func _test_editor_area_tool(md) -> void:
	var village: Dictionary = md.create_complex_map("Editeur Village", "general", "local", 40, 32)
	var editor: Control = ComplexEditorScript.new()
	get_root().add_child(editor)
	editor.size = Vector2(1280, 800)
	await process_frame
	editor.load_map(village)
	await process_frame

	var mods := {"shift": false, "ctrl": false, "alt": false}
	editor._area_label = "Taverne du Cerf"
	editor._area_category = "shop"
	editor._set_tool(ToolsScript.AREA)
	_assert("tool_area_is_drag", ToolsScript.is_drag_tool(ToolsScript.AREA))
	_assert("tool_area_shortcut", ToolsScript.tool_for_shortcut("A") == ToolsScript.AREA)

	# Tracé du lieu au glisser.
	editor._on_pointer_pressed(Vector2(8, 6), Vector2(100, 100), MOUSE_BUTTON_LEFT, mods)
	editor._on_pointer_moved(Vector2(14, 11), Vector2(180, 160), mods)
	editor._on_pointer_released(Vector2(14, 11), Vector2(180, 160), MOUSE_BUTTON_LEFT, mods)
	_assert("editor_area_created", editor.doc.count_of_kind(K_AREA) == 1)

	var area: Dictionary = editor.doc.elements_of_kind(K_AREA)[0]
	_assert("editor_area_label", str(area.get("label", "")) == "Taverne du Cerf")
	_assert("editor_area_category", str(area.get("category", "")) == "shop")
	_assert("editor_area_size", is_equal_approx(float(area.get("w", 0)), 6.0))
	_assert("editor_area_centered", is_equal_approx(float(area.get("x", 0)), 11.0))
	_assert("editor_area_selected", editor.doc.is_selected(str(area.get("id", ""))))

	# Création de la carte enfant depuis l'inspecteur.
	editor._on_child_map_requested(str(area.get("id", "")))
	var saved: Dictionary = md.get_by_id(str(village.get("id", "")))
	var linked: String = str(md.get_area(saved, str(area.get("id", ""))).get("targetMapId", ""))
	_assert("editor_child_linked", not linked.is_empty())
	_assert("editor_child_title", str(md.get_by_id(linked).get("title", "")) == "Taverne du Cerf")
	_assert("editor_breadcrumb", (md.get_map_breadcrumb(linked) as Array).size() == 2)

	# Le lieu se défait comme n'importe quel élément.
	editor._do_undo()
	editor.queue_free()

# ===========================================================================

func _assert(name: String, cond: bool) -> void:
	if not cond:
		print("map_areas_test:FAIL at ", name)
		_failed = true
