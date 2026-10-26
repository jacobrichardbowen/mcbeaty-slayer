class_name Weapon
extends RefCounted
## Ammo, reload and cooldown bookkeeping shared by the hand-held guns.
## Subclasses supply the numbers and implement update() and firing.

enum State { READY, COOLDOWN, RELOAD_START, RELOAD_SHELL, RELOAD_END }

var soldier: Soldier
var kind := ""
var display_name := ""
var mag := 0
var reserve := 0
var state := State.READY
var timer := 0.0
var last_shot_time := -100.0
var _dry_cd := 0.0


func _init(owner_soldier: Soldier) -> void:
	soldier = owner_soldier
	reset()


# --- Per-weapon numbers (override) ---------------------------------------------------

func mag_size() -> int:
	return 1


func start_reserve() -> int:
	return 0


func max_reserve() -> int:
	return 0


func fire_interval() -> float:
	return 1.0


## Red reticle distance.
func autoaim_range() -> float:
	return 10.0


## Rounds one ammo crate gives.
func crate_ammo() -> int:
	return 0


## Magnification when zoomed; 1.0 means the weapon has no zoom.
func zoom_factor() -> float:
	return 1.0


## Current spread in degrees, for the reticle.
func spread_deg() -> float:
	return 0.0


func fire_sound() -> String:
	return ""


# --- Shared behaviour -------------------------------------------------------------------

func reset() -> void:
	mag = mag_size()
	reserve = start_reserve()
	state = State.READY
	timer = 0.0


func is_reloading() -> bool:
	return state == State.RELOAD_START or state == State.RELOAD_SHELL or state == State.RELOAD_END


## Ammo you can still take from a pickup.
func ammo_room() -> int:
	return max_reserve() - reserve


func add_ammo(amount: int) -> int:
	var taken := mini(amount, ammo_room())
	reserve += taken
	return taken


## Melee cancels a reload and briefly blocks firing.
func interrupt(block_time: float) -> void:
	if is_reloading() or state == State.READY:
		state = State.COOLDOWN
	timer = maxf(timer, block_time)


func update(_delta: float) -> void:
	pass


func _tick_timers(delta: float) -> void:
	timer = maxf(0.0, timer - delta)
	_dry_cd = maxf(0.0, _dry_cd - delta)


func _dry_fire() -> void:
	if _dry_cd <= 0.0:
		_dry_cd = 0.5
		soldier.weapon_sound("dry", -8.0)


func _begin_shot() -> void:
	mag -= 1
	state = State.COOLDOWN
	timer = fire_interval()
	last_shot_time = soldier.now()
	soldier.last_fire_time = last_shot_time


## A random direction inside a cone of half-angle `spread` (radians) around fwd.
static func cone_direction(fwd: Vector3, spread: float) -> Vector3:
	var ang := spread * sqrt(randf())
	var rot := randf() * TAU
	return Basis.looking_at(fwd, Vector3.UP) * Vector3(sin(ang) * cos(rot), sin(ang) * sin(rot), -cos(ang))


func _cast(origin: Vector3, dir: Vector3, reach: float) -> Dictionary:
	var exclude: Array[RID] = [soldier.get_rid()]
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach, GameConfig.MASK_SHOT, exclude)
	return soldier.get_world_3d().direct_space_state.intersect_ray(q)
