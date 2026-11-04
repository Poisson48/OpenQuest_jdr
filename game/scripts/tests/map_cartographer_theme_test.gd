extends SceneTree

## Test autonome du thème « carte du cartographe ».
## Vérifie que CartographerTheme.build() produit un Theme non nul
## avec les couleurs de texte et le style de bouton attendus.
##
## Lancement : godot --headless --path game --script res://scripts/tests/map_cartographer_theme_test.gd

const CartographerThemeScript := preload("res://scripts/theme/cartographer_theme.gd")

var _failed: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame

	var t = CartographerThemeScript.build()
	_assert("build_returns_theme", t is Theme)
	_assert("build_not_null", t != null)

	if t is Theme:
		_assert(
			"label_font_color",
			t.get_color("font_color", "Label") == Color("#E1E8E8")
		)
		_assert(
			"button_font_pressed_color",
			t.get_color("font_pressed_color", "Button") == Color("#55D6BE")
		)

		var normal_sb = t.get_stylebox("normal", "Button")
		_assert("button_normal_is_styleboxflat", normal_sb is StyleBoxFlat)
		if normal_sb is StyleBoxFlat:
			_assert(
				"button_normal_bg_color",
				normal_sb.bg_color == Color("#2C363C")
			)

	if _failed:
		print("map_cartographer_theme_test:FAIL")
		quit(1)
		return
	print("map_cartographer_theme_test:PASS")
	quit(0)

# ===========================================================================

func _assert(test_name: String, condition: bool) -> void:
	if condition:
		print("  ok  - ", test_name)
		return
	_failed = true
	printerr("  FAIL - ", test_name)
