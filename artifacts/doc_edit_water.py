from pathlib import Path

# --- RAPPORT_QUALITE_CS2 : deux finitions d'édition -----------------------
p = Path('docs/RAPPORT_QUALITE_CS2.md')
s = p.read_text(encoding='utf-8')
anchor = '## Reste (pistes)'
assert anchor in s
section = '''## Édition fluide & outils eau visibles

- **Drag live incrémental** : déplacer / rotationner / redimensionner un objet
  ne reconstruit plus les couches 3D à chaque mouvement de souris (l'ancien
  `_sync_engine()` complet coûtait **2,3 s** sur la carte « Cité au fil de
  l'eau »). Les nœuds sont mis à jour sur place (`set_mesh_fields` →
  `_place_root`) : mesuré à **0,1 ms par mouvement**, sans rebuild
  (`editor_drag_perf_test`, y compris `move/rotate/resize_no_rebuild`).
- **Outils Eau explicites** : en plus de « Peindre l'eau », la palette expose
  désormais un groupe **Eau** avec **Rivière (tracé)** et **Lac / mare** ; le
  menu « Mode » reste synchronisé avec le bouton actif
  (`water_tools_ui_test`).

''' + anchor
p.write_text(s.replace(anchor, section, 1), encoding='utf-8')

# --- RAPPORT_SESSION : section 1.9 ----------------------------------------
p = Path('docs/RAPPORT_SESSION_CS2_CITE.md')
s = p.read_text(encoding='utf-8')
anchor = '\n---\n\n## 2. Preuves'
assert anchor in s
section = '''
### 1.9 Édition fluide & outils Eau

- **Freeze du drag supprimé** : chaque mouvement appelait `_sync_engine()`
  (rebuild complet des couches). Passage en mise à jour incrémentale des nœuds
  3D (position / rotation / échelle) : **2,3 s → 0,1 ms** par mouvement
  (carte cité HD), sans recréation de nœud. Test `editor_drag_perf_test`.
- **Rivière et Lac visibles** : ces modes étaient cachés dans le menu « Mode »
  de « Peindre l'eau » ; ils sont maintenant des outils de la palette, groupe
  **Eau** (`water_river`, `water_lake`), avec le mode synchronisé.
  Test `water_tools_ui_test`.
- Les contrôles ont été exécutés **en rendu réel (GPU, fenêtre cachée)** comme
  demandé, pas en headless.

''' + anchor
p.write_text(s.replace(anchor, section, 1), encoding='utf-8')
print('docs: édition fluide + outils eau documentés')
