extends Control
class_name MapAreasOverlay

## Pas de dessin en session : les lieux sont implicites (plan illustré).
## Le feedback passe par le curseur (moteur) et le bandeau d'aide (MapPanel).

var engine: Control = null
var map_data: Dictionary = {}
var hovered_id: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func configure(p_engine: Control, p_map: Dictionary) -> void:
	engine = p_engine
	map_data = p_map
	hovered_id = ""
	queue_redraw()

func set_hovered(area_id: String) -> void:
	hovered_id = area_id
	# Pas de redraw : overlay volontairement vide.
