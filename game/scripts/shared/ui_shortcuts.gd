extends RefCounted
class_name UiShortcuts

## Raccourcis clavier partagés de l'interface.
##
## Centralisé ici pour que « Échap annule/ferme » et « Ctrl+Entrée valide »
## se comportent pareil partout, au lieu d'être ré-implémentés (ou oubliés)
## écran par écran.

## Ctrl+Entrée (ou Ctrl+Entrée du pavé numérique) : valider / envoyer.
static func is_submit(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	return key.ctrl_pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER)


## Ctrl+S : enregistrer.
static func is_save(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return false
	return key.ctrl_pressed and key.keycode == KEY_S


## Échap : fermer le panneau courant, revenir en arrière.
static func is_cancel(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_cancel")


## Valider / annuler via les actions UI standard (Entrée, Espace, Échap).
static func is_accept(event: InputEvent) -> bool:
	return event.is_action_pressed("ui_accept")
