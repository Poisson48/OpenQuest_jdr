extends Node

# Constantes de couleurs issues de css/style.css
const BG_DARK: Color = Color("1a1410")
const BG_CARD: Color = Color("2a2218")
const BG_INPUT: Color = Color("1e1812")
const BORDER: Color = Color("4a3c2a")
const GOLD: Color = Color("c9a227")
const GOLD_LIGHT: Color = Color("e8c547")
const TEXT: Color = Color("e8dcc8")
const TEXT_MUTED: Color = Color("9a8870")
const DANGER: Color = Color("cc4444")
const SUCCESS: Color = Color("44aa99")
const INVESTIGATION_ACCENT: Color = Color("788cc8")
const ONESHOT_ACCENT: Color = Color("4a9988")
const BOT_ACCENT: Color = Color("88ccff")

static func get_bbcode_color(c: Color) -> String:
	return c.to_html(false)
