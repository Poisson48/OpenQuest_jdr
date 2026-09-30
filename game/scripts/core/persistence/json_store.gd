extends RefCounted
class_name JsonStore

## Magasin JSON générique pour la persistance `user://`.
##
## Centralise le chargement/sauvegarde des fichiers JSON du jeu.
## Utilisé par les repositories (CharacterRepository, ScenarioRepository, …)
## pour éviter la duplication des helpers `_load_json_file`/`_save_json_file`.

## Charge un fichier JSON et retourne sa valeur parsée, ou `null` en cas d'erreur.
static func load_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("JsonStore: impossible d'ouvrir %s" % path)
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_warning("JsonStore: JSON invalide dans %s" % path)
	return parsed

## Sauvegarde une valeur en JSON. Retourne `true` si l'écriture a réussi.
static func save_file(path: String, data: Variant) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("JsonStore: impossible d'écrire %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

## Supprime un fichier s'il existe.
static func delete_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

## Retourne `true` si le fichier existe.
static func exists(path: String) -> bool:
	return FileAccess.file_exists(path)
