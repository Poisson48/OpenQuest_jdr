extends SceneTree

## Tests de l'éditeur de cartes : document + historique par deltas, sélection,
## presse-papiers, liens, calques, terrain, templates, et pilotage de l'UI.

## `map_editor_tools.gd` ne depend d'aucun autoload : il peut etre precharge.
const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")

# Types d'elements (memes valeurs que les constantes KIND_* du document).
const K_TOKEN := "token"
const K_MARKER := "marker"
const K_EFFECT := "effect"
const K_ZONE := "zone"
const K_PLATFORM := "platform"
const K_WALL := "wall"
const K_NOTE := "note"
const K_LIGHT := "light"

# Charges a l'execution : ces scripts referencent l'autoload MapData, qui n'est
# pas encore un identifiant global quand ce SceneTree est compile.
var DocScript: GDScript
var TemplatesScript: GDScript

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	DocScript = load("res://scripts/maps/editor/map_edit_document.gd")
	TemplatesScript = load("res://scripts/maps/editor/map_editor_templates.gd")
	var md = get_root().get_node("MapData")
	var base: Dictionary = md.create_complex_map("Test éditeur", "general", "local", 20, 14)

	_test_document(base)
	_test_history(base)
	_test_selection_and_clipboard(base)
	_test_links(base)
	_test_layers(base)
	_test_terrain_and_fog(base)
	_test_geometry(base)
	_test_templates(base)
	_test_tools()
	await _test_editor_ui(base)

	if _failed:
		quit(1)
		return
	print("map_editor_test:PASS")
	quit(0)

# ===========================================================================

func _test_document(base: Dictionary) -> void:
	var doc: Variant = DocScript.new()
	doc.load_map(base)
	_assert("doc_loaded", not doc.map_data.is_empty())
	_assert("doc_schema_layers", (doc.map_data.get("layers", []) as Array).size() == 6)
	_assert("doc_schema_walls", doc.map_data.get("walls") is Array)
	_assert("doc_empty", doc.element_ids().is_empty())

	var token_id: String = doc.add_element({"x": 2.0, "y": 3.0, "label": "Garde"}, K_TOKEN)
	_assert("doc_add", doc.count_of_kind(K_TOKEN) == 1)
	var token: Dictionary = doc.get_element(token_id)
	_assert("doc_norm_display", token.get("display") is Dictionary)
	_assert("doc_norm_links", token.get("links") is Dictionary)
	_assert("doc_norm_layer", int(token.get("layer", -1)) >= 0)

	# Chaque type d'élément doit faire un aller-retour de sérialisation.
	doc.add_element({"x": 5.0, "y": 5.0, "markerType": "npc"}, K_MARKER)
	doc.add_element({"x": 6.0, "y": 6.0, "preset": "fire", "radius": 1.0}, K_EFFECT)
	doc.add_element({"x": 7.0, "y": 7.0, "shape": "circle", "radius": 2.0}, K_ZONE)
	doc.add_element({"x": 1.0, "y": 1.0, "w": 4.0, "h": 3.0, "elevation": 1.0}, K_PLATFORM)
	doc.add_element({"x": 8.0, "y": 2.0, "w": 5.0, "h": 0.25, "height": 1.4}, K_WALL)
	doc.add_element({"x": 9.0, "y": 9.0, "text": "Piège ici"}, K_NOTE)
	doc.add_element({"x": 4.0, "y": 8.0, "radius": 3.0}, K_LIGHT)

	var snapshot: Dictionary = doc.to_map_data()
	var defaults: Dictionary = snapshot.get("playDefaults", {})
	_assert("ser_tokens", (defaults.get("tokens", []) as Array).size() == 2)  # token + marqueur
	_assert("ser_effects", (defaults.get("effects", []) as Array).size() == 1)
	_assert("ser_zones", (defaults.get("zones", []) as Array).size() == 1)
	_assert("ser_walls", (snapshot.get("walls", []) as Array).size() == 1)
	_assert("ser_notes", (snapshot.get("notes", []) as Array).size() == 1)
	_assert("ser_elevations", (snapshot.get("elevationLayers", []) as Array).size() == 1)
	_assert("ser_lights", ((snapshot.get("lighting", {}) as Dictionary).get("sources", []) as Array).size() == 1)
	_assert("ser_platform_shape", ((snapshot["elevationLayers"][0] as Dictionary).get("platform") is Dictionary))
	_assert("ser_token_kind", str((defaults["tokens"][0] as Dictionary).get("kind", "")) == "member")

	# Le format historique doit rester lisible : rechargement du snapshot.
	var reloaded: Variant = DocScript.new()
	reloaded.load_map(snapshot)
	_assert("roundtrip_count", reloaded.element_ids().size() == doc.element_ids().size())
	_assert("roundtrip_walls", reloaded.count_of_kind(K_WALL) == 1)
	_assert("roundtrip_lights", reloaded.count_of_kind(K_LIGHT) == 1)
	_assert("roundtrip_notes", reloaded.count_of_kind(K_NOTE) == 1)

func _test_history(base: Dictionary) -> void:
	var doc: Variant = DocScript.new()
	doc.load_map(base)
	_assert("hist_clean", not doc.is_dirty() and not doc.can_undo())

	var id: String = doc.add_element({"x": 1.0, "y": 1.0}, K_TOKEN)
	_assert("hist_dirty", doc.is_dirty())
	_assert("hist_can_undo", doc.can_undo())
	doc.undo()
	_assert("hist_undo_add", not doc.has_element(id))
	doc.redo()
	_assert("hist_redo_add", doc.has_element(id))

	doc.modify_element(id, {"x": 9.0}, "Position")
	_assert("hist_mod", float(doc.get_element(id).get("x", 0)) == 9.0)
	doc.undo()
	_assert("hist_undo_mod", float(doc.get_element(id).get("x", 0)) == 1.0)
	doc.redo()
	_assert("hist_redo_mod", float(doc.get_element(id).get("x", 0)) == 9.0)

	# Une modification sans changement réel ne doit pas polluer l'historique.
	var depth: int = doc.history_labels().size()
	doc.modify_element(id, {"x": 9.0}, "Position")
	_assert("hist_noop", doc.history_labels().size() == depth)

	# Transaction : plusieurs deltas annulés en une seule étape.
	doc.begin_transaction()
	var a: String = doc.add_element({"x": 2.0, "y": 2.0}, K_TOKEN)
	var b: String = doc.add_element({"x": 3.0, "y": 3.0}, K_TOKEN)
	doc.commit_transaction()
	_assert("tx_added", doc.has_element(a) and doc.has_element(b))
	doc.undo()
	_assert("tx_undo_both", not doc.has_element(a) and not doc.has_element(b))
	doc.redo()
	_assert("tx_redo_both", doc.has_element(a) and doc.has_element(b))

	# Suppression puis annulation restaure l'élément à sa place.
	doc.remove_element(a)
	_assert("del", not doc.has_element(a))
	doc.undo()
	_assert("del_undo", doc.has_element(a))

	# Drag live : pas de delta tant que commit_live_edit n'est pas appelé.
	var before_depth: int = doc.history_labels().size()
	doc.set_live_position(a, 12.0, 12.0)
	_assert("live_no_delta", doc.history_labels().size() == before_depth)
	doc.commit_live_edit([a], "Déplacement")
	_assert("live_commit", doc.history_labels().size() == before_depth + 1)
	doc.undo()
	_assert("live_undo", float(doc.get_element(a).get("x", 0)) == 2.0)

	# Annulation d'un drag en cours (Échap) : retour à la copie de référence.
	doc.set_live_position(a, 30.0, 30.0)
	doc.revert_live_edit([a])
	_assert("live_revert", float(doc.get_element(a).get("x", 0)) == 2.0)

	# Métadonnées.
	doc.set_meta_values({"fogEnabled": false}, "Brouillard")
	_assert("meta", doc.map_data.get("fogEnabled") == false)
	doc.undo()
	_assert("meta_undo", doc.map_data.get("fogEnabled") == true)

func _test_selection_and_clipboard(base: Dictionary) -> void:
	var doc: Variant = DocScript.new()
	doc.load_map(base)
	var ids: Array = []
	for i in range(4):
		ids.append(doc.add_element({"x": float(i), "y": 1.0}, K_TOKEN))

	doc.select_only(str(ids[0]))
	_assert("sel_one", doc.selection_size() == 1)
	doc.toggle_selection(str(ids[1]))
	_assert("sel_toggle_on", doc.selection_size() == 2)
	doc.toggle_selection(str(ids[1]))
	_assert("sel_toggle_off", doc.selection_size() == 1)
	doc.select_all()
	_assert("sel_all", doc.selection_size() == 4)
	doc.select_only(str(ids[0]))
	doc.invert_selection()
	_assert("sel_invert", doc.selection_size() == 3)

	doc.select_all()
	var bounds: Rect2 = doc.selection_bounds()
	_assert("sel_bounds", bounds.size.x > 0.0 and bounds.size.y > 0.0)

	# Groupes.
	doc.set_selection([str(ids[0]), str(ids[1])])
	doc.group_selection()
	_assert("group", not str(doc.get_element(str(ids[0])).get("group", "")).is_empty())
	doc.select_only(str(ids[0]))
	doc.expand_selection_to_groups()
	_assert("group_expand", doc.selection_size() == 2)
	doc.ungroup_selection()
	_assert("ungroup", str(doc.get_element(str(ids[0])).get("group", "")).is_empty())

	# Presse-papiers : les copies reçoivent de nouveaux identifiants.
	doc.set_selection([str(ids[0]), str(ids[1])])
	_assert("copy", doc.copy_selection() == 2)
	var pasted: Array = doc.paste(10.0, 10.0)
	_assert("paste_count", pasted.size() == 2)
	_assert("paste_new_ids", not pasted.has(str(ids[0])))
	_assert("paste_total", doc.element_ids().size() == 6)
	_assert("paste_selected", doc.selection_size() == 2)
	doc.undo()
	_assert("paste_undo", doc.element_ids().size() == 4)

	doc.set_selection([str(ids[2])])
	var dup: Array = doc.duplicate_selection()
	_assert("duplicate", dup.size() == 1 and doc.element_ids().size() == 5)

	doc.set_selection([str(ids[3])])
	_assert("cut", doc.cut_selection() == 1)
	_assert("cut_removed", not doc.has_element(str(ids[3])))

func _test_links(base: Dictionary) -> void:
	var doc: Variant = DocScript.new()
	doc.load_map(base)
	var a: String = doc.add_element({"x": 1.0, "y": 1.0}, K_MARKER)
	var b: String = doc.add_element({"x": 5.0, "y": 5.0}, K_MARKER)
	var c: String = doc.add_element({"x": 9.0, "y": 1.0}, K_MARKER)

	_assert("link_ok", doc.link_elements(a, b))
	_assert("link_dup_refused", not doc.link_elements(a, b))
	_assert("link_self_refused", not doc.link_elements(a, a))
	var links_a: Dictionary = doc.get_element(a).get("links", {})
	var links_b: Dictionary = doc.get_element(b).get("links", {})
	_assert("link_next", (links_a.get("next", []) as Array).has(b))
	_assert("link_prev_auto", (links_b.get("prev", []) as Array).has(a))
	_assert("link_segments", doc.link_segments().size() == 1)

	doc.link_elements(b, c)
	_assert("link_chain", doc.link_segments().size() == 2)

	# Supprimer un maillon doit nettoyer les références des voisins.
	doc.remove_element(b)
	var links_a2: Dictionary = doc.get_element(a).get("links", {})
	var links_c2: Dictionary = doc.get_element(c).get("links", {})
	_assert("unlink_on_delete_next", not (links_a2.get("next", []) as Array).has(b))
	_assert("unlink_on_delete_prev", not (links_c2.get("prev", []) as Array).has(b))
	_assert("link_segments_after_delete", doc.link_segments().is_empty())

	doc.link_elements(a, c)
	doc.unlink_elements(a, c)
	_assert("unlink", doc.link_segments().is_empty())

func _test_layers(base: Dictionary) -> void:
	var doc: Variant = DocScript.new()
	doc.load_map(base)
	var id: String = doc.add_element({"x": 1.0, "y": 1.0, "layer": 4}, K_TOKEN)
	_assert("layer_visible", doc.is_element_visible(doc.get_element(id)))
	doc.set_layer_visible(4, false)
	_assert("layer_hidden", not doc.is_element_visible(doc.get_element(id)))
	doc.set_layer_visible(4, true)
	doc.set_layer_locked(4, true)
	_assert("layer_locked", not doc.is_element_selectable(doc.get_element(id)))
	doc.set_layer_locked(4, false)
	doc.rename_layer(4, "Combattants")
	_assert("layer_rename", doc.layer_name(4) == "Combattants")
	doc.undo()
	_assert("layer_rename_undo", doc.layer_name(4) == "Tokens")

	doc.modify_element(id, {"locked": true}, "Verrou")
	_assert("elem_locked", not doc.is_element_selectable(doc.get_element(id)))
	doc.modify_element(id, {"locked": false, "hidden": true}, "Masqué")
	_assert("elem_hidden", not doc.is_element_visible(doc.get_element(id)))

	# Ordre d'empilement.
	doc.modify_element(id, {"hidden": false}, "Visible")
	var second: String = doc.add_element({"x": 2.0, "y": 2.0, "layer": 4}, K_TOKEN)
	doc.set_selection([second])
	doc.send_to_back()
	_assert("z_back", doc.element_ids()[0] == second)
	doc.bring_to_front()
	_assert("z_front", doc.element_ids()[doc.element_ids().size() - 1] == second)

	# Calques : créer, réordonner, supprimer (migration).
	var extra_id: int = doc.add_layer("Décors custom")
	_assert("layer_add", extra_id >= 0 and doc.layer_name(extra_id) == "Décors custom")
	var layers_before: Array = (doc.map_data.get("layers", []) as Array).duplicate()
	doc.move_layer_up(extra_id)
	var layers_after: Array = doc.map_data.get("layers", []) as Array
	_assert("layer_move_up", layers_after.size() == layers_before.size())
	doc.move_layer_down(extra_id)
	doc.set_layer_for_selection(extra_id)  # second is selected
	_assert("layer_assign", int(doc.get_element(second).get("layer", -1)) == extra_id)
	doc.remove_layer(extra_id)
	_assert("layer_remove", not _layer_id_exists(doc, extra_id))
	_assert("layer_migrated", int(doc.get_element(second).get("layer", -1)) != extra_id)

func _layer_id_exists(doc: Variant, layer_id: int) -> bool:
	for layer_variant in doc.map_data.get("layers", []):
		if int((layer_variant as Dictionary).get("id", -1)) == layer_id:
			return true
	return false

func _test_terrain_and_fog(base: Dictionary) -> void:
	var doc: Variant = DocScript.new()
	doc.load_map(base)
	var origin: String = doc.get_tile_at(0, 0)
	_assert("tile_read", not origin.is_empty())
	_assert("tile_oob", doc.get_tile_at(-1, 0).is_empty())

	var width: int = int(doc.map_data.get("width", 20))
	doc.paint_tiles({str(0): "wall", str(width + 1): "wall"})
	_assert("paint", doc.get_tile_at(0, 0) == "wall")
	_assert("paint_second", doc.get_tile_at(1, 1) == "wall")
	doc.undo()
	_assert("paint_undo", doc.get_tile_at(0, 0) == origin)

	doc.bucket_fill(5, 5, "water")
	_assert("bucket", doc.get_tile_at(5, 5) == "water" and doc.get_tile_at(0, 0) == "water")
	doc.undo()
	_assert("bucket_undo", doc.get_tile_at(5, 5) == origin)

	# Redimensionnement : le contenu existant est conservé au coin haut-gauche.
	doc.paint_tiles({str(0): "stone"})
	doc.resize_grid(30, 20)
	_assert("resize_dims", int(doc.map_data.get("width")) == 30 and int(doc.map_data.get("height")) == 20)
	_assert("resize_tiles_len", (doc.map_data.get("tiles", []) as Array).size() == 600)
	_assert("resize_preserved", doc.get_tile_at(0, 0) == "stone")
	doc.undo()
	_assert("resize_undo", int(doc.map_data.get("width")) == 20)

	doc.reveal_fog(["0,0", "1,0"])
	_assert("fog_reveal", doc.fog_cells().size() == 2)
	doc.reveal_fog(["0,0"])
	_assert("fog_no_dup", doc.fog_cells().size() == 2)
	doc.hide_fog(["0,0"])
	_assert("fog_hide", doc.fog_cells().size() == 1)
	doc.undo()
	_assert("fog_undo", doc.fog_cells().size() == 2)
	doc.reveal_all_fog()
	_assert("fog_all", doc.fog_cells().size() == 20 * 14)

func _test_geometry(base: Dictionary) -> void:
	var doc: Variant = DocScript.new()
	doc.load_map(base)
	var ids: Array = []
	for i in range(3):
		ids.append(doc.add_element({"x": float(i) * 4.0, "y": float(i), "w": 1.0, "h": 1.0}, K_TOKEN))
	doc.set_selection(ids)

	doc.align_selection("top")
	var y0: float = float(doc.get_element(str(ids[0])).get("y", -1))
	var y2: float = float(doc.get_element(str(ids[2])).get("y", -1))
	_assert("align_top", is_equal_approx(y0, y2))

	doc.distribute_selection(true)
	var xs: Array = []
	for id in ids:
		xs.append(float(doc.get_element(str(id)).get("x", 0)))
	_assert("distribute", is_equal_approx(xs[1] - xs[0], xs[2] - xs[1]))

	doc.move_elements_by(ids, 2.0, 0.0)
	_assert("nudge", is_equal_approx(float(doc.get_element(str(ids[0])).get("x", 0)), xs[0] + 2.0))
	doc.undo()
	_assert("nudge_undo", is_equal_approx(float(doc.get_element(str(ids[0])).get("x", 0)), xs[0]))

func _test_templates(base: Dictionary) -> void:
	var doc: Variant = DocScript.new()
	doc.load_map(base)
	var name := "test_auto_%d" % Time.get_unix_time_from_system()
	var elements: Array = [
		{"kind": K_TOKEN, "id": "t1", "x": 2.0, "y": 2.0, "w": 1.0, "h": 1.0,
			"label": "A", "display": {"rotation": 0.0}, "links": {"next": ["t2"], "prev": []}},
		{"kind": K_TOKEN, "id": "t2", "x": 5.0, "y": 2.0, "w": 1.0, "h": 1.0,
			"label": "B", "display": {"rotation": 0.0}, "links": {"next": [], "prev": ["t1"]}},
	]
	_assert("tpl_save", TemplatesScript.save_template(name, elements))
	_assert("tpl_exists", TemplatesScript.exists(name))

	var listed: Array = TemplatesScript.list_templates()
	var found := false
	for entry in listed:
		if str((entry as Dictionary).get("name", "")) == name:
			found = true
			_assert("tpl_count", int((entry as Dictionary).get("elementCount", 0)) == 2)
	_assert("tpl_listed", found)

	var placed: Array = TemplatesScript.elements_for_placement(name, 10.0, 10.0, 0)
	_assert("tpl_place_count", placed.size() == 2)
	_assert("tpl_place_new_id", str((placed[0] as Dictionary).get("id", "")) != "t1")
	var px0 := float((placed[0] as Dictionary).get("x", 0))
	var px1 := float((placed[1] as Dictionary).get("x", 0))
	_assert("tpl_place_spacing", is_equal_approx(absf(px1 - px0), 3.0))
	_assert("tpl_place_offset", px0 >= 10.0)

	# Rotation d'un quart de tour : l'écart passe de l'axe X à l'axe Y.
	var rotated: Array = TemplatesScript.elements_for_placement(name, 0.0, 0.0, 1)
	var ry0 := float((rotated[0] as Dictionary).get("y", 0))
	var ry1 := float((rotated[1] as Dictionary).get("y", 0))
	_assert("tpl_rotate", is_equal_approx(absf(ry1 - ry0), 3.0))
	var foot: Vector2 = TemplatesScript.footprint(name, 1)
	_assert("tpl_footprint_swap", foot.y > foot.x)

	doc.begin_transaction()
	for elem in placed:
		doc.add_element(elem as Dictionary, str((elem as Dictionary).get("kind", "")), "Template")
	doc.commit_transaction()
	_assert("tpl_placed_in_doc", doc.element_ids().size() == 2)
	doc.undo()
	_assert("tpl_undo_single_step", doc.element_ids().is_empty())

	_assert("tpl_delete", TemplatesScript.delete_template(name))
	_assert("tpl_gone", not TemplatesScript.exists(name))

func _test_tools() -> void:
	_assert("tool_lookup", ToolsScript.label(ToolsScript.TOKEN) == "Token")
	_assert("tool_shortcut", ToolsScript.tool_for_shortcut("V") == ToolsScript.SELECT)
	_assert("tool_shortcut_missing", ToolsScript.tool_for_shortcut("§").is_empty())
	_assert("tool_pose", ToolsScript.is_pose_tool(ToolsScript.TOKEN))
	_assert("tool_not_pose", not ToolsScript.is_pose_tool(ToolsScript.PLATFORM))
	_assert("tool_drag", ToolsScript.is_drag_tool(ToolsScript.WALL))
	_assert("tool_groups", ToolsScript.defs_in_group("place").size() > 4)
	_assert("snap_cell", is_equal_approx(ToolsScript.apply_snap(2.4, "cell"), 2.0))
	_assert("snap_half", is_equal_approx(ToolsScript.apply_snap(2.4, "half"), 2.5))
	_assert("snap_quarter", is_equal_approx(ToolsScript.apply_snap(2.4, "quarter"), 2.5))
	_assert("snap_off", is_equal_approx(ToolsScript.apply_snap(2.4, "off"), 2.4))
	_assert("snap_vector", ToolsScript.snap_vector(Vector2(1.2, 3.7), "cell") == Vector2(1.0, 4.0))
	_assert("shortcuts_text", ToolsScript.shortcuts_text().contains("Ctrl+Z"))

func _test_editor_ui(base: Dictionary) -> void:
	var editor: Control = load("res://scenes/map_editor/map_editor.tscn").instantiate()
	get_root().add_child(editor)
	editor.size = Vector2(1280, 800)
	await process_frame
	editor.load_map(base)
	await process_frame
	editor._layout_force = true
	editor._apply_responsive_layout()
	_assert("ui_dock_left_wide", editor._dock_left_w >= 150.0 and editor._dock_left_w <= 260.0)
	_assert("ui_dock_right_wide", editor._dock_right_w >= 200.0 and editor._dock_right_w <= 380.0)
	_assert("ui_docks_fit_wide", editor._dock_left_w + editor._dock_right_w < 1280.0 - 120.0)
	_assert("ui_right_min_w", editor._right_tabs != null and editor._right_tabs.custom_minimum_size.x >= 200.0)
	_assert("ui_right_visible", editor._right_tabs.visible)

	# Ultrawide 21:9 — docks % de la largeur réelle, centre restant.
	editor.size = Vector2(2560, 1080)
	await process_frame
	editor._layout_force = true
	editor._apply_responsive_layout()
	_assert("ui_ultrawide_left", editor._dock_left_w >= 150.0 and editor._dock_left_w <= 260.0)
	_assert("ui_ultrawide_right", editor._dock_right_w >= 200.0 and editor._dock_right_w <= 380.0)
	_assert("ui_ultrawide_sum", editor._dock_left_w + editor._dock_right_w < 2560.0 - 280.0)
	_assert("ui_ultrawide_visible", editor._right_tabs.visible and editor._left_scroll.visible)

	# 16:10 laptop.
	editor.size = Vector2(1920, 1200)
	await process_frame
	editor._layout_force = true
	editor._apply_responsive_layout()
	_assert("ui_16x10_fit", editor._dock_left_w + editor._dock_right_w < 1920.0 - 200.0)
	_assert("ui_16x10_visible", editor._right_tabs.visible)

	# Fenêtre courte / compacte (ex. 16:10 bas ou 3:2).
	editor.size = Vector2(1280, 800)
	await process_frame
	editor._layout_force = true
	editor._apply_responsive_layout()
	_assert("ui_1280x800_fit", editor._dock_left_w + editor._dock_right_w < 1280.0 - 120.0)

	editor.size = Vector2(900, 700)
	await process_frame
	editor._layout_force = true
	editor._apply_responsive_layout()
	_assert("ui_dock_left_narrow", editor._dock_left_w <= 200.0)
	_assert("ui_dock_right_narrow", editor._dock_right_w <= 280.0)
	_assert("ui_right_visible_narrow", editor._right_tabs.visible)
	_assert("ui_narrow_sum", editor._dock_left_w + editor._dock_right_w < 900.0 - 100.0)
	var right_w_before_click: float = editor._right_tabs.custom_minimum_size.x
	# Clic carte ne doit pas écraser le dock droit (régression UX).
	editor._on_pointer_pressed(Vector2(5, 5), Vector2(200, 200), MOUSE_BUTTON_LEFT, {"shift": false, "ctrl": false, "alt": false})
	await process_frame
	editor._apply_responsive_layout()
	_assert("ui_right_stable_after_click", editor._right_tabs.visible and editor._right_tabs.custom_minimum_size.x >= right_w_before_click - 1.0)
	editor.size = Vector2(1280, 800)
	await process_frame
	editor._layout_force = true
	editor._apply_responsive_layout()

	_assert("ui_doc_loaded", not editor.doc.map_data.is_empty())
	_assert("ui_engine", editor._engine != null)
	_assert("ui_overlay", editor._overlay != null)
	_assert("ui_minimap", editor._minimap != null)
	# Le SubViewportContainer ne doit pas voler les clics au parent.
	var container = editor._engine.get("_viewport_container")
	_assert("ui_viewport_mouse_ignore", container != null and container.mouse_filter == Control.MOUSE_FILTER_IGNORE)

	var mods := {"shift": false, "ctrl": false, "alt": false}

	# Pose d'un token via la machine à états d'outils.
	editor._set_tool(ToolsScript.TOKEN)
	editor._on_pointer_pressed(Vector2(3.2, 4.4), Vector2(100, 100), MOUSE_BUTTON_LEFT, mods)
	_assert("ui_place_token", editor.doc.count_of_kind(K_TOKEN) == 1)
	var placed: Dictionary = editor.doc.elements_of_kind(K_TOKEN)[0]
	_assert("ui_snap_applied", is_equal_approx(float(placed.get("x", -1)), 3.0))
	_assert("ui_auto_selected", editor.doc.selection_size() == 1)

	# Marqueur, effet, zone, note, lumière.
	editor._set_tool(ToolsScript.MARKER)
	editor._on_pointer_pressed(Vector2(6, 6), Vector2(120, 120), MOUSE_BUTTON_LEFT, mods)
	editor._set_tool(ToolsScript.EFFECT)
	editor._on_pointer_pressed(Vector2(7, 7), Vector2(130, 130), MOUSE_BUTTON_LEFT, mods)
	editor._set_tool(ToolsScript.ZONE)
	editor._on_pointer_pressed(Vector2(8, 8), Vector2(140, 140), MOUSE_BUTTON_LEFT, mods)
	editor._set_tool(ToolsScript.NOTE)
	editor._on_pointer_pressed(Vector2(9, 9), Vector2(150, 150), MOUSE_BUTTON_LEFT, mods)
	editor._set_tool(ToolsScript.LIGHT)
	editor._on_pointer_pressed(Vector2(10, 10), Vector2(160, 160), MOUSE_BUTTON_LEFT, mods)
	_assert("ui_marker", editor.doc.count_of_kind(K_MARKER) == 1)
	_assert("ui_effect", editor.doc.count_of_kind(K_EFFECT) == 1)
	_assert("ui_zone", editor.doc.count_of_kind(K_ZONE) == 1)
	_assert("ui_note", editor.doc.count_of_kind(K_NOTE) == 1)
	_assert("ui_light", editor.doc.count_of_kind(K_LIGHT) == 1)

	# Tracé par glisser : mur puis plateforme puis zone rectangulaire.
	editor._set_tool(ToolsScript.WALL)
	editor._on_pointer_pressed(Vector2(1, 1), Vector2(10, 10), MOUSE_BUTTON_LEFT, mods)
	editor._on_pointer_moved(Vector2(6, 1), Vector2(60, 10), mods)
	editor._on_pointer_released(Vector2(6, 1), Vector2(60, 10), MOUSE_BUTTON_LEFT, mods)
	_assert("ui_wall", editor.doc.count_of_kind(K_WALL) == 1)
	var wall: Dictionary = editor.doc.elements_of_kind(K_WALL)[0]
	_assert("ui_wall_len", is_equal_approx(float(wall.get("w", 0)), 5.0))

	editor._set_tool(ToolsScript.PLATFORM)
	editor._on_pointer_pressed(Vector2(2, 8), Vector2(20, 80), MOUSE_BUTTON_LEFT, mods)
	editor._on_pointer_moved(Vector2(6, 11), Vector2(60, 110), mods)
	editor._on_pointer_released(Vector2(6, 11), Vector2(60, 110), MOUSE_BUTTON_LEFT, mods)
	_assert("ui_platform", editor.doc.count_of_kind(K_PLATFORM) == 1)

	editor._set_tool(ToolsScript.ZONE_RECT)
	editor._on_pointer_pressed(Vector2(12, 2), Vector2(200, 20), MOUSE_BUTTON_LEFT, mods)
	editor._on_pointer_moved(Vector2(16, 6), Vector2(240, 60), mods)
	editor._on_pointer_released(Vector2(16, 6), Vector2(240, 60), MOUSE_BUTTON_LEFT, mods)
	_assert("ui_zone_rect", editor.doc.count_of_kind(K_ZONE) == 2)

	# Polygone : trois sommets puis fermeture au clic droit.
	editor._set_tool(ToolsScript.ZONE_POLY)
	editor._on_pointer_pressed(Vector2(1, 12), Vector2(10, 200), MOUSE_BUTTON_LEFT, mods)
	editor._on_pointer_pressed(Vector2(4, 12), Vector2(40, 200), MOUSE_BUTTON_LEFT, mods)
	editor._on_pointer_pressed(Vector2(4, 13), Vector2(40, 220), MOUSE_BUTTON_LEFT, mods)
	editor._on_pointer_pressed(Vector2(4, 13), Vector2(40, 220), MOUSE_BUTTON_RIGHT, mods)
	_assert("ui_polygon", editor.doc.count_of_kind(K_ZONE) == 3)
	_assert("ui_polygon_cleared", editor._overlay.polygon_points.is_empty())

	# Terrain et brouillard.
	editor._paint_tile = "wall"
	editor._set_tool(ToolsScript.PAINT)
	editor._on_pointer_pressed(Vector2(0, 0), Vector2(0, 0), MOUSE_BUTTON_LEFT, mods)
	_assert("ui_paint", editor.doc.get_tile_at(0, 0) == "wall")
	editor._set_tool(ToolsScript.FOG_REVEAL)
	editor._on_pointer_pressed(Vector2(2, 2), Vector2(30, 30), MOUSE_BUTTON_LEFT, mods)
	_assert("ui_fog", editor.doc.fog_cells().size() >= 5)

	# Mesure : n'ajoute aucun élément mais renseigne la règle.
	var count_before: int = editor.doc.element_ids().size()
	editor._set_tool(ToolsScript.MEASURE)
	editor._on_pointer_pressed(Vector2(0, 0), Vector2(0, 0), MOUSE_BUTTON_LEFT, mods)
	editor._on_pointer_moved(Vector2(3, 4), Vector2(50, 60), mods)
	editor._on_pointer_released(Vector2(3, 4), Vector2(50, 60), MOUSE_BUTTON_LEFT, mods)
	_assert("ui_measure_no_elem", editor.doc.element_ids().size() == count_before)
	_assert("ui_measure_active", editor._overlay.measure_active)

	# --- Chemin de projection : clic-sélection, rectangle, gomme ------------
	# Ces outils reposent sur grid_to_screen() : on vérifie qu'un aller-retour
	# grille → écran → grille retrouve bien le bon élément.
	editor._set_tool(ToolsScript.SELECT)
	editor.doc.clear_selection()
	var target: Dictionary = editor.doc.elements_of_kind(K_TOKEN)[0]
	var tx := float(target.get("x", 0))
	var ty := float(target.get("y", 0))
	var screen: Vector2 = editor._engine.grid_to_screen(tx, ty)
	_assert("proj_on_screen", screen.x > -10000.0)
	var back: Vector2 = editor._engine.screen_to_grid_pos(screen)
	_assert("proj_roundtrip", back.distance_to(Vector2(tx, ty)) < 0.6)

	var picked: String = editor._overlay.element_at_screen(screen)
	_assert("pick_by_screen", picked == str(target.get("id", "")))
	editor._on_pointer_pressed(Vector2(tx, ty), screen, MOUSE_BUTTON_LEFT, mods)
	editor._on_pointer_released(Vector2(tx, ty), screen, MOUSE_BUTTON_LEFT, mods)
	_assert("click_selects", editor.doc.is_selected(str(target.get("id", ""))))

	# Rectangle de sélection couvrant tout le viewport.
	editor.doc.clear_selection()
	var band := Rect2(Vector2(-4000, -4000), Vector2(8000, 8000))
	var in_band: Array = editor._overlay.elements_in_band(band)
	_assert("band_catches_all", in_band.size() >= 5)

	# Glisser d'un élément : la position change et un seul delta est produit.
	editor.doc.select_only(str(target.get("id", "")))
	var depth_before: int = editor.doc.history_labels().size()
	editor._on_pointer_pressed(Vector2(tx, ty), screen, MOUSE_BUTTON_LEFT, mods)
	editor._on_pointer_moved(Vector2(tx + 8.0, ty + 6.0), screen + Vector2(40, 30), mods)
	editor._on_pointer_released(Vector2(tx + 8.0, ty + 6.0), screen + Vector2(40, 30), MOUSE_BUTTON_LEFT, mods)
	var moved: Dictionary = editor.doc.get_element(str(target.get("id", "")))
	_assert("drag_moved", is_equal_approx(float(moved.get("x", 0)), tx + 8.0))
	_assert("drag_one_delta", editor.doc.history_labels().size() == depth_before + 1)
	editor._do_undo()
	_assert("drag_undo", is_equal_approx(float(editor.doc.get_element(str(target.get("id", ""))).get("x", 0)), tx))
	editor._do_redo()

	# Drag collant (GIMP) : sélection sous un élément empilé — on déplace la
	# sélection, pas le dessus.
	editor._do_undo()  # revient à (tx, ty)
	var bottom_id := str(target.get("id", ""))
	var top_id: String = editor.doc.add_element({
		"x": tx, "y": ty, "w": 1.0, "h": 1.0, "label": "dessus",
	}, K_TOKEN)
	editor.doc.select_only(bottom_id)
	_assert("sticky_pick_top", editor._overlay.element_at_screen(screen) == top_id)
	_assert("sticky_hit_selected", editor._overlay.selected_element_at_screen(screen) == bottom_id)
	var top_x_before := float(editor.doc.get_element(top_id).get("x", 0))
	editor._set_tool(ToolsScript.SELECT)
	editor._on_pointer_pressed(Vector2(tx, ty), screen, MOUSE_BUTTON_LEFT, mods)
	_assert("sticky_keeps_sel", editor.doc.is_selected(bottom_id) and not editor.doc.is_selected(top_id))
	editor._on_pointer_moved(Vector2(tx + 3.0, ty), screen + Vector2(20, 0), mods)
	editor._on_pointer_released(Vector2(tx + 3.0, ty), screen + Vector2(20, 0), MOUSE_BUTTON_LEFT, mods)
	_assert("sticky_moved_bottom", is_equal_approx(float(editor.doc.get_element(bottom_id).get("x", 0)), tx + 3.0))
	_assert("sticky_top_unmoved", is_equal_approx(float(editor.doc.get_element(top_id).get("x", 0)), top_x_before))
	_assert("sticky_still_selected", editor.doc.is_selected(bottom_id))

	# Nouveau clic sans sélection préalable : prend le dessus.
	editor.doc.clear_selection()
	editor._on_pointer_pressed(Vector2(tx + 3.0, ty), editor._engine.grid_to_screen(tx + 3.0, ty), MOUSE_BUTTON_LEFT, mods)
	editor._on_pointer_released(Vector2(tx + 3.0, ty), editor._engine.grid_to_screen(tx + 3.0, ty), MOUSE_BUTTON_LEFT, mods)
	# Le dessus est toujours à (tx, ty) ; le dessous à (tx+3). Clic sur dessus.
	var top_screen: Vector2 = editor._engine.grid_to_screen(tx, ty)
	editor._on_pointer_pressed(Vector2(tx, ty), top_screen, MOUSE_BUTTON_LEFT, mods)
	editor._on_pointer_released(Vector2(tx, ty), top_screen, MOUSE_BUTTON_LEFT, mods)
	_assert("fresh_click_picks_top", editor.doc.is_selected(top_id))

	# Calque verrouillé : non sélectionnable + message de blocage.
	editor.doc.set_layer_locked(4, true)
	editor.doc.clear_selection()
	var locked_pick: String = editor._overlay.element_at_screen(top_screen)
	_assert("locked_layer_not_picked", locked_pick != top_id and locked_pick != bottom_id)
	var blocked_pick: String = editor._overlay.blocked_element_at_screen(top_screen)
	_assert("locked_layer_blocked_hit", blocked_pick == top_id or blocked_pick == bottom_id)
	editor.doc.set_layer_locked(4, false)

	# Ordre de picking suit l'ordre des calques (pas seulement l'id numérique).
	var decor_id: int = 1
	var tokens_id: int = 4
	editor.doc.modify_element(bottom_id, {"layer": decor_id}, "Calque décor")
	editor.doc.modify_element(top_id, {"layer": tokens_id}, "Calque tokens")
	# Monter Décor au-dessus de Tokens (index plus grand = premier plan).
	while editor.doc.layer_stack_index(decor_id) < editor.doc.layer_stack_index(tokens_id):
		if not editor.doc.move_layer_down(decor_id):
			break
	_assert("layer_stack_decor_above", editor.doc.layer_stack_index(decor_id) > editor.doc.layer_stack_index(tokens_id))
	var sorted_ids: Array = []
	for e in editor.doc.elements_sorted():
		sorted_ids.append(str((e as Dictionary).get("id", "")))
	_assert("layer_sort_order", sorted_ids.find(bottom_id) > sorted_ids.find(top_id))

	# Nettoyage : on retire le token empilé pour ne pas fausser la persistance.
	editor.doc.remove_element(top_id)
	editor.doc.modify_element(bottom_id, {"layer": tokens_id, "x": tx + 8.0, "y": ty + 6.0}, "Reset sticky")

	# Gomme : supprime l'élément visé par la projection.
	var count_tokens: int = editor.doc.count_of_kind(K_TOKEN)
	var moved_screen: Vector2 = editor._engine.grid_to_screen(tx + 8.0, ty + 6.0)
	editor._set_tool(ToolsScript.ERASE)
	editor._on_pointer_pressed(Vector2(tx + 8.0, ty + 6.0), moved_screen, MOUSE_BUTTON_LEFT, mods)
	_assert("erase", editor.doc.count_of_kind(K_TOKEN) == count_tokens - 1)
	editor._do_undo()
	_assert("erase_undo", editor.doc.count_of_kind(K_TOKEN) == count_tokens)

	# Annulation globale : chaque action précédente doit se défaire une par une.
	var depth: int = editor.doc.history_labels().size()
	_assert("ui_history_depth", depth >= 10)
	editor._do_undo()
	_assert("ui_undo", editor.doc.history_labels().size() == depth - 1)
	editor._do_redo()
	_assert("ui_redo", editor.doc.history_labels().size() == depth)

	# Sauvegarde et relecture depuis MapData.
	editor.save_now()
	_assert("ui_saved_clean", not editor.doc.is_dirty())
	var stored: Dictionary = get_root().get_node("MapData").get_by_id(str(base.get("id", "")))
	_assert("ui_persist_walls", (stored.get("walls", []) as Array).size() == 1)
	_assert("ui_persist_notes", (stored.get("notes", []) as Array).size() == 1)
	_assert("ui_persist_tokens", ((stored.get("playDefaults", {}) as Dictionary).get("tokens", []) as Array).size() == 2)

	# Aperçu (lecture seule) : les panneaux d'édition disparaissent.
	editor.set_editable(false)
	await process_frame
	_assert("ui_readonly_panels", not editor._left_scroll.visible)
	editor.set_editable(true)
	await process_frame
	_assert("ui_editable_panels", editor._left_scroll.visible)

	editor.queue_free()

# ===========================================================================

func _assert(name: String, cond: bool) -> void:
	if not cond:
		print("map_editor_test:FAIL at ", name)
		_failed = true
