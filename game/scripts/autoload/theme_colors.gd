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

# ---------------------------------------------------------------------------
# Jetons de session (console MJ)
# ---------------------------------------------------------------------------
# GOLD servait à la fois d'accent interactif et de signal « il faut agir ».
# Les deux rôles sont maintenant séparés : ACCENT pour la sélection et les
# éléments actifs, ALERT pour ce qui réclame l'attention du MJ.

const ACCENT: Color = GOLD
const ACCENT_LIGHT: Color = GOLD_LIGHT
const ALERT: Color = Color("e07a3f")
const ALERT_SOFT: Color = Color("f0a870")

## Fonds : le parchemin sombre passe du plus profond (scène) au plus clair (carte).
const SURFACE_DEEP: Color = Color("140f0b")
const SURFACE_DOCK: Color = Color("221b13")
const SURFACE_RAISED: Color = Color("2f2618")
const HAIRLINE: Color = Color("3a2f21")

## Couleurs d'auteur du journal — un rôle, une teinte.
const LOG_GM: Color = GOLD_LIGHT
const LOG_NPC: Color = Color("b79bd8")
const LOG_PLAYER: Color = Color("8fc7b4")
const LOG_BOT: Color = BOT_ACCENT
const LOG_DICE: Color = ALERT_SOFT
const LOG_SYSTEM: Color = TEXT_MUTED

static func get_bbcode_color(c: Color) -> String:
	return c.to_html(false)

## Teinte de l'auteur d'une entrée de journal, par type.
static func log_color(entry_type: String) -> Color:
	match entry_type:
		"gm":
			return LOG_GM
		"npc":
			return LOG_NPC
		"bot":
			return LOG_BOT
		"dice":
			return LOG_DICE
		"system":
			return LOG_SYSTEM
		_:
			return LOG_PLAYER
