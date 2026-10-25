extends SceneTree
## Checks the core Tower of Power numbers in a live world (no bots):
## shotgun range, melee, fall damage, jump height, turret arc and lethality,
## and the bunker-control rules that decide where each team spawns.
## Run: godot --headless --path . --fixed-fps 60 -s tests/mechanics_test.gd

var game: Game
var TPS := Engine.physics_ticks_per_second
const DECK_Y_TEST := 14.0
var _failures: Array[String] = []
var _step := 0
var _frames := 0
var _dummy: Soldier
var _data := {}


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	InputSetup.register()
	GameConfig.red_bots = 1
	GameConfig.white_bots = 0
	game = Game.new()
	root.add_child(game)
	game.start()
	for s in game.soldiers:
		s.controller = null
	_dummy = game.soldiers[1]


func _expect(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		_failures.append(what)


func _place(s: Soldier, p: Vector3, yaw := 0.0) -> void:
	# Take over from the match's respawn timer so the dummy stays put.
	game._respawn_at.erase(s)
	if not s.alive:
		s.respawn(Transform3D(Basis(Vector3.UP, yaw), p))
	s.global_position = game.ground_point(p)
	s.velocity = Vector3.ZERO
	s.health = GameConfig.MAX_HEALTH
	s.look_yaw = yaw
	s.look_pitch = 0.0
	s.snap_interpolation()


func _aim(s: Soldier, at: Vector3) -> void:
	var d := (at - s.eye_position()).normalized()
	s.look_yaw = atan2(-d.x, -d.z)
	s.look_pitch = asin(d.y)


func _clear_inputs(s: Soldier) -> void:
	s.in_fire = false
	s.in_melee = false
	s.in_jump = false
	s.in_action = false
	s.in_move = Vector2.ZERO


## Each step runs for some frames; returns true when the test is done.
func _physics_process(_delta: float) -> bool:
	if game == null or not game.is_inside_tree():
		return false
	_frames += 1
	var p := game.player
	var d := _dummy
	match _step:
		0:
			if _frames > 30:
				_data["kills5"] = 0
				_data["trial"] = 0
				_next()
		1:  # Shotgun at 5 m kills (average of several blasts).
			_shot_trial(5.0, "kills5")
		2:
			_expect(_data["kills5"] == 5, "shotgun one-shot kills at 5 m (%d/5)" % _data["kills5"])
			_data["kills15"] = 0
			_data["trial"] = 0
			_next()
		3:
			_shot_trial(15.0, "kills15")
		4:
			_expect(_data["kills15"] == 0, "shotgun does not one-shot at 15 m (%d/5)" % _data["kills15"])
			_next()
		5:  # Melee is a one-hit kill with shields off.
			if _frames == 1:
				_place(p, Vector3(0, 0, 18))
				_place(d, Vector3(0, 0, 16.6))
				_aim(p, d.chest_position())
				p._melee_cd = 0.0
				p.in_melee = true
			elif _frames == 2:
				p.in_melee = false
			elif _frames == 60:
				_expect(not d.alive, "melee kills an unshielded enemy")
				_next()
		6:  # Lunge: melee from 3 m closes the gap.
			if _frames == 1:
				_place(d, Vector3(0, 0, 15))
				_place(p, Vector3(0, 0, 18))
				_aim(p, d.chest_position())
				p._melee_cd = 0.0
				p.in_melee = true
			elif _frames == 2:
				p.in_melee = false
			elif _frames == 90:
				_expect(not d.alive, "melee lunge reaches a target 3 m away")
				_next()
		7:  # Jump height.
			if _frames == 1:
				_place(d, Vector3(-10, 0, 18))
				_place(p, Vector3(0, 0, 18))
				_data["y0"] = p.global_position.y
				_data["apex"] = p.global_position.y
			elif _frames == 3:
				p.in_jump = true
			elif _frames == 4:
				p.in_jump = false
			elif _frames < 150:
				_data["apex"] = maxf(_data["apex"], p.global_position.y)
			else:
				var h: float = _data["apex"] - _data["y0"]
				_expect(h > 1.2 and h < 1.5, "jump height %.2f m (Halo-ish 1.2-1.5)" % h)
				_next()
		8:  # Jumping off the tower deck hurts but does not kill.
			if _frames == 1:
				_place(p, Vector3(5, 14.0, -36.5))
				p.global_position = Vector3(5, 15.2, -33.0)
				p.snap_interpolation()
			elif _frames == 300:
				_expect(p.alive and p.health < 90.0, "14 m fall hurts but is survivable (health %.0f)" % p.health)
				_next()
		9:  # Turret: mount, then mow down an enemy on the open island.
			if _frames == 1:
				_place(p, game.turret.seat_position() + Vector3(0, 0, -0.3))
				# North-east of the dish so the rotating antenna never blocks the line.
				_place(d, Vector3(16, 0, -8), PI)
				p.in_action = true
			elif _frames == 60:
				p.in_action = false
				_expect(p.turret == game.turret, "holding action mounts the Maxim")
			elif _frames > 60 and _frames < 420:
				p.look_yaw = atan2(-(d.chest_position() - game.turret.pivot_position()).x, -(d.chest_position() - game.turret.pivot_position()).z)
				p.look_pitch = asin((d.chest_position() - game.turret.pivot_position()).normalized().y)
				p.in_fire = d.alive
				if not d.alive:
					_data["mg_kill"] = true
			elif _frames == 420:
				p.in_fire = false
				_expect(_data.get("mg_kill", false), "Maxim kills a target on the island (~31 m)")
				_next()
		10:  # Turret arc: the covered west path and the tower flanks are out of reach.
			var t := game.turret
			var west := Vector3(-30.5, -2, -22) - t.pivot_position()
			var flank := Vector3(-14, 1, -44) - t.pivot_position()
			var dish := Vector3(0, -1, 0) - t.pivot_position()
			_expect(t.in_arc(dish), "dish is inside the Maxim's arc")
			_expect(t.in_arc(west) == false or not game.has_line_of_sight(t.muzzle_position(), Vector3(-30.5, -1.6, -22)), "covered west path is safe from the Maxim")
			_expect(not t.in_arc(flank), "tower flank is outside the Maxim's arc")
			_next()
		11:  # Dismount.
			if _frames == 1:
				p.in_action = true
			elif _frames == 60:
				p.in_action = false
				_expect(p.turret == null, "holding action again dismounts")
				_next()
		12:  # Bunker: an uncontested Red inside the tower takes it after the capture time.
			var b := game.bunker
			if _frames == 1:
				b.holder = GameConfig.TEAM_WHITE
				b.progress = 0.0
				b.challenger = -1
				_place(d, Vector3(0, 0, -44))
				_place(p, Vector3(0, 0, 18))
			elif _frames == TPS * 3:
				_expect(b.holder == GameConfig.TEAM_WHITE and b.challenger == GameConfig.TEAM_RED and b.progress > 0.3,
					"bunker capture builds up but takes time (%.0f%% after 3 s)" % (b.progress * 100.0))
			elif _frames == int(TPS * (BunkerControl.CAPTURE_TIME + 0.5)):
				_expect(b.holder == GameConfig.TEAM_RED, "uncontested Red takes the bunker")
				_next()
		13:  # Contested: one White can't take it from one Red inside.
			if _frames == 1:
				_place(p, Vector3(2, 0, -42))
			elif _frames == TPS * 8:
				_expect(game.bunker.holder == GameConfig.TEAM_RED, "an evenly contested bunker stays with the holder")
				_next()
		14:  # Red drops to the ground floor, White climbs to the deck (counts
			# double): outnumbered 2 to 1, the Reds lose it.
			if _frames == 1:
				_place(p, Vector3(4, DECK_Y_TEST, -47))
			elif _frames == int(TPS * (BunkerControl.CAPTURE_TIME + 0.5)):
				_expect(game.bunker.holder == GameConfig.TEAM_WHITE, "outnumbering the holders inside takes the bunker")
				_next()
		15:  # Hand it back to the Reds, then a lone White retakes it once they leave.
			if _frames == 1:
				game.bunker.holder = GameConfig.TEAM_RED
				_place(p, Vector3(2, 0, -42))
				_place(d, Vector3(0, 0, 18))
			elif _frames == int(TPS * (BunkerControl.CAPTURE_TIME + 0.5)):
				_expect(game.bunker.holder == GameConfig.TEAM_WHITE, "White retakes an empty-of-Reds bunker")
				_next()
		16:  # Manning the gun flips it immediately, even with Whites inside.
			if _frames == 1:
				_place(d, game.turret.seat_position() + Vector3(0, 0, -0.3))
			elif _frames == 3:
				game.turret.mount(d)
			elif _frames == 5:
				_expect(game.bunker.holder == GameConfig.TEAM_RED, "manning the Maxim takes the bunker at once")
				_next()
		17:  # Gun empty and bunker empty: the last team on the gun keeps it.
			if _frames == 1:
				game.turret.dismount()
				_place(d, Vector3(-10, 0, 18))
				_place(p, Vector3(10, 0, 18))
			elif _frames == TPS * 10:
				_expect(game.bunker.holder == GameConfig.TEAM_RED, "an empty bunker stays with the last gun team")
				_next()
		18:  # Respawns follow the holder: Reds at the bunker, Whites far away.
			if _frames == 1:
				p.die(null, "test")
				d.die(null, "test")
			elif _frames == int(TPS * (GameConfig.RESPAWN_TIME + 0.5)):
				_expect(p.alive and _near_spawn(p, "far"), "Whites respawn on the far side (%s)" % p.global_position)
				_expect(d.alive and _near_spawn(d, "bunker"), "Reds respawn at the bunker (%s)" % d.global_position)
				_next()
		19:
			print("MECHANICS TEST ", "PASSED" if _failures.is_empty() else "FAILED")
			quit(0 if _failures.is_empty() else 1)
			return true
	return false


func _near_spawn(s: Soldier, side: String) -> bool:
	for xf in game.level.spawn_points[side]:
		var o: Vector3 = (xf as Transform3D).origin
		if Vector2(o.x - s.global_position.x, o.z - s.global_position.z).length() < 1.0:
			return true
	return false


func _next() -> void:
	_step += 1
	_frames = 0


func _shot_trial(dist: float, key: String) -> void:
	var p := game.player
	var d := _dummy
	# Bodies moved this frame only reach the physics server next frame,
	# so place first and pull the trigger two frames later.
	if _frames == 1:
		_place(p, Vector3(0, 0, 18))
		_place(d, Vector3(0, 0, 18 - dist))
		_aim(p, d.chest_position())
		p.weapon.reset()
	elif _frames == 3:
		p.in_fire = true
	elif _frames == 4:
		p.in_fire = false
	elif _frames == 20:
		if not d.alive:
			_data[key] += 1
		_data["trial"] += 1
		if _data["trial"] >= 5:
			_next()
		else:
			_frames = 0
