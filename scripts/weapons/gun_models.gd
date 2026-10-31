class_name GunModels
extends RefCounted
## The guns' looks, from art/TowerOfPower_Soldier.blend (exported to
## assets/weapons/guns.glb by tools/blend/export_blend.py): Shotgun_3P and
## Rifle_3P in soldiers' hands, Shotgun_FP and Rifle_FP in first person
## (drawn at a quarter scale). Each gun holds markers: Muzzle, Hand_R (where
## the right hand grips) and Hand_L (the left hand: on the pump or the
## fore-stock), and the first-person guns their moving parts, Pump and Bolt.
## Blender adds .001 and the like to repeated names, so parts are found by
## how their name starts.

const FILE := "res://assets/weapons/guns.glb"

static var _scene: PackedScene


## A fresh copy of a gun, its root at the origin.
static func make(gun_name: String) -> Node3D:
	if _scene == null:
		_scene = load(FILE)
	var all := _scene.instantiate()
	var gun := all.get_node(gun_name) as Node3D
	all.remove_child(gun)
	all.free()
	gun.transform = Transform3D.IDENTITY
	return gun


## A gun's marker or moving part whose name starts with `prefix`.
static func part(parent: Node, prefix: String) -> Node3D:
	for c in parent.get_children():
		if String(c.name).begins_with(prefix) and not c is MeshInstance3D:
			return c
	push_error("%s has no part named %s" % [parent.name, prefix])
	return null
