extends Node

## Hauteur unique des boutons de l'interface.
##
## Godot calcule la hauteur d'un Button à partir de la police et des marges de
## son StyleBox : elle varie donc d'un type de bouton à l'autre (32, 34, 40, 44,
## 50 px…). Pour une UI cohérente on impose la même hauteur minimale à TOUS les
## boutons, y compris ceux créés à l'exécution (onglets du hub, cartes, lignes
## de sauvegarde…), d'où ce branchement sur `node_added` plutôt qu'une retouche
## scène par scène.

const BUTTON_HEIGHT := 48

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	# Les nœuds déjà présents (autoloads, scène courante) ne déclenchent pas
	# `node_added` : on les traite explicitement.
	call_deferred("_apply_to_tree")

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		call_deferred("_apply_to_button", node)

func _apply_to_tree() -> void:
	for node in get_tree().root.find_children("*", "BaseButton", true, false):
		_apply_to_button(node)

func _apply_to_button(button: BaseButton) -> void:
	if button == null or not is_instance_valid(button):
		return
	# Exemption : les tuiles d'icônes (flyout de l'éditeur, grilles) gèrent
	# leur propre taille — la hauteur standard de 48 px les écraserait.
	if button.has_meta("skip_button_sizing"):
		return
	# Hauteur unique : on écrase toute hauteur déclarée dans les scènes
	# (autrefois 32, 34, 40, 44, 50 px selon les écrans).
	button.custom_minimum_size.y = BUTTON_HEIGHT
