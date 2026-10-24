class_name Game
extends Node3D
## One Tower of Power match: team slayer, no shields, shotguns only, one Maxim
## gun on the Big Tower. Builds the world, spawns soldiers, keeps score.

signal exit_requested
signal restart_requested

var level: AscensionLevel
var turret: MaximTurret
var soldiers: Array[Soldier] = []
var player: Soldier
var player_ctrl: PlayerController
var hud: Hud
var pause_menu: PauseMenu
var fx_root: Node3D
var scores := [0, 0]
var time := 0.0
var time_left := GameConfig.TIME_LIMIT
var over := false
var winner := -1
var tower_team := GameConfig.TEAM_WHITE

var _soldier_root: Node3D
var _bots: Array[BotBrain] = []
var _respawn_at := {}
var _multi := {}
var _end_timer := 0.0


func start() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	Fx.reset()
	_build_environment()
	level = AscensionLevel.new()
	level.name = "Ascension"
	add_child(level)
	level.build()
	fx_root = Node3D.new()
	fx_root.name = "Fx"
	add_child(fx_root)
	turret = MaximTurret.new()
	turret.name = "Maxim"
	turret.transform = level.turret_transform
	add_child(turret)
	turret.gunner_changed.connect(_on_gunner_changed)
	level.set_flag_team(-1)
	for p in level.ammo_points:
		_add_pickup(ground_point(p), 12, false)
	for tp in level.teleporters:
		var t := Teleporter.new()
		t.destination = tp["to"]
		t.position = tp["from"]
		add_child(t)

	_soldier_root = Node3D.new()
	_soldier_root.name = "Soldiers"
	add_child(_soldier_root)
	tower_team = GameConfig.TEAM_WHITE if GameConfig.player_starts_at_tower else GameConfig.TEAM_RED
	_spawn_soldier(GameConfig.TEAM_WHITE, "You", true)
	for i in GameConfig.white_bots:
		_spawn_soldier(GameConfig.TEAM_WHITE, GameConfig.WHITE_NAMES[i % GameConfig.WHITE_NAMES.size()], false)
	for i in GameConfig.red_bots:
		_spawn_soldier(GameConfig.TEAM_RED, GameConfig.RED_NAMES[i % GameConfig.RED_NAMES.size()], false)

	hud = Hud.new()
	hud.game = self
	add_child(hud)
	pause_menu = PauseMenu.new()
	pause_menu.quit_requested.connect(func() -> void: exit_requested.emit())
	pause_menu.restart_requested.connect(func() -> void: restart_requested.emit())
	add_child(pause_menu)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var goal := "Hold the tower" if tower_team == GameConfig.TEAM_WHITE else "Take the tower"
	hud.announce("Tower of Power")
	hud.feed("%s. First to %d kills." % [goal, GameConfig.score_limit], GameConfig.TEAM_COLORS[0])


func input_blocked() -> bool:
	return over or get_tree().paused or (pause_menu != null and pause_menu.visible)


func respawn_left(s: Soldier) -> float:
	return maxf(0.0, float(_respawn_at.get(s, time)) - time)


func has_line_of_sight(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, GameConfig.MASK_SIGHT)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Snap a point onto the floor below it (spawns and pickups are authored roughly).
func ground_point(p: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 2.5, 0), p + Vector3(0, -12, 0), GameConfig.LAYER_WORLD)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return r.position if not r.is_empty() else p


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and not input_blocked() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if over:
		_end_timer -= delta
		if _end_timer <= 0.0:
			exit_requested.emit()
		return
	time += delta
	time_left -= delta
	for s in _respawn_at.keys():
		if time >= float(_respawn_at[s]):
			_respawn_at.erase(s)
			(s as Soldier).respawn(_choose_spawn((s as Soldier).team))
	if time_left <= 0.0:
		_end_match(0 if scores[0] > scores[1] else (1 if scores[1] > scores[0] else -1))


# --- Setup ------------------------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.2, 0.38, 0.7)
	sky_mat.sky_horizon_color = Color(0.68, 0.77, 0.87)
	sky_mat.ground_horizon_color = Color(0.68, 0.77, 0.87)
	sky_mat.ground_bottom_color = Color(0.78, 0.82, 0.88)
	sky_mat.sky_curve = 0.12
	sky_mat.sun_angle_max = 12.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.45
	env.ambient_light_color = Color(0.62, 0.62, 0.62)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 5.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.88)
	env.fog_density = 0.0011
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.1
	env.fog_height = -45.0
	env.fog_height_density = 0.03
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -38, 0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)


func _spawn_soldier(team: int, soldier_name: String, is_player: bool) -> void:
	var s := Soldier.new()
	s.setup(self, team, soldier_name, is_player)
	_soldier_root.add_child(s)
	s.died.connect(_on_soldier_died)
	soldiers.append(s)
	if is_player:
		player = s
		player_ctrl = PlayerController.new()
		player_ctrl.name = "PlayerController"
		player_ctrl.setup(self, s)
		add_child(player_ctrl)
	else:
		_bots.append(BotBrain.new(s, self))
	s.respawn(_choose_spawn(team))


func _add_pickup(pos: Vector3, amount: int, dropped: bool) -> void:
	var p := AmmoPickup.new()
	p.amount = amount
	p.dropped = dropped
	p.position = pos
	add_child(p)


## Halo-ish spawning: your team's side of the map, away from living enemies.
func _choose_spawn(team: int) -> Transform3D:
	var side := "north" if team == tower_team else "south"
	var pts: Array = level.spawn_points[side]
	var scored: Array = []
	for xf in pts:
		var p: Vector3 = (xf as Transform3D).origin
		var nearest := 1e9
		var blocked := false
		for o in soldiers:
			if not o.alive:
				continue
			var d := o.global_position.distance_to(p)
			if d < 1.5:
				blocked = true
			if o.team != team:
				nearest = minf(nearest, d)
		if not blocked:
			scored.append([nearest, xf])
	var pick: Transform3D = pts[randi() % pts.size()]
	if not scored.is_empty():
		scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
		pick = scored[randi() % mini(3, scored.size())][1]
	pick.origin = ground_point(pick.origin)
	return pick


# --- Scoring --------------------------------------------------------------------------

func _on_soldier_died(victim: Soldier, killer: Soldier, cause: String) -> void:
	victim.deaths += 1
	victim.spree = 0
	var msg := ""
	var color: Color = GameConfig.TEAM_COLORS[victim.team]
	if killer == null or killer == victim:
		scores[victim.team] -= 1
		msg = "%s fell to their death" % victim.display_name if cause in ["fell", "fall"] else "%s died" % victim.display_name
	elif killer.team == victim.team:
		scores[killer.team] -= 1
		killer.kills -= 1
		msg = "%s betrayed %s" % [killer.display_name, victim.display_name]
		color = GameConfig.TEAM_COLORS[killer.team]
	else:
		scores[killer.team] += 1
		killer.kills += 1
		killer.spree += 1
		var verb: String = {"melee": "beat down", "maxim": "mowed down", "fell": "knocked off"}.get(cause, "killed")
		msg = "%s %s %s" % [killer.display_name, verb, victim.display_name]
		color = GameConfig.TEAM_COLORS[killer.team]
		_track_medals(killer)
	hud.feed(msg, color)
	if victim == player:
		hud.killed_by = killer.display_name if killer and killer != victim else ""
	_respawn_at[victim] = time + GameConfig.RESPAWN_TIME
	var ammo := victim.weapon.mag + victim.weapon.reserve
	if ammo > 0 and cause != "fell":
		_add_pickup(ground_point(victim.global_position), mini(ammo, 24), true)
	for t in 2:
		if scores[t] >= GameConfig.score_limit:
			_end_match(t)


func _track_medals(k: Soldier) -> void:
	var m: Dictionary = _multi.get(k, {"t": -100.0, "n": 0})
	m["n"] = int(m["n"]) + 1 if time - float(m["t"]) <= GameConfig.MULTIKILL_WINDOW else 1
	m["t"] = time
	_multi[k] = m
	if k != player:
		return
	var multi := ["", "", "Double Kill", "Triple Kill", "Killtacular", "Killtrocity", "Killimanjaro", "Killtastrophe", "Killpocalypse", "Killionaire"]
	var n := int(m["n"])
	if n >= 2:
		hud.announce(multi[mini(n, multi.size() - 1)])
	var sprees := {5: "Killing Spree", 10: "Killing Frenzy", 15: "Running Riot", 20: "Rampage", 25: "Untouchable", 30: "Invincible"}
	if sprees.has(k.spree):
		hud.announce(sprees[k.spree])


func _on_gunner_changed(s: Soldier) -> void:
	level.set_flag_team(s.team if s else -1)
	if s:
		hud.feed("%s manned the Maxim" % s.display_name, GameConfig.TEAM_COLORS[s.team])


func _end_match(team: int) -> void:
	if over:
		return
	over = true
	winner = team
	_end_timer = 8.0
	hud.show_end("%s WIN" % GameConfig.TEAM_NAMES[team].to_upper() if team >= 0 else "DRAW")
