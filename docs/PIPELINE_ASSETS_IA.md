# Pipeline assets IA — recommandation qualité/prix

**Contexte** : OpenQuest 2.5D, assets low-poly, cible « diorama organique proche de Tiny Glade », pipeline Blender offline vers GLB + Godot.

**Date de vérification** : novembre 2026. Les prix peuvent changer ; vérifier avant abonnement.

---

## 1. Verdict rapide

### Meilleur rapport qualité/prix global

**Tripo AI — plan Professional annuel : ~13 $/mois** (20 $/mois sans engagement).

Pourquoi :
- génération **HD** et **Smart Mesh** low-poly ;
- **Smart UV** et **texturing PBR** intégrés ;
- **plugin Godot officiel** ;
- droits commerciaux sur les plans payants (modèle privé) ;
- 3 000 crédits/mois : ~200 modèles HD à 15 crédits, hors textures/UV.

C’est l’offre la plus complète et la moins chère pour produire des **assets de jeu** propres.

### Meilleur pour les textures

**Meshy — plan Pro : ~20 $/mois**.

Pourquoi :
- **AI Texturing** sur un mesh existant (pas seulement sur ses propres modèles) ;
- export **PBR** (albédo, normal, roughness, metallic) ;
- très bon pour retexturer des assets Blender ou des modèles low-poly maison ;
- plugin Blender.

### Combo optimal si le budget le permet

**Tripo Professional annuel + Meshy Pro = ~33 $/mois.**

- Tripo : géométrie, retopo, UV, base mesh propre ;
- Meshy : texturing PBR et variations ;
- **Adobe Materialize (gratuit)** : transformation d’images en matériaux PBR tuilables.

C’est le meilleur compromis qualité/prix pour un solo ou une petite équipe.

---

## 2. Comparatif

| Outil | Prix | Points forts | Limites | Usage recommandé |
|---|---:|---|---|---|
| **Tripo Professional** | 13 $/mois annuel, 20 $/mois mensuel | HD model, Smart Mesh low-poly, UV, PBR, plugin Godot, commercial | Texturing parfois moins fin que Meshy | Base de production |
| **Meshy Pro** | 20 $/mois | Excellent texturing PBR, image-to-3D, Blender plugin, grande communauté | Crédits plus chers pour les gros volumes | Textures et props |
| **Meshy Premium** | 40 $/mois | Plus de crédits, files prioritaires | Surdimensionné pour un solo | Si gros volume |
| **Rodin Creator** | 24 $/mois annuel, 30 $/mois | Très bonne géométrie, HD textures, Smart Low-Poly | Licence commerciale apparemment réservée à Business (96 $/mois) ; cher | À éviter pour l’instant |
| **Rodin Business** | 96 $/mois annuel | Licence commerciale, API, gros volume | Trop cher pour ce projet | Studio |
| **Adobe Materialize** | Gratuit | PBR à partir d’images, normal/roughness/AO, tuilable | Pas de génération 3D | Complément obligatoire |
| **Substance 3D Sampler** | ~23 $/mois | Matériaux PBR pro, filtres, export Godot | Payant, courbe d’apprentissage | Alternative à Materialize |
| **Hunyuan3D / TRELLIS local** | Gratuit | Génération locale | GPU NVIDIA confortable requis ; RX 5600 XT 6 Go limité | Expérimentation seulement |

Sources : [pricing Tripo](https://www.tripo3d.ai/product-doc/getting-started/pricing-credits), [pricing Meshy](https://www.meshy.ai/pricing), [coûts Meshy](https://costbench.com/software/ai-3d-generation/meshy/), [pricing Rodin](https://rodin3ds.com/pricing/).

---

## 3. Ce qu’il faut générer avec l’IA — et ce qu’il ne faut pas

### À générer avec l’IA
- props : tonneaux, charrettes, lanternes, outils, caisses, bannières ;
- végétation : buissons, arbres, roseaux, rochers, souches ;
- variations de matériaux : pierre, bois, tuiles, mousse ;
- textures PBR tuilables : herbe, terre, pierre, sable, neige ;
- icônes, portraits, illustrations de scènes.

### À garder en procédural / Blender
- murs, toits, clôtures, chemins : la topologie doit rester contrôlée ;
- bâtiments modulaires ;
- éléments qui doivent se raccorder au terrain ;
- collisions ;
- assets réutilisés des centaines de fois.

**Règle** : l’IA génère des **assets décoratifs et des textures**. La structure de carte reste procédurale pour rester éditable et fiable.

---

## 4. Pipeline recommandé

```text
1. Concept / prompt
   ↓
2. Tripo (image-to-3D ou text-to-3D)
   - géométrie HD
   - Smart Mesh low-poly
   - Smart UV
   ↓
3. Meshy (AI Texturing) ou Tripo Texture & PBR
   - albédo, normal, roughness, metallic, AO
   ↓
4. Blender
   - nettoyage topologie
   - échelle réelle, pivot au sol
   - suppression des faces inutiles
   - matériaux Godot
   ↓
5. Export GLB + textures 1024/2048
   ↓
6. Godot
   - import, LOD, collisions simples
   - matériau PBR
```

### Réglages de production
- polycount : 300–1 500 tris pour un prop, 2 000–6 000 pour un arbre ;
- textures : 1024×1024 pour les props, 2048 pour les héros ;
- pas de lumière bakée dans l’albédo ;
- UV sans chevauchement ;
- pivot au sol ;
- échelle en mètres, cohérente avec 1 case = 1 unité ;
- matériaux nommés `mat_<asset>_<partie>`.

---

## 5. Budget

### Option minimale
- Tripo Professional annuel : **156 $/an** (~13 $/mois) ;
- Materialize : gratuit ;
- Blender : gratuit.
- **Total : ~156 $/an.**

### Option qualité
- Tripo Professional annuel : ~156 $/an ;
- Meshy Pro : ~240 $/an ;
- Materialize : gratuit.
- **Total : ~396 $/an (~33 $/mois).**

### Option à éviter pour l’instant
- Rodin Creator : ~288 $/an, sans licence commerciale claire ;
- Rodin Business : ~1 152 $/an, surdimensionné.

---

## 6. Test avant abonnement

Faire un **benchmark de 10 assets** avec les deux outils :

1. un tonneau ;
2. une caisse ;
3. une lanterne ;
4. un rocher ;
5. un buisson ;
6. un arbre ;
7. un roseau ;
8. une palissade ;
9. une charrette ;
10. une texture de pierre.

Comparer :
- topologie ;
- propreté des UV ;
- qualité des textures PBR ;
- temps de nettoyage Blender ;
- coût en crédits ;
- licence.

Le gagnant est celui qui demande **le moins de retouches Blender**, pas celui qui génère la plus belle image.

---

## 7. Recommandation finale

Pour OpenQuest, je recommande :

1. **Tripo Professional annuel** comme outil principal de modélisation ;
2. **Meshy Pro** uniquement si les textures sont le point faible ;
3. **Materialize gratuit** pour les textures PBR tuilables ;
4. **Blender** pour le nettoyage final ;
5. **IA uniquement pour le décor et les textures** ; la structure de carte reste procédurale.

Le meilleur rapport qualité/prix absolu est **Tripo seul à 13 $/mois**.  
Le meilleur résultat visuel pour ce projet est **Tripo + Meshy à ~33 $/mois**.
