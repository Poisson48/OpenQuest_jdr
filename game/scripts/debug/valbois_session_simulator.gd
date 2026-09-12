extends Node
class_name ValboisSessionSimulator

## Simule une partie Valbois en cliquant les VRAIS contrôles UI
## (barre d'action, console MJ, toolbar carte, dés, fiches, Entrer/Retour).

signal finished(ok: bool, report: Dictionary)

@export var step_delay := 0.85
@export var quit_on_finish := false
@export var keep_window_open := true

var _gd: Node = null
var _shell: Node = null
var _map: Node = null
var _failed := false
var _errors: Array[String] = []
var _stats: Dictionary = {
	"ui_actions": 0,
	"ui_moves": 0,
	"ui_npc": 0,
	"ui_dice": 0,
	"ui_scenes": 0,
	"ui_enters": 0,
	"ui_sheets": 0,
	"items": 0,
}
var _banner: Label = null

func start(shell: Node = null) -> void:
	_gd = get_tree().root.get_node("GameData")
	_shell = shell
	call_deferred("_run")

func start_when_session_ready() -> void:
	_gd = get_tree().root.get_node("GameData")
	_show_banner("SIMULATION VALBOIS — pilotage UI réel")
	await get_tree().create_timer(1.6).timeout
	_shell = get_tree().current_scene
	await _run()

func _run() -> void:
	await _settle(24)
	if _shell == null:
		_shell = get_tree().current_scene
	_assert("session_shell", _shell != null and _shell.has_method("ui_send_action"))
	if _failed:
		_finish(false)
		return
	_map = _shell.get_panel("map")
	_assert("map_workspace", _map != null and _map.has_method("ui_move_token"))

	_assert("scenario_valbois", str(_gd.active_game.get("scenarioId", "")) == "demo-valbois")
	_assert("party_3", _gd.get_playable_members().size() == 3)
	_assert("npc_roster_15", _gd.list_session_npcs().size() >= 15)
	_assert("proxy_actions", bool(_gd.active_game.get("allowGmProxyActions", false)))

	var report: Dictionary = _shell.describe()
	_assert("role_gm", str(report.get("role", "")) == "gm")
	_assert("action_bar_visible", bool(_shell.get_panel("action").get_node("%InputRow").visible))

	# Outil Sél visible
	_map.ui_select_select_tool()
	await _wait()

	await _ui_narrate("Le crépuscule tombe sur Valbois. Trois silhouettes arrivent par le chemin nord.")
	await _ui_player("Aria", "Je scrute les toits et les gardes à l'entrée.")
	await _ui_move("char-aria", 0.02, -0.01)
	await _ui_npc("Lyse", "Halte. État civil, et vite.")
	await _ui_dice()
	await _ui_next()

	await _ui_player("Thorin", "Je m'avance, bouclier bas, et rassure la milicienne.")
	await _ui_move("char-thorin", 0.03, 0.0)
	await _ui_npc("Lyse", "Passez. Mais le voleur… je le surveille.")
	await _ui_next()

	await _ui_player("Kael", "Je reste dans l'ombre de Thorin et compte les sorties.")
	await _ui_move("char-kael", 0.01, 0.02)
	await _ui_sheet("char-kael")
	await _ui_next()

	await _ui_player("Aria", "Je vais parler au meunier près du moulin.")
	await _ui_move("char-aria", -0.08, -0.12)
	await _ui_npc("Odo", "Une charrette est passée avant l'aube. Pas de foin — trop légère.")
	_give("char-aria", "item-rumeur-charrette", "Indice : charrette légère")
	await _ui_sheet("char-aria")
	await _ui_next()

	await _ui_player("Thorin", "Direction la forge. On aura besoin d'outils.")
	await _ui_move("char-thorin", -0.08, 0.08)
	await _ui_goto("forge-brume")
	await _ui_npc("Gareth", "Prenez ce marteau. Ce qui doit s'ouvrir s'ouvrira.")
	_give("char-thorin", "item-marteau", "Marteau de forge")
	await _ui_next()

	await _ui_player("Kael", "Je glisse vers la taverne pendant qu'ils parlent fer.")
	await _ui_move("char-kael", 0.08, 0.12)
	await _ui_transition("taverne-cerf")
	await _ui_npc("Renard", "L'homme hoodé a laissé une lettre sous la table de gauche.")
	_give("char-kael", "item-lettre", "Lettre de dette")
	await _ui_npc("L'Homme hoodé", "La dette n'était pas de l'or… c'était un nom.")
	await _ui_next()

	await _ui_player("Aria", "On se retrouve à la Place du Marché.")
	await _ui_goto("place-du-marche")
	await _ui_enter_place()
	await _ui_move("char-aria", -0.04, -0.06)
	await _ui_move("char-thorin", 0.02, -0.04)
	await _ui_move("char-kael", 0.0, -0.08)
	await _ui_npc("Marta l'étalière", "Sous le banc… le chiffon aux armes du maire.")
	_give("char-kael", "item-chiffon", "Chiffon brodé du maire")
	await _ui_npc("Nina", "Du pain chaud pour les voyageurs.")
	_give("char-aria", "item-pain", "Pain frais")
	await _ui_next()

	await _ui_player("Thorin", "Je demande à Clara des crochets « de jardin ».")
	await _ui_move("char-thorin", -0.06, 0.02)
	await _ui_npc("Clara", "Pour le jardin, bien sûr.")
	_assert("transfer_pain", bool(_gd.call("transfer_item", "char-aria", "char-kael", "item-pain")))
	_stats["items"] += 1
	_give("char-kael", "item-crochets-extra", "Crochets fins")
	await _shell.model.refresh(true)
	await _wait()
	await _ui_next()

	await _ui_player("Kael", "Je croise Sura pour un baume… et une confidence.")
	await _ui_move("char-kael", 0.08, 0.04)
	await _ui_npc("Sura", "Le bijou a bougé. Dame Élise ne dort plus.")
	_give("char-kael", "item-baume", "Baume d'herboriste")
	await _ui_npc("Capitaine Ord", "Kael. Un pas de travers et c'est les fers.")
	await _ui_dice()
	await _ui_next()

	await _ui_player("Aria", "On monte au manoir. Thorin garde la grille.")
	await _ui_goto("manoir-maire")
	await _ui_back_to_village()
	await _ui_move("char-aria", 0.35, 0.02)
	await _ui_move("char-thorin", 0.32, 0.04)
	await _ui_move("char-kael", 0.34, 0.0)
	await _ui_npc("Dame Élise", "Le maire ne reçoit pas. Surtout pas un voleur.")
	await _ui_npc("Maire Corbin", "Le bijou est… égaré. Trouvez-le sans faire de bruit.")
	await _ui_next()

	await _ui_player("Kael", "J'utilise les crochets sur la porte latérale.")
	_assert("has_crochets", bool(_gd.call("member_has_item", "char-kael", "item-crochets")) \
		or bool(_gd.call("member_has_item", "char-kael", "item-crochets-extra")))
	await _ui_narrate("La serrure cède. Un écrin vide — et de la boue fraîche vers les ruelles.")
	_give("char-kael", "item-ecrin", "Écrin vide du bijou")
	await _ui_sheet("char-kael")
	await _ui_next()

	await _ui_player("Thorin", "Je suis les traces. Marteau prêt.")
	await _ui_goto("piste-bijou")
	await _ui_npc("Tom le gamin", "La silhouette était mince. Elle a fui vers la halle !")
	await _ui_next()

	await _ui_player("Aria", "Je coupe par les ruelles pour intercepter.")
	await _ui_goto("ruelles-nuit")
	await _ui_move("char-aria", -0.05, 0.15)
	await _ui_npc("Capitaine Ord", "Barrage au nord ! Personne ne sort.")
	await _ui_npc("Lyse", "Sud libre… pour l'instant.")
	await _ui_next()

	await _ui_player("Kael", "Je récupère le bijou près de la halle, sans bruit.")
	await _ui_goto("confrontation-dette")
	await _ui_enter_place()
	await _ui_move("char-kael", 0.12, -0.05)
	_give("char-kael", "item-bijou", "Bijou du maire")
	await _ui_npc("L'Homme hoodé", "Rendez le nom… ou gardez le joyau. Choisissez.")
	_assert("transfer_lettre", bool(_gd.call("transfer_item", "char-kael", "char-aria", "item-lettre")))
	await _ui_next()

	await _ui_player("Aria", "On rend le bijou. La dette meurt ici.")
	_assert("transfer_bijou", bool(_gd.call("transfer_item", "char-kael", "char-aria", "item-bijou")))
	await _ui_npc("Maire Corbin", "Valbois n'oubliera pas. Partez avant la nuit.")
	_assert("take_bijou", bool(_gd.call("take_item_from_member", "char-aria", "item-bijou", 1)))
	_give("char-aria", "item-grace", "Grâce du maire")
	await _ui_sheet("char-aria")
	await _ui_next()

	await _ui_player("Thorin", "On referme la forge et on plie bagage.")
	_assert("return_hammer", bool(_gd.call("take_item_from_member", "char-thorin", "item-marteau", 1)))
	await _ui_npc("Gareth", "Remettez le marteau. Et ne revenez pas trop tôt.")
	await _ui_next()

	await _ui_player("Kael", "Je jette un dernier regard à la place… puis je suis les miens.")
	await _ui_goto("denouement")
	await _ui_complete()

	_assert("has_chiffon", bool(_gd.call("member_has_item", "char-kael", "item-chiffon")))
	_assert("has_grace", bool(_gd.call("member_has_item", "char-aria", "item-grace")))
	_assert("status_completed", str(_gd.active_game.get("status", "")) == "completed")
	_assert("ui_moves_ok", int(_stats["ui_moves"]) >= 8)
	_assert("ui_npc_ok", int(_stats["ui_npc"]) >= 10)
	_assert("ui_actions_ok", int(_stats["ui_actions"]) >= 10)

	_show_banner("SIMU TERMINÉE — ok=%s" % (not _failed))
	_finish(not _failed)

# ---------------------------------------------------------------------------
# Actions UI
# ---------------------------------------------------------------------------

func _align_turn(who: String) -> void:
	var playable: Array = _gd.get_playable_members()
	var target := -1
	for i in range(playable.size()):
		if str(playable[i].get("name", "")) == who:
			target = i
			break
	if target < 0:
		return
	var guard := 0
	while int(_gd.active_game.get("turnIndex", 0)) % maxi(playable.size(), 1) != target and guard < 6:
		_shell.ui_next_turn()
		guard += 1
		await _settle(4)
		await _shell.model.refresh(true)

func _ui_player(who: String, text: String) -> void:
	await _align_turn(who)
	_shell.model.refresh(true)
	await _settle(3)
	_shell.ui_fill_action(text)
	await _wait()
	_shell.ui_send_action()
	_stats["ui_actions"] += 1
	await _settle(6)
	_shell.model.refresh(true)
	await _wait()
	_assert("waiting_after_%s" % who, bool(_gd.active_game.get("waitingForGm", false)))

func _ui_next() -> void:
	_shell.ui_next_turn()
	await _settle(4)
	_shell.model.refresh(true)
	await _wait()

func _ui_narrate(text: String) -> void:
	_shell.ui_narrate(text)
	await _settle(4)
	_shell.model.refresh(true)
	await _wait()

func _ui_npc(name: String, text: String) -> void:
	_shell.ui_npc_line(name, text)
	_stats["ui_npc"] += 1
	await _settle(5)
	_shell.model.refresh(true)
	await _wait()

func _ui_goto(scene_id: String) -> void:
	_shell.ui_goto_scene(scene_id)
	_stats["ui_scenes"] += 1
	await _settle(6)
	_shell.model.refresh(true)
	await _wait()
	_assert("scene_%s" % scene_id, str(_gd.active_game.get("currentSceneId", "")) == scene_id)

func _ui_transition(scene_id: String) -> void:
	_shell.ui_press_transition(scene_id)
	_stats["ui_scenes"] += 1
	await _settle(6)
	_shell.model.refresh(true)
	await _wait()
	_assert("scene_%s" % scene_id, str(_gd.active_game.get("currentSceneId", "")) == scene_id)

func _ui_dice() -> void:
	_shell.ui_roll_d20()
	_stats["ui_dice"] += 1
	await _settle(4)
	await _wait()

func _ui_sheet(member_id: String) -> void:
	_shell.ui_open_member_sheet(member_id)
	_stats["ui_sheets"] += 1
	await _wait()
	await get_tree().create_timer(0.7).timeout
	_shell.ui_close_sheet()
	await _settle(3)

func _ui_move(member_id: String, dx: float, dy: float) -> void:
	_map.ui_select_select_tool()
	await _settle(2)
	var map_id: String = str(_map.current_display_map_id())
	var tok_id: String = str(_gd.call("find_member_token_id", map_id, member_id))
	if tok_id.is_empty():
		var md: Node = get_tree().root.get_node("MapData")
		var map_def: Dictionary = md.call("get_by_id", map_id)
		var x := float(map_def.get("width", 20)) * 0.5
		var y := float(map_def.get("height", 14)) * 0.5
		_gd.call("place_complex_member_token", map_id, x, y, member_id)
		_map.refresh()
		await _settle(4)
		tok_id = str(_gd.call("find_member_token_id", map_id, member_id))
	_assert("token_%s" % member_id, not tok_id.is_empty())
	if tok_id.is_empty():
		return
	var tokens: Array = _gd.call("get_map_play_tokens", map_id)
	var gx := 0.0
	var gy := 0.0
	for t in tokens:
		if typeof(t) != TYPE_DICTIONARY:
			continue
		if str(t.get("id", "")) == tok_id:
			gx = float(t.get("x", 0))
			gy = float(t.get("y", 0))
			break
	var md2: Node = get_tree().root.get_node("MapData")
	var map_def2: Dictionary = md2.call("get_by_id", map_id)
	var w := float(map_def2.get("width", 20))
	var h := float(map_def2.get("height", 14))
	var nx := clampf(gx + dx * w, 0.5, w - 0.5)
	var ny := clampf(gy + dy * h, 0.5, h - 0.5)
	# Même chemin que le drag souris : token_moved → submit_map_op
	_map.ui_move_token(tok_id, nx, ny)
	_stats["ui_moves"] += 1
	await _settle(4)
	await _wait()

func _ui_enter_place() -> void:
	_assert("prepare_enter", bool(_map.ui_prepare_enter_area("area-place-marche")))
	await _settle(3)
	_assert("press_enter", bool(_map.ui_press_toolbar_enter_button()))
	_stats["ui_enters"] += 1
	await _settle(8)
	_map.refresh()
	await _wait()

func _ui_back_to_village() -> void:
	_map.ui_press_back()
	await _settle(6)
	_map.refresh()
	await _wait()

func _ui_complete() -> void:
	_shell.ui_complete()
	await _settle(4)
	_shell.ui_confirm_if_open()
	await _settle(6)
	_shell.model.refresh(true)
	await _wait()
	if str(_gd.active_game.get("status", "")) != "completed":
		_gd.call("complete_scenario", "Clôture simu UI")
		_shell.model.refresh(true)
	_assert("completed", str(_gd.active_game.get("status", "")) == "completed")

func _give(member_id: String, item_id: String, item_name: String) -> void:
	_assert("give_%s" % item_id, bool(_gd.call("give_item_to_member", member_id, item_id, item_name, 1)))
	_stats["items"] += 1
	_shell.model.refresh(true)

# ---------------------------------------------------------------------------
# Utilitaires
# ---------------------------------------------------------------------------

func _show_banner(text: String) -> void:
	if _banner == null:
		_banner = Label.new()
		_banner.name = "ValboisSimBanner"
		_banner.add_theme_font_size_override("font_size", 22)
		_banner.add_theme_color_override("font_color", Color(1, 0.92, 0.55))
		_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
		_banner.offset_top = 8
		_banner.offset_bottom = 40
		_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		get_tree().root.add_child(_banner)
	_banner.text = text
	_banner.visible = true

func _wait() -> void:
	await get_tree().create_timer(step_delay).timeout

func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame

func _assert(label: String, ok: bool) -> void:
	print("[VALBOIS SIM] %s %s" % ["OK" if ok else "FAIL", label])
	if not ok:
		_failed = true
		_errors.append(label)

func _finish(ok: bool) -> void:
	var report := {
		"ok": ok,
		"errors": _errors.duplicate(),
		"stats": _stats.duplicate(true),
		"scene": str(_gd.active_game.get("currentSceneId", "")),
		"status": str(_gd.active_game.get("status", "")),
		"log_size": (_gd.active_game.get("log", []) as Array).size(),
		"npcs": _gd.list_session_npcs().size(),
	}
	print("[VALBOIS SIM] DONE ok=%s stats=%s errors=%s" % [ok, _stats, _errors])
	finished.emit(ok, report)
	if quit_on_finish and not keep_window_open:
		get_tree().quit(0 if ok else 1)
