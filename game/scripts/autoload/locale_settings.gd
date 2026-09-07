extends Node

## Préférences de langue (FR / EN). Applique TranslationServer au démarrage.

signal locale_changed(locale: String)

const SETTINGS_PATH := "user://app_settings.cfg"
const DEFAULT_LOCALE := "fr"
const SUPPORTED_LOCALES := ["fr", "en"]

var locale: String = DEFAULT_LOCALE

func _ready() -> void:
	load_settings()
	apply_locale(locale, false)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		locale = DEFAULT_LOCALE
		return
	var saved := str(cfg.get_value("ui", "locale", DEFAULT_LOCALE))
	locale = saved if saved in SUPPORTED_LOCALES else DEFAULT_LOCALE

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # conserve d'autres sections si ajoutées plus tard
	cfg.set_value("ui", "locale", locale)
	cfg.save(SETTINGS_PATH)

func apply_locale(new_locale: String, persist: bool = true) -> void:
	if new_locale not in SUPPORTED_LOCALES:
		new_locale = DEFAULT_LOCALE
	locale = new_locale
	TranslationServer.set_locale(locale)
	if persist:
		save_settings()
	locale_changed.emit(locale)

func locale_display_name(code: String) -> String:
	match code:
		"fr":
			return "Français"
		"en":
			return "English"
		_:
			return code
