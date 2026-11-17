extends SceneTree

## Tests du modèle de session (lot 4) : barres/aura de token, journal en pages,
## ordre de tour optionnel et quickbar par personnage.
##
##   godot --headless --path game -s res://scripts/tests/session_model_test.gd

var _failed := false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")
	var gd = get_root().get_node("GameData")

	var map: Dictionary = md.create_complex_map("Modele session", "general", "local", 12, 10)
	var map_id: String = map.get("id", "")
	md.update_map(map)

	gd.active_game = {
		"id": "test-session-model", "status": "playing", "scenarioId": "demo-couronne-fracturee",
		"mapIds": [map_id], "gmType": "human",
		"party": [
			{"id": "hero-1", "name": "Aria", "hp": 7, "maxHp": 20, "isPlayer": true, "clientId": "player-a"},
			{"id": "hero-2", "name": "Brand", "hp": 12, "maxHp": 12, "isPlayer": true, "clientId": "player-b"},
		],
		"mapPlayState": {}, "mapNavigation": {"view": "world"}, "mapModeOverrides": {},
	}
	gd.ensure_map_play_state()
	var entry: Dictionary = gd.get_map_play_entry(map_id)
	entry["tokens"] = [
		{"id": "tok-a", "x": 2.0, "y": 2.0, "kind": "member", "memberId": "hero-1"},
		{"id": "tok-b", "x": 4.0, "y": 2.0, "kind": "member", "memberId": "hero-2"},
		{"id": "tok-c", "x": 6.0, "y": 2.0, "kind": "marker"},
	]

	_test_token_bars(gd, map_id)
	_test_token_aura(gd, map_id)
	_test_journal(gd)
	_test_turn_order(gd)
	_test_quickbar(gd)

	if _failed:
		quit(1)
		return
	print("session_model_test:PASS")
	quit(0)

func _assert(name: String, cond: bool) -> void:
	if not cond:
		print("session_model_test:FAIL at ", name)
		_failed = true

# --- Barres ----------------------------------------------------------------

func _test_token_bars(gd, map_id: String) -> void:
	_assert("bars_empty", gd.get_token_bars(map_id, "tok-a").is_empty())
	_assert("bar_create", gd.set_token_bar(map_id, "tok-a", "hp", 12, 20))
	var bar: Dictionary = gd.get_token_bar(map_id, "tok-a", "hp")
	_assert("bar_value", int(bar.get("value", -1)) == 12)
	_assert("bar_max", int(bar.get("max", -1)) == 20)

	_assert("bar_clamp_high", gd.set_token_bar(map_id, "tok-a", "hp", 99))
	_assert("bar_clamped_high", int(gd.get_token_bar(map_id, "tok-a", "hp").get("value", -1)) == 20)
	_assert("bar_clamp_low", gd.set_token_bar(map_id, "tok-a", "hp", -5))
	_assert("bar_clamped_low", int(gd.get_token_bar(map_id, "tok-a", "hp").get("value", -1)) == 0)

	_assert("bar_unknown_token", not gd.set_token_bar(map_id, "inconnu", "hp", 1))

	# Une barre non liée peut être posée sur un token (mana, stress…).
	_assert("bar_second", gd.set_token_bar(map_id, "tok-a", "mana", 3, 10))
	_assert("bar_third", gd.set_token_bar(map_id, "tok-a", "stress", 1, 5))
	_assert("bar_max_count", not gd.set_token_bar(map_id, "tok-a", "fourth", 1, 5))

	# Synchronisation depuis la fiche : tok-b n'a pas encore de barre.
	var synced: int = gd.sync_token_bars_from_party(map_id)
	_assert("bars_synced_count", synced == 1)
	var synced_bar: Dictionary = gd.get_token_bar(map_id, "tok-b", "hp")
	_assert("bars_synced_value", int(synced_bar.get("value", -1)) == 12)
	_assert("bars_synced_label", str(synced_bar.get("label", "")) == "PV")
	_assert("bars_synced_link", str(synced_bar.get("link", "")) == "member:hero-2:hp")
	# Un token sans membre (marqueur) n'est pas synchronisé.
	_assert("bars_marker_none", gd.get_token_bars(map_id, "tok-c").is_empty())

	# Opération réseau + autorisation joueur.
	_assert("ops_bar_allowed", gd.PLAYER_ALLOWED_OPS.has(gd.MAP_OP_SET_BAR))
	_assert("ops_bar_apply", gd.apply_map_op(map_id, {
		"type": gd.MAP_OP_SET_BAR, "tokenId": "tok-a", "barId": "hp", "value": 9, "max": 20,
	}))
	_assert("ops_bar_value", int(gd.get_token_bar(map_id, "tok-a", "hp").get("value", -1)) == 9)
	_assert("ops_bar_unknown", not gd.apply_map_op(map_id, {
		"type": gd.MAP_OP_SET_BAR, "tokenId": "inconnu", "barId": "hp", "value": 1,
	}))

# --- Aura ------------------------------------------------------------------

func _test_token_aura(gd, map_id: String) -> void:
	_assert("aura_empty", gd.get_token_aura(map_id, "tok-a").is_empty())
	_assert("aura_set", gd.set_token_aura(map_id, "tok-a", {
		"color": "#66ccff", "radius": 2.0, "label": "Bouclier",
	}))
	var aura: Dictionary = gd.get_token_aura(map_id, "tok-a")
	_assert("aura_color", str(aura.get("color", "")) == "#66ccff")
	_assert("aura_radius", is_equal_approx(float(aura.get("radius", 0.0)), 2.0))
	_assert("aura_label", str(aura.get("label", "")) == "Bouclier")

	# Le rayon est borné.
	gd.set_token_aura(map_id, "tok-a", {"radius": 99.0})
	_assert("aura_radius_clamped", float(gd.get_token_aura(map_id, "tok-a").get("radius", 0.0)) <= 8.0)

	_assert("aura_op_set", gd.apply_map_op(map_id, {
		"type": gd.MAP_OP_SET_AURA, "tokenId": "tok-b",
		"aura": {"color": "#ff8800", "radius": 1.0},
	}))
	_assert("aura_op_present", not gd.get_token_aura(map_id, "tok-b").is_empty())
	_assert("aura_op_clear", gd.apply_map_op(map_id, {
		"type": gd.MAP_OP_SET_AURA, "tokenId": "tok-b", "aura": {},
	}))
	_assert("aura_cleared", gd.get_token_aura(map_id, "tok-b").is_empty())
	_assert("aura_unknown_token", not gd.set_token_aura(map_id, "inconnu", {}))

# --- Journal ---------------------------------------------------------------

func _test_journal(gd) -> void:
	var folder_id: String = gd.create_journal_folder("Campagne")
	_assert("journal_folder", not folder_id.is_empty())
	_assert("journal_folders_count", gd.get_campaign_journal().get("folders", []).size() == 1)

	var page_id: String = gd.create_journal_page(folder_id, "Session 1", "Le groupe arrive à Valbois.")
	_assert("journal_page", not page_id.is_empty())
	var page: Dictionary = gd.find_journal_page(page_id)
	_assert("journal_page_title", str(page.get("title", "")) == "Session 1")
	_assert("journal_page_visibility", str(page.get("visibility", "")) == "table")

	var gm_page_id: String = gd.create_journal_page(folder_id, "Secrets", "Le maire ment.", "gm")
	_assert("journal_gm_page", not gm_page_id.is_empty())
	_assert("journal_bad_visibility_defaults", str(gd.find_journal_page(
		gd.create_journal_page(folder_id, "Divers", "")).get("visibility", "")) == "table")

	_assert("journal_update", gd.update_journal_page(page_id, {"title": "Session 1 (relue)", "body": "Suite."}))
	_assert("journal_updated_title", str(gd.find_journal_page(page_id).get("title", "")) == "Session 1 (relue)")

	# Filtrage : le joueur ne voit pas les pages MJ.
	var player_view: Dictionary = gd.filter_journal_for_player(false)
	var player_pages := 0
	for folder_variant in player_view.get("folders", []):
		player_pages += (folder_variant as Dictionary).get("pages", []).size()
	var gm_view: Dictionary = gd.filter_journal_for_player(true)
	var gm_pages := 0
	for folder_variant in gm_view.get("folders", []):
		gm_pages += (folder_variant as Dictionary).get("pages", []).size()
	_assert("journal_player_hides_gm", player_pages == 2)
	_assert("journal_gm_sees_all", gm_pages == 3)

	_assert("journal_delete", gd.delete_journal_page(gm_page_id))
	_assert("journal_deleted", gd.find_journal_page(gm_page_id).is_empty())
	_assert("journal_delete_unknown", not gd.delete_journal_page("inconnu"))
	_assert("journal_page_unknown_folder", gd.create_journal_page("inconnu", "X").is_empty())

# --- Ordre de tour ---------------------------------------------------------

func _test_turn_order(gd) -> void:
	var order: Dictionary = gd.get_turn_order()
	_assert("turn_default_open", bool(order.get("open", false)))
	_assert("turn_default_direction", int(order.get("direction", 0)) == 1)

	gd.add_turn_order_item("Aria", 15)
	gd.add_turn_order_item("Brand", 9)
	gd.add_turn_order_item("Capitaine", 20)
	var items: Array = gd.get_turn_order().get("items", [])
	_assert("turn_items_count", items.size() == 3)
	_assert("turn_sorted_desc", str((items[0] as Dictionary).get("name", "")) == "Capitaine")
	_assert("turn_sorted_desc_2", str((items[2] as Dictionary).get("name", "")) == "Brand")

	gd.set_turn_order_patch({"direction": -1})
	gd.sort_turn_order()
	items = gd.get_turn_order().get("items", [])
	_assert("turn_sorted_asc", str((items[0] as Dictionary).get("name", "")) == "Brand")

	var current: Dictionary = gd.current_turn_order_item()
	_assert("turn_current", str(current.get("name", "")) == "Brand")
	var next: Dictionary = gd.next_turn_order_item()
	_assert("turn_next", str(next.get("name", "")) == "Aria")
	var wrapper: Dictionary = gd.next_turn_order_item()
	_assert("turn_wrap", str(wrapper.get("name", "")) == "Capitaine")

	var removed_id: String = str((items[0] as Dictionary).get("id", ""))
	_assert("turn_remove", gd.remove_turn_order_item(removed_id))
	_assert("turn_removed_count", gd.get_turn_order().get("items", []).size() == 2)
	_assert("turn_remove_unknown", not gd.remove_turn_order_item("inconnu"))

	gd.set_turn_order_patch({"open": false})
	_assert("turn_closed", not bool(gd.get_turn_order().get("open", true)))

# --- Quickbar --------------------------------------------------------------

func _test_quickbar(gd) -> void:
	_assert("quickbar_empty", gd.get_character_quickbar("hero-1").is_empty())
	_assert("quickbar_set_slot", gd.set_quickbar_slot("hero-1", 0, {
		"label": "Attaque", "action": "roll", "formula": "1d20+5", "icon": "⚔",
	}))
	var slots: Array = gd.get_character_quickbar("hero-1")
	_assert("quickbar_slot_count", slots.size() == 1)
	_assert("quickbar_slot_label", str((slots[0] as Dictionary).get("label", "")) == "Attaque")
	_assert("quickbar_slot_formula", str((slots[0] as Dictionary).get("formula", "")) == "1d20+5")

	# Assainissement : action/visibilité inconnues → valeurs sures.
	gd.set_quickbar_slot("hero-1", 1, {
		"label": "Sort", "action": "pirate", "visibility": "inconnu", "formula": "2d6",
	})
	var sort_slot: Dictionary = gd.get_character_quickbar("hero-1")[1]
	_assert("quickbar_action_safe", str(sort_slot.get("action", "")) == "action")
	_assert("quickbar_visibility_safe", str(sort_slot.get("visibility", "")) == "table")

	# Emplacement MJ : masqué pour le joueur.
	gd.set_quickbar_slot("hero-1", 2, {"label": "Embuscade", "visibility": "gm"})
	_assert("quickbar_player_hides_gm", gd.filter_quickbar_for_player("hero-1", false).size() == 2)
	_assert("quickbar_gm_sees_all", gd.filter_quickbar_for_player("hero-1", true).size() == 3)

	_assert("quickbar_index_bounds", not gd.set_quickbar_slot("hero-1", 10, {"label": "X"}))
	_assert("quickbar_clear", gd.clear_quickbar_slot("hero-1", 0))
	_assert("quickbar_cleared_count", gd.get_character_quickbar("hero-1").size() == 2)
	_assert("quickbar_clear_bounds", not gd.clear_quickbar_slot("hero-1", 9))

	# 15 emplacements fournis → tronqué à 10.
	var many: Array = []
	for i in 15:
		many.append({"label": "Slot %d" % i})
	gd.set_character_quickbar("hero-2", many)
	_assert("quickbar_truncated", gd.get_character_quickbar("hero-2").size() == 10)
	_assert("quickbar_other_character", gd.get_character_quickbar("hero-1").size() == 2)
