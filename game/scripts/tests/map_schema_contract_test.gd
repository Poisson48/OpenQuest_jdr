extends SceneTree

## TEST DE CONTRAT — schéma de carte (phase 2.8b du refactor).
##
## Caractérise `MapData.ensure_map_schema` / `get_play_defaults` /
## `ensure_play_defaults`, extraits vers `core/maps/map_schema.gd`. Le but est de
## figer : clés ajoutées sur une carte vide, types et valeurs par défaut, ORDRE
## d'insertion (significatif pour la sérialisation JSON), idempotence, prédicats
## (carte monde / id démo), fusion des valeurs existantes et copie profonde des
## `playDefaults`.
##
## Convention : `godot --headless --path game -s res://scripts/tests/map_schema_contract_test.gd`

var _failed := false

func _init() -> void:
	call_deferred("_run")
	call_deferred("_arm_watchdog")

func _arm_watchdog() -> void:
	create_timer(60.0).timeout.connect(func():
		print("map_schema_contract_test:FAIL watchdog (60 s)")
		quit(1))

func _run() -> void:
	await process_frame
	var md = get_root().get_node("MapData")

	# =====================================================================
	# 1. Carte vide : toutes les clés du schéma courant sont ajoutées
	# =====================================================================
	var map: Dictionary = {}
	var returned = md.ensure_map_schema(map)
	# Contrat actuel : la carte est complétée EN PLACE et retournée telle quelle.
	_assert("returns_same_dict", is_same(returned, map))

	# Contrat actuel : ordre d'insertion des clés (sérialisation JSON).
	_assert("key_order", map.keys() == [
		"schemaVersion", "renderMode", "grid", "fogEnabled", "perspective",
		"elevationLayers", "lighting", "backgroundImageNight", "groundMode",
		"atmosphere", "playDefaults", "walls", "notes", "measure", "losEnabled",
		"areas", "props", "meshes", "terrainHeights", "terrainMaterials",
		"terrainCarves", "waterLevel", "waterBodies", "ambientFx", "worldId",
		"parentMapId", "status", "layers", "renderStyle",
	])

	_assert("schema_version", int(map.get("schemaVersion", 0)) == 1)
	_assert("render_mode_simple", str(map.get("renderMode", "")) == "simple")
	_assert("fog_enabled_local", bool(map.get("fogEnabled", false)))
	_assert("perspective_topdown", str(map.get("perspective", "")) == "topdown")
	_assert("elevation_layers_empty", (map.get("elevationLayers", null) as Array).is_empty())
	_assert("background_image_night", str(map.get("backgroundImageNight", "?")) == "")
	_assert("ground_mode_terrain3d", str(map.get("groundMode", "")) == "terrain3d")
	_assert("los_disabled", not bool(map.get("losEnabled", true)))
	_assert("water_level_none", is_equal_approx(float(map.get("waterLevel", 0.0)), -1.0))
	_assert("ambient_fx", str(map.get("ambientFx", "?")) == "")
	_assert("world_ids_empty", str(map.get("worldId", "?")) == ""
		and str(map.get("parentMapId", "?")) == "")
	_assert("status_draft", str(map.get("status", "")) == "draft")
	_assert("render_style", str(map.get("renderStyle", "")) == "2.5d")

	# --- grid : défauts + `show` masqué sur décor peint -------------------
	var grid: Dictionary = map.get("grid", {})
	_assert("grid_defaults", int(grid.get("size", 0)) == 70
		and is_equal_approx(float(grid.get("opacity", 0.0)), 0.22)
		and str(grid.get("color", "")) == "#ffffff"
		and bool(grid.get("enabled", false)))
	_assert("grid_show_hidden", grid.has("show") and not bool(grid["show"]))

	# --- lighting : défauts complets --------------------------------------
	var light: Dictionary = map.get("lighting", {})
	_assert("lighting_defaults", not bool(light.get("enabled", true))
		and str(light.get("direction", "")) == "nw"
		and is_equal_approx(float(light.get("intensity", 0.0)), 0.35)
		and str(light.get("ambient", "")) == "#121018"
		and str(light.get("preset", "")) == "jour"
		and (light.get("sources", null) as Array).is_empty()
		and not bool(light.get("nightMode", true))
		and is_equal_approx(float(light.get("nightAmbient", 0.0)), 0.22))

	# --- atmosphere / measure / layers ------------------------------------
	_assert("atmosphere_defaults", map.get("atmosphere", {}) == {
		"enabled": false, "tint": "#1a1410", "opacity": 0.25, "vignette": 0.15,
	})
	_assert("measure_defaults", map.get("measure", {}) == {"unit": "m", "perCell": 1.5})
	var layers: Array = map.get("layers", [])
	_assert("layers_defaults", layers.size() == 6
		and int((layers[0] as Dictionary).get("id", -1)) == 0
		and str((layers[0] as Dictionary).get("name", "")) == "Terrain"
		and str((layers[5] as Dictionary).get("name", "")) == "Notes MJ")

	# --- tableaux de travail vides ----------------------------------------
	_assert("empty_arrays",
		(map.get("walls", null) as Array).is_empty()
		and (map.get("notes", null) as Array).is_empty()
		and (map.get("areas", null) as Array).is_empty()
		and (map.get("props", null) as Array).is_empty()
		and (map.get("meshes", null) as Array).is_empty()
		and (map.get("terrainHeights", null) as Array).is_empty()
		and (map.get("terrainMaterials", null) as Array).is_empty()
		and (map.get("terrainCarves", null) as Array).is_empty()
		and (map.get("waterBodies", null) as Array).is_empty())

	# --- playDefaults : clés/types par défaut -----------------------------
	var pd: Dictionary = map.get("playDefaults", {})
	_assert("play_defaults_keys", pd.size() == 6
		and (pd.get("tokens", null) as Array).is_empty()
		and (pd.get("effects", null) as Array).is_empty()
		and (pd.get("zones", null) as Array).is_empty()
		and (pd.get("fogRevealed", null) as Array).is_empty()
		and (pd.get("lightRevealed", null) as Array).is_empty()
		and typeof(pd.get("viewState")) == TYPE_DICTIONARY)

	# =====================================================================
	# 2. Idempotence et préservation des valeurs existantes
	# =====================================================================
	var snapshot := JSON.stringify(map)
	md.ensure_map_schema(map)
	# Contrat actuel : ré-appliquer le schéma ne change rien (aucune clé en plus).
	_assert("idempotent", JSON.stringify(map) == snapshot)

	# Contrat actuel : les valeurs déjà présentes ne sont jamais écrasées.
	var custom: Dictionary = {"schemaVersion": 3, "renderMode": "complex", "fogEnabled": false}
	md.ensure_map_schema(custom)
	_assert("preserves_existing", int(custom.get("schemaVersion", 0)) == 3
		and str(custom.get("renderMode", "")) == "complex"
		and not bool(custom.get("fogEnabled", true)))

	# Contrat actuel : `grid` existant fusionné/ conservé, seul `show` ajouté.
	var custom_grid: Dictionary = {"grid": {"size": 40}, "id": "mon-test"}
	md.ensure_map_schema(custom_grid)
	_assert("preserves_custom_grid", int((custom_grid["grid"] as Dictionary).get("size", 0)) == 40
		and not bool((custom_grid["grid"] as Dictionary).get("show", true)))

	# Contrat actuel : `lighting` partiel complété sans écraser le preset.
	var custom_light: Dictionary = {"lighting": {"preset": "nuit"}}
	md.ensure_map_schema(custom_light)
	var cl: Dictionary = custom_light["lighting"]
	_assert("repairs_partial_lighting", str(cl.get("preset", "")) == "nuit"
		and not bool(cl.get("nightMode", true))
		and is_equal_approx(float(cl.get("nightAmbient", 0.0)), 0.22)
		and (cl.get("sources", null) as Array).is_empty())

	# =====================================================================
	# 3. Prédicats : carte monde, id démo, fond illustré, renderStyle
	# =====================================================================
	# Contrat actuel : une carte monde a le brouillard DÉSACTIVÉ par défaut.
	var world: Dictionary = {"mapKind": "world"}
	md.ensure_map_schema(world)
	_assert("world_map_no_fog", not bool(world.get("fogEnabled", true)))

	# Contrat actuel : les cartes démo sont publiées, les autres en brouillon.
	var demo: Dictionary = {"id": "demo-valbois-village"}
	md.ensure_map_schema(demo)
	_assert("demo_map_published", str(demo.get("status", "")) == "published")
	_assert("user_map_draft", str(custom_grid.get("status", "")) == "draft")

	# Contrat actuel : un fond illustré force le mode de sol illustré.
	var illustrated: Dictionary = {"backgroundImage": "user://fond.png"}
	md.ensure_map_schema(illustrated)
	_assert("illustrated_ground", str(illustrated.get("groundMode", "")) == "illustrated")

	# Contrat actuel : `grid.show` masqué uniquement pour les styles peinture.
	var vtt: Dictionary = {"renderStyle": "vtt"}
	md.ensure_map_schema(vtt)
	_assert("vtt_grid_not_hidden", not (vtt.get("grid", {}) as Dictionary).has("show"))

	# =====================================================================
	# 4. playDefaults : get (copie profonde) et ensure (réparation)
	# =====================================================================
	# Contrat actuel : `get_play_defaults` renvoie une COPIE profonde.
	var source: Dictionary = {}
	var copy: Dictionary = md.get_play_defaults(source)
	var copy_tokens: Array = copy["tokens"]
	copy_tokens.append({"id": "jeton-local"})
	_assert("get_play_defaults_deep_copy",
		((source.get("playDefaults", {}) as Dictionary).get("tokens", []) as Array).is_empty())

	# Contrat actuel : `ensure_play_defaults` répare les types corrompus.
	var corrupted: Dictionary = {"playDefaults": {"tokens": "pas-un-tableau", "viewState": 42}}
	var repaired: Dictionary = md.ensure_play_defaults(corrupted)
	_assert("ensure_play_defaults_repairs",
		(repaired.get("tokens", null) as Array).is_empty()
		and typeof(repaired.get("viewState")) == TYPE_DICTIONARY
		and (repaired.get("effects", null) as Array).is_empty()
		and (repaired.get("zones", null) as Array).is_empty()
		and (repaired.get("fogRevealed", null) as Array).is_empty()
		and (repaired.get("lightRevealed", null) as Array).is_empty())
	_assert("ensure_play_defaults_reference",
		is_same(repaired, (corrupted["playDefaults"] as Dictionary)))

	# Contrat actuel : les valeurs personnalisées valides sont préservées.
	var custom_pd: Dictionary = {"playDefaults": {"tokens": [{"id": "t1"}]}}
	md.ensure_play_defaults(custom_pd)
	_assert("play_defaults_preserves_custom",
		((custom_pd["playDefaults"] as Dictionary).get("tokens", []) as Array).size() == 1)

	# =====================================================================
	# Nettoyage
	# =====================================================================
	if _failed:
		quit(1)
		return
	print("map_schema_contract_test:PASS")
	quit(0)

func _assert(label: String, cond: bool) -> void:
	if not cond:
		print("map_schema_contract_test:FAIL at ", label)
		_failed = true
