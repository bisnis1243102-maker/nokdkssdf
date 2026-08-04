"""Render a preview of the exported art, assembled the way the game assembles
it, so the models can be checked without an iOS device:

    blender --background --python tools/preview.py -- out.png

The part placement here mirrors BikeRig.sync() in Race3D.swift: wheels at the
axles, fork at the front axle, swingarm at its pivot, rider at the origin.
"""

import bpy
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.join(os.path.dirname(HERE), "MotoRush", "Art")
sys.path.insert(0, HERE)
from blender_assets import Rig  # noqa: E402

OUT = "preview.png"
if "--" in sys.argv:
    extra = sys.argv[sys.argv.index("--") + 1:]
    if extra:
        OUT = extra[0]


def load(name, location=(0, 0, 0)):
    bpy.ops.wm.obj_import(filepath=os.path.join(ART, name + ".obj"),
                          forward_axis='NEGATIVE_Z', up_axis='Y')
    objs = list(bpy.context.selected_objects)
    for o in objs:
        o.location = location
    return objs


bpy.ops.wm.read_factory_settings(use_empty=True)

load("bike_frame")
load("bike_swingarm", Rig.SWING_PIVOT)
load("bike_fork", Rig.FRONT_AXLE)
load("bike_wheel", Rig.FRONT_AXLE)
load("bike_wheel", Rig.REAR_AXLE)
load("rider")

# Ground plane at the tyre contact patch.
bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, Rig.AXLE_Z - Rig.WHEEL_R))
ground = bpy.context.active_object
mat = bpy.data.materials.new("dirt")
mat.use_nodes = True
mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.34, 0.22, 0.15, 1)
mat.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.95
ground.data.materials.append(mat)

# Camera: side-on with a touch of yaw, like the in-game one.
bpy.ops.object.camera_add(location=(0.55, -6.2, 0.55),
                          rotation=(math.radians(87), 0, math.radians(6)))
cam = bpy.context.active_object
cam.data.lens = 70
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type='SUN', location=(3, -4, 6))
sun = bpy.context.active_object
sun.data.energy = 4.5
sun.data.angle = math.radians(3)
sun.rotation_euler = (math.radians(52), math.radians(12), math.radians(35))

bpy.ops.object.light_add(type='AREA', location=(-3.5, -4.5, 2.5))
fill = bpy.context.active_object
fill.data.energy = 320
fill.data.size = 4
fill.rotation_euler = (math.radians(75), 0, math.radians(-40))

world = bpy.data.worlds.new("W")
bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.42, 0.60, 0.85, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.2

sc = bpy.context.scene
sc.render.engine = 'CYCLES'
sc.cycles.samples = 128
sc.cycles.use_denoising = False
sc.render.resolution_x = 1000
sc.render.resolution_y = 560
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("rendered", OUT)
