extends Node

## POC « Table de taverne » — plateau virtuel : la carte est **posée sur une
## table 3D**, entourée de chaises dans une salle de taverne.
##
## Bascule de point de vue : on s'assoit à une place autour de la table —
## celle d'un joueur ou celle du MJ (vue plus haute, tout le plateau).
##
## Lancer (Windows) :
##   .\scripts\play-godot.ps1 res://scenes/debug/table_poc_boot.tscn
##
## Commandes :
##   Espace   = point de vue suivant (Kael → Thorin → Aria → MJ)
##   1 .. 4   = point de vue direct (Kael, Thorin, Aria, MJ)
##   F        = cadrer toute la table
##   Molette  = zoom (s'approcher du plateau)
##   Glisser  = tourner autour de la table (inclinaison incluse)
##   Échap    = quitter

const MAP_PNG := "res://assets/maps/valbois_table_map.png"

## Places autour de la table : 0=Sud, 1=Est, 2=Nord, 3=Ouest.
## Le MJ est au Nord — face aux joueurs, vue légèrement plus haute.
const SEATS := [
	{"seat": 0, "label": "Kael — joueur", "role": "Joueur", "elev": 32.0,
		"color": Color(0.82, 0.24, 0.18)},
	{"seat": 1, "label": "Thorin — joueur", "role": "Joueur", "elev": 32.0,
		"color": Color(0.90, 0.74, 0.20)},
	{"seat": 3, "label": "Aria — joueuse", "role": "Joueuse", "elev": 32.0,
		"color": Color(0.24, 0.68, 0.80)},
	{"seat": 2, "label": "MJ — maître du jeu", "role": "Maître du jeu", "elev": 44.0,
		"color": Color(0.90, 0.89, 0.84)},
]

var _engine: Control
var _banner: Label
var _hint: Label
var _toast: Label
var _selector: HBoxContainer
var _md: Node
var _pov := 0
var _dice_type := 6

func _ready() -> void:
	_md = get_tree().root.get_node("MapData")
	var demo := build_demo(_md)
	if demo.is_empty():
		push_error("[TABLE POC] Impossible de construire la carte démo.")
		get_tree().quit(1)
		return

	# Pas de DisplayServer.window_set_size ici : sous forte mise à l'échelle
	# DPI il désynchronise la surface fenêtre et l'espace de contenu (recadrage
	# du rendu). On garde la taille de fenêtre configurée du projet.
	DisplayServer.window_set_title("POC — Table de taverne (OpenQuest JDR)")

	var EngineScript: GDScript = load("res://scripts/maps/complex_map_engine_3d.gd") as GDScript
	_engine = EngineScript.new()
	_engine.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_engine)
	_engine.configure(
		demo["map"], demo["tokens"], demo["party"], [], [], [],
		false, true, {"mode": "select"}, {}, ""
	)
	_engine.set_table_view(true)

	# Libellés des places (index 0..3 = Sud, Est, Nord, Ouest).
	var labels := ["", "", "", ""]
	for entry: Dictionary in SEATS:
		labels[int(entry["seat"])] = str(entry["label"])
	_engine.set_table_seat_labels(labels)

	_banner = _make_label(28, Color(1.0, 0.92, 0.72))
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(0, 18)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_banner)

	_hint = _make_label(15, Color(0.95, 0.88, 0.72))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.position = Vector2(16, -84)
	add_child(_hint)

	_toast = _make_label(20, Color(1.0, 0.95, 0.8))
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.position = Vector2(0, -36)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_toast)

	_build_dice_selector()

	if _engine.has_signal("table_dice_result"):
		_engine.table_dice_result.connect(_on_dice_result)

	_apply_pov()
	print("[TABLE POC] Vue table active — ", _engine.table_seat_label())

## Choix du type de dé à lancer : d4, d6 (x2), d8, d10, d12, d20, d100 (2d10).
func _build_dice_selector() -> void:
	_selector = HBoxContainer.new()
	_selector.mouse_filter = Control.MOUSE_FILTER_PASS
	_selector.anchor_left = 1.0
	_selector.anchor_top = 0.0
	_selector.offset_left = -580.0
	_selector.offset_top = 60.0
	_selector.offset_right = -16.0
	_selector.offset_bottom = 96.0
	_selector.add_theme_constant_override("separation", 6)
	add_child(_selector)
	var grp := ButtonGroup.new()
	for t: int in [4, 6, 8, 10, 12, 20, 100]:
		var btn := Button.new()
		btn.text = "d100" if t == 100 else "d%d" % t
		btn.tooltip_text = "Un dé par clic droit sur la table" \
			if t != 100 else "Vrai dé à 100 faces (1-100), un seul dé par clic"
		btn.toggle_mode = true
		btn.button_group = grp
		btn.button_pressed = t == _dice_type
		btn.add_theme_font_size_override("font_size", 15)
		btn.pressed.connect(_on_dice_type_pressed.bind(t))
		_selector.add_child(btn)

func _on_dice_type_pressed(t: int) -> void:
	_dice_type = t
	_engine.set_table_dice_sides(t)
	_toast.text = "🎲 Type de dé : %s" % ("d100 (1-100)" if t == 100 else "d%d" % t)
	var stamp := Time.get_ticks_msec()
	_clear_toast_later(stamp)

func _make_label(font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.add_theme_font_size_override("font_size", font_size)
	return lbl

## Place le joueur à sa place (chaise cachée, vue MJ plus haute, dés teintés).
func _apply_pov() -> void:
	var entry: Dictionary = SEATS[_pov]
	_engine.set_table_seat(int(entry["seat"]))
	_engine.set_table_elevation(float(entry["elev"]))
	_engine.set_table_dice_color(entry["color"])
	_banner.text = "👁  Point de vue : %s" % str(entry["label"])
	_hint.text = "[1] Kael · [2] Thorin · [3] Aria · [4] MJ   |   Dé : boutons d4…d100 · clic droit MAINTENU : le dé apparaît et suit la souris → le lâcher le lance avec la vitesse du geste ! · glisser : tourner · Shift+glisser : déplacer la caméra · molette : zoom · F : cadrer · Échap : quitter"

## Règle maison : un dé **compte s'il finit droit** (posé sur une face) —
## même s'il tombe par terre ! De travers (arête/pointe) : relance.
func _on_dice_result(faces: Array, total: int, valid: bool) -> void:
	var parts := PackedStringArray()
	for f_variant in faces:
		parts.append(str(int(f_variant)))
	var who := str(SEATS[_pov]["label"])
	var desc := ""
	if _dice_type == 100:
		desc = "d100 : %d" % total
	elif faces.size() <= 1:
		desc = "d%d : %d" % [_dice_type, total]
	else:
		desc = "%dd%d : %s = %d" % [faces.size(), _dice_type, " + ".join(parts), total]
	if valid:
		_toast.text = "🎲 %s lance %s — il finit droit : ça compte !" % [who, desc]
	else:
		_toast.text = "🎲 %s lance %s — ❌ tombé de travers : ça ne compte pas, relance !" % [who, desc]
	var stamp := Time.get_ticks_msec()
	_clear_toast_later(stamp)

func _clear_toast_later(stamp: int) -> void:
	await get_tree().create_timer(4.5).timeout
	if Time.get_ticks_msec() - stamp >= 4400:
		_toast.text = ""

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed:
		return
	match key.keycode:
		KEY_SPACE:
			_pov = wrapi(_pov + 1, 0, SEATS.size())
		KEY_D:
			# Lancer de secours au clavier : devant soi (le clic droit lance
			# exactement où l'on veut), avec le type de dé sélectionné.
			var entry: Dictionary = SEATS[_pov]
			var seat: int = int(entry["seat"])
			var yaw := deg_to_rad(float(seat) * 90.0)
			var e = _engine
			var target: Vector3 = e._table_target_point()
			var at := target + Vector3(sin(yaw), 0.0, cos(yaw)) * 1.5
			e.roll_table_dice_at(at)
			return
		KEY_1:
			_pov = 0
		KEY_2:
			_pov = 1
		KEY_3:
			_pov = 2
		KEY_4:
			_pov = 3
		KEY_F:
			_engine.reset_zoom()
			_engine.set_table_elevation(float(SEATS[_pov]["elev"]))
			return
		KEY_ESCAPE:
			get_tree().quit(0)
		_:
			return
	_apply_pov()
	get_viewport().set_input_as_handled()

## Carte + tokens de démonstration (statique : réutilisé par les tests).
static func build_demo(md: Node) -> Dictionary:
	if md == null:
		return {}
	# `res://` lu directement par MapData (_load_rgba_image) : pas de copie
	# user://, donc testable même quand le profil utilisateur est protégé.
	if not FileAccess.file_exists(MAP_PNG) \
		and not FileAccess.file_exists(ProjectSettings.globalize_path(MAP_PNG)):
		return {}
	var cells: Vector2i = md.suggest_cells_from_image(MAP_PNG, 70)
	if cells.x < 1 or cells.y < 1:
		cells = Vector2i(22, 15)
	var map: Dictionary = md.create_complex_map(
		"POC — Table de taverne", "general", "local", cells.x, cells.y
	)
	var map_id := str(map.get("id", ""))
	if map_id.is_empty():
		return {}
	map["backgroundImage"] = MAP_PNG
	map["fogEnabled"] = false
	md.update_map(map)
	map = md.get_by_id(map_id)

	var tokens := [
		{
			"id": "kael", "name": "Kael", "label": "Kael",
			"x": cells.x * 0.42, "y": cells.y * 0.55,
			"image": "res://assets/portraits/voleur_kael.png",
			"kind": "member", "memberId": "hero-1", "scale": 1.0,
		},
		{
			"id": "thorin", "name": "Thorin", "label": "Thorin",
			"x": cells.x * 0.55, "y": cells.y * 0.48,
			"image": "res://assets/portraits/thorin.png",
			"kind": "member", "memberId": "hero-2", "scale": 1.0,
		},
		{
			"id": "aria", "name": "Aria", "label": "Aria",
			"x": cells.x * 0.48, "y": cells.y * 0.62,
			"image": "res://assets/portraits/aria_sombrelame.png",
			"kind": "member", "memberId": "hero-3", "scale": 1.0,
		},
	]
	var party := [
		{"id": "hero-1", "name": "Kael", "portrait": "res://assets/portraits/voleur_kael.png"},
		{"id": "hero-2", "name": "Thorin", "portrait": "res://assets/portraits/thorin.png"},
		{"id": "hero-3", "name": "Aria", "portrait": "res://assets/portraits/aria_sombrelame.png"},
	]
	return {"map": map, "tokens": tokens, "party": party, "cells": cells}
