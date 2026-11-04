# Checklist test manuel — Végétation / Eau / Ambiance (éditeur 2.5D)

## Végétation
- [ ] Cocher « Végétation » sur une zone d'herbe → touffes, fleurs, buissons et feuilles mortes apparaissent, uniquement sur les cases d'herbe.
- [ ] Décocher « Végétation » → toute la végétation disparaît immédiatement, sans changer le sol.
- [ ] Peindre du sol non-herbe (roche/sable) près de l'herbe → aucune végétation sur ces cases.
- [ ] Densité végétation à 0 puis à 3 → 0 : rien ; 3 : peuplement nettement plus fourni, sans débordement hors cases d'herbe.
- [ ] Creuser au Relief (U) une zone sous le niveau d'eau → les cases immergées perdent leur végétation.
- [ ] Passer sur un preset nuit → végétation assombrie mais toujours lisible.

## Eau + décor
- [ ] Niveau d'eau à −1 → aucun plan d'eau n'est affiché.
- [ ] Creuser un creux avec U puis régler le niveau d'eau à 2 → un lac remplit uniquement les creux sous la hauteur 2, bords nets.
- [ ] Faire varier le niveau par pas de 0,5 → la ligne d'eau monte/baisse en direct, sans artefact ni scintillement.
- [ ] Densité du décor d'eau à 0 puis à 3 → 0 : aucune lentille ni nénuphar ; 3 : décor nettement plus dense.
- [ ] Changer la graine du décor → disposition des lentilles/nénuphars modifiée ; remettre la même graine → disposition identique (reproductible).
- [ ] Végétation + eau ensemble → aucune touffe ou fleur ne flotte sur l'eau.

## Ambiance
- [ ] Parcourir chaque effet (aucune, poussière, feuilles, pluie, neige, lucioles) → particules cohérentes (pluie fine et rapide, neige qui flotte, feuilles qui tombent, poussière lente).
- [ ] Changer d'effet à chaud → l'ancien effet est remplacé, sans particules résiduelles ni double effet.
- [ ] Effet « lucioles » en mode nuit → lucioles visibles et lumineuses ; effet adapté en mode jour.
- [ ] Tester les presets lumière → l'ambiance change immédiatement, eau et végétation restent correctement éclairées.
- [ ] Sauvegarder puis recharger la carte → ambiance, niveau d'eau, densités et graines restaurés à l'identique.

## Performance
- [ ] Carte grande (~100×100) avec densités végétation et décor d'eau à 3, déplacer la caméra → framerate fluide, sans saccade.
- [ ] Baisser les densités à 0,5 sur cette carte → FPS remonte, rendu restant correct.
- [ ] Enchaîner 10 changements rapides eau/végétation → pas de fuite mémoire ni d'accumulation de nœuds (Moniteur Godot).
- [ ] Zoom arrière maximal → toutes les couches restent rendues, sans disparition ni clignotement.
- [ ] Maintenir-glisser l'outil Relief (U) en continu → terrain mis à jour sans freeze, plan d'eau suit en temps réel.
