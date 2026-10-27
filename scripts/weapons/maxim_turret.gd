class_name MaximTurret
extends Node3D
## The Tower of Power: a Maxim M1910 on a Sokolov mount at the front of the
## Big Tower deck. Infinite ammo, 585 rpm, limited traverse. The gunner stays
## exposed from the sides and from the stair hole behind them. A burst plays
## one seamless recorded loop, pitched down, and ends with the last round
## and its echo on the beat the next round would have fired.

signal gunner_changed(soldier: Soldier)

var gunner: Soldier = null
var yaw := 0.0  # relative to the mount, radians
var pitch := 0.0

var _cooldown := 0.0
var _yaw_node: Node3D
var _pitch_node: Node3D
var _muzzle: Node3D
var _shield: StaticBody3D
var _loop_3d: AudioStreamPlayer3D  # the burst, as everyone else hears it
var _loop_2d: AudioStreamPlayer  # the burst, as the player on the gun hears it
var _bursting := false
var _burst_2d := false  # which of the two is playing
var _route_in := 0.0  # until the burst's sound is re-routed for the listener


func _ready() -> void:
	_build_model()
	_loop_3d = AudioStreamPlayer3D.new()
	_loop_3d.stream = Sfx.stream("maxim_loop")
	_loop_3d.pitch_scale = GameConfig.MG_PITCH
	_loop_3d.volume_db = GameConfig.MG_VOLUME
	_loop_3d.unit_size = 18.0
	_loop_3d.max_distance = 260.0
	_muzzle.add_child(_loop_3d)
	_loop_2d = AudioStreamPlayer.new()
	_loop_2d.stream = _loop_3d.stream
	_loop_2d.pitch_scale = GameConfig.MG_PITCH
	_loop_2d.volume_db = GameConfig.MG_VOLUME - 7.0
	add_child(_loop_2d)


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
	s.stand_up()
	s.velocity = Vector3.ZERO
	s.global_position = seat_position()
	s.snap_interpolation()
	Sfx.play_3d(self, "mount", pivot_position(), -4.0)
	gunner_changed.emit(s)


func dismount() -> void:
	if gunner == null:
		return
	var s := gunner
	if _bursting:
		_end_burst()
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
	_route_in -= delta
	if _bursting and not _burst_2d and _route_in <= 0.0:
		_route_in = 0.15
		Acoustics.route_3d(_loop_3d, muzzle_position(), GameConfig.MG_VOLUME)
	if s.in_fire:
		if _cooldown <= 0.0:
			_fire(s)
			_cooldown = maxf(_cooldown + GameConfig.MG_FIRE_INTERVAL, 0.0)
	else:
		_cooldown = maxf(_cooldown, 0.0)
		if _bursting and _cooldown <= 0.0:
			_end_burst()


func _start_burst(s: Soldier) -> void:
	_bursting = true
	_burst_2d = s.is_player
	if _burst_2d:
		Acoustics.route_2d(_loop_2d)
		_loop_2d.play()
	else:
		Acoustics.route_3d(_loop_3d, muzzle_position(), GameConfig.MG_VOLUME)
		_loop_3d.play()


func _end_burst() -> void:
	_bursting = false
	if _burst_2d:
		_loop_2d.stop()
		Sfx.play_2d(self, "maxim_end", _loop_2d.volume_db, 0.0, GameConfig.MG_PITCH)
	else:
		_loop_3d.stop()
		Sfx.play_3d(self, "maxim_end", muzzle_position(), GameConfig.MG_VOLUME, 0.0, 260.0, GameConfig.MG_PITCH, 18.0)


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
	if Net.online():
		Net.instance.send(Net.Ev.MG_FIRED, [r.position if not r.is_empty() else end,
			0 if r.is_empty() else (2 if r.collider is Soldier else 1), r.normal if not r.is_empty() else Vector3.UP])
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
	if not _bursting:
		_start_burst(s)
	s.on_turret_fired()


# --- Online ---------------------------------------------------------------------------

## Whether a burst is sounding (shared with other machines).
func is_firing() -> bool:
	return _bursting


## Points the gun where a gunner on another machine has it.
func set_aim(p_yaw: float, p_pitch: float) -> void:
	yaw = p_yaw
	pitch = p_pitch
	_yaw_node.rotation.y = yaw
	_pitch_node.rotation.x = pitch


## Starts or ends the burst sound for a gunner on another machine.
func set_remote_firing(on: bool) -> void:
	if on and not _bursting and gunner:
		_start_burst(gunner)
	elif not on and _bursting:
		_end_burst()


## Shows a round fired on another machine (it already did the damage).
func net_fired(end: Vector3, struck: int, normal: Vector3) -> void:
	var root := get_parent().get("fx_root") as Node3D
	if root == null:
		return
	var from := muzzle_position()
	if struck == 2:
		Fx.blood(root, end, (end - from).normalized())
	elif struck == 1:
		Fx.impact(root, end, normal)
	Fx.tracer(root, from, end)
	Fx.flash(root, from + (end - from).normalized() * 0.1, 3.0, 0.3)
	if gunner:
		gunner.last_fire_time = gunner.now()


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
