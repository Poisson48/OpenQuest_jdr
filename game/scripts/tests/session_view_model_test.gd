extends SceneTree

## TEST DE CONTRAT — SessionViewModel (phase 2.1 du refactor).
##
## But : figer le comportement ACTUEL du pont `SessionViewModel` avant d'extraire
## les god files. Ce test ne refactore rien : il caractérise.
##
## Contrats vérifiés :
##   1. cycle de vie `bind()` / `unbind()` (idempotents, connexions réelles) ;
##   2. un `refresh(true)` émet une fois chaque signal (header, party, tour,
##      navigation, carte, réseau, notes, rôle, journal) ;
##   3. un `refresh()` sans changement n'émet RIEN ;
##   4. un changement MINIMAL n'émet QUE le signal concerné — pas de rebuild
##      complet (c'est la raison d'être de ce pont, cf. session_view_model.gd:7) :
##        - append journal      -> `log_appended` seul ;
##        - renommage d'un PJ   -> `party_changed` + `turn_changed` seuls ;
##        - barre de token      -> `map_changed` seule ;
##        - bloc-notes MJ       -> `notes_changed` seule (et GameData n'émet pas
##          `active_game_updated` : la frappe ne doit pas rafraîchir l'UI) ;
##        - journal tronqué     -> `log_reset` seul ;
##        - partie terminée     -> `turn_changed` (payload « Aventure terminée ») ;
##   5. les getters (`role`, payloads de signaux) exposent l'état attendu.
##
## Contrat de conception (commentaire, pas d'assertion possible) :
##   les panneaux de session ne doivent JAMAIS écrire dans `GameData` directement ;
##   ils appellent les commandes de `SessionViewModel` (`submit_action`, `roll`,
##   `narrate`, `advance_turn`, `go_to_scene`, `set_notes`…), qui seules peuvent
##   muter l'état / émettre vers le réseau. Ce test vérifie que ces commandes
##   restent le seul point d'entrée observable (signaux du pont).
##
## Convention : `godot --headless --path game -s res://scripts/tests/session_view_model_test.gd`

const GAME_ID := "test-session-view-model"

var _failed := false
var _counts: Dictionary = {}
var _payload: Dictionary = {}
var _game_updates := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	var gd = get_root().get_node("GameData")
	var md = get_root().get_node("MapData")
	var mm = get_root().get_node("MultiplayerManager")

	# --- État minimal (même recette que session_model_test.gd) -------------
	var map: Dictionary = md.create_complex_map("Contrat view model", "general", "local", 12, 10)
	var map_id := str(map.get("id", ""))
	md.update_map(map)

	gd.active_game = {
		"id": GAME_ID,
		"status": "playing",
		"scenarioId": "demo-valbois",
		"mode": "solo",
		"gmType": "ai",
		"gmName": "MJ (IA)",
		"mapIds": [map_id],
		"party": [
			{"id": "hero-1", "name": "Aria", "hp": 7, "maxHp": 20,
				"isPlayer": true, "isHuman": true, "inventory": []},
			{"id": "hero-2", "name": "Brand", "hp": 12, "maxHp": 12,
				"isPlayer": true, "isHuman": true, "inventory": []},
		],
		"mapPlayState": {},
		"mapNavigation": {"view": "local", "localMapId": map_id},
		"mapModeOverrides": {},
		"turnIndex": 0,
		"waitingForGm": false,
		"visitedSceneIds": [],
		"sceneHistory": [],
		"log": [],
	}
	gd.ensure_map_play_state()
	var entry: Dictionary = gd.get_map_play_entry(map_id)
	entry["tokens"] = [
		{"id": "tok-a", "x": 2.0, "y": 2.0, "kind": "member", "memberId": "hero-1"},
	]

	# Les scénarios intégrés doivent être présents (le test est headless).
	if gd.get_scenario_by_id("demo-valbois").is_empty():
		gd.reload_builtin_scenarios()

	var vm_script: GDScript = load("res://scripts/session/session_view_model.gd")
	var vm = vm_script.new()

	# Le contrat « pas d'écriture directe » part du fait que GameData ne pousse
	# l'état que par son signal ; on compte aussi les émissions réelles.
	gd.active_game_updated.connect(_on_game_updated)

	# =====================================================================
	# A. Cycle de vie bind / unbind
	# =====================================================================
	_assert("role_null_before_refresh", vm.role == null)

	vm.bind()
	_assert("bind_game_signal",
		gd.active_game_updated.is_connected(Callable(vm, "_on_active_game_updated")))
	_assert("bind_net_signal",
		mm.game_state_received.is_connected(Callable(vm, "_on_net_game_state")))

	vm.bind() # idempotent : ne doit pas doubler la connexion
	_assert("bind_idempotent", _connection_count(gd.active_game_updated, vm) == 1)

	vm.unbind()
	_assert("unbind_disconnects",
		not gd.active_game_updated.is_connected(Callable(vm, "_on_active_game_updated")))
	vm.unbind() # idempotent, ne doit pas lever
	_assert("unbind_idempotent", not vm._bound)

	# =====================================================================
	# B. Premier refresh complet : tout est émis une fois
	# =====================================================================
	_connect_vm_signals(vm)
	_reset_counts()
	vm.refresh(true)

	_assert("full_refresh_signals", _counts == {
		"role": 1, "header": 1, "party": 1, "log_reset": 1, "log_appended": 0,
		"turn": 1, "nav": 1, "map": 1, "net": 1, "notes": 1, "dice": 0,
	})

	var header: Dictionary = _payload.get("header", {})
	_assert("header_payload",
		header.has("title") and header.has("progress") and header.has("status") and header.has("mode")
		and str(header.get("title", "")) == gd.get_scenario_display_title())
	_assert("header_status_mode",
		str(header.get("status", "")) == "playing" and str(header.get("mode", "")) == "solo")

	var party_payload: Dictionary = _payload.get("party", {})
	_assert("party_payload",
		party_payload.get("members", []).size() == 2
		and str(party_payload.get("active_id", "")) == "hero-1")

	var turn: Dictionary = _payload.get("turn", {})
	_assert("turn_payload", str(turn.get("headline", "")).contains("Aria")
		and str(turn.get("tone", "")) == "active" and not str(turn.get("hint", "")).is_empty())

	var nav: Dictionary = _payload.get("nav", {})
	var nav_current := 0
	for scene_variant in nav.get("scenes", []):
		if bool((scene_variant as Dictionary).get("current", false)):
			nav_current += 1
	_assert("nav_payload",
		nav.has("scenes") and (nav.get("scenes", []) as Array).size() == 9
		and nav.has("transitions") and nav.has("npcs")
		and not bool(nav.get("terminal", true)) and not bool(nav.get("waiting", true))
		and nav_current == 1)

	_assert("net_payload_local",
		_payload.get("net", {}) == {"online": false, "text": "Partie locale"})
	_assert("notes_payload_empty", str(_payload.get("notes", "?")) == "")
	_assert("log_reset_payload_empty", (_payload.get("log_reset", null) as Array).is_empty())

	# --- Getters : le rôle résolu expose l'état attendu --------------------
	var role = vm.role
	_assert("role_solo_view",
		role != null and str(role.kind) == "solo"
		and str(role.label).contains("MJ IA")
		and bool(role.immersive) and not bool(role.completed))
	_assert("role_capabilities",
		not bool(role.can_narrate) and not bool(role.can_navigate_scenes)
		and bool(role.can_submit_action) and not bool(role.can_see_hidden_map))

	# =====================================================================
	# C. Refresh sans changement : zéro émission
	# =====================================================================
	_reset_counts()
	vm.refresh()
	_assert("no_change_no_signal", _counts == _zero_counts())

	# =====================================================================
	# D. Changements minimaux : seul le signal concerné part
	# =====================================================================
	# D1. Une ligne de journal -> log_appended seul (pas de rebuild complet).
	var log_entries: Array = gd.active_game["log"]
	log_entries.append({"author": "Aria", "type": "player",
		"text": "J'ouvre la porte.", "time": "00:00"})
	gd.active_game["log"] = log_entries
	_reset_counts()
	vm.refresh()
	_assert("log_append_signal", _counts["log_appended"] == 1)
	_assert("log_append_no_rebuild",
		_counts["header"] == 0 and _counts["party"] == 0 and _counts["turn"] == 0
		and _counts["nav"] == 0 and _counts["map"] == 0 and _counts["net"] == 0
		and _counts["notes"] == 0 and _counts["log_reset"] == 0)
	_assert("log_append_payload",
		str((_payload.get("log_appended", {}) as Dictionary).get("text", "")) == "J'ouvre la porte.")

	# D2. Renommage d'un PJ -> party_changed + turn_changed (headline), rien d'autre.
	gd.active_game["party"][0]["name"] = "Aria la Rôdeuse"
	_reset_counts()
	vm.refresh()
	_assert("party_change_signals", _counts["party"] == 1 and _counts["turn"] == 1)
	_assert("party_change_no_rebuild",
		_counts["header"] == 0 and _counts["nav"] == 0 and _counts["map"] == 0
		and _counts["notes"] == 0 and _counts["log_appended"] == 0)
	_assert("turn_headline_updated",
		str((_payload.get("turn", {}) as Dictionary).get("headline", "")).contains("Aria la Rôdeuse"))

	# D3. Barre de token -> map_changed seule (pas de header/party/tour).
	gd.set_token_bar(map_id, "tok-a", "hp", 7, 10)
	_reset_counts()
	vm.refresh()
	_assert("token_bar_map_signal", _counts["map"] == 1
		and _counts["header"] == 0 and _counts["party"] == 0 and _counts["turn"] == 0
		and _counts["nav"] == 0 and _counts["notes"] == 0 and _counts["log_appended"] == 0)

	# D4. Bloc-notes MJ -> notes_changed seule, et PAS d'`active_game_updated`
	#     (game_data.gd: la frappe clavier ne rafraîchit pas l'UI).
	_game_updates = 0
	gd.set_scene_notes("Le maître prépare une embuscade.")
	_assert("notes_no_active_game_updated", _game_updates == 0)
	_reset_counts()
	vm.refresh()
	_assert("notes_signal_only", _counts["notes"] == 1
		and _counts["header"] == 0 and _counts["party"] == 0 and _counts["turn"] == 0
		and _counts["map"] == 0 and _counts["log_appended"] == 0
		and str(_payload.get("notes", "")) == "Le maître prépare une embuscade.")

	# D5. Journal tronqué (reprise de partie) -> log_reset seul.
	gd.active_game["log"] = []
	_reset_counts()
	vm.refresh()
	_assert("log_reset_signal", _counts["log_reset"] == 1
		and (_payload.get("log_reset", null) as Array).is_empty())

	# =====================================================================
	# E. Partie terminée : l'écran doit basculer en lecture seule
	# =====================================================================
	gd.active_game["status"] = "completed"
	_reset_counts()
	vm.refresh()
	var end_turn: Dictionary = _payload.get("turn", {})
	_assert("completed_turn_payload", str(end_turn.get("headline", "")) == "Aventure terminée"
		and str(end_turn.get("tone", "")) == "muted")
	_assert("completed_role_readonly",
		bool(vm.role.completed) and not bool(vm.role.can_submit_action))

	# =====================================================================
	# Nettoyage
	# =====================================================================
	gd.active_game_updated.disconnect(_on_game_updated)
	vm.unbind()
	gd.delete_game(GAME_ID)
	md.delete_map(map_id)

	if _failed:
		quit(1)
		return
	print("session_view_model_test:PASS")
	quit(0)

func _on_game_updated() -> void:
	_game_updates += 1

# --- Compteurs de signaux ---------------------------------------------------

func _connect_vm_signals(vm) -> void:
	vm.role_changed.connect(_on_role)
	vm.header_changed.connect(_on_header)
	vm.party_changed.connect(_on_party)
	vm.log_reset.connect(_on_log_reset)
	vm.log_appended.connect(_on_log_appended)
	vm.turn_changed.connect(_on_turn)
	vm.navigation_changed.connect(_on_nav)
	vm.map_changed.connect(_on_map)
	vm.net_changed.connect(_on_net)
	vm.notes_changed.connect(_on_notes)
	vm.dice_result.connect(_on_dice)

func _on_role(r) -> void:
	_counts["role"] += 1
	_payload["role"] = r

func _on_header(h: Dictionary) -> void:
	_counts["header"] += 1
	_payload["header"] = h

func _on_party(members: Array, active_id: String) -> void:
	_counts["party"] += 1
	_payload["party"] = {"members": members, "active_id": active_id}

func _on_log_reset(entries: Array) -> void:
	_counts["log_reset"] += 1
	_payload["log_reset"] = entries

func _on_log_appended(entry: Dictionary) -> void:
	_counts["log_appended"] += 1
	_payload["log_appended"] = entry

func _on_turn(turn: Dictionary) -> void:
	_counts["turn"] += 1
	_payload["turn"] = turn

func _on_nav(nav: Dictionary) -> void:
	_counts["nav"] += 1
	_payload["nav"] = nav

func _on_map() -> void:
	_counts["map"] += 1

func _on_net(net: Dictionary) -> void:
	_counts["net"] += 1
	_payload["net"] = net

func _on_notes(text: String) -> void:
	_counts["notes"] += 1
	_payload["notes"] = text

func _on_dice(_text: String, _secret: bool) -> void:
	_counts["dice"] += 1

# --- Helpers ----------------------------------------------------------------

func _zero_counts() -> Dictionary:
	return {
		"role": 0, "header": 0, "party": 0, "log_reset": 0, "log_appended": 0,
		"turn": 0, "nav": 0, "map": 0, "net": 0, "notes": 0, "dice": 0,
	}

func _reset_counts() -> void:
	_counts = _zero_counts()

func _connection_count(sig: Signal, obj: Object) -> int:
	var n := 0
	for c in sig.get_connections():
		if c.get("callable") != null and c["callable"].get_object() == obj:
			n += 1
	return n

func _assert(label: String, cond: bool) -> void:
	if not cond:
		print("session_view_model_test:FAIL at ", label, " counts=", _counts)
		_failed = true
