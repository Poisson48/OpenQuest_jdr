extends Node

## Directeur de table LAN : chaque fenêtre joue son rôle via l'UI / le réseau.

const Shared = preload("res://scripts/debug/lan_table_shared.gd")

@export var role_mode: String = "gm" ## gm | player
@export var player_slot: int = 1
@export var step_delay := 1.0
@export var long_session := false

var _shell: Node
var _gd: Node
var _mm: Node
var _beat := 0
var _done := false
var _banner: Label
var _round := 0

const PLAYER_LINES := {
	"Aria": [
		"Je scrute les toits et les gardes à l'entrée.",
		"Je vais parler au meunier près du moulin.",
		"J'examine les traces près de la fontaine.",
		"On se retrouve à la Place du Marché.",
		"Je questionne Nina sur les passages de nuit.",
		"On monte au manoir. Thorin garde la grille.",
		"Je coupe par les ruelles pour intercepter.",
		"Je couvre Kael pendant qu'il crochète.",
		"On rend le bijou. La dette meurt ici.",
		"Je vérifie que personne ne nous suit à la sortie.",
	],
	"Thorin": [
		"Je m'avance, bouclier bas, et rassure la milicienne.",
		"Direction la forge. On aura besoin d'outils.",
		"Je surveille la rue pendant qu'Aria parle.",
		"Je demande à Clara des crochets de jardin.",
		"Je barre le passage si la milice revient.",
		"Je suis les traces. Marteau prêt.",
		"Je tiens la porte du manoir ouverte.",
		"On referme la forge et on plie bagage.",
		"Je rends le marteau à Gareth comme promis.",
		"Je ferme la marche, personne derrière nous.",
	],
	"Kael": [
		"Je reste dans l'ombre de Thorin et compte les sorties.",
		"Je glisse vers la taverne pendant qu'ils parlent fer.",
		"Je fouille sous le banc sans me faire voir.",
		"Je croise Sura pour un baume… et une confidence.",
		"J'utilise les crochets sur la porte latérale.",
		"Je récupère le bijou près de la halle, sans bruit.",
		"Je tends la lettre à Aria.",
		"Je jette un dernier regard à la place… puis je suis les miens.",
		"Je disparais dans l'ombre dès que le maire a son bien.",
		"Trop de regards. On part.",
	],
}

const GM_BEATS_CORE := [
	{"narrate": "Le crépuscule tombe sur Valbois. Trois silhouettes arrivent."},
	{"npc": ["Lyse", "Halte. État civil, et vite."]},
	{"dice": true},
	{"next": true},
	{"npc": ["Odo", "Une charrette est passée avant l'aube. Trop légère."]},
	{"give": ["char-aria", "item-rumeur", "Indice : charrette légère"]},
	{"next": true},
	{"scene": "forge-brume"},
	{"npc": ["Gareth", "Prenez ce marteau. Ce qui doit s'ouvrir s'ouvrira."]},
	{"give": ["char-thorin", "item-marteau", "Marteau de forge"]},
	{"next": true},
	{"scene": "taverne-cerf"},
	{"npc": ["Renard", "L'homme hoodé a laissé une lettre sous la table."]},
	{"give": ["char-kael", "item-lettre", "Lettre de dette"]},
	{"npc": ["L'Homme hoodé", "La dette n'était pas de l'or… c'était un nom."]},
	{"next": true},
	{"scene": "place-du-marche"},
	{"enter": true},
	{"npc": ["Marta l'étalière", "Sous le banc… le chiffon aux armes du maire."]},
	{"give": ["char-kael", "item-chiffon", "Chiffon brodé du maire"]},
	{"npc": ["Nina", "Du pain chaud — et des yeux partout."]},
	{"give": ["char-aria", "item-pain", "Pain frais"]},
	{"next": true},
	{"narrate": "Le crépuscule s'éteint plus tôt que prévu. Les lanternes du marché s'éteignent une à une."},
	{"night": true},
	{"give": ["char-kael", "item-lanterne", "Lanterne de voyage"]},
	{"narrate": "Kael allume sa lanterne — seul cercle de lumière sur la place. Sans elle, plus rien."},
	{"nudge_lantern": true},
	{"npc": ["Clara", "Des crochets « de jardin », vraiment ?"]},
	{"give": ["char-kael", "item-crochets-extra", "Crochets fins"]},
	{"nudge_lantern": true},
	{"next": true},
	{"npc": ["Sura", "Le bijou a bougé. Dame Élise ne dort plus."]},
	{"give": ["char-kael", "item-baume", "Baume d'herboriste"]},
	{"npc": ["Capitaine Ord", "Un pas de travers et c'est les fers."]},
	{"dice": true},
	{"nudge_lantern": true},
	{"next": true},
	{"scene": "manoir-maire"},
	{"npc": ["Dame Élise", "Le maire ne reçoit pas. Surtout pas un voleur."]},
	{"npc": ["Maire Corbin", "Le bijou est égaré. Trouvez-le sans faire de bruit."]},
	{"next": true},
	{"narrate": "La serrure latérale cède sous les crochets de Kael. Un écrin vide."},
	{"give": ["char-kael", "item-ecrin", "Écrin vide"]},
	{"next": true},
	{"scene": "piste-bijou"},
	{"npc": ["Tom le gamin", "Elle a fui vers la halle !"]},
	{"next": true},
	{"scene": "ruelles-nuit"},
	{"npc": ["Capitaine Ord", "Barrage au nord ! Éteignez tout !"]},
	{"npc": ["Lyse", "Sud libre… pour l'instant."]},
	{"nudge_lantern": true},
	{"next": true},
	{"nudge_lantern": true},
	{"npc": ["L'Homme hoodé", "Suivez la flamme… ou restez perdus."]},
	{"scene": "confrontation-dette"},
	{"npc": ["L'Homme hoodé", "Rendez le nom… ou gardez le joyau."]},
	{"give": ["char-kael", "item-bijou", "Bijou du maire"]},
	{"next": true},
	{"narrate": "Aria rend le bijou. La dette meurt ici. Valbois retient son souffle."},
	{"give": ["char-aria", "item-grace", "Grâce du maire"]},
	{"next": true},
	{"scene": "denouement"},
	{"npc": ["Gareth", "Remettez le marteau. Et ne revenez pas trop tôt."]},
	{"night": false},
	{"narrate": "L'aube grise Valbois. Les trois compagnons quittent le village autrement qu'ils y sont entrés."},
]

const GM_BEATS_EXTRA := [
	{"narrate": "Un second souffle : la place murmure encore."},
	{"npc": ["Père Alain", "Éliandre protège ceux qui rendent ce qu'ils ont pris."]},
	{"next": true},
	{"npc": ["Hugo", "Aux écuries, une monture étrangère a disparu."]},
	{"give": ["char-thorin", "item-fer", "Fer à cheval perdu"]},
	{"next": true},
	{"enter": true},
	{"npc": ["Marta l'étalière", "On parle déjà de vous dans tout le village."]},
	{"dice": true},
	{"next": true},
]

const GM_BEATS_FINALE := [
	{"narrate": "Le crépuscule referme Valbois. L'aventure est close."},
	{"complete": true},
]

func start_when_ready() -> void:
	_gd = get_tree().root.get_node("GameData")
	_mm = get_tree().root.get_node("MultiplayerManager")
	_banner = _make_banner("Directeur %s…" % role_mode)
	# Laisse la coquille session s'initialiser.
	for _i in range(90):
		await get_tree().process_frame
		_shell = get_tree().current_scene
		if _shell != null and _shell.has_method("describe"):
			break
	await get_tree().create_timer(1.2).timeout
	_shell = get_tree().current_scene
	if role_mode == "gm":
		await _run_gm()
	else:
		await _run_player()

func _run_gm() -> void:
	_banner.text = "MJ — direction de table (30 mn condensées)"
	var party_names: Array = []
	for m in _gd.active_game.get("party", []):
		party_names.append("%s(%s)" % [m.get("name", "?"), m.get("id", "")])
	_log_dir("party=%s" % ", ".join(party_names))
	Shared.write_status({
		"phase": "playing",
		"code": _mm.room_code,
		"party": party_names,
	})
	var beats: Array = []
	beats.append_array(GM_BEATS_CORE)
	if long_session:
		beats.append_array(GM_BEATS_EXTRA)
	beats.append_array(GM_BEATS_FINALE)
	var i := 0
	while i < beats.size() and not _done:
		var beat: Dictionary = beats[i]
		_log_dir("beat %d/%d keys=%s" % [i + 1, beats.size(), str(beat.keys())])
		if bool(beat.get("next", false)) or beat.has("npc") or beat.has("narrate") \
				or beat.has("scene") or beat.has("complete") or beat.has("enter") \
				or beat.has("night") or bool(beat.get("nudge_lantern", false)):
			await _wait_until(func():
				return bool(_gd.active_game.get("waitingForGm", false)) \
					or str(_gd.active_game.get("status", "")) == "completed" \
					or i == 0
			, 35.0)
		if str(_gd.active_game.get("status", "")) == "completed":
			break
		await _apply_gm_beat(beat)
		i += 1
		await get_tree().create_timer(step_delay).timeout
	_banner.text = "MJ — fin de table"
	_done = true

func _log_dir(msg: String) -> void:
	print("[DIR %s] %s" % [role_mode, msg])
	Shared.ensure_dir()
	var path := Shared.root_dir().path_join("director_%s.log" % role_mode)
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line("%s | %s" % [Time.get_time_string_from_system(), msg])
		f.close()

func _apply_gm_beat(beat: Dictionary) -> void:
	if _shell == null or not is_instance_valid(_shell):
		_shell = get_tree().current_scene
	if beat.has("narrate") and _shell.has_method("ui_narrate"):
		_shell.ui_narrate(str(beat["narrate"]))
		_banner.text = "MJ Diffuser…"
	if beat.has("npc") and _shell.has_method("ui_npc_line"):
		var pair: Array = beat["npc"]
		_shell.ui_npc_line(str(pair[0]), str(pair[1]))
		_banner.text = "MJ Faire parler %s" % pair[0]
	if beat.has("scene") and _shell.has_method("ui_goto_scene"):
		_shell.ui_goto_scene(str(beat["scene"]))
		_banner.text = "MJ scène %s" % beat["scene"]
		await get_tree().create_timer(0.4).timeout
		_focus_map()
	if bool(beat.get("enter", false)) and _shell.get_panel("map"):
		var map = _shell.get_panel("map")
		if map.has_method("ui_prepare_enter_area"):
			map.ui_prepare_enter_area("area-place-marche")
			await get_tree().create_timer(0.3).timeout
			map.ui_press_toolbar_enter_button()
			_mm.broadcast_state()
			await get_tree().create_timer(0.5).timeout
			_focus_map()
	if beat.has("give"):
		var g: Array = beat["give"]
		_gd.call("give_item_to_member", str(g[0]), str(g[1]), str(g[2]), 1)
		_mm.broadcast_state()
	if beat.has("night"):
		var on_night := bool(beat["night"])
		if _shell.has_method("ui_set_night"):
			_shell.ui_set_night(on_night, 0.12 if on_night else 0.22)
		else:
			_gd.call("set_session_night", on_night, 0.12 if on_night else 0.22)
		_banner.text = "MJ nuit %s" % ("ON" if on_night else "OFF")
		Shared.write_status({
			"phase": "playing",
			"code": _mm.room_code,
			"night": on_night,
			"lantern": bool(_gd.call("member_has_lantern", "char-kael")),
		})
		_mm.broadcast_state()
		await get_tree().create_timer(0.8).timeout
		_focus_map()
	if bool(beat.get("nudge_lantern", false)):
		await _nudge_lantern_bearer()
		_banner.text = "MJ lanterne bouge…"
		Shared.write_status({
			"phase": "playing",
			"code": _mm.room_code,
			"night": true,
			"lantern": true,
			"lantern_nudge": true,
		})
	if bool(beat.get("dice", false)) and _shell.has_method("ui_roll_d20"):
		_shell.ui_roll_d20()
	if bool(beat.get("next", false)) and _shell.has_method("ui_next_turn"):
		_shell.ui_next_turn()
		_banner.text = "MJ Tour suivant"
		_mm.broadcast_state()
	if bool(beat.get("complete", false)):
		_log_dir("complete scenario")
		if _shell.has_method("ui_complete"):
			await _shell.ui_complete()
		if str(_gd.active_game.get("status", "")) != "completed":
			_gd.call("complete_scenario", "Fin de table LAN")
			_mm.broadcast_state()
		Shared.write_status({"phase": "completed", "code": _mm.room_code})
		_done = true
	if _shell.get("model") != null:
		_shell.model.refresh(true)
	await get_tree().create_timer(0.2).timeout

func _nudge_lantern_bearer() -> void:
	var map_id := _current_map_id()
	var bearer := "char-kael"
	if not bool(_gd.call("member_has_lantern", bearer)):
		for mid in ["char-aria", "char-thorin", "char-kael"]:
			if bool(_gd.call("member_has_lantern", mid)):
				bearer = mid
				break
	var tok: String = str(_gd.call("find_member_token_id", map_id, bearer))
	if tok.is_empty():
		return
	var tokens: Array = _gd.call("get_map_play_tokens", map_id)
	var gx := 8.0
	var gy := 6.0
	for t in tokens:
		if str(t.get("id", "")) == tok:
			gx = float(t.get("x", gx))
			gy = float(t.get("y", gy))
			break
	# Avance la lanterne sur la carte pour montrer le halo qui suit.
	var map_data: Dictionary = _gd.call("get_session_display_map", map_id).get("displayMap", {})
	var mw := float(map_data.get("width", 20))
	var mh := float(map_data.get("height", 14))
	gx = clampf(gx + randf_range(1.2, 2.4), 1.5, mw - 1.5)
	gy = clampf(gy + randf_range(-1.5, 1.5), 1.5, mh - 1.5)
	_gd.submit_map_op(map_id, {"type": "move_token", "tokenId": tok, "x": gx, "y": gy})
	_mm.broadcast_state()
	await get_tree().create_timer(0.5).timeout
	_focus_map()
	if _shell != null and _shell.get("model") != null:
		_shell.model.refresh(true)

func _current_map_id() -> String:
	var map_id := "demo-valbois-village"
	var nav: Dictionary = _gd.active_game.get("mapNavigation", {})
	if str(nav.get("view", "")) == "local" and not str(nav.get("localMapId", "")).is_empty():
		map_id = str(nav.get("localMapId"))
	var stack: Array = nav.get("areaStack", [])
	if not stack.is_empty():
		map_id = str((stack[stack.size() - 1] as Dictionary).get("mapId", map_id))
	return map_id

func _focus_map() -> void:
	if _shell == null:
		return
	var map = _shell.get_panel("map") if _shell.has_method("get_panel") else null
	if map == null:
		return
	if map.has_method("describe") and map.get("stage") != null:
		var st = map.stage
		if st != null and st.has_method("fit"):
			st.fit()

func _run_player() -> void:
	var my_name := _my_name()
	_banner.text = "%s — en jeu" % my_name
	var line_i := 0
	var lines: Array = PLAYER_LINES.get(my_name, ["J'observe et j'agis."])
	var idle := 0.0
	var max_idle := 900.0 if long_session else 180.0
	while not _done and idle < max_idle:
		if str(_gd.active_game.get("status", "")) == "completed":
			break
		_shell = get_tree().current_scene
		if _shell != null and _shell.get("model") != null:
			_shell.model.refresh(true)
			var role = _shell.model.role
			if role != null and bool(role.can_submit_action):
				var text := str(lines[mini(line_i, lines.size() - 1)])
				line_i += 1
				_banner.text = "%s agit…" % my_name
				await _submit_player_action(text)
				await _maybe_move_own_token()
				idle = 0.0
			else:
				_banner.text = "%s attend son tour…" % my_name
		await get_tree().create_timer(step_delay).timeout
		idle += step_delay
	_banner.text = "%s — fin" % my_name
	_done = true

func _submit_player_action(text: String) -> void:
	# Vue joueur immersive : HUD ; sinon barre d'action.
	var hud = null
	if _shell.has_method("get_player_hud"):
		hud = _shell.get_player_hud()
	if hud != null and hud.visible and hud.has_method("submit_action_text"):
		hud.submit_action_text(text)
	elif _shell.has_method("ui_fill_action"):
		# Fallback si proxy / HUD absent
		_shell.ui_fill_action(text)
		_shell.ui_send_action()
	else:
		_mm.client_submit_action(text)
	await get_tree().create_timer(0.4).timeout

func _maybe_move_own_token() -> void:
	var member: Dictionary = _mm.get_my_party_member(_gd.active_game)
	if member.is_empty():
		return
	var mid: String = str(member.get("id", ""))
	var map_id: String = "demo-valbois-village"
	var nav: Dictionary = _gd.active_game.get("mapNavigation", {})
	if str(nav.get("view", "")) == "local" and not str(nav.get("localMapId", "")).is_empty():
		map_id = str(nav.get("localMapId"))
	var stack: Array = nav.get("areaStack", [])
	if not stack.is_empty():
		map_id = str((stack[stack.size() - 1] as Dictionary).get("mapId", map_id))
	var tok: String = str(_gd.call("find_member_token_id", map_id, mid))
	if tok.is_empty():
		return
	var tokens: Array = _gd.call("get_map_play_tokens", map_id)
	var gx := 0.0
	var gy := 0.0
	for t in tokens:
		if typeof(t) == TYPE_DICTIONARY and str(t.get("id", "")) == tok:
			gx = float(t.get("x", 0))
			gy = float(t.get("y", 0))
			break
	_mm.client_request_map_op(map_id, {
		"type": "move_token",
		"tokenId": tok,
		"x": gx + randf_range(-0.8, 0.8),
		"y": gy + randf_range(-0.8, 0.8),
	})

func _my_name() -> String:
	match clampi(player_slot, 1, 3):
		1: return "Aria"
		2: return "Thorin"
		_: return "Kael"

func _wait_until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while t < timeout:
		if cond.call():
			return
		await get_tree().create_timer(0.25).timeout
		t += 0.25

func _make_banner(text: String) -> Label:
	var b := Label.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	b.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	b.offset_top = -28
	b.offset_bottom = -4
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child(b)
	return b
