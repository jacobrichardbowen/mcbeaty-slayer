class_name SoldierModel
extends Node3D
## Crude primitive soldier. Whites wear pale greatcoats and peaked caps; Reds
## wear red-dyed coats and the pointed budenovka with a red star. The upper
## body pitches with aim, legs swing with speed, and death topples the body.

var team := GameConfig.TEAM_WHITE

var _body: Node3D
var _upper: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _gun: Node3D  # the gun currently held
var _muzzle: Node3D
var _guns := {}  # kind -> [node, muzzle, rest position]
var _gun_rest := Vector3.ZERO
var _meshes: Array[MeshInstance3D] = []
var _phase := 0.0
var _kick := 0.0
var _dead := false
var _death_t := 0.0
var _death_axis := Vector3.RIGHT
var _first_person := false
var _soldier: Soldier


func _ready() -> void:
	# Drawn at the soldier's interpolated position so 60 Hz physics still
	# looks smooth on fast monitors.
	_soldier = get_parent() as Soldier
	top_level = true
	var coat := Color(0.86, 0.86, 0.82) if team == GameConfig.TEAM_WHITE else Color(0.66, 0.13, 0.1)
	var trousers := Color(0.28, 0.3, 0.33) if team == GameConfig.TEAM_WHITE else Color(0.33, 0.28, 0.22)
	var skin := Color(0.86, 0.68, 0.55)
	var boot := Color(0.08, 0.07, 0.06)
	var wood := Color(0.42, 0.27, 0.14)
	var steel := Color(0.15, 0.15, 0.16)

	_body = Node3D.new()
	add_child(_body)
	_leg_l = _limb_pivot(Vector3(-0.12, 0.92, 0))
	_leg_r = _limb_pivot(Vector3(0.12, 0.92, 0))
	for leg in [_leg_l, _leg_r]:
		_add(leg, _box(Vector3(0.17, 0.82, 0.2)), trousers, Vector3(0, -0.43, 0))
		_add(leg, _box(Vector3(0.19, 0.16, 0.3)), boot, Vector3(0, -0.84, -0.05))
	# Greatcoat skirt.
	_add(_body, _cyl(0.24, 0.34, 0.62), coat, Vector3(0, 0.86, 0))

	_upper = Node3D.new()
	_upper.position = Vector3(0, 1.15, 0)
	_body.add_child(_upper)
	_add(_upper, _box(Vector3(0.5, 0.52, 0.3)), coat, Vector3(0, 0.25, 0))
	_add(_upper, _box(Vector3(0.52, 0.07, 0.32)), Color(0.25, 0.18, 0.1), Vector3(0, 0.02, 0))
	_add(_upper, _sphere(0.13), skin, Vector3(0, 0.62, 0))
	if team == GameConfig.TEAM_WHITE:
		_add(_upper, _cyl(0.15, 0.14, 0.09), Color(0.95, 0.95, 0.93), Vector3(0, 0.74, 0))
		_add(_upper, _cyl(0.142, 0.142, 0.04), Color(0.12, 0.12, 0.15), Vector3(0, 0.69, 0))
		_add(_upper, _box(Vector3(0.2, 0.02, 0.1)), Color(0.05, 0.05, 0.05), Vector3(0, 0.69, -0.16))
	else:
		_add(_upper, _cyl(0.0, 0.16, 0.3), Color(0.42, 0.42, 0.34), Vector3(0, 0.82, 0))
		_add(_upper, _box(Vector3(0.09, 0.09, 0.02)), Color(0.95, 0.1, 0.08), Vector3(0, 0.74, -0.14), Vector3(0, 0, PI / 4))
	# Arms reach forward to a shotgun held at the hip.
	var shotgun := Node3D.new()
	shotgun.position = Vector3(0.12, 0.3, -0.32)
	_upper.add_child(shotgun)
	_add(shotgun, _box(Vector3(0.07, 0.09, 0.32)), steel, Vector3(0, 0, 0))
	_add(shotgun, _cyl(0.025, 0.025, 0.55), steel, Vector3(0, 0.02, -0.42), Vector3(PI / 2, 0, 0))
	_add(shotgun, _box(Vector3(0.06, 0.06, 0.16)), wood, Vector3(0, -0.035, -0.32))
	_add(shotgun, _box(Vector3(0.055, 0.1, 0.28)), wood, Vector3(0, -0.04, 0.28))
	_guns["shotgun"] = [shotgun, _marker(shotgun, Vector3(0, 0.02, -0.72)), shotgun.position]
	# Mosin: long wooden stock, thin barrel, bolt handle.
	var rifle := Node3D.new()
	rifle.position = Vector3(0.12, 0.31, -0.3)
	_upper.add_child(rifle)
	_add(rifle, _box(Vector3(0.055, 0.08, 1.0)), wood, Vector3(0, -0.02, -0.05))
	_add(rifle, _cyl(0.016, 0.016, 0.42), steel, Vector3(0, 0.02, -0.72), Vector3(PI / 2, 0, 0))
	_add(rifle, _box(Vector3(0.05, 0.05, 0.2)), steel, Vector3(0, 0.03, 0.08))
	_add(rifle, _cyl(0.012, 0.012, 0.09), steel, Vector3(0.05, 0.03, 0.14), Vector3(0, 0, PI / 2))
	_guns["rifle"] = [rifle, _marker(rifle, Vector3(0, 0.02, -0.95)), rifle.position]
	set_weapon("shotgun")
	_arm(Vector3(0.27, 0.42, 0.0), Vector3(0.14, 0.27, -0.16), coat)
	_arm(Vector3(-0.27, 0.42, 0.0), Vector3(0.1, 0.28, -0.62), coat)


func _marker(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func set_weapon(kind: String) -> void:
	for k in _guns:
		(_guns[k][0] as Node3D).visible = k == kind
	var g: Array = _guns.get(kind, _guns["shotgun"])
	_gun = g[0]
	_muzzle = g[1]
	_gun_rest = g[2]


func _limb_pivot(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	_body.add_child(n)
	return n


func _arm(from: Vector3, to: Vector3, color: Color) -> void:
	var mi := _add(_upper, _box(Vector3(0.12, 0.12, from.distance_to(to))), color, (from + to) * 0.5)
	mi.basis = Basis.looking_at((to - from).normalized(), Vector3.UP)


func _add(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	_meshes.append(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 10
	c.rings = 1
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


## First person hides the body but keeps its shadow.
func _process(_delta: float) -> void:
	if _soldier:
		global_position = _soldier.interpolated_position()


func set_first_person(on: bool) -> void:
	_first_person = on
	for mi in _meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func muzzle_position() -> Vector3:
	return _muzzle.global_position


func kick() -> void:
	_kick = 1.0


func play_death(dir: Vector3) -> void:
	_dead = true
	_death_t = 0.0
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length() < 0.1:
		flat = global_transform.basis.z
	# Topple away from the shot.
	_death_axis = Vector3.UP.cross(flat.normalized()).normalized()


func reset_pose() -> void:
	_dead = false
	_death_t = 0.0
	_body.transform = Transform3D.IDENTITY
	visible = true


func animate(s: Soldier, delta: float) -> void:
	if _dead:
		_death_t = minf(_death_t + delta * 2.6, 1.0)
		var t := 1.0 - pow(1.0 - _death_t, 2.0)
		var local_axis := global_transform.basis.inverse() * _death_axis
		_body.transform = Transform3D(Basis(local_axis.normalized(), t * PI * 0.5), Vector3(0, 0.15 * t, 0))
		return
	rotation.y = s.look_yaw
	_upper.rotation.x = clampf(s.look_pitch, -1.0, 1.0) * 0.8
	_kick = maxf(0.0, _kick - delta * 6.0)
	_gun.position.z = _gun_rest.z + _kick * 0.08
	var speed := s.horizontal_speed()
	var swing := 0.0
	if s.is_on_floor() and speed > 0.3 and not s.turret:
		_phase += delta * speed * 2.0
		swing = sin(_phase) * clampf(speed / GameConfig.RUN_SPEED, 0.0, 1.0) * 0.7
	elif not s.is_on_floor():
		swing = 0.35
	var crouch := s.crouched
	_body.position.y = -0.5 if crouch else 0.0
	_leg_l.rotation.x = (-1.1 if crouch else 0.0) + swing
	_leg_r.rotation.x = (-1.1 if crouch else 0.0) - swing
