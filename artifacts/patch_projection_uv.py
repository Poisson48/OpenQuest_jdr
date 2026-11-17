from pathlib import Path

p = Path('tools/blender/build_reference_volumes.py')
s = p.read_text(encoding='utf-8')

# --- 1) build_mesh : plus de cuisson par îlots ; géométrie seule ------------
start_marker = "    mesh.validate()\n    texture_atlas, glow_atlas = bake_projection("
end_marker = "    mesh.materials.append(material)\n    return obj\n"
start = s.find(start_marker)
end = s.find(end_marker, start)
assert start != -1 and end != -1, 'corps build_mesh introuvable'
end += len(end_marker)
new_body = '''    mesh.validate()
    for poly in mesh.polygons:
        poly.use_smooth = True
    return obj


def make_image_from_pixels(name, pixels):
    """Image Blender packée depuis un tableau RGB (lignes bas → haut)."""
    height, width = pixels.shape[:2]
    image = bpy.data.images.new(name, width=width, height=height, alpha=False)
    rgba = np.ones((height, width, 4), dtype=np.float32)
    rgba[..., :3] = np.clip(pixels, 0.0, 1.0)
    image.pixels.foreach_set(rgba.ravel())
    image.pack()
    return image


def flame_mask(pixels):
    """Masque de flamme (rouge/orangé) pour l'émission de la torche."""
    red, green, blue = pixels[..., 0], pixels[..., 1], pixels[..., 2]
    mask = np.clip((red - 0.62) * 5.0, 0.0, 1.0) * np.clip((green - blue - 0.06) * 6.0, 0.0, 1.0)
    return np.clip(mask, 0.0, 1.0)


def project_uvs(obj, atlas_path, inset=0.015):
    """UV de PROJECTION continue : la peinture de la planche reste cohérente
    sur les murs, toits et façades (au lieu d'îlots indépendants par face qui
    « bouillaient » la texture).

    Chaque boucle de face est projetée sur la vue dominante :
      • normale ±Y → vue de face   (X, Z) ;
      • normale ±X → vue de côté   (Y, Z) ;
      • normale ±Z → vue de dessus (X, Y).
    """
    mesh = obj.data
    low = Vector((min(v.co.x for v in mesh.vertices),
                  min(v.co.y for v in mesh.vertices),
                  min(v.co.z for v in mesh.vertices)))
    high = Vector((max(v.co.x for v in mesh.vertices),
                   max(v.co.y for v in mesh.vertices),
                   max(v.co.z for v in mesh.vertices)))
    span = Vector((max(high.x - low.x, 1e-4),
                   max(high.y - low.y, 1e-4),
                   max(high.z - low.z, 1e-4)))
    uv_layer = mesh.uv_layers.new(name="Reference")
    for poly in mesh.polygons:
        normal = poly.normal
        ax, ay, az = abs(normal.x), abs(normal.y), abs(normal.z)
        if az >= ax and az >= ay:
            view = 2
        elif ay >= ax:
            view = 0
        else:
            view = 1
        for loop_index in poly.loop_indices:
            co = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            x = (co.x - low.x) / span.x
            y = (co.y - low.y) / span.y
            z = (co.z - low.z) / span.z
            if view == 2:
                u_local, v_local = x, y
            elif view == 0:
                u_local, v_local = x, z
            else:
                u_local, v_local = y, z
            u = (view + inset + (1.0 - 2.0 * inset) * u_local) / 3.0
            v = inset + (1.0 - 2.0 * inset) * v_local
            uv_layer.data[loop_index].uv = (u, v)


def projection_material(name, atlas_path, glow=None, emission_strength=1.1):
    """Matériau projeté : la planche de référence EST la texture (aucun bake).

    L'atlas contient les 3 vues côte à côte ; les UV de projection pointent
    dedans. Résultat : peinture continue, nette à la résolution native des
    planches, GLB léger (une image partagée par tout l'objet).
    """
    source = bpy.data.images.load(str(atlas_path))
    source.pack()
    material = oq.make_material(f"{name}_projection", "#ffffff")
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    texture = material.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = source
    texture.extension = "EXTEND"
    material.node_tree.links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    if glow is not None:
        glow_image = make_image_from_pixels(f"{name}_lueur", glow)
        glow_node = material.node_tree.nodes.new("ShaderNodeTexImage")
        glow_node.image = glow_image
        glow_node.extension = "EXTEND"
        material.node_tree.links.new(glow_node.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    return material
'''
s = s[:start] + new_body + s[end:]

# --- 2) export_asset : UV de projection + matériau planche ------------------
old = '''    detail = DETAIL_BUILDERS.get(name)
    if detail:
        obj = oq.join_objects(detail(), name)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        oq.triangulate_mesh(obj)
    else:
        obj = build_mesh(name, args.input, entry, args)
    outline, bounds, floor = finish_mesh(obj, entry)
    nodes = [obj, outline]'''
new = '''    detail = DETAIL_BUILDERS.get(name)
    if detail:
        obj = oq.join_objects(detail(), name)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        oq.triangulate_mesh(obj)
    else:
        obj = build_mesh(name, args.input, entry, args)
    outline, bounds, floor = finish_mesh(obj, entry)
    if not detail:
        atlas_path = args.input / f"{name}_atlas.png"
        project_uvs(obj, atlas_path)
        source_pixels = read_projection(atlas_path) if name == "torche_murale" else None
        glow = flame_mask(source_pixels) * source_pixels if source_pixels is not None else None
        obj.data.materials.append(projection_material(name, atlas_path, glow=glow))
    nodes = [obj, outline]'''
assert old in s, 'export_asset bloc introuvable'
s = s.replace(old, new, 1)

p.write_text(s, encoding='utf-8')
print('build_reference_volumes : UV de projection continus OK')
