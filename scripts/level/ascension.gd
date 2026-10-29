class_name AscensionLevel
extends Node3D
## Hand-built blockout of Halo 2's Ascension, laid out for Tower of Power.
## (The gruntmods map files could not be downloaded from the build sandbox, so
## this is a from-memory layout; see README for swapping in real geometry.)
##
## Top view, -Z is north:
##   Big Tower + Maxim gun ........ north platform, gun faces south over the map
##   Dish + rotating antenna ...... centre of the main island (origin)
##   Command Center ............... east side of the island, walkable roof
##   Sniper Roost / Little Tower .. south-west platform
##   Landing Pad .................. south-east platform via a covered walkway
##   Leap of Faith ................ low ledge off the landing pad, teleporter back
## The west and east side paths drop below the island rim and run under cover
## to the tower's flanks, outside the gun's traverse arc. The centre bridge and
## the open island are the gun's kill zone.

const ISLAND := [
	Vector2(-24, -14), Vector2(-12, -20.5), Vector2(12, -20.5), Vector2(24, -14), Vector2(29, 0),
	Vector2(26, 14), Vector2(16, 22), Vector2(-16, 22), Vector2(-27, 13), Vector2(-29, 0),
]
const TOWER_PLATFORM := [
	Vector2(-12, -31), Vector2(12, -31), Vector2(18, -37), Vector2(18, -54),
	Vector2(12, -60), Vector2(-12, -60), Vector2(-18, -54), Vector2(-18, -37),
]
const DISH_R := 13.0
const DISH_DEPTH := 3.2
const SPIN_SPEED := 0.14  # rad/s, one turn every ~45 s
const DECK_Y := 14.0
const TOWER_CENTER := Vector3(0, 0, -44)

## "bunker": around the Big Tower, used by whoever holds it. "far": the south
## half of the map, used by the other team. Until someone first takes the
## bunker, Whites use "west" and Reds use "east": mirror-image spots the same
## distance from the tower. 16 each, one per soldier.
var spawn_points := {"bunker": [], "far": [], "west": [], "east": []}
var turret_transform := Transform3D(Basis(Vector3.UP, PI), Vector3(0, DECK_Y, -34.3))
var routes := {}
var route_rally := {}
var defend_points: Array[Vector3] = []
## Inside the Big Tower (the capture zone): where attackers go to take it.
var capture_points: Array[Vector3] = []
## Out on the island and side paths, where hunters go looking for a fight.
var hunt_points: Array[Vector3] = []
var ammo_points: Array[Vector3] = []
var teleporters: Array[Dictionary] = []
var nav_region: NavigationRegion3D
var flag: BunkerFlag
## Enclosed spaces, for sound: the Big Tower's stairwell, the Command Center
## and the two roofed side paths.
var indoor_boxes: Array[AABB] = [
	AABB(Vector3(-6.4, -1.0, -50.4), Vector3(12.8, 13.0, 12.8)),
	AABB(Vector3(14.0, 0.0, -3.0), Vector3(9.0, 4.2, 12.0)),
	AABB(Vector3(-32.7, -3.5, -28.5), Vector3(4.4, 3.7, 16.0)),
	AABB(Vector3(28.3, -3.5, -28.5), Vector3(4.4, 3.7, 16.0)),
]
## The enclosed rooms among them (the tower and the Command Center; the
## covered paths are open along one side): High graphics hangs faint lamps here.
var rooms: Array[AABB] = [indoor_boxes[0], indoor_boxes[1]]

var _b: LevelBuilder
var _spinner: AnimatableBody3D


func build() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Navigation"
	add_child(nav_region)
	var body := StaticBody3D.new()
	body.name = "WorldCollision"
	body.collision_layer = GameConfig.LAYER_WORLD
	body.collision_mask = 0
	nav_region.add_child(body)
	var geo := Node3D.new()
	geo.name = "Geometry"
	add_child(geo)
	_b = LevelBuilder.new(geo, body)

	_build_main_island()
	_build_dish_spinner()
	_build_command_center()
	_build_tower_platform()
	_build_big_tower()
	_build_side_paths()
	_build_sniper_roost()
	_build_landing_pad()
	_build_leap_of_faith()
	_build_cover()
	_build_backdrop()
	_define_gameplay_points()
	_bake_navigation()


func _physics_process(delta: float) -> void:
	if _spinner:
		_spinner.rotate_y(SPIN_SPEED * delta)


## Flies the colours of whoever holds the bunker over the Big Tower (-1 = nobody).
func set_flag_team(team: int, instant := false) -> void:
	if flag:
		flag.set_team(team, instant)


# --- Main island -----------------------------------------------------------------

func _build_main_island() -> void:
	var segs := 96
	var outline := PackedVector2Array()
	var dirs: Array[Vector2] = []
	for i in segs:
		var a := TAU * float(i) / float(segs)
		var d := Vector2(cos(a), sin(a))
		dirs.append(d)
		outline.append(d * _ray_polygon(d, ISLAND))
	var dish := MeshKit.new()
	var ground := MeshKit.new()
	var rings := [0.0, 2.5, 5.0, 7.5, 9.5, 11.3, DISH_R]
	for i in segs:
		var j := (i + 1) % segs
		var d0 := dirs[i]
		var d1 := dirs[j]
		for k in rings.size() - 1:
			var ra: float = rings[k]
			var rb: float = rings[k + 1]
			var a0 := _dish_point(d0, ra)
			var a1 := _dish_point(d1, ra)
			var b0 := _dish_point(d0, rb)
			var b1 := _dish_point(d1, rb)
			if k == 0:
				dish.tri(a0, b0, b1, Vector3.UP)
			else:
				dish.quad(a0, b0, b1, a1, Vector3.UP)
		var o0 := outline[i]
		var o1 := outline[j]
		var r0 := d0 * DISH_R
		var r1 := d1 * DISH_R
		var m0 := (r0 + o0) * 0.5
		var m1 := (r1 + o1) * 0.5
		ground.quad(_v(r0), _v(m0), _v(m1), _v(r1), Vector3.UP)
		ground.quad(_v(m0), _v(o0), _v(o1), _v(m1), Vector3.UP)
	_b.add_static_mesh(dish.commit(), "dish")
	_b.add_static_mesh(ground.commit(), "ground")
	_b.cliff_skirt(outline, 0.0, 95.0, 11)

	# Glowing rim ring and radial ribs on the dish.
	var torus := TorusMesh.new()
	torus.inner_radius = DISH_R - 0.25
	torus.outer_radius = DISH_R + 0.1
	torus.rings = 64
	_b.add_mesh(torus, "glow", Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.25, 1)), Vector3(0, 0.02, 0)), false)
	for k in 8:
		var a := TAU * k / 8.0 + 0.2
		var d := Vector2(cos(a), sin(a))
		var p0 := _dish_point(d, 3.0) + Vector3(0, 0.03, 0)
		var p1 := _dish_point(d, 12.6) + Vector3(0, 0.03, 0)
		_b.ramp(p0, p1, 0.18, "trim", 0.05, false)


func _build_dish_spinner() -> void:
	_b.cylinder(Vector3(0, -3.4, 0), 1.3, 11.8, "metal_dark", true, 1.0, 12)
	_b.cylinder(Vector3(0, 8.4, 0), 2.0, 0.6, "metal", true, 1.5, 12)
	_b.cylinder(Vector3(0, 9.0, 0), 0.35, 4.0, "metal", true, 0.12, 8)
	_b.cylinder(Vector3(0, 13.0, 0), 0.3, 0.5, "glow", false, 0.3, 8)

	_spinner = AnimatableBody3D.new()
	_spinner.name = "DishSpinner"
	_spinner.collision_layer = GameConfig.LAYER_MOVING
	_spinner.collision_mask = 0
	_spinner.sync_to_physics = true
	add_child(_spinner)
	var arm := BoxMesh.new()
	arm.size = Vector3(24.0, 4.6, 0.5)
	var arm_xf := Transform3D(Basis.IDENTITY, Vector3(0, 4.3, 0))
	var mi := MeshInstance3D.new()
	mi.mesh = arm
	mi.material_override = LevelBuilder.mat("metal_dark")
	mi.transform = arm_xf
	_spinner.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = arm.size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = arm_xf
	_spinner.add_child(cs)
	for y in [2.05, 6.55]:
		var strip := BoxMesh.new()
		strip.size = Vector3(23.6, 0.12, 0.56)
		var smi := MeshInstance3D.new()
		smi.mesh = strip
		smi.material_override = LevelBuilder.mat("glow")
		smi.position = Vector3(0, y, 0)
		smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_spinner.add_child(smi)
	for x in [-11.6, 11.6]:
		var cap := BoxMesh.new()
		cap.size = Vector3(0.8, 5.4, 0.9)
		var cmi := MeshInstance3D.new()
		cmi.mesh = cap
		cmi.material_override = LevelBuilder.mat("metal")
		cmi.position = Vector3(x, 4.3, 0)
		_spinner.add_child(cmi)


# --- Command Center (east) ---------------------------------------------------------

func _build_command_center() -> void:
	var b := _b
	var h := 4.2
	# West wall with door
	b.block(Vector3(14, 0, -3), Vector3(14.5, h, 1.5), "metal")
	b.block(Vector3(14, 3.0, 1.5), Vector3(14.5, h, 4.5), "metal")
	b.block(Vector3(14, 0, 4.5), Vector3(14.5, h, 9), "metal")
	# East wall with door
	b.block(Vector3(22.5, 0, -3), Vector3(23, h, 1.5), "metal")
	b.block(Vector3(22.5, 3.0, 1.5), Vector3(23, h, 4.5), "metal")
	b.block(Vector3(22.5, 0, 4.5), Vector3(23, h, 9), "metal")
	# North wall with door toward the tower
	b.block(Vector3(14.5, 0, -3), Vector3(17, h, -2.5), "metal")
	b.block(Vector3(17, 3.0, -3), Vector3(20, h, -2.5), "metal")
	b.block(Vector3(20, 0, -3), Vector3(22.5, h, -2.5), "metal")
	# South wall with a firing slot
	b.block(Vector3(14.5, 0, 8.5), Vector3(16, h, 9), "metal")
	b.block(Vector3(16, 0, 8.5), Vector3(21, 1.4, 9), "metal")
	b.block(Vector3(16, 2.6, 8.5), Vector3(21, h, 9), "metal")
	b.block(Vector3(21, 0, 8.5), Vector3(22.5, h, 9), "metal")
	# Roof, ramp up the south side, landing
	b.block(Vector3(13.5, h, -3.5), Vector3(23.5, 4.6, 9.0), "metal_dark")
	b.ramp(Vector3(14.0, 0, 10.7), Vector3(22.0, 4.6, 10.7), 3.0, "paving")
	b.block(Vector3(22.0, 4.2, 8.8), Vector3(23.5, 4.6, 12.2), "metal_dark")
	# Roof parapets
	b.block(Vector3(13.5, 4.6, -3.5), Vector3(13.8, 5.4, 9.0), "metal")
	b.block(Vector3(13.5, 4.6, -3.5), Vector3(23.5, 5.4, -3.2), "metal")
	b.block(Vector3(23.2, 4.6, -3.5), Vector3(23.5, 5.4, 12.2), "metal")
	b.block(Vector3(13.8, 4.6, 8.7), Vector3(22.0, 5.4, 9.0), "metal")
	b.block(Vector3(22.0, 4.6, 11.9), Vector3(23.2, 5.4, 12.2), "metal")
	# Interior: consoles and glowing screens
	b.block(Vector3(15, 0, -2.4), Vector3(18, 1.1, -1.6), "metal_dark")
	b.block(Vector3(15.2, 1.6, -2.48), Vector3(17.8, 2.6, -2.44), "glow", false)
	b.block(Vector3(20.5, 0, 6.0), Vector3(22.4, 1.1, 8.4), "metal_dark")
	b.block(Vector3(22.44, 1.5, 6.2), Vector3(22.48, 2.5, 8.2), "glow", false)
	b.crate(Vector3(16.0, 0, 6.8), 1.1, 0.3)
	# Relay mast on the roof
	b.cylinder(Vector3(15.0, 4.6, -2.0), 0.18, 7.0, "metal", true, 0.08, 8)
	b.cylinder(Vector3(15.0, 11.6, -2.0), 0.22, 0.4, "glow_warm", false, 0.22, 8)


# --- Big Tower platform, bridge and tower ------------------------------------------

func _build_tower_platform() -> void:
	var outline := PackedVector2Array()
	for p in TOWER_PLATFORM:
		outline.append(p)
	_b.flat_top(outline, 0.0, "paving")
	_b.cliff_skirt(outline, 0.0, 80.0, 23)
	# Centre bridge (the turret's lane) with low curbs.
	_b.walkway([Vector3(0, -0.01, -19.6), Vector3(0, -0.01, -31.8)], 5.0, "paving", 0.8)
	_b.block(Vector3(-2.5, -0.2, -31.5), Vector3(-2.2, 0.55, -20.6), "metal")
	_b.block(Vector3(2.2, -0.2, -31.5), Vector3(2.5, 0.55, -20.6), "metal")


func _build_big_tower() -> void:
	var b := _b
	var top := DECK_Y - 0.6  # underside of the deck slab
	# Outer footprint x -7..7, z -51..-37; walls 0.6 thick.
	# South face: door + the large opening above it.
	b.block(Vector3(-7, 0, -37.6), Vector3(-4, top, -37), "metal")
	b.block(Vector3(4, 0, -37.6), Vector3(7, top, -37), "metal")
	b.block(Vector3(-4, 0, -37.6), Vector3(-1.5, 5.5, -37), "metal")
	b.block(Vector3(1.5, 0, -37.6), Vector3(4, 5.5, -37), "metal")
	b.block(Vector3(-1.5, 3.2, -37.6), Vector3(1.5, 5.5, -37), "metal")
	b.block(Vector3(-4, 9.0, -37.6), Vector3(4, top, -37), "metal")
	# West face: door at the NW corner, window over the first ramp.
	b.block(Vector3(-7, 0, -51), Vector3(-6.4, top, -50.2), "metal")
	b.block(Vector3(-7, 2.8, -50.2), Vector3(-6.4, top, -47.8), "metal")
	b.block(Vector3(-7, 0, -47.8), Vector3(-6.4, top, -46), "metal")
	b.block(Vector3(-7, 0, -46), Vector3(-6.4, 2.0, -42), "metal")
	b.block(Vector3(-7, 4.8, -46), Vector3(-6.4, top, -42), "metal")
	b.block(Vector3(-7, 0, -42), Vector3(-6.4, top, -37.6), "metal")
	# East face: door at the SE corner, window over the third ramp.
	b.block(Vector3(6.4, 0, -51), Vector3(7, top, -46), "metal")
	b.block(Vector3(6.4, 0, -46), Vector3(7, 9.0, -42), "metal")
	b.block(Vector3(6.4, 11.6, -46), Vector3(7, top, -42), "metal")
	b.block(Vector3(6.4, 0, -42), Vector3(7, top, -40.4), "metal")
	b.block(Vector3(6.4, 3.2, -40.4), Vector3(7, top, -37.8), "metal")
	b.block(Vector3(6.4, 0, -37.8), Vector3(7, top, -37.6), "metal")
	# North face: window over the second ramp.
	b.block(Vector3(-6.4, 0, -51), Vector3(-2, top, -50.4), "metal")
	b.block(Vector3(2, 0, -51), Vector3(6.4, top, -50.4), "metal")
	b.block(Vector3(-2, 0, -51), Vector3(2, 5.0, -50.4), "metal")
	b.block(Vector3(-2, 7.6, -51), Vector3(2, top, -50.4), "metal")

	# Square spiral inside: four ramps of 3.5 m around the walls.
	b.ramp(Vector3(-4.9, 0.0, -40.6), Vector3(-4.9, 3.5, -47.4), 3.0, "metal_dark")
	b.block(Vector3(-6.4, 3.1, -50.4), Vector3(-3.4, 3.5, -47.4), "metal_dark")
	b.ramp(Vector3(-3.4, 3.5, -48.9), Vector3(3.4, 7.0, -48.9), 3.0, "metal_dark")
	b.block(Vector3(3.4, 6.6, -50.4), Vector3(6.4, 7.0, -47.4), "metal_dark")
	b.ramp(Vector3(4.9, 7.0, -47.4), Vector3(4.9, 10.5, -40.6), 3.0, "metal_dark")
	b.block(Vector3(3.4, 10.1, -40.6), Vector3(6.4, 10.5, -37.6), "metal_dark")
	b.ramp(Vector3(3.4, 10.5, -39.1), Vector3(-3.4, DECK_Y, -39.1), 3.0, "metal_dark")
	# Inner guard rails along the atrium edge, kept clear of the corners.
	var k := 3.5 / 6.8
	b.ramp(Vector3(-3.45, 0.9 + 1.6 * k, -42.2), Vector3(-3.45, 4.4 - 1.0 * k, -46.4), 0.1, "trim", 0.9)
	b.ramp(Vector3(-1.8, 4.4 + 1.6 * k, -47.35), Vector3(2.4, 7.9 - 1.0 * k, -47.35), 0.1, "trim", 0.9)
	b.ramp(Vector3(3.45, 7.9 + 1.6 * k, -45.8), Vector3(3.45, 11.4 - 1.0 * k, -41.6), 0.1, "trim", 0.9)

	# Deck at DECK_Y with the stair hole right behind the gun position.
	b.block(Vector3(-8, top, -52), Vector3(8, DECK_Y, -40.6), "metal_dark")
	b.block(Vector3(-8, top, -40.6), Vector3(-3.4, DECK_Y, -37.6), "metal_dark")
	b.block(Vector3(2.6, top, -40.6), Vector3(8, DECK_Y, -37.6), "metal_dark")
	b.block(Vector3(-8, top, -37.6), Vector3(8, DECK_Y, -34), "metal_dark")
	# Parapets, open at the front for the gun.
	var p_top := DECK_Y + 0.95
	b.block(Vector3(-8, DECK_Y, -52), Vector3(8, p_top, -51.6), "metal")
	b.block(Vector3(-8, DECK_Y, -51.6), Vector3(-7.6, p_top, -34), "metal")
	b.block(Vector3(7.6, DECK_Y, -51.6), Vector3(8, p_top, -34), "metal")
	b.block(Vector3(-7.6, DECK_Y, -34.4), Vector3(-2.2, p_top, -34), "metal")
	b.block(Vector3(2.2, DECK_Y, -34.4), Vector3(7.6, p_top, -34), "metal")
	b.block(Vector3(-8.05, p_top, -52.05), Vector3(8.05, p_top + 0.08, -51.55), "glow", false)

	# Corner buttresses and glow strips: the Ascension relay look.
	for c in [Vector2(-7, -51), Vector2(7, -51), Vector2(-7, -37), Vector2(7, -37)]:
		b.block(Vector3(c.x - 0.6, 0, c.y - 0.6), Vector3(c.x + 0.6, DECK_Y + 0.4, c.y + 0.6), "metal")
		var gx := 0.62 * signf(c.x)
		var gz := 0.62 * signf(c.y + 44.0)
		b.block(Vector3(c.x + gx - 0.05, 1.0, c.y + gz - 0.05), Vector3(c.x + gx + 0.05, DECK_Y - 1.0, c.y + gz + 0.05), "glow", false)
	for lamp in [Vector3(0, 5.5, -44), Vector3(0, 11.5, -44)]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.8, 0.55)
		l.light_energy = 1.6
		l.omni_range = 9.0
		l.position = lamp
		add_child(l)
	# Mast at the back of the deck.
	b.cylinder(Vector3(-6.6, DECK_Y, -50.6), 0.2, 11.0, "metal", true, 0.08, 8)
	b.cylinder(Vector3(-6.6, DECK_Y + 11.0, -50.6), 0.25, 0.5, "glow", false, 0.25, 8)
	# The holder's flag flies high above the deck, out of everyone's way.
	flag = BunkerFlag.new()
	flag.position = Vector3(0, DECK_Y, -51.6)
	add_child(flag)


# --- Side paths -----------------------------------------------------------------------

func _build_side_paths() -> void:
	var b := _b
	var west := [Vector3(-27.4, -0.01, -3.0), Vector3(-30.5, -3, -12), Vector3(-30.5, -3, -29), Vector3(-25, -1.5, -36), Vector3(-17.4, -0.01, -41)]
	var east := [Vector3(27.6, -0.01, -3.5), Vector3(30.5, -3, -12), Vector3(30.5, -3, -29), Vector3(25, -1.5, -36), Vector3(17.4, -0.01, -41)]
	b.walkway(west, 4.0, "paving")
	b.walkway(east, 4.0, "paving")
	for side in [-1.0, 1.0]:
		var s: float = side
		# Roof over the ledge and outer posts + rail.
		b.block(Vector3(32.7 * s, 0.2, -28.5), Vector3(28.3 * s, 0.6, -12.5), "metal_dark")
		for z in [-12.7, -16.6, -20.5, -24.4, -28.3]:
			b.block(Vector3(32.6 * s, -3.0, z - 0.2), Vector3(32.2 * s, 0.2, z + 0.2), "metal")
		b.block(Vector3(32.6 * s, -3.0, -28.5), Vector3(32.3 * s, -2.1, -12.5), "metal")
		b.block(Vector3(32.7 * s, 0.6, -28.5), Vector3(32.5 * s, 0.7, -12.5), "glow", false)
	# West inner wall is solid: the safe route.
	b.block(Vector3(-28.9, -3.0, -28.5), Vector3(-28.5, 0.2, -12.5), "metal")
	# East inner wall has two windows the gun can see through.
	b.block(Vector3(28.5, -3.0, -15.5), Vector3(28.9, 0.2, -12.5), "metal")
	b.block(Vector3(28.5, -3.0, -17.5), Vector3(28.9, -1.9, -15.5), "metal")
	b.block(Vector3(28.5, -0.5, -17.5), Vector3(28.9, 0.2, -15.5), "metal")
	b.block(Vector3(28.5, -3.0, -22.5), Vector3(28.9, 0.2, -17.5), "metal")
	b.block(Vector3(28.5, -3.0, -24.5), Vector3(28.9, -1.9, -22.5), "metal")
	b.block(Vector3(28.5, -0.5, -24.5), Vector3(28.9, 0.2, -22.5), "metal")
	b.block(Vector3(28.5, -3.0, -28.5), Vector3(28.9, 0.2, -24.5), "metal")
	# A boulder on each exposed ramp down, the last cover before the run.
	b.rock(Vector3(-31.2, -2.2, -9.5), 0.9, 1.9, 71)
	b.rock(Vector3(31.0, -2.2, -9.0), 0.9, 1.7, 72)


# --- Sniper Roost (south-west) ----------------------------------------------------------

func _build_sniper_roost() -> void:
	var b := _b
	var outline := _ngon(Vector2(-36, 27), 9.0, 8, deg_to_rad(22.5))
	b.flat_top(outline, 0.0, "paving")
	b.cliff_skirt(outline, 0.0, 70.0, 31)
	b.walkway([Vector3(-21.0, -0.01, 17.2), Vector3(-29.0, -0.01, 22.6)], 4.0, "paving")
	# Little tower core, roof and two-flight ramp.
	b.block(Vector3(-42, 0, 24), Vector3(-36, 6.6, 30), "metal")
	b.block(Vector3(-42, 6.6, 20.0), Vector3(-35.5, 7.0, 30.5), "metal_dark")
	b.block(Vector3(-41.8, 0, 20.2), Vector3(-41.3, 6.6, 20.7), "metal")
	b.block(Vector3(-36.2, 0, 20.2), Vector3(-35.7, 6.6, 20.7), "metal")
	b.ramp(Vector3(-33.0, 0.0, 31.5), Vector3(-41.0, 3.5, 31.5), 3.0, "metal_dark")
	b.block(Vector3(-45, 3.1, 30), Vector3(-41, 3.5, 33), "metal_dark")
	b.ramp(Vector3(-43.5, 3.5, 30.0), Vector3(-43.5, 7.0, 23.0), 3.0, "metal_dark")
	b.block(Vector3(-45, 6.6, 20.0), Vector3(-42, 7.0, 23.0), "metal_dark")
	# Parapets and rails.
	b.block(Vector3(-35.9, 7.0, 20.0), Vector3(-35.5, 8.0, 30.5), "metal")
	b.block(Vector3(-42, 7.0, 30.1), Vector3(-35.5, 8.0, 30.5), "metal")
	b.block(Vector3(-42, 7.0, 20.0), Vector3(-35.5, 8.0, 20.4), "metal")
	b.block(Vector3(-42, 7.0, 23.0), Vector3(-41.6, 8.0, 30.1), "metal")
	b.block(Vector3(-45, 7.0, 20.0), Vector3(-44.7, 7.9, 23.0), "metal")
	b.block(Vector3(-45, 7.0, 20.0), Vector3(-42, 7.9, 20.3), "metal")
	b.block(Vector3(-45, 3.5, 32.7), Vector3(-41, 4.4, 33), "metal")
	# The "fork prongs".
	b.cylinder(Vector3(-41.2, 7.0, 29.7), 0.32, 6.5, "metal", true, 0.04, 6)
	b.cylinder(Vector3(-36.3, 7.0, 29.7), 0.32, 6.5, "metal", true, 0.04, 6)
	b.block(Vector3(-41.95, 1.0, 29.95), Vector3(-41.85, 6.0, 30.05), "glow", false)


# --- Landing Pad (south-east) + Leap of Faith -------------------------------------------

func _build_landing_pad() -> void:
	var b := _b
	var outline := _ngon(Vector2(37, 29), 8.5, 24)
	b.flat_top(outline, 0.0, "paving")
	b.cliff_skirt(outline, 0.0, 70.0, 41)
	var ring := TorusMesh.new()
	ring.inner_radius = 5.0
	ring.outer_radius = 5.6
	ring.rings = 48
	b.add_mesh(ring, "pad_mark", Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.04, 1)), Vector3(37, 0.01, 29)), false)
	# Covered walkway from the island to the pad ("bridge coverings").
	var a := Vector3(23.66, -0.01, 15.24)
	var e := Vector3(31.5, -0.01, 23.2)
	b.walkway([a, e], 4.5, "paving")
	var d := (e - a).normalized()
	var s := Vector3(-d.z, 0, d.x)
	var basis := Basis(Vector3.UP, atan2(d.x, d.z))
	var mid := a + d * 5.9
	b.box(mid + Vector3(0, 3.4, 0), Vector3(5.2, 0.4, 7.4), "metal_dark", basis)
	for side in [-1.0, 1.0]:
		var o: Vector3 = s * 2.35 * float(side)
		b.box(mid + o + Vector3(0, 0.55, 0), Vector3(0.3, 1.1, 7.4), "metal", basis)
		for t in [-3.5, 3.5]:
			b.box(mid + o + d * float(t) + Vector3(0, 1.6, 0), Vector3(0.35, 3.2, 0.35), "metal", basis)
	# Cover on the pad.
	b.crate(Vector3(35.5, 0, 25.5), 1.3, 0.2)
	b.crate(Vector3(36.6, 0, 26.4), 1.0, 0.9)
	b.crate(Vector3(40.0, 0, 31.5), 1.3, 0.5)
	b.sandbags(Vector3(31.5, 0, 32.0), Vector3(34.5, 0, 34.5))
	b.cylinder(Vector3(44.5, 0, 29), 0.15, 6.0, "metal", true, 0.06, 8)
	b.cylinder(Vector3(44.5, 6.0, 29), 0.25, 0.4, "glow_warm", false, 0.25, 8)


func _build_leap_of_faith() -> void:
	var outline := _ngon(Vector2(22, 33), 4.5, 8, deg_to_rad(22.5))
	_b.flat_top(outline, -7.5, "metal")
	_b.cliff_skirt(outline, -7.5, 40.0, 51)
	var pad := TorusMesh.new()
	pad.inner_radius = 0.8
	pad.outer_radius = 1.1
	_b.add_mesh(pad, "glow", Transform3D(Basis.IDENTITY.scaled(Vector3(1, 0.3, 1)), Vector3(22.6, -7.45, 34.0)), false)


# --- Cover on the island and tower platform ------------------------------------------------

func _build_cover() -> void:
	var b := _b
	b.rock(Vector3(-23.0, 0, 5.5), 1.6, 3.0, 1)
	b.rock(Vector3(-24.0, 0, -6.0), 1.4, 2.6, 2)
	b.rock(Vector3(-15.5, 0, 15.5), 1.3, 2.2, 3)
	b.rock(Vector3(22.8, 0, -8.5), 1.5, 2.8, 4)
	b.rock(Vector3(9.5, 0, 17.0), 1.2, 2.0, 5)
	b.rock(Vector3(-18.5, 0, -13.0), 1.2, 2.4, 6)
	b.sandbags(Vector3(-9.0, 0, -17.0), Vector3(-5.0, 0, -17.5))
	b.sandbags(Vector3(5.0, 0, -17.5), Vector3(9.0, 0, -17.0))
	b.sandbags(Vector3(-2.5, 0, 15.8), Vector3(2.5, 0, 15.8))
	b.sandbags(Vector3(-20.0, 0, -2.5), Vector3(-19.2, 0, 1.5))
	b.crate(Vector3(11.5, 0, -6.0), 1.2, 0.2)
	b.crate(Vector3(12.4, 0, -4.4), 1.0, 0.7)
	b.crate(Vector3(-11.0, 0, 18.5), 1.2, 0.4)
	# Tower platform emplacements.
	b.sandbags(Vector3(-13.5, 0, -34.5), Vector3(-9.5, 0, -33.5))
	b.sandbags(Vector3(9.5, 0, -33.5), Vector3(13.5, 0, -34.5))
	b.crate(Vector3(-10.0, 0, -46.0), 1.2, 0.1)
	b.crate(Vector3(10.0, 0, -44.0), 1.2, 0.6)
	b.crate(Vector3(-4.0, 0, -56.5), 1.2, 0.3)
	# Relay antennas.
	for p in [Vector3(-14, 0, -57), Vector3(-22, 0, 9), Vector3(20, 0, 17)]:
		b.cylinder(p, 0.35, 14.0, "metal", true, 0.12, 8)
		b.box(p + Vector3(0, 10, 0), Vector3(3.0, 0.15, 0.15), "metal", Basis.IDENTITY, false)
		b.box(p + Vector3(0, 12, 0), Vector3(2.0, 0.15, 0.15), "metal", Basis.IDENTITY, false)
		b.cylinder(p + Vector3(0, 14, 0), 0.3, 0.4, "glow_warm", false, 0.3, 8)


# --- Backdrop: cloud deck and distant peaks (no collision) ---------------------------------

func _build_backdrop() -> void:
	var clouds := StandardMaterial3D.new()
	var n := FastNoiseLite.new()
	n.frequency = 0.012
	n.fractal_octaves = 5
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 1))
	g.add_point(0.45, Color(1, 1, 1, 0.0))
	var tex := NoiseTexture2D.new()
	tex.width = 1024
	tex.height = 1024
	tex.seamless = true
	tex.noise = n
	tex.color_ramp = g
	clouds.albedo_texture = tex
	clouds.albedo_color = Color(0.97, 0.98, 1.0)
	clouds.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	clouds.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	clouds.cull_mode = BaseMaterial3D.CULL_DISABLED
	clouds.uv1_scale = Vector3(6, 6, 6)
	for layer in [[-70.0, 2600.0, 0.0], [-110.0, 3600.0, 0.37]]:
		var pm := PlaneMesh.new()
		pm.size = Vector2(layer[1], layer[1])
		var mi := MeshInstance3D.new()
		mi.mesh = pm
		var m := clouds.duplicate() as StandardMaterial3D
		m.uv1_offset = Vector3(layer[2], layer[2], 0)
		mi.material_override = m
		mi.position = Vector3(0, layer[0], 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 18:
		var a := TAU * i / 18.0 + rng.randf_range(-0.12, 0.12)
		var dist := rng.randf_range(650.0, 1400.0)
		var h := rng.randf_range(260.0, 520.0)
		var r := h * rng.randf_range(0.4, 0.6)
		var base := Vector3(cos(a) * dist, -300.0, sin(a) * dist)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = r
		cm.height = h
		cm.radial_segments = 7
		cm.rings = 1
		var mi := MeshInstance3D.new()
		mi.mesh = cm
		mi.material_override = LevelBuilder.mat("rock_far")
		mi.position = base + Vector3(0, h * 0.5, 0)
		mi.rotation.y = rng.randf() * TAU
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var cap := CylinderMesh.new()
		cap.top_radius = 0.0
		cap.bottom_radius = r * 0.3
		cap.height = h * 0.3
		cap.radial_segments = 7
		cap.rings = 1
		var ci := MeshInstance3D.new()
		ci.mesh = cap
		ci.material_override = LevelBuilder.mat("snow")
		ci.position = base + Vector3(0, h * 0.85 + 0.5, 0)
		ci.rotation.y = mi.rotation.y
		ci.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ci)


# --- Gameplay points ------------------------------------------------------------------------

func _define_gameplay_points() -> void:
	var bunker: Array = spawn_points["bunker"]
	var far: Array = spawn_points["far"]
	# Behind and beside the Big Tower, outside it: the holders have to come
	# back into the tower to defend it and climb to re-man the gun.
	for p in [Vector3(-10.5, 0, -54), Vector3(-7, 0, -54), Vector3(-3.5, 0, -54), Vector3(0, 0, -54),
			Vector3(3.5, 0, -54), Vector3(7, 0, -54), Vector3(10.5, 0, -54), Vector3(-8, 0, -57.5),
			Vector3(0, 0, -58), Vector3(6, 0, -57.5), Vector3(-12, 0, -50), Vector3(-13, 0, -42),
			Vector3(12, 0, -50), Vector3(13.5, 0, -40), Vector3(-15.5, 0, -47), Vector3(15.5, 0, -46.5)]:
		bunker.append(_xf(p, PI))
	# South edge of the island, the Sniper Roost platform and the Landing Pad.
	for p in [Vector3(-7, 0, 19), Vector3(2.5, 0, 18.5), Vector3(6, 0, 19.5), Vector3(-10, 0, 16),
			Vector3(12.5, 0, 15), Vector3(-13, 0, 13), Vector3(-18, 0, 18.5), Vector3(16.5, 0, 16),
			Vector3(-31, 0, 21.5), Vector3(-31, 0, 26), Vector3(-29, 0, 29.5), Vector3(-34.5, 0, 22),
			Vector3(34, 0, 28), Vector3(38, 0, 33.5), Vector3(41.5, 0, 27), Vector3(37, 0, 22.5)]:
		far.append(_xf(p, 0.0))
	# Neutral start: Sniper Roost + west island for Whites, Landing Pad +
	# Command Center + east island for Reds, everyone facing the tower.
	for p in [Vector3(-31, 0, 21.5), Vector3(-31, 0, 26), Vector3(-29, 0, 29.5), Vector3(-34.5, 0, 22),
			Vector3(-30, 0, 23.5), Vector3(-18, 0, 18.5), Vector3(-13, 0, 13), Vector3(-10, 0, 16),
			Vector3(-7, 0, 19), Vector3(-21, 0, 13), Vector3(-25, 0, 1), Vector3(-25.5, 0, -2.5),
			Vector3(-17, 0, 3), Vector3(-15, 0, 9), Vector3(-12.5, 0, 20.5), Vector3(-23, 0, 14)]:
		spawn_points["west"].append(_xf_facing(p, TOWER_CENTER))
	for p in [Vector3(34, 0, 28), Vector3(38, 0, 33.5), Vector3(41.5, 0, 27), Vector3(37, 0, 22.5),
			Vector3(40, 0, 24.5), Vector3(18, 0, 18.5), Vector3(12, 0, 14), Vector3(12, 0, 19),
			Vector3(6, 0, 19.5), Vector3(19.5, 0, 14.5), Vector3(25, 0, 1), Vector3(25.5, 0, -2.5),
			Vector3(17, 0, 3), Vector3(20, 0, 3.5), Vector3(12.5, 0, 20.5), Vector3(23, 0, 14)]:
		spawn_points["east"].append(_xf_facing(p, TOWER_CENTER))
	routes = {
		"west": [Vector3(-26.0, 0, -2.0), Vector3(-30.5, -3, -13), Vector3(-30.5, -3, -28), Vector3(-18, 0, -41), Vector3(-8.2, 0, -49.0)],
		"east": [Vector3(26.0, 0, -2.5), Vector3(30.5, -3, -13), Vector3(30.5, -3, -28), Vector3(18, 0, -41), Vector3(8.2, 0, -39.1)],
		"center": [Vector3(-7, 0, -15.5), Vector3(0, 0, -21), Vector3(0, 0, -33), Vector3(0, 0, -36.2)],
	}
	# Where attackers on each route regroup before storming: the far end of
	# the covered side paths, and behind the sandbags north of the dish.
	route_rally = {"west": 2, "east": 2, "center": 0}
	# Guard posts: mostly around the tower rather than piled inside it.
	defend_points.assign([
		Vector3(-5, DECK_Y, -47), Vector3(6, DECK_Y, -36.5), Vector3(0, 0, -44),
		Vector3(-9, 0, -49), Vector3(9, 0, -39), Vector3(-12, 0, -40), Vector3(12, 0, -40),
		Vector3(-10, 0, -56), Vector3(10, 0, -56), Vector3(-4, 0, -33.5), Vector3(4, 0, -33.5),
	])
	capture_points.assign([
		Vector3(0, 0, -44), Vector3(-1.5, 0, -42), Vector3(-4.9, 3.5, -48.9), Vector3(4.9, 7.0, -48.9),
		Vector3(4.9, 10.5, -39.1), Vector3(-5, DECK_Y, -47), Vector3(5, DECK_Y, -47), Vector3(-6, DECK_Y, -36.5),
	])
	hunt_points.assign([
		Vector3(0, 0, -16), Vector3(-15, 0, -8), Vector3(15, 0, -9), Vector3(-17, 0, 6), Vector3(9, 0, 13),
		Vector3(-5, 0, 18), Vector3(18.5, 0, 3), Vector3(-30.5, -3, -20), Vector3(30.5, -3, -20), Vector3(-26, 0, 20),
	])
	ammo_points.assign([
		Vector3(0, 0, -42.5), Vector3(18.5, 0, 3.0), Vector3(-31, 0, 27), Vector3(40.5, 0, 28),
		Vector3(21.5, -7.5, 32), Vector3(-30.5, -3, -20.5), Vector3(30.5, -3, -20.5), Vector3(-38.5, 7.0, 25.0),
	])
	teleporters.append({"from": Vector3(22.6, -7.5, 34.0), "to": _xf(Vector3(-3, 0, 19.5), 0.0)})


func _bake_navigation() -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = GameConfig.LAYER_WORLD
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_height = 2.0
	nm.agent_radius = 0.75  # wider than the body: running bots overshoot corners
	nm.agent_max_climb = 0.25  # soldiers step up 0.45 m, keep the navmesh stricter
	nm.agent_max_slope = 40.0
	nm.region_min_size = 4.0
	nav_region.navigation_mesh = nm
	nav_region.bake_navigation_mesh(false)


# --- Helpers ----------------------------------------------------------------------------------

static func dish_height(r: float) -> float:
	if r >= DISH_R:
		return 0.0
	var k := r / DISH_R
	return -DISH_DEPTH * (1.0 - k * k)


func _dish_point(d: Vector2, r: float) -> Vector3:
	return Vector3(d.x * r, dish_height(r), d.y * r)


func _v(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


func _xf(p: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), p)


func _xf_facing(p: Vector3, target: Vector3) -> Transform3D:
	return _xf(p, atan2(-(target.x - p.x), -(target.z - p.z)))


func _ngon(center: Vector2, radius: float, sides: int, rot := 0.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in sides:
		var a := rot + TAU * i / float(sides)
		out.append(center + Vector2(cos(a), sin(a)) * radius)
	return out


static func _ray_polygon(dir: Vector2, poly: Array) -> float:
	var best := 1e9
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		var hit: Variant = Geometry2D.segment_intersects_segment(Vector2.ZERO, dir * 1000.0, a, b)
		if hit != null:
			best = minf(best, (hit as Vector2).length())
	return best
