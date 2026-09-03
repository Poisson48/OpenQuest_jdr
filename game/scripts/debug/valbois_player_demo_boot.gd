extends Node

## Boot démo Valbois en vue JOUEUR : carte plein écran + HUD overlay.

const PORTRAIT_RES := "res://assets/portraits/voleur_kael.png"
const PORTRAIT_STAGING := "user://import_staging/voleur_kael.png"

func _ready() -> void:
	var md := MapData
	var village := _find_valbois(md)
	if village.is_empty():
		push_error("[VALBOIS PLAYER] Carte Valbois introuvable. Lance d'abord : godot -s res://scripts/tests/valbois_diorama_setup.gd")
		get_tree().quit(1)
		return

	var village_id := str(village.get("id", ""))
	var area: Dictionary = md.get_area(village, "area-place-marche")
	var place_id := str(area.get("targetMapId", ""))
	if place_id.is_empty() and village.get("areas") is Array and not (village["areas"] as Array).is_empty():
		place_id = str((village["areas"][0] as Dictionary).get("targetMapId", ""))

	var portrait_path := _import_portrait(md)
	GameData.reload_builtin_scenarios()
	var party: Array = [_make_kael(portrait_path)]
	var map_ids: Array = [village_id]
	if not place_id.is_empty():
		map_ids.append(place_id)

	# Partie solo avec MJ humain distant (simulé) — le client local est JOUEUR.
	GameData.create_new_game("demo-couronne-fracturee", "solo", "human", "long", party, map_ids)
	GameData.active_game["gmName"] = "MJ Distant"
	GameData.active_game["waitingForGm"] = false
	GameData.active_game["forcePlayerView"] = true
	GameData.active_game["mapModeOverrides"] = {village_id: "complex"}
	if not place_id.is_empty():
		GameData.active_game["mapModeOverrides"][place_id] = "complex"
	GameData.active_game["mapNavigation"] = {
		"view": "local",
		"localMapId": village_id,
		"worldMapId": null,
		"worldCell": null,
		"areaStack": [],
	}
	GameData.ensure_map_play_state()

	var w: int = int(village.get("width", 20))
	var h: int = int(village.get("height", 16))
	var tx := int(round(float(w) * 0.50))
	var ty := int(round(float(h) * 0.58))
	GameData.place_member_token(village_id, tx, ty, "hero-kael-voleur")

	GameData.add_log_entry("Système", "Vue joueur — carte plein écran. HUD : action, dés, fiche.", "system")
	GameData.add_log_entry("Kael", "Je m'approche de la Place du Marché…", "player")
	GameData.save_active_game()

	MultiplayerManager.player_role = "player"
	MultiplayerManager.player_name = "Kael"
	MultiplayerManager.is_gm = false

	print("[VALBOIS PLAYER] immersive HUD @", tx, ",", ty, " portrait=", portrait_path)
	get_tree().call_deferred("change_scene_to_file", "res://scenes/session/session.tscn")

func _make_kael(portrait_path: String) -> Dictionary:
	return {
		"id": "hero-kael-voleur",
		"name": "Kael",
		"race": "Humain",
		"class": "Voleur",
		"roster": "general",
		"hp": 11,
		"ac": 14,
		"isPlayer": true,
		"isHuman": true,
		"isBot": false,
		"clientId": "joueur-demo",
		"portrait": portrait_path,
		"image": portrait_path,
		"stats": {"str": 10, "dex": 16, "con": 12, "int": 11, "wis": 13, "cha": 9},
		"temperament": "Méfiant · Silencieux · Opportuniste",
		"stress": "Tendu",
		"quirk": "Compte les sorties d'une pièce avant d'y entrer.",
		"backstory": "Fils d'une couturière de Valbois, Kael revient pour une dette ancienne.",
		"barks": [
			"Les ombres mentent rarement. Les hommes, toujours.",
			"Un regard de trop… je disparais.",
		],
	}

func _import_portrait(md) -> String:
	var sources: Array = [
		ProjectSettings.globalize_path(PORTRAIT_RES),
		ProjectSettings.globalize_path(PORTRAIT_STAGING),
		"/home/leo/Downloads/ChatGPT Image 3 sept. 2026, 14_01_18.png",
	]
	for src_variant in sources:
		var src := str(src_variant)
		if src.is_empty() or not FileAccess.file_exists(src):
			continue
		var dest: String = md.import_token_image(src)
		if not dest.is_empty():
			return dest
	if ResourceLoader.exists(PORTRAIT_RES) or FileAccess.file_exists(ProjectSettings.globalize_path(PORTRAIT_RES)):
		return PORTRAIT_RES
	return ""

func _find_valbois(md) -> Dictionary:
	var best: Dictionary = {}
	for m_variant in md.maps:
		var m: Dictionary = m_variant
		if not str(m.get("title", "")).begins_with("Valbois — Village"):
			continue
		if str(m.get("backgroundImage", "")).is_empty():
			continue
		best = m
	return best
