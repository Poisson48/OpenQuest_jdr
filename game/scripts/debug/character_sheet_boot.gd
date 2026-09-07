extends Node

## Ouvre la fiche personnage en session (page Histoire) pour visualiser le scroll.

const CharacterSheetScene := preload("res://scenes/session/panels/character_sheet.tscn")

const LONG_STORY := """Kael est né dans les ruelles de Valbois, là où les lanternes s'éteignent trop tôt et où les dettes se règlent en silence. Orphelin à neuf ans, il a appris à lire les ombres avant de lire les lettres : chaque porte entrebâillée, chaque regard trop long, chaque bourse mal attachée était une leçon.

Adolescent, il a servi de messager pour des contrebandiers du Chemin de la Forêt. On l'appelait « le Moineau » — trop petit pour qu'on s'en méfie, assez vif pour disparaître avant que la garde n'arrive. Une nuit, une livraison a mal tourné près de la Place du Marché. Kael a survécu ; son mentor, non. Depuis, il porte une cicatrice sous la clavicule et une méfiance qui ne dort jamais.

Aujourd'hui, il marche encore entre deux mondes. D'un côté, la taverne du Cerf et les rumeurs payées en bière. De l'autre, les alliés trop propres qui croient pouvoir l'acheter avec des promesses d'honneur. Kael prend l'or, écoute, et décide seul. Il sait que la fortune favorise les doigts agiles — mais aussi que les ombres mentent rarement, alors que les hommes mentent toujours.

S'il rejoint une compagnie, ce n'est jamais par foi : c'est parce que l'aventure paye mieux que la rue, et parce qu'un groupe offre parfois un bouclier quand la garde frappe trop fort. Surveille toujours les sorties. Compte les lames. Ne laisse personne derrière toi… sauf si rester veut dire mourir.

Cette biographie volontairement longue sert à tester le défilement de la page Histoire : sans ScrollContainer, le texte trop long est coupé ou écrase le reste de la fiche."""

func _ready() -> void:
	var sheet: CharacterSheet = CharacterSheetScene.instantiate()
	add_child(sheet)
	var member := {
		"id": "hero-kael-voleur",
		"name": "Kael",
		"race": "Humain",
		"class": "Voleur",
		"hp": 12,
		"ac": 14,
		"stress": "Méfiant",
		"temperament": "Méfiant · Silencieux · Opportuniste",
		"quirk": "Surveille toujours les sorties.",
		"portrait": "res://assets/portraits/voleur_kael.png",
		"backstory": LONG_STORY,
		"stats": {"str": 10, "dex": 16, "con": 12, "int": 11, "wis": 13, "cha": 9},
		"barks": [
			"Les ombres mentent rarement. Les hommes, toujours.",
			"Un regard de trop… je disparais.",
		],
	}
	sheet.closed.connect(_on_sheet_closed)
	sheet.open(member)
	sheet._showing_story = true
	sheet._show_page()

func _on_sheet_closed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
