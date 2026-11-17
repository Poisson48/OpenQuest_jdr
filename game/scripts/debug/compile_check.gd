extends Node

## Porte de compilation du projet (outillage de refactor).
##
## Charge TOUS les scripts `.gd` (et, en option, toutes les scènes `.tscn`) du
## projet dans un vrai run Godot headless, avec les autoloads enregistrés, pour
## attraper les erreurs de parse/compilation et les `preload` cassés sans lancer
## la suite de tests complète. Beaucoup plus rapide que `run_tests.ps1` : à
## utiliser avant chaque commit du refactor.
##
## Lancement (voir `tools/refactor/verify.ps1`) :
##
##   godot --headless --path game --scene res://scenes/debug/compile_check.tscn
##   godot --headless --path game --scene res://scenes/debug/compile_check.tscn -- --scenes
##
## Code de sortie : 0 = tout compile, 1 = au moins un échec.

const SCRIPT_ROOT := "res://scripts"
const SCENE_ROOT := "res://scenes"

var _checked := 0
var _failures: Array[String] = []


func _ready() -> void:
	var check_scenes := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--scenes":
			check_scenes = true

	var t0 := Time.get_ticks_msec()
	print("[COMPILE CHECK] racine projet : %s" % ProjectSettings.globalize_path("res://"))
	_scan(SCRIPT_ROOT, ".gd")
	if check_scenes:
		_scan(SCENE_ROOT, ".tscn")
	var elapsed := (Time.get_ticks_msec() - t0) / 1000.0

	print("[COMPILE CHECK] %d fichier(s) vérifié(s) en %.1f s — %d échec(s)" % [
		_checked, elapsed, _failures.size()])
	for failure in _failures:
		printerr("[COMPILE CHECK] ÉCHEC : %s" % failure)
	if _failures.is_empty():
		print("[COMPILE CHECK] :PASS")
	else:
		printerr("[COMPILE CHECK] :FAIL")
	get_tree().quit(1 if not _failures.is_empty() else 0)


func _scan(dir_path: String, extension: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		_failures.append("%s (dossier illisible)" % dir_path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan(dir_path.path_join(entry), extension)
		elif entry.ends_with(extension):
			_check_file(dir_path.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()


func _check_file(path: String) -> void:
	_checked += 1
	var res: Resource = ResourceLoader.load(path)
	if res == null:
		_failures.append("%s (chargement impossible — voir erreurs ci-dessus)" % path)
		return
	if res is Script and not (res as Script).can_instantiate():
		# Godot renvoie quand même l'objet GDScript quand la compilation échoue ;
		# `can_instantiate()` est le seul signal fiable dans ce cas.
		_failures.append("%s (compilation échouée — voir erreurs ci-dessus)" % path)
