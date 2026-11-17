extends Control

## Fond de page de l'éditeur de scénario (mix Atelier) : aplat très sombre +
## trame de points façon plan de travail, sur TOUTE la fenêtre.
##
## Le canevas du graphe est rendu transparent (pas de panneau ni de grille
## GraphEdit) pour laisser voir cette trame : c'est le « côté ouvert » de la
## maquette 01-atelier. Aucun dégradé.

const BASE_COLOR := Color("0a0910")
const DOT_COLOR := Color(0.66, 0.61, 0.53, 0.16)
const DOT_RADIUS := 1.15
const DOT_STEP := 20.0
const DOT_OFFSET := Vector2(10.0, 10.0)

var _dot_step: float = DOT_STEP


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func set_dot_step(step: float) -> void:
	_dot_step = maxf(step, 6.0)
	queue_redraw()


func _draw() -> void:
	# Aplat : le fond doit être uniforme (pas de halo ni de dégradé).
	draw_rect(Rect2(Vector2.ZERO, size), BASE_COLOR)
	# Trame de points, alignée sur une demi-pas pour un rendu régulier.
	var step := _dot_step
	var y := DOT_OFFSET.y
	while y < size.y:
		var x := DOT_OFFSET.x
		while x < size.x:
			draw_circle(Vector2(x, y), DOT_RADIUS, DOT_COLOR)
			x += step
		y += step
