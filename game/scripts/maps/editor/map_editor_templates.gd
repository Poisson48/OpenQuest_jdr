extends RefCounted
class_name MapEditorTemplates

## Templates de carte : un groupe d'éléments enregistré avec ses positions
## relatives, replaçable en un clic (avec rotation 0/90/180/270°).
##
## Portage direct du TemplateFileManager de Meownopoly :
## calculateBoundingBox → convertToRelativePositions → écriture JSON,
## puis convertToAbsolutePositions → regenerateUniqueIds au placement.

const TEMPLATES_DIR := "user://map_templates/"
const SUFFIX := "_template.json"

static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(TEMPLATES_DIR)

static func normalize_name(template_name: String) -> String:
	var normalized := template_name.strip_edges().to_lower()
	var allowed := ""
	for i in range(normalized.length()):
		var c := normalized[i]
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-":
			allowed += c
		else:
			allowed += "_"
	allowed = allowed.strip_edges()
	if allowed.is_empty():
		allowed = "template"
	return allowed

static func template_path(template_name: String) -> String:
	return "%s%s%s" % [TEMPLATES_DIR, normalize_name(template_name), SUFFIX]

static func exists(template_name: String) -> bool:
	return FileAccess.file_exists(template_path(template_name))

## Liste les templates disponibles : [{name, file, elementCount, w, h, date}]
static func list_templates() -> Array:
	ensure_dir()
	var out: Array = []
	var dir := DirAccess.open(TEMPLATES_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var data := _read_file(TEMPLATES_DIR + file_name)
			if not data.is_empty():
				var info: Dictionary = data.get("templateInfo", {})
				out.append({
					"name": str(info.get("name", file_name.trim_suffix(SUFFIX))),
					"file": file_name,
					"elementCount": int(info.get("elementCount", (data.get("elements", []) as Array).size())),
					"w": float(info.get("boundingBoxWidth", 1)),
					"h": float(info.get("boundingBoxHeight", 1)),
					"date": str(info.get("creationDate", "")),
				})
		file_name = dir.get_next()
	dir.list_dir_end()
	out.sort_custom(func(a, b): return str(a["name"]).to_lower() < str(b["name"]).to_lower())
	return out

static func bounding_box(elements: Array) -> Rect2:
	if elements.is_empty():
		return Rect2()
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for elem_variant in elements:
		var elem: Dictionary = elem_variant
		var half := Vector2(float(elem.get("w", 1.0)), float(elem.get("h", 1.0))) * 0.5
		var pos := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
		min_p.x = minf(min_p.x, pos.x - half.x)
		min_p.y = minf(min_p.y, pos.y - half.y)
		max_p.x = maxf(max_p.x, pos.x + half.x)
		max_p.y = maxf(max_p.y, pos.y + half.y)
	return Rect2(min_p, max_p - min_p)

## Enregistre une sélection d'éléments comme template réutilisable.
static func save_template(template_name: String, elements: Array) -> bool:
	if template_name.strip_edges().is_empty() or elements.is_empty():
		return false
	ensure_dir()
	var box := bounding_box(elements)
	var payload: Array = []
	for elem_variant in elements:
		var elem: Dictionary = (elem_variant as Dictionary).duplicate(true)
		elem["relativePositionX"] = float(elem.get("x", 0.0)) - box.position.x
		elem["relativePositionY"] = float(elem.get("y", 0.0)) - box.position.y
		elem.erase("id")
		elem.erase("x")
		elem.erase("y")
		payload.append(elem)
	var data := {
		"templateInfo": {
			"name": template_name.strip_edges(),
			"elementCount": payload.size(),
			"boundingBoxWidth": box.size.x,
			"boundingBoxHeight": box.size.y,
			"creationDate": Time.get_datetime_string_from_system(),
		},
		"elements": payload,
	}
	var file := FileAccess.open(template_path(template_name), FileAccess.WRITE)
	if file == null:
		push_warning("Template non enregistré : %s" % template_path(template_name))
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true

static func delete_template(template_name: String) -> bool:
	var path := template_path(template_name)
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK

static func load_template(template_name: String) -> Dictionary:
	return _read_file(template_path(template_name))

static func _read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var raw := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(raw)
	return parsed if parsed is Dictionary else {}

## Prépare les éléments pour un placement à (target_x, target_y).
## `rotation_steps` : 0..3 quarts de tour horaires autour de la bounding box.
static func elements_for_placement(template_name: String, target_x: float, target_y: float, rotation_steps: int = 0) -> Array:
	var data := load_template(template_name)
	if data.is_empty():
		return []
	var info: Dictionary = data.get("templateInfo", {})
	var box := Vector2(float(info.get("boundingBoxWidth", 1.0)), float(info.get("boundingBoxHeight", 1.0)))
	var steps: int = posmod(rotation_steps, 4)
	var out: Array = []
	for elem_variant in data.get("elements", []):
		var elem: Dictionary = (elem_variant as Dictionary).duplicate(true)
		var rel := Vector2(
			float(elem.get("relativePositionX", 0.0)),
			float(elem.get("relativePositionY", 0.0))
		)
		var size := Vector2(float(elem.get("w", 1.0)), float(elem.get("h", 1.0)))
		# Rotation horaire d'un quart de tour : (x, y) → (boxH - y, x).
		var work_box := box
		for _i in range(steps):
			rel = Vector2(work_box.y - rel.y, rel.x)
			size = Vector2(size.y, size.x)
			work_box = Vector2(work_box.y, work_box.x)
		elem.erase("relativePositionX")
		elem.erase("relativePositionY")
		elem["x"] = target_x + rel.x
		elem["y"] = target_y + rel.y
		elem["w"] = size.x
		elem["h"] = size.y
		var display: Dictionary = elem.get("display", {}) if elem.get("display") is Dictionary else {}
		display["rotation"] = fmod(float(display.get("rotation", 0.0)) + 90.0 * float(steps), 360.0)
		elem["display"] = display
		elem["id"] = MapData.generate_id(str(elem.get("kind", "elem")).substr(0, 3))
		elem["links"] = {"next": [], "prev": []}
		out.append(elem)
	return out

## Dimensions de l'empreinte au sol d'un template (après rotation).
static func footprint(template_name: String, rotation_steps: int = 0) -> Vector2:
	var data := load_template(template_name)
	if data.is_empty():
		return Vector2.ONE
	var info: Dictionary = data.get("templateInfo", {})
	var size := Vector2(float(info.get("boundingBoxWidth", 1.0)), float(info.get("boundingBoxHeight", 1.0)))
	if posmod(rotation_steps, 4) % 2 == 1:
		size = Vector2(size.y, size.x)
	return size
