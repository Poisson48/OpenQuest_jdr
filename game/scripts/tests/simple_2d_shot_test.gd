extends SceneTree

## Captures de référence de la carte 2D SIMPLE (avant/après refonte pixel-art).
##
## À lancer SANS `--headless` (les PNG du rendu 2D ont besoin d'un contexte de
## rendu réel) :
##
##   Godot_v4.7.2-stable_win64_console.exe --path game \
##       --script res://scripts/tests/simple_2d_shot_test.gd -- --prefix=carte_2d_avant
##
## Produit dans docs/screenshots/ :
##   <prefix>_render.png  — rendu brut du moteur InteractiveMap (SubViewport 960x600)
##   <prefix>_session.png — session MJ complète (Brumeval, demo-crypte)
##   <prefix>_editeur.png — éditeur 2D (map_viewer, mode édition)
##
## En `--headless` les captures sont sautées mais les vérifications de scène
## restent exécutées : le script sort 0 (utilisable dans run_tests.ps1).

const OUT_DOCS := "res://../docs/screenshots"
const MAP_ID := "demo-crypte-brumeval"
const RENDER_SIZE := Vector2i(960, 600)

var _failed := false
var _prefix := "carte_2d_avant"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	_prefix = _arg_prefix()

	var gd = get_root().get_node("GameData")
	var md = get_root().get_node("MapData")
	gd.reload_builtin_scenarios()
	var map: Dictionary = md.get_by_id(MAP_ID)
	_assert("map_present_%s" % MAP_ID, not map.is_empty())
	if map.is_empty():
		_finish()
		return
	_assert("map_simple", str(map.get("renderMode", "simple")) == "simple")

	await _shot_render(map)
	await _shot_session(gd)
	await _shot_editor(md)

	_finish()

func _arg_prefix() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--prefix="):
			return arg.trim_prefix("--prefix=").strip_edges()
	return "carte_2d_avant"

func _assert(label: String, ok: bool) -> void:
	print(("OK " if ok else "FAIL ") + label)
	if not ok:
		_failed = true

func _finish() -> void:
	if _failed:
		print("simple_2d_shot_test:FAIL (prefix=%s)" % _prefix)
		quit(1)
	else:
		print("simple_2d_shot_test:PASS (prefix=%s)" % _prefix)
		quit(0)

# ---------------------------------------------------------------------------
# 1. Rendu brut du moteur — même cadrage avant/après pour comparer le pixel-art
# ---------------------------------------------------------------------------

func _shot_render(map: Dictionary) -> void:
	var host := SubViewport.new()
	host.size = RENDER_SIZE
	host.transparent_bg = false
	host.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(host)

	var imap: Control = load("res://scripts/maps/simple_map_renderer.gd").new()
	host.add_child(imap)
	imap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var explored: Array = []
	var w: int = int(map.get("width", 0))
	var h: int = int(map.get("height", 0))
	for y in range(h):
		for x in range(w):
			explored.append("%d,%d" % [x, y])
	var tokens: Array = []
	var play_defaults = map.get("playDefaults", {})
	if play_defaults is Dictionary:
		tokens = play_defaults.get("tokens", [])
	imap.configure(map, tokens, [], explored, "oneshot", false, {}, [], [], [], [], [], [])
	imap.suppress_navigation = true
	imap.always_show_areas = false
	for _i in range(8):
		await process_frame
	var cs: int = imap.get_cell_size() if imap.has_method("get_cell_size") else 0
	print("render_cell_size=", cs, " map=", w, "x", h, " tokens=", tokens.size())
	_assert("render_cell_size_positive", cs > 0)
	_save_image(_prefix + "_render", host.get_texture().get_image())
	host.queue_free()
	await process_frame

# ---------------------------------------------------------------------------
# 2. Session MJ — intégration réelle (HUD, panneaux, carte dans le stage)
# ---------------------------------------------------------------------------

func _shot_session(gd) -> void:
	var mm = get_root().get_node("MultiplayerManager")
	var party: Array = [
		{"id": "h1", "name": "Aria", "race": "Elfe", "class": "Rôdeuse", "hp": 12, "ac": 14,
			"isPlayer": true, "isHuman": true, "clientId": "j1"},
		{"id": "h2", "name": "Thorin", "race": "Nain", "class": "Guerrier", "hp": 14, "ac": 16,
			"isPlayer": true, "isHuman": true, "clientId": "j2"},
	]
	gd.create_new_game("demo-crypte", "multi", "human", "long", party)
	gd.active_game["waitingForGm"] = true
	mm.player_role = "gm"
	mm.player_name = "MJ"
	mm.is_gm = true

	change_scene_to_file("res://scenes/session/session.tscn")
	for _i in range(120):
		await process_frame
	var shell: Node = current_scene
	if shell != null and shell.has_method("describe"):
		var desc: Dictionary = shell.describe()
		var map_info: Dictionary = desc.get("map", {})
		print("session_map_describe=", map_info)
		_assert("session_map_stage_present", float(map_info.get("stage_size", Vector2.ZERO).x) > 100.0)
		_assert("session_mode_simple", str(map_info.get("mode", "")) == "simple")
	_save_image(_prefix + "_session", get_root().get_texture().get_image())

# ---------------------------------------------------------------------------
# 3. Éditeur 2D — même carte ouverte dans map_viewer en mode édition
# ---------------------------------------------------------------------------

func _shot_editor(md) -> void:
	md.preview_map_id = MAP_ID
	md.editor_mode = "edit"
	change_scene_to_file("res://scenes/map_viewer.tscn")
	for _i in range(90):
		await process_frame
	var viewer: Node = current_scene
	_assert("editor_scene_loaded", viewer != null)
	_save_image(_prefix + "_editeur", get_root().get_texture().get_image())
	# Aperçu (lecture seule) — vérifie que l'éditeur 2D se recharge dans l'autre sens.
	md.editor_mode = "preview"
	viewer.call("_rebuild_for_mode")
	for _i in range(30):
		await process_frame
	_save_image(_prefix + "_apercu", get_root().get_texture().get_image())

# ---------------------------------------------------------------------------

func _save_image(name: String, img: Image) -> void:
	if DisplayServer.get_name() == "headless":
		print("skip_shot_headless=", name)
		return
	if img == null:
		_assert("shot_%s" % name, false)
		return
	var docs := ProjectSettings.globalize_path(OUT_DOCS)
	DirAccess.make_dir_recursive_absolute(docs)
	var path := "%s/%s.png" % [docs, name]
	var err := img.save_png(path)
	print("screenshot=", path, " err=", err)
	_assert("shot_%s" % name, err == OK)
