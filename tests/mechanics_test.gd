extends SceneTree
## Checks the core Tower of Power numbers in a live world (no bots):
## shotgun range, melee, fall damage, jump height, turret arc and lethality,
## the bunker-control rules that decide where each team spawns, the neutral
## start, ragdolls, the Mosin rifle and respawn weapon choice, and the
## animated character.
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
			if _frames == 2:
				# Nobody holds the bunker yet: each team starts on its own neutral side.
				_expect(game.bunker.holder == -1, "the match starts with the bunker up for grabs")
				_expect(_near_spawn(p, "west") and _near_spawn(d, "east"), "Whites start west and Reds east")
			if _frames > 30:
				_data["kills4"] = 0
				_data["trial"] = 0
				_next()
		1:  # Halo 2's spread: a sure kill up close...
			_shot_trial(4.0, "kills4", 10)
		2:
			_expect(_data["kills4"] >= 9, "shotgun one-shot kills at 4 m (%d/10)" % _data["kills4"])
			_data["kills15"] = 0
			_data["trial"] = 0
			_next()
		3:  # ...and only the odd lucky kill at 15 m.
			_shot_trial(15.0, "kills15", 20)
		4:
			if _frames == 1:
				_expect(_data["kills15"] <= 4, "shotgun rarely one-shots at 15 m (%d/20)" % _data["kills15"])
				_place(p, Vector3(-10, 0, 19.5))
				_place(d, Vector3(-7.5, 0, 19.5))
				_aim(p, d.chest_position())
				p.weapon.reset()
			elif _frames == 3:
				p.in_fire = true
			elif _frames == 4:
				p.in_fire = false
			elif _frames == 5:
				_expect(not d.alive and is_instance_valid(d.ragdoll) and not d.model.visible, "a kill swaps the body for a ragdoll")
				_data["torso0"] = d.ragdoll.torso_position() if is_instance_valid(d.ragdoll) else Vector3.ZERO
			elif _frames == 5 + TPS / 2:
				var moved: float = d.ragdoll.torso_position().x - _data["torso0"].x if is_instance_valid(d.ragdoll) else 0.0
				_expect(moved > 1.5, "a point-blank blast throws the body along the shot (%.1f m in 0.5 s)" % moved)
			elif _frames == 5 + TPS * 3:
				var y: float = d.ragdoll.torso_position().y if is_instance_valid(d.ragdoll) else -100.0
				_expect(y > game.ground_point(d.ragdoll.torso_position()).y - 0.3 and y < 2.0, "the body comes to rest on the ground (torso at y %.2f)" % y)
				_place(d, Vector3(-7.5, 0, 19.5))
				_expect(d.model.visible and d.ragdoll == null, "respawning shows the soldier again")
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
				_expect(h > 1.65 and h < 1.95, "jump height %.2f m (partway to Halo 2's 2.4: 1.65-1.95)" % h)
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
		19:  # Respawning with the rifle picked swaps the gun.
			if _frames == 1:
				p.loadout = "rifle"
				p.respawn(Transform3D(Basis.IDENTITY, game.ground_point(Vector3(3, 0, 17.5))))
				_expect(p.weapon is Rifle and p.weapon.mag == GameConfig.RF_MAG, "respawning with the rifle chosen gives the Mosin")
				_place(d, Vector3(3, 0, -34), 0.0)
			elif _frames == 3:
				_aim(p, d.chest_position())
				p.in_fire = true
			elif _frames == TPS:
				# Held the trigger for a second: semi-auto fires once.
				_expect(p.weapon.mag == GameConfig.RF_MAG - 1, "semi-auto: holding the trigger fires one round (%d left)" % p.weapon.mag)
				_expect(d.alive and d.health < GameConfig.MAX_HEALTH, "one body shot at ~50 m wounds but doesn't kill (health %.0f)" % d.health)
				p.in_fire = false
			elif _frames == TPS + 2:
				p.in_fire = true
			elif _frames == TPS + 3:
				p.in_fire = false
			elif _frames == TPS + 20:
				_expect(not d.alive, "two rifle body shots kill")
				_next()
		20:  # Zoomed headshot at ~50 m kills in one.
			if _frames == 1:
				_place(d, Vector3(3, 0, -34), 0.0)
				p.zoomed = true
			elif _frames == TPS:
				_aim(p, d.global_position + Vector3(0, GameConfig.STAND_HEIGHT - 0.14, 0))
				p.in_fire = true
			elif _frames == TPS + 1:
				p.in_fire = false
			elif _frames == TPS + 20:
				_expect(not d.alive, "one zoomed rifle headshot kills")
				p.zoomed = false
				_next()
		21:  # Bloom: firing fast and moving widens the rifle's spread.
			if _frames == 1:
				var still: float = p.weapon.spread_deg()
				for i in 3:
					(p.weapon as Rifle)._bloom = minf((p.weapon as Rifle)._bloom + GameConfig.RF_BLOOM_PER_SHOT, GameConfig.RF_BLOOM_MAX)
				_expect(p.weapon.spread_deg() > still * 3.0, "rapid fire blooms the rifle (%.2f -> %.2f deg)" % [still, p.weapon.spread_deg()])
			elif _frames == TPS * 2:
				_expect(p.weapon.spread_deg() < GameConfig.RF_SPREAD * 1.5, "bloom settles back down")
				p.loadout = "shotgun"
				p.respawn(Transform3D(Basis.IDENTITY, game.ground_point(Vector3(3, 0, 17.5))))
				_expect(p.weapon is Shotgun, "choosing the shotgun again swaps back")
				_next()
		22:  # The character: the gun follows the aim, and the Reds' wool is red.
			if _frames == 1:
				_place(d, Vector3(-5, 0, 19.5), 0.7)
			d.look_pitch = 0.5
			d.in_move = Vector2(0.7, 0.7)
			d.global_position = game.ground_point(Vector3(-5, 0, 19.5))
			if _frames == 30:
				d.in_move = Vector2.ZERO
				var fwd := -d.model._gun.global_transform.basis.z
				var yaw_err := absf(Vector2(fwd.x, fwd.z).angle_to(Vector2(-sin(d.look_yaw), -cos(d.look_yaw))))
				_expect(absf(asin(fwd.y) - 0.5) < 0.05 and yaw_err < 0.05, "a running soldier's gun points where it aims (pitch %.2f for 0.50)" % asin(fwd.y))
				var red := false
				for mi in d.model.find_children("*", "MeshInstance3D", true, false):
					for i in (mi as MeshInstance3D).mesh.get_surface_count():
						var m := (mi as MeshInstance3D).get_surface_override_material(i) as BaseMaterial3D
						red = red or (m != null and m.albedo_color.r > 0.4 and m.albedo_color.g < 0.2)
				_expect(d.team == GameConfig.TEAM_RED and red, "the Reds wear red wool")
				_next()
		23:  # The holder's flag flies over the tower; a crouched gunner doesn't stretch.
			if _frames == 1:
				p.in_crouch = true
				_place(p, game.turret.seat_position())
			elif _frames == 10:
				game.turret.mount(p)
				p.in_crouch = false
			elif _frames > 10 and _frames < TPS * 5:
				game.player_ctrl._cam_pitch = deg_to_rad(GameConfig.MG_PITCH_MIN)
				game.player_ctrl._cam_yaw = game.turret.base_yaw() + deg_to_rad(GameConfig.MG_YAW_LIMIT)
				_data["stretch"] = maxf(_data.get("stretch", 0.0), _stretch(p.model.skeleton))
			elif _frames == TPS * 5:
				var flag: BunkerFlag = game.level.flag
				_expect(flag.team == game.bunker.holder and flag.cloth_top() > BunkerFlag.POLE_HEIGHT - 1.0,
					"the bunker holder's flag flies at the top of the pole (team %d)" % flag.team)
				_expect(_data["stretch"] < 0.01, "a gunner who mounts crouched keeps their shape (%.3f m)" % _data["stretch"])
				game.turret.dismount()
				_next()
		24:
			print("MECHANICS TEST ", "PASSED" if _failures.is_empty() else "FAILED")
			quit(0 if _failures.is_empty() else 1)
			return true
	return false


## How far any bone sits from where its rig says it should be, in metres.
func _stretch(sk: Skeleton3D) -> float:
	var worst := 0.0
	for b in sk.get_bone_count():
		var parent := sk.get_bone_parent(b)
		if parent >= 0:
			var now := sk.get_bone_global_pose(b).origin.distance_to(sk.get_bone_global_pose(parent).origin)
			worst = maxf(worst, absf(now - sk.get_bone_rest(b).origin.length()))
	return worst * sk.global_transform.basis.get_scale().x


func _near_spawn(s: Soldier, side: String) -> bool:
	for xf in game.level.spawn_points[side]:
		var o: Vector3 = (xf as Transform3D).origin
		if Vector2(o.x - s.global_position.x, o.z - s.global_position.z).length() < 1.0:
			return true
	return false


func _next() -> void:
	_step += 1
	_frames = 0


func _shot_trial(dist: float, key: String, trials: int) -> void:
	var p := game.player
	var d := _dummy
	# Bodies moved this frame only reach the physics server next frame,
	# so place first and pull the trigger two frames later. Flat ground.
	if _frames == 1:
		_place(p, Vector3(-10, 0, 19.5))
		_place(d, Vector3(-10 + dist, 0, 19.5))
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
		if _data["trial"] >= trials:
			_next()
		else:
			_frames = 0
