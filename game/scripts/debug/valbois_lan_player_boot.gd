extends Node

## Boot joueur local : lit le code salon, rejoint, enregistre un perso, attend le lancement.

const Shared = preload("res://scripts/debug/lan_table_shared.gd")
const Director = preload("res://scripts/debug/valbois_lan_director.gd")

@export var player_slot: int = 1 ## 1=Aria, 2=Thorin, 3=Kael

var _joined := false
var _registered := false
var _banner: Label

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("slot="):
			player_slot = int(arg.get_slice("=", 1))
	var info := _identity()
	_banner = _make_banner("%s — attente du code salon…" % info.name)
	MultiplayerManager.force_loopback_p2p = true
	MultiplayerManager.set_player_role("player")
	MultiplayerManager.player_name = info.name
	MultiplayerManager.p2p_error.connect(func(m): _banner.text = "%s ERR: %s" % [info.name, m])
	MultiplayerManager.room_joined.connect(_on_joined)
	MultiplayerManager.room_updated.connect(_on_room_updated)
	MultiplayerManager.game_started.connect(_on_game_started)
	MultiplayerManager.p2p_connected.connect(func(_id): _log("ENet connecté"))

	MultiplayerManager.connect_pooling("ws://127.0.0.1:8080", info.name)
	_poll_code_and_join()

func _identity() -> Dictionary:
	match clampi(player_slot, 1, 3):
		1:
			return {
				"name": "Aria",
				"character": {
					"id": "char-aria", "name": "Aria", "race": "Elfe", "class": "Rôdeuse",
					"hp": 12, "ac": 14,
					"inventory": [
						{"id": "item-arc", "name": "Arc court", "qty": 1},
						{"id": "item-rations", "name": "Rations", "qty": 2},
					],
				},
			}
		2:
			return {
				"name": "Thorin",
				"character": {
					"id": "char-thorin", "name": "Thorin", "race": "Nain", "class": "Guerrier",
					"hp": 14, "ac": 16,
					"inventory": [
						{"id": "item-hache", "name": "Hache de guerre", "qty": 1},
						{"id": "item-bouclier", "name": "Bouclier", "qty": 1},
					],
				},
			}
		_:
			var kael := GameData.make_kael_party_member()
			kael["inventory"] = [
				{"id": "item-crochets", "name": "Crochets de serrure", "qty": 1},
				{"id": "item-cape", "name": "Cape sombre", "qty": 1},
			]
			return {"name": "Kael", "character": kael}

func _poll_code_and_join() -> void:
	var t := 0.0
	while t < 60.0:
		if not MultiplayerManager.is_pooling_connected():
			await get_tree().create_timer(0.3).timeout
			t += 0.3
			continue
		var code := Shared.read_room_code()
		if code.is_empty():
			_banner.text = "%s — attente du code MJ…" % MultiplayerManager.player_name
			await get_tree().create_timer(0.4).timeout
			t += 0.4
			continue
		if not _joined:
			_banner.text = "%s — rejoindre %s…" % [MultiplayerManager.player_name, code]
			MultiplayerManager.join_room(code)
			_joined = true
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		if _registered and MultiplayerManager.is_p2p_active():
			_banner.text = "%s — prêt, en attente du MJ…" % MultiplayerManager.player_name
			return
	_banner.text = "%s — timeout salon" % MultiplayerManager.player_name

func _on_joined(code: String, _room: Dictionary) -> void:
	_log("Rejoint %s" % code)
	_banner.text = "%s — salon %s, enregistrement…" % [MultiplayerManager.player_name, code]
	_register_character()

func _on_room_updated(_room: Dictionary) -> void:
	if not _registered and MultiplayerManager.is_in_room():
		_register_character()

func _register_character() -> void:
	if _registered:
		return
	var info := _identity()
	var ch: Dictionary = info.character.duplicate(true)
	ch["isPlayer"] = true
	ch["isHuman"] = true
	ch["isBot"] = false
	MultiplayerManager.register_character(ch)
	_registered = true
	_log("Personnage enregistré : %s" % ch.get("name", "?"))
	_banner.text = "%s — prêt (salon %s)" % [info.name, MultiplayerManager.room_code]

func _on_game_started(_id: String, state: Dictionary) -> void:
	GameData.apply_server_state(state)
	_banner.text = "%s — session !" % MultiplayerManager.player_name
	var dir: Node = Director.new()
	dir.name = "ValboisLanDirector"
	dir.set("role_mode", "player")
	dir.set("step_delay", 1.0)
	dir.set("player_slot", player_slot)
	get_tree().root.add_child(dir)
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")
	dir.call_deferred("start_when_ready")

func _log(msg: String) -> void:
	print("[LAN P%d] %s" % [player_slot, msg])

func _make_banner(text: String) -> Label:
	var b := Label.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", Color(0.7, 0.95, 1.0))
	b.set_anchors_preset(Control.PRESET_TOP_WIDE)
	b.offset_top = 6
	b.offset_bottom = 34
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(b)
	return b
