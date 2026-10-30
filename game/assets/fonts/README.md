# Police Ringbearer

- **Fichier** : `ringbearer_medium.ttf` (nom interne « Ringbearer Medium »)
- **Auteur** : TheHutt — <thehutt@gmx.net>
- **Origine** : reconstitution de la police du logo de la trilogie *Le Seigneur des Anneaux*
  de Peter Jackson. Archive d'origine : `ringbearer.zip` (2002/2005), `readme.html` conservé ici.
- **Usage** : freeware, à but décoratif. Voir `ringbearer_readme.html`.

## Avertissement de l'auteur (traduit)

> « La police Ringbearer est destinée uniquement au design. L'utiliser pour de
> l'écriture courante n'apporterait pas grand-chose. En raison de sa vocation
> décorative, elle ne fonctionne pas dans les applications qui ne gèrent pas le
> crénage. En principe, il faut utiliser les **minuscules** ; les majuscules sont
> beaucoup plus décoratives et servent à marquer la première ou la dernière
> lettre d'un mot. »

## Couverture de glyphes (relevée avec `fc-query`)

```
20 30-39 41-5a 61-7a a9 ae c0-d6 d8-f6 f8-ff 106-107 10c-10d 111
11e-11f 130-131 141-142 152-153 15e-161 178 17d 20a3 2122
```

Présent : ASCII, chiffres, Latin-1 (dont `À Ç É È à ç é è ê ë î ï ô ù û ü`), `Œ œ`.

**Absent** (d'où la police de secours `ui_font.tres`) :

| Caractère | Usage dans l'app |
|-----------|------------------|
| `←` `→` | boutons « ← Retour » |
| `✕` | « ✕ Fermer » |
| `—` | tagline, séparateurs |
| `’` | apostrophes typographiques |
| `…` | ellipses |
| `·` | eyebrow « JEU DE RÔLE · SOLO & MULTIJOUEUR LOCAL » |
| `« »` | citations du journal |
| emojis | titres et boutons (`🗺️`, `📜`, `⚔️`…) |

## Intégration

`ui_font.tres` = `FontVariation` dont la police de base est Ringbearer et dont les
`fallbacks` pointent vers `SystemFont` (Noto Sans / DejaVu Sans) : les caractères
absents de Ringbearer sont donc rendus par la police système, sans tofu.

Le thème `game/theme/openquest_theme.tres` l'utilise comme `default_font`.
