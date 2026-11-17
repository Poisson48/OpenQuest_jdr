extends RefCounted

## Modèle de session (lot 4 du refactor) — logique **pure** et testable.
##
## Extrait de `game/scripts/autoload/game_data.gd` (phase 2.4) : barres/aura de
## token, journal de campagne, ordre de tour optionnel et quickbar par
## personnage. Aucune dépendance `Node`, aucun autoload : chaque fonction reçoit
## le dictionnaire de partie (`active_game`) ou le token concerné, et le mute
## comme avant.
##
## Les données vivent dans `active_game` (`journal`, `turnOrder`, `quickbars`) et
## suivent la sauvegarde / la diffusion d'état (voir `docs/MODELE_SESSION.md`).
##
## Les constantes historiques `GameData.SESSION_*` restent exposées pour
## compatibilité ; ce module est la référence.

const BAR_MAX_COUNT := 3
const QUICKBAR_SLOTS := 10
const QUICKBAR_ACTIONS: Array = ["roll", "action", "note"]
const VISIBILITIES: Array = ["table", "gm"]

const DEFAULT_TURN_ORDER := { "open": true, "direction": 1, "items": [], "index": 0 }


## Initialise paresseusement les sous-structures de session dans `game`.
## Retourne `{}` si la partie est vide (même contrat que `GameData.session_model`).
static func ensure(game: Dictionary) -> Dictionary:
	if game.is_empty():
		return {}
	if not game.get("journal") is Dictionary:
		game["journal"] = { "folders": [] }
	if not game.get("turnOrder") is Dictionary:
		game["turnOrder"] = DEFAULT_TURN_ORDER.duplicate(true)
	if not game.get("quickbars") is Dictionary:
		game["quickbars"] = {}
	return game


# --- Barres et aura de token ------------------------------------------------

## Barres d'un token (référence directe à la liste stockée dans le token).
static func get_token_bars(token: Dictionary) -> Array:
	var bars_variant: Variant = token.get("bars", [])
	return bars_variant if bars_variant is Array else []


static func get_token_bar(token: Dictionary, bar_id: String) -> Dictionary:
	for bar_variant in get_token_bars(token):
		if not bar_variant is Dictionary:
			continue
		var bar: Dictionary = bar_variant
		if str(bar.get("id", "")) == bar_id:
			return bar
	return {}


## Fixe la valeur d'une barre (créée si absente). `max_value` < 0 conserve le max.
static func set_token_bar(token: Dictionary, bar_id: String, value: int, max_value: int = -1) -> bool:
	if token.is_empty() or bar_id.is_empty():
		return false
	if not token.has("bars") or not token["bars"] is Array:
		token["bars"] = []
	var bars: Array = token["bars"]
	var existing: Dictionary = {}
	for bar_variant in bars:
		if bar_variant is Dictionary and str((bar_variant as Dictionary).get("id", "")) == bar_id:
			existing = bar_variant
			break
	if existing.is_empty():
		if bars.size() >= BAR_MAX_COUNT:
			return false
		existing = {
			"id": bar_id,
			"label": bar_id,
			"value": 0,
			"max": maxi(value, 1),
			"color": "#c0392b",
			"link": "",
		}
		bars.append(existing)
	var limit := max_value if max_value >= 0 else int(existing.get("max", 0))
	if limit > 0:
		existing["max"] = limit
		existing["value"] = clampi(value, 0, limit)
	else:
		existing["value"] = maxi(value, 0)
	return true


static func get_token_aura(token: Dictionary) -> Dictionary:
	var aura_variant: Variant = token.get("aura", {})
	return aura_variant if aura_variant is Dictionary else {}


## Pose une aura (halo d'effet) sur un token ; `{}` ou vide l'efface.
static func set_token_aura(token: Dictionary, aura: Dictionary) -> bool:
	if token.is_empty():
		return false
	var color := str(aura.get("color", "#66ccff"))
	var radius := clampf(float(aura.get("radius", 1.5)), 0.25, 8.0)
	token["aura"] = {
		"color": color,
		"radius": radius,
		"pulse": bool(aura.get("pulse", true)),
		"label": str(aura.get("label", "")),
	}
	return true


static func clear_token_aura(token: Dictionary) -> bool:
	if token.is_empty():
		return false
	token.erase("aura")
	return true


## Crée les barres PV des tokens rattachés à un membre du groupe (si absentes).
static func sync_token_bars_from_party(game: Dictionary, entry: Dictionary) -> int:
	if game.is_empty():
		return 0
	var party: Array = game.get("party", []) if game.get("party") is Array else []
	var synced := 0
	for token_variant in entry.get("tokens", []):
		if not token_variant is Dictionary:
			continue
		var token: Dictionary = token_variant
		var member_id := str(token.get("memberId", ""))
		if member_id.is_empty():
			continue
		if not get_token_bars(token).is_empty():
			continue
		for member_variant in party:
			if not member_variant is Dictionary:
				continue
			var member: Dictionary = member_variant
			if str(member.get("id", "")) != member_id:
				continue
			var hp := int(member.get("hp", 0))
			var max_hp := int(member.get("maxHp", member.get("hp", 10)))
			if set_token_bar(token, "hp", hp, maxi(max_hp, 1)):
				var bar := get_token_bar(token, "hp")
				bar["label"] = "PV"
				bar["link"] = "member:%s:hp" % member_id
				synced += 1
			break
	return synced


# --- Journal de campagne (dossiers / pages) --------------------------------

static func get_journal(game: Dictionary) -> Dictionary:
	var model := ensure(game)
	if model.is_empty():
		return { "folders": [] }
	return model.get("journal", { "folders": [] })


static func create_journal_folder(model: Dictionary, title: String, folder_id: String) -> String:
	var journal: Dictionary = model.get("journal", { "folders": [] })
	journal["folders"].append({
		"id": folder_id,
		"title": title.strip_edges() if not title.strip_edges().is_empty() else "Dossier",
		"pages": [],
	})
	return folder_id


static func create_journal_page(
	model: Dictionary,
	folder_id: String,
	title: String,
	body: String,
	visibility: String,
	page_id: String
) -> String:
	var journal: Dictionary = model.get("journal", { "folders": [] })
	for folder_variant in journal.get("folders", []):
		var folder: Dictionary = folder_variant
		if str(folder.get("id", "")) != folder_id:
			continue
		folder["pages"].append({
			"id": page_id,
			"title": title.strip_edges() if not title.strip_edges().is_empty() else "Page",
			"body": body,
			"visibility": visibility if VISIBILITIES.has(visibility) else "table",
			"updatedAt": int(Time.get_unix_time_from_system()),
		})
		return page_id
	return ""


static func find_journal_page(model: Dictionary, page_id: String) -> Dictionary:
	for folder_variant in model.get("journal", { "folders": [] }).get("folders", []):
		var folder: Dictionary = folder_variant
		for page_variant in folder.get("pages", []):
			var page: Dictionary = page_variant
			if str(page.get("id", "")) == page_id:
				return page
	return {}


static func update_journal_page(model: Dictionary, page_id: String, patch: Dictionary) -> bool:
	var page := find_journal_page(model, page_id)
	if page.is_empty():
		return false
	if patch.has("title"):
		page["title"] = str(patch["title"]).strip_edges()
	if patch.has("body"):
		page["body"] = str(patch["body"])
	if patch.has("visibility") and VISIBILITIES.has(str(patch["visibility"])):
		page["visibility"] = str(patch["visibility"])
	page["updatedAt"] = int(Time.get_unix_time_from_system())
	return true


static func delete_journal_page(model: Dictionary, page_id: String) -> bool:
	for folder_variant in model.get("journal", { "folders": [] }).get("folders", []):
		var folder: Dictionary = folder_variant
		var pages: Array = folder.get("pages", [])
		for i in range(pages.size() - 1, -1, -1):
			if str((pages[i] as Dictionary).get("id", "")) == page_id:
				pages.remove_at(i)
				return true
	return false


## Journal tel que le voit un joueur : les pages `gm` disparaissent.
static func filter_journal_for_player(model: Dictionary, viewer_is_gm: bool) -> Dictionary:
	var journal: Dictionary = get_journal(model).duplicate(true)
	if viewer_is_gm:
		return journal
	for folder_variant in journal.get("folders", []):
		var folder: Dictionary = folder_variant
		var visible_pages: Array = []
		for page_variant in folder.get("pages", []):
			var page: Dictionary = page_variant
			if str(page.get("visibility", "table")) != "gm":
				visible_pages.append(page)
		folder["pages"] = visible_pages
	return journal


# --- Ordre de tour (initiative optionnelle) --------------------------------

static func get_turn_order(model: Dictionary) -> Dictionary:
	if model.is_empty():
		return DEFAULT_TURN_ORDER.duplicate(true)
	return model.get("turnOrder", DEFAULT_TURN_ORDER)


static func set_turn_order_patch(model: Dictionary, patch: Dictionary) -> void:
	var order := get_turn_order(model)
	if patch.has("open"):
		order["open"] = bool(patch["open"])
	if patch.has("direction"):
		order["direction"] = 1 if int(patch["direction"]) >= 0 else -1
	if patch.has("items") and patch["items"] is Array:
		order["items"] = patch["items"]
		order["index"] = 0


static func add_turn_order_item(
	model: Dictionary,
	name: String,
	value: int,
	member_id: String,
	color: String,
	item_id: String
) -> String:
	var order := get_turn_order(model)
	var items: Array = order.get("items", [])
	items.append({
		"id": item_id,
		"name": name.strip_edges() if not name.strip_edges().is_empty() else "Combattant",
		"value": value,
		"memberId": member_id,
		"color": color,
	})
	order["items"] = items
	sort_turn_order(model)
	return item_id


static func remove_turn_order_item(model: Dictionary, item_id: String) -> bool:
	var order := get_turn_order(model)
	var items: Array = order.get("items", [])
	for i in range(items.size() - 1, -1, -1):
		if str((items[i] as Dictionary).get("id", "")) == item_id:
			items.remove_at(i)
			order["index"] = 0
			return true
	return false


## Trie les items dans le sens courant (direction 1 = décroissant).
static func sort_turn_order(model: Dictionary) -> Array:
	var order := get_turn_order(model)
	var items: Array = order.get("items", [])
	var descending := int(order.get("direction", 1)) >= 0
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var va := int(a.get("value", 0))
		var vb := int(b.get("value", 0))
		if va == vb:
			return str(a.get("name", "")) < str(b.get("name", ""))
		return va > vb if descending else va < vb
	)
	order["items"] = items
	return items


static func current_turn_order_item(model: Dictionary) -> Dictionary:
	var order := get_turn_order(model)
	var items: Array = order.get("items", [])
	if items.is_empty():
		return {}
	var index := clampi(int(order.get("index", 0)), 0, items.size() - 1)
	order["index"] = index
	return items[index]


static func next_turn_order_item(model: Dictionary) -> Dictionary:
	var order := get_turn_order(model)
	var items: Array = order.get("items", [])
	if items.is_empty():
		return {}
	order["index"] = (int(order.get("index", 0)) + 1) % items.size()
	return items[int(order["index"])]


# --- Quickbar par personnage ----------------------------------------------

static func get_character_quickbar(model: Dictionary, character_id: String) -> Array:
	if model.is_empty() or character_id.is_empty():
		return []
	var quickbars: Dictionary = model.get("quickbars", {})
	var slots_variant: Variant = quickbars.get(character_id, [])
	var slots: Array = slots_variant if slots_variant is Array else []
	return slots.duplicate(true)


static func sanitize_quickbar_slot(slot: Dictionary) -> Dictionary:
	var action := str(slot.get("action", "action"))
	if not QUICKBAR_ACTIONS.has(action):
		action = "action"
	var visibility := str(slot.get("visibility", "table"))
	if not VISIBILITIES.has(visibility):
		visibility = "table"
	return {
		"label": str(slot.get("label", "")).strip_edges().left(40),
		"action": action,
		"formula": str(slot.get("formula", "")).strip_edges().left(120),
		"visibility": visibility,
		"icon": str(slot.get("icon", "")).left(8),
	}


static func set_character_quickbar(model: Dictionary, character_id: String, slots: Array) -> void:
	if character_id.is_empty() or model.is_empty():
		return
	var quickbars: Dictionary = model["quickbars"]
	var clean: Array = []
	for slot_variant in slots:
		if clean.size() >= QUICKBAR_SLOTS:
			break
		if slot_variant is Dictionary:
			clean.append(sanitize_quickbar_slot(slot_variant))
	quickbars[character_id] = clean


static func set_quickbar_slot(model: Dictionary, character_id: String, index: int, slot: Dictionary) -> bool:
	if index < 0 or index >= QUICKBAR_SLOTS:
		return false
	var slots := get_character_quickbar(model, character_id)
	while slots.size() <= index:
		slots.append({})
	slots[index] = sanitize_quickbar_slot(slot)
	set_character_quickbar(model, character_id, slots)
	return true


static func clear_quickbar_slot(model: Dictionary, character_id: String, index: int) -> bool:
	var slots := get_character_quickbar(model, character_id)
	if index < 0 or index >= slots.size():
		return false
	slots.remove_at(index)
	set_character_quickbar(model, character_id, slots)
	return true


## Quickbar telle que la voit un joueur : les emplacements `gm` disparaissent.
static func filter_quickbar_for_player(model: Dictionary, character_id: String, viewer_is_gm: bool) -> Array:
	var out: Array = []
	for slot_variant in get_character_quickbar(model, character_id):
		var slot: Dictionary = slot_variant
		if viewer_is_gm or str(slot.get("visibility", "table")) != "gm":
			out.append(slot)
	return out
