extends SceneTree

## Géométrie session / HUD aux tailles démo LAN (2x2 ~1720×696) et 1280×720 / 800.
## Headless via SubViewport à taille forcée — pas de fenêtres desktop.

const SIZES := [
	Vector2i(1720, 696),
	Vector2i(1280, 720),
	Vector2i(1280, 800),
]
const PARSE_SCENES := [
	"res://scenes/session/session.tscn",
	"res://scenes/session/panels/player_hud.tscn",
	"res://scenes/session/panels/map_stage.tscn",
	"res://scenes/session/panels/speaker_dialogue_overlay.tscn",
	"res://scenes/session/panels/gm_console.tscn",
]
const PARSE_SCRIPTS := [
	"res://scripts/session/session_layout.gd",
	"res://scripts/session/session_shell.gd",
	"res://scripts/ui/player_session_hud.gd",
	"res://scripts/session/panels/map_stage.gd",
	"res://scripts/session/panels/speaker_dialogue_overlay.gd",
	"res://scripts/session/panels/gm_console.gd",
]

var _failed := false
var _host: SubViewport = null

func _init() -> void:
	call_deferred("_run")
	call_deferred("_arm_watchdog")

func _arm_watchdog() -> void:
	create_timer(120.0).timeout.connect(func():
		print("[HALFSCREEN LAYOUT] FAIL — délai dépassé")
		quit(1))

func _run() -> void:
	await process_frame
	_parse_check()
	if _failed:
		print("[HALFSCREEN LAYOUT] FAIL — parse")
		quit(1)
		return

	for sz in SIZES:
		await _probe_size(sz, false)
		await _probe_size(sz, true)

	if _failed:
		print("[HALFSCREEN LAYOUT] FAIL")
		quit(1)
	else:
		print("[HALFSCREEN LAYOUT] PASS")
		quit(0)

func _parse_check() -> void:
	for path in PARSE_SCENES:
		var packed: PackedScene = load(path)
		_assert("parse_scene %s" % path.get_file(), packed != null)
		if packed == null:
			continue
		var inst := packed.instantiate()
		_assert("instantiate %s" % path.get_file(), inst != null)
		if inst:
			inst.free()
	for path in PARSE_SCRIPTS:
		var script: GDScript = load(path)
		_assert("parse_script %s" % path.get_file(), script != null)

func _probe_size(sz: Vector2i, player_view: bool) -> void:
	_seed_game(player_view)
	var shell := await _mount(sz)
	if shell == null:
		_assert("%s mount" % _tag(sz, player_view), false)
		return
	if player_view:
		_check_player(shell, sz)
		await _check_dialogue(shell, sz)
		_try_headless_png(sz)
	else:
		_check_gm(shell, sz)
	_unmount()

func _mount(sz: Vector2i) -> Node:
	_unmount()
	_host = SubViewport.new()
	_host.name = "HalfscreenHost"
	_host.size = sz
	_host.disable_3d = false
	_host.transparent_bg = false
	_host.handle_input_locally = false
	_host.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(_host)
	var packed: PackedScene = load("res://scenes/session/session.tscn")
	if packed == null:
		return null
	var shell: Node = packed.instantiate()
	_host.add_child(shell)
	if shell is Control:
		(shell as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await _settle(40)
	if shell.get_player_hud() != null and shell.get_player_hud().has_method("_adapt_chrome"):
		shell.get_player_hud().call("_adapt_chrome")
	if shell.has_method("_sync_immersive_insets"):
		shell.call("_sync_immersive_insets")
	await _settle(12)
	print("mounted ", sz, " host=", _host.size, " shell=", (shell as Control).size if shell is Control else Vector2.ZERO)
	return shell

func _unmount() -> void:
	if _host != null and is_instance_valid(_host):
		_host.queue_free()
		_host = null

func _seed_game(player_view: bool) -> void:
	var gd = get_root().get_node("GameData")
	var mm = get_root().get_node("MultiplayerManager")
	var party: Array = [
		{"id": "h1", "name": "Aria", "race": "Elfe", "class": "Rôdeuse", "hp": 12, "ac": 14,
			"isPlayer": true, "isHuman": true, "clientId": "j1"},
		{"id": "h2", "name": "Thorin", "race": "Nain", "class": "Guerrier", "hp": 14, "ac": 16,
			"isPlayer": true, "isHuman": true, "clientId": "j2"},
		{"id": "b1", "name": "Kael", "race": "Humain", "class": "Rôdeur", "hp": 11, "ac": 13, "isBot": true},
	]
	gd.reload_builtin_scenarios()
	gd.create_new_game("demo-kharak", "multi", "human", "long", party)
	gd.active_game["waitingForGm"] = false
	gd.active_game["status"] = "playing"
	gd.active_game["forcePlayerView"] = player_view
	mm.player_role = "player" if player_view else "gm"
	mm.player_name = "Aria" if player_view else "MJ"
	mm.is_gm = not player_view

func _check_gm(shell: Node, sz: Vector2i) -> void:
	var tag := _tag(sz, false)
	var report: Dictionary = shell.describe()
	print(tag, " describe=", report)
	_assert("%s role_gm" % tag, str(report.get("role", "")) == "gm")
	_assert("%s docks" % tag, bool(report.get("left_visible", false)) and bool(report.get("right_visible", false)))
	var map_w := float(report.get("center_width", 0.0))
	var map_h := float(report.get("center_height", 0.0))
	_assert("%s map_not_zero" % tag, map_w >= 200.0 and map_h >= 160.0)
	_assert("%s map_dominates_x" % tag, map_w + 1.0 >= float(report.get("left_width", 0.0)))
	_assert("%s map_dominates_y" % tag, map_h >= float(sz.y) * 0.42)
	var used := float(report.get("left_width", 0.0)) + map_w + float(report.get("right_width", 0.0))
	_assert("%s columns_fit" % tag, used <= float(sz.x) + 8.0)
	var map_info: Dictionary = report.get("map", {})
	var stage: Vector2 = map_info.get("stage_size", Vector2.ZERO)
	_assert("%s stage_alive" % tag, stage.x >= 180.0 and stage.y >= 140.0)

func _check_player(shell: Node, sz: Vector2i) -> void:
	var tag := _tag(sz, true)
	var report: Dictionary = shell.describe()
	print(tag, " describe=", report)
	_assert("%s immersive" % tag, shell.is_immersive())
	_assert("%s hud" % tag, bool(report.get("hud_visible", false)))
	_assert("%s docks_hidden" % tag, not bool(report.get("left_visible", true)) and not bool(report.get("right_visible", true)))
	var map_info: Dictionary = report.get("map", {})
	var stage: Vector2 = map_info.get("stage_size", Vector2.ZERO)
	_assert("%s stage_fullish" % tag, stage.x >= float(sz.x) * 0.85 and stage.y >= float(sz.y) * 0.85)
	var hud: Control = shell.get_player_hud()
	_assert("%s hud_node" % tag, hud != null)
	if hud == null:
		return
	if hud.has_method("_adapt_chrome"):
		hud.call("_adapt_chrome")
	var journal := hud.get_node_or_null("JournalDock") as Control
	var hero := hud.get_node_or_null("HeroDock") as Control
	var bottom := hud.get_node_or_null("BottomBar") as Control
	var top := hud.get_node_or_null("TopBar") as Control
	_assert("%s journal" % tag, journal != null and journal.size.x > 40.0)
	_assert("%s hero" % tag, hero != null and hero.size.x > 40.0)
	_assert("%s bottom" % tag, bottom != null and bottom.size.y > 40.0)
	if journal:
		print(tag, " journal=", journal.size, " hero=", hero.size if hero else Vector2.ZERO, " bottom=", bottom.size if bottom else Vector2.ZERO)
		_assert("%s journal_not_half" % tag, journal.size.x <= maxf(360.0, float(sz.x) * 0.26))
		_assert("%s journal_usable" % tag, journal.size.x >= 180.0 and journal.size.y >= 120.0)
	if hero:
		_assert("%s hero_corner" % tag, hero.size.x <= 340.0 and hero.size.y <= 220.0)
	if bottom:
		_assert("%s bottom_not_half" % tag, bottom.size.y <= float(sz.y) * 0.32)
	if hud.has_method("chrome_insets"):
		var inset: Vector4 = hud.chrome_insets()
		print(tag, " insets=", inset)
		var hole_x := float(sz.x) - inset.x - inset.z
		var hole_y := float(sz.y) - inset.y - inset.w
		_assert("%s inset_no_hero_column" % tag, inset.x < 80.0)
		_assert("%s inset_journal_capped" % tag, inset.z <= maxf(360.0, float(sz.x) * 0.28))
		_assert("%s inset_hole_x" % tag, hole_x >= float(sz.x) * 0.42)
		_assert("%s inset_hole_y" % tag, hole_y >= float(sz.y) * 0.40)
		if top:
			_assert("%s top_thin" % tag, top.size.y <= 80.0)

func _check_dialogue(shell: Node, sz: Vector2i) -> void:
	var tag := "%dx%d dialogue" % [sz.x, sz.y]
	var dlg: Node = shell.get_node_or_null("%SpeakerDialogue")
	_assert("%s overlay" % tag, dlg != null)
	if dlg == null or not dlg.has_method("enqueue"):
		return
	if dlg.has_method("clear"):
		dlg.clear()
	dlg.enqueue("Thorin", "Je barre le passage si la milice revient.", "player", "")
	await _settle(10)
	var box := dlg.get_node_or_null("%DialogueBox") as Control
	var art := dlg.get_node_or_null("%SpeakerArt") as Control
	var hud: Control = shell.get_player_hud()
	var hero := hud.get_node_or_null("HeroDock") as Control if hud else null
	var journal := hud.get_node_or_null("JournalDock") as Control if hud else null
	var bottom := hud.get_node_or_null("BottomBar") as Control if hud else null
	_assert("%s box_visible" % tag, box != null and box.visible and box.size.x > 80.0)
	if box:
		print(tag, " box=", box.get_global_rect(), " art=", art.get_global_rect() if art else Rect2())
		var box_area := box.size.x * box.size.y
		_assert("%s box_not_fullscreen" % tag, box_area <= float(sz.x * sz.y) * 0.28)
		if hero:
			_assert("%s box_vs_hero" % tag, _overlap_ratio(box.get_global_rect(), hero.get_global_rect()) < 0.18)
		if journal and journal.visible:
			_assert("%s box_vs_journal" % tag, _overlap_ratio(box.get_global_rect(), journal.get_global_rect()) < 0.18)
		if bottom:
			_assert("%s box_vs_bottom" % tag, _overlap_ratio(box.get_global_rect(), bottom.get_global_rect()) < 0.22)
	if art and art.visible:
		_assert("%s art_not_huge" % tag, art.size.y <= float(sz.y) * 0.42)
	if dlg.has_method("clear"):
		dlg.clear()

func _try_headless_png(sz: Vector2i) -> void:
	# Renderer dummy (--headless) : pas de texture 2D, on ne capture pas.
	if _host == null or DisplayServer.get_name() == "headless":
		print("headless_png skip ", sz)
		return
	var tex := _host.get_texture()
	if tex == null:
		print("headless_png skip (no tex) ", sz)
		return
	var img: Image = tex.get_image()
	if img == null or img.get_width() < 8:
		print("headless_png skip (empty) ", sz)
		return
	var path := ProjectSettings.globalize_path("res://../valbois-ux-break-headless-%dx%d.png" % [sz.x, sz.y])
	var err := img.save_png(path)
	print("headless_png ", path, " err=", err, " ", img.get_width(), "x", img.get_height())

func _tag(sz: Vector2i, player_view: bool) -> String:
	return "%dx%d %s" % [sz.x, sz.y, "player" if player_view else "gm"]

func _overlap_ratio(a: Rect2, b: Rect2) -> float:
	var inter := a.intersection(b)
	if inter.size.x <= 0.0 or inter.size.y <= 0.0:
		return 0.0
	var smaller := minf(a.get_area(), b.get_area())
	if smaller <= 1.0:
		return 0.0
	return inter.get_area() / smaller

func _settle(frames: int) -> void:
	for _i in range(frames):
		await process_frame

func _assert(label: String, ok: bool) -> void:
	print(("  OK   " if ok else "  FAIL ") + label)
	if not ok:
		_failed = true
