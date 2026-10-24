extends SceneTree
## Renders a handful of viewpoints to PNG for eyeballing the blockout.
## Run (needs a display, e.g. xvfb-run):
##   godot --path . --rendering-method gl_compatibility --resolution 1280x720 -s tests/screenshots.gd -- <out_dir>

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
	GameConfig.red_bots = 4
	GameConfig.white_bots = 2
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
	# [name, kind, a, b] kind: "fp" = player at a looking toward b; "free" = camera at a looking at b; "turret"
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
	if _wait == 25:
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
