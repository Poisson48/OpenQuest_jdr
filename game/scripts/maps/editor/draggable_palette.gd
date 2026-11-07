class_name MapEditorDraggablePalette
extends PanelContainer

## Palette flottante déplaçable façon Blender/GIMP : barre de titre que l'on
## glisse à la souris (LMB maintenu) + bouton fermer. Le contenu est fourni
## par l'appelant. Tant qu'elle n'est pas déplacée, la palette suit son
## ancrage de bord (droite/bas/haut) ; le premier glissage la détache.

signal close_pressed

var _title_label: Label = null
var _dragging := false
var _resizing := false
var _drag_offset := Vector2.ZERO

## Habille le panneau : titre + contenu (détaché de son ancien parent).
func setup(title: String, content: Control, icon: String = "") -> void:
	var stack := VBoxContainer.new()
	stack.name = "PaletteStack"
	stack.add_theme_constant_override("separation", 2)
	var bar := HBoxContainer.new()
	bar.name = "TitleBar"
	bar.add_theme_constant_override("separation", 6)
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = (icon + " " if icon != "" else "") + title
	_title_label.clip_text = true
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_title_label)
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.text = "✕"
	close_btn.tooltip_text = "Fermer la palette"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(24, 0)
	close_btn.pressed.connect(func(): close_pressed.emit())
	bar.add_child(close_btn)
	# La barre entière sert de poignée de déplacement.
	bar.gui_input.connect(_on_title_input)
	stack.add_child(bar)
	stack.add_child(HSeparator.new())
	if content != null:
		if content.get_parent() != null:
			content.get_parent().remove_child(content)
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.add_child(content)
	# Poignée de redimensionnement (coin bas-droit), façon fenêtre flottante.
	var grip_row := HBoxContainer.new()
	grip_row.name = "GripRow"
	grip_row.alignment = BoxContainer.ALIGNMENT_END
	grip_row.mouse_filter = Control.MOUSE_FILTER_PASS
	var grip := Label.new()
	grip.name = "ResizeGrip"
	grip.text = "◢"
	grip.tooltip_text = "Glisser pour redimensionner"
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	grip.mouse_filter = Control.MOUSE_FILTER_PASS
	grip.gui_input.connect(_on_grip_input)
	grip_row.add_child(grip)
	stack.add_child(grip_row)
	add_child(stack)

## Glisser la palette par sa barre de titre (le déplacement vient du mouvement
## relatif de la souris — robuste, y compris hors écran réel).
func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (event as InputEventMouseButton).pressed:
			_dragging = true
			_detach_from_anchors()
		else:
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		global_position += (event as InputEventMouseMotion).relative
		accept_event()

## Redimensionner la palette par sa poignée de coin (bas-droit).
func _on_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (event as InputEventMouseButton).pressed:
			_resizing = true
			_detach_from_anchors()
		else:
			_resizing = false
		accept_event()
	elif event is InputEventMouseMotion and _resizing:
		var m := event as InputEventMouseMotion
		size = Vector2(
			maxf(size.x + m.relative.x, 220.0),
			maxf(size.y + m.relative.y, 120.0))
		accept_event()

## Au premier glissage, la palette quitte son ancrage de bord pour devenir
## librement positionnable (les ancres ancreraient sa taille à la fenêtre).
func _detach_from_anchors() -> void:
	if anchor_left == 0.0 and anchor_top == 0.0 \
			and anchor_right == 0.0 and anchor_bottom == 0.0:
		return
	var gp := global_position
	var sz := size
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = sz.x
	offset_bottom = sz.y
	global_position = gp
