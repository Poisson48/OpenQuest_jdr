extends Node2D
class_name MapElevationLayer

## Calques d'élévation — images PNG par-dessus le fond + plateformes teintées.

var _sprites: Array[Sprite2D] = []
var _platform_zones: Array = []

func configure(map_data: Dictionary, grid_size: int) -> void:
	for child in get_children():
		child.queue_free()
	_sprites.clear()
	_platform_zones.clear()

	var layers: Array = map_data.get("elevationLayers", [])
	if layers is not Array:
		return

	for layer_def in layers:
		if not layer_def is Dictionary:
			continue
		var path: String = str(layer_def.get("image", "")).strip_edges()
		if not path.is_empty():
			var tex := MapData.load_background_texture({"backgroundImage": path})
			if tex:
				var spr := Sprite2D.new()
				spr.texture = tex
				spr.centered = false
				spr.modulate.a = float(layer_def.get("opacity", 0.92))
				var off := layer_def.get("offset", {"x": 0, "y": 0})
				if off is Dictionary:
					spr.position = Vector2(float(off.get("x", 0)), float(off.get("y", 0)))
				add_child(spr)
				_sprites.append(spr)
		elif layer_def.get("platform") is Dictionary:
			_platform_zones.append({
				"def": layer_def,
				"grid_size": grid_size,
			})

	if not _platform_zones.is_empty():
		set_process(true)
		queue_redraw()
	else:
		set_process(false)

func _draw() -> void:
	for entry in _platform_zones:
		var def: Dictionary = entry["def"]
		var gs: int = entry["grid_size"]
		var plat: Dictionary = def.get("platform", {})
		var x := float(plat.get("x", 0)) * gs
		var y := float(plat.get("y", 0)) * gs
		var w := float(plat.get("w", 2)) * gs
		var h := float(plat.get("h", 2)) * gs
		var elev := float(def.get("elevation", 1))
		var col := Color.html(str(def.get("tint", "#8a7a60")))
		col.a = float(def.get("opacity", 0.35))
		var rect := Rect2(x, y, w, h)
		# Ombre de bord (plateforme surélevée)
		var shadow_off := Vector2(3.0 + elev * 2.0, 4.0 + elev * 2.0)
		draw_rect(rect.position + shadow_off, rect.size, Color(0, 0, 0, 0.22))
		draw_rect(rect, col)
		draw_rect(rect, col.lightened(0.15), false, 2.0)
