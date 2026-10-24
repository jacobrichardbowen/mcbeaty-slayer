class_name Shotgun
extends RefCounted
## Halo 2-style shotgun: hitscan pellets in a cone, damage falloff, and a
## shell-by-shell reload you can cancel by pulling the trigger.

enum State { READY, COOLDOWN, RELOAD_START, RELOAD_SHELL, RELOAD_END }

var soldier: Soldier
var mag := GameConfig.SG_MAG
var reserve := GameConfig.SG_START_RESERVE
var state := State.READY
var timer := 0.0
var last_shot_time := -100.0
var _dry_cd := 0.0
var _pump_pending := false


func _init(owner_soldier: Soldier) -> void:
	soldier = owner_soldier


func reset() -> void:
	mag = GameConfig.SG_MAG
	reserve = GameConfig.SG_START_RESERVE
	state = State.READY
	timer = 0.0


func is_reloading() -> bool:
	return state == State.RELOAD_START or state == State.RELOAD_SHELL or state == State.RELOAD_END


## Ammo you can still take from a pickup.
func ammo_room() -> int:
	return GameConfig.SG_MAX_RESERVE - reserve


func add_ammo(amount: int) -> int:
	var taken := mini(amount, ammo_room())
	reserve += taken
	return taken


## Melee cancels a reload and briefly blocks firing.
func interrupt(block_time: float) -> void:
	if is_reloading():
		state = State.COOLDOWN
	if state == State.READY:
		state = State.COOLDOWN
	timer = maxf(timer, block_time)


func update(delta: float) -> void:
	timer = maxf(0.0, timer - delta)
	_dry_cd = maxf(0.0, _dry_cd - delta)
	if _pump_pending and soldier.now() - last_shot_time > 0.32:
		_pump_pending = false
		soldier.weapon_sound("pump", -5.0)
	match state:
		State.COOLDOWN:
			if timer <= 0.0:
				state = State.READY
		State.RELOAD_START:
			if timer <= 0.0:
				state = State.RELOAD_SHELL
				timer = GameConfig.SG_RELOAD_SHELL
		State.RELOAD_SHELL:
			if timer <= 0.0:
				if reserve > 0 and mag < GameConfig.SG_MAG:
					mag += 1
					reserve -= 1
					soldier.weapon_sound("shell", -6.0)
				if mag >= GameConfig.SG_MAG or reserve <= 0:
					state = State.RELOAD_END
					timer = GameConfig.SG_RELOAD_END
				else:
					timer = GameConfig.SG_RELOAD_SHELL
		State.RELOAD_END:
			if timer <= 0.0:
				state = State.READY
				soldier.weapon_sound("pump", -4.0)

	if soldier.in_fire:
		# Pulling the trigger mid-reload fires the shells already loaded.
		if (state == State.RELOAD_SHELL or state == State.RELOAD_START) and mag > 0:
			state = State.READY
		if state == State.READY:
			if mag > 0:
				_fire()
			elif reserve > 0:
				_start_reload()
			elif _dry_cd <= 0.0:
				_dry_cd = 0.5
				soldier.weapon_sound("dry", -8.0)
	if soldier.in_reload and state == State.READY and mag < GameConfig.SG_MAG and reserve > 0:
		_start_reload()
	if state == State.READY and mag == 0 and reserve > 0:
		_start_reload()


func _start_reload() -> void:
	state = State.RELOAD_START
	timer = GameConfig.SG_RELOAD_START


static func falloff(dist: float) -> float:
	if dist <= GameConfig.SG_FALLOFF_START:
		return 1.0
	var k := clampf((dist - GameConfig.SG_FALLOFF_START) / (GameConfig.SG_FALLOFF_END - GameConfig.SG_FALLOFF_START), 0.0, 1.0)
	return lerpf(1.0, GameConfig.SG_FALLOFF_MIN, k)


func _fire() -> void:
	mag -= 1
	state = State.COOLDOWN
	timer = GameConfig.SG_FIRE_INTERVAL
	last_shot_time = soldier.now()
	soldier.last_fire_time = last_shot_time
	_pump_pending = true
	var origin := soldier.eye_position()
	var fwd := soldier.aim_direction()
	var basis := Basis.looking_at(fwd, Vector3.UP)
	var space := soldier.get_world_3d().direct_space_state
	var exclude: Array[RID] = [soldier.get_rid()]
	var hits := {}
	var marks := 0
	var fx_root := soldier.fx_root()
	var spread := deg_to_rad(GameConfig.SG_SPREAD)
	for i in GameConfig.SG_PELLETS:
		var ang := spread * sqrt(randf())
		var rot := randf() * TAU
		var dir := basis * Vector3(sin(ang) * cos(rot), sin(ang) * sin(rot), -cos(ang))
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * GameConfig.SG_RANGE, GameConfig.MASK_SHOT, exclude)
		var r := space.intersect_ray(q)
		if r.is_empty():
			continue
		var pos: Vector3 = r.position
		var dmg := GameConfig.SG_PELLET_DAMAGE * falloff(origin.distance_to(pos))
		var col: Object = r.collider
		if col is Soldier:
			hits[col] = float(hits.get(col, 0.0)) + dmg
			if marks < 8:
				Fx.blood(fx_root, pos, dir)
				marks += 1
		elif marks < 8:
			Fx.impact(fx_root, pos, r.normal)
			marks += 1
	soldier.on_weapon_fired()
	for target in hits:
		(target as Soldier).take_damage(hits[target], soldier, "shotgun", (target as Soldier).chest_position(), fwd)
