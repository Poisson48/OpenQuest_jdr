extends PanelContainer
class_name MapNavigatorPanel

## Barre de navigation carte : où l'on est (onglets, fil d'Ariane) et à quelle
## échelle on la regarde.
## Structure dans `scenes/session/panels/map_navigator.tscn`.

signal map_selected(map_id: String)
signal exit_area_requested
signal exit_to_world_requested
signal zoom_in_requested
signal zoom_out_requested
signal fit_requested

## Taille de case de référence d'une table virtuelle : sert à traduire
## l'échelle mesurée en pourcentage compréhensible.
const REFERENCE_CELL_PX := 64.0

@onready var _back: Button = %BtnBack
@onready var _tabs: HBoxContainer = %TabRow
@onready var _crumb: Label = %LblCrumb
@onready var _scale: Label = %LblScale

var _back_action: String = ""

func _ready() -> void:
	_back.pressed.connect(_on_back_pressed)
	%BtnZoomOut.pressed.connect(func(): zoom_out_requested.emit())
	%BtnZoomIn.pressed.connect(func(): zoom_in_requested.emit())
	%BtnFit.pressed.connect(func(): fit_requested.emit())

func set_tabs(maps: Array, active_id: String) -> void:
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	if maps.size() <= 1:
		return
	for map_variant in maps:
		var map_entry: Dictionary = map_variant
		var map_id := str(map_entry.get("id", ""))
		var btn := SessionStyle.tool_button(
			str(map_entry.get("title", map_id)), "Basculer sur cette carte"
		)
		btn.set_pressed_no_signal(map_id == active_id)
		btn.pressed.connect(func(): map_selected.emit(map_id))
		_tabs.add_child(btn)

## `nav` provient de `GameData.get_session_display_map().navContext`.
func set_breadcrumb(nav: Dictionary) -> void:
	_back_action = str(nav.get("mode", ""))
	match _back_action:
		"area":
			_back.visible = true
			_crumb.text = _area_crumb(nav)
		"local":
			_back.visible = true
			_crumb.text = "%s › %s" % [
				nav.get("worldMap", {}).get("title", "Monde"),
				nav.get("localMap", {}).get("title", "Scène"),
			]
		_:
			_back.visible = false
			_crumb.text = str(nav.get("title", ""))
	_crumb.tooltip_text = _crumb.text

## Affiche l'échelle mesurée à l'écran plutôt que le facteur interne du moteur,
## qui vaut 1 dès qu'on recadre et ne veut donc rien dire.
func set_effective_scale(pixels_per_cell: float) -> void:
	if pixels_per_cell <= 0.0:
		_scale.text = "—"
		_scale.tooltip_text = "Échelle inconnue"
		return
	_scale.text = "%d %%" % int(round(pixels_per_cell / REFERENCE_CELL_PX * 100.0))
	_scale.tooltip_text = "%d pixels par case (référence %d px) · molette pour zoomer" % [
		int(round(pixels_per_cell)), int(REFERENCE_CELL_PX)
	]

func _on_back_pressed() -> void:
	if _back_action == "area":
		exit_area_requested.emit()
	elif _back_action == "local":
		exit_to_world_requested.emit()

func _area_crumb(nav: Dictionary) -> String:
	var parts: PackedStringArray = []
	var root: Dictionary = nav.get("rootMap", {})
	if not root.is_empty():
		parts.append(str(root.get("title", "Carte")))
	for entry_variant in nav.get("areaStack", []):
		if entry_variant is Dictionary:
			parts.append(str((entry_variant as Dictionary).get("label", "Lieu")))
	return " › ".join(parts)
