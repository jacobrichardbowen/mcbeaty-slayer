extends SceneTree
## Headless smoke test: builds a match full of bots, checks the navmesh links
## every spawn to the Maxim, then simulates a few minutes of play.
## Run: godot --headless --path . --fixed-fps 60 -s tests/smoke_test.gd [-- reds=N whites=N near|far]

const SIM_SECONDS := 300.0

var game: Game
var _t := 0.0
var _next_report := 0.0
var _mounts := 0
var _kills := 0
var _failures: Array[String] = []
var _was_alive := {}
var _spawns := 0
var _bad_spawns := 0
var _flips := 0
var _wall_start := 0


func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	InputSetup.register()
	GameConfig.red_bots = 4
	GameConfig.white_bots = 3
	GameConfig.score_limit = 250
	# Optional overrides: -- reds=N whites=N far
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("reds="):
			GameConfig.red_bots = int(arg.substr(5))
		elif arg.begins_with("whites="):
			GameConfig.white_bots = int(arg.substr(7))
		elif arg == "far":
			GameConfig.bunker_start = GameConfig.TEAM_RED
		elif arg == "near":
			GameConfig.bunker_start = GameConfig.TEAM_WHITE
	game = Game.new()
	root.add_child(game)
	game.start()
	_wall_start = Time.get_ticks_msec()
	game.bunker.holder_changed.connect(func(team: int, reason: String) -> void:
		_flips += 1
		print("[%6.1f] bunker -> %s (%s)" % [game.time, GameConfig.TEAM_NAMES[team], reason]))
	game.turret.gunner_changed.connect(func(s: Soldier) -> void:
		if s:
			_mounts += 1
			print("[%6.1f] %s mounted the Maxim" % [game.time, s.display_name]))
	for s in game.soldiers:
		s.died.connect(func(v: Soldier, k: Soldier, cause: String) -> void:
			_kills += 1
			print("[%6.1f] %s -> %s (%s)" % [game.time, k.display_name if k else "-", v.display_name, cause]))


func _check_paths() -> void:
	var map := game.level.nav_region.get_navigation_map()
	var seat := game.turret.seat_position()
	for side in ["bunker", "far", "west", "east"]:
		for xf in game.level.spawn_points[side]:
			var from := game.ground_point((xf as Transform3D).origin)
			var path := NavigationServer3D.map_get_path(map, from, seat, true)
			var ok := path.size() > 1 and path[path.size() - 1].distance_to(seat) < 1.5
			if not ok:
				_failures.append("no nav path %s spawn %s -> seat (end %s)" % [side, from, path[path.size() - 1] if path.size() else "none"])
	for key in game.level.routes:
		for wp in game.level.routes[key]:
			var p := game.ground_point(wp)
			var c := NavigationServer3D.map_get_closest_point(map, p)
			if c.distance_to(p) > 1.0:
				_failures.append("route %s waypoint %s off navmesh (closest %s)" % [key, p, c])
	print("nav check done, polygons: ", game.level.nav_region.navigation_mesh.get_polygon_count())


func _physics_process(delta: float) -> bool:
	if game == null or not game.is_inside_tree():
		return false
	_t += delta
	if _t > 0.3 and _t - delta <= 0.3:
		_check_paths()
	if _t >= _next_report:
		_next_report += 15.0
		var line := "[%6.1f] score W %d R %d |" % [game.time, game.scores[0], game.scores[1]]
		for s in game.soldiers:
			line += " %s(%.0f,%.0f,%.0f)%s" % [s.display_name.substr(0, 4), s.global_position.x, s.global_position.y, s.global_position.z, "" if s.alive else "x"]
		print(line)
	_check_respawns()
	var p := game.player
	if p.alive and _t > 1.0 and p.global_position.y < -5.0 and not p.is_on_floor():
		_failures.append("player fell through the world at %s" % p.global_position)
		p.die(null, "test")
	if _t >= SIM_SECONDS:
		_finish()
		return true
	return false


## Every respawn must land on the side its team is entitled to right now.
func _check_respawns() -> void:
	for s in game.soldiers:
		var was: bool = _was_alive.get(s, true)
		if s.alive and not was and _t > 1.0:
			_spawns += 1
			var side := game.spawn_side(s.team)
			var ok := false
			for xf in game.level.spawn_points[side]:
				var o: Vector3 = (xf as Transform3D).origin
				ok = ok or Vector2(o.x - s.global_position.x, o.z - s.global_position.z).length() < 1.0
			if not ok:
				_bad_spawns += 1
				print("[%6.1f] %s (%s) spawned off its %s side at %s" % [game.time, s.display_name, GameConfig.TEAM_NAMES[s.team], side, s.global_position])
		_was_alive[s] = s.alive


func _finish() -> void:
	var wall := (Time.get_ticks_msec() - _wall_start) / 1000.0
	print("mounts: %d  deaths: %d  respawns: %d (wrong side %d)  bunker flips: %d" % [_mounts, _kills, _spawns, _bad_spawns, _flips])
	print("simulated %.0f s in %.1f s wall (%.2fx real time, %d soldiers)" % [SIM_SECONDS, wall, SIM_SECONDS / wall, game.soldiers.size()])
	if _bad_spawns > 0:
		_failures.append("%d respawns on the wrong side" % _bad_spawns)
	if _mounts == 0:
		_failures.append("no bot ever manned the Maxim")
	if _kills == 0:
		_failures.append("nobody died in %d s" % SIM_SECONDS)
	for f in _failures:
		print("FAIL: ", f)
	print("SMOKE TEST ", "PASSED" if _failures.is_empty() else "FAILED")
	quit(0 if _failures.is_empty() else 1)
