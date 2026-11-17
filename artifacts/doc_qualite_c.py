from pathlib import Path

p = Path('docs/RAPPORT_QUALITE_CS2.md')
s = p.read_text(encoding='utf-8')
old = """**C — Bâti/décors HD + LOD (à faire)** : régénérer depuis les planches avec
`SIZE 160–256`, budget 6 000–12 000 tris, atlas 1024–2048 et contour conservé,
puis LOD (HD près / niveau actuel au loin). Le kit complet ne pèse que
191 072 tris aujourd'hui : la marge de performance est large."""
new = """**C — Bâti/décors HD + LOD (livré)** : deux verrous ont été levés dans le
pipeline (`reference_hull.py` + `build_reference_volumes.py`, désormais
paramétrables) :

1. **Géométrie** : reconstruction sur grille **128³** (au lieu de 64³) et budget
   porté à `max(700, min(6000, 3 × triangles_base))` → 12 000 tris avec contour
   pour les gros bâtiments (au lieu de 2 150–4 300).
2. **Texture** : fini le bake par îlots de 18 px qui « bouillait » — les UV sont
   maintenant des **UV de projection continus** (face ±Y → vue de face, ±X →
   côté, ±Z → dessus) directement dans l'atlas des 3 vues de la planche
   (résolution native). Les tuiles de toit, colombages, pierres, bannières et
   ouvertures restent **cohérents et nets sur tout le bâtiment** ; le GLB est
   plus léger qu'avec le bake (une image partagée au lieu d'un atlas par face).

LOD : l'import glTF Godot génère les niveaux de détail (`meshes/generate_lods`)
à partir du maillage HD ; les objets lointains sont simplifiés automatiquement.
Le kit complet reste sous ~1 M de triangles : largement dans le budget GPU."""
assert old in s, 'section C introuvable'
p.write_text(s.replace(old, new, 1), encoding='utf-8')
print('RAPPORT_QUALITE C mis à jour')
