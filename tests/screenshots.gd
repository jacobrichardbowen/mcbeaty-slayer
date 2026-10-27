extends SceneTree
## Renders a handful of viewpoints to PNG for eyeballing the blockout.
## Run (needs a display, e.g. xvfb-run):
##   godot --path . --rendering-method gl_compatibility --resolution 1280x720 --fixed-fps 60 -s tests/screenshots.gd -- <out_dir>

var game: Game
var _out := "user://shots"
var _shots: Array = []
var _i := 0
var _wait := 0
var _cam: Camera3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_start.call_deferred()


func _start() -> void:
	InputSetup.register()
	GameConfig.red_bots = 16
	GameConfig.white_bots = 15
	game = Game.new()
	root.add_child(game)
	game.start()
	# Freeze the bots so every shot is stable.
	for s in game.soldiers:
		if s != game.player:
			s.controller = null
	_cam = Camera3D.new()
	_cam.far = 3000.0
	game.add_child(_cam)
	# [name, kind, a, b, frames to wait] kind: "fp" = player at a looking toward b; "free" = camera at a looking at b; "turret"
	_shots = [
		["overview_south", "free", Vector3(10, 75, 85), Vector3(0, 0, -10)],
		["overview_side", "free", Vector3(-95, 45, -10), Vector3(0, 0, -15)],
		["deck_view", "fp", Vector3(3, 14, -37), Vector3(0, 0, 10)],
		["island_to_tower", "fp", Vector3(4, 0, 12), Vector3(0, 10, -44)],
		["west_path", "fp", Vector3(-30.5, -3, -14), Vector3(-30.5, -2, -30)],
		["tower_inside", "fp", Vector3(0, 0, -42), Vector3(-5, 4, -49)],
		["turret", "turret", Vector3.ZERO, Vector3.ZERO],
		["turret_aim", "turret_aim", Vector3(-10, 0, 8), Vector3.ZERO],
		["soldiers", "free", Vector3(0.5, 1.9, -53.2), Vector3(0, 1.1, -57.5)],
		["roost", "fp", Vector3(-20, 0, 12), Vector3(-39, 6, 26)],
		["pad", "fp", Vector3(20, 0, 10), Vector3(37, 0, 29)],
		["scoreboard", "scoreboard", Vector3(0, 0, -20), Vector3(0, 8, -44)],
		["capture", "capture", Vector3(0, 0, -20), Vector3(0, 8, -44)],
		["rifle", "rifle", Vector3(4, 0, 12), Vector3(0, 6, -44)],
		["rifle_zoom", "rifle_zoom", Vector3(4, 0, 12), Vector3(0, 8, -44)],
		["ragdoll_flight", "ragdoll", Vector3(-1, 1.6, 28), Vector3(-1, 1.0, 18.5), 16],
		["ragdoll_rest", "free", Vector3(3.5, 2.6, 22.5), Vector3(3.2, 0.2, 17), 150],
		["respawn_pick", "dead", Vector3(4, 0, 12), Vector3(0, 6, -44)],
		["flag_reds", "flag", Vector3(22, 5, 32), Vector3(0, 26, -48), 260],
	]


func _process(_delta: float) -> bool:
	if game == null or not game.is_inside_tree():
		return false
	if _i >= _shots.size():
		quit()
		return true
	if _wait == 0:
		_setup(_shots[_i])
	_wait += 1
	if _wait == (_shots[_i][4] if _shots[_i].size() > 4 else 25):
		var img := root.get_viewport().get_texture().get_image()
		var path := "%s/%02d_%s.png" % [_out, _i, _shots[_i][0]]
		img.save_png(path)
		print("saved ", path)
		_wait = 0
		_i += 1
	return false


func _setup(shot: Array) -> void:
	var p := game.player
	p.in_fire = false
	if p.turret and shot[1] != "turret_aim":
		p.turret.dismount()
	match shot[1]:
		"free":
			_cam.current = true
			_cam.global_position = shot[2]
			_cam.look_at(shot[3], Vector3.UP)
			if shot[0] == "soldiers":
				_pose_soldiers()
		"fp":
			game.player_ctrl.camera.current = true
			_place(p, shot[2], shot[3])
		"turret":
			game.player_ctrl.camera.current = true
			p.global_position = game.turret.seat_position()
			p.snap_interpolation()
			game.turret.mount(p)
		"scoreboard":
			game.player_ctrl.camera.current = true
			_place(p, shot[2], shot[3])
			Input.action_press("scoreboard")
		"capture":
			# Reds halfway through taking the bunker.
			Input.action_release("scoreboard")
			game.player_ctrl.camera.current = true
			_place(p, shot[2], shot[3])
			game.bunker.challenger = GameConfig.TEAM_RED
			game.bunker.progress = 0.6
		"rifle":
			Input.action_release("scoreboard")
			game.bunker.progress = 0.0
			game.player_ctrl.camera.current = true
			p.loadout = "rifle"
			p.respawn(Transform3D(Basis.IDENTITY, game.ground_point(shot[2])))
			_place(p, shot[2], shot[3])
		"rifle_zoom":
			game.player_ctrl.camera.current = true
			_place(p, shot[2], shot[3])
			p.zoomed = true
		"ragdoll":
			# A point-blank shotgun kill on each team, thrown across the view.
			p.zoomed = false
			_cam.current = true
			_cam.global_position = shot[2]
			_cam.look_at(shot[3], Vector3.UP)
			var spots := [Vector3(-5, 0, 20.5), Vector3(-3, 0, 18.5)]
			for team in 2:
				for s in game.soldiers:
					if s != p and s.team == team and s.alive:
						s.global_position = game.ground_point(spots[team])
						s.look_yaw = 0.3
						s.snap_interpolation()
						s.model._process(0.0)
						s.die(null, "shotgun", Vector3(1, 0, -0.6 + team * 0.4), GameConfig.FLING_SHOTGUN_MAX)
						break
		"flag":
			# The Reds take the bunker; their banner runs up over the tower.
			_cam.current = true
			_cam.global_position = shot[2]
			_cam.look_at(shot[3], Vector3.UP)
			game.level.set_flag_team(GameConfig.TEAM_RED)
		"dead":
			p.zoomed = false
			game.player_ctrl.camera.current = true
			p.die(game.soldiers[1], "rifle")
			game.hud.killed_by = game.soldiers[1].display_name
		"turret_aim":
			# Swing the gun toward a point on the island and fire a burst.
			game.player_ctrl.camera.current = true
			p.global_position = game.turret.seat_position()
			p.snap_interpolation()
			game.turret.mount(p)
			game.player_ctrl._sync_mode()
			var d: Vector3 = (shot[2] as Vector3) - game.turret.pivot_position()
			game.player_ctrl._cam_yaw = atan2(-d.x, -d.z)
			game.player_ctrl._cam_pitch = asin(d.normalized().y) + 0.05
			p.in_fire = true


func _place(p: Soldier, at: Vector3, look: Vector3) -> void:
	p.global_position = game.ground_point(at)
	p.velocity = Vector3.ZERO
	p.snap_interpolation()
	var d := (look - p.eye_position()).normalized()
	p.look_yaw = atan2(-d.x, -d.z)
	p.look_pitch = asin(d.y)


func _pose_soldiers() -> void:
	var xs := [-2.4, -0.8, 0.8, 2.4]
	var k := 0
	for s in game.soldiers:
		if s == game.player or k >= xs.size():
			continue
		s.global_position = game.ground_point(Vector3(xs[k], 0, -57.5))
		s.snap_interpolation()
		s.look_yaw = PI + (0.35 if k % 2 == 0 else -0.35)
		k += 1
