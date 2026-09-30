extends RefCounted
class_name Inventory

## Gestion de l'inventaire de groupe — logique pure.
##
## Travaille directement sur le dictionnaire `active_game` (partagé par référence).
## Chaque membre a un tableau `inventory` d'items `{ id, name, qty }`.

## Retourne l'inventaire d'un membre (tableau vide si absent).
static func get_member_inventory(game: Dictionary, member_id: String) -> Array:
	var m := _find_member(game, member_id)
	if m.is_empty():
		return []
	if not m.has("inventory") or not m["inventory"] is Array:
		m["inventory"] = []
	return m["inventory"]

## Ajoute un item à l'inventaire d'un membre. Regroupe par `item_id`.
static func give_item_to_member(game: Dictionary, member_id: String, item_id: String, item_name: String, qty: int = 1) -> bool:
	var inv := get_member_inventory(game, member_id)
	if inv.is_empty() and _find_member(game, member_id).is_empty():
		return false
	for item in inv:
		if item.get("id", "") == item_id:
			item["qty"] = int(item.get("qty", 1)) + qty
			return true
	inv.append({ "id": item_id, "name": item_name, "qty": qty })
	return true

## Retire un item de l'inventaire d'un membre. Retourne `true` si retiré.
static func take_item_from_member(game: Dictionary, member_id: String, item_id: String, qty: int = 1) -> bool:
	var inv := get_member_inventory(game, member_id)
	for i in inv.size():
		var item: Dictionary = inv[i]
		if item.get("id", "") == item_id:
			var current := int(item.get("qty", 1))
			if current < qty:
				return false
			item["qty"] = current - qty
			if item["qty"] <= 0:
				inv.remove_at(i)
			return true
	return false

## Transfère un item d'un membre à un autre.
static func transfer_item(game: Dictionary, from_member_id: String, to_member_id: String, item_id: String, qty: int = 1) -> bool:
	if not member_has_item(game, from_member_id, item_id, qty):
		return false
	var item_name := _item_name(game, from_member_id, item_id)
	if not take_item_from_member(game, from_member_id, item_id, qty):
		return false
	return give_item_to_member(game, to_member_id, item_id, item_name, qty)

## Retourne `true` si le membre possède au moins `qty` de l'item.
static func member_has_item(game: Dictionary, member_id: String, item_id: String, qty: int = 1) -> bool:
	for item in get_member_inventory(game, member_id):
		if item.get("id", "") == item_id:
			return int(item.get("qty", 1)) >= qty
	return false

## Retourne `true` si le membre possède une lanterne.
static func member_has_lantern(game: Dictionary, member_id: String) -> bool:
	for item in get_member_inventory(game, member_id):
		if _is_lantern(item):
			return true
	return false

## Retourne `true` si au moins un membre du groupe possède une lanterne.
static func party_has_lantern(game: Dictionary) -> bool:
	for m in game.get("party", []):
		if member_has_lantern(game, m.get("id", "")):
			return true
	return false

## Retourne `true` si le membre local est aveugle à la nuit (sans lanterne).
static func local_member_is_night_blind(game: Dictionary, local_member_id: String) -> bool:
	return not member_has_lantern(game, local_member_id)

# ---------------------------------------------------------------------------
# Helpers internes
# ---------------------------------------------------------------------------

static func _find_member(game: Dictionary, member_id: String) -> Dictionary:
	for m in game.get("party", []):
		if m.get("id", "") == member_id:
			return m
	return {}

static func _item_name(game: Dictionary, member_id: String, item_id: String) -> String:
	for item in get_member_inventory(game, member_id):
		if item.get("id", "") == item_id:
			return item.get("name", item_id)
	return item_id

static func _is_lantern(item: Dictionary) -> bool:
	var id: String = item.get("id", "").to_lower()
	var name: String = item.get("name", "").to_lower()
	return "lantern" in id or "lanterne" in id or "lantern" in name or "lanterne" in name
