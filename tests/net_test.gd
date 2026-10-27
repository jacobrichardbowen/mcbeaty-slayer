extends SceneTree
## Two copies of the game play a scripted online match over this machine's
## network. Run the host first, then the client, each in its own process:
##   godot --headless --path . -s tests/net_test.gd -- host
##   godot --headless --path . -s tests/net_test.gd -- client
## Each prints its own checks and NET TEST PASSED / FAILED.

var role := ""
var net: Net
var game: Game
var _failures: Array[String] = []
var _done := {}
var _start := -1.0
var _host_x := Vector2(INF, -INF)  # the host's lowest and highest x seen
var _red_score_seen := 0


func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "host"
	InputSetup.register()
	net = Net.new()
	net.name = "Net"
	root.add_child(net)
	net.match_started.connect(_on_match_started)
	if role == "host":
		GameConfig.player_loadout = "rifle"
		net.host.call_deferred("Host", false)
	else:
		GameConfig.player_loadout = "shotgun"
		_expect(Net.decode(Net.encode("203.0.113.7", 24565)) == ["203.0.113.7", 24565], "a join code spells the address and port")
		# RFC 5769's sample STUN answer (section 2.2): 192.0.2.1, port 32853.
		var stun := "0101003c2112a442b7e7a701bc34d686fa87dfae8022000b7465737420766563746f7220002000080001a147e112a643000800142b91f599fd9e90c38c7489f92af9ba53f06be7d780280004c07d4c96"
		_expect(Stun.parse(stun.hex_decode(), "b7e7a701bc34d686fa87dfae".hex_decode()) == ["192.0.2.1", 32853], "a STUN answer reads right")
		net.join.call_deferred("Client", "127.0.0.1")


func _expect(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + "[%s] %s" % [role, what])
	if not cond:
		_failures.append(what)


func _once(key: String) -> bool:
	if _done.has(key):
		return false
	_done[key] = true
	return true


func _on_match_started() -> void:
	game = Game.new()
	root.add_child(game)
	game.start()
	# Scripted soldiers only: no bot or player input.
	for s in game.soldiers:
		s.controller = null


func _finish() -> void:
	print("NET TEST ", "PASSED" if _failures.is_empty() else "FAILED")
	quit(0 if _failures.is_empty() else 1)


func _physics_process(_delta: float) -> bool:
	var now := Net.clock()
	if role == "host" and game == null and net.players.size() == 2 and _once("start"):
		_expect(true, "the client joined the lobby")
		net.start_match(1, 2)
	if game == null or not game.is_inside_tree():
		if now > 40.0 and _once("timeout"):
			_expect(false, "the match started")
			_finish()
		return false
	if _start < 0.0:
		_start = now
		_expect(game.soldiers.size() == 5, "everyone has the same 5 soldiers (%d)" % game.soldiers.size())
	var t := now - _start
	if role == "host":
		_host_script(t)
	else:
		_client_script(t)
	return false


func _soldier(soldier_name: String) -> Soldier:
	for s in game.soldiers:
		if s.display_name == soldier_name:
			return s
	return null


func _host_script(t: float) -> void:
	var me := game.player
	var client := _soldier("Client")
	var bot := _soldier(GameConfig.WHITE_NAMES[0])
	if t > 0.5 and _once("park"):
		# The White bot waits on open ground for the client to shoot it.
		bot.global_position = game.ground_point(Vector3(-6, 0, 19.5))
		me.global_position = game.ground_point(Vector3(8, 0, 19.5))
		me.look_yaw = 0.0
	if t > 2.0 and t < 3.0:
		me.in_move = Vector2(-1, 0)  # strafe along open ground for the client to watch
	elif t >= 3.0 and t < 3.1:
		me.in_move = Vector2.ZERO
	if t > 9.0 and _once("host_shoots"):
		# One rifle body shot at the client: hurts, doesn't kill.
		me.global_position = game.ground_point(Vector3(7, 0, 19.5))
		me.snap_interpolation()
	if t > 9.2 and t < 9.3 and client.alive:
		var to := client.chest_position() - me.eye_position()
		me.look_yaw = atan2(-to.x, -to.z)
		me.look_pitch = asin(to.normalized().y)
		me.in_fire = true
	elif t >= 9.3:
		me.in_fire = false
	if t > 7.5 and _once("kill_seen"):
		_expect(not bot.alive, "the client's shotgun killed the host's bot")
		_expect(game.scores[GameConfig.TEAM_RED] >= 1, "the Reds scored for it (%d)" % game.scores[GameConfig.TEAM_RED])
	if t > 3.0 and _once("client_moves"):
		_expect(client.puppet and client.global_position.distance_to(game.ground_point(Vector3(-2, 0, 19.5))) < 2.5, "the client's soldier shows where the client put it")
	if t > 15.0 and _once("gun_seen"):
		_expect(game.turret.gunner == client, "the client is on the Maxim")
		_expect(game.bunker.holder == GameConfig.TEAM_RED, "manning it took the bunker for the Reds")
	if t > 21.0 and _once("left_seen"):
		_expect(not client.puppet and client.controller is BotBrain, "a bot took over when the client left")
		_finish()


func _client_script(t: float) -> void:
	var me := game.player
	var host := _soldier("Host")
	var bot := _soldier(GameConfig.WHITE_NAMES[0])
	if t > 1.0 and _once("stand"):
		me.global_position = game.ground_point(Vector3(-2, 0, 19.5))
	# The two machines start their clocks apart, so watch the host's whole strafe.
	if t > 0.2 and t < 4.6:
		_host_x.x = minf(_host_x.x, host.global_position.x)
		_host_x.y = maxf(_host_x.y, host.global_position.x)
	if t > 4.6 and _once("host_moved"):
		_expect(_host_x.y - _host_x.x > 3.0, "the host's soldier moves on the client's screen (%.1f m)" % (_host_x.y - _host_x.x))
	if t > 5.5 and t < 5.6 and bot.alive:
		# Point blank at the host's bot.
		me.global_position = bot.global_position + Vector3(3, 0, 0)
		me.snap_interpolation()
	if t > 5.8 and t < 5.9 and bot.alive:
		var to := bot.chest_position() - me.eye_position()
		me.look_yaw = atan2(-to.x, -to.z)
		me.look_pitch = asin(to.normalized().y)
		me.in_fire = true
	elif t >= 5.9:
		me.in_fire = false
	if t > 7.5 and _once("kill_back"):
		_expect(not bot.alive, "the bot's death came back from the host")
		_expect(game.scores[GameConfig.TEAM_RED] >= 1, "the score came back too")
	if t > 11.0 and _once("hurt"):
		_expect(me.alive and me.health < 60.0, "the host's rifle round hurt the client (health %.0f)" % me.health)
	if t > 11.5 and t < 13.0:
		if _once("to_gun"):
			me.global_position = game.turret.seat_position()
			me.snap_interpolation()
		me.in_action = true
	elif t >= 13.0 and t < 13.1:
		me.in_action = false
	if t > 14.5 and _once("on_gun"):
		_expect(me.turret == game.turret, "the host let the client onto the Maxim")
		_expect(game.bunker.holder == GameConfig.TEAM_RED and game.level.flag.team == GameConfig.TEAM_RED, "the bunker and its flag turned Red on the client")
	if t > 16.0 and _once("leave"):
		net.leave()
		_finish()
