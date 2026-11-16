"""Modelage des pièces dont les éléments fins se masquent entre les vues."""

import math

from mathutils import Vector

import oq_common as oq


def bar(name, a, b, radius, material, vertices=8):
    a, b = Vector(a), Vector(b)
    axis = b - a
    return oq.add_cylinder(name, radius, axis.length, (a + b) / 2, material, vertices,
                           axis.to_track_quat("Z", "Y").to_euler())


def link(name, center, half_w, half_h, tube, turn, material):
    """Maillon ovalisé, chaque maillon pivote d'un quart de tour."""
    vertices, faces = [], []
    segments, sides = 20, 6
    for i in range(segments):
        angle = math.tau * i / segments
        across = Vector((math.cos(turn), math.sin(turn), 0))
        normal = Vector((-math.sin(turn), math.cos(turn), 0))
        up = Vector((0, 0, 1))
        radial = across * math.cos(angle) + up * math.sin(angle)
        origin = Vector(center) + across * (half_w * math.cos(angle)) + up * (half_h * math.sin(angle))
        for j in range(sides):
            angle_tube = math.tau * j / sides
            vertices.append(origin + tube * (radial * math.cos(angle_tube) + normal * math.sin(angle_tube)))
    for i in range(segments):
        for j in range(sides):
            a, b = i * sides, ((i + 1) % segments) * sides
            k = (j + 1) % sides
            faces.append((a + j, a + k, b + k, b + j))
    return oq.add_mesh(name, vertices, faces, material)


def chain():
    # Référence : platine losange, trois rivets et anneau de tirage ajouré.
    iron = oq.make_material("fer_patine", "#554c42")
    rubbed = oq.make_material("fer_lustre", "#776d60")
    plate = oq.add_box("platine_losange", (0.25, 0.055, 0.25), (0, 0.19, 1.53),
                       iron, (0, math.pi / 4, 0))
    parts = [plate]
    for x, z in [(0.0, 1.65), (-0.10, 1.53), (0.10, 1.53)]:
        parts.append(oq.add_ico_sphere("rivet", 0.026, (x, 0.15, z), rubbed))
    parts.append(link("attache", (0, 0.11, 1.44), 0.082, 0.082, 0.021, math.pi / 2, rubbed))
    for i in range(5):
        parts.append(link("maillon", (0, 0.068, 1.31 - i * 0.175),
                          0.067, 0.119, 0.021, i % 2 * math.pi / 2, iron if i % 2 else rubbed))
    parts.append(link("anneau_de_tirage", (0, 0.062, 0.365), 0.126, 0.15, 0.028, 0, rubbed))
    return parts


def lantern():
    # Référence : poteau à colliers, console triangulée et fanal hexagonal.
    oak = oq.make_material("chene_use", "#8c633e")
    iron = oq.make_material("fer_lanterne", "#443f38")
    brass = oq.make_material("rivets_laiton", "#a58357")
    glass = oq.make_material("verre_ambre", "#f1a934", emission="#ffae44", emission_strength=1.05)
    x = -0.29
    parts = [
        oq.add_box("poteau", (0.19, 0.19, 2.10), (x, 0, 1.05), oak),
        oq.add_cone("chapeau", 0.15, 0.16, (x, 0, 2.17), oak, vertices=4,
                    rotation=(0, 0, math.pi / 4)),
        oq.add_box("potence", (0.72, 0.16, 0.13), (-0.015, 0, 1.96), oak),
        bar("jambe_de_force", (x, 0, 1.48), (0.13, 0, 1.92), 0.052, oak, vertices=4),
        link("anneau", (0.24, 0, 1.77), 0.048, 0.063, 0.016, 0, iron),
        oq.add_cone("chapeau_fanal", 0.235, 0.19, (0.24, 0, 1.60), iron, vertices=6, radius2=0.08),
        oq.add_cylinder("lanterne_ambre", 0.173, 0.29, (0.24, 0, 1.36), glass, vertices=6),
        oq.add_cone("culot", 0.067, 0.12, (0.24, 0, 1.16), iron, vertices=6, radius2=0.22),
    ]
    for height in (0.27, 1.00, 1.96):
        parts.append(oq.add_box("collier", (0.222, 0.22, 0.105), (x, 0, height), iron))
        parts.append(oq.add_ico_sphere("rivet", 0.026, (x, -0.115, height), brass))
    for i in range(6):
        angle = math.tau * i / 6
        offset = Vector((math.cos(angle), math.sin(angle), 0)) * 0.178
        a = Vector((0.24, 0, 1.207)) + offset
        b = a + Vector((0, 0, 0.31))
        parts.append(bar("montant", a, b, 0.018, iron, vertices=5))
        for p in (a, b):
            parts.append(oq.add_ico_sphere("cabochon", 0.026, p, brass))
    return parts


def skeleton():
    # Référence : jambes écartées, côtes ouvertes, épée vers le sol et pagne.
    bone = oq.make_material("os_ivoire", "#c6b48d")
    old_bone = oq.make_material("os_patine", "#aa9570")
    leather = oq.make_material("cuir_dechire", "#735345")
    rust = oq.make_material("fer_rouille", "#826755")
    dark = oq.make_material("orbites", "#302a22")
    parts = []
    for sign in (-1, 1):
        hip = Vector((0.117 * sign, 0.018, 0.63))
        knee = Vector((0.16 * sign, -0.04, 0.34))
        ankle = Vector((0.197 * sign, 0.0, 0.07))
        shoulder = Vector((0.167 * sign, 0, 0.94))
        elbow = Vector((0.224 * sign, -0.01, 0.76))
        hand = Vector((0.25 * sign, -0.085, 0.60))
        for a, b, width in ((hip, knee, 0.036), (knee, ankle, 0.029),
                            (shoulder, elbow, 0.028), (elbow, hand, 0.023)):
            parts.append(bar("os_long", a, b, width, bone, 6))
        for joint in (knee, shoulder, elbow, hand):
            parts.append(oq.add_ico_sphere("articulation", 0.039, joint, old_bone))
        parts.append(oq.add_ico_sphere("pied", 0.065, (ankle.x, -0.062, 0.043),
                                      bone, subdivisions=2, scale=(0.72, 1.28, 0.64)))
    parts.append(bar("colonne", (0, 0.045, 0.58), (0, 0.027, 1.04), 0.027, old_bone))
    parts.append(oq.add_ico_sphere("bassin", 0.14, (0, 0.026, 0.61), old_bone,
                                  subdivisions=2, scale=(1, 0.61, 0.49)))
    for i in range(5):
        height = 0.72 + i * 0.045
        radius = 0.112 + 0.027 * math.sin(i * 0.55)
        for j in range(12):
            a, b = (math.tau * p / 12 for p in (j, j + 1))
            p = (radius * math.cos(a), 0.093 * math.sin(a), height + 0.014 * math.sin(a))
            q = (radius * math.cos(b), 0.093 * math.sin(b), height + 0.014 * math.sin(b))
            parts.append(bar("cote", p, q, 0.014, bone, 4))
    parts.append(oq.add_ico_sphere("crane", 0.108, (0, -0.026, 1.082), bone,
                                  subdivisions=2, scale=(0.85, 0.94, 1.0)))
    parts.append(oq.add_box("machoire", (0.123, 0.09, 0.044), (0, -0.07, 0.997), old_bone))
    for x in (-0.04, 0.04):
        parts.append(oq.add_ico_sphere("orbite", 0.029, (x, -0.108, 1.074), dark,
                                      scale=(1, 0.44, 0.85)))
    parts.append(oq.add_box("ceinture", (0.265, 0.17, 0.047), (0, 0.018, 0.595), leather))
    cloth = [(-0.115, -0.073, 0.585), (0.115, -0.073, 0.585),
             (0.053, -0.106, 0.427), (-0.011, -0.115, 0.38), (-0.077, -0.10, 0.466)]
    back = [(x, y + 0.022, z) for x, y, z in cloth]
    faces = [(0, 1, 2, 3, 4), (9, 8, 7, 6, 5)]
    faces.extend((i, i + 5, (i + 1) % 5 + 5, (i + 1) % 5) for i in range(5))
    parts.append(oq.add_mesh("pagne", cloth + back, faces, leather))
    parts.append(bar("poignee", (-0.253, -0.09, 0.625), (-0.273, -0.105, 0.527), 0.017, leather))
    parts.append(bar("garde", (-0.325, -0.093, 0.515), (-0.222, -0.111, 0.539), 0.013, rust))
    parts.append(oq.add_box("lame_rouillee", (0.058, 0.019, 0.397), (-0.318, -0.12, 0.322),
                            rust, (-0.07, 0.22, 0.05)))
    return parts


DETAIL_BUILDERS = {"chaine_murale": chain, "lanterne": lantern, "pnj_squelette": skeleton}
