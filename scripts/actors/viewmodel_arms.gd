class_name ViewmodelArms
extends Node3D
## The player's own arms in first person: the character's sleeves and gloves
## (FP_Arms in the .blend), on a copy of its skeleton, in the aiming idle's pose
## (fingers curled round a rifle). Every frame the rig is laid along the gun
## so the right hand sits on its grip, and the left arm reaches for the pump
## or fore-stock. The hands follow every pump, kick, reload and swing.

## Arm size against the viewmodel's (quarter-scale) guns.
const SCALE := 1.1
## Elbows hang down and out (skeleton space: the character faces +Z).
const POLE := {"Right": Vector3(-0.7, -1.0, 0.0), "Left": Vector3(0.7, -1.0, 0.0)}

var team := GameConfig.TEAM_WHITE

var _sk: Skeleton3D
var _bone := {}
var _character: Node3D
var _hand_on_grip := {}  # side -> hand relative to its grip, in the aiming pose
var _hold := Transform3D()  # the aiming pose's gun line, at its right grip
var _base_pose := {}  # bone -> rotation in the aiming pose


func _ready() -> void:
	_character = SoldierModel.make_character(team, "FP_Arms")
	add_child(_character)
	_sk = _character.get_node("Skeleton3D")
	for b in _sk.get_bone_count():
		_bone[_sk.get_bone_name(b).trim_prefix("mixamorig_")] = b
	for mi: MeshInstance3D in _sk.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The first frame of the aiming idle: fingers curled round a rifle.
	var idle := SoldierAnims.library().get_animation("idle")
	for t in idle.get_track_count():
		var b := _sk.find_bone(str(idle.track_get_path(t)).get_slice(":", 1))
		if b < 0:
			continue
		if idle.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			_sk.set_bone_pose_rotation(b, idle.rotation_track_interpolate(t, 0.0))
		elif idle.track_get_type(t) == Animation.TYPE_POSITION_3D:
			_sk.set_bone_pose_position(b, idle.position_track_interpolate(t, 0.0))
	var r := _grip("Right")
	var l := _grip("Left")
	var basis := Basis.looking_at(l - r, Vector3.UP)
	_hold = Transform3D(basis, r)
	_hand_on_grip["Right"] = _hold.affine_inverse() * _sk.get_bone_global_pose(_bone["RightHand"])
	_hand_on_grip["Left"] = Transform3D(basis, l).affine_inverse() * _sk.get_bone_global_pose(_bone["LeftHand"])
	for side in ["Right", "Left"]:
		for part in ["Arm", "ForeArm", "Hand"]:
			var b: int = _bone[side + part]
			_base_pose[b] = _sk.get_bone_pose_rotation(b)


func _grip(side: String) -> Vector3:
	return (_sk.get_bone_global_pose(_bone[side + "Hand"]).origin
		+ _sk.get_bone_global_pose(_bone[side + "HandMiddle1"]).origin) * 0.5


## Puts the right hand on `gun`'s grip and the left on its fore-grip, both
## given in the local space of the nodes that carry them.
func hold(gun: Node3D, right_grip: Vector3, fore: Node3D, left_grip: Vector3) -> void:
	# Lay the aiming pose along the gun, its right grip on the gun's.
	var to_here := global_transform.affine_inverse()
	var g := to_here * gun.global_transform
	var along := Transform3D(Basis.looking_at(-g.basis.z, g.basis.y), g * right_grip)
	_character.transform = along * Transform3D(Basis.from_scale(Vector3.ONE * SCALE)) * _hold.affine_inverse()
	var to_skel := _sk.global_transform.affine_inverse()
	g = to_skel * gun.global_transform
	var basis := Basis.looking_at(-g.basis.z, g.basis.y)
	var anchors := {"Right": to_skel * (gun.global_transform * right_grip), "Left": to_skel * (fore.global_transform * left_grip)}
	for b: int in _base_pose:
		_sk.set_bone_pose_rotation(b, _base_pose[b])
	for side: String in anchors:
		var hand: Transform3D = Transform3D(basis, anchors[side]) * _hand_on_grip[side]
		SoldierModel.two_bone_ik(_sk, _bone[side + "Arm"], _bone[side + "ForeArm"], _bone[side + "Hand"], hand, POLE[side])
