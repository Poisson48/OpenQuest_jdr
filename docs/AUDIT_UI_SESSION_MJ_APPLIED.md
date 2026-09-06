# Corrections appliquées — Audit UI session MJ (6 sept. 2026)

Source : audit Claude session MJ (branche `interface`).

## P0
- **P0-1** Dashboard viewport : plus aucun `ScrollContainer` de page — `MainLayout` ancré plein écran, `TopBand` + `MapPanel` en `EXPAND_FILL`.
- **P0-2** Panneau MJ non scrollable : `GmVBox` ancré dans un `GmClip` (`Control` clippé) qui remplit la colonne sous le groupe.
- **P0-3** Indicateurs de tour dans le cadre « action joueur » (le `StatusBar` séparé a été supprimé) + bordure dorée du panneau MJ si attente.
- **P0-4** Zoom carte uniquement avec **Ctrl+molette**.
- **P0-5** Plus d’append manuel après `add_log_entry` (dés / action / IA).

## P1 / P2 ciblés
- Journal : stick-to-bottom seulement si déjà en bas ; ratio Histoire 1.2.
- Groupe compact + initiale si pas de portrait.
- Ctrl+Entrée pour diffuser narration / PNJ.
- Case **Secret** pour jets MJ non publiés.
- Chrono depuis ouverture session.
- Confirmation Quitter / Clore ; libellés danger.
- Debug session conditionné à `OS.is_debug_build()`.
- Immersive chrome symétrique ; hints Ctrl+molette ; cases carte simple max 48 px.

---

> Obsolete depuis la reconstruction scene-first de la session (session.tscn + panels/*.tscn).
> Voir docs/SESSION_UI.md : session.gd et map_panel.gd n'existent plus.
