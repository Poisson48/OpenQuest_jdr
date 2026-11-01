# UX de l'éditeur de cartes 2.5D

> Guide d'utilisation de l'interface de l'éditeur (`scenes/map_editor/map_editor.tscn`).
> Complète [GUIDE_CARTE_25D.md](./GUIDE_CARTE_25D.md) (parcours de création) et
> [MAP_EDITOR.md](./MAP_EDITOR.md) (référence exhaustive).

Ce document décrit **comment se repérer dans l'éditeur, retrouver les outils de
construction et éviter les erreurs courantes**. Il liste aussi les aides
ajoutées à l'inspecteur, à la mini-carte et aux panneaux.

---

## 1. Les trois colonnes

```
┌──────────────┬──────────────────────────────────┬─────────────────┐
│ PALETTE      │ BARRE D'ACTION + VUE 3D          │ PANNEAUX        │
│ outils       │ undo/save · aligner · zoom       │ Inspecteur      │
│ options      │                                  │ Calques         │
│ aimantation  │   carte 2.5D + overlay 2D        │ Carte           │
│ mini-carte   │                                  │ Biblio          │
│              │ ligne d'état + aide de l'outil   │ Historique      │
└──────────────┴──────────────────────────────────┴─────────────────┘
```

- **Palette (gauche)** : armée d'un clic ; l'outil reste actif jusqu'au suivant.
  Le bouton enfoncé indique l'outil courant. Les options de l'outil apparaissent
  juste en dessous, puis l'aimantation et la mini-carte.
- **Vue 3D (centre)** : se construit et s'édite à la souris. Sous la carte, la
  ligne d'état affiche la case, le nombre de sélections et l'outil ; la ligne
  d'aide rappelle le geste attendu.
- **Panneaux (droite)** : Inspecteur (objet sélectionné), Calques (arborescence),
  Carte (réglages), Biblio (décors, objets 3D, effets, templates), Historique
  (annuler/rétablir + raccourcis), Monde (zones).

---

## 2. Construire une maison en 30 secondes

La palette regroupe les outils de construction dans **Placer** (icônes dédiées,
sans raccourci clavier pour la plupart) :

| Étape | Outil | Geste |
|---|---|---|
| 1 | 🏠 **Pièce 3D** | Glisser un rectangle : 4 murs + coins |
| 2 | 🛖 **Toit 3D** | Glisser un rectangle au-dessus de la pièce |
| 3 | 🚪 **Porte 3D** | Cliquer sur un mur : ouverture + porte à auvent |
| 4 | 🪟 **Fenêtre 3D** | Cliquer sur un mur : fenêtre à volets |
| 5 | 🪑 **Meubler** | Cliquer dans la pièce : mobilier d'ambiance |
| — | 🏡 **Maison rapide** | Glisser un rectangle : murs + dallage + toit + porte d'un coup |

**Intérieur** : poser une **Porte 3D**, puis l'outil **Intérieur** (ou le bouton
« Créer / ouvrir l'intérieur » de l'inspecteur de la porte). Un lieu et une carte
intérieure reliée sont créés.

**Relief et eau** : ⛰ **Relief (U)** monte/abaisse le sol ; le niveau d'eau se
règle dans **Carte → Terrain & eau** (creuser d'abord, puis régler le niveau).

**Bâtiments du catalogue** : **Biblio → Objets 3D** ; cliquer un objet arme
l'outil 🧊 **Objet 3D**, puis cliquer la carte. L'aimantation (option de l'outil)
colle toits et façades au bâtiment le plus proche.

---

## 3. Savoir quel outil est actif

Trois retours visuels complémentaires :

1. le bouton de la palette reste **enfoncé** ;
2. la ligne d'aide sous la carte affiche **icône + nom + geste** de l'outil ;
3. l'**inspecteur vide** (aucune sélection) rappelle la liste des outils de
   construction et les gestes de navigation.

En cas de doute : `Échap` annule l'action en cours (tracé, déplacement, lien),
puis rouvre le menu éditeur. `V` revient à l'outil Sélection.

---

## 4. Inspecteur : que peut-on faire sans raccourci ?

L'inspecteur est contextuel. Pour **un** objet sélectionné :

- **⚡ Actions** : Recadrer (F), Dupliquer (Ctrl+D), Supprimer (Suppr),
  Premier plan / Arrière-plan, Grouper/Dégrouper, Verrouiller, « Même type ».
- **Identité** : nom, calque, état verrouillé/masqué.
- **📍 Position & taille** : coordonnées et empreinte en cases.
- **🎛 Apparence** : rotation, opacité, échelle, luminosité, miroirs, teinte.
- **Champs spécifiques** : token (portrait, vision), mur (hauteur, porte),
  lumière, décor, **objet 3D** (dimensions X/Y/Z, rotation ±90°, élévation,
  suivre le sol), **lieu** (catégorie, cartouche, carte enfant).
- **🏷 Organisation** : calque, verrou, masqué, notes MJ.
- **🔗 Liens** : créer un lien orienté, supprimer un lien existant.

Pour **plusieurs** objets : composition de la sélection (types + emprise),
actions groupées, alignement/distribution, application en lot de rotation,
opacité, teinte, calque, verrou, masqué, et liste cliquable pour recadrer.

> Les actions rapides appellent directement le document d'édition : elles
> passent donc par l'historique (Ctrl+Z) et ne nécessitent pas de connaître les
> raccourcis.

---

## 5. Navigation 3D et aide

| Geste | Effet |
|---|---|
| **Molette** | Zoomer / dézoomer |
| **Clic milieu maintenu** | Orbite 3D autour du point visé |
| **Maj + clic milieu** | Déplacer la vue (sans tourner) |
| **Espace maintenu** ou outil ✋ | Navigation temporaire à la souris |
| **F** | Recadrer sur la sélection |
| **Échap** | Annuler l'action ; sinon menu éditeur |
| **Clic droit** | Fermer un polygone ; sinon info de case |
| **Ctrl+Z / Ctrl+Y** | Annuler / rétablir |
| **Ctrl+S** | Enregistrer |

Tant qu'aucun objet n'est sélectionné, l'overlay affiche un **rappel discret en
bas à gauche** de ces gestes ; il disparaît dès la première sélection. Le
bouton **?** de la barre d'action ouvre l'aide complète ; le menu **☰ / Échap**
liste aussi les raccourcis (désormais défilables).

---

## 6. Retours visuels et prévention d'erreurs

- **Survol** : l'élément qui serait sélectionné est entouré et nommé ; un
  élément verrouillé est en **rouge avec 🔒**.
- **Hors carte** : la case limite la plus proche clignote en rouge avec
  « Hors carte » (sinon le clic serait ignoré silencieusement).
- **Tracés** : largeur × hauteur pour les rectangles, longueur en cases pour les
  lignes (murs, chemins, clôtures).
- **Sélection** : les poignées de coin ne s'affichent que pour les décors et
  objets 3D (les autres types ne sont pas redimensionnables à la souris).
- **Mini-carte** : bâtiments, murs et décors sont visibles ; la case survolée est
  mise en évidence ; le rectangle blanc représente la vue courante. Clic =
  recentrer.
- **Vérification** : le bouton **✓** de la barre d'action liste les problèmes
  (buffers de terrain, objets hors limites, assets manquants, eau sans
  dépression, liens cassés).

---

## 7. Onglet Carte (réglages)

Ordre de lecture : **Fond → Dimensions → Grille → Échelle → Brouillard →
Terrain & eau → Style de rendu → Perspective → Atmosphère → Éclairage →
Nuit → Affichage éditeur → Sauvegarde → Import/Export**.

Points utiles :

- **Terrain & eau** : type de sol (terrain 3D ou fond illustré), niveau d'eau
  (−1 = aucune) et ambiance animée (lucioles, pluie…). Ces trois réglages sont
  maintenant accompagnés d'une courte explication.
- **Style de rendu** : *Carte 2.5D* (défaut), *Diorama*, *VTT 3D*,
  *Hybride DD2*. Le style conditionne la caméra, les ombres, la grille et la
  pose des décors.
- **Grille** : surtout utile en VTT 3D ; en 2.5D/diorama, le fond illustré
  guide déjà l'œil (la case reste un repère de placement).
- **Sauvegarde** : manuelle (défaut), à chaque modification, ou périodique 30 s.
  La politique est aussi dans le menu Échap.

---

## 8. Limites connues et points d'attention

- **Reconstruction de l'inspecteur** : chaque modification d'une propriété
  reconstruit le panneau (comportement actuel de l'hôte d'UI). Conséquence :
  le défilement de l'inspecteur revient en haut après une modification et le
  sélecteur de couleur se referme. Contournement : régler les propriétés
  groupées, puis vérifier le résultat sur la carte.
- **Politique de sauvegarde** : l'onglet Carte et le menu Échap peuvent afficher
  un état différent jusqu'à la prochaine ouverture du menu ; c'est la politique
  réellement active (chips de la barre d'action) qui fait foi.
- **Raccourcis** : les touches à une lettre ne s'appliquent pas pendant la
  saisie dans un champ. Les outils de construction sans raccourci s'arment
  uniquement depuis la palette.
- **Collab édition** : hors scope (voir l'audit éditeur, P2 différé).
- **Performance mini-carte** : l'aperçu du sol dessine une case par cellule ;
  sur une très grande carte, la mini-carte peut ralentir légèrement.

---

## 9. Vérifications rapides (checklist)

1. Ouvrir une carte complexe : palette, vue 3D, inspecteur vide, mini-carte.
2. Glisser un rectangle de sélection : inspecteur multi avec actions et
   alignement.
3. Sélectionner un objet 3D : boutons Actions, dimensions, rotation ±90°.
4. Survoler un élément verrouillé : contour rouge + 🔒.
5. Glisser hors carte : avertissement « Hors carte ».
6. Tracer un mur : longueur affichée en cases.
7. Ouvrir Esc → tous les raccourcis sont visibles (scroll si nécessaire).
8. Carte → Terrain & eau : les listes déroulantes ont bien leurs libellés.
9. ✓ Vérifier la carte : rapport lisible, sans faux positif.
