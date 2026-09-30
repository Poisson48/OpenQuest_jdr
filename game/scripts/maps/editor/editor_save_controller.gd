extends RefCounted
class_name EditorSaveController

## Contrôleur de sauvegarde de l'éditeur de cartes.
##
## Gère les trois politiques de sauvegarde et la sérialisation du document
## vers `MapData`. Extraite de `map_complex_editor.gd`.

const DocumentScript := preload("res://scripts/maps/editor/map_edit_document.gd")

# --- Politiques de sauvegarde --------------------------------------------------
const SAVE_MANUAL := "manual"
const SAVE_ON_CHANGE := "on_change"
const SAVE_INTERVAL := "interval"

## Politique active.
var save_policy: String = SAVE_MANUAL
## Intervalle de sauvegarde automatique (secondes).
var save_interval: float = 30.0
## Timestamp de la dernière sauvegarde (unix).
var last_saved_at: float = 0.0

# --- Callbacks injectés --------------------------------------------------------
var on_status: Callable = Callable()
var on_refresh_badges: Callable = Callable()
var on_layout_changed: Callable = Callable()

## Retourne le libellé de la politique courante.
func policy_label() -> String:
	match save_policy:
		SAVE_ON_CHANGE:
			return "À chaque modif"
		SAVE_INTERVAL:
			return "Toutes les 30 s"
		_:
			return "Manuelle"

## Change la politique de sauvegarde et notifie l'UI.
func set_policy(policy: String, label: String = "") -> void:
	save_policy = policy
	on_status.call("Politique de sauvegarde : %s" % (label if not label.is_empty() else policy_label()))
	on_refresh_badges.call()

## Sérialise le document vers un snapshot `MapData` prêt à persister.
func serialize(doc, engine = null) -> Dictionary:
	if engine and engine.has_method("get_view_state"):
		doc.play_defaults["viewState"] = engine.get_view_state()
	return doc.to_map_data()

## Enregistre le document dans `MapData` et marque comme propre.
func save_now(doc, engine = null) -> void:
	var snapshot := serialize(doc, engine)
	MapData.update_map(snapshot)
	doc.mark_saved()
	last_saved_at = Time.get_unix_time_from_system()
	on_status.call("Carte enregistrée.")
	on_refresh_badges.call()
	on_layout_changed.call()

## Appelé par `_on_doc_changed` : déclenche la sauvegarde si la politique l'exige.
func on_doc_changed(doc, reason: String) -> void:
	if save_policy == SAVE_ON_CHANGE and doc.is_dirty() and reason != "load":
		save_now(doc)

## Retourne le temps écoulé depuis la dernière sauvegarde, formaté.
func saved_ago_text() -> String:
	if last_saved_at <= 0.0:
		return "jamais sauvé"
	var ago := int(Time.get_unix_time_from_system() - last_saved_at)
	if ago < 5:
		return "sauvé à l'instant"
	elif ago < 60:
		return "sauvé il y a %ds" % ago
	elif ago < 3600:
		return "sauvé il y a %d min" % int(ago / 60.0)
	else:
		return "sauvé il y a %d h" % int(ago / 3600.0)

## Retourne `true` si l'auto-save par intervalle est active.
func is_autosave_active() -> bool:
	return save_policy == SAVE_INTERVAL

## Retourne le compte à rebours avant la prochaine auto-save (secondes).
func autosave_countdown(timer: Timer) -> int:
	if timer == null or timer.is_stopped():
		return 0
	return maxi(0, int(ceil(timer.time_left)))

## Exporte le snapshot courant vers un fichier JSON.
func export_json(doc, engine, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		on_status.call("Export impossible : %s" % path)
		return false
	file.store_string(JSON.stringify(serialize(doc, engine), "\t"))
	on_status.call("Carte exportée : %s" % path.get_file())
	return true

## Importe un fichier JSON comme nouvelle définition de la carte courante.
func import_json(doc, path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		on_status.call("Fichier JSON invalide.")
		return false
	var imported: Dictionary = parsed
	imported["id"] = doc.map_data.get("id", imported.get("id", ""))
	doc.load_map(imported)
	on_status.call("Carte importée depuis %s" % path.get_file())
	return true
