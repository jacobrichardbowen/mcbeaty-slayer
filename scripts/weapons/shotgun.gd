class_name Shotgun
extends Weapon
## Halo 2-style shotgun: hitscan pellets in a cone, damage falloff, and a
## shell-by-shell reload you can cancel by pulling the trigger.

var _pump_pending := false


func _init(owner_soldier: Soldier) -> void:
	super(owner_soldier)
	kind = "shotgun"
	display_name = "SHOTGUN"


func mag_size() -> int:
	return GameConfig.SG_MAG


func start_reserve() -> int:
	return GameConfig.SG_START_RESERVE


func max_reserve() -> int:
	return GameConfig.SG_MAX_RESERVE


func fire_interval() -> float:
	return GameConfig.SG_FIRE_INTERVAL


func autoaim_range() -> float:
	return GameConfig.SG_AUTOAIM_RANGE


func crate_ammo() -> int:
	return GameConfig.SG_CRATE


func spread_deg() -> float:
	return GameConfig.SG_SPREAD


func fire_sound() -> String:
	return "shotgun"


func update(delta: float) -> void:
	_tick_timers(delta)
	if _pump_pending and soldier.now() - last_shot_time > 0.32:
		# Halo 2 pumps after every shot: the rack, quieter than a reload's.
		_pump_pending = false
		soldier.weapon_sound("rack", -12.0)
	match state:
		State.COOLDOWN:
			if timer <= 0.0:
				state = State.READY
		State.RELOAD_START:
			if timer <= 0.0:
				_next_shell()
		State.RELOAD_SHELL:
			if timer <= 0.0:
				if reserve > 0 and mag < mag_size():
					mag += 1
					reserve -= 1
				if mag >= mag_size() or reserve <= 0:
					state = State.RELOAD_END
					timer = GameConfig.SG_RELOAD_END
					soldier.weapon_sound("rack", -6.0)
				else:
					_next_shell()
		State.RELOAD_END:
			if timer <= 0.0:
				state = State.READY

	if soldier.in_fire:
		# Pulling the trigger mid-reload fires the shells already loaded.
		if (state == State.RELOAD_SHELL or state == State.RELOAD_START) and mag > 0:
			state = State.READY
		if state == State.READY:
			if mag > 0:
				_fire()
			elif reserve > 0:
				_start_reload()
			else:
				_dry_fire()
	if soldier.in_reload and state == State.READY and mag < mag_size() and reserve > 0:
		_start_reload()
	if state == State.READY and mag == 0 and reserve > 0:
		_start_reload()


func _start_reload() -> void:
	state = State.RELOAD_START
	timer = GameConfig.SG_RELOAD_START


## The shell sound starts with the hand, as the shell is pushed in.
func _next_shell() -> void:
	state = State.RELOAD_SHELL
	timer = GameConfig.SG_RELOAD_SHELL
	soldier.weapon_sound("shell", -7.0)


static func falloff(dist: float) -> float:
	if dist <= GameConfig.SG_FALLOFF_START:
		return 1.0
	var k := clampf((dist - GameConfig.SG_FALLOFF_START) / (GameConfig.SG_FALLOFF_END - GameConfig.SG_FALLOFF_START), 0.0, 1.0)
	return lerpf(1.0, GameConfig.SG_FALLOFF_MIN, k)


func _fire() -> void:
	_begin_shot()
	_pump_pending = true
	var origin := soldier.eye_position()
	var fwd := soldier.aim_direction()
	var hits := {}
	var marks := 0
	var fx_root := soldier.fx_root()
	var spread := deg_to_rad(GameConfig.SG_SPREAD)
	var ends := PackedVector3Array()
	var struck := PackedByteArray()
	var normals := PackedVector3Array()
	for i in GameConfig.SG_PELLETS:
		var dir := cone_direction(fwd, spread)
		var r := _cast(origin, dir, GameConfig.SG_RANGE)
		if r.is_empty():
			continue
		var pos: Vector3 = r.position
		ends.append(pos)
		struck.append(2 if r.collider is Soldier else 1)
		normals.append(r.normal)
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
	if Net.online():
		Net.instance.send(Net.Ev.FIRED, [soldier.net_id, "shotgun", ends, struck, normals])
	for target in hits:
		(target as Soldier).take_damage(hits[target], soldier, "shotgun", (target as Soldier).chest_position(), fwd)
