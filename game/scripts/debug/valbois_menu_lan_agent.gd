extends Node

## Agent UI : menu → salon → setup → session via vrais boutons.
## Doit vivre sur root (jamais current_scene).

const Shared = preload("res://scripts/debug/lan_table_shared.gd")
const Director = preload("res://scripts/debug/valbois_lan_director.gd")

@export var role_mode: String = "gm"
@export var player_slot: int = 1
@export var display_name: String = "MJ"
@export var auto_boot: bool = true

var _menu: Node
var _banner: Label
var _started := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("role="):
			role_mode = arg.get_slice("=", 1)
		elif arg.begins_with("slot="):
			player_slot = int(arg.get_slice("=", 1))
		elif arg.begins_with("name="):
			display_name = arg.get_slice("=", 1)
	if display_name.is_empty():
		display_name = _default_name()
	if auto_boot:
		call_deferred("begin_from_root")

func _default_name() -> String:
	if role_mode == "gm":
		return "MJ"
	match clampi(player_slot, 1, 3):
		1: return "Aria"
		2: return "Thorin"
		_: return "Kael"

func _st() -> SceneTree:
	var t := get_tree()
	if t != null:
		return t
	return Engine.get_main_loop() as SceneTree

## Point d'entrée sûr : déjà enfant de root.
func begin_from_root() -> void:
	if _started:
		return
	if not is_inside_tree():
		# Réessai au prochain frame si appelé trop tôt.
		call_deferred("begin_from_root")
		return
	_started = true
	var st := _st()
	if st == null:
		push_error("[MENU] no SceneTree")
		_started = false
		return
	if st.current_scene == self:
		var keeper: Node = (load(get_script().resource_path) as GDScript).new()
		keeper.name = "ValboisMenuLanAgent"
		keeper.set("role_mode", role_mode)
		keeper.set("player_slot", player_slot)
		keeper.set("display_name", display_name)
		keeper.set("auto_boot", false)
		st.root.add_child(keeper)
		keeper.call_deferred("begin_from_root")
		return
	if get_parent() != st.root:
		if get_parent() != null:
			get_parent().remove_child(self)
		st.root.add_child(self)
		await st.process_frame
	_banner = _make_banner("%s — boot…" % display_name)
	MultiplayerManager.force_loopback_p2p = true
	if not MultiplayerManager.game_started.is_connected(_on_game_started):
		MultiplayerManager.game_started.connect(_on_game_started)
	_log("goto main_menu")
	st.change_scene_to_file("res://scenes/main_menu.tscn")
	await st.process_frame
	await st.process_frame
	await _wait_until(func():
		var s := _st().current_scene
		return s != null and is_instance_valid(s) and s.has_node("%BtnConnectPooling")
	, 25.0)
	_menu = _st().current_scene
	if _menu == null or not _menu.has_node("%BtnConnectPooling"):
		_banner.text = "%s — menu KO" % display_name
		_log("menu missing controls scene=%s" % (_menu.name if _menu else "null"))
		return
	_log("menu ok")
	_banner.text = "%s — menu OK" % display_name
	await _run_lobby()

func _run_lobby() -> void:
	_banner.text = "%s — connexion…" % display_name
	_menu.get_node("%PlayerNameInput").text = display_name
	_menu.get_node("%PoolingUrlInput").text = "ws://127.0.0.1:8080"
	var role_opt: OptionButton = _menu.get_node("%OptPoolingRole")
	for i in range(role_opt.item_count):
		if str(role_opt.get_item_metadata(i)) == role_mode:
			role_opt.select(i)
			break
	if role_opt.item_count > 0:
		role_opt.item_selected.emit(role_opt.selected)
	MultiplayerManager.set_player_role(role_mode)
	MultiplayerManager.player_name = display_name
	Shared.write_status({"phase": "connecting", "role": role_mode, "name": display_name})
	await _wait(0.6)
	_menu.get_node("%BtnConnectPooling").pressed.emit()
	_log("connect clicked")
	await _wait_until(func(): return MultiplayerManager.is_pooling_connected(), 25.0)
	if not MultiplayerManager.is_pooling_connected():
		_banner.text = "%s — pooling KO" % display_name
		Shared.write_status({"phase": "pooling_fail", "role": role_mode})
		_log("pooling fail")
		return
	_log("pooling ok mj=%s" % MultiplayerManager.is_mj())
	if role_mode == "gm":
		await _gm_flow()
	else:
		await _player_flow()

func _gm_flow() -> void:
	Shared.ensure_dir()
	_banner.text = "MJ — créer salon…"
	await _wait(0.5)
	_menu.get_node("%BtnCreateRoom").pressed.emit()
	_log("create room clicked")
	await _wait_until(func(): return MultiplayerManager.is_in_room() and MultiplayerManager.is_gm, 20.0)
	var code := MultiplayerManager.room_code
	_log("code=%s" % code)
	if code.is_empty():
		_banner.text = "MJ — code vide"
		return
	Shared.write_room_code(code)
	Shared.write_status({"phase": "waiting_players", "code": code, "players": 0, "ready": 0})
	_banner.text = "MJ — code %s — attente 3 joueurs…" % code
	await _wait_until(func():
		var n := 0
		var ready := 0
		for p in MultiplayerManager.get_room_players():
			if bool(p.get("isGm", false)):
				continue
			n += 1
			var ch = p.get("character", {})
			if typeof(ch) == TYPE_DICTIONARY and not (ch as Dictionary).is_empty():
				ready += 1
		Shared.write_status({
			"phase": "waiting_players",
			"code": MultiplayerManager.room_code,
			"players": n,
			"ready": ready
		})
		return n >= 3 and ready >= 3 and MultiplayerManager.is_p2p_host()
	, 120.0)
	_banner.text = "MJ — lancer setup…"
	_log("players ready, launch")
	await _wait_until(func():
		return is_instance_valid(_menu) and _menu.has_node("%BtnLaunchPoolingGame") and _menu.get_node("%BtnLaunchPoolingGame").visible
	, 30.0)
	_menu.get_node("%BtnLaunchPoolingGame").pressed.emit()
	await _wait(2.0)
	await _wait_until(func():
		var s := _st().current_scene
		return s != null and s.has_node("%BtnStartGame")
	, 25.0)
	var setup := _st().current_scene
	_banner.text = "MJ — setup Valbois…"
	await _wait(1.5)
	if setup != null and setup.has_node("%OptScenario"):
		_prefer_valbois(setup.get_node("%OptScenario"))
	if setup != null and setup.has_node("%BtnStartGame"):
		setup.get_node("%BtnStartGame").pressed.emit()
		Shared.write_status({"phase": "starting", "code": MultiplayerManager.room_code})
		_banner.text = "MJ — démarrage…"
		_log("start game clicked")

func _prefer_valbois(opt: OptionButton) -> void:
	for i in range(opt.item_count):
		var meta = opt.get_item_metadata(i)
		var txt := str(opt.get_item_text(i)).to_lower()
		if str(meta).contains("valbois") or txt.contains("valbois"):
			opt.select(i)
			return

func _player_flow() -> void:
	_banner.text = "%s — attente code…" % display_name
	var code := ""
	var t := 0.0
	while t < 90.0:
		code = Shared.read_room_code()
		if not code.is_empty():
			break
		await _wait(0.4)
		t += 0.4
	if code.is_empty():
		_banner.text = "%s — pas de code" % display_name
		_log("no room code")
		return
	_log("got code %s" % code)
	_menu = _st().current_scene
	_menu.get_node("%RoomCodeInput").text = code
	await _wait(0.4)
	_menu.get_node("%BtnJoinRoom").pressed.emit()
	_log("join clicked")
	await _wait_until(func(): return MultiplayerManager.is_in_room(), 25.0)
	_banner.text = "%s — choix perso…" % display_name
	await _wait(1.0)
	_select_character()
	await _wait(0.5)
	_menu.get_node("%BtnPoolingRegisterChar").pressed.emit()
	_banner.text = "%s — prêt, attend MJ…" % display_name
	_log("registered, waiting start")

func _select_character() -> void:
	# Garantit Aria / Thorin / Kael même si le profil user est pollué.
	GameData._ensure_kael_character()
	GameData._ensure_seed_character("char-aria")
	GameData._ensure_seed_character("char-thorin")
	if _menu.has_method("_populate_pooling_characters"):
		_menu._populate_pooling_characters()
	var opt: OptionButton = _menu.get_node("%OptPoolingChar")
	var want_id := ""
	match clampi(player_slot, 1, 3):
		1: want_id = "char-aria"
		2: want_id = "char-thorin"
		_: want_id = "char-kael"
	for i in range(opt.item_count):
		if str(opt.get_item_metadata(i)) == want_id:
			opt.select(i)
			_log("selected %s (%s)" % [want_id, opt.get_item_text(i)])
			return
	var want_name := display_name.to_lower()
	for i in range(opt.item_count):
		if str(opt.get_item_text(i)).to_lower().contains(want_name):
			opt.select(i)
			_log("selected by name %s" % opt.get_item_text(i))
			return
	_log("WARN char not found want=%s count=%d" % [want_id, opt.item_count])

func _on_game_started(_id: String, state: Dictionary) -> void:
	GameData.apply_server_state(state)
	_banner.text = "%s — session !" % display_name
	Shared.write_status({"phase": "playing", "code": MultiplayerManager.room_code})
	_log("game started")
	if _st().root.has_node("ValboisLanDirector"):
		return
	var dir: Node = Director.new()
	dir.name = "ValboisLanDirector"
	dir.set("role_mode", role_mode)
	dir.set("player_slot", player_slot)
	dir.set("step_delay", 2.2)
	dir.set("long_session", true)
	_st().root.add_child(dir)
	dir.call_deferred("start_when_ready")

func _wait(sec: float) -> void:
	await _st().create_timer(sec).timeout

func _wait_until(cond: Callable, timeout: float) -> void:
	var t := 0.0
	while t < timeout:
		var ok := false
		if cond.is_valid():
			ok = bool(cond.call())
		if ok:
			return
		await _st().create_timer(0.25).timeout
		t += 0.25

func _log(msg: String) -> void:
	print("[MENU %s] %s" % [display_name, msg])
	Shared.ensure_dir()
	var path := Shared.root_dir().path_join("agent_%s.log" % display_name.replace(" ", "_"))
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line("%s | %s" % [Time.get_time_string_from_system(), msg])
		f.close()

func _make_banner(text: String) -> Label:
	var b := Label.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	b.set_anchors_preset(Control.PRESET_TOP_WIDE)
	b.offset_top = 4
	b.offset_bottom = 32
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_st().root.add_child(b)
	return b
