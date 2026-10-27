class_name Game
extends Node3D
## One Tower of Power match: team slayer, no shields, shotguns only, one Maxim
## gun on the Big Tower. Builds the world, spawns soldiers, keeps score.
## Online (see Net) the host's copy runs the match; a client's copy shows it,
## driven by the host's snapshots and events, with its own soldier played
## locally.

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
var wind: AudioStreamPlayer
var scores := [0, 0]
var time := 0.0
var time_left := GameConfig.TIME_LIMIT
var over := false
var winner := -1
var bunker: BunkerControl
var quit_by_player := false  # left from the pause menu (rather than the match ending)

var _soldier_root: Node3D
var _bots: Array[BotBrain] = []
var _respawn_at := {}
var _multi := {}
var _end_timer := 0.0
var _pickups := {}  # id -> AmmoPickup, the same ids on every machine
var _next_pickup := 0


func start() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	Fx.reset()
	Sfx.warm_up()
	_build_environment()
	# Wind and snow howl over Ascension all match long, under the gunfire.
	wind = AudioStreamPlayer.new()
	wind.name = "Wind"
	wind.stream = Sfx.stream("wind")
	wind.volume_db = GameConfig.WIND_VOLUME
	wind.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(wind)
	wind.play()
	level = AscensionLevel.new()
	level.name = "Ascension"
	add_child(level)
	level.build()
	Acoustics.setup(level)
	fx_root = Node3D.new()
	fx_root.name = "Fx"
	add_child(fx_root)
	turret = MaximTurret.new()
	turret.name = "Maxim"
	turret.transform = level.turret_transform
	add_child(turret)
	turret.gunner_changed.connect(_on_gunner_changed)
	var start_holder := GameConfig.bunker_start
	bunker = BunkerControl.new(start_holder)
	bunker.holder_changed.connect(_on_holder_changed)
	level.set_flag_team(start_holder, true)
	for p in level.ammo_points:
		_add_pickup(ground_point(p), 0, false)
	for tp in level.teleporters:
		var t := Teleporter.new()
		t.destination = tp["to"]
		t.position = tp["from"]
		add_child(t)

	_soldier_root = Node3D.new()
	_soldier_root.name = "Soldiers"
	add_child(_soldier_root)
	if Net.online():
		_spawn_roster(Net.instance)
	else:
		_spawn_soldier(GameConfig.TEAM_WHITE, "You", "player").respawn(_choose_spawn(GameConfig.TEAM_WHITE))
		for i in GameConfig.white_bots:
			_spawn_soldier(GameConfig.TEAM_WHITE, GameConfig.WHITE_NAMES[i % GameConfig.WHITE_NAMES.size()], "bot").respawn(_choose_spawn(GameConfig.TEAM_WHITE))
		for i in GameConfig.red_bots:
			_spawn_soldier(GameConfig.TEAM_RED, GameConfig.RED_NAMES[i % GameConfig.RED_NAMES.size()], "bot").respawn(_choose_spawn(GameConfig.TEAM_RED))

	hud = Hud.new()
	hud.game = self
	add_child(hud)
	pause_menu = PauseMenu.new()
	pause_menu.quit_requested.connect(func() -> void:
		quit_by_player = true
		exit_requested.emit())
	pause_menu.restart_requested.connect(func() -> void: restart_requested.emit())
	add_child(pause_menu)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var goal := "Hold the bunker" if bunker.holder == player.team else "Take the bunker"
	if bunker.holder < 0:
		goal = "The bunker is up for grabs: take it"
	hud.announce("Tower of Power")
	hud.feed("%s. First to %d kills." % [goal, GameConfig.score_limit], GameConfig.TEAM_COLORS[0])
	hud.feed("Whoever holds the bunker spawns there.", Color(0.8, 0.8, 0.8))


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


func soldier_by_id(id: int) -> Soldier:
	for s in soldiers:
		if s.net_id == id:
			return s
	return null


func _unhandled_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and not input_blocked() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	# Indoors the wind drops to a muffled whistle.
	var cam := get_viewport().get_camera_3d()
	var target := GameConfig.WIND_VOLUME - (10.0 if cam and Acoustics.indoors(cam.global_position) else 0.0)
	wind.volume_db = move_toward(wind.volume_db, target, delta * 20.0)


func _physics_process(delta: float) -> void:
	if over:
		_end_timer -= delta
		if _end_timer <= 0.0:
			exit_requested.emit()
		return
	time += delta
	time_left -= delta
	if Net.is_client():
		return  # the host runs the rules
	bunker.update(delta, soldiers, turret.gunner)
	for s in _respawn_at.keys():
		if time >= float(_respawn_at[s]):
			_respawn_at.erase(s)
			var xf := _choose_spawn((s as Soldier).team)
			(s as Soldier).respawn(xf)
			if Net.is_host():
				Net.instance.send(Net.Ev.RESPAWN, [(s as Soldier).net_id, xf])
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


## role: "player" (played here), "bot" (run here) or "puppet" (run elsewhere).
func _spawn_soldier(team: int, soldier_name: String, role: String, peer := 1) -> Soldier:
	var s := Soldier.new()
	s.setup(self, team, soldier_name, role == "player")
	s.net_id = soldiers.size()
	s.owner_peer = peer
	s.puppet = role == "puppet"
	if role == "player":
		s.loadout = GameConfig.player_loadout
	_soldier_root.add_child(s)
	s.died.connect(_on_soldier_died)
	soldiers.append(s)
	if role == "player":
		player = s
		player_ctrl = PlayerController.new()
		player_ctrl.name = "PlayerController"
		player_ctrl.setup(self, s)
		add_child(player_ctrl)
	elif role == "bot":
		_add_bot(s)
	return s


func _add_bot(s: Soldier) -> void:
	var bot := BotBrain.new(s, self)
	bot.hunter = _bots.filter(func(b: BotBrain) -> bool: return b.s.team == s.team).size() % 3 != 0
	_bots.append(bot)


## Online: everyone builds the same soldiers in the same order. The host
## picks the first spawns and then tells the others to begin.
func _spawn_roster(net: Net) -> void:
	net.game = self
	var me := net.my_peer()
	for r: Dictionary in net.roster:
		var peer: int = r["peer"]
		var role := "player" if peer == me else ("bot" if peer == 0 and Net.is_host() else "puppet")
		var s := _spawn_soldier(r["team"], r["name"], role, peer if peer > 0 else 1)
		if Net.is_host():
			r["xf"] = _choose_spawn(s.team)
		s.respawn(r["xf"])
	if Net.is_host():
		net.send_start()


func _add_pickup(pos: Vector3, amount: int, dropped: bool, kind := "shotgun", id := -1) -> void:
	var p := AmmoPickup.new()
	p.amount = amount
	p.dropped = dropped
	p.kind = kind
	p.position = pos
	p.id = id if id >= 0 else _next_pickup
	_next_pickup = maxi(_next_pickup, p.id + 1)
	_pickups[p.id] = p
	p.tree_exiting.connect(func() -> void: _pickups.erase(p.id))
	add_child(p)
	if dropped and Net.is_host():
		Net.instance.send(Net.Ev.DROP, [p.id, pos, amount, kind])


## The bunker holders spawn at the bunker, everyone else on the far side.
## Before anyone has taken it, each team has its own neutral side. Within a
## side, pick a spot away from living enemies.
func _choose_spawn(team: int) -> Transform3D:
	return _pick_spawn(team, spawn_side(team))


func spawn_side(team: int) -> String:
	if bunker.holder < 0:
		return "west" if team == GameConfig.TEAM_WHITE else "east"
	return "bunker" if team == bunker.holder else "far"


func _pick_spawn(team: int, side: String) -> Transform3D:
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
	if victim == player:
		hud.killed_by = killer.display_name if killer and killer != victim else ""
	if Net.is_client():
		# The host keeps score; this just counts down our own respawn.
		_respawn_at[victim] = time + GameConfig.RESPAWN_TIME
		return
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
		var verb: String = {"melee": "beat down", "maxim": "mowed down", "fell": "knocked off",
			"rifle": "shot", "headshot": "headshot"}.get(cause, "killed")
		msg = "%s %s %s" % [killer.display_name, verb, victim.display_name]
		color = GameConfig.TEAM_COLORS[killer.team]
		_track_medals(killer)
	_feed(msg, color)
	_respawn_at[victim] = time + GameConfig.RESPAWN_TIME
	var ammo := victim.weapon.mag + victim.weapon.reserve
	if ammo > 0 and cause != "fell":
		_add_pickup(ground_point(victim.global_position), mini(ammo, victim.weapon.max_reserve() / 2), true, victim.weapon.kind)
	for t in 2:
		if scores[t] >= GameConfig.score_limit:
			_end_match(t)


## A kill-feed line, for everyone.
func _feed(msg: String, color: Color) -> void:
	hud.feed(msg, color)
	if Net.is_host():
		Net.instance.send(Net.Ev.FEED, [msg, color])


func _track_medals(k: Soldier) -> void:
	var m: Dictionary = _multi.get(k, {"t": -100.0, "n": 0})
	m["n"] = int(m["n"]) + 1 if time - float(m["t"]) <= GameConfig.MULTIKILL_WINDOW else 1
	m["t"] = time
	_multi[k] = m
	var human_elsewhere := k.puppet and Net.is_host()
	if k != player and not human_elsewhere:
		return
	var multi := ["", "", "Double Kill", "Triple Kill", "Killtacular", "Killtrocity", "Killimanjaro", "Killtastrophe", "Killpocalypse", "Killionaire"]
	var sprees := {5: "Killing Spree", 10: "Killing Frenzy", 15: "Running Riot", 20: "Rampage", 25: "Untouchable", 30: "Invincible"}
	var n := int(m["n"])
	var calls := []
	if n >= 2:
		calls.append(multi[mini(n, multi.size() - 1)])
	if sprees.has(k.spree):
		calls.append(sprees[k.spree])
	for text: String in calls:
		if k == player:
			hud.announce(text)
		else:
			Net.instance.send(Net.Ev.ANNOUNCE, [text], k.owner_peer)


func _on_gunner_changed(s: Soldier) -> void:
	if Net.is_client():
		return
	if Net.is_host():
		Net.instance.send(Net.Ev.MOUNTED, [s.net_id if s else -1])
	if s:
		_feed("%s manned the Maxim" % s.display_name, GameConfig.TEAM_COLORS[s.team])


func _on_holder_changed(team: int, _reason: String) -> void:
	level.set_flag_team(team)
	_feed("%s took the bunker and now spawn there" % GameConfig.TEAM_NAMES[team], GameConfig.TEAM_COLORS[team])
	if player:
		hud.announce("Bunker taken" if team == player.team else "Bunker lost")


func _end_match(team: int) -> void:
	if over:
		return
	over = true
	winner = team
	_end_timer = 8.0
	hud.show_end("%s WIN" % GameConfig.TEAM_NAMES[team].to_upper() if team >= 0 else "DRAW")
	if Net.is_host():
		Net.instance.send(Net.Ev.END, [team])


# --- Online -----------------------------------------------------------------------------

## Host: the whole match as it stands, 20 times a second.
func pack_snapshot() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_double(Net.clock())
	buf.put_float(time_left)
	buf.put_16(scores[0])
	buf.put_16(scores[1])
	buf.put_8(bunker.holder)
	buf.put_8(bunker.challenger)
	buf.put_u8(int(clampf(bunker.progress, 0.0, 1.0) * 255.0))
	NetCodec.put_pitch(buf, turret.yaw)
	NetCodec.put_pitch(buf, turret.pitch)
	buf.put_u8(1 if turret.is_firing() else 0)
	buf.put_u8(soldiers.size())
	for s in soldiers:
		var latest := s.latest_net_state() if s.puppet and s.alive else {}
		if latest.is_empty():
			NetCodec.put_motion(buf, s, NetCodec.flags_of(s))
		else:
			# A friend's newest state goes straight on, not our view of it a moment behind.
			NetCodec.put_motion(buf, s, int(latest["flags"]) | NetCodec.ALIVE, latest)
		buf.put_u8(int(clampf(s.health, 0.0, 255.0)))
		buf.put_16(s.kills)
		buf.put_u16(s.deaths)
	return buf.data_array


## Client: applies the host's snapshot.
func apply_snapshot(data: PackedByteArray) -> void:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	var sent := buf.get_double()
	var at := sent + Net.instance.clock_offset(1, sent)
	time_left = buf.get_float()
	scores = [buf.get_16(), buf.get_16()]
	var holder := buf.get_8()
	bunker.challenger = buf.get_8()
	bunker.progress = buf.get_u8() / 255.0
	if holder != bunker.holder:
		bunker.holder = holder
		level.set_flag_team(holder)
		if holder >= 0:
			hud.announce("Bunker taken" if holder == player.team else "Bunker lost")
	var tyaw := NetCodec.get_pitch(buf)
	var tpitch := NetCodec.get_pitch(buf)
	var firing := buf.get_u8() == 1
	if turret.gunner and turret.gunner != player:
		turret.set_aim(tyaw, tpitch)
		turret.set_remote_firing(firing)
	for i in buf.get_u8():
		var st := NetCodec.get_motion(buf)
		var health := float(buf.get_u8())
		var kills := buf.get_16()
		var deaths := buf.get_u16()
		var s := soldier_by_id(st["id"])
		if s == null:
			continue
		s.kills = kills
		s.deaths = deaths
		if s.alive:
			s.health = health
		if s.puppet:
			s.push_net_state(at, st)


## Client: our own soldier, 30 times a second.
func pack_own_state() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_double(Net.clock())
	var gunning := turret.gunner == player
	NetCodec.put_motion(buf, player, NetCodec.flags_of(player, gunning and turret.is_firing()))
	buf.put_u8(1 if gunning else 0)
	if gunning:
		NetCodec.put_pitch(buf, turret.yaw)
		NetCodec.put_pitch(buf, turret.pitch)
	return buf.data_array


## Host: a player's update about their own soldier.
func apply_player_state(peer: int, data: PackedByteArray) -> void:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	var sent := buf.get_double()
	var at := sent + Net.instance.clock_offset(peer, sent)
	var st := NetCodec.get_motion(buf)
	var s := soldier_by_id(st["id"])
	if s == null or s.owner_peer != peer or not s.puppet:
		return
	if s.alive:
		s.push_net_state(at, st)
	if buf.get_u8() == 1 and turret.gunner == s:
		turret.set_aim(NetCodec.get_pitch(buf), NetCodec.get_pitch(buf))
		turret.set_remote_firing(int(st["flags"]) & NetCodec.FIRING != 0)


## A game event from another machine (see Net.Ev).
func on_net_event(kind: int, args: Array, sender: int) -> void:
	var host := Net.is_host()
	match kind:
		Net.Ev.FIRED:
			var s := soldier_by_id(args[0])
			if s and s.puppet:
				s.net_fired(args[1], args[2], args[3], args[4])
			Net.instance.relay(kind, args, sender)
		Net.Ev.MG_FIRED:
			turret.net_fired(args[0], args[1], args[2])
			Net.instance.relay(kind, args, sender)
		Net.Ev.MELEE:
			var s := soldier_by_id(args[0])
			if s and s.puppet:
				s.melee_time = time
				Sfx.play_3d(s, "swing", s.eye_position(), -8.0)
			Net.instance.relay(kind, args, sender)
		Net.Ev.PICKUP:
			if _pickups.has(args[0]):
				(_pickups[args[0]] as AmmoPickup).take()
			Net.instance.relay(kind, args, sender)
		Net.Ev.HIT:
			# A player's hit, or their own fall. Only their own soldier's shots count.
			var victim := soldier_by_id(args[0])
			var attacker := soldier_by_id(args[2])
			var shooter_ok := attacker != null and attacker.owner_peer == sender
			var own_fall := attacker == null and victim != null and victim.owner_peer == sender
			if host and victim and (shooter_ok or own_fall):
				if args[3] == "melee":
					Sfx.play_3d(victim, "melee_hit", args[4], 0.0)
					Fx.blood(fx_root, args[4], args[5])
				victim.take_damage(args[1], attacker, args[3], args[4], args[5])
		Net.Ev.KILL:
			var victim := soldier_by_id(args[0])
			if host and victim and victim.owner_peer == sender:
				victim.die(soldier_by_id(args[1]), args[2], Vector3.DOWN)
		Net.Ev.MOUNT:
			var s := soldier_by_id(args[0])
			if host and s and s.owner_peer == sender:
				if args[1] and turret.can_mount(s):
					turret.mount(s)
				elif not args[1] and turret.gunner == s:
					turret.dismount()
		Net.Ev.DAMAGED:
			var victim := soldier_by_id(args[0])
			if victim:
				# Our own melee already made its sound and blood here.
				if args[3] == "melee" and soldier_by_id(args[2]) != player:
					Sfx.play_3d(victim, "melee_hit", args[4], 0.0)
					Fx.blood(fx_root, args[4], Vector3.UP)
				victim.net_damaged(args[1], soldier_by_id(args[2]), args[4], args[5])
		Net.Ev.DIED:
			var victim := soldier_by_id(args[0])
			if victim:
				victim.net_die(soldier_by_id(args[1]), args[2], args[3], args[4])
		Net.Ev.RESPAWN:
			var s := soldier_by_id(args[0])
			if s:
				s.respawn(args[1])
				_respawn_at.erase(s)
		Net.Ev.MOUNTED:
			var s := soldier_by_id(args[0])
			if s == null:
				turret.dismount()
			elif turret.gunner != s:
				turret.dismount()
				turret.mount(s)
		Net.Ev.DROP:
			_add_pickup(args[1], args[2], true, args[3], args[0])
		Net.Ev.FEED:
			hud.feed(args[0], args[1])
		Net.Ev.ANNOUNCE:
			hud.announce(args[0])
		Net.Ev.END:
			_end_match(args[0])


## Host: a player left mid-match; a bot takes over their soldier.
func remove_peer(peer: int, who: String) -> void:
	for s in soldiers:
		if s.owner_peer == peer and s.puppet:
			s.puppet = false
			s.owner_peer = 1
			s.snap_interpolation()
			_add_bot(s)
	_feed("%s left; a bot takes their place" % who, Color(0.8, 0.8, 0.8))
