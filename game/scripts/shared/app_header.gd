extends VBoxContainer

## En-tête partagé : eyebrow, titre, tagline et sélecteur de langue.
## Instancié en haut de chaque page pour garder une identité visuelle cohérente.

@onready var opt_language: OptionButton = %OptLanguage

var _updating_language_ui := false

func _ready() -> void:
	_setup_language_selector()
	LocaleSettings.locale_changed.connect(_on_locale_changed)

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
	get_tree().root.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
