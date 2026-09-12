extends RefCounted
class_name LanTableShared

## Fichiers partagés entre les 4 fenêtres Godot (même PC).

static func repo_root() -> String:
	var base := ProjectSettings.globalize_path("res://").simplify_path()
	# Cas normal : res:// = .../game
	var parent := base.path_join("..").simplify_path()
	if FileAccess.file_exists(parent.path_join("scripts").path_join("play-godot-valbois-lan.ps1")):
		return parent
	# Profil isolé : res:// = .../.godot_profiles/MJ → remonter 2 niveaux
	var grand := parent.path_join("..").simplify_path()
	if FileAccess.file_exists(grand.path_join("scripts").path_join("play-godot-valbois-lan.ps1")):
		return grand
	return parent

static func root_dir() -> String:
	return repo_root().path_join(".lan_table")

static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(root_dir())

static func room_code_path() -> String:
	return root_dir().path_join("room_code.txt")

static func status_path() -> String:
	return root_dir().path_join("status.json")

static func clear() -> void:
	ensure_dir()
	for name in ["room_code.txt", "status.json", "ready_players.txt"]:
		var p := root_dir().path_join(name)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

static func write_room_code(code: String) -> void:
	ensure_dir()
	var f := FileAccess.open(room_code_path(), FileAccess.WRITE)
	if f:
		f.store_string(code.strip_edges())

static func read_room_code() -> String:
	if not FileAccess.file_exists(room_code_path()):
		return ""
	var f := FileAccess.open(room_code_path(), FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text().strip_edges()

static func write_status(data: Dictionary) -> void:
	ensure_dir()
	var f := FileAccess.open(status_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

static func read_status() -> Dictionary:
	if not FileAccess.file_exists(status_path()):
		return {}
	var f := FileAccess.open(status_path(), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
