class_name SoldierModel
extends Node3D
## The soldier on screen: the custom character, played with the Mixamo clips
## (see SoldierAnims). Both teams share the model and the Reds' wool is dyed
## red. Legs run, strafe or leap from the clips while the upper body holds the
## aiming pose. The spine then turns so the gun line points where the soldier
## aims, crouching lowers the hips and bends the knees with the feet planted,
## and the gun is placed between the hands. On death a Ragdoll takes over.

const RED_WOOL := Color(0.6, 0.1, 0.08)
const CROUCH_DROP := 0.55  # metres the hips sink when crouched
const BOB_KEEP := 0.35  # share of the run's up-and-down bounce kept
const BOB_RANGE := 35.0  # metres from the camera
const UPPER_BODY := ["Spine", "Neck", "Head", "Shoulder", "Arm", "Hand"]

static var _scene: PackedScene
static var _tree_root: AnimationNodeBlendTree
static var _red_wool: Material

var team := GameConfig.TEAM_WHITE
var skeleton: Skeleton3D

var _character: Node3D
var _tree: AnimationTree
var _bone := {}  # name without the "mixamorig_" prefix -> index
var _gun: Node3D  # the gun currently held
var _muzzle: Node3D
var _grip := Vector3.ZERO  # where the right hand holds the gun, in the gun's space
var _guns := {}  # kind -> [node, muzzle, grip]
var _meshes: Array[GeometryInstance3D] = []
var _kick := 0.0
var _crouch := 0.0
var _air := 0.0
var _air_time := 0.0
var _hips_avg := INF
var _soldier: Soldier


## A fresh copy of the character in its team colours, also used for ragdolls.
## The character from the .blend, its skeleton straight under the root (as
## the clips and this code expect) and showing one mesh: the body
## ("Soldier") or the first-person arms ("FP_Arms").
static func make_character(p_team: int, keep := "Soldier") -> Node3D:
	if _scene == null:
		_scene = load(SoldierAnims.CHARACTER)
	var c := _scene.instantiate() as Node3D
	var sk := c.find_child("Skeleton3D") as Skeleton3D
	var holder := sk.get_parent() as Node3D
	if holder != c:
		var xf := holder.transform * sk.transform
		holder.remove_child(sk)
		c.add_child(sk)
		sk.transform = xf
		holder.free()
	for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", false, false):
		if mi.name != keep:
			mi.free()
	var player := c.get_node_or_null("AnimationPlayer")
	if player:
		c.remove_child(player)
		player.free()
	# Mixamo faces +Z and the game faces -Z. Scale it to the hitbox, by its
	# own height to the top of its head.
	var head_top := sk.get_bone_global_rest(sk.find_bone("mixamorig_HeadTop_End")).origin.y
	c.rotation.y = PI
	c.scale = Vector3.ONE * (GameConfig.STAND_HEIGHT - 0.02) / head_top
	if p_team == GameConfig.TEAM_RED:
		for mi in c.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i)
				if m and m.resource_name.begins_with("White Wool"):
					(mi as MeshInstance3D).set_surface_override_material(i, _dyed(m))
	return c


static func _dyed(white: Material) -> Material:
	if _red_wool == null:
		_red_wool = white.duplicate()
		(_red_wool as BaseMaterial3D).albedo_color = RED_WOOL
	return _red_wool


func _ready() -> void:
	# Drawn at the soldier's interpolated position so 60 Hz physics still
	# looks smooth on fast monitors.
	_soldier = get_parent() as Soldier
	top_level = true
	_character = make_character(team)
	add_child(_character)
	skeleton = _character.get_node("Skeleton3D")
	for b in skeleton.get_bone_count():
		_bone[skeleton.get_bone_name(b).trim_prefix("mixamorig_")] = b
	for mi in _character.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(mi)
	_tree = AnimationTree.new()
	_tree.add_animation_library("", SoldierAnims.library())
	_tree.tree_root = _blend_tree(skeleton)
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_character.add_child(_tree)
	_tree.set("parameters/aim/blend_amount", 1.0)
	_tree.active = true
	_build_guns()
	set_weapon("shotgun")


## Legs: idle, run, backpedal and strafes blended by velocity, then the leap
## while airborne. Upper body: always the aiming idle.
static func _blend_tree(sk: Skeleton3D) -> AnimationNodeBlendTree:
	if _tree_root:
		return _tree_root
	var move := AnimationNodeBlendSpace2D.new()
	move.sync = true
	for point: Array in [["idle", Vector2.ZERO], ["run", Vector2(0, 1)], ["back", Vector2(0, -1)],
			["strafe_r", Vector2(1, 0)], ["strafe_l", Vector2(-1, 0)]]:
		move.add_blend_point(_clip(point[0]), point[1])
	var aim := AnimationNodeBlend2.new()
	aim.filter_enabled = true
	for b in sk.get_bone_count():
		var bone := sk.get_bone_name(b)
		for part: String in UPPER_BODY:
			if bone.contains(part):
				aim.set_filter_path(NodePath("Skeleton3D:" + bone), true)
				break
	var bt := AnimationNodeBlendTree.new()
	bt.add_node("move", move)
	bt.add_node("rate", AnimationNodeTimeScale.new())
	bt.add_node("air_pose", _clip("air"))
	bt.add_node("air", AnimationNodeBlend2.new())
	bt.add_node("aim_pose", _clip("idle"))
	bt.add_node("aim", aim)
	bt.connect_node("rate", 0, "move")
	bt.connect_node("air", 0, "rate")
	bt.connect_node("air", 1, "air_pose")
	bt.connect_node("aim", 0, "air")
	bt.connect_node("aim", 1, "aim_pose")
	bt.connect_node("output", 0, "aim")
	_tree_root = bt
	return bt


static func _clip(name: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = name
	return a


func _build_guns() -> void:
	for kind in ["shotgun", "rifle"]:
		var gun := GunModels.make("Shotgun_3P" if kind == "shotgun" else "Rifle_3P")
		add_child(gun)
		for mi in gun.find_children("*", "MeshInstance3D", true, false):
			_meshes.append(mi)
		_guns[kind] = [gun, GunModels.part(gun, "Muzzle"), GunModels.part(gun, "Hand_R").position]


func set_weapon(kind: String) -> void:
	for k in _guns:
		(_guns[k][0] as Node3D).visible = k == kind
	var g: Array = _guns.get(kind, _guns["shotgun"])
	_gun = g[0]
	_muzzle = g[1]
	_grip = g[2]


## First person hides the body but keeps its shadow.
func set_first_person(on: bool) -> void:
	for mi in _meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func muzzle_position() -> Vector3:
	return _muzzle.global_position


func kick() -> void:
	_kick = 1.0


func _process(delta: float) -> void:
	if _soldier == null:
		return
	global_position = _soldier.interpolated_position()
	if visible:
		_animate(_soldier, delta)


func _animate(s: Soldier, delta: float) -> void:
	var aim_pitch := clampf(s.look_pitch, -1.2, 1.2)
	rotation.y = s.look_yaw
	if s.turret:
		rotation.y = s.turret.base_yaw() + s.turret.yaw
		aim_pitch = s.turret.pitch
	_gun.visible = s.turret == null
	# Legs follow the velocity, measured in the soldier's own frame.
	var yaw_basis := Basis(Vector3.UP, rotation.y)
	var local := Vector2(s.velocity.dot(yaw_basis.x), s.velocity.dot(-yaw_basis.z))
	var speed := local.length()
	var top_speed := GameConfig.CROUCH_SPEED if s.crouched else GameConfig.RUN_SPEED
	var on_floor := s.on_ground() or s.turret != null
	var blend := Vector2.ZERO
	var rate := 1.0
	if speed > 0.3 and on_floor:
		blend = (local / top_speed).limit_length(1.0)
		var dir := local / speed
		var stride := (absf(dir.y) * float(SoldierAnims.stride["run" if dir.y > 0.0 else "back"])
			+ absf(dir.x) * float(SoldierAnims.stride["strafe_r" if dir.x > 0.0 else "strafe_l"])) / (absf(dir.x) + absf(dir.y))
		var clip_speed := stride * _character.scale.x / SoldierAnims.CYCLE
		rate = clampf(speed / clip_speed, 0.6, 2.4)
	_air_time = 0.0 if on_floor else _air_time + delta
	_air = move_toward(_air, 1.0 if _air_time > 0.12 else 0.0, delta * (5.0 if _air_time > 0.0 else 10.0))
	_crouch = move_toward(_crouch, 1.0 if s.crouched else 0.0, delta * 6.0)
	_kick = maxf(0.0, _kick - delta * 6.0)
	_tree.set("parameters/move/blend_position", blend)
	_tree.set("parameters/rate/scale", rate)
	_tree.set("parameters/air/blend_amount", _air)
	_tree.advance(delta)

	# Sped up to the game's pace the run bobs hard: keep a third of the hips'
	# bounce around their running average (and sink them when crouched),
	# bending the legs so the feet stay where the clip put them.
	# Past BOB_RANGE the bounce can't be seen, so only crouching bends legs.
	var hips_y := skeleton.get_bone_pose_position(_bone["Hips"]).y
	_hips_avg = hips_y if _hips_avg == INF else lerpf(_hips_avg, hips_y, 1.0 - exp(-delta * 4.0))
	var cam := get_viewport().get_camera_3d()
	var near := cam == null or cam.global_position.distance_squared_to(global_position) < BOB_RANGE * BOB_RANGE
	var drop := (hips_y - _hips_avg) * (1.0 - BOB_KEEP) * (1.0 if near else 0.0) + _crouch * CROUCH_DROP / _character.scale.x
	if absf(drop) > 0.002:
		_lower_hips(drop)
	var swing := clampf((s.now() - s.melee_time) / 0.3, 0.0, 1.0)
	var melee := sin(swing * PI) if swing < 1.0 else 0.0
	_aim_spine(aim_pitch + _kick * 0.12 - melee * 0.35, melee * 0.6)
	_place_gun()


func _grip_point(side: String) -> Vector3:
	var hand := skeleton.get_bone_global_pose(_bone[side + "Hand"]).origin
	var knuckles := skeleton.get_bone_global_pose(_bone[side + "HandMiddle1"]).origin
	return (hand + knuckles) * 0.5


## Turns the spine so the line from the right hand to the left (the gun)
## points along the aim. This also undoes the hips' twist in the strafes.
## Skeleton space: the character faces +Z.
func _aim_spine(pitch: float, twist: float) -> void:
	var now := (_grip_point("Left") - _grip_point("Right")).normalized()
	var want := Vector3(0, sin(pitch), cos(pitch)).rotated(Vector3.UP, twist)
	var turn := Quaternion(now, want)
	var step := Basis(Quaternion.IDENTITY.slerp(turn, 1.0 / 3.0))
	for name in ["Spine", "Spine1", "Spine2"]:
		var b: int = _bone[name]
		turn_bone_to(skeleton, b, step * skeleton.get_bone_global_pose(b).basis)


## Sets a bone's rotation so its skeleton-space orientation becomes `rot`.
## Only rotations (and the hips' position) are ever changed after the clips
## play. The clips rewrite those every frame, so nothing can build up. Bone
## lengths and scales stay exactly as rigged.
static func turn_bone_to(sk: Skeleton3D, b: int, rot: Basis) -> void:
	var parent := sk.get_bone_parent(b)
	var parent_rot := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	sk.set_bone_pose_rotation(b, (parent_rot.inverse() * rot.orthonormalized()).get_rotation_quaternion())


## Bends a two-bone limb (thigh and shin, upper arm and forearm) so its end
## bone reaches `target`, as near as the limb's length allows, and turns the
## end to the target's orientation. The joint bends towards `pole`, keeping
## whatever bend the pose already has.
static func two_bone_ik(sk: Skeleton3D, upper: int, lower: int, end: int, target: Transform3D, pole: Vector3) -> void:
	var root := sk.get_bone_global_pose(upper)
	var joint := sk.get_bone_global_pose(lower).origin
	var tip := sk.get_bone_global_pose(end).origin
	var a := root.origin.distance_to(joint)
	var b := joint.distance_to(tip)
	var to := target.origin - root.origin
	var along := to.normalized()
	var reach := clampf(to.length(), absf(a - b) + 0.01, a + b - 0.01)
	var bend := ((joint - root.origin).slide(along).normalized() + pole).slide(along).normalized()
	var x := (a * a - b * b + reach * reach) / (2.0 * reach)
	var joint_want := root.origin + along * x + bend * sqrt(maxf(a * a - x * x, 0.0))
	_swing(sk, upper, root, joint, joint_want)
	_swing(sk, lower, sk.get_bone_global_pose(lower), sk.get_bone_global_pose(end).origin, root.origin + along * reach)
	turn_bone_to(sk, end, target.basis)


static func _swing(sk: Skeleton3D, b: int, pose: Transform3D, child_now: Vector3, child_want: Vector3) -> void:
	var q := Quaternion((child_now - pose.origin).normalized(), (child_want - pose.origin).normalized())
	turn_bone_to(sk, b, Basis(q) * pose.basis)


## Sinks the hips (or lifts them, for a negative drop) and bends each knee so
## the feet stay where the clip put them.
func _lower_hips(drop: float) -> void:
	var feet := []
	for side in ["Left", "Right"]:
		feet.append(skeleton.get_bone_global_pose(_bone[side + "Foot"]))
	var hips: int = _bone["Hips"]
	skeleton.set_bone_pose_position(hips, skeleton.get_bone_pose_position(hips) - Vector3(0, drop, 0))
	for i in 2:
		var side: String = ["Left", "Right"][i]
		# Knees bend forward (+Z here), the way the clip already bends them.
		two_bone_ik(skeleton, _bone[side + "UpLeg"], _bone[side + "Leg"], _bone[side + "Foot"], feet[i], Vector3(0, 0, 1))


func _place_gun() -> void:
	var to_world := skeleton.global_transform
	var right := to_world * _grip_point("Right")
	var left := to_world * _grip_point("Left")
	var fwd := (left - right).normalized()
	var xf := Transform3D(Basis.looking_at(fwd, global_transform.basis.y), right)
	_gun.global_transform = xf.translated_local(-_grip + Vector3(0, 0, _kick * 0.08))
