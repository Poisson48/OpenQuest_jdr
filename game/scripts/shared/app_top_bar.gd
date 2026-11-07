extends HBoxContainer

## Barre de navigation partagée : bouton retour + titre + actions.
## Chaque page l'instancie, définit le titre et ajoute ses propres
## boutons dans le conteneur %Actions.

signal back_pressed

@onready var btn_back: Button = %BtnBack
@onready var title: Label = %Title
@onready var crumb: Label = %Crumb
@onready var actions: HBoxContainer = %Actions

## Texte du bouton retour (défaut : "← Retour").
@export var back_text: String = "← Retour":
	set(value):
		back_text = value
		if is_node_ready():
			btn_back.text = value

## Texte du titre.
@export var title_text: String = "Page":
	set(value):
		title_text = value
		if is_node_ready():
			title.text = value

## Fil d'Ariane affiché au-dessus du titre (ex. « Hub › Scénarios › Éditeur »).
@export var crumb_text: String = "":
	set(value):
		crumb_text = value
		if is_node_ready():
			_apply_crumb()

func _apply_crumb() -> void:
	crumb.text = crumb_text
	crumb.visible = not crumb_text.is_empty()

func _ready() -> void:
	btn_back.text = back_text
	title.text = title_text
	_apply_crumb()
	btn_back.pressed.connect(func(): back_pressed.emit())

## Met à jour le titre (pages dont le titre est dynamique).
func set_title(value: String) -> void:
	title_text = value

## Affiche / masque le libellé de titre (éditeur de carte : champ de saisie).
func set_title_visible(on: bool) -> void:
	title.visible = on

## Ajoute un contrôle dans la zone d'actions (à droite du titre).
func add_action(control: Control) -> void:
	actions.add_child(control)
