class_name MaximTurret
extends Node3D
## The Tower of Power: a Maxim M1910 on a Sokolov mount at the front of the
## Big Tower deck. Infinite ammo, 600 rpm, limited traverse. The gunner stays
## exposed from the sides and from the stair hole behind them.

signal gunner_changed(soldier: Soldier)

var gunner: Soldier = null
var yaw := 0.0  # relative to the mount, radians
var pitch := 0.0

var _cooldown := 0.0
var _yaw_node: Node3D
var _pitch_node: Node3D
var _muzzle: Node3D
var _shield: StaticBody3D


func _ready() -> void:
	_build_model()


func shield_rid() -> RID:
	return _shield.get_rid()


func base_yaw() -> float:
	return global_rotation.y


func seat_position() -> Vector3:
	return global_transform * Vector3(0, 0, 1.25)


func pivot_position() -> Vector3:
	return global_transform * Vector3(0, 1.15, 0)


func muzzle_position() -> Vector3:
	return _muzzle.global_position


func barrel_direction() -> Vector3:
	return -_muzzle.global_transform.basis.z


func can_mount(s: Soldier) -> bool:
	return gunner == null and s.alive and s.turret == null \
		and s.global_position.distance_to(seat_position()) < GameConfig.MG_MOUNT_RANGE


## True if a world-space direction from the pivot is inside the traverse limits.
func in_arc(dir: Vector3) -> bool:
	var y := atan2(-dir.x, -dir.z)
	var rel := wrapf(y - base_yaw(), -PI, PI)
	var p := asin(clampf(dir.normalized().y, -1.0, 1.0))
	return absf(rel) <= deg_to_rad(GameConfig.MG_YAW_LIMIT) \
		and p >= deg_to_rad(GameConfig.MG_PITCH_MIN) and p <= deg_to_rad(GameConfig.MG_PITCH_MAX)


func mount(s: Soldier) -> void:
	gunner = s
	s.turret = self
	s.velocity = Vector3.ZERO
	s.global_position = seat_position()
	s.snap_interpolation()
	Sfx.play_3d(self, "mount", pivot_position(), -4.0)
	gunner_changed.emit(s)


func dismount() -> void:
	if gunner == null:
		return
	var s := gunner
	gunner = null
	s.turret = null
	gunner_changed.emit(null)


## Called from the gunner's physics tick. look_yaw/look_pitch are the
## world-space direction the gunner wants the barrel to point.
func drive(s: Soldier, delta: float) -> void:
	var want_yaw := clampf(wrapf(s.look_yaw - base_yaw(), -PI, PI), -deg_to_rad(GameConfig.MG_YAW_LIMIT), deg_to_rad(GameConfig.MG_YAW_LIMIT))
	var want_pitch := clampf(s.look_pitch, deg_to_rad(GameConfig.MG_PITCH_MIN), deg_to_rad(GameConfig.MG_PITCH_MAX))
	var step := deg_to_rad(GameConfig.MG_TURN_RATE) * delta
	yaw = move_toward(yaw, want_yaw, step)
	pitch = move_toward(pitch, want_pitch, step)
	_yaw_node.rotation.y = yaw
	_pitch_node.rotation.x = pitch
	_cooldown -= delta
	if s.in_fire:
		if _cooldown <= 0.0:
			_fire(s)
			_cooldown = maxf(_cooldown + GameConfig.MG_FIRE_INTERVAL, 0.0)
	else:
		_cooldown = maxf(_cooldown, 0.0)


func _fire(s: Soldier) -> void:
	s.last_fire_time = s.now()
	var from := muzzle_position()
	var basis := Basis.looking_at(barrel_direction(), Vector3.UP)
	var spread := deg_to_rad(GameConfig.MG_SPREAD)
	var ang := spread * sqrt(randf())
	var rot := randf() * TAU
	var dir := basis * Vector3(sin(ang) * cos(rot), sin(ang) * sin(rot), -cos(ang))
	var exclude: Array[RID] = [s.get_rid(), _shield.get_rid()]
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * GameConfig.MG_RANGE, GameConfig.MASK_SHOT, exclude)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	var fx_root := s.fx_root()
	var end := from + dir * GameConfig.MG_RANGE
	if not r.is_empty():
		end = r.position
		var col: Object = r.collider
		if col is Soldier:
			(col as Soldier).take_damage(GameConfig.MG_DAMAGE, s, "maxim", end, dir)
			Fx.blood(fx_root, end, dir)
		else:
			Fx.impact(fx_root, end, r.normal)
	Fx.tracer(fx_root, from, end)
	Fx.flash(fx_root, from + dir * 0.1, 3.0, 0.3)
	if s.is_player:
		Sfx.play_2d(self, "maxim", -3.0, 0.05)
	else:
		Sfx.play_3d(self, "maxim", from, 2.0, 0.05, 220.0)
	s.on_turret_fired()


# --- Model: Sokolov wheeled mount with gun shield -------------------------------------

func _part(parent: Node3D, mesh: Mesh, mat_name: String, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(mat_name)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _mat(mat_name: String) -> StandardMaterial3D:
	var colors := {
		"steel": Color(0.22, 0.25, 0.22), "olive": Color(0.3, 0.34, 0.24),
		"brass": Color(0.72, 0.56, 0.25), "rubber": Color(0.08, 0.08, 0.08),
	}
	var m := StandardMaterial3D.new()
	m.albedo_color = colors.get(mat_name, Color.GRAY)
	m.metallic = 0.6 if mat_name != "rubber" else 0.0
	m.roughness = 0.5
	return m


func _cyl(r: float, h: float, segs := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _build_model() -> void:
	# Static carriage: two wheels and the trail.
	for x in [-0.42, 0.42]:
		_part(self, _cyl(0.3, 0.08, 16), "rubber", Vector3(x, 0.3, 0.05), Vector3(0, 0, PI / 2))
		_part(self, _cyl(0.1, 0.1, 8), "steel", Vector3(x, 0.3, 0.05), Vector3(0, 0, PI / 2))
	_part(self, _box(Vector3(0.9, 0.08, 0.08)), "steel", Vector3(0, 0.3, 0.05))
	_part(self, _box(Vector3(0.12, 0.08, 1.0)), "olive", Vector3(0, 0.22, 0.55), Vector3(0.3, 0, 0))

	_yaw_node = Node3D.new()
	_yaw_node.position = Vector3(0, 0.62, 0)
	add_child(_yaw_node)
	_part(_yaw_node, _cyl(0.07, 0.5, 8), "steel", Vector3(0, 0.2, 0))
	# Shield turns with the gun and blocks frontal fire.
	_part(_yaw_node, _box(Vector3(0.95, 0.75, 0.04)), "olive", Vector3(0, 0.5, -0.38))
	_shield = StaticBody3D.new()
	_shield.collision_layer = GameConfig.LAYER_WORLD
	_shield.collision_mask = 0
	_yaw_node.add_child(_shield)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.95, 0.75, 0.06)
	cs.shape = bs
	cs.position = Vector3(0, 0.5, -0.38)
	_shield.add_child(cs)

	_pitch_node = Node3D.new()
	_pitch_node.position = Vector3(0, 0.53, 0)
	_yaw_node.add_child(_pitch_node)
	# Water jacket, receiver, muzzle, spade grips, ammo belt box.
	_part(_pitch_node, _cyl(0.085, 0.8), "steel", Vector3(0, 0, -0.5), Vector3(PI / 2, 0, 0))
	_part(_pitch_node, _cyl(0.03, 0.18, 8), "steel", Vector3(0, 0, -0.98), Vector3(PI / 2, 0, 0))
	_part(_pitch_node, _box(Vector3(0.16, 0.18, 0.36)), "steel", Vector3(0, 0, 0.05))
	_part(_pitch_node, _cyl(0.03, 0.06, 8), "brass", Vector3(0, 0.1, -0.35))
	for x in [-0.08, 0.08]:
		_part(_pitch_node, _cyl(0.022, 0.14, 6), "olive", Vector3(x, 0, 0.3), Vector3(PI / 2, 0, 0))
	_part(_pitch_node, _box(Vector3(0.22, 0.2, 0.3)), "olive", Vector3(0.25, -0.15, 0.0))
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0, -1.08)
	_pitch_node.add_child(_muzzle)
