extends HBoxContainer

## Barre de navigation partagée : bouton retour + titre + actions.
## Chaque page l'instancie, définit le titre et ajoute ses propres
## boutons dans le conteneur %Actions.

signal back_pressed

@onready var btn_back: Button = %BtnBack
@onready var title: Label = %Title
@onready var actions: HBoxContainer = %Actions

## Texte du bouton retour (défaut : "← Retour").
var back_text: String = "← Retour":
	set(value):
		back_text = value
		if is_node_ready():
			btn_back.text = value

## Texte du titre.
var title_text: String = "Page":
	set(value):
		title_text = value
		if is_node_ready():
			title.text = value

func _ready() -> void:
	btn_back.text = back_text
	title.text = title_text
	btn_back.pressed.connect(func(): back_pressed.emit())

## Ajoute un contrôle dans la zone d'actions (à droite du titre).
func add_action(control: Control) -> void:
	actions.add_child(control)
