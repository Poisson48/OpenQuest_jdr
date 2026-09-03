extends RefCounted
class_name MapEditDocument

## Modèle d'édition de carte : éléments unifiés, historique undo/redo par deltas,
## transactions, sélection, presse-papiers, calques.
##
## Inspiré de l'architecture éditeur Meownopoly (EditDelta / Map::pushDelta /
## shadow copy ItemSnapable), transposée en GDScript pur : au lieu de snapshots
## complets, chaque action pousse un delta { before, after } et les deltas d'une
## même transaction sont annulés/refaits en une seule étape.

signal changed(reason: String)
signal selection_changed(ids: Array)
signal history_changed()
signal dirty_changed(is_dirty: bool)

const MAX_HISTORY := 120

# --- Types de delta ---------------------------------------------------------
const D_ELEM_ADD := "elem_add"
const D_ELEM_DEL := "elem_del"
const D_ELEM_MOD := "elem_mod"
const D_META := "meta"
const D_TILES := "tiles"
const D_FOG := "fog"
const D_ORDER := "order"

# --- Types d'éléments -------------------------------------------------------
const KIND_TOKEN := "token"
const KIND_MARKER := "marker"
const KIND_EFFECT := "effect"
const KIND_ZONE := "zone"
const KIND_PLATFORM := "platform"
const KIND_OVERLAY := "overlay"
const KIND_WALL := "wall"
const KIND_NOTE := "note"
const KIND_LIGHT := "light"
const KIND_LINK := "link"
const KIND_AREA := "area"
const KIND_PROP := "prop"

const ALL_KINDS := [
	KIND_TOKEN, KIND_MARKER, KIND_EFFECT, KIND_ZONE, KIND_PLATFORM,
	KIND_OVERLAY, KIND_WALL, KIND_NOTE, KIND_LIGHT, KIND_LINK, KIND_AREA,
	KIND_PROP,
]

const KIND_ICONS := {
	KIND_TOKEN: "🧍", KIND_MARKER: "📍", KIND_EFFECT: "✨", KIND_ZONE: "⭕",
	KIND_PLATFORM: "🟫", KIND_OVERLAY: "🖼", KIND_WALL: "🧱", KIND_NOTE: "📝",
	KIND_LIGHT: "💡", KIND_LINK: "🌀", KIND_AREA: "🏠", KIND_PROP: "🏚",
}

const KIND_LABELS := {
	KIND_TOKEN: "Token", KIND_MARKER: "Marqueur", KIND_EFFECT: "Effet",
	KIND_ZONE: "Zone", KIND_PLATFORM: "Plateforme", KIND_OVERLAY: "Calque image",
	KIND_WALL: "Mur", KIND_NOTE: "Note MJ", KIND_LIGHT: "Lumière",
	KIND_LINK: "Passage", KIND_AREA: "Lieu", KIND_PROP: "Décor",
}

const DEFAULT_DISPLAY := {
	"rotation": 0.0,
	"mirrorH": false,
	"mirrorV": false,
	"scale": 1.0,
	"opacity": 1.0,
	"tint": "",
	"colorize": 0.0,
	"brightness": 0.0,
	"contrast": 0.0,
	"saturation": 0.0,
}

## Clés de `map_data` couvertes par les deltas `meta`.
const META_KEYS := [
	"title", "description", "width", "height", "grid", "fogEnabled",
	"perspective", "lighting", "atmosphere", "backgroundImage",
	"backgroundTransform", "scenarioId", "roster", "mapKind", "measure",
]

# --- État -------------------------------------------------------------------
var map_data: Dictionary = {}
var play_defaults: Dictionary = {}

var _elements: Dictionary = {}      # id -> element Dictionary
var _order: Array = []              # ids, ordre de création / empilement
var _shadow: Dictionary = {}        # id -> dernier état JSON validé (shadow copy)
var _selected: Array = []

var _undo_stack: Array = []         # Array[Array[delta]]
var _redo_stack: Array = []
var _pending: Array = []            # transaction ouverte
var _transaction_depth: int = 0
var _restoring: bool = false
var _dirty: bool = false
var _clipboard: Array = []

# ===========================================================================
# Chargement / sérialisation
# ===========================================================================

func load_map(source: Dictionary) -> void:
	map_data = MapData.ensure_map_schema(source.duplicate(true))
	_ensure_editor_schema()
	play_defaults = MapData.ensure_play_defaults(map_data).duplicate(true)
	_elements.clear()
	_order.clear()
	_shadow.clear()
	_selected.clear()
	_undo_stack.clear()
	_redo_stack.clear()
	_pending.clear()
	_transaction_depth = 0
	_deserialize()
	_commit_all_shadows()
	_set_dirty(false)
	history_changed.emit()
	selection_changed.emit([])
	changed.emit("load")

func _ensure_editor_schema() -> void:
	if not map_data.has("walls") or typeof(map_data["walls"]) != TYPE_ARRAY:
		map_data["walls"] = []
	if not map_data.has("notes") or typeof(map_data["notes"]) != TYPE_ARRAY:
		map_data["notes"] = []
	if not map_data.has("areas") or typeof(map_data["areas"]) != TYPE_ARRAY:
		map_data["areas"] = []
	if not map_data.has("props") or typeof(map_data["props"]) != TYPE_ARRAY:
		map_data["props"] = []
	if not map_data.has("backgroundTransform") or typeof(map_data["backgroundTransform"]) != TYPE_DICTIONARY:
		map_data["backgroundTransform"] = {"offsetX": 0.0, "offsetY": 0.0, "scale": 1.0, "opacity": 1.0}
	if not map_data.has("measure") or typeof(map_data["measure"]) != TYPE_DICTIONARY:
		map_data["measure"] = {"unit": "m", "perCell": 1.5}
	if not map_data.has("layers") or typeof(map_data["layers"]) != TYPE_ARRAY:
		map_data["layers"] = default_layers()
	var lighting: Dictionary = MapData.get_lighting_config(map_data)
	if not lighting.has("sources") or typeof(lighting["sources"]) != TYPE_ARRAY:
		lighting["sources"] = []
	map_data["lighting"] = lighting

static func default_layers() -> Array:
	return [
		{"id": 0, "name": "Terrain", "visible": true, "locked": false},
		{"id": 1, "name": "Décor", "visible": true, "locked": false},
		{"id": 2, "name": "Structures", "visible": true, "locked": false},
		{"id": 3, "name": "Zones & effets", "visible": true, "locked": false},
		{"id": 4, "name": "Tokens", "visible": true, "locked": false},
		{"id": 5, "name": "Notes MJ", "visible": true, "locked": false},
	]

func _deserialize() -> void:
	for tok in play_defaults.get("tokens", []):
		if tok is Dictionary:
			var kind := KIND_MARKER if str(tok.get("kind", "")) == "marker" else KIND_TOKEN
			_ingest(tok, kind, 4 if kind == KIND_TOKEN else 3)
	for eff in play_defaults.get("effects", []):
		if eff is Dictionary:
			_ingest(eff, KIND_EFFECT, 3)
	for zone in play_defaults.get("zones", []):
		if zone is Dictionary:
			_ingest(zone, KIND_ZONE, 3)
	for layer_def in map_data.get("elevationLayers", []):
		if not layer_def is Dictionary:
			continue
		if layer_def.get("platform") is Dictionary:
			var plat: Dictionary = layer_def["platform"]
			var elem: Dictionary = (layer_def as Dictionary).duplicate(true)
			elem["x"] = float(plat.get("x", 0))
			elem["y"] = float(plat.get("y", 0))
			elem["w"] = float(plat.get("w", 2))
			elem["h"] = float(plat.get("h", 2))
			elem.erase("platform")
			_ingest(elem, KIND_PLATFORM, 2)
		elif not str(layer_def.get("image", "")).is_empty():
			_ingest(layer_def.duplicate(true), KIND_OVERLAY, 1)
	for wall in map_data.get("walls", []):
		if wall is Dictionary:
			_ingest(wall, KIND_WALL, 2)
	for note in map_data.get("notes", []):
		if note is Dictionary:
			_ingest(note, KIND_NOTE, 5)
	var lighting: Dictionary = map_data.get("lighting", {})
	for src in lighting.get("sources", []):
		if src is Dictionary:
			_ingest(src, KIND_LIGHT, 2)
	for link in map_data.get("locationLinks", []):
		if link is Dictionary:
			_ingest(link, KIND_LINK, 5)
	for area in map_data.get("areas", []):
		if area is Dictionary:
			_ingest(area, KIND_AREA, 5)
	for prop in map_data.get("props", []):
		if prop is Dictionary:
			_ingest(prop, KIND_PROP, 1)

func _ingest(raw: Dictionary, kind: String, default_layer: int) -> void:
	var elem := normalize_element(raw, kind, default_layer)
	var id: String = elem["id"]
	_elements[id] = elem
	_order.append(id)

static func normalize_element(raw: Dictionary, kind: String, default_layer: int = 3) -> Dictionary:
	var elem: Dictionary = raw.duplicate(true)
	if kind == KIND_TOKEN:
		# Le format historique stocke le sous-type dans `kind` ("member").
		elem["tokenKind"] = str(elem.get("tokenKind", raw.get("kind", "member")))
		if elem["tokenKind"] == "marker":
			elem["tokenKind"] = "member"
	elem["kind"] = kind
	if str(elem.get("id", "")).is_empty():
		elem["id"] = MapData.generate_id(kind.substr(0, 3))
	elem["x"] = float(elem.get("x", 0.0))
	elem["y"] = float(elem.get("y", 0.0))
	elem["w"] = maxf(0.1, float(elem.get("w", _default_width(kind, elem))))
	elem["h"] = maxf(0.1, float(elem.get("h", _default_height(kind, elem))))
	elem["layer"] = int(elem.get("layer", default_layer))
	elem["zOrder"] = float(elem.get("zOrder", 0.0))
	elem["locked"] = bool(elem.get("locked", false))
	elem["hidden"] = bool(elem.get("hidden", false))
	elem["group"] = str(elem.get("group", ""))
	elem["notes"] = str(elem.get("notes", ""))
	if str(elem.get("label", "")).is_empty():
		elem["label"] = default_label(elem)
	var display: Dictionary = DEFAULT_DISPLAY.duplicate(true)
	if elem.get("display") is Dictionary:
		display.merge(elem["display"], true)
	elem["display"] = display
	var links: Dictionary = {"next": [], "prev": []}
	if elem.get("links") is Dictionary:
		var raw_links: Dictionary = elem["links"]
		links["next"] = (raw_links.get("next", []) as Array).duplicate() if raw_links.get("next") is Array else []
		links["prev"] = (raw_links.get("prev", []) as Array).duplicate() if raw_links.get("prev") is Array else []
	elem["links"] = links
	return elem

static func _default_width(kind: String, elem: Dictionary) -> float:
	match kind:
		KIND_ZONE:
			return float(elem.get("radius", 1.5)) * 2.0
		KIND_EFFECT:
			return float(elem.get("radius", 1.0)) * 2.0
		KIND_PLATFORM:
			return 3.0
		KIND_OVERLAY:
			return float(elem.get("mapWidth", 16))
		KIND_WALL:
			return 1.0
		KIND_AREA:
			return 3.0
		_:
			return 1.0

static func _default_height(kind: String, elem: Dictionary) -> float:
	match kind:
		KIND_ZONE:
			return float(elem.get("radius", 1.5)) * 2.0
		KIND_EFFECT:
			return float(elem.get("radius", 1.0)) * 2.0
		KIND_PLATFORM:
			return 3.0
		KIND_OVERLAY:
			return float(elem.get("mapHeight", 12))
		KIND_WALL:
			return 1.0
		KIND_AREA:
			return 3.0
		_:
			return 1.0

static func default_label(elem: Dictionary) -> String:
	var kind := str(elem.get("kind", KIND_TOKEN))
	match kind:
		KIND_MARKER:
			return MapData.get_marker_label(str(elem.get("markerType", "npc")))
		KIND_EFFECT:
			return str(elem.get("preset", "Effet")).capitalize()
		KIND_ZONE:
			return "Zone"
		KIND_PLATFORM:
			return "Plateforme"
		KIND_OVERLAY:
			return str(elem.get("image", "Calque")).get_file()
		KIND_WALL:
			return "Mur"
		KIND_NOTE:
			return "Note"
		KIND_LIGHT:
			return "Lumière"
		KIND_LINK:
			return str(elem.get("label", "Passage"))
		KIND_AREA:
			return "Lieu"
		_:
			return "Token"

## Reconstruit `map_data` + `playDefaults` à partir du modèle plat.
func to_map_data() -> Dictionary:
	var out: Dictionary = map_data.duplicate(true)
	var tokens: Array = []
	var effects: Array = []
	var zones: Array = []
	var elevations: Array = []
	var walls: Array = []
	var notes: Array = []
	var lights: Array = []
	var links: Array = []
	var areas: Array = []
	var props: Array = []
	for id in _order:
		var elem: Dictionary = _elements.get(id, {})
		if elem.is_empty():
			continue
		var payload: Dictionary = elem.duplicate(true)
		match str(elem.get("kind", "")):
			KIND_TOKEN:
				payload["kind"] = str(elem.get("tokenKind", "member"))
				tokens.append(payload)
			KIND_MARKER:
				payload["kind"] = "marker"
				tokens.append(payload)
			KIND_EFFECT:
				effects.append(payload)
			KIND_ZONE:
				zones.append(payload)
			KIND_PLATFORM:
				payload["platform"] = {
					"x": int(round(elem.get("x", 0))),
					"y": int(round(elem.get("y", 0))),
					"w": int(round(elem.get("w", 3))),
					"h": int(round(elem.get("h", 3))),
				}
				elevations.append(payload)
			KIND_OVERLAY:
				elevations.append(payload)
			KIND_WALL:
				walls.append(payload)
			KIND_NOTE:
				notes.append(payload)
			KIND_LIGHT:
				lights.append(payload)
			KIND_LINK:
				payload["x"] = int(round(elem.get("x", 0)))
				payload["y"] = int(round(elem.get("y", 0)))
				links.append(payload)
			KIND_AREA:
				areas.append(payload)
			KIND_PROP:
				props.append(payload)
	var pd: Dictionary = play_defaults.duplicate(true)
	pd["tokens"] = tokens
	pd["effects"] = effects
	pd["zones"] = zones
	if not pd.has("fogRevealed") or typeof(pd["fogRevealed"]) != TYPE_ARRAY:
		pd["fogRevealed"] = []
	if not pd.has("viewState") or typeof(pd["viewState"]) != TYPE_DICTIONARY:
		pd["viewState"] = {}
	out["playDefaults"] = pd
	out["elevationLayers"] = elevations
	out["walls"] = walls
	out["notes"] = notes
	out["locationLinks"] = links
	out["areas"] = areas
	out["props"] = props
	var lighting: Dictionary = out.get("lighting", {}).duplicate(true) if out.get("lighting") is Dictionary else {}
	lighting["sources"] = lights
	out["lighting"] = lighting
	out["schemaVersion"] = MapData.SCHEMA_VERSION
	return MapData.ensure_map_schema(out)

# ===========================================================================
# Lecture du modèle
# ===========================================================================

func get_element(id: String) -> Dictionary:
	return _elements.get(id, {})

func has_element(id: String) -> bool:
	return _elements.has(id)

func element_ids() -> Array:
	return _order.duplicate()

func elements() -> Array:
	var out: Array = []
	for id in _order:
		out.append(_elements[id])
	return out

## Éléments triés pour l'affichage (calque puis ordre de création).
func elements_sorted() -> Array:
	var out: Array = elements()
	out.sort_custom(func(a, b):
		var la := int(a.get("layer", 0))
		var lb := int(b.get("layer", 0))
		if la != lb:
			return la < lb
		return float(a.get("zOrder", 0.0)) < float(b.get("zOrder", 0.0))
	)
	return out

func elements_of_kind(kind: String) -> Array:
	var out: Array = []
	for id in _order:
		if str(_elements[id].get("kind", "")) == kind:
			out.append(_elements[id])
	return out

func count_of_kind(kind: String) -> int:
	return elements_of_kind(kind).size()

func is_layer_visible(layer_index: int) -> bool:
	for layer_def in map_data.get("layers", []):
		if int(layer_def.get("id", -1)) == layer_index:
			return bool(layer_def.get("visible", true))
	return true

func is_layer_locked(layer_index: int) -> bool:
	for layer_def in map_data.get("layers", []):
		if int(layer_def.get("id", -1)) == layer_index:
			return bool(layer_def.get("locked", false))
	return false

func is_element_visible(elem: Dictionary) -> bool:
	if bool(elem.get("hidden", false)):
		return false
	return is_layer_visible(int(elem.get("layer", 0)))

func is_element_selectable(elem: Dictionary) -> bool:
	if bool(elem.get("locked", false)):
		return false
	if is_layer_locked(int(elem.get("layer", 0))):
		return false
	return is_element_visible(elem)

func layer_name(layer_index: int) -> String:
	for layer_def in map_data.get("layers", []):
		if int(layer_def.get("id", -1)) == layer_index:
			return str(layer_def.get("name", "Calque %d" % layer_index))
	return "Calque %d" % layer_index

# ===========================================================================
# Historique — deltas & transactions
# ===========================================================================

func begin_transaction() -> void:
	_transaction_depth += 1
	if _transaction_depth == 1:
		_pending = []

func commit_transaction() -> void:
	if _transaction_depth <= 0:
		return
	_transaction_depth -= 1
	if _transaction_depth > 0:
		return
	if not _pending.is_empty():
		_push_step(_pending)
	_pending = []

func abort_transaction() -> void:
	_transaction_depth = 0
	_pending = []

func _push_delta(delta: Dictionary) -> void:
	if _restoring:
		return
	if _transaction_depth > 0:
		_pending.append(delta)
	else:
		_push_step([delta])

func _push_step(step: Array) -> void:
	if step.is_empty():
		return
	_undo_stack.append(step)
	if _undo_stack.size() > MAX_HISTORY:
		_undo_stack.pop_front()
	_redo_stack.clear()
	_set_dirty(true)
	history_changed.emit()

func can_undo() -> bool:
	return not _undo_stack.is_empty()

func can_redo() -> bool:
	return not _redo_stack.is_empty()

func undo_label() -> String:
	if _undo_stack.is_empty():
		return ""
	return _step_label(_undo_stack[_undo_stack.size() - 1])

func redo_label() -> String:
	if _redo_stack.is_empty():
		return ""
	return _step_label(_redo_stack[_redo_stack.size() - 1])

func history_labels() -> Array:
	var out: Array = []
	for step in _undo_stack:
		out.append(_step_label(step))
	return out

func _step_label(step: Array) -> String:
	if step.is_empty():
		return "?"
	var first: Dictionary = step[0]
	var type := str(first.get("type", ""))
	var suffix := " ×%d" % step.size() if step.size() > 1 else ""
	match type:
		D_ELEM_ADD:
			return "Ajout %s%s" % [_delta_kind_label(first, "after"), suffix]
		D_ELEM_DEL:
			return "Suppression %s%s" % [_delta_kind_label(first, "before"), suffix]
		D_ELEM_MOD:
			return "%s %s%s" % [str(first.get("note", "Modification")), _delta_kind_label(first, "after"), suffix]
		D_META:
			return "Réglages carte"
		D_TILES:
			return "Peinture terrain%s" % suffix
		D_FOG:
			return "Brouillard"
		D_ORDER:
			return "Ordre des calques"
		_:
			return type

func _delta_kind_label(delta: Dictionary, side: String) -> String:
	var payload = delta.get(side, {})
	if payload is Dictionary:
		return str(KIND_LABELS.get(str(payload.get("kind", "")), "élément")).to_lower()
	return "élément"

func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	var step: Array = _undo_stack.pop_back()
	_restoring = true
	for i in range(step.size() - 1, -1, -1):
		_apply_delta(step[i], true)
	_restoring = false
	_redo_stack.append(step)
	_prune_selection()
	_set_dirty(true)
	history_changed.emit()
	changed.emit("undo")
	return true

func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	var step: Array = _redo_stack.pop_back()
	_restoring = true
	for delta in step:
		_apply_delta(delta, false)
	_restoring = false
	_undo_stack.append(step)
	_prune_selection()
	_set_dirty(true)
	history_changed.emit()
	changed.emit("redo")
	return true

func _apply_delta(delta: Dictionary, use_before: bool) -> void:
	var type := str(delta.get("type", ""))
	match type:
		D_ELEM_ADD:
			if use_before:
				_raw_remove(str(delta.get("id", "")))
			else:
				_raw_insert(delta.get("after", {}).duplicate(true), int(delta.get("index", -1)))
		D_ELEM_DEL:
			if use_before:
				_raw_insert(delta.get("before", {}).duplicate(true), int(delta.get("index", -1)))
			else:
				_raw_remove(str(delta.get("id", "")))
		D_ELEM_MOD:
			var state = delta.get("before" if use_before else "after", {})
			if state is Dictionary and not state.is_empty():
				var id := str(delta.get("id", ""))
				_elements[id] = (state as Dictionary).duplicate(true)
				_shadow[id] = (state as Dictionary).duplicate(true)
		D_META:
			var meta = delta.get("before" if use_before else "after", {})
			if meta is Dictionary:
				for key in (meta as Dictionary).keys():
					map_data[key] = (meta as Dictionary)[key]
		D_TILES:
			var cells = delta.get("before" if use_before else "after", {})
			if cells is Dictionary:
				var tiles: Array = map_data.get("tiles", [])
				for key in (cells as Dictionary).keys():
					var idx := int(key)
					if idx >= 0 and idx < tiles.size():
						tiles[idx] = (cells as Dictionary)[key]
				map_data["tiles"] = tiles
		D_FOG:
			var fog = delta.get("before" if use_before else "after", [])
			if fog is Array:
				play_defaults["fogRevealed"] = (fog as Array).duplicate()
		D_ORDER:
			var order = delta.get("before" if use_before else "after", [])
			if order is Array:
				_order = (order as Array).duplicate()

func _raw_insert(elem: Dictionary, index: int) -> void:
	var id := str(elem.get("id", ""))
	if id.is_empty():
		return
	_elements[id] = elem
	_shadow[id] = elem.duplicate(true)
	if _order.has(id):
		return
	if index >= 0 and index <= _order.size():
		_order.insert(index, id)
	else:
		_order.append(id)

func _raw_remove(id: String) -> void:
	_elements.erase(id)
	_shadow.erase(id)
	_order.erase(id)

func _prune_selection() -> void:
	var before := _selected.size()
	_selected = _selected.filter(func(id): return _elements.has(id))
	if _selected.size() != before:
		selection_changed.emit(_selected.duplicate())

func _commit_all_shadows() -> void:
	for id in _elements:
		_shadow[id] = (_elements[id] as Dictionary).duplicate(true)

func _commit_shadow(id: String) -> void:
	if _elements.has(id):
		_shadow[id] = (_elements[id] as Dictionary).duplicate(true)

## Dernier état « validé » d'un élément (shadow copy façon ItemSnapable).
func _shadow_state(id: String) -> Dictionary:
	if _shadow.has(id):
		return (_shadow[id] as Dictionary).duplicate(true)
	if _elements.has(id):
		return (_elements[id] as Dictionary).duplicate(true)
	return {}

# ===========================================================================
# Mutations
# ===========================================================================

## Calque naturel d'un type d'élément, quand l'appelant n'en impose pas.
static func default_layer_for_kind(kind: String) -> int:
	match kind:
		KIND_OVERLAY:
			return 1
		KIND_PROP:
			return 1
		KIND_PLATFORM, KIND_WALL, KIND_LIGHT:
			return 2
		KIND_TOKEN:
			return 4
		KIND_NOTE, KIND_LINK, KIND_AREA:
			return 5
		_:
			return 3

func add_element(elem: Dictionary, kind: String = "", note: String = "") -> String:
	var resolved_kind := kind if not kind.is_empty() else str(elem.get("kind", KIND_TOKEN))
	var normalized := normalize_element(elem, resolved_kind, default_layer_for_kind(resolved_kind))
	normalized["zOrder"] = float(_order.size()) * 0.001
	var id: String = normalized["id"]
	_elements[id] = normalized
	_order.append(id)
	_shadow[id] = normalized.duplicate(true)
	_push_delta({
		"type": D_ELEM_ADD,
		"id": id,
		"index": _order.size() - 1,
		"after": normalized.duplicate(true),
		"note": note,
	})
	changed.emit("add")
	return id

func remove_element(id: String) -> void:
	if not _elements.has(id):
		return
	var index := _order.find(id)
	var before: Dictionary = (_elements[id] as Dictionary).duplicate(true)
	_unlink_all(id)
	_raw_remove(id)
	_push_delta({"type": D_ELEM_DEL, "id": id, "index": index, "before": before})
	_selected.erase(id)
	selection_changed.emit(_selected.duplicate())
	changed.emit("remove")

func remove_elements(ids: Array) -> void:
	if ids.is_empty():
		return
	begin_transaction()
	for id in ids.duplicate():
		remove_element(str(id))
	commit_transaction()

## Applique des modifications à un élément et enregistre le delta.
func modify_element(id: String, mutations: Dictionary, note: String = "Modification") -> void:
	if not _elements.has(id):
		return
	var before: Dictionary = _shadow_state(id)
	var elem: Dictionary = _elements[id]
	for key in mutations.keys():
		if key == "display" and mutations[key] is Dictionary:
			var display: Dictionary = (elem.get("display", {}) as Dictionary).duplicate(true)
			display.merge(mutations[key], true)
			elem["display"] = display
		else:
			elem[key] = mutations[key]
	_elements[id] = elem
	if _states_equal(before, elem):
		return  # Aucun changement réel : pas de delta parasite dans l'historique.
	_commit_shadow(id)
	_push_delta({
		"type": D_ELEM_MOD,
		"id": id,
		"before": before,
		"after": elem.duplicate(true),
		"note": note,
	})
	changed.emit("modify")

## Modifie sans historique (drag en cours). `commit_live_edit` clôt l'action.
func set_live_position(id: String, gx: float, gy: float) -> void:
	if not _elements.has(id):
		return
	var elem: Dictionary = _elements[id]
	elem["x"] = gx
	elem["y"] = gy
	_elements[id] = elem

func commit_live_edit(ids: Array, note: String = "Déplacement") -> void:
	if ids.is_empty():
		return
	begin_transaction()
	for id_variant in ids:
		var id := str(id_variant)
		if not _elements.has(id):
			continue
		var before: Dictionary = _shadow_state(id)
		var after: Dictionary = (_elements[id] as Dictionary).duplicate(true)
		if _states_equal(before, after):
			continue
		_commit_shadow(id)
		_push_delta({"type": D_ELEM_MOD, "id": id, "before": before, "after": after, "note": note})
	commit_transaction()
	changed.emit("commit")

func revert_live_edit(ids: Array) -> void:
	for id_variant in ids:
		var id := str(id_variant)
		if _shadow.has(id):
			_elements[id] = (_shadow[id] as Dictionary).duplicate(true)
	changed.emit("revert")

static func _states_equal(a: Dictionary, b: Dictionary) -> bool:
	return JSON.stringify(a) == JSON.stringify(b)

func modify_selection(mutations: Dictionary, note: String = "Modification") -> void:
	if _selected.is_empty():
		return
	begin_transaction()
	for id in _selected.duplicate():
		modify_element(str(id), mutations, note)
	commit_transaction()

func move_elements_by(ids: Array, dx: float, dy: float, note: String = "Déplacement") -> void:
	if ids.is_empty():
		return
	begin_transaction()
	for id_variant in ids:
		var id := str(id_variant)
		var elem: Dictionary = _elements.get(id, {})
		if elem.is_empty() or bool(elem.get("locked", false)):
			continue
		modify_element(id, {"x": float(elem.get("x", 0.0)) + dx, "y": float(elem.get("y", 0.0)) + dy}, note)
	commit_transaction()

# --- Métadonnées ------------------------------------------------------------

func set_meta_values(values: Dictionary, note: String = "Réglages") -> void:
	var before: Dictionary = {}
	var after: Dictionary = {}
	var touched := false
	for key in values.keys():
		var old_value = map_data.get(key)
		if typeof(old_value) == typeof(values[key]) and JSON.stringify(old_value) == JSON.stringify(values[key]):
			continue
		before[key] = old_value.duplicate(true) if old_value is Dictionary or old_value is Array else old_value
		after[key] = values[key]
		map_data[key] = values[key]
		touched = true
	if not touched:
		return
	_push_delta({"type": D_META, "before": before, "after": after, "note": note})
	changed.emit("meta")

## Applique un réglage sans historique (aperçu live d'un slider).
func set_meta_live(key: String, value: Variant) -> void:
	map_data[key] = value
	changed.emit("meta_live")

# --- Terrain ----------------------------------------------------------------

func paint_tiles(cells: Dictionary) -> void:
	if cells.is_empty():
		return
	var tiles: Array = map_data.get("tiles", [])
	var before: Dictionary = {}
	var after: Dictionary = {}
	for key in cells.keys():
		var idx := int(key)
		if idx < 0 or idx >= tiles.size():
			continue
		var new_value := str(cells[key])
		if str(tiles[idx]) == new_value:
			continue
		before[str(idx)] = tiles[idx]
		after[str(idx)] = new_value
		tiles[idx] = new_value
	if after.is_empty():
		return
	map_data["tiles"] = tiles
	_push_delta({"type": D_TILES, "before": before, "after": after})
	changed.emit("tiles")

func get_tile_at(cx: int, cy: int) -> String:
	var w: int = int(map_data.get("width", 16))
	var h: int = int(map_data.get("height", 12))
	if cx < 0 or cy < 0 or cx >= w or cy >= h:
		return ""
	var tiles: Array = map_data.get("tiles", [])
	var idx := cy * w + cx
	if idx < 0 or idx >= tiles.size():
		return ""
	return str(tiles[idx])

## Remplissage par diffusion (bucket) à partir d'une case.
func bucket_fill(cx: int, cy: int, tile_id: String) -> void:
	var w: int = int(map_data.get("width", 16))
	var h: int = int(map_data.get("height", 12))
	var target := get_tile_at(cx, cy)
	if target.is_empty() or target == tile_id:
		return
	var cells: Dictionary = {}
	var queue: Array = [Vector2i(cx, cy)]
	var seen: Dictionary = {}
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var key := "%d,%d" % [cell.x, cell.y]
		if seen.has(key):
			continue
		seen[key] = true
		if cell.x < 0 or cell.y < 0 or cell.x >= w or cell.y >= h:
			continue
		if get_tile_at(cell.x, cell.y) != target:
			continue
		cells[str(cell.y * w + cell.x)] = tile_id
		queue.append(Vector2i(cell.x + 1, cell.y))
		queue.append(Vector2i(cell.x - 1, cell.y))
		queue.append(Vector2i(cell.x, cell.y + 1))
		queue.append(Vector2i(cell.x, cell.y - 1))
	paint_tiles(cells)

## Redimensionne la grille en conservant le contenu existant.
func resize_grid(new_w: int, new_h: int) -> void:
	var old_w: int = int(map_data.get("width", 16))
	var old_h: int = int(map_data.get("height", 12))
	if new_w == old_w and new_h == old_h:
		return
	var old_tiles: Array = map_data.get("tiles", [])
	var fill := str(old_tiles[0]) if not old_tiles.is_empty() else "floor"
	var new_tiles: Array = []
	new_tiles.resize(new_w * new_h)
	for y in range(new_h):
		for x in range(new_w):
			var value := fill
			if x < old_w and y < old_h:
				var idx := y * old_w + x
				if idx < old_tiles.size():
					value = str(old_tiles[idx])
			new_tiles[y * new_w + x] = value
	begin_transaction()
	set_meta_values({"width": new_w, "height": new_h, "tiles": new_tiles}, "Redimensionnement")
	commit_transaction()

# --- Brouillard -------------------------------------------------------------

func fog_cells() -> Array:
	var fog = play_defaults.get("fogRevealed", [])
	return fog if fog is Array else []

func set_fog_cells(cells: Array, note: String = "Brouillard") -> void:
	var before: Array = fog_cells().duplicate()
	var after: Array = cells.duplicate()
	if JSON.stringify(before) == JSON.stringify(after):
		return
	play_defaults["fogRevealed"] = after
	_push_delta({"type": D_FOG, "before": before, "after": after, "note": note})
	changed.emit("fog")

func reveal_fog(cells: Array) -> void:
	var fog: Array = fog_cells().duplicate()
	var touched := false
	for key in cells:
		var k := str(key)
		if not fog.has(k):
			fog.append(k)
			touched = true
	if touched:
		set_fog_cells(fog, "Révélation")

func hide_fog(cells: Array) -> void:
	var fog: Array = fog_cells().duplicate()
	var touched := false
	for key in cells:
		var k := str(key)
		if fog.has(k):
			fog.erase(k)
			touched = true
	if touched:
		set_fog_cells(fog, "Masquage")

func reveal_all_fog() -> void:
	var w: int = int(map_data.get("width", 16))
	var h: int = int(map_data.get("height", 12))
	var cells: Array = []
	for y in range(h):
		for x in range(w):
			cells.append("%d,%d" % [x, y])
	set_fog_cells(cells, "Tout révéler")

# ===========================================================================
# Liens entre éléments (bidirectionnels, façon SnapableElementConnections)
# ===========================================================================

func link_elements(source_id: String, target_id: String) -> bool:
	if source_id == target_id:
		return false
	if not _elements.has(source_id) or not _elements.has(target_id):
		return false
	var source: Dictionary = _elements[source_id]
	var next: Array = (source.get("links", {}) as Dictionary).get("next", [])
	if next.has(target_id):
		return false
	begin_transaction()
	var source_links: Dictionary = (source.get("links", {}) as Dictionary).duplicate(true)
	source_links["next"] = (source_links.get("next", []) as Array).duplicate()
	source_links["next"].append(target_id)
	modify_element(source_id, {"links": source_links}, "Lien")
	var target: Dictionary = _elements[target_id]
	var target_links: Dictionary = (target.get("links", {}) as Dictionary).duplicate(true)
	target_links["prev"] = (target_links.get("prev", []) as Array).duplicate()
	if not target_links["prev"].has(source_id):
		target_links["prev"].append(source_id)
	modify_element(target_id, {"links": target_links}, "Lien")
	commit_transaction()
	return true

func unlink_elements(source_id: String, target_id: String) -> void:
	if not _elements.has(source_id) or not _elements.has(target_id):
		return
	begin_transaction()
	var source_links: Dictionary = (_elements[source_id].get("links", {}) as Dictionary).duplicate(true)
	source_links["next"] = (source_links.get("next", []) as Array).duplicate()
	source_links["next"].erase(target_id)
	modify_element(source_id, {"links": source_links}, "Lien")
	var target_links: Dictionary = (_elements[target_id].get("links", {}) as Dictionary).duplicate(true)
	target_links["prev"] = (target_links.get("prev", []) as Array).duplicate()
	target_links["prev"].erase(source_id)
	modify_element(target_id, {"links": target_links}, "Lien")
	commit_transaction()

## Retire toutes les références vers `id` avant sa suppression.
func _unlink_all(id: String) -> void:
	var elem: Dictionary = _elements.get(id, {})
	if elem.is_empty():
		return
	var links: Dictionary = elem.get("links", {})
	for other_id in (links.get("next", []) as Array):
		_strip_link(str(other_id), "prev", id)
	for other_id in (links.get("prev", []) as Array):
		_strip_link(str(other_id), "next", id)

func _strip_link(other_id: String, key: String, id: String) -> void:
	if not _elements.has(other_id):
		return
	var other: Dictionary = _elements[other_id]
	var other_links: Dictionary = (other.get("links", {}) as Dictionary).duplicate(true)
	var list: Array = (other_links.get(key, []) as Array).duplicate()
	if not list.has(id):
		return
	list.erase(id)
	other_links[key] = list
	modify_element(other_id, {"links": other_links}, "Lien")

func link_segments() -> Array:
	var segments: Array = []
	for id in _order:
		var elem: Dictionary = _elements[id]
		if not is_element_visible(elem):
			continue
		for target_id in (elem.get("links", {}) as Dictionary).get("next", []):
			var target: Dictionary = _elements.get(str(target_id), {})
			if target.is_empty() or not is_element_visible(target):
				continue
			segments.append({
				"from": Vector2(float(elem.get("x", 0)), float(elem.get("y", 0))),
				"to": Vector2(float(target.get("x", 0)), float(target.get("y", 0))),
				"fromId": id,
				"toId": str(target_id),
			})
	return segments

# ===========================================================================
# Sélection
# ===========================================================================

func selection() -> Array:
	return _selected.duplicate()

func selection_size() -> int:
	return _selected.size()

func is_selected(id: String) -> bool:
	return _selected.has(id)

func set_selection(ids: Array) -> void:
	var filtered: Array = []
	for id_variant in ids:
		var id := str(id_variant)
		if _elements.has(id) and not filtered.has(id):
			filtered.append(id)
	if JSON.stringify(filtered) == JSON.stringify(_selected):
		return
	_selected = filtered
	selection_changed.emit(_selected.duplicate())

func select_only(id: String) -> void:
	set_selection([id] if not id.is_empty() else [])

func toggle_selection(id: String) -> void:
	var current := _selected.duplicate()
	if current.has(id):
		current.erase(id)
	else:
		current.append(id)
	set_selection(current)

func add_to_selection(ids: Array) -> void:
	var current := _selected.duplicate()
	for id in ids:
		if not current.has(str(id)):
			current.append(str(id))
	set_selection(current)

func clear_selection() -> void:
	set_selection([])

func select_all() -> void:
	var ids: Array = []
	for id in _order:
		if is_element_selectable(_elements[id]):
			ids.append(id)
	set_selection(ids)

func invert_selection() -> void:
	var ids: Array = []
	for id in _order:
		if not _selected.has(id) and is_element_selectable(_elements[id]):
			ids.append(id)
	set_selection(ids)

func select_same_kind() -> void:
	if _selected.is_empty():
		return
	var kind := str(_elements[_selected[0]].get("kind", ""))
	var ids: Array = []
	for id in _order:
		if str(_elements[id].get("kind", "")) == kind and is_element_selectable(_elements[id]):
			ids.append(id)
	set_selection(ids)

## Étend la sélection aux membres des mêmes groupes.
func expand_selection_to_groups() -> void:
	var groups: Dictionary = {}
	for id in _selected:
		var g := str(_elements[id].get("group", ""))
		if not g.is_empty():
			groups[g] = true
	if groups.is_empty():
		return
	var ids := _selected.duplicate()
	for id in _order:
		var g := str(_elements[id].get("group", ""))
		if not g.is_empty() and groups.has(g) and not ids.has(id):
			ids.append(id)
	set_selection(ids)

func selection_bounds() -> Rect2:
	if _selected.is_empty():
		return Rect2()
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for id in _selected:
		var elem: Dictionary = _elements[id]
		var half := Vector2(float(elem.get("w", 1.0)), float(elem.get("h", 1.0))) * 0.5
		var pos := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
		min_p.x = minf(min_p.x, pos.x - half.x)
		min_p.y = minf(min_p.y, pos.y - half.y)
		max_p.x = maxf(max_p.x, pos.x + half.x)
		max_p.y = maxf(max_p.y, pos.y + half.y)
	return Rect2(min_p, max_p - min_p)

# ===========================================================================
# Groupes
# ===========================================================================

func group_selection() -> void:
	if _selected.size() < 2:
		return
	var group_id := MapData.generate_id("grp")
	begin_transaction()
	for id in _selected:
		modify_element(str(id), {"group": group_id}, "Groupement")
	commit_transaction()

func ungroup_selection() -> void:
	if _selected.is_empty():
		return
	begin_transaction()
	for id in _selected:
		modify_element(str(id), {"group": ""}, "Dégroupement")
	commit_transaction()

# ===========================================================================
# Presse-papiers
# ===========================================================================

func copy_selection() -> int:
	_clipboard.clear()
	for id in _selected:
		_clipboard.append((_elements[id] as Dictionary).duplicate(true))
	return _clipboard.size()

func cut_selection() -> int:
	var count := copy_selection()
	remove_elements(_selected.duplicate())
	return count

func clipboard_size() -> int:
	return _clipboard.size()

## Colle le presse-papiers, centré sur (gx, gy) si fourni, sinon décalé d'une case.
func paste(gx: float = INF, gy: float = INF) -> Array:
	if _clipboard.is_empty():
		return []
	var min_p := Vector2(INF, INF)
	for entry in _clipboard:
		min_p.x = minf(min_p.x, float((entry as Dictionary).get("x", 0.0)))
		min_p.y = minf(min_p.y, float((entry as Dictionary).get("y", 0.0)))
	var offset := Vector2(1.0, 1.0)
	if gx != INF and gy != INF:
		offset = Vector2(gx, gy) - min_p
	var group_remap: Dictionary = {}
	var id_remap: Dictionary = {}
	var new_ids: Array = []
	begin_transaction()
	for elem_variant in _clipboard:
		var elem: Dictionary = (elem_variant as Dictionary).duplicate(true)
		var old_id := str(elem.get("id", ""))
		elem["x"] = float(elem.get("x", 0.0)) + offset.x
		elem["y"] = float(elem.get("y", 0.0)) + offset.y
		elem["id"] = MapData.generate_id(str(elem.get("kind", "elem")).substr(0, 3))
		var group := str(elem.get("group", ""))
		if not group.is_empty():
			if not group_remap.has(group):
				group_remap[group] = MapData.generate_id("grp")
			elem["group"] = group_remap[group]
		elem["links"] = {"next": [], "prev": []}
		var new_id := add_element(elem, str(elem.get("kind", KIND_TOKEN)), "Collage")
		id_remap[old_id] = new_id
		new_ids.append(new_id)
	# Recrée les liens internes au lot collé.
	for source_variant in _clipboard:
		var source: Dictionary = source_variant
		var source_old := str(source.get("id", ""))
		if not id_remap.has(source_old):
			continue
		for target_variant in (source.get("links", {}) as Dictionary).get("next", []):
			var target_old := str(target_variant)
			if id_remap.has(target_old):
				link_elements(str(id_remap[source_old]), str(id_remap[target_old]))
	commit_transaction()
	set_selection(new_ids)
	return new_ids

func duplicate_selection() -> Array:
	if _selected.is_empty():
		return []
	var saved := _clipboard.duplicate(true)
	copy_selection()
	var ids := paste()
	_clipboard = saved
	return ids

# ===========================================================================
# Ordre d'affichage / calques
# ===========================================================================

func set_layer_for_selection(layer_index: int) -> void:
	if _selected.is_empty():
		return
	begin_transaction()
	for id in _selected:
		modify_element(str(id), {"layer": layer_index}, "Calque")
	commit_transaction()

func bring_to_front() -> void:
	_reorder_selection(true, true)

func send_to_back() -> void:
	_reorder_selection(false, true)

func bring_forward() -> void:
	_reorder_selection(true, false)

func send_backward() -> void:
	_reorder_selection(false, false)

func _reorder_selection(forward: bool, extreme: bool) -> void:
	if _selected.is_empty():
		return
	var before := _order.duplicate()
	for id_variant in _selected:
		var id := str(id_variant)
		var idx := _order.find(id)
		if idx < 0:
			continue
		_order.remove_at(idx)
		var target := idx
		if extreme:
			target = _order.size() if forward else 0
		else:
			target = clampi(idx + (1 if forward else -1), 0, _order.size())
		_order.insert(target, id)
	if JSON.stringify(before) == JSON.stringify(_order):
		return
	_push_delta({"type": D_ORDER, "before": before, "after": _order.duplicate()})
	_resequence_z()
	changed.emit("order")

func _resequence_z() -> void:
	for i in range(_order.size()):
		var elem: Dictionary = _elements[_order[i]]
		elem["zOrder"] = float(i) * 0.001

func set_layer_visible(layer_index: int, visible: bool) -> void:
	var layers: Array = (map_data.get("layers", []) as Array).duplicate(true)
	for layer_def in layers:
		if int(layer_def.get("id", -1)) == layer_index:
			layer_def["visible"] = visible
	set_meta_values({"layers": layers}, "Visibilité calque")

func set_layer_locked(layer_index: int, locked: bool) -> void:
	var layers: Array = (map_data.get("layers", []) as Array).duplicate(true)
	for layer_def in layers:
		if int(layer_def.get("id", -1)) == layer_index:
			layer_def["locked"] = locked
	set_meta_values({"layers": layers}, "Verrou calque")

func rename_layer(layer_index: int, name: String) -> void:
	var layers: Array = (map_data.get("layers", []) as Array).duplicate(true)
	for layer_def in layers:
		if int(layer_def.get("id", -1)) == layer_index:
			layer_def["name"] = name
	set_meta_values({"layers": layers}, "Nom calque")

# ===========================================================================
# Alignement & distribution
# ===========================================================================

func align_selection(mode: String) -> void:
	if _selected.size() < 2:
		return
	var bounds := selection_bounds()
	begin_transaction()
	for id_variant in _selected:
		var id := str(id_variant)
		var elem: Dictionary = _elements[id]
		var half := Vector2(float(elem.get("w", 1.0)), float(elem.get("h", 1.0))) * 0.5
		var pos := Vector2(float(elem.get("x", 0.0)), float(elem.get("y", 0.0)))
		match mode:
			"left":
				pos.x = bounds.position.x + half.x
			"right":
				pos.x = bounds.end.x - half.x
			"top":
				pos.y = bounds.position.y + half.y
			"bottom":
				pos.y = bounds.end.y - half.y
			"center_h":
				pos.x = bounds.get_center().x
			"center_v":
				pos.y = bounds.get_center().y
		modify_element(id, {"x": pos.x, "y": pos.y}, "Alignement")
	commit_transaction()

func distribute_selection(horizontal: bool) -> void:
	if _selected.size() < 3:
		return
	var axis := "x" if horizontal else "y"
	var ids := _selected.duplicate()
	ids.sort_custom(func(a, b):
		return float(_elements[a].get(axis, 0.0)) < float(_elements[b].get(axis, 0.0))
	)
	var first := float(_elements[ids[0]].get(axis, 0.0))
	var last := float(_elements[ids[ids.size() - 1]].get(axis, 0.0))
	var step := (last - first) / float(ids.size() - 1)
	begin_transaction()
	for i in range(ids.size()):
		var mutation: Dictionary = {}
		mutation[axis] = first + step * float(i)
		modify_element(str(ids[i]), mutation, "Distribution")
	commit_transaction()

# ===========================================================================
# État « modifié »
# ===========================================================================

func is_dirty() -> bool:
	return _dirty

func mark_saved() -> void:
	_set_dirty(false)

func _set_dirty(value: bool) -> void:
	if _dirty == value:
		return
	_dirty = value
	dirty_changed.emit(_dirty)
