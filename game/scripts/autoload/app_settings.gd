extends Node

## Préférences de l' APPLICATION (menu Paramètres de l'éditeur de cartes 3D).
##
## ## Découpage
## Ce qui est réglé ici ne modifie **pas** l'identité visuelle d'une carte :
## ce sont des préférences de machine et de confort (boucle de rendu, FPS,
## surcharges de qualité, langue, remap des raccourcis). Tout ce qui voyage
## avec la carte (grille, brouillard, éclairage, style de rendu, preset qualité,
## densités eau/végétation…) reste dans `map_data` et se règle dans l'onglet
## « Carte » — voir `docs/RAPPORT_E...` et `artifacts/reglages_inventaire.md`.
##
## ## Persistance
## Même fichier que `LocaleSettings` : `user://app_settings.cfg`. On **relit**
## toujours le fichier avant d'écrire pour ne pas écraser la section `[ui]`.
## Sections écrites ici : `[display]`, `[rendering]`, `[interface]`, `[keys]`.
##
## ## Boucle de rendu
## `Engine.max_fps`, VSync, mode fenêtre, délai d'infobulles sont appliqués ici
## directement. Les surcharges 3D (MSAA, AA écran, échelle de rendu, ombres,
## AO/SSIL/glow/brume volumétrique, réflexions d'eau) sont **déléguées au
## moteur** via `ComplexMapEngine3D.set_global_overrides()` : le moteur les
## réapplique après chaque `configure()`, sinon la carte reprendrait la main à
## chaque édition.
##
## Signal unique : `settings_changed(section)` avec section parmi
## `display`, `rendering`, `interface`, `keys`.

signal settings_changed(section: String)

const SETTINGS_PATH := "user://app_settings.cfg"

## Outils de l'éditeur : catalogue pur (aucun autoload) → préchargeable ici
## pour exposer les raccourcis d'outils dans le remap.
const ToolsScript := preload("res://scripts/maps/editor/map_editor_tools.gd")

const SECTION_DISPLAY := "display"
const SECTION_RENDERING := "rendering"
const SECTION_INTERFACE := "interface"
const SECTION_KEYS := "keys"

## Valeur « neutre » : le réglage n'est pas surchargé, la carte décide.
const NEUTRAL_AA := "auto"
const NEUTRAL_SHADOWS := "map"

## Valeurs par défaut (= comportement historique de l'éditeur).
## `fps_*` : le compteur existait et était toujours visible en barre d'état.
## `aa` : l'éditeur était en MSAA 2× (cinéma : MSAA 4×), échelle 1.0.
const DEFAULTS := {
	SECTION_DISPLAY: {
		"max_fps": 0,             # 0 = illimité
		"vsync": true,
		"window_mode": "windowed", # windowed | fullscreen
		# 0 = taille automatique au démarrage (comportement historique).
		"window_width": 0,
		"window_height": 0,
		"fps_visible": true,
		"fps_details": true,       # ms + draw calls dans le compteur
		"fps_position": "status",  # status | top_right
		"fps_graph": true,         # graphe de frametime de l'aperçu
		"fps_warn_below": 45,
		"tooltip_delay": 0.45,
	},
	SECTION_RENDERING: {
		# `carte` = rendu décidé par la carte (défaut historique intact).
		"preset": "carte",         # carte | performance | equilibre | cinema
		"aa": "auto",              # auto | off | fxaa | msaa2 | msaa4 | msaa8
		"render_scale": 1.0,
		"shadow_quality": "map",   # map | off | low | medium | high
		"shadow_max_distance": 160.0,
		"ssao": true,
		"ssil": true,
		"glow": true,
		"volumetric_fog": true,
		"water_reflections": true,
	},
	SECTION_INTERFACE: {
		"theme": "or",             # or | jade (chrome de l'éditeur)
		"ui_scale": 100,           # 90 | 100 | 110 | 125 (%)
		"confirm_delete": false,
		"show_minimap": true,
		"show_hint_bar": true,
	},
}

## Échelles d'interface proposées (%).
const UI_SCALES := [90, 100, 110, 125]

const ThemeScript := preload("res://scripts/theme/cartographer_theme.gd")

## Presets globaux : chaque cran écrit les réglages fins ci-dessus.
## `carte` est le défaut : aucun réglage n'est surchargé (rendu historique
## strictement identique à la carte, condition des tests de non-régression).
const PRESETS := {
	"carte": {
		"aa": "auto", "render_scale": 1.0, "shadow_quality": "map",
		"ssao": true, "ssil": true, "glow": true,
		"volumetric_fog": true, "water_reflections": true,
	},
	"performance": {
		"aa": "off", "render_scale": 0.85, "shadow_quality": "off",
		"ssao": false, "ssil": false, "glow": false,
		"volumetric_fog": false, "water_reflections": false,
	},
	"equilibre": {
		"aa": "msaa2", "render_scale": 1.0, "shadow_quality": "medium",
		"ssao": true, "ssil": false, "glow": true,
		"volumetric_fog": false, "water_reflections": true,
	},
	"cinema": {
		"aa": "msaa4", "render_scale": 1.0, "shadow_quality": "high",
		"ssao": true, "ssil": true, "glow": true,
		"volumetric_fog": true, "water_reflections": true,
	},
}

const PRESET_LABELS := {
	"carte": "Carte",
	"performance": "Performance",
	"equilibre": "Équilibré",
	"cinema": "Cinéma",
}

## Niveaux d'anti-aliasing → (MSAA 3D, AA écran). `auto` = non surchargé.
const AA_LEVELS := {
	"auto": {"label": "Auto (carte)", "msaa": -1, "ssaa": -1},
	"off": {"label": "Aucun", "msaa": 0, "ssaa": 0},
	"fxaa": {"label": "FXAA", "msaa": 0, "ssaa": 1},
	"msaa2": {"label": "MSAA 2×", "msaa": 1, "ssaa": 0},
	"msaa4": {"label": "MSAA 4×", "msaa": 2, "ssaa": 0},
	"msaa8": {"label": "MSAA 8×", "msaa": 3, "ssaa": 0},
}

# ===========================================================================
# Raccourcis remappables
# ===========================================================================
# Le gestionnaire clavier de l'éditeur teste des keycodes en dur (`match`) et
# `ToolsScript.tool_for_shortcut()` pour les lettres d'outils. On n'y touche
# pas : `translate_key_event()` traduit une touche remappée vers la touche
# d'origine AVANT le match, et neutralise l'ancienne touche devenue libre.

const ACTION_GLOBAL_ACTIONS := [
	# Fichier & édition
	{"id": "undo", "label": "Annuler", "group": "Fichier & édition", "key": "Z", "ctrl": true},
	{"id": "redo", "label": "Rétablir", "group": "Fichier & édition", "key": "Y", "ctrl": true},
	{"id": "save", "label": "Enregistrer la carte", "group": "Fichier & édition", "key": "S", "ctrl": true},
	{"id": "copy", "label": "Copier la sélection", "group": "Fichier & édition", "key": "C", "ctrl": true},
	{"id": "cut", "label": "Couper la sélection", "group": "Fichier & édition", "key": "X", "ctrl": true},
	{"id": "paste", "label": "Coller", "group": "Fichier & édition", "key": "V", "ctrl": true},
	{"id": "duplicate", "label": "Dupliquer la sélection", "group": "Fichier & édition", "key": "D", "ctrl": true},
	{"id": "select_all", "label": "Tout sélectionner", "group": "Fichier & édition", "key": "A", "ctrl": true},
	{"id": "invert", "label": "Inverser la sélection", "group": "Fichier & édition", "key": "I", "ctrl": true},
	{"id": "group", "label": "Grouper", "group": "Fichier & édition", "key": "G", "ctrl": true},
	{"id": "ungroup", "label": "Dégrouper", "group": "Fichier & édition", "key": "G", "ctrl": true, "shift": true},
	{"id": "delete", "label": "Supprimer la sélection", "group": "Fichier & édition", "key": "Delete"},
	{"id": "search_asset", "label": "Rechercher un asset", "group": "Fichier & édition", "key": "K", "ctrl": true},
	# Affichage & fenêtre
	{"id": "toggle_ui", "label": "Masquer les panneaux", "group": "Affichage & fenêtre", "key": "Tab"},
	{"id": "immersive", "label": "Mode immersion", "group": "Affichage & fenêtre", "key": "Tab", "shift": true},
	{"id": "fullscreen", "label": "Plein écran", "group": "Affichage & fenêtre", "key": "F11"},
	{"id": "settings", "label": "Ouvrir les paramètres", "group": "Affichage & fenêtre", "key": "F10"},
	{"id": "recenter", "label": "Recentrer la carte", "group": "Affichage & fenêtre", "key": "Home"},
	{"id": "palette_lib", "label": "Dock bibliothèque", "group": "Affichage & fenêtre", "key": "B"},
	{"id": "palette_right", "label": "Dock inspecteur / calques", "group": "Affichage & fenêtre", "key": "N"},
	{"id": "palette_opts", "label": "Options de l'outil actif", "group": "Affichage & fenêtre", "key": "S"},
	{"id": "tool_flyout", "label": "Plus d'outils", "group": "Affichage & fenêtre", "key": "A"},
	{"id": "tab_inspector", "label": "Onglet Inspecteur", "group": "Affichage & fenêtre", "key": "I"},
	{"id": "tab_layers", "label": "Onglet Calques", "group": "Affichage & fenêtre", "key": "L"},
	{"id": "tab_map", "label": "Onglet Carte", "group": "Affichage & fenêtre", "key": "C"},
	{"id": "layer_up", "label": "Avancer d'un rang", "group": "Affichage & fenêtre", "key": "PageUp"},
	{"id": "layer_down", "label": "Reculer d'un rang", "group": "Affichage & fenêtre", "key": "PageDown"},
]

const ACTION_GROUP_TOOLS := "Outils"

## Noms de touches spéciales (le reste passe par `OS.find_keycode_from_string`).
const NAMED_KEYCODES := {
	"TAB": KEY_TAB, "HOME": KEY_HOME, "PAGEUP": KEY_PAGEUP, "PAGEDOWN": KEY_PAGEDOWN,
	"DELETE": KEY_DELETE, "ESCAPE": KEY_ESCAPE, "SPACE": KEY_SPACE, "ENTER": KEY_ENTER,
	"BACKSPACE": KEY_BACKSPACE, "INSERT": KEY_INSERT,
	"F1": KEY_F1, "F2": KEY_F2, "F3": KEY_F3, "F4": KEY_F4, "F5": KEY_F5,
	"F6": KEY_F6, "F7": KEY_F7, "F8": KEY_F8, "F9": KEY_F9, "F10": KEY_F10,
	"F11": KEY_F11, "F12": KEY_F12,
	"LEFT": KEY_LEFT, "RIGHT": KEY_RIGHT, "UP": KEY_UP, "DOWN": KEY_DOWN,
}

## Touches qu'on refuse d'attribuer : elles pilotent l'interface elle-même.
const RESERVED_KEYCODES := [KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]

## Combinaisons déjà gérées par l'éditeur sans passer par la table d'actions.
const RESERVED_COMBOS := [
	{"keycode": KEY_Z, "ctrl": true, "shift": true},   # rétablir (alias)
	{"keycode": KEY_BACKSPACE, "ctrl": false, "shift": false}, # supprimer (alias)
]

# ===========================================================================
# État
# ===========================================================================

var _values: Dictionary = {}
var _key_overrides: Dictionary = {}       # action_id -> binding Dictionary

var _action_defs: Dictionary = {}         # action_id -> {label, group, default}
var _action_order: Array = []             # ids, ordre d'affichage
var _effective: Dictionary = {}           # action_id -> binding courant
var _override_target: Dictionary = {}     # slot( nouvelle touche ) -> binding canonique
var _blocked_slots: Dictionary = {}       # slot( ancienne touche ) -> true
var _key_cache_dirty: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	_apply_display_settings()
	_apply_interface_settings()
	_apply_window_mode_if_needed()
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.4
	_save_timer.timeout.connect(_flush_save)
	add_child(_save_timer)

var _save_timer: Timer = null
var _save_dirty: bool = false

## Écriture différée : un curseur qui glisse ne réécrit pas le .cfg à 60 Hz.
func request_save(delay: float = 0.4) -> void:
	_save_dirty = true
	if _save_timer != null:
		_save_timer.start(delay)
	else:
		save_settings()

func _flush_save() -> void:
	if _save_dirty:
		_save_dirty = false
		save_settings()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_flush_save()

# ===========================================================================
# Lecture / écriture des valeurs
# ===========================================================================

func get_value(section: String, key: String) -> Variant:
	var defaults: Dictionary = DEFAULTS.get(section, {})
	if _values.has(section) and (_values[section] as Dictionary).has(key):
		return (_values[section] as Dictionary)[key]
	return defaults.get(key, null)

func get_display(key: String) -> Variant:
	return get_value(SECTION_DISPLAY, key)

func get_rendering(key: String) -> Variant:
	return get_value(SECTION_RENDERING, key)

func get_interface(key: String) -> Variant:
	return get_value(SECTION_INTERFACE, key)

## Écrit une valeur, l'applique immédiatement et persiste. `apply` = false
## pour les écritures en lot (preset) qui appliquent une seule fois ensuite.
func set_value(section: String, key: String, value: Variant, apply: bool = true) -> void:
	if not _values.has(section):
		_values[section] = {}
	(_values[section] as Dictionary)[key] = value
	request_save()
	if apply:
		apply_section(section)

## Applique une section au système (fenêtre, moteur, interface).
func apply_section(section: String) -> void:
	match section:
		SECTION_DISPLAY:
			_apply_display_settings()
		SECTION_RENDERING:
			_apply_rendering_to_engines()
		SECTION_INTERFACE:
			_apply_interface_settings()
	settings_changed.emit(section)

## Thème (variante de palette) et taille de l'interface. Le thème est un état
## global de `CartographerTheme` ; l'échelle passe par le facteur du canvas
## racine (Godot : `content_scale_factor`), donc toute l'UI suit d'un coup.
func _apply_interface_settings() -> void:
	ThemeScript.set_active_variant(str(get_interface("theme")))
	var scale := float(get_interface("ui_scale")) / 100.0
	if absf(scale - 1.0) < 0.001:
		scale = 1.0
	var tree := get_tree()
	if tree != null and tree.root != null:
		tree.root.content_scale_factor = scale

## Variante de thème active (`or` / `jade`).
func theme_variant() -> String:
	return ThemeScript.normalize_variant(str(get_interface("theme")))

func load_settings() -> void:
	_values = {}
	for section in DEFAULTS.keys():
		_values[section] = (DEFAULTS[section] as Dictionary).duplicate(true)
	_key_overrides = {}
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		for section in DEFAULTS.keys():
			if not cfg.has_section(section):
				continue
			for key in (DEFAULTS[section] as Dictionary).keys():
				var default_value: Variant = (DEFAULTS[section] as Dictionary)[key]
				var saved: Variant = cfg.get_value(section, key, default_value)
				# Garde le type par défaut : un .cfg édité à la main ne doit pas
				# casser les castings (float vs int, bool vs string).
				match typeof(default_value):
					TYPE_BOOL:
						saved = bool(saved)
					TYPE_INT:
						saved = int(saved)
					TYPE_FLOAT:
						saved = float(saved)
					TYPE_STRING:
						saved = str(saved)
				(_values[section] as Dictionary)[key] = saved
		if cfg.has_section(SECTION_KEYS):
			for action_id in cfg.get_section_keys(SECTION_KEYS):
				var binding: Variant = cfg.get_value(SECTION_KEYS, action_id)
				var parsed := _binding_from_variant(binding)
				if not parsed.is_empty():
					_key_overrides[action_id] = parsed
	_key_cache_dirty = true
	_ensure_action_defs()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # conserve [ui] de LocaleSettings
	for section in DEFAULTS.keys():
		for key in (_values.get(section, {}) as Dictionary).keys():
			cfg.set_value(section, key, (_values[section] as Dictionary)[key])
	if cfg.has_section(SECTION_KEYS):
		cfg.erase_section(SECTION_KEYS)
	_ensure_action_defs()
	for action_id in _key_overrides.keys():
		var default_binding: Dictionary = (_action_defs[action_id]["default"] as Dictionary) \
			if _action_defs.has(action_id) else {}
		if _key_overrides[action_id] == default_binding:
			continue
		cfg.set_value(SECTION_KEYS, action_id, _key_overrides[action_id])
	cfg.save(SETTINGS_PATH)

## Réinitialise une section aux valeurs par défaut (et persiste).
func reset_section(section: String) -> void:
	if not DEFAULTS.has(section):
		return
	_values[section] = (DEFAULTS[section] as Dictionary).duplicate(true)
	if section == SECTION_KEYS:
		_key_overrides.clear()
		_key_cache_dirty = true
	save_settings()
	apply_section(section)

## Réinitialise tout (réglages + raccourcis) — action « danger » du menu.
func reset_all() -> void:
	_values = {}
	for section in DEFAULTS.keys():
		_values[section] = (DEFAULTS[section] as Dictionary).duplicate(true)
	_key_overrides.clear()
	_key_cache_dirty = true
	save_settings()
	for section in [SECTION_DISPLAY, SECTION_RENDERING, SECTION_INTERFACE]:
		apply_section(section)
	settings_changed.emit(SECTION_KEYS)

# ===========================================================================
# Application — fenêtre & boucle de rendu
# ===========================================================================

func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"

func _apply_display_settings() -> void:
	Engine.max_fps = maxi(0, int(get_display("max_fps")))
	if _is_headless():
		return
	var want_vsync := bool(get_display("vsync"))
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if want_vsync else DisplayServer.VSYNC_DISABLED)

## Applique le mode fenêtre **uniquement** au démarrage ou quand l'utilisateur
## change ce réglage (sinon un changement de limite FPS forcerait la fenêtre).
## La résolution mémorisée est appliquée ici, bornée à l'écran utilisable :
## un changement de moniteur ne peut pas rendre la fenêtre inatteignable.
func _apply_window_mode_if_needed() -> void:
	if _is_headless():
		return
	if str(get_display("window_mode")) == "fullscreen":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	var size := window_resolution()
	if size.x > 0 and size.y > 0:
		DisplayServer.window_set_size(clamp_to_screen(size))
		center_window()

## Résolution mémorisée dans les préférences (`(0, 0)` = automatique).
func window_resolution() -> Vector2i:
	return Vector2i(
		maxi(0, int(get_display("window_width"))),
		maxi(0, int(get_display("window_height"))))

## Borne une taille de fenêtre à l'espace utilisable de l'écran courant.
func clamp_to_screen(size: Vector2i) -> Vector2i:
	if _is_headless():
		return size
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if usable.size.x <= 0 or usable.size.y <= 0:
		return size
	return Vector2i(
		clampi(size.x, 640, usable.size.x),
		clampi(size.y, 400, usable.size.y))

## Centre la fenêtre sur l'écran courant (après un changement de résolution).
func center_window() -> void:
	if _is_headless():
		return
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	var size := DisplayServer.window_get_size()
	DisplayServer.window_set_position(usable.position + Vector2i(
		maxi(0, (usable.size.x - size.x) / 2),
		maxi(0, (usable.size.y - size.y) / 2)))

## Applique une résolution de fenêtre. `persist = false` sert à l'essai avant
## confirmation (le menu Paramètres restaure l'ancienne taille si refus).
## Passer une taille en fenêtré est nécessaire : le plein écran impose le mode
## natif du moniteur.
func set_window_resolution(width: int, height: int, persist: bool = true) -> void:
	if not _is_headless():
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if width > 0 and height > 0:
			DisplayServer.window_set_size(clamp_to_screen(Vector2i(width, height)))
			center_window()
	if persist:
		set_value(SECTION_DISPLAY, "window_width", maxi(0, width), false)
		set_value(SECTION_DISPLAY, "window_height", maxi(0, height), false)
		set_value(SECTION_DISPLAY, "window_mode", "windowed", true)

## Reflète le mode fenêtre courant (F11, etc.) dans les préférences.
func sync_window_mode_from_display() -> void:
	if _is_headless():
		return
	var mode := DisplayServer.window_get_mode()
	var value := "fullscreen" if mode == DisplayServer.WINDOW_MODE_FULLSCREEN else "windowed"
	if value != str(get_display("window_mode")):
		set_value(SECTION_DISPLAY, "window_mode", value)
		save_settings()

## Applique le délai d'infobulle (ProjectSettings lu à l'affichage des tooltips).
func apply_tooltip_delay() -> void:
	var delay := clampf(float(get_display("tooltip_delay")), 0.0, 3.0)
	ProjectSettings.set_setting("gui/timers/tooltip_delay_sec", delay)

func set_preset(preset_id: String) -> void:
	if not PRESETS.has(preset_id):
		return
	var values: Dictionary = (PRESETS[preset_id] as Dictionary).duplicate(true)
	for key in values.keys():
		set_value(SECTION_RENDERING, key, values[key], false)
	set_value(SECTION_RENDERING, "preset", preset_id, true)
	save_settings()

# ===========================================================================
# Application — moteur 3D (surcharges de confort machine)
# ===========================================================================

## Dictionnaire transmis à `ComplexMapEngine3D.set_global_overrides()`.
## Les sentinelles -1 (« auto ») et "map" (« comme la carte ») demandent au
## moteur de restituer exactement le rendu décidé par la carte : par défaut le
## rendu historique reste donc bit-à-bit identique.
func overrides_config() -> Dictionary:
	var out: Dictionary = {}
	var aa_id := str(get_rendering("aa"))
	if not AA_LEVELS.has(aa_id):
		aa_id = NEUTRAL_AA
	var aa: Dictionary = AA_LEVELS[aa_id]
	out["msaa"] = int(aa["msaa"])          # -1 = la carte décide
	out["screen_space_aa"] = int(aa["ssaa"])  # -1 = la carte décide
	out["render_scale"] = clampf(float(get_rendering("render_scale")), 0.5, 1.0)
	var shadow_quality := str(get_rendering("shadow_quality"))
	if shadow_quality.is_empty():
		shadow_quality = NEUTRAL_SHADOWS
	out["shadow_quality"] = shadow_quality
	out["shadow_max_distance"] = clampf(
		float(get_rendering("shadow_max_distance")), 60.0, 260.0)
	out["ssao"] = bool(get_rendering("ssao"))
	out["ssil"] = bool(get_rendering("ssil"))
	out["glow"] = bool(get_rendering("glow"))
	out["volumetric_fog"] = bool(get_rendering("volumetric_fog"))
	out["water_reflections"] = bool(get_rendering("water_reflections"))
	return out

## À appeler après chaque `engine.configure()` (voir `_sync_engine`).
func apply_to_engine(engine: Node) -> void:
	if engine == null or not is_instance_valid(engine):
		return
	if engine.has_method("set_global_overrides"):
		engine.call("set_global_overrides", overrides_config())

## Moteurs vivants enregistrés (l'éditeur et la session) : un changement de
## réglage s'applique à tous sans que le menu ait à les connaître.
var _engines: Array = []

func register_engine(engine: Node) -> void:
	if engine == null:
		return
	if not _engines.has(engine):
		_engines.append(engine)
		engine.tree_exiting.connect(func(): _engines.erase(engine), CONNECT_ONE_SHOT)
	apply_to_engine(engine)

func _apply_rendering_to_engines() -> void:
	var alive: Array = []
	for engine in _engines:
		if engine == null or not is_instance_valid(engine):
			continue
		alive.append(engine)
		apply_to_engine(engine)
	_engines = alive

# ===========================================================================
# Raccourcis : définition, traduction, remap
# ===========================================================================

func _ensure_action_defs() -> void:
	if not _action_defs.is_empty():
		return
	_action_defs.clear()
	_action_order.clear()
	for entry in ACTION_GLOBAL_ACTIONS:
		var def: Dictionary = entry
		var action_id := str(def["id"])
		var binding := _binding_from_parts(
			str(def.get("key", "")),
			bool(def.get("ctrl", false)),
			bool(def.get("alt", false)),
			bool(def.get("shift", false)))
		if binding.is_empty():
			continue
		_action_defs[action_id] = {
			"label": str(def["label"]),
			"group": str(def["group"]),
			"default": binding,
		}
		_action_order.append(action_id)
	# Raccourcis d'outils : une lettre / un chiffre par outil (catalogue pur).
	for tool_def in ToolsScript.DEFS:
		var shortcut := str((tool_def as Dictionary).get("shortcut", "")).strip_edges()
		if shortcut.is_empty():
			continue
		var binding := _binding_from_parts(shortcut, false, false, false)
		if binding.is_empty():
			continue
		var action_id := "tool:%s" % str((tool_def as Dictionary).get("id", ""))
		_action_defs[action_id] = {
			"label": "Outil · %s" % str((tool_def as Dictionary).get("label", action_id)),
			"group": ACTION_GROUP_TOOLS,
			"default": binding,
		}
		_action_order.append(action_id)

func _binding_from_parts(key_name: String, ctrl: bool, alt: bool, shift: bool) -> Dictionary:
	var keycode := _keycode_from_name(key_name)
	if keycode == 0:
		return {}
	return {"keycode": keycode, "ctrl": ctrl, "alt": alt, "shift": shift}

func _keycode_from_name(key_name: String) -> int:
	var upper := key_name.strip_edges().to_upper()
	if upper.is_empty():
		return 0
	if NAMED_KEYCODES.has(upper):
		return int(NAMED_KEYCODES[upper])
	if upper.length() == 1:
		return OS.find_keycode_from_string(upper)
	return OS.find_keycode_from_string(upper)

func _binding_from_variant(raw: Variant) -> Dictionary:
	if raw is Dictionary:
		var raw_dict: Dictionary = raw
		var keycode := int(raw_dict.get("keycode", 0))
		if keycode == 0:
			keycode = _keycode_from_name(str(raw_dict.get("key", "")))
		if keycode == 0:
			return {}
		return {
			"keycode": keycode,
			"ctrl": bool(raw_dict.get("ctrl", false)),
			"alt": bool(raw_dict.get("alt", false)),
			"shift": bool(raw_dict.get("shift", false)),
		}
	return {}

## Libellés lisibles des touches spéciales (affichage clavier).
const KEY_DISPLAY_NAMES := {
	KEY_TAB: "Tab", KEY_HOME: "Origine", KEY_PAGEUP: "Page ↑", KEY_PAGEDOWN: "Page ↓",
	KEY_DELETE: "Suppr", KEY_ESCAPE: "Échap", KEY_SPACE: "Espace", KEY_ENTER: "Entrée",
	KEY_BACKSPACE: "Retour", KEY_INSERT: "Inser",
	KEY_F1: "F1", KEY_F2: "F2", KEY_F3: "F3", KEY_F4: "F4", KEY_F5: "F5",
	KEY_F6: "F6", KEY_F7: "F7", KEY_F8: "F8", KEY_F9: "F9", KEY_F10: "F10",
	KEY_F11: "F11", KEY_F12: "F12",
	KEY_LEFT: "←", KEY_RIGHT: "→", KEY_UP: "↑", KEY_DOWN: "↓",
}

static func key_name(keycode: int) -> String:
	if KEY_DISPLAY_NAMES.has(keycode):
		return str(KEY_DISPLAY_NAMES[keycode])
	return OS.get_keycode_string(keycode)

## Libellé d'affichage d'une liaison : « Ctrl+Maj+Z », « F10 », « Page Up »…
static func binding_label(binding: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if bool(binding.get("ctrl", false)):
		parts.append("Ctrl")
	if bool(binding.get("alt", false)):
		parts.append("Alt")
	if bool(binding.get("shift", false)):
		parts.append("Maj")
	parts.append(key_name(int(binding.get("keycode", 0))))
	return "+".join(parts)

static func binding_from_event(event: InputEventKey) -> Dictionary:
	var keycode := event.keycode
	if keycode == 0:
		keycode = event.physical_keycode
	return {
		"keycode": keycode,
		"ctrl": event.ctrl_pressed,
		"alt": event.alt_pressed,
		"shift": event.shift_pressed,
	}

func _slot_key(binding: Dictionary) -> String:
	return "%d|%d|%d|%d" % [
		int(binding.get("keycode", 0)),
		1 if bool(binding.get("ctrl", false)) else 0,
		1 if bool(binding.get("alt", false)) else 0,
		1 if bool(binding.get("shift", false)) else 0,
	]

func _refresh_key_cache() -> void:
	_ensure_action_defs()
	_effective.clear()
	_override_target.clear()
	_blocked_slots.clear()
	for action_id in _action_order:
		var default_binding: Dictionary = _action_defs[action_id]["default"]
		var current: Dictionary = _key_overrides.get(action_id, default_binding)
		_effective[action_id] = current
		if current != default_binding:
			_override_target[_slot_key(current)] = default_binding
			_blocked_slots[_slot_key(default_binding)] = true
	# Une touche bloquée qui est aussi la nouvelle touche d'une autre action
	# garde la priorité au remap (sinon on ne pourrait échanger deux touches).
	for slot in _override_target.keys():
		_blocked_slots.erase(slot)
	_key_cache_dirty = false

## Traduit une touche remappée vers la touche d'origine attendue par l'éditeur.
## Retourne `null` si la touche doit être neutralisée (ancienne liaison).
func translate_key_event(event: InputEventKey) -> InputEventKey:
	if _key_cache_dirty:
		_refresh_key_cache()
	if _override_target.is_empty() and _blocked_slots.is_empty():
		return event
	var binding := binding_from_event(event)
	var slot := _slot_key(binding)
	if _override_target.has(slot):
		var canonical: Dictionary = _override_target[slot]
		var out := event.duplicate() as InputEventKey
		out.keycode = int(canonical.get("keycode", 0))
		out.physical_keycode = 0
		out.ctrl_pressed = bool(canonical.get("ctrl", false))
		out.alt_pressed = bool(canonical.get("alt", false))
		out.shift_pressed = bool(canonical.get("shift", false))
		return out
	if _blocked_slots.has(slot):
		return null
	return event

## Liaison courante d'une action (`{}` si l'action n'existe pas).
func binding_for(action_id: String) -> Dictionary:
	if _key_cache_dirty:
		_refresh_key_cache()
	return (_effective.get(action_id, {}) as Dictionary).duplicate(true)

func default_binding_for(action_id: String) -> Dictionary:
	_ensure_action_defs()
	if not _action_defs.has(action_id):
		return {}
	return (_action_defs[action_id]["default"] as Dictionary).duplicate(true)

## Raison du refus d'une liaison pour une action, ou "" si elle est libre.
func can_use_binding(action_id: String, binding: Dictionary) -> String:
	_ensure_action_defs()
	if binding.is_empty():
		return "Touche non reconnue."
	var keycode := int(binding["keycode"])
	if keycode in RESERVED_KEYCODES:
		return "%s est réservé par l'interface (Échap, Entrée, Espace)." % key_name(keycode)
	for combo in RESERVED_COMBOS:
		if int(combo["keycode"]) == keycode \
				and bool(combo["ctrl"]) == bool(binding.get("ctrl", false)) \
				and bool(combo["shift"]) == bool(binding.get("shift", false)):
			return "Combinaison déjà utilisée par l'éditeur."
	if _key_cache_dirty:
		_refresh_key_cache()
	var slot := _slot_key(binding)
	for other_id in _action_order:
		if other_id == action_id:
			continue
		if _slot_key(_effective[other_id]) == slot:
			return "Déjà utilisé par « %s »." % str(_action_defs[other_id]["label"])
	return ""

## Change la liaison d'une action. Retourne "" en cas de succès, sinon la raison.
func set_action_binding(action_id: String, binding: Dictionary) -> String:
	_ensure_action_defs()
	if not _action_defs.has(action_id):
		return "Action inconnue."
	if binding == default_binding_for(action_id):
		_key_overrides.erase(action_id)
	else:
		var reason := can_use_binding(action_id, binding)
		if not reason.is_empty():
			return reason
		_key_overrides[action_id] = binding
	_key_cache_dirty = true
	save_settings()
	settings_changed.emit(SECTION_KEYS)
	return ""

func reset_action_binding(action_id: String) -> void:
	_key_overrides.erase(action_id)
	_key_cache_dirty = true
	save_settings()
	settings_changed.emit(SECTION_KEYS)

func reset_keys() -> void:
	_key_overrides.clear()
	_key_cache_dirty = true
	save_settings()
	settings_changed.emit(SECTION_KEYS)

## Vrai si l'action a été personnalisée.
func is_action_remapped(action_id: String) -> bool:
	return _key_overrides.has(action_id)

## Actions remappables, dans l'ordre d'affichage :
## `[{id, label, group, default: {...}, binding: {...}, remapped: bool}]`
func actions_list() -> Array:
	_ensure_action_defs()
	if _key_cache_dirty:
		_refresh_key_cache()
	var out: Array = []
	for action_id in _action_order:
		var def: Dictionary = _action_defs[action_id]
		out.append({
			"id": action_id,
			"label": str(def["label"]),
			"group": str(def["group"]),
			"default": (def["default"] as Dictionary).duplicate(true),
			"binding": (_effective[action_id] as Dictionary).duplicate(true),
			"remapped": _key_overrides.has(action_id),
		})
	return out

## Libellé de raccourci d'un outil pour la palette ("" si non remappé).
func shortcut_label_for_tool(tool_id: String) -> String:
	var action_id := "tool:%s" % tool_id
	if not is_action_remapped(action_id):
		return ""
	return binding_label(binding_for(action_id))

# ===========================================================================
# Libellés d'interface
# ===========================================================================

func fps_position_label() -> String:
	return "Coin supérieur droit" if str(get_display("fps_position")) == "top_right" \
		else "Barre d'état"

func shadow_quality_label(quality_id: String = "") -> String:
	var id := quality_id if not quality_id.is_empty() else str(get_rendering("shadow_quality"))
	match id:
		"map":
			return "Comme la carte"
		"off":
			return "Désactivées"
		"low":
			return "Basses"
		"high":
			return "Hautes"
		_:
			return "Moyennes"
