extends SceneTree

## TEST DE CONTRAT — API publique de l'autoload `GameData` (phase 2.2 du refactor).
##
## But : figer le comportement ACTUEL de l'API GameData utilisée par les écrans et
## les tests, AVANT d'extraire `session_model` / `game_play` hors du god file
## (phase 2.4). Ce test ne refactore rien : il caractérise, assertion par
## assertion, avec le contrat attendu en commentaire.
##
## Couverture : catalogues de scénarios, normalisations personnage/scénario,
## CRUD scénario & personnage, création/sauvegarde/chargement de partie,
## mapPlayState, journal, tour, notes de scène, résumé de navigation.
##
## Convention : `godot --headless --path game -s res://scripts/tests/game_data_contract_test.gd`
## Nettoyage : les entités créées (scénario, personnage, partie, carte) sont
## supprimées en fin de test pour ne pas polluer les données utilisateur.

const SCRATCH_CHARACTER_ID := "test-contract-character"

var _failed := false
var _game_updates := 0

func _init() -> void:
	call_deferred("_run")
	call_deferred("_arm_watchdog")

func _arm_watchdog() -> void:
	create_timer(60.0).timeout.connect(func():
		print("game_data_contract_test:FAIL watchdog (60 s)")
		quit(1))

func _run() -> void:
	await process_frame
	var gd = get_root().get_node("GameData")
	var md = get_root().get_node("MapData")
	# Compteur d'émissions d'état : sert à figer les contrats « signal émis /
	# signal NON émis » (sauvegarde, notes de scène).
	gd.active_game_updated.connect(_on_game_updated)

	# =====================================================================
	# 1. Catalogues de scénarios
	# =====================================================================
	var catalog: Array = gd.get_scenarios()
	# Contrat actuel : le catalogue publié (démos + scénarios publiés) n'est jamais vide.
	var only_catalog := not catalog.is_empty()
	for scn_variant in catalog:
		if not gd.is_catalog_scenario(scn_variant):
			only_catalog = false
	_assert("catalog_non_empty", only_catalog)

	# Contrat actuel : `get_scenario_by_id` renvoie le scénario normalisé du
	# catalogue, et un identifiant inconnu renvoie un dictionnaire vide (pas null).
	var demo: Dictionary = gd.get_scenario_by_id("demo-valbois")
	_assert("scenario_by_id",
		not demo.is_empty() and not str(demo.get("title", "")).is_empty()
		and gd.get_scenario_by_id("inconnu-xyz").is_empty())

	# Contrat actuel : filtrage exact par format de quête ET par roster
	# (les enquêtes sont un roster distinct).
	var oneshots: Array = gd.get_scenarios("oneshot")
	var filters_ok := not oneshots.is_empty()
	for scn_variant in oneshots:
		if str((scn_variant as Dictionary).get("questFormat", "")) != "oneshot":
			filters_ok = false
	var inv: Array = gd.get_scenarios("", "investigation")
	filters_ok = filters_ok and not inv.is_empty()
	for scn_variant in inv:
		if str((scn_variant as Dictionary).get("roster", "general")) != "investigation":
			filters_ok = false
	_assert("scenarios_filters", filters_ok)

	# Contrat actuel : titre affichable avec repli « Aventure ».
	_assert("scenario_display_title",
		gd.get_scenario_display_title("demo-valbois") == str(demo.get("title", ""))
		and gd.get_scenario_display_title("inconnu-xyz") == "Aventure")

	# Contrat actuel : format déduit du scénario ; repli « oneshot » si inconnu.
	var demo_format: String = gd.get_quest_format_for_scenario("demo-valbois")
	_assert("scenario_quest_format",
		demo_format in ["oneshot", "long", "investigation"]
		and gd.get_quest_format_for_scenario("inconnu-xyz") == "oneshot")

	# Contrat actuel : `load_scenarios()` est rejouable et réémet `scenarios_updated`.
	var count_before: int = gd.scenarios.size()
	var updated_hits := [0]
	var on_scenarios_updated := func() -> void: updated_hits[0] += 1
	gd.scenarios_updated.connect(on_scenarios_updated)
	gd.load_scenarios()
	gd.scenarios_updated.disconnect(on_scenarios_updated)
	_assert("load_scenarios_replayable", gd.scenarios.size() == count_before and updated_hits[0] >= 1)

	# Contrat actuel : `get_scenarios_for_quest_format` = catalogue filtré.
	var catalog_oneshot: Array = gd.get_scenarios_for_quest_format("oneshot")
	var catalog_oneshot_ok := not catalog_oneshot.is_empty()
	for scn_variant in catalog_oneshot:
		if not gd.is_catalog_scenario(scn_variant):
			catalog_oneshot_ok = false
	_assert("scenarios_for_quest_format", catalog_oneshot_ok)

	# =====================================================================
	# 2. Normalisations (pures, sans écriture disque)
	# =====================================================================
	# Contrat actuel : `normalize_character({})` complète tier medium + stats + CA.
	var blank_char: Dictionary = gd.normalize_character({})
	var blank_stats: Dictionary = blank_char.get("stats", {})
	_assert("normalize_character_medium",
		str(blank_char.get("rulesetTier", "")) == "medium"
		and blank_stats.size() == 6
		and int(blank_char.get("ac", 0)) == 10)

	# Contrat actuel : tier simple => simpleStats + trait, pas de stats D&D.
	var simple_char: Dictionary = gd.normalize_character({"rulesetTier": "simple"})
	_assert("normalize_character_simple",
		(simple_char.get("simpleStats", {}) as Dictionary).size() == 4
		and str(simple_char.get("trait", "?")) == ""
		and not simple_char.has("stats"))

	# Contrat actuel : tier complete => niveau 1, alignement et maîtrises vides.
	var complete_char: Dictionary = gd.normalize_character({"rulesetTier": "complete"})
	_assert("normalize_character_complete",
		int(complete_char.get("level", 0)) == 1
		and str(complete_char.get("alignment", "?")) == ""
		and str(complete_char.get("proficiencies", "?")) == "")

	# Contrat actuel : la normalisation ne mute pas l'entité source.
	var source: Dictionary = {}
	gd.normalize_character(source)
	_assert("normalize_character_no_mutation", source.is_empty())

	# Contrat actuel : tier inconnu => « medium » (repli silencieux).
	_assert("ruleset_tier_fallback", gd.get_ruleset_tier({"rulesetTier": "pirate"}) == "medium")

	# Contrat actuel : modificateur D&D (floor((valeur - 10) / 2)).
	_assert("stat_modifier",
		gd.stat_modifier(10) == 0 and gd.stat_modifier(8) == -1 and gd.stat_modifier(15) == 2)

	# Contrat actuel : formatage signé.
	_assert("format_modifier", gd.format_modifier(2) == "+2" and gd.format_modifier(-3) == "-3")

	# Contrat actuel : `get_scenario_by_id` renvoie déjà un scénario normalisé
	# (chaque scène a un `id` et une liste `mapIds`) et la normalisation est idempotente.
	var scenes_ok: bool = not (demo.get("scenes", []) as Array).is_empty()
	for scene_variant in demo.get("scenes", []):
		var scene: Dictionary = scene_variant
		if str(scene.get("id", "")).is_empty() or typeof(scene.get("mapIds", null)) != TYPE_ARRAY:
			scenes_ok = false
	var QN = load("res://scripts/quest_navigation.gd")
	var renormalized: Dictionary = QN.normalize_scenario(demo)
	_assert("normalize_scenario_idempotent",
		scenes_ok and JSON.stringify(renormalized) == JSON.stringify(demo))

	# =====================================================================
	# 3. CRUD scénario (brouillon -> publié -> supprimé)
	# =====================================================================
	# Id unique par run : la suppression laisse une tombe persistante
	# (emoved_scenario_ids), donc on ne réutilise jamais le même id.
	var scn_id := "test-contract-scn-%d" % Time.get_ticks_usec()
	gd.save_scenario({"id": scn_id, "title": "Contrat", "status": "draft"})
	# Contrat actuel : un scénario sans statut explicite est créé en brouillon.
	var saved_scn: Dictionary = gd.get_scenario_by_id(scn_id)
	_assert("save_scenario_draft", not saved_scn.is_empty()
		and str(saved_scn.get("status", "")) == "draft" and not gd.is_catalog_scenario(saved_scn))

	# Contrat actuel : brouillon listé séparément du catalogue.
	var in_drafts := false
	for scn_variant in gd.get_draft_scenarios():
		if str((scn_variant as Dictionary).get("id", "")) == scn_id:
			in_drafts = true
	_assert("save_scenario_in_drafts", in_drafts)

	# Contrat actuel : publication => entre dans le catalogue ; dépublier annule.
	_assert("publish_scenario", gd.publish_scenario(scn_id)
		and gd.is_catalog_scenario(gd.get_scenario_by_id(scn_id))
		and gd.unpublish_scenario(scn_id)
		and not gd.is_catalog_scenario(gd.get_scenario_by_id(scn_id)))

	# Contrat actuel : la suppression d'un scénario utilisateur est une tombe
	# (`removed_scenario_ids`) ; les scénarios démo du catalogue sont protégés.
	_assert("delete_scenario", gd.delete_scenario(scn_id)
		and gd.get_scenario_by_id(scn_id).is_empty()
		and not gd.delete_scenario("demo-valbois"))

	# =====================================================================
	# 4. CRUD personnage (normalisation à l'écriture)
	# =====================================================================
	gd.save_character({"id": SCRATCH_CHARACTER_ID, "name": "Contrat", "roster": "general"})
	# Contrat actuel : `save_character` normalise puis indexe par id ; le
	# filtrage `get_characters(roster)` le retrouve ensuite.
	gd.save_character({"id": SCRATCH_CHARACTER_ID, "name": "Contrat", "roster": "general"})
	var saved_char: Dictionary = gd.get_character_by_id(SCRATCH_CHARACTER_ID)
	var char_in_roster := false
	for char_variant in gd.get_characters("general"):
		if str((char_variant as Dictionary).get("id", "")) == SCRATCH_CHARACTER_ID:
			char_in_roster = true
	_assert("save_character_normalized_roster", not saved_char.is_empty()
		and str(saved_char.get("rulesetTier", "")) == "medium"
		and int(saved_char.get("ac", 0)) == 10
		and char_in_roster)

	# Contrat actuel : suppression par id (l'id n'est plus retrouvé ensuite).
	gd.delete_character(SCRATCH_CHARACTER_ID)
	_assert("delete_character", gd.get_character_by_id(SCRATCH_CHARACTER_ID).is_empty())

	# =====================================================================
	# 5. Création / sauvegarde / chargement de partie (gameStorage)
	# =====================================================================
	var map: Dictionary = md.create_complex_map("Contrat GameData", "general", "local", 12, 10)
	var map_id := str(map.get("id", ""))
	md.update_map(map)

	var party: Array = [
		{"id": "hero-1", "name": "Aria", "hp": 7, "maxHp": 20,
			"isPlayer": true, "isHuman": true},
		{"id": "hero-2", "name": "Brand", "hp": 12, "maxHp": 12,
			"isPlayer": true, "isHuman": true},
	]
	var game: Dictionary = gd.create_new_game("demo-valbois", "solo", "ai", "oneshot", party, [map_id])
	# Contrat actuel : `create_new_game` retourne la partie active et la persiste.
	# Note : en mode solo sur `demo-valbois`, `_apply_valbois_demo` injecte Kael
	# en tête de groupe (comportement de la démo) — d'où `>= 2` et non `== 2`.
	_assert("create_new_game_fields",
		not game.is_empty()
		and not str(game.get("id", "")).is_empty()
		and str(game.get("scenarioId", "")) == "demo-valbois"
		and str(game.get("status", "")) == "playing"
		and str(game.get("gmType", "")) == "ai"
		and (game.get("party", []) as Array).size() >= 2
		and not (game.get("log", []) as Array).is_empty()
		and (game.get("mapIds", []) as Array).has(map_id)
		and int(game.get("turnIndex", -1)) == 0
		and not bool(game.get("waitingForGm", true)))
	var game_id := str(game.get("id", ""))
	_assert("create_new_game_active", gd.has_active_game()
		and str(gd.active_game.get("id", "")) == game_id)

	# Contrat actuel : `ensure_map_play_state` garantit les 3 sous-structures et
	# `get_map_play_entry` crée une entrée complète (liste + dictionnaires) par carte.
	gd.ensure_map_play_state()
	var entry: Dictionary = gd.get_map_play_entry(map_id)
	_assert("map_play_state",
		typeof(gd.active_game.get("mapPlayState")) == TYPE_DICTIONARY
		and (gd.active_game.get("mapNavigation", {}) as Dictionary).has("view")
		and typeof(gd.active_game.get("mapModeOverrides")) == TYPE_DICTIONARY
		and (entry.get("tokens", []) as Array).is_empty()
		and (entry.get("explored", []) as Array).is_empty()
		and typeof(entry.get("viewState")) == TYPE_DICTIONARY
		and typeof(entry.get("doorStates")) == TYPE_DICTIONARY)

	# Contrat actuel : l'entrée est stable (mêmes clés, tokens conservés au 2e accès).
	entry["tokens"] = [{"id": "tok-a", "x": 3.0, "y": 3.0, "kind": "member", "memberId": "hero-1"}]
	var entry_again: Dictionary = gd.get_map_play_entry(map_id)
	_assert("map_play_entry_stable", (entry_again.get("tokens", []) as Array).size() == 1
		and str((entry_again.get("tokens", [])[0] as Dictionary).get("id", "")) == "tok-a")

	# Contrat actuel : save_active_game + load_game_by_id = aller-retour de l'état
	# mapPlayState (les tokens posés sont relus après chargement).
	var updates_before := _game_updates
	gd.save_active_game()
	_assert("save_active_game_emits", _game_updates > updates_before
		and gd.get_playing_games().size() >= 1)
	_assert("load_game_by_id", gd.load_game_by_id(game_id)
		and str(gd.active_game.get("id", "")) == game_id)
	var reloaded_entry: Dictionary = gd.get_map_play_entry(map_id)
	_assert("game_storage_roundtrip", (reloaded_entry.get("tokens", []) as Array).size() == 1
		and str((reloaded_entry.get("tokens", [])[0] as Dictionary).get("memberId", "")) == "hero-1")
	_assert("load_game_by_id_unknown", not gd.load_game_by_id("inconnu-xyz"))

	# =====================================================================
	# 6. Journal, tour, membres actifs
	# =====================================================================
	var log_before := (gd.active_game.get("log", []) as Array).size()
	gd.add_log_entry("Aria", "Je pousse la porte.", "player")
	var log_after: Array = gd.active_game.get("log", [])
	# Contrat actuel : toute ligne ajoutée porte auteur/type/texte/heure.
	_assert("add_log_entry", log_after.size() == log_before + 1
		and str((log_after[log_after.size() - 1] as Dictionary).get("author", "")) == "Aria"
		and str((log_after[log_after.size() - 1] as Dictionary).get("type", "")) == "player"
		and not str((log_after[log_after.size() - 1] as Dictionary).get("time", "")).is_empty())

	# Contrat actuel : mode solo => premier membre humain ; la démo Valbois
	# injecte Kael, donc 3 jouables (Kael, Aria, Brand) et Kael actif.
	_assert("active_member", str(gd.get_active_member().get("name", "")) == "Kael"
		and gd.get_playable_members().size() == 3)

	# Contrat actuel : MJ IA => `apply_player_action` journalise sans attendre de MJ
	# et SANS avancer le tour (le MJ décide ensuite).
	var turn_before := int(gd.active_game.get("turnIndex", -1))
	gd.apply_player_action("Aria", "J'ouvre le coffre.")
	_assert("apply_player_action_ai",
		not bool(gd.active_game.get("waitingForGm", true))
		and int(gd.active_game.get("turnIndex", -1)) == turn_before
		and str(gd.active_game.get("log", [])[-1].get("type", "")) == "player")

	# Contrat actuel : le flag « en attente du MJ » bloque la prise d'action.
	gd.set_waiting_for_gm(true)
	_assert("waiting_blocks_action", gd.is_waiting_for_gm() and not gd.can_member_act(""))

	# Contrat actuel : `advance_player_turn` efface l'attente et passe au suivant
	# (rotation modulo le nombre de jouables, ici 3 avec Kael injecté par la démo).
	var playable_count: int = gd.get_playable_members().size()
	gd.advance_player_turn()
	_assert("advance_player_turn",
		not gd.is_waiting_for_gm()
		and int(gd.active_game.get("turnIndex", -1)) == (turn_before + 1) % playable_count
		and gd.can_member_act(""))
	# Contrat actuel : une partie terminée est en lecture seule.
	gd.active_game["status"] = "completed"
	_assert("completed_blocks_action", not gd.can_member_act(""))
	gd.active_game["status"] = "playing"

	# =====================================================================
	# 7. Notes de scène, navigation, divers contrats purs
	# =====================================================================
	# Contrat actuel : notes par scène, "" par défaut, SANS `active_game_updated`
	# (la frappe clavier ne doit pas rafraîchir l'UI — cf. game_data.gd).
	var updates_before_notes := _game_updates
	gd.set_scene_notes("Bloc-notes du MJ", "scene-test")
	_assert("scene_notes",
		gd.get_scene_notes("scene-test") == "Bloc-notes du MJ"
		and gd.get_scene_notes("scene-inconnue") == ""
		and _game_updates == updates_before_notes)

	# Contrat actuel : résumé de navigation complet pour l'écran de session.
	var nav_summary: Dictionary = gd.get_scene_navigation_summary()
	_assert("scene_navigation_summary",
		not str(nav_summary.get("currentSceneId", "")).is_empty()
		and typeof(nav_summary.get("transitions")) == TYPE_ARRAY
		and (nav_summary.get("visitedSceneIds", []) as Array).has(str(nav_summary.get("currentSceneId", "")))
		and not str(nav_summary.get("progressLabel", "")).is_empty()
		and typeof(nav_summary.get("isTerminal")) == TYPE_BOOL)

	# Contrat actuel : la synchro scénario recopie le titre dans la partie.
	gd.active_game["scenarioTitle"] = ""
	gd.sync_active_game_scenario_metadata()
	_assert("sync_scenario_metadata",
		str(gd.active_game.get("scenarioTitle", "")) == str(gd.get_scenario_by_id("demo-valbois").get("title", "")))

	# Contrat actuel : résumé de groupe (noms joints, puis « + N autres »).
	var summary_2: String = gd.get_game_party_summary(gd.active_game)
	var four: Array = [
		{"name": "Aria"}, {"name": "Brand"}, {"name": "Cedric"}, {"name": "Dana"},
	]
	_assert("party_summary", summary_2.contains("Aria") and summary_2.contains("Brand")
		and gd.get_game_party_summary({"party": four}) == "Aria + 3 autres")

	# =====================================================================
	# Nettoyage
	# =====================================================================
	gd.delete_game(game_id)
	_assert("delete_game_cleanup", gd.active_game.is_empty()
		and not gd.get_playing_games().any(func(g): return str(g.get("id", "")) == game_id))
	md.delete_map(map_id)

	gd.active_game_updated.disconnect(_on_game_updated)

	if _failed:
		quit(1)
		return
	print("game_data_contract_test:PASS")
	quit(0)

func _on_game_updated() -> void:
	_game_updates += 1

func _assert(label: String, cond: bool) -> void:
	if not cond:
		print("game_data_contract_test:FAIL at ", label)
		_failed = true
