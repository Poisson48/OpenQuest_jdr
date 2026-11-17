from pathlib import Path

p = Path('docs/RAPPORT_QUALITE_CS2.md')
s = p.read_text(encoding='utf-8')
old = "| Dérive du motif **dans le sens du courant** | rivières : espace de dérive du ruban (UV : u en travers, v le long du tracé) remis à l'échelle monde (`flow_ribbon`) au lieu de l'UV2 monde fixe ; vitesse visuelle calmée (`RIVER_FLOW_VISUAL_SCALE`) — le motif suit les méandres au lieu de défiler dans une direction unique à toute vitesse | `demo_riviere_s.png` / `demo_riviere_s_detail.png` (démo rivière en S) |"
new = "| Dérive du motif **dans le sens du courant** | rivières : espace de dérive du ruban (UV : u en travers, v le long du tracé) remis à l'échelle monde (`flow_ribbon`) au lieu de l'UV2 monde fixe ; canaux / plans d'eau polygonaux : `flow_dir` **par bassin** (coordonnées monde normalisées) + dérive calmée (`RIVER_FLOW_VISUAL_SCALE`, `LAKE_FLOW_VISUAL_SCALE`) — le motif suit le méandre ou l'axe du canal au lieu de défiler en +X à toute vitesse. Verrouillé par `water_bodies_test` | `demo_riviere_s*.png`, `cite_eau_canal.png` |"
assert old in s, 'ligne dérive introuvable'
p.write_text(s.replace(old, new, 1), encoding='utf-8')
print('RAPPORT_QUALITE: ligne dérive courant mise à jour')
