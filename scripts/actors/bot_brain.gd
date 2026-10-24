class_name BotBrain
extends RefCounted
## Rudimentary bot. Goals, in order:
##   1. Shoot or punch any enemy it can see up close.
##   2. If nobody holds the Maxim, run to it and man it.
##   3. If the enemy holds it, storm the tower along a side path.
##   4. If its own team holds it, guard the tower.
## On the gun it sweeps the arc for targets and hops off if someone sneaks
## up from outside the traverse.

var s: Soldier
var game: Game
var agent: NavigationAgent3D
var target: Soldier = null

var _think := 0.0
var _seen_for := 0.0
var _last_seen := -100.0
var _last_seen_pos := Vector3.ZERO
var _aim_err := Vector2.ZERO
var _strafe := 1.0
var _strafe_t := 0.0
var _route: Array = []
var _route_i := 0
var _goal := Vector3.ZERO
var _defend_t := 0.0
var _stuck_t := 0.0
var _stuck_check := Vector3.ZERO
var _unstick_t := 0.0
var _unstick_move := Vector2.ZERO
var _burst_t := 0.0
var _repath_t := 0.0
var _rng := RandomNumberGenerator.new()


func _init(soldier: Soldier, g: Game) -> void:
	s = soldier
	game = g
	s.controller = self
	_rng.randomize()
	agent = NavigationAgent3D.new()
	agent.radius = 0.5
	agent.height = 1.8
	agent.path_desired_distance = 0.8
	agent.target_desired_distance = 1.0
	agent.path_max_distance = 1.5
	agent.avoidance_enabled = false
	s.add_child(agent)


func on_spawned() -> void:
	target = null
	_seen_for = 0.0
	_route_i = 0
	_route = _pick_route()
	_stuck_t = 0.0
	_stuck_check = s.global_position


func on_damaged(_amount: float, attacker: Soldier, _pos: Vector3) -> void:
	# Turn on whoever is shooting you, even from behind.
	if attacker and attacker.alive and s.is_enemy(attacker) and target == null:
		target = attacker
		_seen_for = 0.0
		_last_seen = s.now()
		_last_seen_pos = attacker.global_position


func _pick_route() -> Array:
	var routes: Dictionary = game.level.routes
	var x := s.global_position.x
	var roll := _rng.randf()
	var key := "center"
	if roll > 0.1:
		if x < -5.0:
			key = "west" if roll < 0.8 else "east"
		elif x > 5.0:
			key = "east" if roll < 0.8 else "west"
		else:
			key = "west" if roll < 0.55 else "east"
	# Spawning at the tower: no route needed.
	if s.global_position.z < -30.0:
		return []
	return routes[key]


func gather_input(delta: float) -> void:
	s.in_move = Vector2.ZERO
	s.in_jump = false
	s.in_crouch = false
	s.in_fire = false
	s.in_reload = false
	s.in_melee = false
	s.in_action = false
	if game.over:
		return
	_think -= delta
	if _think <= 0.0:
		_think = 0.12
		_perceive()
	if target:
		_seen_for += delta
	if s.turret:
		_drive_turret(delta)
		return
	if target and s.now() - _last_seen < 2.5:
		_engage(delta)
	else:
		target = null
		_objective(delta)
	_unstick(delta)


# --- Perception -----------------------------------------------------------------------

func _perceive() -> void:
	var eye := s.eye_position()
	var fwd := s.aim_direction()
	if s.turret:
		eye = s.turret.pivot_position()
	var best: Soldier = null
	var best_d := INF
	for o in game.soldiers:
		if not o.alive or not s.is_enemy(o):
			continue
		var to := o.chest_position() - eye
		var d := to.length()
		if d > GameConfig.BOT_VIEW_RANGE:
			continue
		if s.turret:
			if not s.turret.in_arc(to) and d > 10.0:
				continue
		elif d > 8.0 and to.normalized().dot(fwd) < 0.2 and o != target:
			continue
		if not game.has_line_of_sight(eye, o.chest_position()):
			continue
		if d < best_d:
			best_d = d
			best = o
	if best:
		if best != target:
			_seen_for = 0.0
			var err := deg_to_rad(GameConfig.BOT_TURRET_AIM_ERROR if s.turret else GameConfig.BOT_AIM_ERROR)
			_aim_err = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-0.6, 0.6)) * err
		target = best
		_last_seen = s.now()
		_last_seen_pos = best.global_position
	elif target and not target.alive:
		target = null


# --- Combat on foot -------------------------------------------------------------------

func _engage(delta: float) -> void:
	var aim_point := target.chest_position()
	var visible := s.now() - _last_seen < 0.3
	if not visible:
		aim_point = _last_seen_pos + Vector3(0, 1.2, 0)
	_aim_at(aim_point, delta, GameConfig.BOT_TURN_RATE)
	_aim_err = _aim_err.move_toward(Vector2.ZERO, delta * deg_to_rad(4.0))
	var to := target.global_position - s.global_position
	var dist := Vector2(to.x, to.z).length()
	var err := s.aim_direction().angle_to(aim_point - s.eye_position())
	if visible and _seen_for > GameConfig.BOT_REACTION:
		if dist < 2.6 and err < 0.6:
			s.in_melee = true
		elif dist < 9.0 and err < deg_to_rad(7.0) and not _friend_in_line(s.eye_position(), s.aim_direction(), dist):
			s.in_fire = true
	# Close in with a strafe, Halo bot style.
	_strafe_t -= delta
	if _strafe_t <= 0.0:
		_strafe_t = _rng.randf_range(0.4, 1.1)
		_strafe = -_strafe if _rng.randf() < 0.7 else _strafe
		if _rng.randf() < 0.15 and dist < 10.0:
			s.in_jump = true
	var move_dir := Vector3.ZERO
	if dist > 3.5:
		move_dir = _nav_direction(target.global_position if visible else _last_seen_pos)
	var right := Basis(Vector3.UP, s.look_yaw).x
	var strafe_dir := right * _strafe
	if not _safe_ahead(strafe_dir):
		_strafe = -_strafe
		strafe_dir = -strafe_dir
	move_dir = (move_dir + strafe_dir * (0.8 if dist < 12.0 else 0.4)).normalized()
	_set_move(move_dir)
	if s.weapon.mag < 4 and dist > 12.0:
		s.in_reload = true


# --- Objective ------------------------------------------------------------------------

func _objective(delta: float) -> void:
	var t := game.turret
	var seat := t.seat_position()
	if t.gunner == null:
		if _route_i < _route.size() and s.global_position.distance_to(seat) > 25.0:
			_follow_route(delta)
			return
		_goal = seat
		if s.global_position.distance_to(seat) < GameConfig.MG_MOUNT_RANGE - 0.4:
			s.in_action = true
			_face_dir(t.barrel_direction(), delta)
			return
	elif t.gunner.team != s.team:
		if _route_i < _route.size():
			_follow_route(delta)
			return
		_goal = seat
	else:
		_defend_t -= delta
		if _defend_t <= 0.0 or s.global_position.distance_to(_goal) < 1.5:
			_defend_t = _rng.randf_range(6.0, 12.0)
			var pts: Array[Vector3] = game.level.defend_points
			_goal = pts[_rng.randi() % pts.size()]
	var dir := _nav_direction(_goal)
	_set_move(dir)
	if dir != Vector3.ZERO:
		_face_dir(dir, delta)
	if s.weapon.mag < s.weapon.reserve and s.weapon.mag < GameConfig.SG_MAG:
		s.in_reload = true


func _follow_route(delta: float) -> void:
	var wp: Vector3 = _route[_route_i]
	var flat := Vector2(wp.x - s.global_position.x, wp.z - s.global_position.z)
	if flat.length() < 2.5:
		_route_i += 1
		return
	var dir := _nav_direction(wp)
	_set_move(dir)
	if dir != Vector3.ZERO:
		_face_dir(dir, delta)


# --- Turret ---------------------------------------------------------------------------

func _drive_turret(delta: float) -> void:
	var t := s.turret
	if target and target.alive:
		var to := target.chest_position() - t.pivot_position()
		if not t.in_arc(to):
			# Someone is flanking the gun: get off and fight.
			if to.length() < 14.0:
				s.in_action = true
			return
		var aim := target.chest_position() + target.velocity * 0.1
		_aim_at_from(t.pivot_position(), aim, delta, 140.0)
		_aim_err = _aim_err.move_toward(Vector2.ZERO, delta * deg_to_rad(1.5))
		var err := t.barrel_direction().angle_to(aim - t.muzzle_position())
		_burst_t -= delta
		if _burst_t < -0.35:
			_burst_t = _rng.randf_range(0.5, 1.0)
		if _seen_for > GameConfig.BOT_TURRET_REACTION and err < deg_to_rad(6.0) and _burst_t > 0.0 \
				and s.now() - _last_seen < 0.4 and not _friend_in_line(t.muzzle_position(), t.barrel_direction(), to.length()):
			s.in_fire = true
	else:
		# Idle sweep across the map.
		var sweep := sin(s.now() * 0.4) * deg_to_rad(45.0)
		s.look_yaw = t.base_yaw() + sweep
		s.look_pitch = deg_to_rad(-12.0)


## True if a teammate stands inside the shot cone closer than the target.
func _friend_in_line(origin: Vector3, dir: Vector3, max_dist: float) -> bool:
	for o in game.soldiers:
		if o == s or not o.alive or s.is_enemy(o):
			continue
		var to := o.chest_position() - origin
		var d := to.length()
		if d < max_dist + 1.0 and dir.angle_to(to) < maxf(deg_to_rad(GameConfig.SG_SPREAD + 3.0), atan(0.6 / maxf(d, 0.1))):
			return true
	return false


# --- Steering helpers -----------------------------------------------------------------

func _nav_direction(goal: Vector3) -> Vector3:
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0:
		return Vector3.ZERO
	_repath_t -= 1.0 / Engine.physics_ticks_per_second
	if agent.target_position.distance_to(goal) > 1.0 or _repath_t <= 0.0:
		_repath_t = 1.5
		agent.target_position = goal
	var next := agent.get_next_path_position()
	var d := next - s.global_position
	d.y = 0.0
	if d.length() < 0.05:
		# Path done (or no path): only walk straight at a goal that is close,
		# never across a gap toward an unreachable one.
		d = goal - s.global_position
		d.y = 0.0
		if d.length() > 2.5 or not _safe_ahead(d):
			return Vector3.ZERO
	return d.normalized() if d.length() > 0.05 else Vector3.ZERO


func _set_move(world_dir: Vector3) -> void:
	var b := Basis(Vector3.UP, s.look_yaw)
	s.in_move = Vector2(world_dir.dot(b.x), world_dir.dot(-b.z))
	# Ease off when the ground ahead runs out, so momentum can't carry us over.
	if world_dir != Vector3.ZERO and s.is_on_floor() and not _safe_ahead(world_dir, 0.9):
		s.in_move *= 0.3


func _face_dir(dir: Vector3, delta: float) -> void:
	var want := atan2(-dir.x, -dir.z)
	var step := deg_to_rad(GameConfig.BOT_TURN_RATE) * delta
	s.look_yaw = wrapf(s.look_yaw + clampf(wrapf(want - s.look_yaw, -PI, PI), -step, step), -PI, PI)
	s.look_pitch = move_toward(s.look_pitch, 0.0, step)


func _aim_at(point: Vector3, delta: float, rate_deg: float) -> void:
	_aim_at_from(s.eye_position(), point, delta, rate_deg)


func _aim_at_from(origin: Vector3, point: Vector3, delta: float, rate_deg: float) -> void:
	var d := (point - origin).normalized()
	var want_yaw := atan2(-d.x, -d.z) + _aim_err.x
	var want_pitch := asin(clampf(d.y, -1.0, 1.0)) + _aim_err.y
	var step := deg_to_rad(rate_deg) * delta
	s.look_yaw = wrapf(s.look_yaw + clampf(wrapf(want_yaw - s.look_yaw, -PI, PI), -step, step), -PI, PI)
	s.look_pitch = clampf(move_toward(s.look_pitch, want_pitch, step), deg_to_rad(-85.0), deg_to_rad(85.0))


## Avoid strafing off a ledge: the spot one meter over must be on the navmesh.
func _safe_ahead(dir: Vector3, reach := 1.2) -> bool:
	var map := s.get_world_3d().navigation_map
	var probe := s.global_position + dir.normalized() * reach
	var closest := NavigationServer3D.map_get_closest_point(map, probe)
	return Vector2(closest.x - probe.x, closest.z - probe.z).length() < 0.35 and absf(closest.y - probe.y) < 1.0


func _unstick(delta: float) -> void:
	if s.in_move.length() < 0.3 or s.turret:
		_stuck_t = 0.0
		_stuck_check = s.global_position
		return
	_unstick_t = maxf(0.0, _unstick_t - delta)
	_stuck_t += delta
	if _stuck_t > 1.0:
		if s.global_position.distance_to(_stuck_check) < 0.6:
			s.in_jump = true
			_unstick_t = 0.6
			_strafe = -_strafe
			_unstick_move = (Vector2(_strafe, 0.0) - s.in_move.normalized()).normalized()
		_stuck_t = 0.0
		_stuck_check = s.global_position
	if _unstick_t > 0.0:
		var b := Basis(Vector3.UP, s.look_yaw)
		var world := b.x * _unstick_move.x - b.z * _unstick_move.y
		s.in_move = _unstick_move if _safe_ahead(world) else Vector2.ZERO
