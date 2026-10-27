class_name Rifle
extends Weapon
## Mosin-Nagant, made semi-automatic for the prototype: one round per trigger
## pull, a 5-round stripper clip, and a single tight shot that blooms when you
## fire fast, move or jump. Two body shots kill; a headshot kills outright.
## Zooms 2x like Halo 2's Battle Rifle.

var _bloom := 0.0  # degrees
var _trigger_down := false
var _reload_sound: Node = null


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
	_stop_reload_sound()


func interrupt(block_time: float) -> void:
	if is_reloading():
		_stop_reload_sound()
	super(block_time)


func _stop_reload_sound() -> void:
	if is_instance_valid(_reload_sound):
		_reload_sound.queue_free()
	_reload_sound = null


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
	match state:
		State.COOLDOWN:
			if timer <= 0.0:
				state = State.READY
		State.RELOAD_START:
			if timer <= 0.0:
				state = State.RELOAD_SHELL
				timer = GameConfig.RF_RELOAD_CLIP
		State.RELOAD_SHELL:
			# Pressing a stripper clip into the magazine.
			if timer <= 0.0:
				var n := mini(mag_size() - mag, reserve)
				mag += n
				reserve -= n
				state = State.RELOAD_END
				timer = GameConfig.RF_RELOAD_END
		State.RELOAD_END:
			if timer <= 0.0:
				state = State.READY

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


## One recording covers the whole reload: bolt back, clip in, bolt home.
func _start_reload() -> void:
	state = State.RELOAD_START
	timer = GameConfig.RF_RELOAD_START
	_reload_sound = soldier.weapon_sound("rifle_reload", -8.0)


static func falloff(dist: float) -> float:
	if dist <= GameConfig.RF_FALLOFF_START:
		return 1.0
	var k := clampf((dist - GameConfig.RF_FALLOFF_START) / (GameConfig.RF_FALLOFF_END - GameConfig.RF_FALLOFF_START), 0.0, 1.0)
	return lerpf(1.0, GameConfig.RF_FALLOFF_MIN, k)


func _fire() -> void:
	var spread := deg_to_rad(spread_deg())
	_begin_shot()
	_bloom = minf(_bloom + GameConfig.RF_BLOOM_PER_SHOT, GameConfig.RF_BLOOM_MAX)
	var origin := soldier.eye_position()
	var dir := cone_direction(soldier.aim_direction(), spread)
	var r := _cast(origin, dir, GameConfig.RF_RANGE)
	var fx_root := soldier.fx_root()
	var end := origin + dir * GameConfig.RF_RANGE
	soldier.on_weapon_fired()
	if Net.online():
		Net.instance.send(Net.Ev.FIRED, [soldier.net_id, "rifle", PackedVector3Array([r.position if not r.is_empty() else end]),
			PackedByteArray([0 if r.is_empty() else (2 if r.collider is Soldier else 1)]), PackedVector3Array([r.normal if not r.is_empty() else Vector3.UP])])
	if r.is_empty():
		Fx.tracer(fx_root, soldier.muzzle_position(), end, Color(1.0, 0.9, 0.7, 0.6))
		whiz_past(soldier, origin, end, false)
		return
	end = r.position
	whiz_past(soldier, origin, end, r.collider == soldier.local_player())
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


## A round that passes close by the player's head, without hitting them,
## whizzes past: louder the closer it came, from where it passed.
static func whiz_past(shooter: Soldier, from: Vector3, to: Vector3, hit_player: bool) -> void:
	var p := shooter.local_player()
	if p == null or p == shooter or not p.alive or hit_player:
		return
	var ear := p.eye_position()
	var path := to - from
	var t := clampf((ear - from).dot(path) / path.length_squared(), 0.0, 1.0)
	var near := from + path * t
	var miss := near.distance_to(ear)
	if t > 0.0 and t < 1.0 and miss < GameConfig.RF_WHIZ_RADIUS:
		Sfx.play_3d(p, "whiz", near, lerpf(0.0, -10.0, miss / GameConfig.RF_WHIZ_RADIUS), 0.08, 25.0, 1.0, 3.0)
