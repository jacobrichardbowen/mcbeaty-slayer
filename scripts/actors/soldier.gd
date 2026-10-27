class_name Soldier
extends CharacterBody3D
## One combatant, human or bot. A controller (PlayerController or BotBrain)
## fills the in_* fields and look angles every physics tick; Soldier does the
## Halo-style movement, shotgun, melee lunge and turret mounting.

signal died(victim: Soldier, killer: Soldier, cause: String)

const STEP_HEIGHT := 0.45

var team := GameConfig.TEAM_WHITE
var display_name := "Soldier"
var is_player := false
var controller: Object  # needs gather_input(delta); may have on_* callbacks

# Controller inputs (edges are true for one tick).
var in_move := Vector2.ZERO
var in_jump := false
var in_crouch := false
var in_fire := false
var in_reload := false
var in_melee := false
var in_action := false
var look_yaw := 0.0
var look_pitch := 0.0

var health := GameConfig.MAX_HEALTH
var alive := true
var crouched := false
var eye_height := GameConfig.STAND_EYE
var weapon: Weapon
## Gun to carry from the next spawn on ("shotgun" or "rifle").
var loadout := "shotgun"
var zoomed := false
var turret: MaximTurret = null
var model: SoldierModel
var ragdoll: Ragdoll = null  # this life's body once dead, until it vanishes
var kills := 0
var deaths := 0
var spree := 0
var last_damage_time := -100.0
var last_fire_time := -100.0
var last_attacker: Soldier = null
var last_attacker_time := -100.0
var melee_time := -100.0

# Positions at the start and end of the last physics tick, for smooth cameras.
var prev_position := Vector3.ZERO
var curr_position := Vector3.ZERO

var _game: Game
var _shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _was_on_floor := true
var _melee_cd := 0.0
var _lunge_target: Soldier = null
var _lunge_time := 0.0
var _action_hold := 0.0
var _action_used := false
var _step_accum := 0.0
var _last_grunt := -100.0


func setup(game: Game, p_team: int, p_name: String, player: bool) -> void:
	_game = game
	team = p_team
	display_name = p_name
	is_player = player
	name = p_name.replace(" ", "_")


func _ready() -> void:
	collision_layer = GameConfig.LAYER_SOLDIER
	collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_SOLDIER | GameConfig.LAYER_MOVING
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.35
	floor_constant_speed = true
	floor_block_on_wall = true
	_capsule = CapsuleShape3D.new()
	_capsule.radius = GameConfig.RADIUS
	_capsule.height = GameConfig.STAND_HEIGHT
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	_shape.position.y = GameConfig.STAND_HEIGHT * 0.5
	add_child(_shape)
	model = SoldierModel.new()
	model.team = team
	add_child(model)
	weapon = make_weapon(loadout)
	model.set_weapon(loadout)
	snap_interpolation()


func now() -> float:
	return _game.time


func fx_root() -> Node3D:
	return _game.fx_root


## The human player, for sounds only they should hear.
func local_player() -> Soldier:
	return _game.player if _game else null


func eye_position() -> Vector3:
	return global_position + Vector3(0, eye_height, 0)


func aim_direction() -> Vector3:
	return Vector3(-sin(look_yaw) * cos(look_pitch), sin(look_pitch), -cos(look_yaw) * cos(look_pitch))


func chest_position() -> Vector3:
	var h := GameConfig.CROUCH_HEIGHT if crouched else GameConfig.STAND_HEIGHT
	return global_position + Vector3(0, h * 0.68, 0)


func head_position() -> Vector3:
	var h := GameConfig.CROUCH_HEIGHT if crouched else GameConfig.STAND_HEIGHT
	return global_position + Vector3(0, h - 0.15, 0)


func is_enemy(other: Soldier) -> bool:
	return other != null and other.team != team


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


## Halo 2 motion tracker rule: moving upright or firing shows you; crouching
## or standing still hides you.
func shows_on_tracker() -> bool:
	if not alive:
		return false
	if now() - last_fire_time < 1.5:
		return true
	if turret:
		return false
	return horizontal_speed() > 1.5 and not crouched


func snap_interpolation() -> void:
	prev_position = global_position
	curr_position = global_position


func interpolated_position() -> Vector3:
	return prev_position.lerp(curr_position, Engine.get_physics_interpolation_fraction())


# --- Physics tick -----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	prev_position = global_position
	if not alive:
		_corpse_physics(delta)
		curr_position = global_position
		return
	if controller:
		controller.gather_input(delta)
	_melee_cd = maxf(0.0, _melee_cd - delta)
	if turret:
		velocity = Vector3.ZERO
		global_position = turret.seat_position()
		turret.drive(self, delta)
	else:
		_move(delta)
		weapon.update(delta)
		if in_melee:
			_try_melee()
	_handle_action(delta)
	if now() - last_damage_time > GameConfig.HEALTH_REGEN_DELAY and health < GameConfig.MAX_HEALTH:
		health = minf(GameConfig.MAX_HEALTH, health + GameConfig.HEALTH_REGEN_RATE * delta)
	if global_position.y < GameConfig.KILL_Y:
		_fell_off_map()
	curr_position = global_position


func _move(delta: float) -> void:
	var on_floor := is_on_floor()
	if in_crouch != crouched:
		if in_crouch:
			_set_crouch(true, on_floor)
		else:
			_try_stand(on_floor)
	var target_eye := GameConfig.CROUCH_EYE if crouched else GameConfig.STAND_EYE
	eye_height = move_toward(eye_height, target_eye, 5.0 * delta)

	var yaw_basis := Basis(Vector3.UP, look_yaw)
	var wish := yaw_basis.x * in_move.x - yaw_basis.z * in_move.y
	if wish.length() > 1.0:
		wish = wish.normalized()
	var hv := Vector3(velocity.x, 0, velocity.z)
	var jumped := false

	if _lunge_target:
		_lunge_time -= delta
		var to := _lunge_target.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if not _lunge_target.alive or _lunge_time <= 0.0 or dist <= GameConfig.MELEE_RANGE * 0.75:
			if _lunge_target.alive and dist <= GameConfig.MELEE_RANGE + 0.4:
				_melee_hit(_lunge_target)
			_lunge_target = null
		else:
			hv = to / dist * GameConfig.MELEE_LUNGE_SPEED
	elif on_floor:
		var max_speed := GameConfig.CROUCH_SPEED if crouched else _run_speed()
		var accel := GameConfig.GROUND_ACCEL if wish.length_squared() > 0.0001 else GameConfig.GROUND_DECEL
		hv = hv.move_toward(wish * max_speed, accel * delta)
		if in_jump:
			velocity.y = GameConfig.JUMP_VELOCITY
			jumped = true
	elif wish.length_squared() > 0.0001:
		# Strong Halo air control without bleeding momentum when you let go.
		hv = hv.move_toward(wish * _run_speed(), GameConfig.AIR_ACCEL * delta)

	velocity.x = hv.x
	velocity.z = hv.z
	if on_floor and not jumped:
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= GameConfig.GRAVITY * delta
	var fall_speed := -velocity.y
	var motion := Vector3(velocity.x, 0, velocity.z) * delta
	move_and_slide()
	if on_floor and is_on_wall() and motion.length_squared() > 1e-6:
		_try_step_up(motion)
	var now_floor := is_on_floor()
	if now_floor and not _was_on_floor:
		_on_land(fall_speed)
	_was_on_floor = now_floor
	if now_floor and not crouched:
		_step_accum += horizontal_speed() * delta
		if _step_accum > 2.3:
			_step_accum = 0.0
			Sfx.play_3d(self, "step", global_position, -20.0 if not is_player else -24.0, 0.15, 30.0, 1.0, 3.0)


## Climb a lip up to STEP_HEIGHT that blocked horizontal movement.
func _try_step_up(motion: Vector3) -> void:
	var xf := global_transform
	var up := Vector3.UP * STEP_HEIGHT
	if test_move(xf, up):
		return
	xf.origin += up
	if test_move(xf, motion):
		return
	xf.origin += motion
	var hit := KinematicCollision3D.new()
	if test_move(xf, -up, hit) and hit.get_normal().angle_to(Vector3.UP) <= floor_max_angle:
		xf.origin += hit.get_travel()
		global_transform = xf
		apply_floor_snap()


## Halo 2 runs faster forwards than sideways or backwards.
func _run_speed() -> float:
	if in_move.length_squared() < 0.0001:
		return GameConfig.RUN_SPEED
	var forward := maxf(in_move.normalized().y, 0.0)
	return lerpf(GameConfig.STRAFE_SPEED, GameConfig.RUN_SPEED, forward)


## Stands straight up, e.g. to man the Maxim (whose height is fixed).
func stand_up() -> void:
	if crouched:
		_set_crouch(false, true)


func _set_crouch(c: bool, on_floor: bool) -> void:
	var dy := GameConfig.STAND_HEIGHT - GameConfig.CROUCH_HEIGHT
	crouched = c
	var h := GameConfig.CROUCH_HEIGHT if c else GameConfig.STAND_HEIGHT
	_capsule.height = h
	_shape.position.y = h * 0.5
	if not on_floor and c:
		# Crouch-jump: tuck the feet up so the head stays where it was.
		global_position.y += dy
		eye_height = GameConfig.CROUCH_EYE


func _try_stand(on_floor: bool) -> void:
	var dy := GameConfig.STAND_HEIGHT - GameConfig.CROUCH_HEIGHT
	if on_floor:
		if not test_move(global_transform, Vector3(0, dy, 0)):
			_set_crouch(false, true)
	elif not test_move(global_transform, Vector3(0, -dy, 0)):
		global_position.y -= dy
		_set_crouch(false, false)
		eye_height = GameConfig.STAND_EYE
	elif not test_move(global_transform, Vector3(0, dy, 0)):
		_set_crouch(false, false)


func _on_land(impact: float) -> void:
	if impact > GameConfig.FALL_DAMAGE_MIN_SPEED:
		var k := (impact - GameConfig.FALL_DAMAGE_MIN_SPEED) / (GameConfig.FALL_DAMAGE_LETHAL_SPEED - GameConfig.FALL_DAMAGE_MIN_SPEED)
		take_damage(k * GameConfig.MAX_HEALTH, null, "fall", global_position, Vector3.DOWN)
	if impact > 7.0:
		Sfx.play_3d(self, "land", global_position, -12.0, 0.1, 40.0, 1.0, 4.0)


## The ragdoll is what you see; the hidden body just settles where it fell.
func _corpse_physics(delta: float) -> void:
	if global_position.y < GameConfig.KILL_Y:
		return
	velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
	velocity.y -= GameConfig.GRAVITY * delta
	move_and_slide()


# --- Melee ----------------------------------------------------------------------------

func _try_melee() -> void:
	if _melee_cd > 0.0:
		return
	_melee_cd = GameConfig.MELEE_COOLDOWN
	melee_time = now()
	weapon.interrupt(0.45)
	if controller and controller.has_method("on_melee"):
		controller.on_melee()
	var target := _find_melee_target()
	if target == null:
		Sfx.play_3d(self, "swing", eye_position(), -8.0)
		return
	var dist := Vector2(target.global_position.x - global_position.x, target.global_position.z - global_position.z).length()
	if dist <= GameConfig.MELEE_RANGE:
		_melee_hit(target)
	else:
		_lunge_target = target
		_lunge_time = 0.25
		Sfx.play_3d(self, "swing", eye_position(), -8.0)


func _find_melee_target() -> Soldier:
	var best: Soldier = null
	var best_d := INF
	var eye := eye_position()
	var fwd := aim_direction()
	var cone := cos(deg_to_rad(GameConfig.MELEE_LUNGE_CONE))
	for s in _game.soldiers:
		if s == self or not s.alive or not is_enemy(s):
			continue
		var to := s.chest_position() - eye
		var d := to.length()
		if d > GameConfig.MELEE_LUNGE_RANGE + 0.5 or d < 0.01 or absf(s.global_position.y - global_position.y) > 1.2:
			continue
		if to.normalized().dot(fwd) < cone and d > 1.2:
			continue
		if not _game.has_line_of_sight(eye, s.chest_position()):
			continue
		if d < best_d:
			best_d = d
			best = s
	return best


func _melee_hit(target: Soldier) -> void:
	var dir := (target.chest_position() - eye_position()).normalized()
	Sfx.play_3d(self, "melee_hit", target.chest_position(), 0.0)
	Fx.blood(fx_root(), target.chest_position(), dir)
	target.take_damage(GameConfig.MELEE_DAMAGE, self, "melee", target.chest_position(), dir)


# --- Turret ---------------------------------------------------------------------------

func _handle_action(delta: float) -> void:
	if not in_action:
		_action_hold = 0.0
		_action_used = false
		return
	_action_hold += delta
	if _action_hold < GameConfig.MG_MOUNT_HOLD or _action_used:
		return
	_action_used = true
	if turret:
		turret.dismount()
	elif _game.turret.can_mount(self):
		_set_crouch(false, true)
		_game.turret.mount(self)


# --- Damage ---------------------------------------------------------------------------

func take_damage(amount: float, attacker: Soldier, cause: String, hit_pos: Vector3, dir: Vector3) -> void:
	if not alive or amount <= 0.0:
		return
	if attacker and attacker != self and attacker.team == team and not GameConfig.FRIENDLY_FIRE:
		return
	health -= amount
	if health > 0.0:
		_grunt(false)
	last_damage_time = now()
	if attacker and attacker != self:
		last_attacker = attacker
		last_attacker_time = now()
	if controller and controller.has_method("on_damaged"):
		controller.on_damaged(amount, attacker, hit_pos)
	if health <= 0.0:
		die(attacker, cause, dir, Ragdoll.fling_speed(cause, amount))


func _fell_off_map() -> void:
	var killer: Soldier = null
	if last_attacker and now() - last_attacker_time < 5.0:
		killer = last_attacker
	die(killer, "fell", Vector3.DOWN)


func die(killer: Soldier, cause: String, dir := Vector3.ZERO, fling := 0.0) -> void:
	if not alive:
		return
	alive = false
	health = 0.0
	if turret:
		turret.dismount()
	_lunge_target = null
	collision_layer = 0
	collision_mask = GameConfig.LAYER_WORLD
	_grunt(true)
	ragdoll = Ragdoll.spawn(self, dir, fling, cause == "headshot")
	model.visible = false
	velocity = Vector3.ZERO
	died.emit(self, killer, cause)


func respawn(xf: Transform3D) -> void:
	alive = true
	health = GameConfig.MAX_HEALTH
	_set_crouch(false, true)
	eye_height = GameConfig.STAND_EYE
	global_position = xf.origin
	look_yaw = xf.basis.get_euler().y
	look_pitch = 0.0
	velocity = Vector3.ZERO
	collision_layer = GameConfig.LAYER_SOLDIER
	collision_mask = GameConfig.LAYER_WORLD | GameConfig.LAYER_SOLDIER | GameConfig.LAYER_MOVING
	zoomed = false
	if weapon.kind != loadout:
		weapon = make_weapon(loadout)
		model.set_weapon(loadout)
	else:
		weapon.reset()
	model.visible = true
	ragdoll = null
	spree = 0
	last_attacker = null
	last_damage_time = -100.0
	_was_on_floor = true
	_lunge_target = null
	snap_interpolation()
	if controller and controller.has_method("on_spawned"):
		controller.on_spawned()


# --- Hooks used by weapons --------------------------------------------------------------

func weapon_sound(sound: String, volume_db := 0.0) -> Node:
	if is_player:
		return Sfx.play_2d(self, sound, volume_db, 0.03)
	return Sfx.play_3d(self, sound, eye_position(), volume_db + 3.0, 0.04, 40.0, 1.0, 4.0)


## A pained grunt when hit, at most every 0.6 s, and always on dying.
func _grunt(dying: bool) -> void:
	if not dying and now() - _last_grunt < 0.6:
		return
	_last_grunt = now()
	var louder := 3.0 if dying else 0.0
	if is_player:
		Sfx.play_2d(self, "pain", -9.0 + louder, 0.05)
	else:
		Sfx.play_3d(self, "pain", eye_position(), -6.0 + louder, 0.08, 45.0, 1.0, 5.0)


func make_weapon(kind: String) -> Weapon:
	return Rifle.new(self) if kind == "rifle" else Shotgun.new(self)


## Where shots appear to leave from: the viewmodel for the player.
func muzzle_position() -> Vector3:
	if controller and controller.has_method("muzzle_position"):
		return controller.muzzle_position()
	return model.muzzle_position()


## Hits in the top ~third of a metre of the body count as headshots.
func is_head_hit(pos: Vector3) -> bool:
	var h := GameConfig.CROUCH_HEIGHT if crouched else GameConfig.STAND_HEIGHT
	return pos.y > global_position.y + h - GameConfig.HEAD_HEIGHT


func on_weapon_fired() -> void:
	model.kick()
	var sound := weapon.fire_sound()
	if is_player:
		Sfx.play_2d(self, sound, -3.0, 0.03)
	else:
		Sfx.play_3d(self, sound, eye_position(), -2.0, 0.03, 220.0, 1.0, 10.0)
		Fx.flash(fx_root(), model.muzzle_position(), 4.0, 0.4)
	if controller and controller.has_method("on_weapon_fired"):
		controller.on_weapon_fired()


func on_turret_fired() -> void:
	if controller and controller.has_method("on_turret_fired"):
		controller.on_turret_fired()
