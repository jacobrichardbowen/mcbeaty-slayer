class_name Ragdoll
extends Node3D
## Halo 2 handed its dead to Havok: the body goes limp and is thrown along the
## killing shot, hardest by a point-blank shotgun. This copies a soldier's
## primitive parts onto jointed rigid bodies that only collide with the level.

# part -> [centre in the model's part frame, collision box (radius for the head), mass, share of the fling]
const PARTS := {
	"torso": [Vector3(0, 1.1, 0), Vector3(0.48, 1.1, 0.34), 24.0, 1.0],
	"head": [Vector3(0, 0.62, 0), Vector3(0.15, 0, 0), 5.0, 1.0],
	"leg_l": [Vector3(0, -0.45, 0), Vector3(0.18, 0.9, 0.22), 9.0, 0.55],
	"leg_r": [Vector3(0, -0.45, 0), Vector3(0.18, 0.9, 0.22), 9.0, 0.55],
	"arm_l": [Vector3(-0.31, 0.13, 0), Vector3(0.12, 0.6, 0.12), 4.0, 0.9],
	"arm_r": [Vector3(0.31, 0.13, 0), Vector3(0.12, 0.6, 0.12), 4.0, 0.9],
}
# [parent, child, joint in the child's part frame, swing and twist limits in degrees]
const JOINTS := [
	["torso", "head", Vector3(0, 0.52, 0), 35.0, 30.0],
	["torso", "leg_l", Vector3.ZERO, 55.0, 15.0],
	["torso", "leg_r", Vector3.ZERO, 55.0, 15.0],
	["torso", "arm_l", Vector3(-0.31, 0.43, 0), 80.0, 40.0],
	["torso", "arm_r", Vector3(0.31, 0.43, 0), 80.0, 40.0],
]

static var _live := []
static var _material: PhysicsMaterial

var _bodies := {}  # part -> RigidBody3D
var _visuals := {}  # part -> Node3D, drawn between physics ticks
var _prev := {}
var _curr := {}
var _age := 0.0


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
	# The model is drawn a fraction of a tick behind; start from the physics pose.
	var to_world := Transform3D(model.global_transform.basis, s.global_position) * model.global_transform.affine_inverse()
	var away := Vector3(dir.x, 0, dir.z)
	if away.length_squared() < 0.01:
		away = model.global_transform.basis.z  # falls and the like: go over backwards
	away = away.normalized()
	var push := away * speed + Vector3.UP * speed * GameConfig.FLING_LIFT
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = model.coat
	sleeve.roughness = 0.85
	for part: String in PARTS:
		var spec: Array = PARTS[part]
		var xf := (to_world * model.part_frame(part).global_transform).translated_local(spec[0])
		var body := RigidBody3D.new()
		body.name = part
		body.transform = xf  # the ragdoll sits at the origin, so this is global
		body.collision_layer = GameConfig.LAYER_DEBRIS
		body.collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_MOVING
		body.mass = spec[2]
		body.continuous_cd = true
		body.linear_damp = 0.1
		body.angular_damp = 2.0
		body.physics_material_override = _physics_material()
		var cs := CollisionShape3D.new()
		var size: Vector3 = spec[1]
		if part == "head":
			var sphere := SphereShape3D.new()
			sphere.radius = size.x
			cs.shape = sphere
		else:
			var box := BoxShape3D.new()
			box.size = size
			cs.shape = box
		body.add_child(cs)
		add_child(body)
		var share: float = spec[3]
		if head_hit and part == "head":
			share *= 1.6
		body.linear_velocity = s.velocity + push * share
		if part == "torso" or part == "head":
			# Even a gentle kill buckles the knees instead of leaving the body balanced.
			body.linear_velocity += away * 1.2
		if part == "torso":
			body.angular_velocity = Vector3.UP.cross(away) * 2.5
		_bodies[part] = body

		var vis := Node3D.new()
		vis.transform = xf
		add_child(vis)
		var inv := xf.affine_inverse()
		for mi: MeshInstance3D in model.part_meshes(part):
			var copy := mi.duplicate() as MeshInstance3D
			copy.transform = inv * to_world * mi.global_transform
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			vis.add_child(copy)
		if part.begins_with("arm"):
			# The model's arms are posed on the gun; a ragdoll's hang free.
			var arm := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = size
			arm.mesh = mesh
			arm.material_override = sleeve
			vis.add_child(arm)
		_visuals[part] = vis
		_prev[part] = xf
		_curr[part] = xf

	for j: Array in JOINTS:
		var a: RigidBody3D = _bodies[j[0]]
		var b: RigidBody3D = _bodies[j[1]]
		var pivot: Vector3 = (to_world * model.part_frame(j[1]).global_transform) * (j[2] as Vector3)
		var joint := ConeTwistJoint3D.new()
		# The twist axis (local X) runs from the joint out along the child limb.
		joint.transform = Transform3D(Basis(Quaternion(Vector3.RIGHT, (b.position - pivot).normalized())), pivot)
		joint.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(j[3]))
		joint.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(j[4]))
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
	return (_visuals["torso"] as Node3D).global_position


func _physics_process(delta: float) -> void:
	_age += delta
	for part: String in _bodies:
		_prev[part] = _curr[part]
		_curr[part] = (_bodies[part] as RigidBody3D).global_transform
	if _age > GameConfig.RAGDOLL_LIFETIME or torso_position().y < GameConfig.KILL_Y:
		queue_free()


func _process(_delta: float) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	# Shrink away over the last moments rather than popping out.
	var k := clampf((GameConfig.RAGDOLL_LIFETIME - _age) / 0.4, 0.01, 1.0)
	for part: String in _visuals:
		var xf: Transform3D = (_prev[part] as Transform3D).interpolate_with(_curr[part], f)
		if k < 1.0:
			xf.basis = xf.basis.scaled(Vector3.ONE * k)
		(_visuals[part] as Node3D).transform = xf
