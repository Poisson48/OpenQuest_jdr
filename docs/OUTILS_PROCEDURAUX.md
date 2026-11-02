# Outils procéduraux — aide-mémoire MJ

Ce document liste les outils de construction procédurale de l’éditeur de carte
2.5D et les gestes de base pour un MJ non graphiste.

## Principe

Aucun asset à modéliser : on dessine, on choisit un style et une graine, l’éditeur
génère la géométrie et le décor.

## Outils de tracé

| Outil | Geste | Résultat |
|---|---|---|
| 🪄 Mur procédural | clic-glisser libre | un seul mesh de mur continu, crête biseautée, styles pierre/chaux/bois |
| 🪵 Clôture procédurale | clic-glisser libre | poteaux + lisses en un mesh |
| 🛤 Chemin procédural | clic-glisser libre | ruban de chemin biseauté, largeur réglable |
| 🌀 Tracé organique | clic-glisser libre | modules orientés tangente (murs/clôtures/palissades) |
| 🌸 Zone fleurie | dessiner une zone | fleurs ou herbe du type choisi, densité/taille |
| 🍂 Décor contextuel | clic près d’un mur/chemin/berge | buissons, rochers, haies, roseaux, nénuphars |
| 🏘 Générer scène | clic | village, forêt ou camp complet |
| 🛖 Toit 3D | rectangle | toit modulaire (historique) |
| 🏠 Toit procédural | rectangle | deux pans ou croupe, tuiles/ardoise/chaume |
| 🪟 Fenêtre 3D | clic près d’un mur | fenêtre, y compris sur murs procéduraux |
| 🚪 Porte 3D | clic près d’un mur | porte + ouverture, y compris sur murs procéduraux |

## Construction de bâtiment

### Maison rapide
Option prête à l’emploi qui produit :

- murs ;
- dallage ;
- toit ;
- porte ;
- fenêtres automatiques (option) ;
- intérieur lié (option) ;
- sol aplati (option) ;
- étages 1–3.

### Pièce 3D
Le rectangle crée quatre murs lissés et des coins. Ajouter ensuite dallage,
ouvertures et toit.

### Empilement
Avec l’outil Objet 3D, l’option **Empilement automatique** pose l’objet au-dessus
d’un objet qui recouvre son emprise (table → lanterne). Un badge `↑` indique la
hauteur dans l’aperçu.

## Recettes rapides

### Village
1. Outil **🏘 Générer scène**.
2. Style **Village**, graine au choix.
3. Cliquer sur la carte.
4. Retoucher les maisons, ajouter fleurs/arbres.

### Camp
Même chose avec le style **Camp** : tentes, feu, tonneaux, bannière, charrette.

### Forêt
Style **Forêt** : clairière, chemin, arbres, rochers.

### Jardin
1. Zone fleurie type marguerites/camp.
2. Décor contextuel près des murs.
3. Chemin procédural ou peint.

### Enclos
1. Clôture procédurale.
2. Porte 3D si nécessaire.
3. Décor contextuel le long des clôtures.

## Démos

```powershell
# Village généré
.\scripts\play-godot.ps1 res://scenes/debug/generated_village_demo.tscn

# Camp généré
.\scripts\play-godot.ps1 res://scenes/debug/generated_camp_demo.tscn

# Forêt générée
.\scripts\play-godot.ps1 res://scenes/debug/generated_forest_demo.tscn

# Toits procéduraux
.\scripts\play-godot.ps1 res://scenes/debug/procedural_roof_demo.tscn

# Construction complète
.\scripts\play-godot.ps1 res://scenes/debug/construction_demo.tscn
```

## Limites actuelles

- géométrie et assets encore low-poly ;
- pas encore de marche continue inter-zones ;
- ouvertures/toits sur emprises irrégulières à compléter ;
- LOD/profiling à pousser sur les très grandes cartes.
