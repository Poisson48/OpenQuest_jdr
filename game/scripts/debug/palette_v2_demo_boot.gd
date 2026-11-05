extends Node

## Démo de la palette d'outils v2 (refonte UI). Fenêtre autonome : à gauche la
## palette groupée, à droite un espace « vue 3D » factice, en bas un statut qui
## affiche l'outil cliqué.

const PaletteScript := preload("res://scripts/maps/editor/v2/palette.gd")

var _status: Label

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var split := HSplitContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(split)

	# --- Colonne gauche : palette d'outils ---
	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(220, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left)

	var palette = PaletteScript.new()
	palette.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(palette)
	palette.tool_selected.connect(_on_tool_selected)
	palette.setup(_groups())
	palette.set_active("select")

	# --- Colonne droite : emplacement futur de la vue 3D ---
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(right)

	var placeholder := Label.new()
	placeholder.text = "VUE 3D\n(à venir dans la refonte v2)"
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder.add_theme_font_size_override("font_size", 24)
	placeholder.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6))
	right.add_child(placeholder)

	# --- Barre basse : statut ---
	var status := PanelContainer.new()
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_top = -34
	root.add_child(status)
	_status = Label.new()
	_status.text = "Outil : Sélection"
	_status.add_theme_font_size_override("font_size", 13)
	status.add_child(_status)

func _on_tool_selected(tool_id: String) -> void:
	_status.text = "Outil : %s" % tool_id

func _groups() -> Array:
	return [
		{"title": "Naviguer", "tools": [
			{"id": "select", "icon": "👆", "label": "Sélection", "shortcut": "V"},
			{"id": "pan", "icon": "✋", "label": "Déplacer la vue", "shortcut": "H"},
			{"id": "erase", "icon": "🧹", "label": "Gomme", "shortcut": "E"},
			{"id": "measure", "icon": "📏", "label": "Mesurer", "shortcut": "M"},
		]},
		{"title": "Dessiner", "tools": [
			{"id": "path", "icon": "🛤", "label": "Chemin", "shortcut": "C"},
			{"id": "wall", "icon": "🧱", "label": "Mur", "shortcut": "W"},
			{"id": "zone", "icon": "⭕", "label": "Zone", "shortcut": "Z"},
			{"id": "platform", "icon": "🟫", "label": "Plateforme", "shortcut": ""},
			{"id": "area", "icon": "🏠", "label": "Lieu", "shortcut": "A"},
		]},
		{"title": "Peindre", "tools": [
			{"id": "paint", "icon": "🖌", "label": "Terrain", "shortcut": "B"},
			{"id": "ground", "icon": "🟫", "label": "Sol", "shortcut": "Y"},
			{"id": "relief", "icon": "⛰", "label": "Relief", "shortcut": "U"},
		]},
		{"title": "Décor", "tools": [
			{"id": "mesh", "icon": "🧊", "label": "Objet 3D", "shortcut": "O"},
			{"id": "vegetation", "icon": "🌿", "label": "Végétation", "shortcut": ""},
			{"id": "flowers", "icon": "🌸", "label": "Fleurs", "shortcut": ""},
			{"id": "bushes", "icon": "🌳", "label": "Buissons", "shortcut": ""},
		]},
		{"title": "Ambiance", "tools": [
			{"id": "water", "icon": "💧", "label": "Eau", "shortcut": ""},
			{"id": "light", "icon": "💡", "label": "Lumière", "shortcut": ""},
			{"id": "particles", "icon": "✨", "label": "Particules", "shortcut": ""},
		]},
	]
