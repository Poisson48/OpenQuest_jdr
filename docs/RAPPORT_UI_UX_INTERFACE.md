# Rapport UI/UX — Interface (hors cartes) — points ouverts

**Projet** : OpenQuest JDR — client Godot 4.7
**Branche** : `interface`
**Date** : 1er novembre 2026
**Périmètre** : menu, hub, éditeurs de contenu, configuration de partie, session MJ, HUD joueur, thème partagé
**Hors périmètre** : moteur de carte, éditeurs de carte, tokens, fog → voir `RAPPORT_UI_UX_CARTES.md`

> **Ce document ne contient que ce qui reste à faire.** Chaque point a été
> re-vérifié dans le code à la date du rapport. La liste actionnable est dans
> [TODO_UI_UX.md](TODO_UI_UX.md).

---

## Synthèse

L'interface est cohérente sur ses fondations : palette unique, une seule police,
une seule hauteur de bouton (48 px), une seule barre de navigation, poignées de
séparation et infobulles stylées, modales normalisées, raccourcis clavier partout.
Ce qui reste relève de la **dette de forme** (le style vit encore dans les
scènes) et de finitions d'usage.

| # | Point | Gravité | Effort |
|---|-------|---------|--------|
| 1 | 53 overrides de style encore en dur (219 au départ) | Moyen | Moyen |

---

## 1 · MOYEN — 53 overrides de style encore écrits en dur

**Où** : toutes les scènes de `game/scenes/`
**Constat** (comptage à date) :

| Type | Occurrences |
|------|-------------|
| `theme_override_font_sizes/font_size` | **34** |
| `theme_override_colors/font_color` | **19** |

Les valeurs sont alignées sur la palette (aucune teinte hors charte), mais elles
restent dupliquées dans les scènes : changer une couleur ou une taille demande
encore d'éditer les fichiers un par un, et le thème ne fait plus autorité.

**Fait** : 219 → 53 (la migration des 4 cartes sur `CardBase` a supprimé les overrides qu'elles portaient). Les 34 titres de section qui étaient des `HeadingLabel`
forcés à 14 px sont passés en `SectionLabel` (hiérarchie rétablie), et 59 couleurs
de palette ont été remplacées par trois variations dédiées (`MutedLabel`,
`GoldLabel`, `InvestigationLabel`).

**Action restante** : achever avec les variations du thème
(`TitleLabel`, `HeadingLabel`, `SectionLabel`, `CaptionLabel`, `BadgeLabel`,
`AccentButton`…), en commençant par les pages les plus stables (menu, hub).

---


---


---


---


---


---

## Ordre d'attaque suggéré

1. **§1 — overrides restants** (34 tailles + 19 couleurs)


---

*Rapport interface uniquement. Le périmètre cartes est couvert par `RAPPORT_UI_UX_CARTES.md`.*
