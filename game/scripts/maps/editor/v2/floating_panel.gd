class_name MapEditorFloatingPanel
extends PopupPanel

## Panneau flottant autonome (refonte UI v2) : petite popup composée d'une
## barre de titre (libellé + bouton fermer) et d'un conteneur VBox destiné au
## contenu fourni par l'appelant. 100 % autonome : aucun autoload, aucune
## scène externe, toute l'interface est construite en code.

## Émis lorsque le panneau est fermé (bouton fermer, fermeture de fenêtre
## ou Échap).
signal dismissed

const _TITLE_LABEL_NAME := "TitleLabel"
const _CLOSE_BUTTON_NAME := "CloseButton"
const _CONTENT_HOST_NAME := "ContentHost"

var _title_label: Label = null
var _close_button: Button = null
var _content_host: VBoxContainer = null
var _is_open := false


func _init() -> void:
	_build_chrome()
	popup_hide.connect(_on_popup_hide)
	close_requested.connect(_on_close_requested)


## Configure le panneau : titre de la barre + nœud de contenu.
## Le contenu est détaché de son ancien parent puis accueilli dans le
## conteneur VBox du panneau (tout contenu précédent est retiré).
func setup(title: String, content: Node) -> void:
	_title_label.text = title
	for child in _content_host.get_children():
		_content_host.remove_child(child)
		child.queue_free()
	if content != null:
		if content.get_parent() != null:
			content.get_parent().remove_child(content)
		_content_host.add_child(content)


## Ouvre le panneau à la position globale donnée (coordonnées écran).
func open_at(global_pos: Vector2) -> void:
	_is_open = true
	position = Vector2i(global_pos.round())
	reset_size()
	popup()


# ---------------------------------------------------------------------------
# Construction de l'interface
# ---------------------------------------------------------------------------

func _build_chrome() -> void:
	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	var title_bar := HBoxContainer.new()
	title_bar.name = "TitleBar"
	title_bar.add_theme_constant_override("separation", 8)
	root.add_child(title_bar)

	_title_label = Label.new()
	_title_label.name = _TITLE_LABEL_NAME
	_title_label.text = ""
	_title_label.clip_text = true
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(_title_label)

	_close_button = Button.new()
	_close_button.name = _CLOSE_BUTTON_NAME
	_close_button.text = "X"
	_close_button.tooltip_text = "Fermer"
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.pressed.connect(_on_close_pressed)
	title_bar.add_child(_close_button)

	root.add_child(HSeparator.new())

	_content_host = VBoxContainer.new()
	_content_host.name = _CONTENT_HOST_NAME
	_content_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_host.add_theme_constant_override("separation", 6)
	root.add_child(_content_host)


# ---------------------------------------------------------------------------
# Fermeture
# ---------------------------------------------------------------------------

## Bouton fermer de la barre de titre.
func _on_close_pressed() -> void:
	_dismiss()


## Fermeture demandée par la fenêtre (bouton système / Échap).
func _on_close_requested() -> void:
	_dismiss()


## La popup s'est cachée (y compris via Échap) : notifier si ce n'est pas déjà fait.
func _on_popup_hide() -> void:
	if _is_open:
		_dismiss()


func _dismiss() -> void:
	if not _is_open:
		return
	_is_open = false
	dismissed.emit()
	hide()
