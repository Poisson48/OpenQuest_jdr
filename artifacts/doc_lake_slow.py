from pathlib import Path

p = Path('docs/RAPPORT_QUALITE_CS2.md')
s = p.read_text(encoding='utf-8')
old = "canaux / plans d'eau polygonaux : `flow_dir` **par bassin** (coordonnées monde normalisées) + dérive calmée (`RIVER_FLOW_VISUAL_SCALE`, `LAKE_FLOW_VISUAL_SCALE`) — le motif suit le méandre ou l'axe du canal au lieu de défiler en +X à toute vitesse. Verrouillé par `water_bodies_test`"
new = "canaux / plans d'eau polygonaux : `flow_dir` **par bassin** (coordonnées monde normalisées) + dérive calmée (`RIVER_FLOW_VISUAL_SCALE` 0,10 ; canal 0,18 ; **lac 0,025 — il frémit à peine**) — le motif suit le méandre ou l'axe du canal au lieu de défiler en +X à toute vitesse. Verrouillé par `water_bodies_test` (`lake_barely_moves`)"
assert old in s, 'ligne dérive introuvable'
p.write_text(s.replace(old, new, 1), encoding='utf-8')
print('doc dérive : échelles lac/canal précisées')
