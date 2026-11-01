extends Node

# ---------------------------------------------------------------------------
# Palette « grimoire » — inspiration jeu de rôle sur table
# ---------------------------------------------------------------------------
# Encre indigo pour les fonds (parchemin encré), or antique pour l'accent
# principal, sceau de cire pour le danger, vert-de-gris pour la réussite,
# bleu arcanique pour l'enquête. Contraste plus marqué qu'une simple gamme
# brun/or, et chaque teinte a un rôle unique.

const BG_DARK: Color = Color("14111c")      # fond de page (encre)
const BG_CARD: Color = Color("221d2f")      # carte / panneau
const BG_INPUT: Color = Color("171320")     # champ de saisie
const BORDER: Color = Color("3c3252")       # bordure
const GOLD: Color = Color("c9a44c")         # or antique (accent)
const GOLD_LIGHT: Color = Color("f2d98a")   # or clair (titres)
const TEXT: Color = Color("f6eeda")         # parchemin
const TEXT_MUTED: Color = Color("c3b4a1")   # parchemin estompé
const DANGER: Color = Color("b23a48")       # sceau de cire
const SUCCESS: Color = Color("4e9e8a")      # vert-de-gris
const INVESTIGATION_ACCENT: Color = Color("8296d8")  # bleu arcanique
const ONESHOT_ACCENT: Color = Color("4e9e8a")
const BOT_ACCENT: Color = Color("8fd2ea")

# ---------------------------------------------------------------------------
# Jetons de session (console MJ)
# ---------------------------------------------------------------------------
# GOLD servait à la fois d'accent interactif et de signal « il faut agir ».
# Les deux rôles sont maintenant séparés : ACCENT pour la sélection et les
# éléments actifs, ALERT pour ce qui réclame l'attention du MJ.

const ACCENT: Color = GOLD
const ACCENT_LIGHT: Color = GOLD_LIGHT
const ALERT: Color = Color("d9743f")
const ALERT_SOFT: Color = Color("f0ae7a")

## Fonds : le parchemin sombre passe du plus profond (scène) au plus clair (carte).
const SURFACE_DEEP: Color = Color("0d0b12")
const SURFACE_DOCK: Color = Color("1b1726")
const SURFACE_RAISED: Color = Color("2b2440")
const HAIRLINE: Color = Color("2c2540")

# ---------------------------------------------------------------------------
# Typographie — 3 niveaux max pour les titres
# ---------------------------------------------------------------------------
const FONT_SIZE_H1: int = 24      # Titre de page
const FONT_SIZE_H2: int = 20      # Titre de section / panel
const FONT_SIZE_H3: int = 16      # Titre de sous-section
const FONT_SIZE_BODY: int = 16    # Texte courant
const FONT_SIZE_CAPTION: int = 14 # Légende, métadonnées
const FONT_SIZE_MICRO: int = 12   # Détails techniques

# ---------------------------------------------------------------------------
# Boutons — 3 hauteurs standard
# ---------------------------------------------------------------------------
const BTN_HEIGHT_CTA: int = 48       # Action principale (Lancer, Envoyer)
const BTN_HEIGHT_STANDARD: int = 40  # Action secondaire
const BTN_HEIGHT_COMPACT: int = 32   # Outil compact (dés, zoom)

# ---------------------------------------------------------------------------
# HUD joueur immersif — sorties du codage en dur des scènes
# ---------------------------------------------------------------------------
const HUD_TITLE: Color = Color("f6eeda")
const HUD_TURN: Color = Color("f2d98a")
const HUD_HERO_SUB: Color = Color("c3b4a1")
const HUD_HP: Color = Color("e06070")
const DANGER_SEP: Color = Color("5a2028")

## Couleurs d'auteur du journal — un rôle, une teinte.
const LOG_GM: Color = GOLD_LIGHT
const LOG_NPC: Color = Color("b9a0dc")
const LOG_PLAYER: Color = Color("8fcbb6")
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
