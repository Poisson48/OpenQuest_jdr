# Guide — carte 2.5D, monde de zones et éditeur

Ce guide décrit le parcours complet pour **créer un monde de cartes façon Dofus**
avec l'éditeur, poser des bâtiments 3D, peindre le terrain et **tester en
session**. Il suppose la branche `feat/carte-2.5d-editeur`.

## 1. Lancer les deux démos

```powershell
# Éditeur de démonstration (carte 2.5D + onglet Monde)
.\scripts\play-godot.ps1 res://scenes/debug/carte_25d_boot.tscn

# Session monde (7 zones reliées, figurines, carte du monde)
.\scripts\play-godot.ps1 res://scenes/debug/carte_25d_session_boot.tscn
```

La démo éditeur construit un monde de 7 zones (village, place, forêt avec
étang, taverne, donjon nocturne, camp enneigé, ruines sous la pluie) et l'ouvre
sur le village. Un **second monde** de démonstration (Île du Lac, Plage des
Brumes) est visible via le sélecteur de mondes de l'onglet Monde.

## 2. Créer et gérer un monde de zones

Onglet **Monde** (à droite, ou **⤢ Plein écran**) :

| Action | Effet |
|---|---|
| **＋ Zone** | crée une carte 2.5D de la taille choisie (nom + thème de départ : Vide, Village, Forêt, Ruines, Camp enneigé, Bord de mer, Lac — sols, relief, ambiance et quelques décors) et la pose sous le monde |
| **Glisser une zone** | change sa position `zoneX/zoneY` sur le plan |
| **Relier les bords** | détecte les voisins qui partagent un bord (offset en cases si tailles différentes) |
| **Lier…** | lien manuel : bord, zone cible, décalage |
| **Taille…** | redimensionne la carte de la zone (contenu conservé en haut à gauche) |
| **Dupliquer** | copie la zone sous elle-même |
| **Assigner…** | rattache une carte existante hors monde comme nouvelle zone |
| **Valider** | chevauchements, liens cassés, tailles incohérentes |
| **Ouvrir** / double-clic | ouvre la zone dans l'éditeur de carte |
| **▶ Tester** | lance une session sur le monde courant (2 héros placés) |

Les zones ont des **tailles libres** et chaque carte porte `worldId`,
`zoneX/zoneY/zoneW/zoneH` et `edges` (nord/sud/est/ouest).

## 3. Peindre le terrain

Onglet **Carte** :

- **Type de sol** : *Terrain 3D* (heightfield) ou *Fond illustré* (plat).
- **Eau (niveau)** : `-1` = aucune eau ; sinon hauteur du plan d'eau en cases.
  Creuse d'abord avec **⛰ Relief (U)**, puis règle le niveau.
- **Ambiance** : lucioles, poussière, feuilles, pluie ou neige (particules animées).
- **Style de rendu** : Carte 2.5D (défaut), Diorama, VTT 3D, Hybride DD2.

Outils terrain :

- **🟫 Sol (Y)** : peint herbe / terre-chemin / pierre-pavé / **neige** / **sable**.
- **⛰ Relief (U)** : monte, baisse, aplatit, lisse ; rayon et force réglables.
- Les cartes en terrain 3D ont une **jupe de falaise** et un **fond de plateau**
  dégradé : elles se lisent comme des îlots.

## 4. Poser bâtiments et décors 3D

**Biblio → 🧊 Objets 3D** (80 objets livrés) :

- **Recherche** + filtres **Tous / Bâtiments / Toits & façades / Personnages /
  Nature / Intérieurs / Mobilier**.
- Clique un objet → l'outil **Objet 3D** est armé → clique la carte.
- **＋ Importer un GLB…** : ajoute ton propre modèle (vignette automatique),
  sans Blender ni ligne de commande.
- **Aimantation aux bâtiments** (cochée par défaut) : un **toit** se pose sur le
  bâtiment le plus proche, une **façade** (porte, fenêtre, balcon, auvent) se
  place contre le **mur le plus proche du clic** (avant, arrière ou côté), le dos
  du module collé au nu du mur. Le fantôme sous le curseur montre la pose réelle.
- **Échelle** : champ dans les options pour le prochain objet, ou dans
  l'inspecteur pour la sélection (uniforme X/Y/Z). La poignée de coin
  redimensionne aussi en conservant les proportions.
- **Outil 🏗 Mur 3D** : glisse un tracé pour construire une **rangée de murs
  modulaires** (`mur.glb`) orientés et alignés au terrain, avec **hauteur
  réglable** ; les façades (porte, fenêtre, auvent) peuvent ensuite s'aimanter
  dessus. Base de construction libre façon Sims.
- **Outil 🏠 Pièce 3D** : glisse un rectangle pour fermer une pièce (4 murs qui
  se recouvrent aux angles), puis pose porte/fenêtre/auvent et un toit.
- **Outil 🛖 Toit 3D** : glisse un rectangle au-dessus de la pièce ; génère une
  grille de tuiles à la hauteur réglée, avec styles **Tuiles / Chaume / Croupe /
  Appentis**.
- **Outil ▦ Dallage** : glisse un rectangle à l'intérieur : sol au choix
  (**pierre, terre, herbe, sable, neige**), nivellement optionnel.
- **Outil 🚪 Porte 3D** : clique sur un mur 3D ; le mur est remplacé par deux
  montants laissant une ouverture, et une porte à auvent est insérée.
- **Outil 🏡 Maison rapide** : glisse un rectangle ; construit d'un coup murs,
  dallage, toit et porte au centre du mur avant.
- **Outil 🪟 Fenêtre 3D** : clique sur un mur ; pose une fenêtre à volets sur la
  façade extérieure (murs hauts recommandés).
- **Outil 🪑 Meubler** : clique dans une pièce ; pose un ensemble de mobilier
  (salle commune, chambre, comptoir, campement) aligné au sol.
- **Outil 🪵 Clôture** : glisse le long d'une limite ; pose une clôture
  modulaire (**barrière / clôture basse / palissade**) alignée au terrain.
  La démo du village montre une porte à auvent et une fenêtre à volets posées
  ainsi sur les maisons.
- Sélection : **Dimensions X/Y/Z** et **Rotation** dans l'inspecteur, ou poignées
  de coin / rotation sur la carte ; `R` pivote de 90°.
- Élévation réglable pour les modules posés librement.

Conventions des assets : 1 unité Blender = 1 case, origine au pied, avant `+Z`,
palette Valbois. Voir [BLENDER_PIPELINE.md](./BLENDER_PIPELINE.md).

## 5. Tester en session

- Dans l'éditeur, **Monde → ▶ Tester** : la session démarre sur le monde courant.
- Touche **M** (ou bouton **🌍** de la barre) : carte du monde (zones découvertes,
  aperçus des sols/bâtiments, « Vous êtes ici », voyage rapide par clic).
- **G** recentre la caméra sur le groupe (ou bouton **Groupe** dans la barre), **F** recadre toute la carte.
- **N** affiche/masque les noms flottants ; **C** affiche/masque la **mini-carte** (clic = recentrer la caméra).
- **+ / −** zooment ; **1-9** bascule entre les cartes/onglets.
- **H** ouvre l'**aide des raccourcis** de session (Échap pour fermer).
- **D** ou bouton **Pas** : outil Déplacer — clique une case pour y déplacer le personnage sélectionné (ou actif) ; le survol affiche un curseur sur la case visée. Une case déjà occupée par une figurine est refusée. Le pion du personnage actif est **sélectionné automatiquement** à l'ouverture d'une zone.
- Glisse un pion vers un **bord** de carte pour passer dans la zone voisine :
  fondu noir + nom de la zone, et **« Nouvelle zone découverte »** à la première
  visite. Les **sorties** de la zone sont aussi cliquables en haut à gauche.
- Les membres sans portrait sont rendus en **figurines 3D par classe**
  (aventurier, archère, mage, voleuse, prêtresse, garde, marchand, villageoise),
  avec leur **nom flottant** au-dessus et une **respiration discrète** ; les
  créatures (gobelin, squelette) par leur nom.
- La démo de session place aussi des **PNJ** (marchand, garde, villageois) et des
  **créatures** (gobelin en forêt, squelette au donjon) en figurines 3D nommées ;
  **cliquer un PNJ** affiche sa réplique dans une bulle (réplique de rôle, ou
  **dialogue personnalisé** porté par le token).

## 6. Sauvegarde et limites

- Sauvegarde : `Ctrl+S` (carte), politique de sauvegarde dans l'onglet Carte
  (manuelle / à chaque modification / périodique), export/import JSON.
- Le monde est regroupé par `worldId` ; les zones d'un même monde partagent le
  plan et les liens de bords.
- Limites connues : pas d'animation de personnages, pas de collisions 3D, eau
  non nagée, toits/façades non magnétisés aux formes complexes (approximation
  sur le bâtiment le plus proche).

## 7. Voir aussi

- [CARTE_25D.md](./CARTE_25D.md) — architecture et état du chantier.
- [MONDE_ZONES.md](./MONDE_ZONES.md) — modèle de zones, transitions, plan D1→D6.
- [MAP_EDITOR.md](./MAP_EDITOR.md) — référence exhaustive de l'éditeur.
- [BLENDER_PIPELINE.md](./BLENDER_PIPELINE.md) — fabrication des assets.
- Captures : [`carte_25d_mesh_demo.png`](./screenshots/carte_25d_mesh_demo.png),
  [`carte_25d_monde_plein_ecran.png`](./screenshots/carte_25d_monde_plein_ecran.png),
  [`carte_25d_etang.png`](./screenshots/carte_25d_etang.png),
  [`session_monde_25d.png`](./screenshots/session_monde_25d.png),
  [`session_carte_monde.png`](./screenshots/session_carte_monde.png).
