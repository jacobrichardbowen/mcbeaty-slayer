class_name Rifle
extends Weapon
## Mosin-Nagant, made semi-automatic for the prototype: one round per trigger
## pull, a 5-round stripper clip, and a single tight shot that blooms when you
## fire fast, move or jump. Two body shots kill; a headshot kills outright.
## Zooms 2x like Halo 2's Battle Rifle.

var _bloom := 0.0  # degrees
var _trigger_down := false
var _bolt_pending := false


func _init(owner_soldier: Soldier) -> void:
	super(owner_soldier)
	kind = "rifle"
	display_name = "MOSIN-NAGANT"


func mag_size() -> int:
	return GameConfig.RF_MAG


func start_reserve() -> int:
	return GameConfig.RF_START_RESERVE


func max_reserve() -> int:
	return GameConfig.RF_MAX_RESERVE


func fire_interval() -> float:
	return GameConfig.RF_FIRE_INTERVAL


func autoaim_range() -> float:
	return GameConfig.RF_AUTOAIM_RANGE


func crate_ammo() -> int:
	return GameConfig.RF_CRATE


func zoom_factor() -> float:
	return GameConfig.RF_ZOOM


func fire_sound() -> String:
	return "rifle"


func reset() -> void:
	super()
	_bloom = 0.0


func spread_deg() -> float:
	var s := soldier
	var spread := GameConfig.RF_SPREAD + _bloom
	spread += GameConfig.RF_MOVE_SPREAD * clampf(s.horizontal_speed() / GameConfig.RUN_SPEED, 0.0, 1.0)
	if not s.is_on_floor():
		spread += GameConfig.RF_AIR_SPREAD
	if s.crouched:
		spread *= GameConfig.RF_CROUCH_MULT
	if s.zoomed:
		spread *= GameConfig.RF_ZOOM_SPREAD_MULT
	return spread


func update(delta: float) -> void:
	_tick_timers(delta)
	_bloom = move_toward(_bloom, 0.0, GameConfig.RF_BLOOM_RECOVERY * delta)
	if _bolt_pending and soldier.now() - last_shot_time > 0.12:
		_bolt_pending = false
		soldier.weapon_sound("bolt", -9.0)
	match state:
		State.COOLDOWN:
			if timer <= 0.0:
				state = State.READY
		State.RELOAD_START:
			if timer <= 0.0:
				state = State.RELOAD_SHELL
				timer = GameConfig.RF_RELOAD_CLIP
				soldier.weapon_sound("bolt", -6.0)
		State.RELOAD_SHELL:
			# Pressing a stripper clip into the magazine.
			if timer <= 0.0:
				var n := mini(mag_size() - mag, reserve)
				mag += n
				reserve -= n
				soldier.weapon_sound("clip", -5.0)
				state = State.RELOAD_END
				timer = GameConfig.RF_RELOAD_END
		State.RELOAD_END:
			if timer <= 0.0:
				state = State.READY
				soldier.weapon_sound("bolt", -6.0)

	# Semi-automatic: one shot per pull of the trigger.
	var pulled := soldier.in_fire and not _trigger_down
	_trigger_down = soldier.in_fire
	if pulled and state == State.READY:
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
	timer = GameConfig.RF_RELOAD_START


static func falloff(dist: float) -> float:
	if dist <= GameConfig.RF_FALLOFF_START:
		return 1.0
	var k := clampf((dist - GameConfig.RF_FALLOFF_START) / (GameConfig.RF_FALLOFF_END - GameConfig.RF_FALLOFF_START), 0.0, 1.0)
	return lerpf(1.0, GameConfig.RF_FALLOFF_MIN, k)


func _fire() -> void:
	var spread := deg_to_rad(spread_deg())
	_begin_shot()
	_bolt_pending = true
	_bloom = minf(_bloom + GameConfig.RF_BLOOM_PER_SHOT, GameConfig.RF_BLOOM_MAX)
	var origin := soldier.eye_position()
	var dir := cone_direction(soldier.aim_direction(), spread)
	var r := _cast(origin, dir, GameConfig.RF_RANGE)
	var fx_root := soldier.fx_root()
	var end := origin + dir * GameConfig.RF_RANGE
	soldier.on_weapon_fired()
	if r.is_empty():
		Fx.tracer(fx_root, soldier.muzzle_position(), end, Color(1.0, 0.9, 0.7, 0.6))
		return
	end = r.position
	Fx.tracer(fx_root, soldier.muzzle_position(), end, Color(1.0, 0.9, 0.7, 0.6))
	var col: Object = r.collider
	if col is Soldier:
		var target := col as Soldier
		var head := target.is_head_hit(end)
		var dmg := GameConfig.RF_DAMAGE * falloff(origin.distance_to(end))
		if head:
			dmg *= GameConfig.RF_HEADSHOT_MULT
		Fx.blood(fx_root, end, dir)
		target.take_damage(dmg, soldier, "headshot" if head else "rifle", end, dir)
	else:
		Fx.impact(fx_root, end, r.normal)
