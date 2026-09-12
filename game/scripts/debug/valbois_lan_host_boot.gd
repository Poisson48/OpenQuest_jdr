extends Node

## Boot MJ local : crée le salon pooling, attend 3 joueurs, lance Valbois.

const Shared = preload("res://scripts/debug/lan_table_shared.gd")
const Director = preload("res://scripts/debug/valbois_lan_director.gd")

var _started := false
var _banner: Label

func _ready() -> void:
	_banner = _make_banner("MJ — connexion pooling…")
	Shared.clear()
	Shared.write_status({"phase": "host_boot", "role": "gm"})

	MultiplayerManager.force_loopback_p2p = true
	MultiplayerManager.set_player_role("gm")
	MultiplayerManager.player_name = "MJ Valbois"
	MultiplayerManager.p2p_error.connect(_on_err)
	MultiplayerManager.room_updated.connect(_on_room_updated)
	MultiplayerManager.game_started.connect(_on_game_started)
	MultiplayerManager.p2p_host_started.connect(func(addr): _log("ENet hôte %s" % addr))

	MultiplayerManager.connect_pooling("ws://127.0.0.1:8080", "MJ Valbois")
	_wait_connected_then_create()

func _wait_connected_then_create() -> void:
	var t := 0.0
	while not MultiplayerManager.is_pooling_connected() and t < 20.0:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
	if not MultiplayerManager.is_pooling_connected():
		_fail("Pooling injoignable — lance le serveur (npm run dev).")
		return
	_banner.text = "MJ — création du salon…"
	MultiplayerManager.create_room("Valbois LAN")

func _on_room_updated(room: Dictionary) -> void:
	var code := str(room.get("code", MultiplayerManager.room_code))
	if not code.is_empty() and MultiplayerManager.is_gm:
		Shared.write_room_code(code)
	var players: Array = room.get("players", [])
	var humans := 0
	var ready := 0
	for p in players:
		if bool(p.get("isGm", false)):
			continue
		humans += 1
		if typeof(p.get("character", {})) == TYPE_DICTIONARY and not (p.get("character", {}) as Dictionary).is_empty():
			ready += 1
	Shared.write_status({
		"phase": "waiting_players",
		"code": code,
		"players": humans,
		"ready": ready,
	})
	_banner.text = "MJ — code %s — joueurs %d/3 (chars %d/3)" % [code, humans, ready]
	if _started:
		return
	if not MultiplayerManager.is_p2p_host():
		return
	if humans >= 3 and ready >= 3:
		_started = true
		_banner.text = "MJ — lancement Valbois…"
		await get_tree().create_timer(0.8).timeout
		_launch_valbois()

func _launch_valbois() -> void:
	MapData.load_maps()
	GameData.reload_builtin_scenarios()
	# Party vide : merge depuis le salon (3 personnages enregistrés).
	MultiplayerManager.client_request_start_game(
		"demo-valbois",
		[],
		"multi",
		"human",
		"oneshot",
		3,
		["demo-valbois-village", "demo-valbois-place"]
	)

func _on_game_started(_id: String, state: Dictionary) -> void:
	GameData.apply_server_state(state)
	GameData.active_game["forcePlayerView"] = false
	GameData.active_game["allowGmProxyActions"] = false
	GameData.active_game["gmName"] = "MJ Valbois"
	GameData.save_active_game()
	Shared.write_status({"phase": "playing", "code": MultiplayerManager.room_code})
	_banner.text = "MJ — session en cours"
	var dir: Node = Director.new()
	dir.name = "ValboisLanDirector"
	dir.set("role_mode", "gm")
	dir.set("step_delay", 1.1)
	get_tree().root.add_child(dir)
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")
	dir.call_deferred("start_when_ready")

func _on_err(msg: String) -> void:
	_log("ERR %s" % msg)
	_banner.text = "MJ ERREUR : %s" % msg

func _fail(msg: String) -> void:
	_on_err(msg)
	push_error(msg)

func _log(msg: String) -> void:
	print("[LAN HOST] %s" % msg)

func _make_banner(text: String) -> Label:
	var b := Label.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	b.set_anchors_preset(Control.PRESET_TOP_WIDE)
	b.offset_top = 6
	b.offset_bottom = 36
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(b)
	return b
