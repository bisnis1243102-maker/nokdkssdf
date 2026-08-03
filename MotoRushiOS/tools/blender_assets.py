"""Build MotoRush's 3D art in Blender and export it for SceneKit.

Everything here is modelled from primitives in code — there are no downloaded
meshes, textures or rigs — so the whole art set is reproducible with:

    blender --background --python tools/blender_assets.py

Output lands in MotoRush/Art as Wavefront OBJ + MTL, one file per animated
part, which SceneKit loads through ModelIO. Parts are split rather than shipped
as one hierarchy because the renderer drives them independently: the wheels sit
at their solved suspension positions, the fork slides with travel, and the
rider leans with weight transfer.

Axes are exported Y-up / -Z-forward to match SceneKit, with the bike's length
along +X, so the model lines up with the physics without a correction matrix.
"""

import bpy
import bmesh
import math
import os
import sys

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "MotoRush", "Art")


# ── helpers ────────────────────────────────────────────────────────────────

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, rgb, metallic=0.0, roughness=0.6):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
    # Viewport colour, which is what the Collada exporter carries over.
    mat.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    mat.metallic = metallic
    mat.roughness = roughness
    return mat


def shade(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = False
    return obj


def box(name, size, loc, rot=(0, 0, 0), mat=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    bpy.ops.object.transform_apply(scale=True)
    if mat:
        shade(o, mat)
    return o


def cyl(name, radius, depth, loc, rot=(0, 0, 0), verts=16, mat=None):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=verts,
                                        location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    if mat:
        shade(o, mat)
    return o


def sphere(name, radius, loc, mat=None, segments=16, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=loc,
                                         segments=segments, ring_count=rings)
    o = bpy.context.active_object
    o.name = name
    if mat:
        shade(o, mat)
    return o


def join(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o


def ground_origin(obj):
    """Move the mesh so the object stands on its own origin: centred in X/Y
    with its base at Z=0. Scenery is then placed by dropping it on the
    terrain height with no per-prop fudge factors."""
    # Bake any object-level rotation/scale into the mesh first, otherwise the
    # recentring happens in the wrong frame.
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    mesh = obj.data
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    cx = (min(xs) + max(xs)) / 2
    cy = (min(ys) + max(ys)) / 2
    mz = min(zs)
    for v in mesh.vertices:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= mz
    obj.location = (0, 0, 0)
    return obj


def empty(name, loc=(0, 0, 0)):
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=loc)
    o = bpy.context.active_object
    o.name = name
    return o


def export(filename, objects):
    """Write the given objects to OBJ+MTL in SceneKit's axis convention."""
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, filename)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.wm.obj_export(
        filepath=path,
        export_selected_objects=True,
        forward_axis='NEGATIVE_Z',
        up_axis='Y',
        apply_modifiers=True,
        export_materials=True,
        export_triangulated_mesh=True,
        export_normals=True,
        export_uv=False,
        path_mode='STRIP')
    print("wrote", path)


# ── bike ───────────────────────────────────────────────────────────────────
# Modelled in metres, wheelbase along +X, up is +Z (Blender), origin at the
# centre of mass so the Swift side can rotate it about the same point the
# physics does.

def build_wheel(name, radius=0.33, width=0.11):
    rubber = material(name + "_Rubber", (0.05, 0.05, 0.06), 0.0, 0.85)
    metal = material(name + "_Rim", (0.78, 0.80, 0.84), 0.9, 0.25)
    disc = material(name + "_Disc", (0.55, 0.57, 0.60), 0.8, 0.35)

    parts = []
    tyre = cyl(name + "_tyre", radius, width, (0, 0, 0), rot=(math.pi / 2, 0, 0), verts=24)
    shade(tyre, rubber)
    parts.append(tyre)

    # Knobs, so the tyre reads as a proper MX carcass when it spins.
    for i in range(12):
        a = (i / 12.0) * math.tau
        k = box(name + "_knob%d" % i, (0.055, width * 1.05, 0.05),
                (math.cos(a) * radius, 0, math.sin(a) * radius),
                rot=(0, -a, 0))
        shade(k, rubber)
        parts.append(k)

    rim = cyl(name + "_rim", radius * 0.66, width * 0.55, (0, 0, 0),
              rot=(math.pi / 2, 0, 0), verts=20)
    shade(rim, metal)
    parts.append(rim)

    for i in range(8):
        a = (i / 8.0) * math.tau
        sp = box(name + "_spoke%d" % i, (radius * 0.62, 0.012, 0.012),
                 (math.cos(a) * radius * 0.33, 0, math.sin(a) * radius * 0.33),
                 rot=(0, -a, 0))
        shade(sp, metal)
        parts.append(sp)

    hub = cyl(name + "_hub", 0.055, width * 1.2, (0, 0, 0), rot=(math.pi / 2, 0, 0), verts=12)
    shade(hub, metal)
    parts.append(hub)

    brake = cyl(name + "_disc", radius * 0.42, 0.012, (0, width * 0.6, 0),
                rot=(math.pi / 2, 0, 0), verts=20)
    shade(brake, disc)
    parts.append(brake)

    return join(parts, name)


def build_bike():
    reset_scene()

    plastic = material("Plastic", (0.90, 0.24, 0.16), 0.05, 0.35)
    dark = material("DarkPlastic", (0.09, 0.10, 0.12), 0.1, 0.5)
    metal = material("Metal", (0.72, 0.74, 0.78), 0.95, 0.22)
    chrome = material("Chrome", (0.85, 0.86, 0.90), 1.0, 0.12)
    seat = material("Seat", (0.08, 0.08, 0.09), 0.0, 0.75)
    plate = material("Plate", (0.93, 0.94, 0.96), 0.0, 0.4)

    root = empty("Bike")

    frame_parts = []
    # Main spar and cradle.
    frame_parts.append(shade(box("spar", (0.86, 0.12, 0.09), (0.0, 0, 0.10), (0, -0.12, 0)), metal))
    frame_parts.append(shade(box("cradle", (0.60, 0.10, 0.07), (-0.10, 0, -0.14), (0, 0.18, 0)), metal))
    # Engine block.
    frame_parts.append(shade(box("engine", (0.34, 0.26, 0.28), (-0.02, 0, -0.06)), dark))
    frame_parts.append(shade(cyl("head", 0.10, 0.22, (0.10, 0, 0.06),
                                 rot=(math.pi / 2, 0, 0), verts=12), metal))
    # Tank and shrouds.
    frame_parts.append(shade(box("tank", (0.40, 0.26, 0.20), (0.16, 0, 0.26), (0, -0.06, 0)), plastic))
    frame_parts.append(shade(box("shroudL", (0.30, 0.05, 0.22), (0.20, 0.14, 0.22), (0.12, -0.1, 0)), plastic))
    frame_parts.append(shade(box("shroudR", (0.30, 0.05, 0.22), (0.20, -0.14, 0.22), (-0.12, -0.1, 0)), plastic))
    # Seat and rear fender.
    frame_parts.append(shade(box("seatpad", (0.52, 0.16, 0.09), (-0.24, 0, 0.30), (0, -0.05, 0)), seat))
    frame_parts.append(shade(box("rearfender", (0.34, 0.20, 0.05), (-0.52, 0, 0.30), (0, -0.16, 0)), plastic))
    # Number plate at the rear, angled like a real side plate.
    frame_parts.append(shade(box("plateL", (0.24, 0.02, 0.18), (-0.40, 0.12, 0.16), (0.1, -0.1, 0)), plate))
    frame_parts.append(shade(box("plateR", (0.24, 0.02, 0.18), (-0.40, -0.12, 0.16), (-0.1, -0.1, 0)), plate))
    # Exhaust.
    frame_parts.append(shade(cyl("header", 0.035, 0.55, (0.02, 0.10, 0.02),
                                 rot=(0, math.pi / 2 - 0.25, 0.35), verts=10), chrome))
    frame_parts.append(shade(cyl("silencer", 0.055, 0.34, (-0.44, 0.13, 0.14),
                                 rot=(0, math.pi / 2 - 0.1, 0.1), verts=10), chrome))
    # Front fender + headlight shroud.
    frame_parts.append(shade(box("frontfender", (0.36, 0.18, 0.04), (0.60, 0, 0.16), (0, 0.12, 0)), plastic))
    frame = join(frame_parts, "Frame")
    frame.parent = root

    # Forks: a separate node so the Swift side can slide them with the
    # suspension travel.
    fork_parts = []
    fork_parts.append(shade(cyl("forkL", 0.032, 0.62, (0.0, 0.10, -0.05),
                                rot=(0, 0.22, 0), verts=10), chrome))
    fork_parts.append(shade(cyl("forkR", 0.032, 0.62, (0.0, -0.10, -0.05),
                                rot=(0, 0.22, 0), verts=10), chrome))
    fork_parts.append(shade(box("triple", (0.10, 0.26, 0.06), (0.06, 0, 0.26), (0, 0.22, 0)), metal))
    fork_parts.append(shade(cyl("bars", 0.018, 0.62, (0.02, 0, 0.34),
                                rot=(math.pi / 2, 0, 0), verts=8), dark))
    fork = join(fork_parts, "Fork")
    fork.parent = root

    swing_parts = []
    swing_parts.append(shade(box("armL", (0.58, 0.05, 0.07), (-0.28, 0.09, 0.0), (0, 0.06, 0)), metal))
    swing_parts.append(shade(box("armR", (0.58, 0.05, 0.07), (-0.28, -0.09, 0.0), (0, 0.06, 0)), metal))
    swing_parts.append(shade(cyl("shock", 0.030, 0.34, (-0.10, 0, 0.14),
                                 rot=(0, -0.5, 0), verts=8),
                             material("Shock", (0.85, 0.20, 0.20), 0.4, 0.3)))
    swing = join(swing_parts, "Swingarm")
    swing.parent = root

    wheel = build_wheel("Wheel")

    export("bike_frame.obj", [frame])
    export("bike_fork.obj", [fork])
    export("bike_swingarm.obj", [swing])
    export("bike_wheel.obj", [wheel])


# ── rider ──────────────────────────────────────────────────────────────────

def build_rider():
    reset_scene()

    jersey = material("Jersey", (0.13, 0.35, 0.92), 0.0, 0.55)
    pants = material("Pants", (0.10, 0.11, 0.14), 0.0, 0.6)
    boot = material("Boot", (0.06, 0.06, 0.07), 0.1, 0.5)
    helmet = material("Helmet", (0.95, 0.36, 0.15), 0.2, 0.25)
    visor = material("Visor", (0.35, 0.85, 0.65), 0.6, 0.1)
    skin = material("Glove", (0.15, 0.16, 0.18), 0.0, 0.6)

    root = empty("Rider")
    parts = []

    # Crouched attack position: torso forward, arms out to the bars, knees bent.
    parts.append(shade(box("torso", (0.30, 0.34, 0.42), (0.02, 0, 0.66), (0, 0.35, 0)), jersey))
    parts.append(shade(box("hips", (0.26, 0.32, 0.20), (-0.14, 0, 0.44)), pants))

    for side, y in (("L", 0.15), ("R", -0.15)):
        parts.append(shade(cyl("thigh" + side, 0.075, 0.36, (-0.06, y, 0.32),
                               rot=(0, 1.05, 0), verts=8), pants))
        parts.append(shade(cyl("shin" + side, 0.060, 0.34, (-0.12, y, 0.06),
                               rot=(0, -0.25, 0), verts=8), pants))
        parts.append(shade(box("boot" + side, (0.22, 0.11, 0.11), (-0.06, y, -0.08)), boot))
        parts.append(shade(cyl("upperarm" + side, 0.055, 0.32, (0.20, y * 1.05, 0.78),
                               rot=(0, 1.25, 0), verts=8), jersey))
        parts.append(shade(cyl("forearm" + side, 0.045, 0.30, (0.42, y * 1.15, 0.74),
                               rot=(0, 1.5, 0), verts=8), jersey))
        parts.append(shade(sphere("glove" + side, 0.055, (0.56, y * 1.2, 0.70), segments=10, rings=6), skin))

    parts.append(shade(cyl("neck", 0.06, 0.10, (0.14, 0, 0.90), verts=8), jersey))
    parts.append(shade(sphere("helmet", 0.135, (0.19, 0, 1.00), segments=18, rings=10), helmet))
    parts.append(shade(box("peak", (0.22, 0.20, 0.03), (0.34, 0, 1.06), (0, -0.25, 0)), helmet))
    parts.append(shade(box("goggles", (0.09, 0.24, 0.08), (0.29, 0, 1.00), (0, 0.1, 0)), visor))
    parts.append(shade(box("chinbar", (0.16, 0.16, 0.10), (0.29, 0, 0.92), (0, 0.2, 0)), helmet))

    rider = join(parts, "RiderBody")
    rider.parent = root

    export("rider.obj", [rider])


# ── scenery ────────────────────────────────────────────────────────────────

def build_props():
    reset_scene()

    bark = material("Bark", (0.24, 0.16, 0.10), 0.0, 0.8)
    leaf = material("Leaf", (0.20, 0.42, 0.18), 0.0, 0.7)
    hay = material("Hay", (0.78, 0.66, 0.34), 0.0, 0.8)
    cloth = material("Cloth", (0.90, 0.32, 0.20), 0.0, 0.6)
    pole = material("Pole", (0.80, 0.82, 0.86), 0.85, 0.3)
    steel = material("Steel", (0.55, 0.58, 0.62), 0.9, 0.35)

    # Tree
    t = [shade(cyl("trunk", 0.14, 2.2, (0, 0, 1.1), verts=8), bark)]
    for i, (r, z) in enumerate(((0.95, 2.2), (0.75, 2.9), (0.5, 3.5))):
        bpy.ops.mesh.primitive_cone_add(radius1=r, depth=1.2, vertices=10, location=(0, 0, z))
        c = bpy.context.active_object
        c.name = "canopy%d" % i
        t.append(shade(c, leaf))
    tree = join(t, "Tree")
    tree.location = (0, 0, 0)

    # Hay bale
    bale = shade(cyl("Bale", 0.45, 0.9, (6, 0, 0.45), rot=(0, math.pi / 2, 0), verts=12), hay)

    # Marker flag
    f = [shade(cyl("flagpole", 0.03, 1.6, (12, 0, 0.8), verts=6), pole)]
    f.append(shade(box("flagcloth", (0.5, 0.02, 0.32), (12.28, 0, 1.42)), cloth))
    flag = join(f, "Flag")

    # Start / finish gantry
    g = [shade(box("towerL", (0.22, 0.22, 5.0), (18, 4.2, 2.5)), steel)]
    g.append(shade(box("towerR", (0.22, 0.22, 5.0), (18, -4.2, 2.5)), steel))
    g.append(shade(box("span", (0.30, 9.0, 0.30), (18, 0, 5.0)), steel))
    g.append(shade(box("banner", (0.10, 8.4, 1.10), (18, 0, 4.3)), cloth))
    gantry = join(g, "Gantry")

    # Props are exported apart so each can be instanced and scattered.
    for o in (tree, bale, flag, gantry):
        ground_origin(o)
    export("prop_tree.obj", [tree])
    export("prop_bale.obj", [bale])
    export("prop_flag.obj", [flag])
    export("prop_gantry.obj", [gantry])


if __name__ == "__main__":
    build_bike()
    build_rider()
    build_props()
    print("MotoRush art build complete ->", OUT_DIR)
