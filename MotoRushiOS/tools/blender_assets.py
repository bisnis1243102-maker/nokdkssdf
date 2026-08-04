"""Build MotoRush's 3D art in Blender and export it for SceneKit.

Everything here is modelled from primitives in code — there are no downloaded
meshes, textures or rigs — so the whole art set is reproducible with:

    blender --background --python tools/blender_assets.py

Output lands in MotoRush/Art as Wavefront OBJ + MTL, one file per animated
part, which SceneKit loads through ModelIO. Parts are split rather than shipped
as one hierarchy because the renderer drives them independently: the wheels sit
at their solved suspension positions, the fork slides with travel, and the
rider leans with weight transfer.

Everything is laid out around the anchors in `Rig` below, which are the same
numbers the Swift side uses, so the parts meet where they should:

    origin          centre of mass, level with the top of the engine
    axles           +/- wheelbase/2, AXLE_Z below the origin
    swing pivot     just behind the engine, where the swingarm hinges
    steering head   top of the fork, raked back like a real front end
    pegs / bars     where the rider's boots and hands attach

Axes here are Blender's (X forward, Z up); the exporter converts to SceneKit's
Y-up / -Z-forward on the way out.
"""

import bpy
import math
import os

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "MotoRush", "Art")


class Rig:
    WHEELBASE = 1.34
    WHEEL_R = 0.33
    AXLE_Z = -0.30
    REAR_AXLE = (-WHEELBASE / 2, 0.0, AXLE_Z)
    FRONT_AXLE = (WHEELBASE / 2, 0.0, AXLE_Z)
    SWING_PIVOT = (-0.10, 0.0, -0.16)
    HEAD = (0.50, 0.0, 0.22)          # steering head
    RAKE = math.radians(27)
    PEG = (-0.10, 0.21, -0.20)
    BAR = (0.44, 0.27, 0.36)
    SEAT_Z = 0.16


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
    mat.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    mat.metallic = metallic
    mat.roughness = roughness
    return mat


def shade(obj, mat, smooth=False):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for poly in obj.data.polygons:
        poly.use_smooth = smooth
    return obj


def bevel(obj, width=0.008, segments=2):
    """Soften every hard edge a little. Nothing man-made has a perfectly sharp
    corner, and the highlight along a bevel is most of what makes a shape read
    as solid rather than as a flat card."""
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    mod = obj.modifiers.new("bevel", 'BEVEL')
    mod.width = width
    mod.segments = segments
    mod.limit_method = 'ANGLE'
    mod.angle_limit = math.radians(40)
    bpy.ops.object.modifier_apply(modifier=mod.name)
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


def cyl(name, radius, depth, loc, rot=(0, 0, 0), verts=16, mat=None, smooth=True):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, vertices=verts,
                                        location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    if mat:
        shade(o, mat, smooth)
    return o


def cone(name, r1, r2, depth, loc, rot=(0, 0, 0), verts=12, mat=None):
    """Tapered segment — a straight tube reads as a broom handle."""
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=depth,
                                    vertices=verts, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    if mat:
        shade(o, mat, True)
    return o


def sphere(name, radius, loc, mat=None, segments=20, rings=12, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=loc,
                                         segments=segments, ring_count=rings)
    o = bpy.context.active_object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    if mat:
        shade(o, mat, True)
    return o


def tube_between(name, a, b, radius, mat, verts=10, taper=None):
    """A cylinder that spans two points — the honest way to make parts join up
    instead of guessing at rotations."""
    dx, dy, dz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length < 1e-6:
        length = 1e-6
    mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2)
    ry = math.acos(max(-1.0, min(1.0, dz / length)))
    rz = math.atan2(dy, dx)
    if taper is None:
        return cyl(name, radius, length, mid, rot=(0, ry, rz), verts=verts, mat=mat)
    return cone(name, radius, taper, length, mid, rot=(0, ry, rz), verts=verts, mat=mat)


def arc_panel(name, centre, radius, start, end, width, thickness, mat, steps=14):
    """A curved shell built as one swept mesh — a fender. Chaining rotated
    boxes leaves visible gaps at the joins however much they overlap, so this
    lays down the vertex ring directly and stitches quads between them."""
    verts = []
    faces = []
    half = width / 2
    for i in range(steps + 1):
        t = start + (end - start) * i / steps
        cx, cz = math.cos(t), math.sin(t)
        outer = radius + thickness
        # Four points per rib: inner/outer surface, near/far side.
        verts.append((centre[0] + cx * radius, centre[1] - half, centre[2] + cz * radius))
        verts.append((centre[0] + cx * radius, centre[1] + half, centre[2] + cz * radius))
        verts.append((centre[0] + cx * outer, centre[1] + half, centre[2] + cz * outer))
        verts.append((centre[0] + cx * outer, centre[1] - half, centre[2] + cz * outer))
    for i in range(steps):
        a = i * 4
        b = (i + 1) * 4
        faces.append((a, b, b + 1, a + 1))          # inner face
        faces.append((a + 3, a + 2, b + 2, b + 3))  # outer face
        faces.append((a + 1, b + 1, b + 2, a + 2))  # far edge
        faces.append((a, a + 3, b + 3, b))          # near edge
    # Cap the ends so the shell is a closed solid.
    faces.append((0, 1, 2, 3))
    last = steps * 4
    faces.append((last + 3, last + 2, last + 1, last))

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    shade(obj, mat)
    return [obj]


def blob(name, balls, mat, resolution=0.008, smooth=True, threshold=0.6):
    """Build a shape from metaballs and convert it to a mesh. Metaballs merge
    with a smooth fillet, which is the difference between a moulded shell and a
    sphere with boxes stuck on it — remeshing a union of primitives still
    leaves you with the silhouette of the primitives.

    `balls` is a list of (location, radius). Plain BALL elements are used
    deliberately: ELLIPSOID elements need their size and influence radius kept
    in step or they contribute no field at all and convert to an empty mesh.
    """
    bpy.ops.object.metaball_add(type='BALL', radius=balls[0][1], location=balls[0][0])
    obj = bpy.context.active_object
    obj.name = name + "_mball"
    mball = obj.data
    mball.resolution = resolution
    mball.render_resolution = resolution
    mball.threshold = threshold
    for (loc, radius) in balls[1:]:
        el = mball.elements.new(type='BALL')
        el.co = (loc[0] - balls[0][0][0], loc[1] - balls[0][0][1], loc[2] - balls[0][0][2])
        el.radius = radius
    bpy.context.view_layer.update()
    bpy.ops.object.convert(target='MESH')
    mesh_obj = bpy.context.active_object
    mesh_obj.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    shade(mesh_obj, mat, smooth)
    return mesh_obj


def fuse(objs, name, voxel=0.018, smooth=True):
    """Join parts that share a material and voxel-remesh them into a single
    continuous skin. Gluing primitives together always reads as glued
    primitives; remeshing is what turns a pile of shapes into one moulded
    object — which is the whole difference between a helmet and a ball with
    boxes stuck to it."""
    obj = join(objs, name)
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    obj.data.remesh_voxel_size = voxel
    obj.data.remesh_voxel_adaptivity = 0.0
    bpy.ops.object.voxel_remesh()
    if smooth:
        bpy.ops.object.shade_smooth()
        for poly in obj.data.polygons:
            poly.use_smooth = True
    return obj


def join(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o


def move_mesh(obj, dx, dy, dz):
    """Shift the geometry inside the object so its origin lands on a pivot."""
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for v in obj.data.vertices:
        v.co.x += dx
        v.co.y += dy
        v.co.z += dz
    obj.location = (0, 0, 0)
    return obj


def ground_origin(obj):
    """Stand the object on its own origin: centred in X/Y, base at Z=0."""
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


# ── palette ────────────────────────────────────────────────────────────────

def bike_materials():
    return {
        "plastic": material("Plastic", (0.86, 0.20, 0.12), 0.05, 0.32),
        "dark": material("DarkPlastic", (0.07, 0.08, 0.09), 0.15, 0.45),
        "metal": material("Metal", (0.62, 0.64, 0.68), 0.9, 0.30),
        "chrome": material("Chrome", (0.86, 0.88, 0.92), 1.0, 0.10),
        "alloy": material("Alloy", (0.74, 0.75, 0.78), 0.85, 0.22),
        "seat": material("Seat", (0.06, 0.06, 0.07), 0.0, 0.80),
        "plate": material("Plate", (0.94, 0.95, 0.97), 0.0, 0.35),
        "rubber": material("Rubber", (0.045, 0.045, 0.05), 0.0, 0.90),
        "shock": material("Shock", (0.90, 0.55, 0.10), 0.5, 0.25),
    }


# ── wheel ──────────────────────────────────────────────────────────────────

def build_wheel():
    M = bike_materials()
    R = Rig.WHEEL_R
    width = 0.115
    parts = []

    # Carcass as a torus, not a filled disc: a real tyre is a ring, and the
    # hole is what lets the rim and spokes read from the side.
    bpy.ops.mesh.primitive_torus_add(major_radius=R - width * 0.42,
                                     minor_radius=width * 0.46,
                                     major_segments=36, minor_segments=10,
                                     location=(0, 0, 0), rotation=(math.pi / 2, 0, 0))
    tyre = bpy.context.active_object
    tyre.name = "tyre"
    shade(tyre, M["rubber"], True)
    parts.append(tyre)

    # Knobs in two staggered rows, which is what makes a spinning MX tyre read
    # as a knobbly rather than a smooth ring.
    for row, offset in ((0, -width * 0.26), (1, width * 0.26)):
        for i in range(14):
            a = (i / 14.0) * math.tau + row * (math.tau / 28)
            k = box("knob%d_%d" % (row, i), (0.050, 0.040, 0.026),
                    (math.cos(a) * (R - 0.012), offset, math.sin(a) * (R - 0.012)),
                    rot=(0, -a, 0))
            shade(k, M["rubber"])
            parts.append(k)

    bpy.ops.mesh.primitive_torus_add(major_radius=R * 0.70, minor_radius=0.022,
                                     major_segments=32, minor_segments=8,
                                     location=(0, 0, 0), rotation=(math.pi / 2, 0, 0))
    rim = bpy.context.active_object
    rim.name = "rim"
    shade(rim, M["alloy"], True)
    parts.append(rim)

    parts.append(cyl("hub", 0.062, width * 1.05, (0, 0, 0), rot=(math.pi / 2, 0, 0),
                     verts=16, mat=M["alloy"]))

    # Spokes lace from hub to rim, alternating sides like a real wheel.
    for i in range(16):
        a = (i / 16.0) * math.tau
        side = width * 0.22 * (1 if i % 2 == 0 else -1)
        parts.append(tube_between(
            "spoke%d" % i,
            (math.cos(a) * 0.055, side, math.sin(a) * 0.055),
            (math.cos(a + 0.30) * R * 0.70, 0, math.sin(a + 0.30) * R * 0.70),
            0.0055, M["chrome"], verts=6))

    bpy.ops.mesh.primitive_torus_add(major_radius=R * 0.44, minor_radius=0.010,
                                     major_segments=28, minor_segments=6,
                                     location=(0, width * 0.60, 0), rotation=(math.pi / 2, 0, 0))
    disc = bpy.context.active_object
    disc.name = "disc"
    shade(disc, M["metal"], True)
    parts.append(disc)

    return join(parts, "Wheel")


# ── bike ───────────────────────────────────────────────────────────────────

def build_bike():
    reset_scene()
    M = bike_materials()
    frame_parts = []

    head = Rig.HEAD
    pivot = Rig.SWING_PIVOT

    # Backbone: head → under the seat, then down to the swingarm pivot, with a
    # cradle running forward under the engine. Tubes that actually meet.
    frame_parts.append(tube_between("backbone", head, (-0.30, 0, 0.10), 0.035, M["metal"]))
    frame_parts.append(tube_between("downtube", head, (0.14, 0, -0.20), 0.032, M["metal"]))
    frame_parts.append(tube_between("cradle", (0.14, 0, -0.20), (pivot[0], 0, -0.24), 0.028, M["metal"]))
    frame_parts.append(tube_between("seattube", (-0.30, 0, 0.10), pivot, 0.030, M["metal"]))
    for side in (0.085, -0.085):
        frame_parts.append(tube_between("spar%.0f" % (side * 1000),
                                        (head[0] - 0.06, side, head[2] - 0.02),
                                        (-0.26, side * 0.9, 0.06), 0.024, M["metal"]))
        frame_parts.append(tube_between("subframe%.0f" % (side * 1000),
                                        (-0.26, side * 0.9, 0.06),
                                        (-0.60, side * 0.75, 0.20), 0.020, M["metal"]))

    # Engine: cases, cylinder canted forward, head.
    frame_parts.append(box("cases", (0.30, 0.26, 0.22), (-0.06, 0, -0.16), mat=M["dark"]))
    frame_parts.append(box("clutch", (0.16, 0.06, 0.18), (-0.10, 0.15, -0.16), mat=M["alloy"]))
    frame_parts.append(cyl("barrel", 0.085, 0.20, (0.06, 0, 0.00),
                           rot=(0, 0.35, 0), verts=14, mat=M["alloy"]))
    frame_parts.append(box("cylhead", (0.17, 0.20, 0.10), (0.11, 0, 0.09),
                           rot=(0, 0.35, 0), mat=M["alloy"]))

    # Tank, shrouds and seat.
    frame_parts.append(box("tank", (0.44, 0.23, 0.24), (0.23, 0, 0.11),
                           rot=(0, -0.14, 0), mat=M["plastic"]))
    frame_parts.append(box("tanktop", (0.34, 0.17, 0.10), (0.21, 0, 0.23),
                           rot=(0, -0.14, 0), mat=M["plastic"]))
    for side in (0.12, -0.12):
        frame_parts.append(box("shroud%.0f" % (side * 1000), (0.34, 0.035, 0.30),
                               (0.28, side, 0.05), rot=(0, -0.22, 0),
                               mat=M["plastic"]))
    frame_parts.append(box("seat", (0.46, 0.15, 0.07), (-0.22, 0, Rig.SEAT_Z),
                           rot=(0, -0.06, 0), mat=M["seat"]))
    frame_parts.append(box("seatnose", (0.14, 0.11, 0.05), (0.02, 0, Rig.SEAT_Z + 0.02),
                           rot=(0, -0.16, 0), mat=M["seat"]))

    # Side plates and rear fender.
    for side in (0.125, -0.125):
        frame_parts.append(box("plate%.0f" % (side * 1000), (0.24, 0.02, 0.16),
                               (-0.46, side * 0.92, 0.14), rot=(0, -0.18, 0),
                               mat=M["plate"]))
    frame_parts.append(box("rearfender", (0.42, 0.20, 0.032), (-0.56, 0, 0.20),
                           rot=(0, -0.12, 0), mat=M["plastic"]))
    frame_parts.append(box("rearfendertip", (0.18, 0.16, 0.028), (-0.80, 0, 0.235),
                           rot=(0, -0.20, 0), mat=M["plastic"]))
    frame_parts.extend(arc_panel("rearguard",
                                 (Rig.REAR_AXLE[0], 0, Rig.REAR_AXLE[2]), 0.40,
                                 math.radians(58), math.radians(104), 0.19, 0.035,
                                 M["plastic"], steps=8))

    # Exhaust sweeping out of the head into a silencer.
    frame_parts.append(tube_between("header", (0.16, 0.05, 0.06), (0.02, 0.13, -0.06),
                                    0.026, M["chrome"], verts=8))
    frame_parts.append(tube_between("midpipe", (0.02, 0.13, -0.06), (-0.34, 0.15, 0.06),
                                    0.030, M["chrome"], verts=8))
    frame_parts.append(tube_between("silencer", (-0.34, 0.15, 0.06), (-0.60, 0.15, 0.14),
                                    0.048, M["alloy"], verts=10, taper=0.042))

    for side in (Rig.PEG[1], -Rig.PEG[1]):
        frame_parts.append(box("peg%.0f" % (side * 1000), (0.10, 0.09, 0.02),
                               (Rig.PEG[0], side, Rig.PEG[2]), mat=M["metal"]))

    frame = join(frame_parts, "Frame")
    bevel(frame, 0.006, 2)

    # ── fork: origin at the front axle, tubes raked back to the head ────────
    axle = Rig.FRONT_AXLE
    fork_parts = []
    for side in (0.095, -0.095):
        top = (head[0] - 0.03 + math.sin(Rig.RAKE) * 0.10, side, head[2] + 0.10)
        low = (axle[0], side, axle[2])
        midpoint = ((low[0] + top[0]) / 2, side, (low[2] + top[2]) / 2)
        fork_parts.append(tube_between("lower%.0f" % (side * 1000), low,
                                       (midpoint[0], side, midpoint[2] - 0.02),
                                       0.042, M["dark"], verts=12))
        fork_parts.append(tube_between("stanchion%.0f" % (side * 1000),
                                       (midpoint[0], side, midpoint[2] - 0.04),
                                       top, 0.030, M["chrome"], verts=12))
    fork_parts.append(box("tripleclamp", (0.09, 0.24, 0.045),
                          (head[0] + 0.06, 0, head[2] + 0.10),
                          rot=(0, Rig.RAKE, 0), mat=M["alloy"]))
    fork_parts.append(tube_between("bar", (head[0] + 0.02, Rig.BAR[1], Rig.BAR[2]),
                                   (head[0] + 0.02, -Rig.BAR[1], Rig.BAR[2]),
                                   0.016, M["dark"], verts=10))
    for side in (Rig.BAR[1], -Rig.BAR[1]):
        fork_parts.append(tube_between("grip%.0f" % (side * 1000),
                                       (head[0] + 0.02, side * 0.72, Rig.BAR[2]),
                                       (head[0] + 0.02, side, Rig.BAR[2]),
                                       0.020, M["seat"], verts=8))
    fork_parts.extend(arc_panel("frontfender", (axle[0], 0, axle[2]), 0.41,
                                math.radians(18), math.radians(96), 0.21, 0.038,
                                M["plastic"], steps=12))
    fork = join(fork_parts, "Fork")
    bevel(fork, 0.005, 2)
    move_mesh(fork, -axle[0], 0, -axle[2])     # origin at the front axle

    # ── swingarm: origin at the pivot, arms reaching the rear axle ──────────
    rear = Rig.REAR_AXLE
    swing_parts = []
    for side in (0.085, -0.085):
        swing_parts.append(tube_between("arm%.0f" % (side * 1000),
                                        (pivot[0], side, pivot[2]),
                                        (rear[0], side * 0.82, rear[2]),
                                        0.032, M["alloy"], verts=10, taper=0.024))
    swing_parts.append(box("brace", (0.12, 0.16, 0.05), (-0.34, 0, -0.20), mat=M["alloy"]))
    swing_parts.append(tube_between("shockbody", (pivot[0] + 0.02, 0, pivot[2] + 0.06),
                                    (-0.22, 0, 0.12), 0.034, M["shock"], verts=10))
    swing_parts.append(tube_between("shockshaft", (-0.30, 0, -0.14),
                                    (pivot[0] + 0.02, 0, pivot[2] + 0.02),
                                    0.014, M["chrome"], verts=8))
    swing_parts.append(cyl("sprocket", 0.085, 0.012, (rear[0], 0.075, rear[2]),
                           rot=(math.pi / 2, 0, 0), verts=24, mat=M["alloy"]))
    swing_parts.append(box("chaintop", (0.58, 0.02, 0.014), (-0.38, 0.075, -0.14),
                           rot=(0, 0.06, 0), mat=M["dark"]))
    swing_parts.append(box("chainbot", (0.58, 0.02, 0.014), (-0.38, 0.075, -0.24),
                           rot=(0, -0.04, 0), mat=M["dark"]))
    swing = join(swing_parts, "Swingarm")
    bevel(swing, 0.005, 2)
    move_mesh(swing, -pivot[0], 0, -pivot[2])  # origin at the pivot

    wheel = build_wheel()

    export("bike_frame.obj", [frame])
    export("bike_fork.obj", [fork])
    export("bike_swingarm.obj", [swing])
    export("bike_wheel.obj", [wheel])


# ── rider ──────────────────────────────────────────────────────────────────

def build_rider():
    """A rider in the attack position, built so the boots land on the pegs and
    the gloves land on the bars — the two contact points that sell the pose."""
    reset_scene()

    jersey = material("Jersey", (0.12, 0.34, 0.90), 0.0, 0.50)
    pants = material("Pants", (0.10, 0.11, 0.14), 0.0, 0.55)
    boot = material("Boot", (0.05, 0.05, 0.06), 0.15, 0.40)
    helmet = material("Helmet", (0.72, 0.10, 0.05), 0.30, 0.16)
    visor = material("Visor", (0.30, 0.82, 0.62), 0.7, 0.08)
    glove = material("Glove", (0.12, 0.13, 0.16), 0.0, 0.55)

    helmet_parts, jersey_parts, pants_parts, other = [], [], [], []

    hip = (-0.14, 0.0, 0.30)
    chest = (0.06, 0.0, 0.62)
    neck = (0.11, 0.0, 0.70)
    head_c = (0.155, 0.0, 0.795)

    jersey_parts.append(tube_between("torso", hip, chest, 0.135, jersey, verts=14, taper=0.115))
    jersey_parts.append(sphere("chestmass", 0.135, chest, jersey, scale=(1.15, 0.85, 1.0)))
    pants_parts.append(sphere("hipmass", 0.130, hip, pants, scale=(1.05, 0.95, 1.0)))
    jersey_parts.append(tube_between("shoulders", (chest[0], 0.16, chest[2] + 0.03),
                              (chest[0], -0.16, chest[2] + 0.03), 0.085, jersey, verts=12))

    for side in (1, -1):
        y = 0.155 * side
        knee = (0.04, y * 1.15, 0.06)
        peg = (Rig.PEG[0], Rig.PEG[1] * side, Rig.PEG[2] + 0.06)
        elbow = (0.26, y * 1.25, 0.60)
        grip = (Rig.BAR[0] + 0.02, Rig.BAR[1] * side * 0.95, Rig.BAR[2] + 0.03)

        # Legs: hip → knee → boot on the peg, bent as a standing rider's are.
        pants_parts.append(tube_between("thigh%d" % side, (hip[0], y, hip[2]), knee,
                                  0.085, pants, verts=10, taper=0.065))
        pants_parts.append(sphere("kneepad%d" % side, 0.070, knee, pants))
        pants_parts.append(tube_between("shin%d" % side, knee, (peg[0], peg[1], peg[2] + 0.02),
                                  0.062, pants, verts=10, taper=0.052))
        other.append(box("boot%d" % side, (0.21, 0.10, 0.10),
                         (peg[0] + 0.03, peg[1], peg[2] - 0.03), mat=boot))
        other.append(box("bootcuff%d" % side, (0.10, 0.11, 0.14),
                         (peg[0] - 0.01, peg[1], peg[2] + 0.06), mat=boot))

        # Arms: shoulder → elbow → glove on the bar.
        jersey_parts.append(tube_between("upperarm%d" % side, (chest[0], y * 1.05, chest[2] + 0.02),
                                  elbow, 0.058, jersey, verts=10, taper=0.048))
        jersey_parts.append(sphere("elbow%d" % side, 0.050, elbow, jersey))
        jersey_parts.append(tube_between("forearm%d" % side, elbow, grip,
                                  0.046, jersey, verts=10, taper=0.040))
        other.append(sphere("glove%d" % side, 0.055, grip, glove, scale=(1.2, 1.0, 1.0)))

    # ── helmet ─────────────────────────────────────────────────────────
    # Built as a shape, not a ball with details glued on: an oval shell, a
    # brow that carries the peak, a chin bar that projects ahead of the face,
    # and a recessed eye port with the goggle sitting in it.
    strap_mat = material("HelmetStrap", (0.07, 0.08, 0.10), 0.0, 0.55)
    port = material("Port", (0.05, 0.05, 0.06), 0.0, 0.7)

    jersey_parts.append(tube_between("neck", (neck[0], 0, neck[2] - 0.02),
                              (chest[0], 0, chest[2] + 0.05), 0.055, jersey, verts=8))

    # Real MX-lid proportions, in metres: a shell about 250 mm front to back,
    # a peak projecting ~85 mm past the brow, and a chin bar standing ahead of
    # the eye port. Shell, jaw and chin bar are metaballs so they flow into one
    # another the way a moulded shell does.
    hx, hz = head_c[0], head_c[2]
    # Dense, heavily overlapping balls along a spine: spacing well under the
    # radius is what makes them merge into one ovoid instead of a peanut.
    shell = blob("HelmetShell", [
        ((hx - 0.080, 0.0, hz - 0.015), 0.088),
        ((hx - 0.050, 0.0, hz + 0.000), 0.096),
        ((hx - 0.020, 0.0, hz + 0.008), 0.099),
        ((hx + 0.010, 0.0, hz + 0.008), 0.099),
        ((hx + 0.040, 0.0, hz + 0.000), 0.096),
        ((hx + 0.065, 0.0, hz - 0.015), 0.090),
        ((hx + 0.060, 0.0, hz - 0.050), 0.082),   # jaw line
        ((hx + 0.090, 0.0, hz - 0.062), 0.074),
        ((hx + 0.118, 0.0, hz - 0.058), 0.064),   # chin bar
    ], helmet, resolution=0.006)
    helmet_parts.append(shell)
    # The peak stays a crisp moulded plate — real ones are sharp-edged.
    helmet_parts.append(box("peak", (0.165, 0.205, 0.020),
                            (hx + 0.140, 0, hz + 0.062),
                            rot=(0, -0.22, 0), mat=helmet))

    strap_mat = material("HelmetStrap", (0.07, 0.08, 0.10), 0.0, 0.55)
    port = material("Port", (0.05, 0.05, 0.06), 0.0, 0.7)
    other.append(box("chinvent", (0.035, 0.085, 0.035),
                     (head_c[0] + 0.180, 0, head_c[2] - 0.070),
                     rot=(0, 0.26, 0), mat=port))
    other.append(box("eyeport", (0.045, 0.185, 0.080),
                     (head_c[0] + 0.115, 0, head_c[2] + 0.000),
                     rot=(0, 0.08, 0), mat=port))
    other.append(box("goggle", (0.040, 0.198, 0.072),
                     (head_c[0] + 0.130, 0, head_c[2] + 0.002),
                     rot=(0, 0.08, 0), mat=visor))
    other.append(box("gogglestrap", (0.190, 0.215, 0.044),
                     (head_c[0] - 0.020, 0, head_c[2] + 0.010),
                     rot=(0, 0.03, 0), mat=strap_mat))

    # Each material group becomes one skin; the small hard details (goggle,
    # boots, gloves) stay crisp on top.
    helmet_body = fuse(helmet_parts, "Helmet", voxel=0.008)
    torso = fuse(jersey_parts, "Torso", voxel=0.014)
    legs = fuse(pants_parts, "Legs", voxel=0.014)

    parts = [helmet_body, torso, legs] + other
    rider = join(parts, "RiderBody")
    bevel(rider, 0.006, 2)
    export("rider.obj", [rider])


def build_rider_standing():
    """A rider stood upright, for the podium and the rider screen. The racing
    model is crouched into the bars, which looks wrong anywhere off the bike,
    so this is posed separately rather than re-used."""
    reset_scene()

    jersey = material("Jersey", (0.12, 0.34, 0.90), 0.0, 0.50)
    pants = material("Pants", (0.10, 0.11, 0.14), 0.0, 0.55)
    boot = material("Boot", (0.05, 0.05, 0.06), 0.15, 0.40)
    helmet = material("Helmet", (0.72, 0.10, 0.05), 0.30, 0.16)
    visor = material("Visor", (0.30, 0.82, 0.62), 0.7, 0.08)
    glove = material("Glove", (0.12, 0.13, 0.16), 0.0, 0.55)
    strap_mat = material("HelmetStrap", (0.07, 0.08, 0.10), 0.0, 0.55)
    port = material("Port", (0.05, 0.05, 0.06), 0.0, 0.7)

    helmet_parts, jersey_parts, pants_parts, other = [], [], [], []

    # Real proportions for a 1.78 m rider: feet at 0, knees 0.48, hips 0.92,
    # shoulders 1.45, head centred at 1.62. Getting these wrong is what makes
    # a figure read as a squat doll rather than a person.
    hip = (0.0, 0.0, 0.92)
    chest = (0.0, 0.0, 1.36)
    shoulder_z = 1.40
    head_c = (0.02, 0.0, 1.68)

    jersey_parts.append(tube_between("torso", (hip[0], 0, hip[2] - 0.04), chest,
                                     0.125, jersey, verts=14, taper=0.150))
    jersey_parts.append(sphere("chestmass", 0.152, (0.0, 0.0, 1.31), jersey,
                               scale=(0.78, 1.10, 0.88)))
    pants_parts.append(sphere("hipmass", 0.140, hip, pants, scale=(0.85, 1.05, 0.80)))
    jersey_parts.append(tube_between("shoulders", (0.0, 0.200, shoulder_z),
                                     (0.0, -0.200, shoulder_z), 0.088, jersey, verts=12))
    jersey_parts.append(tube_between("neck", (head_c[0], 0, 1.60), (0.0, 0, 1.40),
                                     0.056, jersey, verts=8))

    for side in (1, -1):
        y = 0.095 * side
        knee = (0.015, y * 1.05, 0.48)
        ankle = (0.0, y * 1.05, 0.09)
        pants_parts.append(tube_between("thigh%d" % side, (hip[0], y, hip[2] - 0.06), knee,
                                        0.098, pants, verts=10, taper=0.076))
        pants_parts.append(sphere("kneepad%d" % side, 0.078, knee, pants))
        pants_parts.append(tube_between("shin%d" % side, knee, ankle,
                                        0.070, pants, verts=10, taper=0.056))
        other.append(box("boot%d" % side, (0.27, 0.115, 0.11), (0.05, y * 1.05, 0.055), mat=boot))
        other.append(box("bootcuff%d" % side, (0.12, 0.125, 0.22), (-0.01, y * 1.05, 0.17), mat=boot))

        # The winner throws one arm up; the other hangs by the hip.
        shoulder = (0.0, 0.205 * side, shoulder_z - 0.02)
        if side == 1:
            elbow = (0.03, 0.300 * side, 1.62)
            hand = (0.0, 0.330 * side, 1.97)
        else:
            elbow = (0.02, 0.255 * side, 1.12)
            hand = (0.05, 0.270 * side, 0.88)
        jersey_parts.append(tube_between("upperarm%d" % side, shoulder, elbow,
                                         0.068, jersey, verts=10, taper=0.056))
        jersey_parts.append(sphere("elbow%d" % side, 0.057, elbow, jersey))
        jersey_parts.append(tube_between("forearm%d" % side, elbow, hand,
                                         0.052, jersey, verts=10, taper=0.045))
        other.append(sphere("glove%d" % side, 0.060, hand, glove, scale=(1.05, 1.0, 1.15)))

    hx, hz = head_c[0], head_c[2]
    shell = blob("HelmetShell", [
        ((hx - 0.080, 0.0, hz - 0.015), 0.088),
        ((hx - 0.050, 0.0, hz + 0.000), 0.096),
        ((hx - 0.020, 0.0, hz + 0.008), 0.099),
        ((hx + 0.010, 0.0, hz + 0.008), 0.099),
        ((hx + 0.040, 0.0, hz + 0.000), 0.096),
        ((hx + 0.065, 0.0, hz - 0.015), 0.090),
        ((hx + 0.060, 0.0, hz - 0.050), 0.082),
        ((hx + 0.090, 0.0, hz - 0.062), 0.074),
        ((hx + 0.118, 0.0, hz - 0.058), 0.064),
    ], helmet, resolution=0.006)
    helmet_parts.append(shell)
    helmet_parts.append(box("peak", (0.165, 0.205, 0.020), (hx + 0.140, 0, hz + 0.062),
                            rot=(0, -0.22, 0), mat=helmet))
    other.append(box("eyeport", (0.045, 0.185, 0.080), (hx + 0.115, 0, hz + 0.000),
                     rot=(0, 0.08, 0), mat=port))
    other.append(box("goggle", (0.040, 0.198, 0.072), (hx + 0.130, 0, hz + 0.002),
                     rot=(0, 0.08, 0), mat=visor))
    other.append(box("gogglestrap", (0.190, 0.215, 0.044), (hx - 0.020, 0, hz + 0.010),
                     rot=(0, 0.03, 0), mat=strap_mat))

    helmet_body = fuse(helmet_parts, "Helmet", voxel=0.008)
    torso = fuse(jersey_parts, "Torso", voxel=0.014)
    legs = fuse(pants_parts, "Legs", voxel=0.014)

    rider = join([helmet_body, torso, legs] + other, "RiderStanding")
    bevel(rider, 0.006, 2)
    export("rider_stand.obj", [rider])


# ── scenery ────────────────────────────────────────────────────────────────

def build_props():
    reset_scene()

    bark = material("Bark", (0.22, 0.15, 0.10), 0.0, 0.85)
    leaf = material("Leaf", (0.18, 0.38, 0.16), 0.0, 0.75)
    hay = material("Hay", (0.76, 0.64, 0.32), 0.0, 0.85)
    cloth = material("Cloth", (0.88, 0.30, 0.18), 0.0, 0.60)
    pole = material("Pole", (0.78, 0.80, 0.84), 0.85, 0.30)
    steel = material("Steel", (0.52, 0.55, 0.60), 0.9, 0.35)

    # Tree: tapered trunk, a couple of limbs and stacked canopy blobs.
    t = [cone("trunk", 0.17, 0.09, 2.4, (0, 0, 1.2), verts=10, mat=bark)]
    t.append(tube_between("limbA", (0, 0, 1.7), (0.5, 0.2, 2.3), 0.045, bark, verts=6))
    t.append(tube_between("limbB", (0, 0, 1.9), (-0.45, -0.15, 2.5), 0.04, bark, verts=6))
    for i, (r, z, off) in enumerate(((0.95, 2.5, (0.05, 0.0)), (0.78, 3.1, (-0.1, 0.08)),
                                     (0.52, 3.6, (0.08, -0.05)))):
        t.append(sphere("canopy%d" % i, r, (off[0], off[1], z), leaf,
                        segments=14, rings=8, scale=(1.0, 1.0, 0.72)))
    tree = join(t, "Tree")

    bale = cyl("Bale", 0.45, 0.95, (0, 0, 0.45), rot=(0, math.pi / 2, 0),
               verts=18, mat=hay)

    f = [cyl("flagpole", 0.032, 1.7, (0, 0, 0.85), verts=8, mat=pole)]
    f.append(box("flagcloth", (0.52, 0.02, 0.34), (0.28, 0, 1.48), rot=(0, 0, 0.06), mat=cloth))
    flag = join(f, "Flag")

    g = [cyl("towerL", 0.13, 5.0, (0, 4.2, 2.5), verts=10, mat=steel)]
    g.append(cyl("towerR", 0.13, 5.0, (0, -4.2, 2.5), verts=10, mat=steel))
    for z in (1.6, 3.2):
        g.append(tube_between("braceL%0.1f" % z, (0, 4.2, z), (0, 2.6, z + 0.9), 0.05, steel, verts=6))
        g.append(tube_between("braceR%0.1f" % z, (0, -4.2, z), (0, -2.6, z + 0.9), 0.05, steel, verts=6))
    g.append(tube_between("span", (0, 4.4, 5.0), (0, -4.4, 5.0), 0.13, steel, verts=10))
    g.append(box("banner", (0.06, 8.6, 1.15), (0, 0, 4.3), mat=cloth))
    gantry = join(g, "Gantry")

    for o in (tree, bale, flag, gantry):
        ground_origin(o)
    bevel(bale, 0.02, 2)

    export("prop_tree.obj", [tree])
    export("prop_bale.obj", [bale])
    export("prop_flag.obj", [flag])
    export("prop_gantry.obj", [gantry])


if __name__ == "__main__":
    build_bike()
    build_rider()
    build_rider_standing()
    build_props()
    print("MotoRush art build complete ->", OUT_DIR)
