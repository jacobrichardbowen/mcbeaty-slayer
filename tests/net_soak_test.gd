extends SceneTree
## Four players on four copies of the game, each played by the bot AI, plus
## the host's bots, fighting for a minute over this machine's network. At the
## same wall-clock moment every copy prints where it sees each soldier, so
## the views can be compared, then the match ends. tools/net_soak.sh runs all
## four and compares them; by hand:
##   godot --headless --path . -s tests/net_soak_test.gd -- host Host <deadline> [via]
##   godot --headless --path . -s tests/net_soak_test.gd -- join <name> <deadline> [via]
## `via` is "direct" (the default: friends connect straight to 127.0.0.1) or
## "fake:<stun port>:<board port>:<router port>": through tests/fake_internet.py,
## the way friends join over the real internet, with a join code.

var net: Net
var game: Game
var role := ""
var who := ""
var deadline := 0.0
var _brain: BotBrain
var _printed := false
var _deaths := {}  # net id -> Unix time of its latest death seen here


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0]
	who = args[1]
	deadline = float(args[2])
	InputSetup.register()
	net = Net.new()
	net.name = "Net"
	root.add_child(net)
	net.status_changed.connect(func(text: String) -> void: print("[%s] %s" % [who, text]))
	net.match_started.connect(func() -> void:
		game = Game.new()
		root.add_child(game)
		game.start()
		for s in game.soldiers:
			s.died.connect(func(v: Soldier, _k: Soldier, _c: String) -> void: _deaths[v.net_id] = Time.get_unix_time_from_system())
		# Our player is played by the bot AI too.
		_brain = BotBrain.new(game.player, game))
	var via := (args[3] if args.size() > 3 else "direct").split(":")
	if via[0] == "fake":
		Net.stun_servers = [["127.0.0.1", int(via[1])]]
		Net.meeting_url = "http://127.0.0.1:%s/" % via[2]
	if role == "host":
		net.host.call_deferred(who, via[0] == "fake")
	else:
		net.join.call_deferred(who, Net.encode("127.0.0.1", int(via[3])) if via[0] == "fake" else "127.0.0.1")


func _physics_process(_delta: float) -> bool:
	var now := Time.get_unix_time_from_system()
	if role == "host" and game == null and (net.players.size() == Net.MAX_PLAYERS or now > deadline - 55.0):
		net.start_match(5, 7)
	if game and not _printed and now >= deadline - 2.0:
		_printed = true
		var view := {}
		for s in game.soldiers:
			view[s.net_id] = [snappedf(s.global_position.x, 0.01), snappedf(s.global_position.y, 0.01), snappedf(s.global_position.z, 0.01), s.alive, s.owner_peer, s.puppet]
		print("VIEW %s %s" % [who, JSON.stringify({"me": net.my_peer(), "at": now, "code": net.code, "deaths": _deaths, "soldiers": view,
			"scores": game.scores, "snapshot_bytes": game.pack_snapshot().size()})])
	if now >= deadline + (2.0 if role == "host" else 0.0):
		quit()
		return true
	return false
