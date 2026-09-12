extends RefCounted
class_name SessionViewModel

## Pont unique entre l'état de partie (GameData / MultiplayerManager) et les
## panneaux de session.
##
## L'ancienne session rebranchait tout sur `active_game_updated` : une ligne de
## journal reconstruisait le groupe, les barres d'outils et la carte. Ici on
## compare l'état précédent et on n'émet que ce qui a réellement bougé.

const QuestNavigation = preload("res://scripts/quest_navigation.gd")

signal header_changed(header: Dictionary)
signal party_changed(members: Array, active_id: String)
signal log_reset(entries: Array)
signal log_appended(entry: Dictionary)
signal turn_changed(turn: Dictionary)
signal navigation_changed(nav: Dictionary)
signal map_changed()
signal role_changed(role: SessionRoleView)
signal net_changed(net: Dictionary)
signal dice_result(text: String, secret: bool)
signal notes_changed(text: String)

var role: SessionRoleView = null

var _header: Dictionary = {}
var _party_signature: String = ""
var _turn: Dictionary = {}
var _nav_signature: String = ""
var _map_signature: String = ""
var _net: Dictionary = {}
var _log_count: int = 0
var _notes: String = ""
var _bound: bool = false

# ---------------------------------------------------------------------------
# Cycle de vie
# ---------------------------------------------------------------------------

func bind() -> void:
	if _bound:
		return
	_bound = true
	GameData.active_game_updated.connect(_on_active_game_updated)
	MultiplayerManager.game_state_received.connect(_on_net_game_state)
	MultiplayerManager.log_entry_received.connect(_on_net_log_entry)
	MultiplayerManager.dice_result_received.connect(_on_net_dice_result)
	MultiplayerManager.map_op_received.connect(_on_net_map_op)

func unbind() -> void:
	if not _bound:
		return
	_bound = false
	if GameData.active_game_updated.is_connected(_on_active_game_updated):
		GameData.active_game_updated.disconnect(_on_active_game_updated)
	if MultiplayerManager.game_state_received.is_connected(_on_net_game_state):
		MultiplayerManager.game_state_received.disconnect(_on_net_game_state)
	if MultiplayerManager.log_entry_received.is_connected(_on_net_log_entry):
		MultiplayerManager.log_entry_received.disconnect(_on_net_log_entry)
	if MultiplayerManager.dice_result_received.is_connected(_on_net_dice_result):
		MultiplayerManager.dice_result_received.disconnect(_on_net_dice_result)
	if MultiplayerManager.map_op_received.is_connected(_on_net_map_op):
		MultiplayerManager.map_op_received.disconnect(_on_net_map_op)

## Recalcule tout et n'émet que les différences. `full` force la réémission
## (premier affichage, ou reprise après un changement de rôle).
func refresh(full: bool = false) -> void:
	GameData.sync_active_game_scenario_metadata()
	var state: Dictionary = GameData.active_game

	var next_role := SessionRoleView.resolve(state, MultiplayerManager)
	if full or role == null or not next_role.equals(role):
		role = next_role
		role_changed.emit(role)
	else:
		role = next_role

	var header := _build_header(state)
	if full or header != _header:
		_header = header
		header_changed.emit(header)

	var party: Array = state.get("party", [])
	var active_id: String = str(GameData.get_active_member().get("id", ""))
	var party_sig := _party_signature_of(party, active_id)
	if full or party_sig != _party_signature:
		_party_signature = party_sig
		party_changed.emit(party, active_id)

	var turn := _build_turn(state)
	if full or turn != _turn:
		_turn = turn
		turn_changed.emit(turn)

	var nav := _build_navigation(state)
	var nav_sig := JSON.stringify(nav)
	if full or nav_sig != _nav_signature:
		_nav_signature = nav_sig
		navigation_changed.emit(nav)

	var map_sig := _map_signature_of(state)
	if full or map_sig != _map_signature:
		_map_signature = map_sig
		map_changed.emit()

	var net := _build_net()
	if full or net != _net:
		_net = net
		net_changed.emit(net)

	var notes := GameData.get_scene_notes()
	if full or notes != _notes:
		_notes = notes
		notes_changed.emit(notes)

	_sync_log(state, full)

# ---------------------------------------------------------------------------
# Construction des charges utiles
# ---------------------------------------------------------------------------

func _build_header(state: Dictionary) -> Dictionary:
	var scenario := GameData.get_scenario_by_id(str(state.get("scenarioId", "")))
	return {
		"title": GameData.get_scenario_display_title(),
		"progress": QuestNavigation.format_progress_label(scenario, state),
		"status": str(state.get("status", "playing")),
		"mode": str(state.get("mode", "solo")),
	}

func _build_turn(state: Dictionary) -> Dictionary:
	if state.is_empty() or str(state.get("status", "")) == "completed":
		return {
			"headline": "Aventure terminée",
			"hint": "Consultez le journal ou quittez la session.",
			"tone": "muted",
		}
	var actor := GameData.get_active_member()
	var actor_name: String = str(actor.get("name", "?")) if not actor.is_empty() else "?"
	var waiting: bool = GameData.is_waiting_for_gm()

	if not bool(state.get("gmType", "ai") == "human"):
		return {
			"headline": "À vous de jouer — %s" % actor_name,
			"hint": "Décrivez votre action. Les compagnons joueront ensuite.",
			"tone": "active",
		}

	if role != null and role.kind == SessionRoleView.KIND_GM:
		if waiting:
			return {
				"headline": "Action de %s — répondez puis validez le tour" % actor_name,
				"hint": "Diffuser une réponse sans changer de joueur. Tour suivant passe la main.",
				"tone": "alert",
			}
		if GameData.get_playable_members().size() <= 1:
			return {
				"headline": "Table MJ — %s" % actor_name,
				"hint": "Vous pilotez l'aventure ; les joueurs agissent depuis leurs clients.",
				"tone": "idle",
			}
		return {
			"headline": "Table MJ — tour de %s" % actor_name,
			"hint": "Le joueur actif doit agir. Tour suivant passe au suivant.",
			"tone": "idle",
		}

	if waiting:
		return {
			"headline": "En attente du MJ",
			"hint": "%s prépare la suite..." % GameData.get_gm_display_name(),
			"tone": "muted",
		}
	if role != null and not role.can_submit_action:
		return {
			"headline": "Tour de %s" % actor_name,
			"hint": "Ce n'est pas encore votre tour.",
			"tone": "muted",
		}
	return {
		"headline": "Votre tour — %s" % actor_name,
		"hint": "Décrivez l'action de votre personnage.",
		"tone": "active",
	}

func _build_navigation(state: Dictionary) -> Dictionary:
	if state.is_empty():
		return {}
	var scenario := GameData.get_scenario_by_id(str(state.get("scenarioId", "")))
	var summary := GameData.get_scene_navigation_summary()
	var current_id := str(summary.get("currentSceneId", ""))
	var visited: Array = summary.get("visitedSceneIds", [])
	var scenes: Array = []
	for scene_variant in scenario.get("scenes", []):
		if typeof(scene_variant) != TYPE_DICTIONARY:
			continue
		var scene: Dictionary = scene_variant
		var scene_id := str(scene.get("id", ""))
		scenes.append({
			"id": scene_id,
			"label": QuestNavigation.format_picker_label(scene, scene_id == current_id, visited.has(scene_id)),
			"current": scene_id == current_id,
		})
	var npcs: Array = []
	for npc_variant in GameData.list_session_npcs():
		var npc: Dictionary = npc_variant
		npcs.append({
			"name": str(npc.get("name", "PNJ")),
			"role": str(npc.get("role", "")),
			"emoji": str(npc.get("emoji", "")),
		})
	return {
		"scenes": scenes,
		"transitions": summary.get("transitions", []),
		"npcs": npcs,
		"terminal": bool(summary.get("isTerminal", false)),
		"waiting": GameData.is_waiting_for_gm(),
	}

func _build_net() -> Dictionary:
	if MultiplayerManager.is_p2p_active() and MultiplayerManager.is_in_room():
		var member := MultiplayerManager.get_my_party_member(GameData.active_game)
		var suffix := "" if member.is_empty() else " · %s" % member.get("name", "")
		var role_name := "MJ" if MultiplayerManager.is_p2p_host() else "joueur"
		return { "online": true, "text": "P2P — %s%s" % [role_name, suffix] }
	return { "online": false, "text": "Partie locale" }

func _party_signature_of(party: Array, active_id: String) -> String:
	var parts: PackedStringArray = [active_id]
	for member_variant in party:
		var member: Dictionary = member_variant
		var inv_sig := JSON.stringify(member.get("inventory", []))
		parts.append("%s|%s|%s|%s|%s|%s" % [
			member.get("id", ""), member.get("name", ""),
			member.get("hp", 0), member.get("ac", 0),
			member.get("portrait", member.get("image", "")),
			inv_sig,
		])
	return "¤".join(parts)

## Ce qui oblige la carte à se reconfigurer — pas la narration ni les dés.
func _map_signature_of(state: Dictionary) -> String:
	return JSON.stringify({
		"maps": state.get("mapIds", []),
		"currentMapId": state.get("currentMapId", ""),
		"nav": state.get("mapNavigation", {}),
		"overrides": state.get("mapModeOverrides", {}),
		"play": state.get("mapPlayState", state.get("mapPlay", {})),
		"status": state.get("status", ""),
	})

func _sync_log(state: Dictionary, full: bool) -> void:
	var entries: Array = state.get("log", [])
	var count := entries.size()
	if full or count < _log_count:
		_log_count = count
		log_reset.emit(entries)
		return
	if count == _log_count:
		return
	for i in range(_log_count, count):
		var entry: Dictionary = entries[i]
		log_appended.emit(entry)
	_log_count = count

# ---------------------------------------------------------------------------
# Réactions aux signaux
# ---------------------------------------------------------------------------

func _on_active_game_updated() -> void:
	refresh()

func _on_net_game_state(state: Dictionary) -> void:
	GameData.apply_server_state(state)
	refresh()

func _on_net_log_entry(entry: Dictionary) -> void:
	# `apply_server_state` peut aussi apporter l'entrée : on ne l'affiche qu'une
	# fois en laissant le compteur suivre le journal réel.
	var entries: Array = GameData.active_game.get("log", [])
	if entries.size() > _log_count:
		_sync_log(GameData.active_game, false)
		return
	log_appended.emit(entry)

func _on_net_dice_result(res: Dictionary, formatted: String) -> void:
	var text := formatted if not formatted.is_empty() else GameData.format_dice_result(res)
	dice_result.emit(_plain(text), false)

func _on_net_map_op(_map_id: String, _op: Dictionary) -> void:
	map_changed.emit()

# ---------------------------------------------------------------------------
# Commandes (les panneaux n'écrivent jamais dans GameData directement)
# ---------------------------------------------------------------------------

func submit_action(text: String) -> void:
	var action := text.strip_edges()
	if action.is_empty() or role == null or not role.can_submit_action:
		return
	if MultiplayerManager.is_p2p_active() and GameData.has_active_game():
		MultiplayerManager.client_submit_action(action)
		return
	_process_local_action(action)

func roll(formula: String, secret: bool = false) -> void:
	var f := formula.strip_edges()
	if f.is_empty():
		return
	if MultiplayerManager.is_p2p_active() and GameData.has_active_game():
		MultiplayerManager.client_request_dice_roll(f)
		return
	var res := GameData.roll_dice(f)
	if res.has("error"):
		dice_result.emit(str(res["error"]), false)
		return
	var formatted := GameData.format_dice_result(res)
	dice_result.emit(_plain(formatted), secret)
	if secret and role != null and role.can_roll_secret:
		return
	GameData.add_log_entry("Dé", formatted, "dice")

func narrate(text: String) -> void:
	var body := text.strip_edges()
	if body.is_empty() or role == null or not role.can_narrate:
		return
	_broadcast(GameData.get_gm_display_name(), body, "gm")

func npc_line(npc_name: String, text: String) -> void:
	var body := text.strip_edges()
	if body.is_empty() or npc_name.is_empty() or role == null or not role.can_narrate:
		return
	_broadcast(npc_name, "« %s »" % body, "npc")

func advance_turn() -> void:
	if role == null or not role.can_narrate:
		return
	var p2p_live := (
		MultiplayerManager.is_p2p_active()
		and GameData.has_active_game()
		and (MultiplayerManager.is_p2p_host() or MultiplayerManager.is_in_room())
	)
	if p2p_live:
		MultiplayerManager.client_advance_turn()
		refresh()
		return
	GameData.advance_player_turn()
	refresh()

func go_to_scene(scene_id: String, reason: String = "Choix du MJ") -> void:
	if scene_id.is_empty() or role == null or not role.can_navigate_scenes:
		return
	if MultiplayerManager.is_p2p_active():
		MultiplayerManager.client_go_to_scene(scene_id, reason)
	else:
		GameData.go_to_scene(scene_id, reason)
	refresh(true)

func advance_scene() -> void:
	if role == null or not role.can_navigate_scenes:
		return
	if MultiplayerManager.is_p2p_active():
		MultiplayerManager.client_advance_scene()
	else:
		GameData.advance_scene()
	refresh(true)

func complete_scenario(reason: String = "Clôture par le MJ") -> void:
	if role == null or not role.can_navigate_scenes:
		return
	if MultiplayerManager.is_p2p_active():
		MultiplayerManager.client_complete_scenario(reason)
	else:
		GameData.complete_scenario(reason)
	refresh(true)

func set_notes(text: String) -> void:
	_notes = text
	GameData.set_scene_notes(text)

func _broadcast(author: String, text: String, log_type: String) -> void:
	# P2P seulement si un salon peut vraiment relayer. Sinon le return
	# après `client_gm_broadcast` avalait la ligne (démo locale, hôte mort).
	var p2p_live := (
		MultiplayerManager.is_p2p_active()
		and GameData.has_active_game()
		and (MultiplayerManager.is_p2p_host() or MultiplayerManager.is_in_room())
	)
	if p2p_live:
		MultiplayerManager.client_gm_broadcast(author, text, log_type)
		refresh()
		return
	GameData.add_log_entry(author, text, log_type)
	GameData.set_waiting_for_gm(false)
	refresh()


func _process_local_action(action: String) -> void:
	var actor := GameData.get_active_member()
	var player_name: String = str(actor.get("name", "Joueur")) if not actor.is_empty() else "Joueur"
	GameData.apply_player_action(player_name, action)
	if str(GameData.active_game.get("gmType", "ai")) == "ai":
		_simulate_ai_reply(action)
	refresh()

func _simulate_ai_reply(action: String) -> void:
	var replies := [
		"Le Maître du Jeu écoute votre décision. Les ombres s'étirent et le vent murmure...",
		"Votre initiative porte ses fruits : la situation évolue et révèle de nouveaux détails.",
		"Vous observez l'environnement avec vigilance. Quelque chose attire votre attention...",
		"Une tension palpable s'installe. Le destin attend l'issue de vos choix.",
	]
	var text: String = str(replies[randi() % replies.size()]) + "\n[i]« %s »[/i]" % action
	GameData.add_log_entry("MJ (IA)", text, "gm")

	var bots: Array = []
	for member_variant in GameData.active_game.get("party", []):
		var member: Dictionary = member_variant
		if bool(member.get("isBot", false)):
			bots.append(member)
	if bots.is_empty():
		return
	var bot: Dictionary = bots[randi() % bots.size()]
	var bot_lines := [
		"approuve votre idée et couvre vos arrières.",
		"scrute les alentours l'arme au poing.",
		"prend des notes et garde le silence.",
		"prépare un sortilège en prévision du danger.",
	]
	GameData.add_log_entry(
		str(bot.get("name", "Compagnon")),
		"%s %s" % [bot.get("name", "Compagnon"), bot_lines[randi() % bot_lines.size()]],
		"bot"
	)

static func _plain(text: String) -> String:
	return text.replace("[b]", "").replace("[/b]", "")
