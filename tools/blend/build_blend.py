"""Builds art/TowerOfPower_Soldier.blend from the assets the game used before
the .blend existed: the Mixamo character, its six Mixamo clips and the guns.
It was run once; the .blend is the source from now on (see export_blend.py).
Kept to show how the file was made, and to rebuild it if ever needed.

    python tools/blend/build_blend.py <character.fbx> <clips dir> <guns.glb> <out.blend>

Needs Blender as a Python module (pip install bpy, matching Python version).
"""

import os
import re
import sys

import bpy
from mathutils import Matrix, Quaternion

char_fbx, clips_dir, guns_glb, out_blend = sys.argv[-4:]

# Action name (what the game asks for) -> Mixamo clip file.
CLIPS = {
    "idle": "rifle aiming idle",
    "run": "rifle run",
    "back": "run backwards",
    "strafe_l": "strafe left",
    "strafe_r": "strafe right",
    "jump": "jump forward",
}
HIPS = "mixamorig:Hips"
# The game fitted the clips' hip movement to the rig by the ratio of the
# characters' hip heights: v005's stood 1.2997 m (its own file; the rig saved
# inside each clip file stands a little taller, 1.3056).
CLIP_HIPS_HEIGHT = 1.2997
ARM_PARTS = ("Arm", "Hand")  # the first-person arms: what these bones carry

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 30


def import_fbx(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def drop_actions(obj):
    if obj.animation_data and obj.animation_data.action:
        act = obj.animation_data.action
        obj.animation_data.action = None
        bpy.data.actions.remove(act)


def collection(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c


def move_to(obj, coll):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    coll.objects.link(obj)
    for child in obj.children:
        move_to(child, coll)


# --- The character, in metres, standing on the origin, facing -Y -----------------------

objs = import_fbx(char_fbx)
rig = next(o for o in objs if o.type == "ARMATURE")
body = next(o for o in objs if o.type == "MESH")
drop_actions(rig)
rig.name = "Soldier_Rig"
rig.data.name = "Soldier_Rig"
body.name = "Soldier"

# Mixamo comes in as centimetres scaled by 0.01 and turned upright: bake that in.
world = body.matrix_world.copy()
body.parent = None
body.matrix_world = world
for o in (rig, body):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
body.parent = rig
body.matrix_parent_inverse = Matrix.Identity(4)
for m in body.modifiers:
    if m.type == "ARMATURE":
        m.object = rig


def rest_local(arm, name):
    b = arm.data.bones[name]
    return b.parent.matrix_local.inverted() @ b.matrix_local if b.parent else b.matrix_local


# --- The clips, as actions on the rig ---------------------------------------------------
# The game played these clips (made by Mixamo for an earlier rig, v005) by
# copying each joint's angle to its own parent onto the new rig, and fitting
# the hips' movement to its legs. The same conversion here, so the actions
# look exactly as they did in the game.

rig.animation_data_create()
rig.rotation_mode = "XYZ"
for pb in rig.pose.bones:
    pb.rotation_mode = "QUATERNION"
rig_hips_height = rig.data.bones[HIPS].head_local.z

for action_name, clip in CLIPS.items():
    objs = import_fbx(os.path.join(clips_dir, clip + ".fbx"))
    src = next(o for o in objs if o.type == "ARMATURE")
    src_act = src.animation_data.action
    to_world = src.matrix_world.copy()
    src_rot = to_world.to_quaternion()
    hip_scale = rig_hips_height / CLIP_HIPS_HEIGHT
    rest_a = {b.name: rest_local(src, b.name) for b in src.data.bones}
    rest_b = {b.name: rest_local(rig, b.name) for b in rig.data.bones}
    act = bpy.data.actions.new(action_name)
    act.use_fake_user = True
    rig.animation_data.action = act
    start, end = (int(round(f)) for f in src_act.frame_range)
    last = {}
    for frame in range(start, end + 1):
        scene.frame_set(frame)
        for pb in rig.pose.bones:
            name = pb.name
            if name not in src.pose.bones:
                continue
            basis_a = src.pose.bones[name].matrix_basis
            local_a = rest_a[name] @ basis_a
            if name == HIPS:
                q = src_rot @ local_a.to_quaternion()
                loc = (to_world @ local_a.translation) * hip_scale
                basis_b = rest_b[name].inverted() @ Matrix.LocRotScale(loc, q, None)
                pb.location = basis_b.translation
                pb.keyframe_insert("location", frame=frame - start)
            else:
                basis_b = rest_b[name].inverted() @ Matrix.LocRotScale(None, local_a.to_quaternion(), None)
            q_b = basis_b.to_quaternion()
            if name in last:
                q_b.make_compatible(last[name])
            last[name] = q_b
            pb.rotation_quaternion = q_b
            pb.keyframe_insert("rotation_quaternion", frame=frame - start)
    print("clip %-8s <- %-18s frames %d, hips scaled %.4f" % (action_name, clip, end - start + 1, hip_scale))
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.actions.remove(src_act)

for a in list(bpy.data.actions):
    if a.name not in CLIPS:
        bpy.data.actions.remove(a)
rig.animation_data.action = bpy.data.actions["idle"]
for pb in rig.pose.bones:
    pb.matrix_basis = Matrix.Identity(4)
scene.frame_start, scene.frame_end = 0, int(bpy.data.actions["idle"].frame_range[1])
scene.frame_set(0)

# --- First-person arms: the sleeves and gloves, cut from the body -----------------------
# Triangles whose corners all carry at least half their weight on bones named
# *Arm* or *Hand* (the rule the game used to cut them at runtime).

arms = body.copy()
arms.data = body.data.copy()
arms.name = "FP_Arms"
arms.data.name = "FP_Arms"
scene.collection.objects.link(arms)
bpy.ops.object.select_all(action="DESELECT")
arms.select_set(True)
bpy.context.view_layer.objects.active = arms
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.quads_convert_to_tris()
bpy.ops.object.mode_set(mode="OBJECT")
arm_groups = {g.index for g in arms.vertex_groups if any(p in g.name for p in ARM_PARTS)}
on_arm = [sum(ge.weight for ge in v.groups if ge.group in arm_groups) >= 0.5 for v in arms.data.vertices]
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="DESELECT")
bpy.ops.object.mode_set(mode="OBJECT")
for poly in arms.data.polygons:
    poly.select = not all(on_arm[i] for i in poly.vertices)
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.delete(type="FACE")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.delete_loose()
bpy.ops.object.mode_set(mode="OBJECT")
print("FP_Arms: %d of %d triangles" % (len(arms.data.polygons), sum(len(p.vertices) - 2 for p in body.data.polygons)))

# --- Guns -------------------------------------------------------------------------------

before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=guns_glb)
gun_objs = [o for o in bpy.data.objects if o not in before]
holder = next(o for o in gun_objs if o.name == "Guns")
roots = list(holder.children)
for o in gun_objs:
    if o is holder or o in roots:
        continue
    o.name = re.sub(r"\d+$", "", o.name)  # Godot numbered repeats; Blender adds .001 instead
    if o.type == "MESH":
        o.data.name = o.name
    if o.type == "EMPTY" and not o.children:
        o.empty_display_type = "SPHERE"  # the markers: muzzle and hands
        o.empty_display_size = 0.015
for r in roots:
    w = r.matrix_world.copy()
    r.parent = None
    r.matrix_world = w
bpy.data.objects.remove(holder, do_unlink=True)
# Laid out beside the soldier for viewing; the game only uses each gun's
# parts and markers relative to its root, not where the root is.
layout = {"Shotgun_3P": (0.7, 0.0, 1.0), "Rifle_3P": (0.7, 0.0, 1.25),
          "Shotgun_FP": (-0.9, 0.0, 1.0), "Rifle_FP": (-0.9, 0.0, 1.35)}
for r in roots:
    r.location = layout[r.name]
    r.rotation_euler = (0.0, 0.0, 0.0)
    r.empty_display_size = 0.1

# --- Tidy up and save -------------------------------------------------------------------

move_to(rig, collection("Character"))
move_to(arms, collection("First-person arms"))
guns3p = collection("Guns, third person")
gunsfp = collection("Guns, first person")
for r in roots:
    move_to(r, guns3p if r.name.endswith("_3P") else gunsfp)
for c in list(scene.collection.children):
    if c.name == "Collection":
        bpy.data.collections.remove(c)
bpy.context.view_layer.layer_collection.children["First-person arms"].hide_viewport = True
bpy.ops.wm.save_as_mainfile(filepath=out_blend, compress=True)
print("saved", out_blend)
