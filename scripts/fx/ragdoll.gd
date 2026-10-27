class_name Ragdoll
extends Node3D
## Halo 2 handed its dead to Havok: the body goes limp and is thrown along the
## killing shot, hardest by a point-blank shotgun. A copy of the soldier's
## character takes its last pose, then one rigid capsule per limb segment
## moves its bones. The capsules collide only with the level.

# segment -> [bone it moves, bone at its far end, radius, mass, share of the fling]
const SEGMENTS := {
	"torso": ["Hips", "Neck", 0.16, 20.0, 1.0],
	"head": ["Head", "HeadTop_End", 0.11, 4.0, 1.0],
	"arm_l": ["LeftArm", "LeftForeArm", 0.06, 2.5, 0.9],
	"fore_l": ["LeftForeArm", "LeftHandMiddle1", 0.05, 2.0, 0.9],
	"arm_r": ["RightArm", "RightForeArm", 0.06, 2.5, 0.9],
	"fore_r": ["RightForeArm", "RightHandMiddle1", 0.05, 2.0, 0.9],
	"thigh_l": ["LeftUpLeg", "LeftLeg", 0.085, 7.0, 0.6],
	"shin_l": ["LeftLeg", "LeftFoot", 0.065, 4.0, 0.5],
	"thigh_r": ["RightUpLeg", "RightLeg", 0.085, 7.0, 0.6],
	"shin_r": ["RightLeg", "RightFoot", 0.065, 4.0, 0.5],
}
# [parent, child, "cone", swing, twist] or [parent, child, "hinge", most bend,
# which way a straight limb bends: +1 elbows (about the right side), -1 knees]
const JOINTS := [
	["torso", "head", "cone", 35.0, 30.0],
	["torso", "arm_l", "cone", 80.0, 40.0],
	["torso", "arm_r", "cone", 80.0, 40.0],
	["torso", "thigh_l", "cone", 55.0, 15.0],
	["torso", "thigh_r", "cone", 55.0, 15.0],
	["arm_l", "fore_l", "hinge", 140.0, 1.0],
	["arm_r", "fore_r", "hinge", 140.0, 1.0],
	["thigh_l", "shin_l", "hinge", 135.0, -1.0],
	["thigh_r", "shin_r", "hinge", 135.0, -1.0],
]
const SINK_TIME := 1.0  # seconds spent sinking out of sight at the end

static var _live := []
static var _material: PhysicsMaterial

var _character: Node3D
var _skeleton: Skeleton3D
var _bone := {}  # segment -> bone index
var _offset := {}  # segment -> bone transform relative to its body
var _order: Array[String] = []  # segments, parents' bones first
var _bodies := {}  # segment -> RigidBody3D
var _prev := {}
var _curr := {}
var _age := 0.0
var _still := 0.0
var _frozen := false


## Swaps a soldier who just died for a body thrown at `speed` along `dir`.
static func spawn(s: Soldier, dir: Vector3, speed: float, head_hit := false) -> Ragdoll:
	var r := Ragdoll.new()
	r.top_level = true
	s.fx_root().add_child(r)
	r._build(s, dir, speed, head_hit)
	_live = _live.filter(func(x: Variant) -> bool: return is_instance_valid(x) and not (x as Node).is_queued_for_deletion())
	_live.append(r)
	if _live.size() > GameConfig.RAGDOLL_MAX:
		(_live.pop_front() as Node).queue_free()
	return r


static func fling_speed(cause: String, damage: float) -> float:
	match cause:
		"shotgun":
			var point_blank := GameConfig.SG_PELLETS * GameConfig.SG_PELLET_DAMAGE
			var k := clampf(inverse_lerp(GameConfig.MAX_HEALTH, point_blank, damage), 0.0, 1.0)
			return lerpf(GameConfig.FLING_SHOTGUN_MIN, GameConfig.FLING_SHOTGUN_MAX, k)
		"rifle":
			return GameConfig.FLING_RIFLE
		"headshot":
			return GameConfig.FLING_HEADSHOT
		"maxim":
			return GameConfig.FLING_MAXIM
		"melee":
			return GameConfig.FLING_MELEE
	return 0.0


func _build(s: Soldier, dir: Vector3, speed: float, head_hit: bool) -> void:
	var model := s.model
	var src := model.skeleton
	# A copy of the character in the soldier's last pose. The model is drawn a
	# fraction of a tick behind, so start it from the physics position.
	_character = SoldierModel.make_character(s.team)
	add_child(_character)
	var to_world := Transform3D(model.global_transform.basis, s.global_position) * model.global_transform.affine_inverse()
	_character.global_transform = to_world * (src.get_parent() as Node3D).global_transform
	_skeleton = _character.get_node("Skeleton3D")
	for b in src.get_bone_count():
		_skeleton.set_bone_pose_position(b, src.get_bone_pose_position(b))
		_skeleton.set_bone_pose_rotation(b, src.get_bone_pose_rotation(b))
	var skel_xf := _skeleton.global_transform

	var away := Vector3(dir.x, 0, dir.z)
	if away.length_squared() < 0.01:
		away = model.global_transform.basis.z  # falls and the like: go over backwards
	away = away.normalized()
	var push := away * speed + Vector3.UP * speed * GameConfig.FLING_LIFT
	for seg: String in SEGMENTS:
		var spec: Array = SEGMENTS[seg]
		var bone := _skeleton.find_bone("mixamorig_" + spec[0])
		var bone_xf := skel_xf * _skeleton.get_bone_global_pose(bone)
		var tip := skel_xf * _skeleton.get_bone_global_pose(_skeleton.find_bone("mixamorig_" + spec[1])).origin
		var along := tip - bone_xf.origin
		var radius: float = spec[2]
		var xf := Transform3D(Basis(Quaternion(Vector3.UP, along.normalized())), (bone_xf.origin + tip) * 0.5)
		var body := RigidBody3D.new()
		body.name = seg
		body.transform = xf  # the ragdoll sits at the origin, so this is global
		body.collision_layer = GameConfig.LAYER_DEBRIS
		body.collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_MOVING
		body.mass = spec[3]
		body.continuous_cd = true
		body.linear_damp = 0.1
		body.angular_damp = 2.0
		body.physics_material_override = _physics_material()
		var capsule := CapsuleShape3D.new()
		capsule.radius = radius
		capsule.height = maxf(along.length() + radius, radius * 2.0)
		var cs := CollisionShape3D.new()
		cs.shape = capsule
		body.add_child(cs)
		add_child(body)
		var share: float = spec[4]
		if head_hit and seg == "head":
			share *= 1.6
		body.linear_velocity = s.velocity + push * share
		if seg == "torso" or seg == "head":
			# Even a gentle kill buckles the knees instead of leaving the body balanced.
			body.linear_velocity += away * 1.2
		if seg == "torso":
			body.angular_velocity = Vector3.UP.cross(away) * 2.5
		_bodies[seg] = body
		_bone[seg] = bone
		_offset[seg] = xf.affine_inverse() * bone_xf
		_prev[seg] = xf
		_curr[seg] = xf
	_order.assign(SEGMENTS.keys())
	_order.sort_custom(func(a: String, b: String) -> bool: return _bone[a] < _bone[b])

	var right := (skel_xf.basis * Vector3.LEFT).normalized()  # the character faces +Z in its skeleton
	for j: Array in JOINTS:
		var a: RigidBody3D = _bodies[j[0]]
		var b: RigidBody3D = _bodies[j[1]]
		var pivot := skel_xf * _skeleton.get_bone_global_pose(_bone[j[1]]).origin
		var child_dir := (b.position - pivot).normalized()
		var joint: Joint3D
		if j[2] == "cone":
			# The twist axis (local X) runs from the joint out along the child limb.
			var cone := ConeTwistJoint3D.new()
			cone.transform = Transform3D(Basis(Quaternion(Vector3.RIGHT, child_dir)), pivot)
			cone.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(j[3]))
			cone.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(j[4]))
			joint = cone
		else:
			# The hinge axis (local Z) is the one the limb is already bent about,
			# so the limits are measured from its bend at the moment of death.
			# Godot counts the hinge angle the other way: bending is negative.
			var parent_dir := (pivot - a.position).normalized()
			var axis := parent_dir.cross(child_dir)
			var bent := atan2(axis.length(), parent_dir.dot(child_dir))
			axis = axis.normalized() if axis.length() > 0.05 else right * float(j[4])
			var hinge := HingeJoint3D.new()
			hinge.transform = Transform3D(Basis(Quaternion(Vector3.BACK, axis)), pivot)
			hinge.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, bent - deg_to_rad(j[3]))
			hinge.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, bent)
			joint = hinge
		joint.node_a = NodePath("../" + a.name)
		joint.node_b = NodePath("../" + b.name)
		add_child(joint)


static func _physics_material() -> PhysicsMaterial:
	if _material == null:
		_material = PhysicsMaterial.new()
		_material.friction = 0.9
		_material.bounce = 0.05
	return _material


func torso_position() -> Vector3:
	return (_bodies["torso"] as RigidBody3D).global_position


## Where the death camera looks.
func focus() -> Vector3:
	var f := Engine.get_physics_interpolation_fraction()
	return (_prev["torso"] as Transform3D).origin.lerp((_curr["torso"] as Transform3D).origin, f)


func _physics_process(delta: float) -> void:
	_age += delta
	for seg: String in _bodies:
		_prev[seg] = _curr[seg]
		_curr[seg] = (_bodies[seg] as RigidBody3D).global_transform
	if _age > GameConfig.RAGDOLL_LIFETIME or torso_position().y < GameConfig.KILL_Y:
		queue_free()
	elif not _frozen:
		_settle(delta)


## Godot's joints never quite come to rest, so a body that has stopped moving
## is frozen in place: no twitching corpses, and no physics cost.
func _settle(delta: float) -> void:
	var fastest := 0.0
	for b: RigidBody3D in _bodies.values():
		fastest = maxf(fastest, b.linear_velocity.length())
	_still = _still + delta if fastest < 0.6 and _age > 1.0 else 0.0
	if _still < 0.4 and _age < 4.0:
		return
	_frozen = true
	for b: RigidBody3D in _bodies.values():
		b.freeze = true
		b.collision_mask = 0


func _process(_delta: float) -> void:
	var sink := clampf((_age - GameConfig.RAGDOLL_LIFETIME + SINK_TIME) / SINK_TIME, 0.0, 1.0)
	if sink > 0.0:
		# Frozen by now: the posed body just sinks out of sight.
		_character.position.y = -0.7 * sink
		return
	if _frozen and _prev["torso"] == _curr["torso"]:
		return
	var f := Engine.get_physics_interpolation_fraction()
	var to_skel := _skeleton.global_transform.affine_inverse()
	for seg in _order:
		var body_xf: Transform3D = (_prev[seg] as Transform3D).interpolate_with(_curr[seg], f)
		_skeleton.set_bone_global_pose(_bone[seg], (to_skel * body_xf * _offset[seg]).orthonormalized())
