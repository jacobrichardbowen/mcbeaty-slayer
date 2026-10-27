extends SceneTree
## Four seats: a host and three friends fill the lobby, and a fifth player is
## told the game is full. Every process checks at the same wall-clock moment
## (a Unix time given on the command line); the host stays up a little longer.
##   godot --headless --path . -s tests/net_lobby_test.gd -- host Host <deadline>
##   godot --headless --path . -s tests/net_lobby_test.gd -- join <name> <deadline>
## Each prints its result and LOBBY TEST PASSED / FAILED.

var net: Net
var role := ""
var who := ""
var deadline := 0.0
var _left := ""
var _result := -1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	role = args[0]
	who = args[1]
	deadline = float(args[2])
	net = Net.new()
	net.name = "Net"
	root.add_child(net)
	net.match_left.connect(func(reason: String) -> void: _left = reason)
	if role == "host":
		net.host.call_deferred(who, false)
	else:
		net.join.call_deferred(who, "127.0.0.1")


func _physics_process(_delta: float) -> bool:
	var now := Time.get_unix_time_from_system()
	if role == "host":
		# Check while everyone is still here, then stay until they've checked.
		if now >= deadline - 1.0 and _result < 0:
			_result = 1 if net.players.size() == Net.MAX_PLAYERS else 0
			print("[host] lobby: %s" % ", ".join(net.players.values().map(func(p: Dictionary) -> String: return "%s (%s)" % [p["name"], GameConfig.TEAM_NAMES[p["team"]]])))
		if now < deadline + 2.0:
			return false
		return _finish(_result == 1)
	if now < deadline:
		return false
	if who == "Fifth":
		print("[%s] turned away: %s" % [who, _left])
		return _finish(_left.contains("full"))
	print("[%s] sees %d players" % [who, net.players.size()])
	return _finish(net.players.size() == Net.MAX_PLAYERS)


func _finish(ok: bool) -> bool:
	print("LOBBY TEST ", "PASSED" if ok else "FAILED")
	quit(0 if ok else 1)
	return true
