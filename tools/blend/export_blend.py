"""Exports art/TowerOfPower_Soldier.blend to the files the game loads:

    assets/characters/soldier/soldier.glb  the rig, the body (Soldier), the
                                           first-person arms (FP_Arms) and
                                           every action on the rig
    assets/weapons/guns.glb                Shotgun_3P, Rifle_3P, Shotgun_FP,
                                           Rifle_FP, with their markers

    python tools/blend/export_blend.py [file.blend]

Needs Blender as a Python module (pip install bpy==5.2.3 on Python 3.13) or
run inside Blender: blender -b file.blend --python tools/blend/export_blend.py
If FP_Arms is missing it is cut from the body again (see build_blend.py).
"""

import os
import sys

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GUNS = ("Shotgun_3P", "Rifle_3P", "Shotgun_FP", "Rifle_FP")
ARM_PARTS = ("Arm", "Hand")

if sys.argv[-1].endswith(".blend"):
    bpy.ops.wm.open_mainfile(filepath=sys.argv[-1])
scene = bpy.context.scene


def show_everything():
    def walk(lc):
        lc.exclude = False
        lc.hide_viewport = False
        for c in lc.children:
            walk(c)
    walk(bpy.context.view_layer.layer_collection)
    for o in scene.objects:
        o.hide_set(False)
        o.hide_viewport = False
        o.hide_select = False


def tree(obj):
    out = [obj]
    for c in obj.children:
        out += tree(c)
    return out


def select(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def cut_arms(body, rig):
    arms = body.copy()
    arms.data = body.data.copy()
    arms.name = arms.data.name = "FP_Arms"
    scene.collection.objects.link(arms)
    select([arms])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.quads_convert_to_tris()
    bpy.ops.object.mode_set(mode="OBJECT")
    groups = {g.index for g in arms.vertex_groups if any(p in g.name for p in ARM_PARTS)}
    on_arm = [sum(ge.weight for ge in v.groups if ge.group in groups) >= 0.5 for v in arms.data.vertices]
    for poly in arms.data.polygons:
        poly.select = not all(on_arm[i] for i in poly.vertices)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.delete(type="FACE")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.delete_loose()
    bpy.ops.object.mode_set(mode="OBJECT")
    print("FP_Arms was missing: cut it from the body again")
    return arms


def export(path, objs, animations):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    select(objs)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True,
        export_animations=animations, export_animation_mode="ACTIONS",
        export_skins=True, export_all_influences=True, export_def_bones=False, export_yup=True,
        export_force_sampling=True, export_optimize_animation_size=False, export_reset_pose_bones=True,
        export_cameras=False, export_lights=False, export_extras=False)
    print("wrote", os.path.relpath(path, ROOT))


show_everything()
if bpy.context.object and bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
rig = next(o for o in scene.objects if o.type == "ARMATURE")
meshes = [o for o in scene.objects if o.type == "MESH" and o.parent == rig]
arms = next((o for o in meshes if o.name == "FP_Arms"), None)
body = next(o for o in meshes if o.name != "FP_Arms")
if arms is None:
    arms = cut_arms(body, rig)
    arms.parent = rig
for a in bpy.data.actions:
    a.use_fake_user = True  # keep every action, used or not, in the export
rig.animation_data.action = None
for pb in rig.pose.bones:
    pb.location = (0, 0, 0)
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.scale = (1, 1, 1)

export(os.path.join(ROOT, "assets/characters/soldier/soldier.glb"), [rig, body, arms], True)
guns = []
for name in GUNS:
    guns += tree(scene.objects[name])
export(os.path.join(ROOT, "assets/weapons/guns.glb"), guns, False)
