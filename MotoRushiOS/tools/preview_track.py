"""Render a preview of a race scene: the real track heightfield extruded into
the same banked ribbon the game builds at runtime, with the bike and rider on
it and scenery scattered down the sides.

    node tools/dump_track.mjs track.json          # from the browser build
    blender --background --python tools/preview_track.py -- track.json out.png

The cross-section below is the same one as `TerrainBuilder.section` in
Race3D.swift, so this shows the shape the app actually renders rather than an
artist's impression of it.
"""

import bpy
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(os.path.dirname(HERE), "MotoRush", "Art")
sys.path.insert(0, HERE)
from blender_assets import Rig  # noqa: E402

# (lateral offset, height offset) — mirrors TerrainBuilder.section.
SECTION = [(-9.0, -4.2), (-6.2, -2.6), (-3.6, 0.55), (-2.9, 0.0), (0.0, 0.0),
           (2.9, 0.0), (3.6, 0.55), (4.4, -3.4)]

# Matches TerrainBuilder.propRows: both scenery rows on the far side only.
PROP_ROWS = [(-4.4, -0.42), (-6.6, -2.83)]

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
TRACK = args[0] if args else "track.json"
OUT = args[1] if len(args) > 1 else "track_preview.png"
# Where along the track to put the camera, in metres.
FOCUS = float(args[2]) if len(args) > 2 else 120.0

data = json.load(open(TRACK))
heights = data["heights"]
step = data["step"]


def height_at(x):
    f = x / step
    if f <= 0:
        return heights[0]
    if f >= len(heights) - 1:
        return heights[-1]
    i = int(f)
    return heights[i] + (heights[i + 1] - heights[i]) * (f - i)


bpy.ops.wm.read_factory_settings(use_empty=True)

# ── terrain ribbon ─────────────────────────────────────────────────────────
# Only the stretch around the camera is built; the whole 900 m would be wasted
# geometry for a still.
x0, x1 = max(0.0, FOCUS - 55), FOCUS + 75
verts, faces = [], []
rows = 0
x = x0
while x <= x1:
    h = height_at(x)
    for (z, dz) in SECTION:
        # Blender's lateral axis is negated against SceneKit's z. Building the
        # section directly would render the scene mirrored: with the camera on
        # the near side, +x would run left here and right in the app.
        verts.append((x, -z, h + dz))
    rows += 1
    x += 0.6

cols = len(SECTION)
for r in range(rows - 1):
    for c in range(cols - 1):
        a = r * cols + c
        b = (r + 1) * cols + c
        faces.append((a, b, b + 1, a + 1))

mesh = bpy.data.meshes.new("Terrain")
mesh.from_pydata(verts, [], faces)
mesh.update()
terrain = bpy.data.objects.new("Terrain", mesh)
bpy.context.collection.objects.link(terrain)
for poly in terrain.data.polygons:
    poly.use_smooth = True

dirt = bpy.data.materials.new("Dirt")
dirt.use_nodes = True
bsdf = dirt.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.32, 0.20, 0.13, 1)
bsdf.inputs["Roughness"].default_value = 0.95
terrain.data.materials.append(dirt)


def load(name, location, rot=(0.0, 0.0, 0.0), scale=1.0):
    """Import a part and place it. The deselect matters: the importer adds to
    the selection rather than replacing it, so without this every later import
    drags all the earlier ones along with it."""
    bpy.ops.object.select_all(action='DESELECT')
    bpy.ops.wm.obj_import(filepath=os.path.join(ART, name + ".obj"),
                          forward_axis='NEGATIVE_Z', up_axis='Y')
    objs = list(bpy.context.selected_objects)
    for o in objs:
        o.location = location
        # Add to the importer's rotation rather than replacing it: the axis
        # conversion lives there, so overwriting it lays the model on its side.
        o.rotation_euler.x += rot[0]
        o.rotation_euler.y += rot[1]
        o.rotation_euler.z += rot[2]
        o.scale = (scale, scale, scale)
    return objs


# ── the bike, sitting on the track with the suspension at rest ─────────────
bike_x = FOCUS
ground = height_at(bike_x)
slope = (height_at(bike_x + 0.4) - height_at(bike_x - 0.4)) / 0.8
pitch = math.atan(slope)
origin_z = ground + Rig.WHEEL_R - Rig.AXLE_Z

def on_bike(anchor):
    """World placement of a part whose model origin is `anchor` in bike space,
    with the whole bike pitched to the slope it is sitting on."""
    ax, _, az = anchor
    c, sn = math.cos(-pitch), math.sin(-pitch)
    return (bike_x + ax * c + az * sn, 0.0, origin_z - ax * sn + az * c)


# Pitch the bike onto the slope it is standing on.
pitch_rot = (0.0, 0.0, -pitch)
load("bike_frame", on_bike((0, 0, 0)), rot=pitch_rot)
load("bike_swingarm", on_bike(Rig.SWING_PIVOT), rot=pitch_rot)
load("bike_fork", on_bike(Rig.FRONT_AXLE), rot=pitch_rot)
load("bike_wheel", on_bike(Rig.FRONT_AXLE), rot=pitch_rot)
load("bike_wheel", on_bike(Rig.REAR_AXLE), rot=pitch_rot)
load("rider", on_bike((0, 0, 0)), rot=pitch_rot)

# ── scenery down the sides ────────────────────────────────────────────────
for prop in data.get("props", []):
    px = prop["x"]
    if not (x0 + 4 < px < x1 - 4):
        continue
    # The browser build calls the field "type" and marks the far row "layer".
    kind = {"tree": "prop_tree", "banner": "prop_gantry",
            "flag": "prop_flag"}.get(prop.get("type") or prop.get("kind"), "prop_bale")
    # Far side only, near track level: the camera sits out on the near side, so
    # anything placed there stands between the viewer and the race.
    side, drop = PROP_ROWS[1 if (prop.get("layer") or prop.get("back")) else 0]
    load(kind, (px, -side, height_at(px) + drop), rot=(0, 0, px % 1.5),
         scale=prop.get("scale", 1.0))

# ── camera, lighting, sky ─────────────────────────────────────────────────
# Aim with a constraint rather than hand-computed Euler angles — the terrain
# height varies, so a fixed rotation buries the camera in the next rise.
# Match the in-game camera: nearly side-on and only a couple of metres above
# the bike. Looking down from high up puts the ribbon's outer skirt between
# the camera and the track.
bpy.ops.object.empty_add(type='PLAIN_AXES',
                         location=(bike_x + 2.5, 0, height_at(bike_x) + 1.0))
target = bpy.context.active_object

# Square-on to the track and up a little, which is how the game frames it.
# -y here is the app's +z, i.e. the near side the race camera views from.
bpy.ops.object.camera_add(location=(bike_x + 3.0, -17.0, height_at(bike_x) + 3.4))
cam = bpy.context.active_object
cam.data.lens = 50
con = cam.constraints.new(type='TRACK_TO')
con.target = target
con.track_axis = 'TRACK_NEGATIVE_Z'
con.up_axis = 'UP_Y'
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type='SUN', location=(bike_x, -20, 30))
sun = bpy.context.active_object
sun.data.energy = 4.2
sun.data.angle = math.radians(2.5)
sun.rotation_euler = (math.radians(52), math.radians(8), math.radians(28))

world = bpy.data.worlds.new("Sky")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.42, 0.62, 0.88, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.15

sc = bpy.context.scene
sc.render.engine = 'CYCLES'
sc.cycles.samples = 96
sc.cycles.use_denoising = False
sc.render.resolution_x = 1200
sc.render.resolution_y = 620
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("rendered", OUT)
