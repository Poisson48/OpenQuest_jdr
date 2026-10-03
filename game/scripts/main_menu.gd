extends Control

const SavedGameRowScene := preload("res://scenes/hub/panels/saved_game_row.tscn")

@onready var home_page: VBoxContainer = %HomePage
@onready var ongoing_page: PanelContainer = %OngoingPage
@onready var play_status_lbl: Label = %PlayStatusLabel
@onready var saved_games_list: VBoxContainer = %SavedGamesList
@onready var opt_language: OptionButton = %OptLanguage

var _pending_delete_id: String = ""
var _updating_language_ui := false

const DISCORD_INVITE_URL := "https://discord.gg/nqYfxpbNC"

func _ready() -> void:
	%BtnOngoing.pressed.connect(_on_ongoing_pressed)
	%BtnDiscover.pressed.connect(_on_discover_pressed)
	%BtnDiscord.pressed.connect(_on_discord_pressed)
	%BtnBackHome.pressed.connect(_on_back_home_pressed)
	%BtnPlayNew.pressed.connect(_on_play_pressed)
	%ConfirmDeleteResume.confirmed.connect(_on_confirm_delete_resume)
	LocaleSettings.locale_changed.connect(_on_locale_changed)

	_setup_language_selector()
	_configure_pooling_dropdown(opt_language)
	_apply_static_translations()
	_show_home_page()
	_render_saved_games()
	_highlight_nav("home")

func _setup_language_selector() -> void:
	_updating_language_ui = true
	opt_language.clear()
	var selected := 0
	for i in LocaleSettings.SUPPORTED_LOCALES.size():
		var code: String = LocaleSettings.SUPPORTED_LOCALES[i]
		opt_language.add_item(LocaleSettings.locale_display_name(code), i)
		opt_language.set_item_metadata(i, code)
		if code == LocaleSettings.locale:
			selected = i
	opt_language.selected = selected
	if not opt_language.item_selected.is_connected(_on_language_selected):
		opt_language.item_selected.connect(_on_language_selected)
	_updating_language_ui = false

func _on_language_selected(idx: int) -> void:
	if _updating_language_ui:
		return
	var code := str(opt_language.get_item_metadata(idx))
	LocaleSettings.apply_locale(code)

func _on_locale_changed(_locale: String) -> void:
	_setup_language_selector()
	_apply_static_translations()
	_render_saved_games()
	get_tree().root.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)

func _apply_static_translations() -> void:
	%ConfirmDeleteResume.title = tr("Effacer la partie")
	%ConfirmDeleteResume.ok_button_text = tr("Effacer")
	%ConfirmDeleteResume.cancel_button_text = tr("Annuler")
	%ConfirmDeleteResume.dialog_text = tr("Effacer cette partie ? Toute la progression sera perdue.")

func _configure_pooling_dropdown(dropdown: OptionButton) -> void:
	dropdown.get_popup().popup_window = true

func _on_play_pressed() -> void:
	GameData.go_to_game_setup()

func _on_ongoing_pressed() -> void:
	_show_ongoing_page()
	_highlight_nav("ongoing")

func _on_back_home_pressed() -> void:
	_show_home_page()
	_highlight_nav("home")

func _on_discover_pressed() -> void:
	GameData.go_to_hub()

func _on_discord_pressed() -> void:
	if not _open_url_detached(DISCORD_INVITE_URL):
		push_warning("Impossible d'ouvrir l'invitation Discord.")

func _open_url_detached(url: String) -> bool:
	match OS.get_name():
		"Linux":
			var quoted := "'%s'" % url.replace("'", "'\\''")
			if FileAccess.file_exists("/usr/bin/gio"):
				if OS.create_process("/bin/sh", [
					"-c",
					"gio open %s >/dev/null 2>&1 &" % quoted,
				]) >= 0:
					return true
			return OS.create_process("/bin/sh", [
				"-c",
				"xdg-open %s >/dev/null 2>&1 &" % quoted,
			]) >= 0
		"macOS":
			return OS.create_process("open", [url]) >= 0
		"Windows":
			return OS.create_process("cmd", ["/C", "start", "", url]) >= 0
		_:
			OS.shell_open(url)
			return true

func _show_home_page() -> void:
	home_page.visible = true
	ongoing_page.visible = false

func _show_ongoing_page() -> void:
	home_page.visible = false
	ongoing_page.visible = true
	_render_saved_games()

func _highlight_nav(which: String) -> void:
	var gold := ThemeColors.GOLD_LIGHT
	var muted := ThemeColors.TEXT_MUTED
	%BtnOngoing.add_theme_color_override("font_color", gold if which == "ongoing" else muted)

func _render_saved_games() -> void:
	for child in saved_games_list.get_children():
		child.queue_free()
	var games: Array = GameData.get_playing_games()
	if games.is_empty():
		play_status_lbl.text = tr("Aucune partie en cours")
		return
	play_status_lbl.text = tr("%d partie(s) en cours") % games.size()
	for game in games:
		saved_games_list.add_child(_make_saved_game_row(game))

func _make_saved_game_row(game: Dictionary) -> PanelContainer:
	var row := SavedGameRowScene.instantiate()
	row.setup(game)
	row.resume_pressed.connect(_resume_game)
	row.delete_pressed.connect(_ask_delete_game)
	return row

func _resume_game(game_id: String) -> void:
	if not GameData.load_game_by_id(game_id):
		_render_saved_games()
		return
	get_tree().change_scene_to_file("res://scenes/session/session.tscn")

func _ask_delete_game(game_id: String, title: String) -> void:
	_pending_delete_id = game_id
	%ConfirmDeleteResume.dialog_text = tr("Effacer la partie « %s » ? Toute la progression sera perdue.") % title
	%ConfirmDeleteResume.popup_centered()

func _on_confirm_delete_resume() -> void:
	if _pending_delete_id.is_empty():
		return
	GameData.delete_game(_pending_delete_id)
	_pending_delete_id = ""
	_render_saved_games()