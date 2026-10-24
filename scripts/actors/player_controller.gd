class_name PlayerController
extends Node3D
## Local player: reads mouse/keyboard/gamepad, drives the soldier, and owns
## the camera (first person, Halo 2-style third person on the Maxim, and the
## orbiting death cam) plus the first-person shotgun viewmodel.

const VM_REST := Vector3(0.34, -0.31, -0.86)
const VM_TOE_IN := 0.07
const PUMP_REST_Z := -0.36

var soldier: Soldier
var game: Game
var camera: Camera3D
var aim_target: Soldier = null
var red_reticle := false
var damage_flash := 0.0

var _mode := ""
var _vm: Node3D
var _vm_gun: Node3D
var _vm_pump: Node3D
var _vm_muzzle: Node3D
var _recoil := 0.0
var _cam_kick := 0.0
var _bob := 0.0
var _reload_blend := 0.0
var _melee_anim := 0.0
var _shake := 0.0
var _cam_yaw := 0.0
var _cam_pitch := 0.0
var _pad_accel := 0.0
var _death_orbit := 0.0


func setup(g: Game, s: Soldier) -> void:
	game = g
	soldier = s
	s.controller = self


func _ready() -> void:
	camera = Camera3D.new()
	camera.near = 0.03
	camera.far = 3000.0
	camera.fov = GameConfig.vertical_fov()
	add_child(camera)
	camera.current = true
	_build_viewmodel()
	_sync_mode()


# --- Input ----------------------------------------------------------------------------

func gather_input(_delta: float) -> void:
	var s := soldier
	_sync_mode()
	if game.input_blocked():
		s.in_move = Vector2.ZERO
		s.in_jump = false
		s.in_crouch = false
		s.in_fire = false
		s.in_reload = false
		s.in_melee = false
		s.in_action = false
	else:
		s.in_move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		s.in_jump = Input.is_action_just_pressed("jump")
		s.in_crouch = Input.is_action_pressed("crouch")
		s.in_fire = Input.is_action_pressed("fire")
		s.in_reload = Input.is_action_just_pressed("reload")
		s.in_melee = Input.is_action_just_pressed("melee")
		s.in_action = Input.is_action_pressed("action")
	if s.turret:
		_aim_turret()
	_update_target()


func _unhandled_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not game.input_blocked():
		var sens := deg_to_rad(GameConfig.mouse_sensitivity)
		var inv := -1.0 if GameConfig.invert_y else 1.0
		_look(-mm.relative.x * sens, -mm.relative.y * sens * inv)


func _look(dyaw: float, dpitch: float) -> void:
	var s := soldier
	if not s.alive:
		return
	if s.turret:
		var limit := deg_to_rad(GameConfig.MG_YAW_LIMIT + 8.0)
		var rel := clampf(wrapf(_cam_yaw + dyaw - s.turret.base_yaw(), -PI, PI), -limit, limit)
		_cam_yaw = s.turret.base_yaw() + rel
		_cam_pitch = clampf(_cam_pitch + dpitch, deg_to_rad(GameConfig.MG_PITCH_MIN - 5.0), deg_to_rad(GameConfig.MG_PITCH_MAX))
	else:
		s.look_yaw = wrapf(s.look_yaw + dyaw, -PI, PI)
		s.look_pitch = clampf(s.look_pitch + dpitch, deg_to_rad(-85.0), deg_to_rad(85.0))


func _pad_look(delta: float) -> void:
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick == Vector2.ZERO or game.input_blocked():
		_pad_accel = 0.0
		return
	var mag := minf(stick.length(), 1.0)
	# Halo-style: squared response, then a turn ramp when the stick is pinned.
	_pad_accel = minf(_pad_accel + delta * 2.0, 1.0) if mag > 0.95 else 0.0
	var rate := deg_to_rad(GameConfig.pad_look_speed) * (1.0 + 0.9 * _pad_accel)
	if red_reticle:
		rate *= 0.55  # aim assist: slow down over a target
	var v := stick.normalized() * mag * mag * rate * delta
	var inv := -1.0 if GameConfig.invert_y else 1.0
	_look(-v.x, -v.y * inv)


# --- Targeting ------------------------------------------------------------------------

func _aim_turret() -> void:
	var t := soldier.turret
	var xf := _turret_cam_transform()
	var dir := -xf.basis.z
	var exclude: Array[RID] = [soldier.get_rid(), t.shield_rid()]
	var q := PhysicsRayQueryParameters3D.create(xf.origin, xf.origin + dir * GameConfig.MG_RANGE, GameConfig.MASK_SHOT, exclude)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	var target: Vector3 = r.position if not r.is_empty() else xf.origin + dir * GameConfig.MG_RANGE
	var gd := (target - t.pivot_position()).normalized()
	soldier.look_yaw = atan2(-gd.x, -gd.z)
	soldier.look_pitch = asin(clampf(gd.y, -1.0, 1.0))


func _update_target() -> void:
	var s := soldier
	aim_target = null
	red_reticle = false
	if not s.alive:
		return
	var origin := s.eye_position()
	var dir := s.aim_direction()
	var reach := GameConfig.SG_AUTOAIM_RANGE
	if s.turret:
		var xf := _turret_cam_transform()
		origin = xf.origin
		dir = -xf.basis.z
		reach = GameConfig.MG_AUTOAIM_RANGE
	var best_ang := INF
	var best_dist := 0.0
	for o in game.soldiers:
		if o == s or not o.alive:
			continue
		var to := o.chest_position() - origin
		var d := to.length()
		if d > 80.0:
			continue
		var ang := dir.angle_to(to)
		var tol := maxf(deg_to_rad(2.0), atan(0.5 / maxf(d, 0.1)))
		if ang < tol and ang < best_ang and game.has_line_of_sight(origin, o.chest_position()):
			best_ang = ang
			best_dist = d
			aim_target = o
	red_reticle = aim_target != null and s.is_enemy(aim_target) and best_dist <= reach


# --- Camera ---------------------------------------------------------------------------

func _sync_mode() -> void:
	var s := soldier
	var mode := "dead" if not s.alive else ("turret" if s.turret else "fp")
	if mode == _mode:
		return
	if mode == "turret":
		# Like a Halo 2 vehicle: the camera starts lined up with the gun.
		_cam_yaw = s.turret.base_yaw() + s.turret.yaw
		_cam_pitch = s.turret.pitch
	elif mode == "fp" and _mode == "turret":
		s.look_yaw = _cam_yaw
		s.look_pitch = clampf(_cam_pitch, deg_to_rad(-85.0), deg_to_rad(85.0))
	elif mode == "dead":
		_death_orbit = s.look_yaw
	s.model.set_first_person(mode == "fp")
	_mode = mode


func _turret_cam_transform() -> Transform3D:
	var t := soldier.turret
	var pivot := t.pivot_position() + Vector3(0, 1.1, 0)
	var dir := Vector3(-sin(_cam_yaw) * cos(_cam_pitch), sin(_cam_pitch), -cos(_cam_yaw) * cos(_cam_pitch))
	var pos := pivot - dir * 3.3 + Vector3(0, 0.3, 0)
	var exclude: Array[RID] = [soldier.get_rid(), t.shield_rid()]
	var q := PhysicsRayQueryParameters3D.create(pivot, pos, GameConfig.LAYER_WORLD, exclude)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		pos = (r.position as Vector3) + (pivot - pos).normalized() * 0.3
	return Transform3D(Basis.looking_at(dir, Vector3.UP), pos)


func _process(delta: float) -> void:
	_pad_look(delta)
	_sync_mode()
	var s := soldier
	_shake = maxf(0.0, _shake - delta)
	_cam_kick = move_toward(_cam_kick, 0.0, deg_to_rad(20.0) * delta)
	damage_flash = maxf(0.0, damage_flash - delta * 1.5)
	match _mode:
		"fp":
			camera.global_position = s.interpolated_position() + Vector3(0, s.eye_height, 0)
			camera.rotation = Vector3(s.look_pitch + _cam_kick, s.look_yaw, 0)
		"turret":
			var xf := _turret_cam_transform()
			if _shake > 0.0:
				xf.origin += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.025
			camera.global_transform = xf
		"dead":
			_death_orbit += delta * 0.35
			var corpse := s.global_position
			camera.global_position = corpse + Vector3(sin(_death_orbit) * 4.5, 3.2, cos(_death_orbit) * 4.5)
			camera.look_at(corpse + Vector3(0, 0.5, 0), Vector3.UP)
	_vm.visible = _mode == "fp"
	_update_viewmodel(delta)


# --- Viewmodel ------------------------------------------------------------------------

func _vm_part(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	m.metallic = 0.3 if color.get_luminance() < 0.2 else 0.0
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _vm_box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _vm_cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 1
	return c


func _build_viewmodel() -> void:
	var steel := Color(0.13, 0.13, 0.14)
	var wood := Color(0.45, 0.28, 0.14)
	var skin := Color(0.86, 0.68, 0.55)
	var sleeve := Color(0.86, 0.86, 0.82) if soldier.team == GameConfig.TEAM_WHITE else Color(0.66, 0.13, 0.1)
	_vm = Node3D.new()
	_vm.scale = Vector3.ONE * 0.25
	camera.add_child(_vm)
	_vm_gun = Node3D.new()
	_vm_gun.position = VM_REST
	_vm_gun.rotation.y = VM_TOE_IN
	_vm.add_child(_vm_gun)
	_vm_part(_vm_gun, _vm_box(Vector3(0.06, 0.085, 0.3)), steel, Vector3.ZERO)
	_vm_part(_vm_gun, _vm_cyl(0.021, 0.62), steel, Vector3(0, 0.026, -0.46), Vector3(PI / 2, 0, 0))
	_vm_part(_vm_gun, _vm_cyl(0.018, 0.5), steel, Vector3(0, -0.02, -0.41), Vector3(PI / 2, 0, 0))
	_vm_part(_vm_gun, _vm_box(Vector3(0.006, 0.02, 0.012)), Color(0.8, 0.8, 0.8), Vector3(0, 0.05, -0.75))
	_vm_part(_vm_gun, _vm_box(Vector3(0.062, 0.115, 0.34)), wood, Vector3(0, -0.05, 0.31), Vector3(-0.18, 0, 0))
	_vm_part(_vm_gun, _vm_box(Vector3(0.09, 0.09, 0.11)), skin, Vector3(0.0, -0.075, 0.12))
	_vm_part(_vm_gun, _vm_box(Vector3(0.13, 0.13, 0.55)), sleeve, Vector3(0.05, -0.15, 0.42), Vector3(0.25, 0.1, 0))
	_vm_pump = Node3D.new()
	_vm_pump.position = Vector3(0, -0.024, PUMP_REST_Z)
	_vm_gun.add_child(_vm_pump)
	_vm_part(_vm_pump, _vm_box(Vector3(0.072, 0.066, 0.18)), wood, Vector3.ZERO)
	_vm_part(_vm_pump, _vm_box(Vector3(0.1, 0.08, 0.12)), skin, Vector3(-0.01, -0.055, 0))
	_vm_part(_vm_pump, _vm_box(Vector3(0.13, 0.13, 0.6)), sleeve, Vector3(-0.12, -0.15, 0.27), Vector3(0.28, -0.45, 0))
	_vm_muzzle = Node3D.new()
	_vm_muzzle.position = Vector3(0, 0.026, -0.8)
	_vm_gun.add_child(_vm_muzzle)


func _update_viewmodel(delta: float) -> void:
	var s := soldier
	var w := s.weapon
	var speed := s.horizontal_speed() if s.is_on_floor() else 0.0
	_bob += delta * speed * 1.7
	var bob_amt := clampf(speed / GameConfig.RUN_SPEED, 0.0, 1.0)
	var pos := VM_REST + Vector3(sin(_bob) * 0.02, -absf(cos(_bob)) * 0.018, 0.0) * bob_amt
	var rot := Vector3(0, VM_TOE_IN, 0)
	if not s.is_on_floor():
		pos.y -= 0.02
	_recoil = maxf(0.0, _recoil - delta * 5.0)
	pos.z += _recoil * 0.12
	rot.x += _recoil * 0.22
	var pump := 0.0
	if w.state == Shotgun.State.COOLDOWN:
		var t := (s.now() - w.last_shot_time) / GameConfig.SG_FIRE_INTERVAL
		if t > 0.3 and t < 0.75:
			pump = sin((t - 0.3) / 0.45 * PI)
	_vm_pump.position.z = PUMP_REST_Z + pump * 0.11
	_reload_blend = move_toward(_reload_blend, 1.0 if w.is_reloading() else 0.0, delta * 6.0)
	rot.z += _reload_blend * 0.5
	rot.x += _reload_blend * 0.12
	pos.y -= _reload_blend * 0.05
	if w.state == Shotgun.State.RELOAD_SHELL:
		var k := 1.0 - w.timer / GameConfig.SG_RELOAD_SHELL
		pos.y -= sin(k * PI) * 0.025
	_melee_anim = maxf(0.0, _melee_anim - delta)
	if _melee_anim > 0.0:
		var m := sin((1.0 - _melee_anim / 0.3) * PI)
		pos += Vector3(-0.2, 0.06, -0.12) * m
		rot += Vector3(0.1, 0.9, 0.5) * m
	_vm_gun.position = pos
	_vm_gun.rotation = rot


# --- Callbacks from Soldier -------------------------------------------------------------

func on_weapon_fired() -> void:
	_recoil = 1.0
	_cam_kick += deg_to_rad(2.2)
	Fx.flash(game.fx_root, _vm_muzzle.global_position, 3.0, 0.08)


func on_turret_fired() -> void:
	_shake = 0.08


func on_melee() -> void:
	_melee_anim = 0.3


func on_damaged(amount: float, _attacker: Soldier, _pos: Vector3) -> void:
	damage_flash = minf(1.0, damage_flash + amount / 60.0)
	Sfx.play_2d(self, "hurt", -10.0, 0.1)


func on_spawned() -> void:
	_sync_mode()
