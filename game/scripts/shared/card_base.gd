extends PanelContainer
class_name CardBase

## Carte générique du hub : en-tête (titre + badge), méta, corps libre, actions.
##
## Les quatre cartes (personnage, bot, scénario, carte) partageaient la même
## structure recopiée quatre fois. Elles instancient désormais cette scène et
## se contentent de remplir les zones via l'API ci-dessous.
##
## Le menu « ⋯ » est fourni : `add_overflow(["Libellé", ...])` crée un
## MenuButton et émet `overflow_selected(id)`.

signal overflow_selected(id: int)

@onready var _title: Label = %Title
@onready var _badge: Label = %Badge
@onready var _meta: Label = %Meta
@onready var _body: VBoxContainer = %Body
@onready var _actions: HBoxContainer = %Actions

## Texte du titre de la carte.
func set_title(text: String) -> void:
	_title.text = text

## Badge d'état (mode, rareté…). Masqué si `text` est vide.
func set_badge(text: String, color: Color = Color(0, 0, 0, 0)) -> void:
	_badge.text = text
	_badge.visible = not text.is_empty()
	if color.a > 0.0:
		_badge.add_theme_color_override("font_color", color)
	else:
		_badge.remove_theme_color_override("font_color")

## Ligne de métadonnées sous le titre. Masquée si vide.
## (nommé ainsi : `set_meta` est réservé par Object)
func set_meta_line(text: String) -> void:
	_meta.text = text
	_meta.visible = not text.is_empty()

## Ajoute une ligne de texte au corps de la carte.
## `variation` : "" (défaut), "CaptionLabel", "MutedLabel", "SectionLabel"…
func add_body(text: String, variation: String = "") -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not variation.is_empty():
		lbl.theme_type_variation = variation
	_body.add_child(lbl)
	return lbl

## Ajoute un contrôle quelconque au corps.
func add_body_control(control: Control) -> void:
	_body.add_child(control)

## Ajoute un bouton d'action (aligné à droite).
## `variation` : "" (défaut), "AccentButton", "DangerButton", "ToolButton"…
func add_action(text: String, variation: String = "", expand: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	if not variation.is_empty():
		btn.theme_type_variation = variation
	if expand:
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.add_child(btn)
	return btn

## Ajoute un bouton d'action déjà construit (l'appelant garde la main).
func add_action_control(button: Button, expand: bool = false) -> Button:
	if expand:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_actions.add_child(button)
	return button

## Ajoute le menu « ⋯ » avec les entrées fournies (l'id est l'index).
func add_overflow(labels: Array) -> MenuButton:
	var menu := MenuButton.new()
	menu.text = "⋯"
	menu.tooltip_text = "Plus d'actions"
	menu.flat = false
	menu.custom_minimum_size = Vector2(52, 0)
	var popup := menu.get_popup()
	for i in labels.size():
		popup.add_item(str(labels[i]), i)
	popup.id_pressed.connect(func(id: int): overflow_selected.emit(id))
	_actions.add_child(menu)
	return menu

## Active / désactive une entrée du menu « ⋯ » par son index.
func set_overflow_enabled(menu: MenuButton, index: int, enabled: bool) -> void:
	var popup := menu.get_popup()
	if index >= 0 and index < popup.item_count:
		popup.set_item_disabled(index, not enabled)

## Masque entièrement la barre d'actions (cartes sans action).
func hide_actions() -> void:
	_actions.visible = false
