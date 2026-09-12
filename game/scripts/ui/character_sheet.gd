extends Control
class_name CharacterSheet

## Fiche personnage plein écran.
## Structure dans `scenes/session/panels/character_sheet.tscn`.
## Gauche : stats / histoire (scroll si besoin) · Droite : silhouette.

signal closed

const BARK_INTERVAL := 7.5

@onready var _dim: ColorRect = %Dim
@onready var _art: TextureRect = %Art
@onready var _name: Label = %LblName
@onready var _subtitle: Label = %LblSubtitle
@onready var _stats_page: ScrollContainer = %StatsPage
@onready var _story_page: VBoxContainer = %StoryPage
@onready var _story_scroll: ScrollContainer = %StoryScroll
@onready var _chip_hp = %ChipHP
@onready var _chip_ac = %ChipAC
@onready var _chip_mood = %ChipMood
@onready var _ability_str = %AbilitySTR
@onready var _ability_dex = %AbilityDEX
@onready var _ability_con = %AbilityCON
@onready var _ability_int = %AbilityINT
@onready var _ability_wis = %AbilityWIS
@onready var _ability_cha = %AbilityCHA
@onready var _traits: Label = %LblTraits
@onready var _inventory: Label = %LblInventory
@onready var _bark: Label = %LblBark
@onready var _story: Label = %LblStory
@onready var _quirk: Label = %LblQuirk
@onready var _story_btn: Button = %BtnStory

var _member: Dictionary = {}
var _showing_story: bool = false
var _bark_idx: int = 0
var _bark_timer: float = 0.0
var _last_story_wrap_w: float = -1.0
var _last_stats_wrap_w: float = -1.0

func _ready() -> void:
	visible = false
	set_process(false)
	%BtnClose.pressed.connect(close)
	_story_btn.pressed.connect(_toggle_story)
	_dim.gui_input.connect(_on_dim_input)

func open(member: Dictionary) -> void:
	if not is_node_ready():
		await ready
	_member = member.duplicate(true)
	_showing_story = false
	_bark_idx = randi() % maxi(1, _barks().size())
	_bark_timer = 0.0
	_last_story_wrap_w = -1.0
	_last_stats_wrap_w = -1.0
	_fill()
	_show_page()
	_load_art()
	visible = true
	set_process(true)
	move_to_front()
	call_deferred("_fit_story_wrap_width")
	call_deferred("_fit_stats_wrap_width")

func close() -> void:
	visible = false
	set_process(false)
	closed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and visible:
		_fit_story_wrap_width()
		_fit_stats_wrap_width()

func _process(delta: float) -> void:
	if not visible or _showing_story:
		return
	_bark_timer += delta
	if _bark_timer < BARK_INTERVAL:
		return
	_bark_timer = 0.0
	var lines := _barks()
	if lines.is_empty():
		return
	_bark_idx = (_bark_idx + 1) % lines.size()
	_bark.text = "« %s »" % lines[_bark_idx]
	_bark.modulate.a = 0.35
	var tw := create_tween()
	tw.tween_property(_bark, "modulate:a", 1.0, 0.45)

func _fill() -> void:
	_name.text = str(_member.get("name", "Aventurier")).to_upper()
	_subtitle.text = "%s  ·  %s" % [_member.get("race", "?"), _member.get("class", "?")]
	_chip_hp.setup("PV", str(_member.get("hp", 10)), ThemeColors.DANGER.lightened(0.25))
	_chip_ac.setup("CA", str(_member.get("ac", 10)), ThemeColors.INVESTIGATION_ACCENT)
	_chip_mood.setup("Humeur", str(_member.get("stress", "Calme")), ThemeColors.GOLD)
	var stats: Dictionary = _member.get("stats", {}) if _member.get("stats") is Dictionary else {}
	if stats.is_empty():
		stats = {"str": 10, "dex": 16, "con": 12, "int": 11, "wis": 13, "cha": 9}
	_ability_str.setup("FOR", int(stats.get("str", 10)))
	_ability_dex.setup("DEX", int(stats.get("dex", 10)))
	_ability_con.setup("CON", int(stats.get("con", 10)))
	_ability_int.setup("INT", int(stats.get("int", 10)))
	_ability_wis.setup("SAG", int(stats.get("wis", 10)))
	_ability_cha.setup("CHA", int(stats.get("cha", 10)))
	var temperament := str(_member.get("temperament", "Méfiant · Silencieux · Opportuniste"))
	_traits.text = temperament
	var inv_bits: Array[String] = []
	for it_variant in _member.get("inventory", []):
		if typeof(it_variant) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_variant
		var qty := int(it.get("qty", 1))
		var iname := str(it.get("name", it.get("id", "?")))
		inv_bits.append("• %s" % (iname if qty <= 1 else "%s ×%d" % [iname, qty]))
	if _inventory != null:
		_inventory.text = "Sac vide" if inv_bits.is_empty() else "\n".join(inv_bits)
	var lines: Array = _barks()
	var line: String = str(lines[_bark_idx % lines.size()]) if not lines.is_empty() else "…"
	_bark.text = "« %s »" % line
	_story.text = str(_member.get("backstory", "Aucune histoire écrite.")).strip_edges()
	_quirk.text = str(_member.get("quirk", "Surveille toujours les sorties."))

func _show_page() -> void:
	_stats_page.visible = not _showing_story
	_story_page.visible = _showing_story
	_story_btn.text = "← Fiche" if _showing_story else "Histoire ▸"
	# Remet le scroll en haut à chaque changement de page.
	if _showing_story:
		_story_scroll.scroll_vertical = 0
		call_deferred("_fit_story_wrap_width")
	else:
		_stats_page.scroll_vertical = 0
		call_deferred("_fit_stats_wrap_width")

func _fit_story_wrap_width() -> void:
	if _story_scroll == null or not is_instance_valid(_story_scroll):
		return
	var w := floorf(maxf(120.0, _story_scroll.size.x - 18.0))
	if is_equal_approx(w, _last_story_wrap_w):
		return
	_last_story_wrap_w = w
	_story.custom_minimum_size = Vector2(w, 0)
	_quirk.custom_minimum_size = Vector2(w, 0)
	var inner := _story_scroll.get_child(0) as Control
	if inner:
		inner.custom_minimum_size = Vector2(w, 0)

func _fit_stats_wrap_width() -> void:
	if _stats_page == null or not is_instance_valid(_stats_page):
		return
	var w := floorf(maxf(120.0, _stats_page.size.x - 18.0))
	if is_equal_approx(w, _last_stats_wrap_w):
		return
	_last_stats_wrap_w = w
	_traits.custom_minimum_size = Vector2(w, 0)
	_bark.custom_minimum_size = Vector2(w, 0)

func _toggle_story() -> void:
	_showing_story = not _showing_story
	_show_page()

func _load_art() -> void:
	var path := str(_member.get("portrait", _member.get("image", ""))).strip_edges()
	_art.texture = null
	if path.is_empty():
		return
	var cut := MapData.load_token_cutout(path, 320)
	if cut != null:
		_art.texture = cut
		_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return
	var tex := MapData.load_token_portrait(path, Color(0.1, 0.08, 0.06), 512)
	if tex != null:
		_art.texture = tex

func _barks() -> Array:
	var custom = _member.get("barks", [])
	if custom is Array and not custom.is_empty():
		return custom
	return [
		"Les ombres mentent rarement. Les hommes, toujours.",
		"Un regard de trop… je disparais.",
		"La fortune favorise les doigts agiles.",
	]

func _on_dim_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		close()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
