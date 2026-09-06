extends RefCounted
class_name SessionLayout

## Seul propriétaire de la géométrie de la session.
##
## Les panneaux ne connaissent que leur contenu ; largeur des docks, marges,
## visibilité de l'en-tête et bascule immersive sont décidées ici. C'est ce qui
## rend la restauration symétrique : `apply_preset(PRESET_GM)` reconstruit
## exactement l'état d'avant l'immersion, sans qu'aucun panneau ne se souvienne
## de quoi que ce soit.

const PRESET_GM := "gm"
const PRESET_IMMERSIVE := "immersive"

const LEFT_MIN := 232
const RIGHT_MIN := 268
const MAP_MIN := 380

## Largeurs cibles par palier de fenêtre : (largeur mini, dock gauche, dock droit).
const BREAKPOINTS := [
	{ "from": 1600, "left": 330, "right": 410 },
	{ "from": 1360, "left": 300, "right": 372 },
	{ "from": 1120, "left": 268, "right": 330 },
	{ "from": 0, "left": 240, "right": 290 },
]

## En dessous, le dock gauche se replie automatiquement pour laisser vivre la carte.
const AUTO_COLLAPSE_WIDTH := 1040

var preset: String = PRESET_GM
var left_visible_pref: bool = true

var _root: Control = null
var _margins: MarginContainer = null
var _header: Control = null
var _outer: HSplitContainer = null
var _inner: HSplitContainer = null
var _left: Control = null
var _center: Control = null
var _right: Control = null

var _left_width: float = 0.0
var _right_width: float = 0.0
var _user_sized: bool = false

func configure(root: Control, margins: MarginContainer, header: Control,
		outer: HSplitContainer, inner: HSplitContainer,
		left: Control, center: Control, right: Control) -> void:
	_root = root
	_margins = margins
	_header = header
	_outer = outer
	_inner = inner
	_left = left
	_center = center
	_right = right

	_left.custom_minimum_size.x = LEFT_MIN
	_right.custom_minimum_size.x = RIGHT_MIN
	_center.custom_minimum_size.x = MAP_MIN
	for panel in [_left, _center, _right]:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outer.dragged.connect(_on_split_dragged)
	_inner.dragged.connect(_on_split_dragged)
	_root.resized.connect(relayout)
	# Le premier calcul tombe avant que les conteneurs ne connaissent leur
	# taille : on recalcule à chaque fois qu'elle change, jusqu'à convergence.
	_outer.resized.connect(relayout)
	_inner.resized.connect(relayout)

func apply_preset(next_preset: String) -> void:
	preset = next_preset
	var immersive := preset == PRESET_IMMERSIVE
	_header.visible = not immersive
	_left.visible = not immersive and _left_allowed()
	_right.visible = not immersive
	var margin := 0 if immersive else UiLayout.SPACING_PANEL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_margins.add_theme_constant_override(side, margin)
	relayout()

func set_left_dock_visible(on: bool) -> void:
	left_visible_pref = on
	if preset != PRESET_IMMERSIVE:
		_left.visible = _left_allowed()
		relayout()

func is_immersive() -> bool:
	return preset == PRESET_IMMERSIVE

## Largeurs réellement appliquées — utilisé par les tests de mise en page.
func describe() -> Dictionary:
	return {
		"preset": preset,
		"viewport": _root.size if _root else Vector2.ZERO,
		"header_visible": _header.visible if _header else false,
		"left_visible": _left.visible if _left else false,
		"right_visible": _right.visible if _right else false,
		"left_width": _left.size.x if _left else 0.0,
		"center_width": _center.size.x if _center else 0.0,
		"right_width": _right.size.x if _right else 0.0,
		"center_height": _center.size.y if _center else 0.0,
	}

func relayout() -> void:
	if _root == null or _outer == null:
		return
	if preset == PRESET_IMMERSIVE:
		return
	var available := _outer.size.x
	if available < 32.0:
		# Premier layout : la taille n'est pas encore connue, on repasse plus tard.
		call_deferred("relayout")
		return
	var targets := _target_widths(available)
	_left_width = targets.x
	_right_width = targets.y

	var sep := float(_outer.get_theme_constant("separation"))
	if _left.visible:
		_set_offset(_outer, int(round(_left_width - (available - sep) * 0.5)))
		_apply_inner_offset(available - sep - _left_width)
	else:
		_set_offset(_outer, 0)
		_apply_inner_offset(available)

func _apply_inner_offset(inner_width: float) -> void:
	var sep := float(_inner.get_theme_constant("separation"))
	_set_offset(_inner, int(round((inner_width - sep) * 0.5 - _right_width)))

## N'écrit que si la valeur change : `split_offset` renvoie un signal de
## redimensionnement, et on serait sinon rappelé en boucle.
static func _set_offset(split: SplitContainer, offset: int) -> void:
	if split.split_offset != offset:
		split.split_offset = offset

func _left_allowed() -> bool:
	if not left_visible_pref:
		return false
	var width := _root.size.x if _root else 0.0
	return width >= AUTO_COLLAPSE_WIDTH

## Cible (gauche, droite) pour la largeur disponible, en gardant la carte au large.
func _target_widths(available: float) -> Vector2:
	var left := 0.0
	var right := 0.0
	if _user_sized:
		left = _left_width
		right = _right_width
	else:
		var window_width := _root.size.x if _root else available
		for step in BREAKPOINTS:
			if window_width >= float(step["from"]):
				left = float(step["left"])
				right = float(step["right"])
				break
	if not _left.visible:
		left = 0.0
	left = maxf(left, LEFT_MIN if _left.visible else 0.0)
	right = maxf(right, RIGHT_MIN)

	# La carte reste prioritaire : on rogne les docks avant de la rétrécir.
	var overflow := (left + right + MAP_MIN) - available
	if overflow > 0.0:
		var right_room := right - RIGHT_MIN
		var taken := minf(overflow, right_room)
		right -= taken
		overflow -= taken
	if overflow > 0.0 and _left.visible:
		var left_room := left - LEFT_MIN
		left -= minf(overflow, left_room)
	return Vector2(left, right)

func _on_split_dragged(_offset: int) -> void:
	# Le MJ a redimensionné à la main : on retient ses largeurs jusqu'à la fin
	# de la session plutôt que de les écraser au prochain redimensionnement.
	if preset == PRESET_IMMERSIVE:
		return
	_user_sized = true
	_left_width = _left.size.x if _left.visible else 0.0
	_right_width = _right.size.x
